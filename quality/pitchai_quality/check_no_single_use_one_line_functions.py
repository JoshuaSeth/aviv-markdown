# Copyright (c) 2026 PitchAI. All rights reserved.
"""Fail on tiny helper functions that hide one expression or one guarded call."""

from __future__ import annotations

import ast
from typing import TYPE_CHECKING, cast

from pitchai_quality.analysis_support import (
    checker_parser,
    function_body_without_docstring,
    parse_modules,
    scan_roots,
    write_failure,
    write_success,
)
from pitchai_quality.single_use_reporting import FunctionDefinition, FunctionUse, Violation, violation_message

if TYPE_CHECKING:
    from collections.abc import Sequence

    from pitchai_quality.analysis_support import ParsedModule


def _candidate_statement_after_docstring(node: ast.FunctionDef | ast.AsyncFunctionDef) -> ast.stmt | None:
    body = function_body_without_docstring(node)
    if len(body) != 1:
        return None
    statement = body[0]
    is_single_line = statement.lineno == statement.end_lineno
    if not is_single_line and not _is_guarded_call_statement(statement):
        return None
    return statement


def _is_guarded_call_statement(statement: ast.stmt) -> bool:
    if not isinstance(statement, ast.If) or statement.orelse or len(statement.body) != 1:
        return False
    call_statement = statement.body[0]
    return isinstance(call_statement, ast.Expr) and _call_value(call_statement.value) is not None


def _call_value(value: ast.AST) -> ast.Call | None:
    if isinstance(value, ast.Await):
        value = value.value
    return value if isinstance(value, ast.Call) else None


def _candidate_definitions(parsed_modules: Sequence[ParsedModule]) -> dict[str, FunctionDefinition]:
    candidates: dict[str, FunctionDefinition] = {}
    for parsed in parsed_modules:
        for statement in parsed.tree.body:
            if not isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef):
                continue
            candidate_statement = _candidate_statement_after_docstring(statement)
            if candidate_statement is None:
                continue
            candidates[f"{parsed.module}.{statement.name}"] = FunctionDefinition(
                path=parsed.path,
                module=parsed.module,
                name=statement.name,
                line=statement.lineno,
                statement=candidate_statement,
            )
    return candidates


def _name_target(
    name: str,
    parsed: ParsedModule,
    candidates: dict[str, FunctionDefinition],
    bindings: dict[str, str],
) -> str | None:
    same_module = f"{parsed.module}.{name}"
    if same_module in candidates:
        return same_module
    imported = bindings.get(name)
    return imported if imported in candidates else None


def _attribute_target(
    node: ast.Attribute,
    candidates: dict[str, FunctionDefinition],
    bindings: dict[str, str],
) -> str | None:
    prefix = _attribute_base_name(node.value)
    if prefix is None:
        return None
    module_name = bindings.get(prefix, prefix)
    qualified_name = f"{module_name}.{node.attr}"
    return qualified_name if qualified_name in candidates else None


def _module_uses(parsed: ParsedModule, candidates: dict[str, FunctionDefinition]) -> dict[str, list[FunctionUse]]:
    bindings = _import_bindings(parsed.tree, candidates)
    uses: dict[str, list[FunctionUse]] = {key: [] for key in candidates}
    for node in ast.walk(parsed.tree):
        qualified_name: str | None = None
        expression = ""
        line = 0
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            qualified_name = _name_target(node.id, parsed, candidates, bindings)
            expression = node.id
            line = node.lineno
        elif isinstance(node, ast.Attribute) and isinstance(node.ctx, ast.Load):
            qualified_name = _attribute_target(node, candidates, bindings)
            expression = ast.unparse(node)
            line = node.lineno
        if qualified_name is None:
            continue
        definition = candidates[qualified_name]
        if parsed.path != definition.path or line != definition.line:
            uses[qualified_name].append(FunctionUse(path=parsed.path, line=line, expression=expression))
    return uses


def _attribute_base_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _attribute_base_name(node.value)
        return f"{parent}.{node.attr}" if parent else None
    return None


def _import_bindings(tree: ast.Module, candidates: dict[str, FunctionDefinition]) -> dict[str, str]:
    bindings: dict[str, str] = {}
    for statement in tree.body:
        if isinstance(statement, ast.Import):
            for alias in statement.names:
                if _has_candidate_with_module_prefix(alias.name, candidates):
                    bindings[alias.asname or alias.name.split(".", maxsplit=1)[0]] = alias.name
        elif isinstance(statement, ast.ImportFrom) and statement.module is not None:
            for alias in statement.names:
                imported = f"{statement.module}.{alias.name}"
                if imported in candidates or _has_candidate_with_module_prefix(imported, candidates):
                    bindings[alias.asname or alias.name] = imported
    return bindings


def _has_candidate_with_module_prefix(module_name: str, candidates: dict[str, FunctionDefinition]) -> bool:
    prefix = f"{module_name}."
    return any(candidate.startswith(prefix) for candidate in candidates)


def _find_violations(parsed_modules: Sequence[ParsedModule]) -> list[Violation]:
    candidates = _candidate_definitions(parsed_modules)
    uses: dict[str, list[FunctionUse]] = {key: [] for key in candidates}
    for parsed in parsed_modules:
        for qualified_name, found_uses in _module_uses(parsed, candidates).items():
            uses[qualified_name].extend(found_uses)

    violations: list[Violation] = []
    for qualified_name, found_uses in uses.items():
        if _is_guarded_call_statement(candidates[qualified_name].statement):
            violations.append(
                Violation(
                    definition=candidates[qualified_name],
                    uses=tuple(found_uses),
                    reason="guarded_call",
                ),
            )
            continue
        if len(found_uses) <= 1:
            violations.append(
                Violation(
                    definition=candidates[qualified_name],
                    uses=tuple(found_uses),
                    reason="low_runtime_use",
                ),
            )
            continue
        if _is_chained_lookup_statement(candidates[qualified_name].statement):
            violations.append(
                Violation(
                    definition=candidates[qualified_name],
                    uses=tuple(found_uses),
                    reason="chained_lookup",
                ),
            )
    return violations


def _is_chained_lookup_statement(statement: ast.stmt) -> bool:
    value = _statement_value(statement)
    if isinstance(value, ast.Await):
        value = value.value
    return (
        isinstance(value, ast.Call)
        and isinstance(value.func, ast.Attribute)
        and value.func.attr == "get"
        and isinstance(value.func.value, ast.Call)
    )


def _statement_value(statement: ast.stmt) -> ast.AST | None:
    if isinstance(statement, ast.Return):
        return statement.value
    if isinstance(statement, ast.Expr):
        return statement.value
    return None


def main(argv: Sequence[str] | None = None) -> int:
    """Run the single-use helper checker.

    Returns:
        Zero when no violations exist; otherwise one.
    """
    args = checker_parser("Reject single-use one-line helper functions.").parse_args(
        list(argv) if argv is not None else None,
    )
    raw_paths = cast("list[str]", args.paths)
    violations = _find_violations(parse_modules(scan_roots(raw_paths)))

    if violations:
        for violation in violations:
            write_failure(violation_message(violation))
        return 1

    write_success("ok no_single_use_one_line_functions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
