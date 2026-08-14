# Python Quality Gate

Run the repository's complete fail-closed Python gate with:

```sh
uv run --project quality --python 3.12 --frozen check
```

The aggregate runs the anti-bypass policy, all five PitchAI Python preference
checkers, Ruff with every rule selected, BasedPyright in strict mode with fatal
warnings, full Pylint with a score floor of 10 and a 250-line module ceiling,
and Semgrep `ERROR` rules. It checks every repository Python and stub file,
including tests and tools. Only generated caches, virtual environments, build
outputs, and other non-source directories are omitted from discovery.

The read-only GitHub Actions workflow runs for every pull request and every
push branch. It intentionally has no branch-name filter, so repositories whose
default branch is `main`, `master`, `staging`, or another project-specific name
cannot silently skip the gate.

The read-only GitHub workflow is the external CI trust root. Before installing
or executing the quality project, it compares the anti-bypass verifier with an
exact SHA-256 digest committed in the workflow and fails loudly on a mismatch.
The verifier hardcodes the exact digest of the required-file manifest. The
manifest, in turn, hashes the runner, all five preference checkers, every
semantic helper, the complete-source resolver, `strict_policy.py`, locked
dependencies, tool configuration, Semgrep policy, and this documentation. The
workflow, verifier, and manifest are intentionally excluded from the manifest
to keep the digest chain acyclic.

The verifier rejects missing or unexpected portable files, altered manifest
membership, and every manifested-file hash mismatch. It also validates the
workflow's all-PR/all-push triggers, read-only permissions, trust-anchor step,
frozen install and aggregate commands, full-SHA action pins, and absence of
`continue-on-error: true`. The unavoidable boundary is a coordinated edit to
the external workflow trust root and the chain it anchors: that change must be
identified and judged in code review. Repository-local files cannot
self-authenticate such a coordinated change, this design makes no claim of
mutually authenticated local files, and it uses no operational signing secret.

Ruff always receives `--config quality/pyproject.toml`, BasedPyright receives
`--project quality/pyproject.toml`, Pylint receives
`--rcfile quality/pyproject.toml`, and Semgrep receives the absolute strict
config path. Installation and execution both select the frozen `quality`
project. Consequently root dependency files cannot change the quality
environment, and root tool configs cannot weaken these invocations. The
anti-bypass gate also rejects alternate root tool configs and any other GitHub
Actions workflow that invokes the quality project or a direct checker.
Across every workflow, non-local `uses:` references must be pinned to a full
40-hex commit SHA and `continue-on-error` is forbidden. Mutable third-party
action tags and ignored workflow failures are reported as anti-bypass debt;
deployment workflows receive no exemption.

A nonzero result is an enforcement result, not permission to narrow coverage.
Repair violations with real dependencies or stubs and explicit boundary
architecture. Do not add inline suppressions, diagnostic downgrades, source
exclusions, ignored failures, or checker wrappers that hide a tool result.
