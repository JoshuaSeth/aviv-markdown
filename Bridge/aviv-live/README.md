# Aviv live Markdown bridge

This small Node service gives Aviv a real write path for an allowlisted public Markdown file. Public reads use `GET /aviv-live/<name>.md`. Authenticated saves use `PUT /api/aviv-live/<name>.md` with a bearer token, the source ID, and `If-Match` from the last downloaded ETag.

The bridge never accepts credentials in URLs, never serves files outside its manifest, rejects stale saves with HTTP
412, limits documents to 16 MiB, validates UTF-8, and commits accepted writes through an atomic rename. Writes are
serialized per source, so simultaneous requests carrying one ETag produce exactly one commit. Run its dependency-free
tests with `npm test`.

Deployment inputs live under `deploy/`. The write token belongs in `/etc/aviv-live/write-token` with mode `0600`; it must not be committed or printed. The matching token is stored in Aviv's macOS Keychain service `net.pitchai.aviv.remote-write`, scoped to both the source ID and write-endpoint origin.
