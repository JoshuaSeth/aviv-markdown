# Aviv Agent Instructions

## Source and branches

- Treat `https://github.com/JoshuaSeth/aviv-markdown.git` as the source of truth.
- Use `/code/aviv-markdown` as the canonical PitchAI development-server checkout.
- Branch from `staging`; keep `main` as the default/release branch. Land changes through a reviewed pull request.
- Track work in the PitchAI PM project `AVIV` and keep repository, branch, validation, and handoff evidence current.

## Travel Mac

- The SSH alias `travel-macbook` reaches the Mac used for macOS runtime validation. Never commit its host, IP,
  credentials, or private SSH configuration.
- Do not edit, clean, reset, pull, build in, or delete the historical checkout at
  `/Users/sethvanderbijl/code/Aviv_new`.
- Use a disposable clone for Mac validation. Remove that clone after the test. Copy work from the historical checkout
  only after preserving it and reviewing its diff against GitHub.

## Validation

- Run `uv run --project quality --python 3.12 --frozen check` for the complete repository Python gate.
- Run `make check` where the native tools configured in `scripts/ios_check.env` are installed.
- Run `swift test` and `swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete` on macOS.
- Run the Windows solution tests and publish scripts on Windows; the WinUI XAML compiler is not available on macOS or
  Linux.
- Fail loudly when a required tool or configured target is missing. Do not add validation exclusions, ignored failures,
  or business-logic fallbacks.

See `Docs/OPERATIONS.md` for the source inventory, prerequisites, preservation evidence, and release boundaries.
