#!/usr/bin/env python3
"""Fail on tiny helper functions that hide one expression or one guarded call."""

from __future__ import annotations

import argparse
import ast
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCAN_ROOTS = (
    REPO_ROOT / "domain_checks",
    REPO_ROOT / "e2e_registry",
    REPO_ROOT / "e2e_runner",
    REPO_ROOT / "e2e_sandbox",
)
EXCLUDED_PARTS = {
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".semgrep",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "test_support",
    "tests",
    "venv",
}


@dataclass(frozen=True)
class FunctionDefinition:
    path: Path
    module: str
    name: str
    line: int
    statement: ast.stmt

    @property
    def qualified_name(self) -> str:
        return f"{self.module}.{self.name}"


@dataclass(frozen=True)
class FunctionUse:
    path: Path
    line: int
    expression: str


@dataclass(frozen=True)
class Violation:
    definition: FunctionDefinition
    uses: tuple[FunctionUse, ...]
    reason: str


@dataclass(frozen=True)
class ParsedModule:
    path: Path
    module: str
    tree: ast.Module


def _module_name(path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        relative = resolved.relative_to(REPO_ROOT)
    except ValueError:
        relative = Path(resolved.name)
    parts = relative.with_suffix("").parts
    if parts[-1] == "__init__":
        parts = parts[:-1]
    return ".".join(parts)


def _iter_python_files(paths: Iterable[Path]) -> Iterable[Path]:
    for path in paths:
        if any(part in EXCLUDED_PARTS for part in path.parts):
            continue
        if path.is_file() and path.suffix in {".py", ".pyi"}:
            yield path
        elif path.is_dir():
            for child in path.rglob("*.py"):
                if child.is_file() and not any(part in EXCLUDED_PARTS for part in child.parts):
                    yield child
            for child in path.rglob("*.pyi"):
                if child.is_file() and not any(part in EXCLUDED_PARTS for part in child.parts):
                    yield child


def _parse_modules(paths: Iterable[Path]) -> tuple[ParsedModule, ...]:
    modules: list[ParsedModule] = []
    for path in _iter_python_files(paths):
        source = path.read_text(encoding="utf-8")
        modules.append(ParsedModule(path=path, module=_module_name(path), tree=ast.parse(source, filename=str(path))))
    return tuple(modules)


def _candidate_statement_after_docstring(node: ast.FunctionDef | ast.AsyncFunctionDef) -> ast.stmt | None:
    body = list(node.body)
    if body and _is_docstring_statement(body[0]):
        body = body[1:]
    if len(body) != 1:
        return None
    statement = body[0]
    if not _is_single_line_statement(statement) and not _is_guarded_call_statement(statement):
        return None
    return statement


def _is_single_line_statement(statement: ast.stmt) -> bool:
    return getattr(statement, "lineno", None) == getattr(statement, "end_lineno", None)


def _is_guarded_call_statement(statement: ast.stmt) -> bool:
    if not isinstance(statement, ast.If) or statement.orelse or len(statement.body) != 1:
        return False
    call_statement = statement.body[0]
    return isinstance(call_statement, ast.Expr) and _call_value(call_statement.value) is not None


def _call_value(value: ast.AST) -> ast.Call | None:
    if isinstance(value, ast.Await):
        value = value.value
    return value if isinstance(value, ast.Call) else None


def _is_docstring_statement(node: ast.stmt) -> bool:
    return (
        isinstance(node, ast.Expr)
        and isinstance(node.value, ast.Constant)
        and isinstance(node.value.value, str)
    )


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


class _UseVisitor(ast.NodeVisitor):
    def __init__(self, parsed: ParsedModule, candidates: dict[str, FunctionDefinition]) -> None:
        self.parsed = parsed
        self.candidates = candidates
        self.local_bindings = _import_bindings(parsed.tree, candidates)
        self.uses: dict[str, list[FunctionUse]] = {key: [] for key in candidates}

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        self._visit_function_body(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        self._visit_function_body(node)

    def visit_Name(self, node: ast.Name) -> None:  # noqa: N802
        if isinstance(node.ctx, ast.Load):
            qualified_name = self._resolve_name(node.id)
            if qualified_name is not None:
                self._record_use(qualified_name, node.lineno, node.id)

    def visit_Attribute(self, node: ast.Attribute) -> None:  # noqa: N802
        if isinstance(node.ctx, ast.Load):
            qualified_name = self._resolve_attribute(node)
            if qualified_name is not None:
                self._record_use(qualified_name, node.lineno, ast.unparse(node))
                return
        self.generic_visit(node)

    def _visit_function_body(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        for default in (*node.args.defaults, *node.args.kw_defaults):
            if default is not None:
                self.visit(default)
        for decorator in node.decorator_list:
            self.visit(decorator)
        if node.returns is not None:
            self.visit(node.returns)
        for statement in node.body:
            self.visit(statement)

    def _resolve_name(self, name: str) -> str | None:
        same_module = f"{self.parsed.module}.{name}"
        if same_module in self.candidates:
            return same_module
        imported = self.local_bindings.get(name)
        return imported if imported in self.candidates else None

    def _resolve_attribute(self, node: ast.Attribute) -> str | None:
        prefix = _attribute_base_name(node.value)
        if prefix is None:
            return None
        module_name = self.local_bindings.get(prefix, prefix)
        qualified_name = f"{module_name}.{node.attr}"
        return qualified_name if qualified_name in self.candidates else None

    def _record_use(self, qualified_name: str, line: int, expression: str) -> None:
        definition = self.candidates[qualified_name]
        if self.parsed.path == definition.path and line == definition.line:
            return
        self.uses[qualified_name].append(FunctionUse(path=self.parsed.path, line=line, expression=expression))


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
        visitor = _UseVisitor(parsed, candidates)
        visitor.visit(parsed.tree)
        for qualified_name, found_uses in visitor.uses.items():
            uses[qualified_name].extend(found_uses)

    violations: list[Violation] = []
    for qualified_name, found_uses in uses.items():
        if _is_guarded_call_statement(candidates[qualified_name].statement):
            violations.append(
                Violation(
                    definition=candidates[qualified_name],
                    uses=tuple(found_uses),
                    reason="guarded_call",
                )
            )
            continue
        if len(found_uses) <= 1:
            violations.append(
                Violation(
                    definition=candidates[qualified_name],
                    uses=tuple(found_uses),
                    reason="low_runtime_use",
                )
            )
            continue
        if _is_chained_lookup_statement(candidates[qualified_name].statement):
            violations.append(
                Violation(
                    definition=candidates[qualified_name],
                    uses=tuple(found_uses),
                    reason="chained_lookup",
                )
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


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="Optional files or folders. Defaults to runtime roots.")
    return parser


def _relative(path: Path) -> Path:
    return path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(list(argv) if argv is not None else None)
    roots = tuple(Path(raw).resolve(strict=False) for raw in args.paths) if args.paths else DEFAULT_SCAN_ROOTS
    violations = _find_violations(_parse_modules(roots))

    if violations:
        for violation in violations:
            definition = violation.definition
            if violation.reason == "guarded_call":
                print(
                    f"{_relative(definition.path)}:{definition.line}: {definition.name}: "
                    "guarded-call helper function is not allowed; keep the `if` and the side-effect call at the call "
                    "site so the condition, side effect, and surrounding context stay visible "
                    f"(runtime uses: {len(violation.uses)})",
                    file=sys.stderr,
                )
            elif violation.reason == "chained_lookup":
                print(
                    f"{_relative(definition.path)}:{definition.line}: {definition.name}: "
                    "single-line helper function is not allowed when it only performs a chained lookup on a freshly "
                    "computed value; name the computed value at the call site, then call `.get(...)` on that variable "
                    f"(runtime uses: {len(violation.uses)})",
                    file=sys.stderr,
                )
            elif violation.uses:
                use = violation.uses[0]
                print(
                    f"{_relative(definition.path)}:{definition.line}: {definition.name}: "
                    "single-line helper function is not allowed with only one runtime caller; replace it with "
                    "named variable(s) at the use site, preferably named from the helper function. Keep a function "
                    "when it owns a real procedure or boundary, not merely to name one expression "
                    f"(only runtime use: {_relative(use.path)}:{use.line} `{use.expression}`)",
                    file=sys.stderr,
                )
            else:
                print(
                    f"{_relative(definition.path)}:{definition.line}: {definition.name}: "
                    "single-line helper function is not allowed with zero runtime callers; remove it, or name the "
                    "expression locally in the test/caller that needs it. Keep a function only when it owns a real "
                    "procedure or reusable boundary.",
                    file=sys.stderr,
                )
        return 1

    print("ok no_single_use_one_line_functions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
