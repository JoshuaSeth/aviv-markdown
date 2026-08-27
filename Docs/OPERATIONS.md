# Aviv Operations

## Source of truth

Aviv is the native macOS and Windows Markdown editor in
`https://github.com/JoshuaSeth/aviv-markdown.git`. The repository is public under the MIT license, so no replacement
private repository is needed. GitHub is authoritative; the PitchAI development server uses this checkout:

```text
/code/aviv-markdown
```

`main` is the default/release branch. `staging` is the integration branch. Start work from `staging`, use a dedicated
branch, and land it through a pull request.

The project is registered in the PitchAI PM database as `AVIV` (`Aviv Editor`), owned by Seth. Operationalization work
is recorded in task `AVIV-OPS-20260824`; public-URL live sync and authenticated save-back are tracked in
`AVIV-URL-SYNC-20260824`; the production Live Documents integration and runbook are tracked in
`AVIV-LIVE-DOCS-20260825`.

## Source inventory

The 2026-08-24 inventory found three relevant locations on the travel Mac:

- `/Users/sethvanderbijl/code/Aviv_new` — native Swift/AppKit and C#/WinUI repository, connected to the GitHub remote.
  Its local `main` was at `1ed3e9d64027c1937dd1555fab9772a86c771b86`, behind GitHub, with 18 unstaged deletions
  under `Windows/src/Aviv.Windows.App`. Those deletions were preserved but are not part of the authoritative source.
- `/Users/sethvanderbijl/PitchAI Code/typora_clone` — older Electron prototype with no Git metadata. It is historical
  lineage, not the active Aviv codebase.
- `/Users/sethvanderbijl/code/pitchai_net` — separate publishing-site repository containing the Aviv download page and
  packaged installers. It is not the editor source.

Before the server checkout was normalized, all three relevant source surfaces were archived without changing the Mac.
The root-only preservation set is stored on the development server at:

```text
/mnt/pitchai-dev-data/cold-validation-archives/aviv-travel-mac-preservation-20260824T133000Z
```

`SHA256SUMS` verifies the three gzip archives. The native archive also passed `git fsck --full` after macOS AppleDouble
metadata was excluded from a disposable validation extraction. Do not delete or mutate the Mac checkout; it remains a
historical recovery source.

## Requirements and local use

### macOS

- macOS 13 or newer
- Swift 5.9 or newer; Xcode is required for AppKit runtime, UI, packaging, and installer checks
- Python 3.9 or newer for `scripts/ios_check.py`
- The optional formatter, linter, and security tools enabled in `scripts/ios_check.env`

Run the app and core tests from the repository root:

```sh
swift run Aviv
swift test
swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
```

Packaging and end-to-end UI verification remain explicit operations:

```sh
Scripts/run_ui_verification.sh
Scripts/package_app.sh
Scripts/package_dmg.sh
```

The packaged-app accessibility verifier loads normal local, URL-backed live, and large structured Markdown fixtures;
checks that minimap and source-line metadata agree; enforces a two-second large-document load budget; exercises outline
navigation; audits editor, toolbar, title, status, format, live-sync, and conflict metadata; and writes JSON plus a PNG:

```sh
dist/Aviv.app/Contents/MacOS/Aviv --verify-accessibility dist/accessibility-audit
```

The styled-marker verifier drives native AppKit click events in a real document window for a normal local Markdown
file and a URL-backed live document. It proves that focus mounts the exact raw heading marker, click-away restores the
same reading-mode pixels, and source text, caret geometry, scroll position, title, and live-sync status remain intact.
It writes focused, restored, and native-window screenshots plus a JSON report:

```sh
dist/Aviv.app/Contents/MacOS/Aviv \
  --verify-styled-marker-reveal https://pitchai.net/aviv-live/seth-live-demo.md \
  --local-file Samples/styled-marker-reveal.md \
  --evidence-dir dist/styled-marker-reveal
```

The search verifier exercises the compact toolbar at the minimum supported window width and three wider layouts. It
fails on any toolbar or traffic-light overlap, missing previous/next control or shortcut, outline hit that is not
exposed, or editor geometry change. It also checks the live-document badge at 720 points, benchmarks 16,000 matches in
a 2.1 MB document, and writes compositor PNGs plus JSON:

```sh
dist/Aviv.app/Contents/MacOS/Aviv \
  --verify-search-ui Samples/search-layout-proof.md \
  --evidence-dir dist/search-toolbar
```

The header verifier opens both local and URL-backed documents, clicks the live-document indicator, proves the exact
opened URL is selectable and copied, and rejects any popover-induced editor or toolbar shift. It also verifies the
centered title's bounded native window-drag surface against traffic lights and toolbar controls at 720, 840, 1080,
and 1440 points, then writes native header and popover PNG evidence:

```sh
dist/Aviv.app/Contents/MacOS/Aviv \
  --verify-header-ui https://pitchai.net/aviv-live/seth-live-demo.md \
  --local-file Samples/styled-marker-reveal.md \
  --evidence-dir dist/header-ui
```

For the real macOS Accessibility tree of a running build, grant Accessibility permission to the terminal or automation
host once, then capture the bounded tab-separated audit. The script fails loudly if the process, window, permission, or
child traversal is unavailable:

```sh
Scripts/audit_accessibility_tree.sh Aviv 7 > dist/accessibility-audit/system-events-tree.tsv
```

The URL-source verifier needs a public fixture, its write token in a mode-`0600` file, and an external process that
edits the backing Markdown after each readiness line. It never accepts a token on the command line:

```sh
dist/Aviv.app/Contents/MacOS/Aviv \
  --verify-remote-live https://pitchai.net/aviv-live/seth-live-demo.md \
  --token-file /path/to/write-token \
  --evidence-dir /path/to/evidence
```

See [REMOTE_MARKDOWN.md](REMOTE_MARKDOWN.md) for the source headers and exact verification sequence.
For PitchAI's authenticated same-URL file service, use [LIVE_DOCUMENTS.md](LIVE_DOCUMENTS.md). That runbook records the
production safe folder, snapshot store, separate read/write credentials, exact Aviv workflow, error handling, and
deployment boundary without containing either secret.

### Windows

The native Windows app requires Windows, .NET 10, PowerShell, and the Windows App SDK described in
`Windows/README.md`. Run core tests with:

```powershell
dotnet test Windows/tests/Aviv.Windows.Core.Tests/Aviv.Windows.Core.Tests.csproj --configuration Release
```

Use `Windows/scripts/publish-win-x64.ps1` or `Windows/scripts/publish-win-arm64.ps1` for self-contained builds. App
build, UI interaction, and screenshot verification must run on Windows.

### Repository quality

Run the native gate where its configured tools are installed:

```sh
make check
make check-probe
```

Run the complete repository Python gate with its frozen Python 3.12 environment:

```sh
uv run --project quality --python 3.12 --frozen check
```

The Python environment under `quality/.venv` is generated and must not be committed.

### Known validation debt

As of 2026-08-24, the strict Swift build, test suite, production package, command and layout verifiers, UI snapshots,
scroll-stability checks, and typing-performance checks pass in a disposable clone on the travel Mac. The configured
`swift-format` check also passes.

The composite native policy gate is not yet clean: it still reports legacy force-unwrap, regex, CLI-output, and
best-effort cleanup patterns that predate the development-server registration. The travel Mac also does not have the
standalone SwiftLint, Semgrep, or Gitleaks executables required by that composite gate. Do not weaken or bypass those
checks. Resolve the legacy findings and install the missing tools in a dedicated quality task; until then, use the
passing runtime evidence above together with the repository-wide Python gate, and report the native policy-gate debt
in every release handoff.

## Live Markdown bridge

The production demonstration bridge runs on `pitchai-main` as `aviv-live.service`, bound to
`127.0.0.1:8793` behind nginx. Its public source is
`https://pitchai.net/aviv-live/seth-live-demo.md`; authenticated writes use the endpoint advertised in the source
headers. Runtime files are deliberately outside the Git checkout:

```text
/opt/aviv-live/server.mjs
/etc/aviv-live/sources.json
/etc/aviv-live/write-token
/var/lib/aviv-live/seth-live-demo.md
```

The token file is readable only by the service account and must never enter Git, a URL, a command-line argument, or
release evidence. The source manifest is an allowlist. The bridge rejects traversal, unlisted files, invalid UTF-8,
oversized documents, missing authentication, source-ID mismatches, and writes without a matching ETag. Writes for one
source are serialized and committed by atomic rename.

This demonstration bridge is separate from PitchAI Live Documents. The demo URL is public and its write endpoint uses
one bearer token. Live Documents protects reads with a read-only query token, protects writes with a separate bearer
token, automatically discovers safe regular files, and snapshots every overwritten version. Do not copy credentials,
runtime files, or assumptions between the two services.

Deploy bridge changes by syntax-checking the candidate, preserving the current installed file, restarting the service,
then verifying `/healthz`, the public source headers, an authenticated conditional write, and public readback. The
repository assets are in `Bridge/aviv-live`; its README contains the exact environment and nginx contract.

## Travel-Mac validation

The SSH alias `travel-macbook` is managed outside this repository. Do not record the underlying address or credentials
here. Treat `/Users/sethvanderbijl/code/Aviv_new` as read-only.

For Apple-platform validation:

1. Confirm the server branch is committed and pushed.
2. Connect with `ssh travel-macbook`.
3. Create a temporary directory and clone the GitHub branch into it. Do not reuse the historical checkout.
4. Run the required Swift build, tests, application, UI verifier, or packaging command in the temporary clone.
5. Record the commit SHA and command result, then remove the temporary clone.

For Aviv 1.1.0, the coordinated production verification used the public source above and external SSH edits to its
backing file. A clean edit appeared in 1.246 seconds with `0.000` point viewport movement and `0.000` text-container
width change. A second edit arriving over a dirty local buffer remained pending without replacing local text.
`Cmd-S` then changed the ETag and the saved marker was visible through the public URL. The normal performance gate also
passed on a 4,000-row, 392,480-character table with 0.6 ms scroll-update p95 and 27.0 ms raster p95.

If new local-only work is ever found on the Mac, archive the complete tree first, inspect `git status`, branches,
remotes, and diffs, and import only reviewed changes on a new server branch. Never reset or clean the Mac to make its
state match GitHub.

## Release boundary

This repository builds the editor and installers. The download page and published files live in the separate
`JoshuaSeth/pitchai_net` repository. Building an artifact does not authorize publishing it; verify checksums and follow
the publishing repository's release process.
