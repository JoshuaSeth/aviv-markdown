import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createAvivLiveServer } from "../server.mjs";

async function fixture(t, { writable = true } = {}) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "aviv-live-test-"));
  const documentPath = path.join(directory, "seth-live-demo.md");
  const tokenPath = path.join(directory, "write-token");
  await fs.writeFile(documentPath, "# Live\n\nOriginal.\n", "utf8");
  await fs.writeFile(tokenPath, "test-secret\n", { encoding: "utf8", mode: 0o600 });
  const server = createAvivLiveServer({
    publicBaseURL: "https://pitchai.test/aviv-live",
    writeBaseURL: "https://pitchai.test/api/aviv-live",
    tokenPath,
    sources: new Map([
      [
        "seth-live-demo.md",
        { path: documentPath, sourceId: "seth-live-demo", writable },
      ],
    ]),
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(async () => {
    await new Promise((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
    await fs.rm(directory, { recursive: true, force: true });
  });
  const address = server.address();
  return {
    baseURL: `http://127.0.0.1:${address.port}`,
    documentPath,
  };
}

test("public GET advertises stable source metadata and supports conditional polling", async (t) => {
  const context = await fixture(t);
  const first = await fetch(`${context.baseURL}/aviv-live/seth-live-demo.md`);
  assert.equal(first.status, 200);
  assert.equal(await first.text(), "# Live\n\nOriginal.\n");
  assert.equal(first.headers.get("x-aviv-source-id"), "seth-live-demo");
  assert.equal(first.headers.get("x-aviv-poll-interval"), "1");
  assert.equal(
    first.headers.get("x-aviv-write-url"),
    "https://pitchai.test/api/aviv-live/seth-live-demo.md",
  );
  const etag = first.headers.get("etag");
  assert.ok(etag);

  const second = await fetch(`${context.baseURL}/aviv-live/seth-live-demo.md`, {
    headers: { "If-None-Match": etag },
  });
  assert.equal(second.status, 304);
  assert.equal(await second.text(), "");
});

test("authenticated conditional PUT atomically saves Markdown", async (t) => {
  const context = await fixture(t);
  const opened = await fetch(`${context.baseURL}/aviv-live/seth-live-demo.md`);
  const etag = opened.headers.get("etag");
  const saved = await fetch(`${context.baseURL}/api/aviv-live/seth-live-demo.md`, {
    method: "PUT",
    headers: {
      Authorization: "Bearer test-secret",
      "Content-Type": "text/markdown; charset=utf-8",
      "If-Match": etag,
      "X-Aviv-Source-ID": "seth-live-demo",
    },
    body: "# Live\n\nSaved from Aviv.\n",
  });
  assert.equal(saved.status, 204);
  assert.notEqual(saved.headers.get("etag"), etag);
  assert.equal(await fs.readFile(context.documentPath, "utf8"), "# Live\n\nSaved from Aviv.\n");
});

test("missing authentication cannot change the backing file", async (t) => {
  const context = await fixture(t);
  const opened = await fetch(`${context.baseURL}/aviv-live/seth-live-demo.md`);
  const response = await fetch(`${context.baseURL}/api/aviv-live/seth-live-demo.md`, {
    method: "PUT",
    headers: {
      "If-Match": opened.headers.get("etag"),
      "X-Aviv-Source-ID": "seth-live-demo",
    },
    body: "overwrite",
  });
  assert.equal(response.status, 401);
  assert.equal(await fs.readFile(context.documentPath, "utf8"), "# Live\n\nOriginal.\n");
});

test("stale ETag preserves an external agent edit", async (t) => {
  const context = await fixture(t);
  const opened = await fetch(`${context.baseURL}/aviv-live/seth-live-demo.md`);
  await fs.writeFile(context.documentPath, "# Live\n\nExternal agent edit.\n", "utf8");
  const response = await fetch(`${context.baseURL}/api/aviv-live/seth-live-demo.md`, {
    method: "PUT",
    headers: {
      Authorization: "Bearer test-secret",
      "If-Match": opened.headers.get("etag"),
      "X-Aviv-Source-ID": "seth-live-demo",
    },
    body: "# Live\n\nStale local overwrite.\n",
  });
  assert.equal(response.status, 412);
  assert.equal(
    await fs.readFile(context.documentPath, "utf8"),
    "# Live\n\nExternal agent edit.\n",
  );
});

test("simultaneous writes with one ETag allow exactly one commit", async (t) => {
  const context = await fixture(t);
  const opened = await fetch(`${context.baseURL}/aviv-live/seth-live-demo.md`);
  const etag = opened.headers.get("etag");
  const attempts = Array.from({ length: 12 }, (_, index) => {
    const body = `# Live\n\nConcurrent writer ${index}.\n`;
    return fetch(`${context.baseURL}/api/aviv-live/seth-live-demo.md`, {
      method: "PUT",
      headers: {
        Authorization: "Bearer test-secret",
        "If-Match": etag,
        "X-Aviv-Source-ID": "seth-live-demo",
      },
      body,
    }).then((response) => ({ body, status: response.status }));
  });

  const results = await Promise.all(attempts);
  const committed = results.filter((result) => result.status === 204);
  assert.equal(committed.length, 1);
  assert.equal(results.filter((result) => result.status === 412).length, 11);
  assert.equal(await fs.readFile(context.documentPath, "utf8"), committed[0].body);
});

test("source identity mismatch and read-only sources fail loudly", async (t) => {
  const writable = await fixture(t);
  const opened = await fetch(`${writable.baseURL}/aviv-live/seth-live-demo.md`);
  const mismatch = await fetch(`${writable.baseURL}/api/aviv-live/seth-live-demo.md`, {
    method: "PUT",
    headers: {
      Authorization: "Bearer test-secret",
      "If-Match": opened.headers.get("etag"),
      "X-Aviv-Source-ID": "another-source",
    },
    body: "mismatch",
  });
  assert.equal(mismatch.status, 409);

  const readOnly = await fixture(t, { writable: false });
  const denied = await fetch(`${readOnly.baseURL}/api/aviv-live/seth-live-demo.md`, {
    method: "PUT",
    headers: { Authorization: "Bearer test-secret" },
    body: "denied",
  });
  assert.equal(denied.status, 403);
});

test("unlisted and traversal-shaped paths are never served", async (t) => {
  const context = await fixture(t);
  const missing = await fetch(`${context.baseURL}/aviv-live/unknown.md`);
  assert.equal(missing.status, 404);

  const traversal = await new Promise((resolve, reject) => {
    const request = http.request(
      `${context.baseURL}/aviv-live/%2e%2e%2fseth-live-demo.md`,
      (response) => {
        response.resume();
        response.on("end", () => resolve(response.statusCode));
      },
    );
    request.on("error", reject);
    request.end();
  });
  assert.equal(traversal, 404);
});
