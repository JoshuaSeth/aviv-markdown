# Copyright (c) 2026 PitchAI. All rights reserved.
"""Fail on vague top-type soup in checked Python function signatures."""

from __future__ import annotations

import ast
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast

from pitchai_quality.analysis_support import (
    checker_parser,
    collect_file_violations,
    relative_path,
    scan_roots,
    write_failure,
    write_success,
)

if TYPE_CHECKING:
    from collections.abc import Sequence
    from pathlib import Path


@dataclass(frozen=True)
class Violation:
    """One vague public type annotation."""

    path: Path
    line: int
    name: str
    annotation: str
    reason: str


def _function_violations(path: Path, node: ast.FunctionDef | ast.AsyncFunctionDef) -> list[Violation]:
    arguments = [*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs]
    if node.args.vararg is not None:
        arguments.append(node.args.vararg)
    if node.args.kwarg is not None:
        arguments.append(node.args.kwarg)

    annotated_arguments = (argument for argument in arguments if argument.annotation is not None)
    annotations = [(cast("ast.expr", argument.annotation), argument.lineno) for argument in annotated_arguments]
    if node.returns is not None:
        annotations.append((node.returns, node.lineno))

    violations: list[Violation] = []
    for annotation, line in annotations:
        reason = _vague_reason(annotation)
        if reason is not None:
            violations.append(Violation(path, line, node.name, ast.unparse(annotation), reason))
    return violations


def _vague_reason(annotation: ast.AST) -> str | None:
    name = _annotation_name(annotation)
    if name == "Any" or name.endswith(".Any"):
        return "Any in signature"
    if name == "object" or name.endswith(".object"):
        return "object in signature"

    if isinstance(annotation, ast.Subscript):
        base = _annotation_name(annotation.value)
        slice_node = annotation.slice
        slice_values = slice_node.elts if isinstance(slice_node, ast.Tuple) else [slice_node]
        if base in {"dict", "Dict", "Mapping", "MutableMapping", "Sequence", "list", "tuple"}:
            for value in slice_values:
                value_name = _annotation_name(value)
                if value_name == "Any" or value_name.endswith(".Any"):
                    return f"{base}[..., Any] in signature"
                if value_name == "object" or value_name.endswith(".object"):
                    return f"{base}[..., object] in signature"
        for value in slice_values:
            nested = _vague_reason(value)
            if nested is not None:
                return nested
    return None


def _annotation_name(annotation: ast.AST) -> str:
    if isinstance(annotation, ast.Name):
        return annotation.id
    if isinstance(annotation, ast.Attribute):
        parent = _annotation_name(annotation.value)
        return f"{parent}.{annotation.attr}" if parent else annotation.attr
    if isinstance(annotation, ast.Constant) and isinstance(annotation.value, str):
        return annotation.value
    if isinstance(annotation, ast.Subscript):
        return _annotation_name(annotation.value)
    return ""


def _check_file(path: Path) -> list[Violation]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    nodes = ast.walk(tree)
    functions = (node for node in nodes if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef))
    return [violation for node in functions for violation in _function_violations(path, node)]


def main(argv: Sequence[str] | None = None) -> int:
    """Run the vague-signature checker.

    Returns:
        Zero when no violations exist; otherwise one.
    """
    args = checker_parser("Reject vague top-type function signatures.").parse_args(
        list(argv) if argv is not None else None,
    )
    raw_paths = cast("list[str]", args.paths)
    violations = collect_file_violations(scan_roots(raw_paths), _check_file)

    if violations:
        for violation in violations:
            write_failure(
                f"{relative_path(violation.path)}:{violation.line}: {violation.name}: "
                f"vague annotation `{violation.annotation}` ({violation.reason})",
            )
        return 1

    write_success("ok no_vague_signatures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
