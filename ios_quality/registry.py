# Copyright (c) 2026 PitchAI. All rights reserved.
"""Canonical gate registry and aggregate execution."""

from __future__ import annotations

import sys
from typing import TYPE_CHECKING

from .build_gates import BuildGateRunner
from .runtime import ProcessRunner, write_header
from .static_gates import StaticGateRunner
from .xcode_gates import XcodeGateRunner

if TYPE_CHECKING:
    from .model import CheckConfig, Gate


class GateRegistryError(ValueError):
    """Signal an inconsistent native quality-gate registry."""


GATE_ORDER = (
    "preflight",
    "format-swift-format",
    "format-swiftformat",
    "swiftlint",
    "pitchai-patterns",
    "secrets-builtin",
    "gitleaks",
    "semgrep",
    "spm-resolve",
    "xcode-build-for-testing",
    "swiftlint-analyze",
    "xcode-analyze",
    "xcode-test",
    "periphery",
    "ui-snapshots",
)


def gates(config: CheckConfig) -> tuple[Gate, ...]:
    """Build the complete canonical gate sequence.

    Returns:
        All native quality gates in their execution order.

    Raises:
        GateRegistryError: If gate definitions are duplicated or incomplete.
    """
    process = ProcessRunner()
    unordered: list[Gate] = []
    unordered.extend(BuildGateRunner(config, process).gates())
    unordered.extend(StaticGateRunner(config, process).gates())
    unordered.extend(XcodeGateRunner(config, process).gates())

    by_name: dict[str, Gate] = {}
    for gate in unordered:
        if gate.name in by_name:
            message = f"duplicate native quality gate: {gate.name}"
            raise GateRegistryError(message)
        by_name[gate.name] = gate
    if set(by_name) != set(GATE_ORDER):
        message = "native quality gate registry does not match the canonical gate order"
        raise GateRegistryError(message)

    ordered = [by_name[name] for name in GATE_ORDER]
    return tuple(ordered)


def run_gates(config: CheckConfig, *, only: str | None, skip: set[str] | frozenset[str]) -> int:
    """Run selected native gates without masking individual failures.

    Returns:
        Zero when all selected gates pass; otherwise a nonzero aggregate status.
    """
    available_gates = gates(config)
    selected = list(available_gates)
    if only is not None:
        selected = [gate for gate in available_gates if gate.name == only]
    if only is not None and not selected:
        sys.stderr.write(f"Unknown gate: {only}\n")
        return 2

    failures: list[str] = []
    for gate in selected:
        if gate.name in skip:
            write_header(f"{gate.name} skipped by explicit --skip")
            continue
        status = gate.run()
        if status != 0:
            failures.append(f"{gate.name}={status}")
    if failures:
        sys.stderr.write(f"\nFAILED iOS quality gates: {', '.join(failures)}\n")
        return 1
    sys.stdout.write("\nAll selected iOS quality gates passed.\n")
    return 0


def write_gate_list(config: CheckConfig) -> None:
    """Write all configured native gate names and descriptions."""
    for gate in gates(config):
        sys.stdout.write(f"{gate.name}: {gate.description}\n")
