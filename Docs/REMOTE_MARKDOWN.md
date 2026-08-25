# Remote Markdown sources

Aviv 1.1.0 for macOS can open a Markdown document from a public HTTPS URL, follow external changes, and save through an
authenticated bridge when the source explicitly advertises one. The Windows app does not yet implement this feature.

## Open and follow a URL

Use **File → Open from URL…** (`Shift-Cmd-O`) and enter an HTTPS URL. Generic sources should be credential-free. A
provider may instead define a constrained read-only query token, as PitchAI Live Documents does; in that case the
entire URL is sensitive and must not be shared. Aviv downloads no more than 16 MiB and accepts valid UTF-8 or UTF-16
Markdown. URL user-info credentials, insecure HTTP URLs, unsafe write URLs, invalid text, and malformed responses fail
visibly.

The open document retains two URL identities:

- `openedURL` is exactly what the user opened and is what appears in recents.
- `resolvedURL` is the final public download URL after redirects and remains the polling target after a save.

Polling uses `If-None-Match` when an ETag is available and otherwise uses `If-Modified-Since`. The default interval is
one second. A server may request an interval between 1 and 60 seconds; values outside that range are clamped. A `304`
response does no diffing, Markdown styling, or layout work.

When a clean remote document changes, Aviv maps every selection through the changed range, captures the first visible
text glyph as an anchor, refreshes the Markdown, restores that anchor to the same screen position, and keeps the text
container width fixed. The source badge, heartbeat, shimmer, top-edge pulse, changed-line marker, and compact toast are
overlay-only and never participate in document layout.

## Source response contract

A generic public Markdown URL needs no Aviv-specific headers and opens read-only. A bridge-backed source uses these
response headers:

| Header | Required for | Meaning |
| --- | --- | --- |
| `ETag` | conflict-safe save | Validator sent in polling and `If-Match` writes |
| `Last-Modified` | optional polling fallback | Validator used only when no ETag exists |
| `X-Aviv-Source-ID` | bridge identity | Stable identity that must not change while the document is open |
| `X-Aviv-Poll-Interval` | optional | Requested polling interval in seconds, clamped to 1–60 |
| `X-Aviv-Source-URL` | bridge diagnostics | Canonical public download URL |
| `X-Aviv-Write-URL` | authenticated save | HTTPS endpoint that accepts conditional `PUT`; any provider-defined read token must remain unchanged |

The production example is
[https://pitchai.net/aviv-live/seth-live-demo.md](https://pitchai.net/aviv-live/seth-live-demo.md).

PitchAI's authenticated general-purpose source is Live Documents at `https://livedocuments.pitchai.net`. It uses a
separate read-only `access_token` query value for Aviv's initial `GET` and a bearer token for `PUT`; the same complete
URL is advertised for reads and writes. See [PitchAI Live Documents in Aviv](LIVE_DOCUMENTS.md) for the exact safe
folder, credential handling, open/save workflow, error map, deployment path, and operator checks.

## Authenticated Command-S

Aviv never sends `PUT` to an arbitrary download URL. `Cmd-S` is enabled for a URL source only when
`X-Aviv-Write-URL` is present and the current source has an ETag. On the first save, Aviv names the write host and asks
for its bearer token. The token is stored in macOS Keychain under service `net.pitchai.aviv.remote-write`; Aviv does
not place that write token in the opened URL, recent documents, logs, or Markdown metadata. Provider-defined read-only
query tokens are part of the opened URL and must be handled as sensitive URLs.

The write request contains:

```http
PUT /api/aviv-live/source.md
Authorization: Bearer <keychain token>
Content-Type: text/markdown; charset=utf-8
If-Match: "current-etag"
X-Aviv-Source-ID: stable-source-id
```

A successful response must return a fresh ETag. `401` removes the stale Keychain entry and offers one credential retry.
`409` is treated as a source-identity failure. `412` is a write conflict. Any other non-success response fails visibly;
the local buffer stays dirty.

## Simultaneous edits

Aviv compares three states: the last accepted remote Markdown, the current local buffer, and the newest observed remote
Markdown.

| State | Result |
| --- | --- |
| Local buffer still equals the accepted version | Apply the remote change in place |
| Local buffer differs and the remote source changes | Preserve the local buffer and hold the incoming snapshot |
| `Cmd-S` while an incoming snapshot is pending | Refuse the write and open conflict resolution |
| User chooses **Use Incoming** | Replace the local buffer with the pending snapshot |
| User chooses **Replace Remote with Mine** | Send the local buffer with the pending snapshot's newest ETag |
| User chooses **Keep Editing** | Make no change; the incoming state remains visible and pending |

The bridge serializes writes per source. Of several simultaneous writes carrying the same ETag, exactly one can commit;
the rest receive `412`. The source is allowlisted and confined to its configured data root, and a successful write uses
a flushed temporary file followed by atomic rename.

## Performance and verification

Automated coverage includes URL/source parsing, conditional polling, source identity, authenticated request headers,
fresh save validators, clean refresh, dirty-buffer conflict preservation, explicit replacement, caret/range mapping,
zero-shift layout behavior, and six overlay indicators. The bridge suite adds authentication, traversal, encoding,
read-only, stale-validator, atomic-write, and 12-way simultaneous-write tests.

The 2026-08-24 production run used the public URL above, an external SSH edit, and the packaged macOS app:

```text
AVIV_REMOTE_READY_CLEAN source=seth-live-demo poll=1.0s indicators=6
AVIV_REMOTE_CLEAN_APPLIED elapsed=1.246s viewport_delta=0.000 width_delta=0.000
AVIV_REMOTE_READY_CONFLICT local_preserved=true
AVIV_REMOTE_CONFLICT_PRESERVED incoming_waiting=true overwrite=false
AVIV_REMOTE_COMMAND_S_SAVED etag_changed=true public_readback=true source=seth-live-demo
remote-live-verifier: PASS
```

The standard large-document gate also passed a 4,000-row, 392,480-character Markdown table: 274.5 ms initial load,
0.6 ms scroll-update p95, 27.0 ms raster p95, and 11.2 ms average edit time. Conditional `304` polling does not enter
the render path.

Evidence:

- [Clean external update](assets/aviv-remote-clean-update.png)
- [Dirty-buffer conflict preservation](assets/aviv-remote-conflict-preserved.png)
- [Authenticated Command-S save](assets/aviv-remote-command-s-saved.png)

The reference bridge, service unit, nginx location, manifest example, and deployment notes live in
[`Bridge/aviv-live`](../Bridge/aviv-live/README.md).
