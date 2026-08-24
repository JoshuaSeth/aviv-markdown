# Seth's live Aviv document

> This public Markdown file is connected to Aviv's authenticated live-source bridge.

## What to expect

- Aviv checks this source every second with a conditional request.
- Clean external edits appear in place without moving the caret or viewport.
- Local work is preserved when an external edit arrives at the same time.
- Command-S writes through an authenticated endpoint with ETag conflict protection.

## Shared working notes

This section is safe for Seth and an external agent to edit together. Incoming changes receive restrained visual feedback in Aviv: a source badge, heartbeat, status shimmer, edge pulse, changed-line marker, and compact toast.

| Capability | Live state |
| --- | --- |
| Public URL open | Ready |
| One-second polling | Ready |
| Authenticated save | Ready |
| Conflict preservation | Ready |

## Stable reading area

The paragraphs below make viewport preservation visible during a live-edit demonstration.

01. Aviv keeps the document source identity attached to the open window.

02. Conditional requests avoid downloading unchanged Markdown.

03. External updates are diffed only after the ETag changes.

04. The current selection maps across incoming insertions and deletions.

05. The visible text anchor returns to the same screen position.

06. Overlay indicators never participate in text layout.

07. Large tables keep the same optimized render path.

08. A dirty local buffer is never replaced automatically.

09. A stale save fails rather than pretending it succeeded.

10. The write credential stays in the macOS Keychain.

11. Stable anchor for the live viewport check.

12. This final line remains available for future external-agent edits.
