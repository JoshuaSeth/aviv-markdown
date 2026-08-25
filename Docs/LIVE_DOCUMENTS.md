# PitchAI Live Documents in Aviv

PitchAI Live Documents is the production source for Markdown that must remain an ordinary file on `pitchai-main` while
Aviv opens, follows, and saves it remotely. The public origin is `https://livedocuments.pitchai.net`. This integration
uses the same stable file URL for `GET`, `HEAD`, and `PUT`; the HTTP method and save headers determine the operation.

The service implementation and authoritative server runbook live in
`JoshuaSeth/pitchai_infrastructure/services/live-documents`.

## Production paths and ownership

| Purpose | Production value |
| --- | --- |
| Exposed safe folder | `/var/lib/pitchai-live-documents/documents` |
| Prior-version snapshots | `/var/lib/pitchai-live-documents/snapshots` |
| Read-only Aviv token file | `/etc/pitchai-live-documents/aviv-read-token` |
| Write bearer token file | `/etc/pitchai-live-documents/bearer-token` |
| Service | `pitchai-live-documents.service` |
| Public file route | `https://livedocuments.pitchai.net/files/<safe-path>` |

An infrastructure operator exposes a document by installing it into the safe folder with the service account as owner.
No manifest or service restart is needed:

```sh
sudo install \
  -o pitchai-live-documents \
  -g pitchai-live-documents \
  -m 0640 \
  /path/to/approved-document.md \
  /var/lib/pitchai-live-documents/documents/approved-document.md
```

Names may contain ASCII letters, digits, spaces, `.`, `_`, and `-`; every path segment must start with a letter or
digit. Hidden names, empty segments, `.`/`..`, trailing dots or spaces, symlinks, devices, and non-regular files are
rejected. A remote `PUT` replaces an existing file only. It cannot create a new path.

## The two credentials

Live Documents deliberately separates read and write authority:

1. The Aviv read token appears only in the stable query-token URL:

   ```text
   https://livedocuments.pitchai.net/files/approved-document.md?access_token=<AVIV_READ_TOKEN>
   ```

   It authorizes `GET` and `HEAD`, never `PUT`. Treat the entire URL as a secret: it remains attached to the open
   document and may appear in Aviv's Open Recent list. Do not put it in Git, PM records, logs, screenshots, shell
   history, or chat. Obtain it through the approved private credential route; do not print the root-owned token file.

2. The bearer token authorizes every save. On the first `Cmd-S`, Aviv shows a secure prompt for the write token and
   stores it in macOS Keychain under service `net.pitchai.aviv.remote-write`. Never substitute the bearer token into
   the URL.

Nginx logs the path without query arguments or referrers, its vhost error log is disabled, and Uvicorn access logging
is disabled. These settings are part of the security boundary for the read-token URL and must not be relaxed.

## Open and save

1. Obtain the complete query-token URL privately. Do not reconstruct it with the bearer token.
2. In Aviv 1.1.0 or newer on macOS, choose **File → Open from URL…** (`Shift-Cmd-O`) and paste the URL.
3. Confirm the source badge identifies `livedocuments.pitchai.net`. Aviv polls once per second with the latest `ETag`.
4. Edit the Markdown and press `Cmd-S`.
5. At the first save prompt, enter the separate bearer write token. Aviv sends it in `Authorization`, never in the URL.
6. Keep the document open until the saved state appears. A successful save returns a fresh `ETag`; subsequent polling
   and saves continue on the identical query-token URL.

The effective save request is:

```http
PUT /files/approved-document.md?access_token=<AVIV_READ_TOKEN>
Authorization: Bearer <BEARER_TOKEN>
Content-Type: text/markdown; charset=utf-8
If-Match: "latest-etag"
X-Aviv-Source-ID: live-documents:<path-digest>
```

Before replacing the file, the server writes its exact prior bytes to
`/var/lib/pitchai-live-documents/snapshots/<safe-path>/`. Writes are serialized, flushed to a private temporary file,
and committed by atomic rename. If another writer wins first, Aviv receives `412` and preserves the local buffer.

## External edits and conflicts

An external filesystem change or another successful writer changes the document's validator. If Aviv's local buffer
is clean, the new Markdown is applied in place while selection, visible anchor, scroll position, and layout width stay
fixed. If the local buffer is dirty, Aviv keeps the local text and shows **Incoming edit waiting**.

Use **File → Resolve Incoming Changes…** to choose one of the explicit outcomes:

- **Use Incoming** replaces the local buffer with the newest server version.
- **Replace Remote with Mine** conditionally writes the local buffer against the newest observed `ETag`.
- **Keep Editing** leaves both the local buffer and pending incoming version unchanged.

Do not work around a conflict by copying an old `ETag` or issuing an unconditional write.

## Errors and recovery

| Symptom or HTTP status | Meaning and action |
| --- | --- |
| `401` while opening | The read URL is missing, stale, duplicated, or wrong. Obtain a newly issued private URL. |
| `401` while saving | The bearer credential is stale or wrong. Aviv removes its Keychain entry and offers one secure retry. |
| `403 unsafe_path` | The name, traversal form, symlink, or entry type is outside the safe namespace. Correct the server path. |
| `404 file_not_found` | The file does not exist. Install it in the safe folder first; remote `PUT` cannot create it. |
| `412 write_conflict` | The remote file changed. Keep the local buffer and resolve the incoming change explicitly. |
| `413 document_too_large` | The file exceeds the 16 MiB production bound. Reduce or split it. |
| `428 validator_required` | A client attempted to save without `If-Match`. Refresh in Aviv; do not retry unconditionally. |
| `500 snapshot_failure` or `storage_failure` | Stop saving and inspect ownership, free space, and the service journal. |
| `503 storage_unavailable` or `index_too_large` | A confined root is unavailable or the 2,000-file index bound was exceeded. |
| Aviv says the URL is read-only | The response lost `X-Aviv-Write-URL` or `ETag`. Treat this as a proxy/service contract failure. |

Safe operator checks do not require printing either token:

```sh
systemctl status pitchai-live-documents.service
journalctl -u pitchai-live-documents.service --since '30 minutes ago'
readlink -f /opt/pitchai-live-documents/current
nginx -t
```

For read-token rotation, issue a new private URL and reopen it in Aviv. For bearer rotation, replace the protected
server file atomically, restart the service, update the CI smoke credential, and enter the new token when Aviv retries
the next save. Never paste either value into a diagnostic command or ticket.

## Deployment and launch evidence

The service is released from `JoshuaSeth/pitchai_infrastructure`. Pull requests land in `staging`, then a reviewed
promotion lands in `main`. Only a tested push to `main` can activate production. The workflow deploys the exact merged
SHA into an immutable release directory, switches the `current` symlink atomically, verifies authenticated loopback
health, and proves public unauthorized denial plus authenticated reads. A failed activation restores the prior SHA.

The 2026-08-25 launch activated infrastructure main SHA `60173ec1e94102c669fcceb6aeffb44493fa3e8d`.
Production verification proved TLS and three public DNS resolvers; authenticated and unauthenticated index, health,
`GET`, `HEAD`, validators, same-URL `PUT`, exact restoration, private snapshots, automatic safe-folder discovery,
Aviv query-token reads, bearer-only writes, traversal and symlink confinement, no CORS, and credential-free request
logs.

A disposable travel-Mac clone of Aviv commit `dffc926f8625429a934490b35821f6690fb6fdac` then passed strict formatting,
59 tests with warnings-as-errors and complete Swift 6 concurrency, a strict build, release packaging, and code-signature
verification. Against the production query-token URL, the native verifier applied a clean external edit in 1.092
seconds with `0.000` point viewport movement and `0.000` text-container width change, preserved a dirty local buffer
when a second external edit arrived, and completed an authenticated `Cmd-S` with a fresh ETag and public readback.
All three rendered evidence frames were inspected and contained no credential. The temporary server fixture and its
five private snapshots, Mac clone and token files, and local evidence copies were removed after verification; the
historical travel-Mac checkout remained unchanged.
