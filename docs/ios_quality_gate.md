# PitchAI iOS Quality Gate

This project uses the PitchAI hyper-strict iOS quality gate.

Run:

```sh
make check
```

Useful commands:

```sh
make check-list
make check-one GATE=swiftlint
make check-probe
make format
```

The gate fails on formatting drift, SwiftLint violations, PitchAI forbidden
runtime patterns, secret-like strings, Semgrep findings, dependency issues,
compiler warnings/errors, strict concurrency failures, analyzer findings, and
test/simulator failures according to `scripts/ios_check.env`.

Release safety: this gate is not release automation. It uses simulator/test
builds and a local DerivedData path. It must not archive, export, upload to
TestFlight, or modify signing/provisioning settings.
