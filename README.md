# Aviv Markdown ✨

**Aviv is a hyper-clean native macOS Markdown editor with a calm WYSIWYG writing surface.**

It is built for people who want Markdown files, native speed, and a focused document feel without the usual split preview/source editor clutter. You write real `.md` files, but Aviv renders them inline so the page feels quiet, minimal, and direct.

![Aviv editor screenshot](Docs/assets/aviv-editor.png)

## Why Aviv? 🌿

Most Markdown editors make you choose between raw source and rendered preview. Aviv aims for the sweet spot:

- **WYSIWYG-style Markdown editing** without giving up the underlying plain-text `.md` file.
- **No split preview pane** and no mode switcher.
- **Stable layout while editing** so content does not jump when the cursor moves.
- **Native AppKit macOS app** instead of Electron.
- **Minimal, glassy, readable UI** with subtle frosted top and minimap surfaces.

## Features 🚀

- Live rendered Markdown in one editable surface.
- Smart syntax reveal on the active line.
- Headings, bold, italic, code, links, blockquotes, rules, tables, task lists, and fenced code.
- Native open/save panels for `.md` files.
- Multiple windows and native macOS document tabs.
- `Cmd-T` for a new tab, `Cmd-W` to close the active tab/window.
- Drag tabs out into new windows and merge windows back together.
- Clean minimap/sidebar that follows the actual rendered viewport.
- Top bar and sidebar use subtle blur/tint so overlays stay readable.
- Zoom controls that change view size without changing Markdown source.
- Native print and page setup support.
- Command, tab, layout, and minimap verifiers for regression testing.

## Screenshots 🖼️

![Aviv minimap screenshot](Docs/assets/aviv-minimap.png)

## Install Locally 🛠️

Aviv is a Swift Package app targeting macOS.

```bash
swift run Aviv
```

To package and install it as the default Markdown handler:

```bash
Scripts/install_default_markdown_handler.sh
```

That builds `dist/Aviv.app`, installs it to `/Applications` when possible, signs it ad hoc, registers it with LaunchServices, and makes it the default app for Markdown files.

## Verification ✅

Run the complete verification suite:

```bash
Scripts/run_ui_verification.sh
```

This runs:

- Swift unit tests
- command/menu verifier
- tab/window verifier
- layout stability verifier
- minimap viewport verifier
- rendered snapshot generation

Core invariants are tested directly: moving the cursor should not shift rendered content, the minimap should track the real scroll viewport, and native tabs/windows should behave like real macOS document tabs.

## Project Shape 🧱

```text
Sources/AvivApp      macOS app shell, menus, windows, tabs, packaging verifiers
Sources/AvivCore     editor view, Markdown styling, minimap, parsing, snapshots
Tests/AvivCoreTests  layout, minimap, edge-case, command, and styling tests
Scripts              packaging, LaunchServices install, verification scripts
Docs                 design notes and regression checklists
Samples              sample Markdown fixtures
```

## Philosophy 🧘

Aviv is intentionally quiet. Markdown remains editable source, but the visual surface is designed for reading and writing rather than inspecting syntax all day.

The editor should feel:

- **fast**
- **native**
- **minimal**
- **stable**
- **beautifully boring when you are focused**

## Status 🌱

This is an early but functional macOS Markdown editor prototype. It already opens, edits, saves, tabs, windows, renders, prints, verifies, and installs locally as a Markdown handler.

