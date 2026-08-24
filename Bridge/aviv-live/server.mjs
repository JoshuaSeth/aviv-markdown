import { createHash, timingSafeEqual } from "node:crypto";
import { promises as fs, realpathSync, readFileSync } from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { TextDecoder } from "node:util";

const MAX_DOCUMENT_BYTES = 16 * 1024 * 1024;
const SLUG_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*\.md$/;
const SOURCE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]*$/;
const utf8Decoder = new TextDecoder("utf-8", { fatal: true });

export function loadConfig(environment = process.env) {
  const dataRoot = required(environment, "AVIV_LIVE_DATA_ROOT");
  const manifestPath = required(environment, "AVIV_LIVE_MANIFEST");
  const tokenPath = required(environment, "AVIV_LIVE_WRITE_TOKEN_FILE");
  const publicBaseURL = validatedBaseURL(
    required(environment, "AVIV_LIVE_PUBLIC_BASE_URL"),
    "AVIV_LIVE_PUBLIC_BASE_URL",
  );
  const writeBaseURL = validatedBaseURL(
    required(environment, "AVIV_LIVE_WRITE_BASE_URL"),
    "AVIV_LIVE_WRITE_BASE_URL",
  );
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (manifest.version !== 1 || typeof manifest.sources !== "object") {
    throw new Error("AVIV_LIVE_MANIFEST must contain version 1 and a sources object");
  }

  const canonicalRoot = realpathSync(dataRoot);
  const sources = new Map();
  for (const [slug, entry] of Object.entries(manifest.sources)) {
    if (!SLUG_PATTERN.test(slug)) {
      throw new Error(`Invalid Markdown source slug: ${slug}`);
    }
    if (!entry || typeof entry.path !== "string" || !SOURCE_ID_PATTERN.test(entry.sourceId)) {
      throw new Error(`Invalid source manifest entry: ${slug}`);
    }
    const candidate = path.resolve(canonicalRoot, entry.path);
    const canonicalPath = realpathSync(candidate);
    if (!isInside(canonicalRoot, canonicalPath)) {
      throw new Error(`Source escapes AVIV_LIVE_DATA_ROOT: ${slug}`);
    }
    sources.set(slug, {
      path: canonicalPath,
      sourceId: entry.sourceId,
      writable: entry.writable === true,
    });
  }

  return {
    host: environment.AVIV_LIVE_HOST || "127.0.0.1",
    port: parsePort(environment.AVIV_LIVE_PORT || "8787"),
    publicBaseURL,
    writeBaseURL,
    tokenPath,
    sources,
  };
}

export function createAvivLiveServer(config) {
  const writeLocks = new Map();
  return http.createServer(async (request, response) => {
    try {
      await routeRequest(request, response, config, writeLocks);
    } catch (error) {
      if (error instanceof HTTPError && !response.headersSent) {
        sendError(response, error.status, error.code, error.message);
        return;
      }
      console.error("aviv-live request failed", error instanceof Error ? error.message : error);
      if (!response.headersSent) {
        sendError(response, 500, "internal_error", "The source bridge could not complete the request.");
      } else {
        response.destroy();
      }
    }
  });
}

async function routeRequest(request, response, config, writeLocks) {
  const requestURL = new URL(request.url || "/", "http://localhost");
  if (request.method === "GET" && requestURL.pathname === "/healthz") {
    sendJSON(response, 200, { status: "ok" });
    return;
  }

  const publicSlug = matchSlug(requestURL.pathname, "/aviv-live/");
  if (publicSlug !== null) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      sendMethodNotAllowed(response, "GET, HEAD");
      return;
    }
    await serveMarkdown(request, response, config, publicSlug);
    return;
  }

  const writeSlug = matchSlug(requestURL.pathname, "/api/aviv-live/");
  if (writeSlug !== null) {
    if (request.method !== "PUT") {
      sendMethodNotAllowed(response, "PUT");
      return;
    }
    await saveMarkdown(request, response, config, writeSlug, writeLocks);
    return;
  }

  sendError(response, 404, "not_found", "No Markdown source exists at this path.");
}

async function serveMarkdown(request, response, config, slug) {
  const source = config.sources.get(slug);
  if (!source) {
    sendError(response, 404, "not_found", "No Markdown source exists at this path.");
    return;
  }

  const document = await readMarkdown(source.path);
  setSourceHeaders(response, config, slug, source, document);
  if (request.headers["if-none-match"] === document.etag) {
    response.writeHead(304);
    response.end();
    return;
  }
  response.setHeader("Content-Type", "text/markdown; charset=utf-8");
  response.setHeader("Content-Length", document.bytes.length);
  response.writeHead(200);
  response.end(request.method === "HEAD" ? undefined : document.bytes);
}

async function saveMarkdown(request, response, config, slug, writeLocks) {
  const source = config.sources.get(slug);
  if (!source) {
    sendError(response, 404, "not_found", "No Markdown source exists at this path.");
    return;
  }
  if (!source.writable) {
    sendError(response, 403, "read_only", "This Markdown source is read-only.");
    return;
  }
  if (!(await isAuthorized(request, config.tokenPath))) {
    response.setHeader("WWW-Authenticate", 'Bearer realm="Aviv remote save"');
    sendError(response, 401, "unauthorized", "A valid write token is required.");
    return;
  }
  if (request.headers["x-aviv-source-id"] !== source.sourceId) {
    sendError(response, 409, "source_identity_mismatch", "The source identity does not match.");
    return;
  }
  const expectedETag = request.headers["if-match"];
  if (typeof expectedETag !== "string" || expectedETag.length === 0) {
    sendError(response, 428, "validator_required", "If-Match is required for safe writes.");
    return;
  }

  const incoming = await readRequestBody(request);
  validateUTF8(incoming);

  const saved = await withSourceWriteLock(writeLocks, source.path, async () => {
    const beforeCommit = await readMarkdown(source.path);
    if (expectedETag !== beforeCommit.etag) {
      throw new HTTPError(
        412,
        "write_conflict",
        "The Markdown source changed before this save.",
      );
    }
    await atomicWrite(source.path, incoming);
    const committed = await readMarkdown(source.path);
    if (!committed.bytes.equals(incoming)) {
      throw new HTTPError(
        412,
        "write_conflict",
        "The Markdown source changed while this save completed.",
      );
    }
    return committed;
  });
  setSourceHeaders(response, config, slug, source, saved);
  response.writeHead(204);
  response.end();
}

async function withSourceWriteLock(writeLocks, sourcePath, operation) {
  const previous = writeLocks.get(sourcePath) || Promise.resolve();
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const tail = previous.then(() => gate);
  writeLocks.set(sourcePath, tail);
  await previous;
  try {
    return await operation();
  } finally {
    release();
    if (writeLocks.get(sourcePath) === tail) {
      writeLocks.delete(sourcePath);
    }
  }
}

async function readMarkdown(filePath) {
  const bytes = await fs.readFile(filePath);
  if (bytes.length > MAX_DOCUMENT_BYTES) {
    throw new HTTPError(413, "document_too_large", "The Markdown document exceeds 16 MiB.");
  }
  validateUTF8(bytes);
  const stat = await fs.stat(filePath);
  return {
    bytes,
    etag: `"${createHash("sha256").update(bytes).digest("hex")}"`,
    lastModified: stat.mtime.toUTCString(),
  };
}

async function readRequestBody(request) {
  const declaredLength = Number(request.headers["content-length"] || "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_DOCUMENT_BYTES) {
    throw new HTTPError(413, "document_too_large", "The Markdown document exceeds 16 MiB.");
  }
  const chunks = [];
  let received = 0;
  for await (const chunk of request) {
    received += chunk.length;
    if (received > MAX_DOCUMENT_BYTES) {
      throw new HTTPError(413, "document_too_large", "The Markdown document exceeds 16 MiB.");
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, received);
}

async function atomicWrite(filePath, bytes) {
  const temporaryPath = path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.aviv-${process.pid}-${Date.now()}`,
  );
  let handle;
  try {
    handle = await fs.open(temporaryPath, "wx", 0o600);
    await handle.writeFile(bytes);
    await handle.sync();
    await handle.close();
    handle = undefined;
    await fs.rename(temporaryPath, filePath);
  } finally {
    if (handle) {
      await handle.close().catch(() => {});
    }
    await fs.unlink(temporaryPath).catch(() => {});
  }
}

async function isAuthorized(request, tokenPath) {
  const authorization = request.headers.authorization;
  if (typeof authorization !== "string" || !authorization.startsWith("Bearer ")) {
    return false;
  }
  const supplied = Buffer.from(authorization.slice("Bearer ".length), "utf8");
  const expected = Buffer.from((await fs.readFile(tokenPath, "utf8")).trim(), "utf8");
  if (supplied.length !== expected.length || expected.length === 0) {
    return false;
  }
  return timingSafeEqual(supplied, expected);
}

function setSourceHeaders(response, config, slug, source, document) {
  response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
  response.setHeader("ETag", document.etag);
  response.setHeader("Last-Modified", document.lastModified);
  response.setHeader("X-Aviv-Source-ID", source.sourceId);
  response.setHeader("X-Aviv-Poll-Interval", "1");
  response.setHeader("X-Aviv-Source-URL", `${config.publicBaseURL}/${encodeURIComponent(slug)}`);
  if (source.writable) {
    response.setHeader("X-Aviv-Write-URL", `${config.writeBaseURL}/${encodeURIComponent(slug)}`);
  }
}

function matchSlug(pathname, prefix) {
  if (!pathname.startsWith(prefix)) {
    return null;
  }
  let slug;
  try {
    slug = decodeURIComponent(pathname.slice(prefix.length));
  } catch {
    return "";
  }
  return SLUG_PATTERN.test(slug) ? slug : "";
}

function validateUTF8(bytes) {
  try {
    utf8Decoder.decode(bytes);
  } catch {
    throw new HTTPError(415, "invalid_encoding", "Markdown must be valid UTF-8 text.");
  }
  if (bytes.includes(0)) {
    throw new HTTPError(415, "invalid_encoding", "Markdown must not contain null bytes.");
  }
}

function sendMethodNotAllowed(response, allow) {
  response.setHeader("Allow", allow);
  sendError(response, 405, "method_not_allowed", "That method is not allowed for this path.");
}

function sendError(response, status, code, message) {
  sendJSON(response, status, { error: code, message });
}

function sendJSON(response, status, value) {
  const body = Buffer.from(`${JSON.stringify(value)}\n`, "utf8");
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Content-Length", body.length);
  response.writeHead(status);
  response.end(body);
}

function required(environment, name) {
  const value = environment[name];
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function validatedBaseURL(value, name) {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    throw new Error(`${name} must be a credential-free HTTPS base URL`);
  }
  return url.href.replace(/\/$/, "");
}

function parsePort(value) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("AVIV_LIVE_PORT must be an integer between 1 and 65535");
  }
  return port;
}

function isInside(root, candidate) {
  return candidate === root || candidate.startsWith(`${root}${path.sep}`);
}

class HTTPError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const entryPath = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : "";
if (import.meta.url === entryPath) {
  const config = loadConfig();
  const server = createAvivLiveServer(config);
  server.on("clientError", (_error, socket) => {
    socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
  });
  server.listen(config.port, config.host, () => {
    console.log(`aviv-live listening on ${config.host}:${config.port}`);
  });
}
