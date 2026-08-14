# Copyright (c) 2026 PitchAI. All rights reserved.
"""Fail on functions that only pass parameters through to another function."""

from __future__ import annotations

import ast
from typing import TYPE_CHECKING, cast

from pitchai_quality.analysis_support import (
    checker_parser,
    function_body_without_docstring,
    parse_modules,
    relative_path,
    scan_roots,
    write_failure,
    write_success,
)
from pitchai_quality.pure_wrapper_index import Violation, build_callable_index, import_bindings
from pitchai_quality.pure_wrapper_resolution import FunctionScope, resolve_parameter_call_target

if TYPE_CHECKING:
    from collections.abc import Sequence

    from pitchai_quality.analysis_support import ParsedModule
    from pitchai_quality.pure_wrapper_index import CallableIndex


def _call_from_statement(statement: ast.stmt) -> ast.Call | None:
    if not isinstance(statement, ast.Return | ast.Expr):
        return None
    value = statement.value
    if isinstance(value, ast.Await):
        value = value.value
    return value if isinstance(value, ast.Call) else None


def _find_violations(parsed_modules: Sequence[ParsedModule]) -> list[Violation]:
    index = build_callable_index(parsed_modules)
    violations: list[Violation] = []
    for parsed in parsed_modules:
        bindings = import_bindings(parsed.tree, index)
        _add_module_violations(violations, parsed=parsed, index=index, bindings=bindings)
    return violations


def _add_module_violations(
    violations: list[Violation],
    *,
    parsed: ParsedModule,
    index: CallableIndex,
    bindings: dict[str, str],
) -> None:
    for statement in parsed.tree.body:
        if isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef):
            _add_function_violation(
                violations,
                node=statement,
                scope=FunctionScope(module=parsed.module, class_name=None),
                index=index,
                bindings=bindings,
            )
        if isinstance(statement, ast.ClassDef):
            for child in statement.body:
                if isinstance(child, ast.FunctionDef | ast.AsyncFunctionDef):
                    _add_function_violation(
                        violations,
                        node=child,
                        scope=FunctionScope(module=parsed.module, class_name=statement.name),
                        index=index,
                        bindings=bindings,
                    )


def _add_function_violation(
    violations: list[Violation],
    *,
    node: ast.FunctionDef | ast.AsyncFunctionDef,
    scope: FunctionScope,
    index: CallableIndex,
    bindings: dict[str, str],
) -> None:
    body = function_body_without_docstring(node)
    if node.decorator_list or len(body) != 1:
        return
    call = _call_from_statement(body[0])
    if call is None:
        return
    target = resolve_parameter_call_target(call, node, scope, index, bindings)
    qualname = node.name if scope.class_name is None else f"{scope.class_name}.{node.name}"
    definition = index.definitions[f"{scope.module}.{qualname}"]
    if target is not None and target != definition.qualified_name:
        violations.append(Violation(definition=definition, target=target, call_line=call.lineno))


def main(argv: Sequence[str] | None = None) -> int:
    """Run the pure-wrapper checker.

    Returns:
        Zero when no violations exist; otherwise one.
    """
    args = checker_parser("Reject repository-local pass-through wrappers.").parse_args(
        list(argv) if argv is not None else None,
    )
    raw_paths = cast("list[str]", args.paths)
    violations = _find_violations(parse_modules(scan_roots(raw_paths)))
    if violations:
        for violation in violations:
            definition = violation.definition
            write_failure(
                f"{relative_path(definition.path)}:{definition.line}: {definition.display_name}: "
                "pure wrapper function is forbidden; call the leaf function directly instead of keeping a wrapper "
                f"(wraps `{violation.target}` at line {violation.call_line})",
            )
        return 1
    write_success("ok no_pure_wrapper_functions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
