# Apple quality configuration and activation

Run `uv run check` from the repository root. It calls the existing `make check`
Apple aggregate, then retains the previous Python aggregate where one existed.
Both return statuses are preserved; a failed Apple check cannot become success
because the Python check passed. No native/static gate is reimplemented here.

`uv run check --list` lists the configured Apple gates. `uv run check --probe`
runs the deliberate failing-fixture harness through `make check-probe`.
Those diagnostics do not claim that application lint/build/tests pass.

Installation acceptance is configuration correctness, command wiring and
failure propagation. Existing application debt remains visible and does not
prevent installing the checker. Required repository protections still apply.
Native build/test results require a real Mac/Xcode; Linux activation is not
simulator validation. No deployment, signing or artifact publication is part
of this entrypoint.
