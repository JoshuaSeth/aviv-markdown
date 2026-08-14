# Copyright (c) 2026 PitchAI. All rights reserved.
"""Fail on dense inline comprehensions that should be named in steps."""

from __future__ import annotations

import ast
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast

from pitchai_quality.analysis_support import (
    checker_parser,
    parse_modules,
    relative_path,
    scan_roots,
    write_failure,
    write_success,
)

if TYPE_CHECKING:
    from collections.abc import Iterable, Sequence
    from pathlib import Path

    from pitchai_quality.analysis_support import ParsedModule

_NESTED_CALL_THRESHOLD = 2
ADVICE = """Preferred shape:
all_paths_in_dir = root.iterdir()
directories_in_dir = (path for path in all_paths_in_dir if path.is_dir())
queued_agent_paths = (path for path in directories_in_dir if queued_prompt_paths(path))
queued_agent_names = (path.name for path in queued_agent_paths)
return tuple(sorted(queued_agent_names))

Principle: prefer vertical named steps. A short single-line comprehension is good when it does one thing. When the logic
does several things, make the code vertically longer on purpose: source lookup, each filter, mapping, and final
materialization should each get a short named value."""


@dataclass(frozen=True)
class Violation:
    """One dense comprehension and the reason it should be expanded."""

    path: Path
    line: int
    column: int
    reason: str


def _parent_map(tree: ast.AST) -> dict[ast.AST, ast.AST]:
    parents: dict[ast.AST, ast.AST] = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[child] = node
    return parents


def _ancestors(node: ast.AST, parents: dict[ast.AST, ast.AST]) -> tuple[ast.AST, ...]:
    ancestors: list[ast.AST] = []
    current = node
    while current in parents:
        current = parents[current]
        ancestors.append(current)
    return tuple(ancestors)


def _comprehensions(tree: ast.AST) -> Iterable[ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp]:
    for node in ast.walk(tree):
        if isinstance(node, ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp):
            yield node


def _call_ancestor_count(ancestors: Sequence[ast.AST]) -> int:
    count = 0
    for ancestor in ancestors:
        if isinstance(ancestor, ast.stmt):
            break
        if isinstance(ancestor, ast.Call):
            count += 1
    return count


def _is_inside_inline_conditional_with_call(ancestors: Sequence[ast.AST]) -> bool:
    has_call = False
    for ancestor in ancestors:
        if isinstance(ancestor, ast.stmt):
            return False
        if isinstance(ancestor, ast.Call):
            has_call = True
        elif isinstance(ancestor, ast.IfExp):
            return has_call
    return False


def _projects_target_value(node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp, target: ast.AST) -> bool:
    if not isinstance(target, ast.Name) or isinstance(node, ast.DictComp):
        return True
    if not isinstance(node.elt, ast.Name):
        return True
    return node.elt.id != target.id


def _has_compound_filter(node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp) -> bool:
    filter_count = sum(len(generator.ifs) for generator in node.generators)
    if filter_count > 1:
        return True
    return any(isinstance(condition, ast.BoolOp) for generator in node.generators for condition in generator.ifs)


def _assigned_comprehension_reason(
    node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp,
    ancestors: Sequence[ast.AST],
) -> str | None:
    is_direct_assignment = bool(ancestors) and isinstance(ancestors[0], ast.Assign | ast.AnnAssign)
    if not is_direct_assignment:
        return None
    if not node.generators:
        return None
    generator = node.generators[0]
    has_source_lookup = not isinstance(generator.iter, ast.Name | ast.Attribute | ast.Subscript)
    has_projection = _projects_target_value(node, generator.target)
    has_filter = any(item.ifs for item in node.generators)
    if _has_compound_filter(node):
        return "assigned comprehension has a compound filter; split each filter into a short named vertical step"
    responsibility_count = sum((has_source_lookup, has_projection, has_filter))
    if responsibility_count > 1:
        return (
            "assigned comprehension still does multiple things; use multiple short named comprehensions for source "
            "lookup, filtering, mapping, and final materialization"
        )
    return None


def _violation_reason(
    node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp,
    ancestors: Sequence[ast.AST],
) -> str | None:
    contains_named_expression = False
    for child in ast.walk(node):
        if isinstance(child, ast.NamedExpr):
            contains_named_expression = True
            break
    if contains_named_expression:
        return "walrus inside comprehension makes compute-and-filter logic too dense"
    if _call_ancestor_count(ancestors) >= _NESTED_CALL_THRESHOLD:
        return "comprehension is hidden inside nested calls; name the computed values before final materialization"
    if _is_inside_inline_conditional_with_call(ancestors):
        return (
            "comprehension is mixed with an inline conditional and a call; split the condition and values into named "
            "steps"
        )
    return _assigned_comprehension_reason(node, ancestors)


def _find_violations(parsed_modules: Sequence[ParsedModule]) -> list[Violation]:
    violations: list[Violation] = []
    seen: set[tuple[Path, int, int]] = set()
    for parsed in parsed_modules:
        parents = _parent_map(parsed.tree)
        for node in _comprehensions(parsed.tree):
            reason = _violation_reason(node, _ancestors(node, parents))
            if reason is None:
                continue
            key = (parsed.path, node.lineno, node.col_offset)
            if key in seen:
                continue
            seen.add(key)
            violations.append(Violation(path=parsed.path, line=node.lineno, column=node.col_offset + 1, reason=reason))
    return violations


def main(argv: Sequence[str] | None = None) -> int:
    """Run the dense-comprehension checker.

    Returns:
        Zero when no violations exist; otherwise one.
    """
    args = checker_parser("Reject dense inline comprehensions.").parse_args(list(argv) if argv is not None else None)
    raw_paths = cast("list[str]", args.paths)
    violations = _find_violations(parse_modules(scan_roots(raw_paths)))

    if violations:
        for violation in violations:
            write_failure(
                f"{relative_path(violation.path)}:{violation.line}:{violation.column}: "
                f"dense inline comprehension is not allowed; {violation.reason}",
            )
        write_failure(f"\n{ADVICE}")
        return 1

    write_success("ok no_dense_inline_comprehensions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
