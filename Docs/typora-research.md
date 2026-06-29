# Typora Research

Sources checked on 2026-06-29:

- <https://typora.io/>
- <https://support.typora.io/Quick-Start/>
- <https://support.typora.io/Table-Editing/>

Relevant findings:

- Typora positions itself as a markdown reader and writer with a single live-preview surface. The official site says it removes the separate preview window, mode switcher, and markdown source symbols so the writer can focus on content.
- Typora's quick start describes Live Preview: inline styles render after typing, block styles render as blocks, and markdown tags are hidden or displayed smartly.
- Typora documents GitHub Flavored Markdown support and lists common blocks: headings, lists, task lists, tables, code fences, block quotes, horizontal rules, links, images, and inline styles.
- Typora's table docs confirm that users can still write markdown table source directly, while the UI helps edit rows, columns, and alignment.

Implementation decisions for Aviv:

- Build a native macOS AppKit application, not Electron.
- Use one editable surface, not a source/preview split.
- Keep raw markdown characters in the text storage at all times. Inactive syntax is transparent but still occupies identical glyph metrics. Active-line syntax is repainted in a soft annotation color. This intentionally preserves glyph positions while moving the cursor.
- Apply rendered markdown typography to content independently of cursor position. Only syntax marker foreground color changes between reading and editing states.
- Test the no-layout-shift promise by measuring glyph bounding rects for semantic content across many cursor positions.
