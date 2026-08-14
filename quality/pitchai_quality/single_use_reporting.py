# Copyright (c) 2026 PitchAI. All rights reserved.
"""Data and diagnostics for the single-use helper checker."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from pitchai_quality.analysis_support import relative_path

if TYPE_CHECKING:
    import ast
    from pathlib import Path


@dataclass(frozen=True)
class FunctionDefinition:
    """One candidate helper function."""

    path: Path
    module: str
    name: str
    line: int
    statement: ast.stmt


@dataclass(frozen=True)
class FunctionUse:
    """One runtime reference to a candidate helper."""

    path: Path
    line: int
    expression: str


@dataclass(frozen=True)
class Violation:
    """One helper that does not justify a function boundary."""

    definition: FunctionDefinition
    uses: tuple[FunctionUse, ...]
    reason: str


def violation_message(violation: Violation) -> str:
    """Render the actionable diagnostic for one helper violation.

    Returns:
        A complete source-located remediation message.
    """
    definition = violation.definition
    location = f"{relative_path(definition.path)}:{definition.line}: {definition.name}: "
    if violation.reason == "guarded_call":
        return (
            f"{location}guarded-call helper function is not allowed; keep the `if` and the side-effect call at the "
            "call site so the condition, side effect, and surrounding context stay visible "
            f"(runtime uses: {len(violation.uses)})"
        )
    if violation.reason == "chained_lookup":
        return (
            f"{location}single-line helper function is not allowed when it only performs a chained lookup on a "
            "freshly computed value; name the computed value at the call site, then call `.get(...)` on that variable "
            f"(runtime uses: {len(violation.uses)})"
        )
    if violation.uses:
        use = violation.uses[0]
        return (
            f"{location}single-line helper function is not allowed with only one runtime caller; replace it with "
            "named variable(s) at the use site, preferably named from the helper function. Keep a function when it "
            "owns a real procedure or boundary, not merely to name one expression "
            f"(only runtime use: {relative_path(use.path)}:{use.line} `{use.expression}`)"
        )
    return (
        f"{location}single-line helper function is not allowed with zero runtime callers; remove it, or name the "
        "expression locally in the test/caller that needs it. Keep a function only when it owns a real procedure or "
        "reusable boundary."
    )
