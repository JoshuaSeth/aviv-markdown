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

`scripts/ios_check.py` is the stable command entry point. Its implementation is
split across the typed `ios_quality` package so every module is covered by the
repository's strict Python gate and remains below the 250-line module ceiling.

Run that separate repository-wide Python gate with:

```sh
uv run --project quality --python 3.12 --frozen check
```

Release safety: this gate is not release automation. It uses simulator/test
builds and a local DerivedData path. It must not archive, export, upload to
TestFlight, or modify signing/provisioning settings.
