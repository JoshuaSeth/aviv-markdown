#!/usr/bin/env python3
"""Fail on functions that are only pass-through wrappers around another function."""

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
    qualname: str
    line: int

    @property
    def qualified_name(self) -> str:
        return f"{self.module}.{self.qualname}"

    @property
    def display_name(self) -> str:
        return self.qualname


@dataclass(frozen=True)
class ParsedModule:
    path: Path
    module: str
    tree: ast.Module


@dataclass(frozen=True)
class Violation:
    definition: FunctionDefinition
    target: str
    call_line: int


@dataclass(frozen=True)
class _CallableIndex:
    definitions: dict[str, FunctionDefinition]
    aliases: dict[str, str]

    def resolve(self, qualified_name: str) -> str | None:
        seen: set[str] = set()
        current = qualified_name
        while current in self.aliases:
            if current in seen:
                return None
            seen.add(current)
            current = self.aliases[current]
        return current if current in self.definitions else None

    def has_callables_below(self, module_name: str) -> bool:
        prefix = f"{module_name}."
        return any(name.startswith(prefix) for name in (*self.definitions, *self.aliases))


@dataclass(frozen=True)
class _ParameterSet:
    regular: frozenset[str]
    vararg: str | None
    kwarg: str | None


@dataclass(frozen=True)
class _FunctionScope:
    module: str
    class_name: str | None


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


def _definitions(parsed_modules: Sequence[ParsedModule]) -> dict[str, FunctionDefinition]:
    definitions: dict[str, FunctionDefinition] = {}
    for parsed in parsed_modules:
        for statement in parsed.tree.body:
            if isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef):
                _add_definition(definitions, parsed=parsed, qualname=statement.name, line=statement.lineno)
            elif isinstance(statement, ast.ClassDef):
                for child in statement.body:
                    if isinstance(child, ast.FunctionDef | ast.AsyncFunctionDef):
                        _add_definition(
                            definitions,
                            parsed=parsed,
                            qualname=f"{statement.name}.{child.name}",
                            line=child.lineno,
                        )
    return definitions


def _add_definition(definitions: dict[str, FunctionDefinition], *, parsed: ParsedModule, qualname: str, line: int) -> None:
    definition = FunctionDefinition(path=parsed.path, module=parsed.module, qualname=qualname, line=line)
    definitions[definition.qualified_name] = definition


def _callable_index(parsed_modules: Sequence[ParsedModule]) -> _CallableIndex:
    definitions = _definitions(parsed_modules)
    aliases: dict[str, str] = {}
    for parsed in parsed_modules:
        for statement in parsed.tree.body:
            alias = _same_module_alias(statement, parsed=parsed, definitions=definitions)
            if alias is not None:
                aliases[alias[0]] = alias[1]
            aliases.update(_imported_function_aliases(statement, parsed=parsed, definitions=definitions, aliases=aliases))
    return _CallableIndex(definitions=definitions, aliases=aliases)


def _same_module_alias(
    statement: ast.stmt,
    *,
    parsed: ParsedModule,
    definitions: dict[str, FunctionDefinition],
) -> tuple[str, str] | None:
    target = _single_name_assignment_target(statement)
    if target is None:
        return None
    value = _assignment_value(statement)
    if not isinstance(value, ast.Name):
        return None
    source = f"{parsed.module}.{value.id}"
    if source not in definitions:
        return None
    return (f"{parsed.module}.{target}", source)


def _single_name_assignment_target(statement: ast.stmt) -> str | None:
    if isinstance(statement, ast.Assign) and len(statement.targets) == 1 and isinstance(statement.targets[0], ast.Name):
        return statement.targets[0].id
    if isinstance(statement, ast.AnnAssign) and isinstance(statement.target, ast.Name):
        return statement.target.id
    return None


def _assignment_value(statement: ast.stmt) -> ast.AST | None:
    if isinstance(statement, ast.Assign):
        return statement.value
    if isinstance(statement, ast.AnnAssign):
        return statement.value
    return None


def _imported_function_aliases(
    statement: ast.stmt,
    *,
    parsed: ParsedModule,
    definitions: dict[str, FunctionDefinition],
    aliases: dict[str, str],
) -> dict[str, str]:
    imported_aliases: dict[str, str] = {}
    if not isinstance(statement, ast.ImportFrom) or statement.module is None:
        return imported_aliases
    index = _CallableIndex(definitions=definitions, aliases=aliases)
    for alias in statement.names:
        imported = f"{statement.module}.{alias.name}"
        resolved = index.resolve(imported)
        if resolved is not None:
            imported_aliases[f"{parsed.module}.{alias.asname or alias.name}"] = resolved
    return imported_aliases


def _import_bindings(tree: ast.Module, index: _CallableIndex) -> dict[str, str]:
    bindings: dict[str, str] = {}
    for statement in tree.body:
        if isinstance(statement, ast.Import):
            for alias in statement.names:
                if index.has_callables_below(alias.name):
                    bindings[alias.asname or alias.name.split(".", maxsplit=1)[0]] = alias.name
        elif isinstance(statement, ast.ImportFrom) and statement.module is not None:
            for alias in statement.names:
                imported = f"{statement.module}.{alias.name}"
                resolved = index.resolve(imported)
                if resolved is not None:
                    bindings[alias.asname or alias.name] = resolved
                elif index.has_callables_below(imported):
                    bindings[alias.asname or alias.name] = imported
    return bindings


def _effective_body(node: ast.FunctionDef | ast.AsyncFunctionDef) -> list[ast.stmt]:
    body = list(node.body)
    if body and _is_docstring_statement(body[0]):
        body = body[1:]
    return body


def _is_docstring_statement(node: ast.stmt) -> bool:
    return (
        isinstance(node, ast.Expr)
        and isinstance(node.value, ast.Constant)
        and isinstance(node.value.value, str)
    )


def _call_from_statement(statement: ast.stmt) -> ast.Call | None:
    value: ast.AST | None
    if isinstance(statement, ast.Return):
        value = statement.value
    elif isinstance(statement, ast.Expr):
        value = statement.value
    else:
        return None
    if isinstance(value, ast.Await):
        value = value.value
    return value if isinstance(value, ast.Call) else None


def _parameters(node: ast.FunctionDef | ast.AsyncFunctionDef) -> _ParameterSet:
    return _ParameterSet(
        regular=frozenset(argument.arg for argument in (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs)),
        vararg=node.args.vararg.arg if node.args.vararg is not None else None,
        kwarg=node.args.kwarg.arg if node.args.kwarg is not None else None,
    )


def _call_uses_only_parameters(call: ast.Call, parameters: _ParameterSet) -> bool:
    return all(_argument_is_parameter(argument, parameters) for argument in call.args) and all(
        _keyword_value_is_parameter(keyword, parameters) for keyword in call.keywords
    )


def _name_is_parameter(name: str, parameters: _ParameterSet) -> bool:
    return name in parameters.regular or name == parameters.vararg or name == parameters.kwarg


def _argument_is_parameter(argument: ast.AST, parameters: _ParameterSet) -> bool:
    if isinstance(argument, ast.Name):
        return _name_is_parameter(argument.id, parameters)
    if isinstance(argument, ast.Starred) and isinstance(argument.value, ast.Name):
        return argument.value.id == parameters.vararg
    return False


def _keyword_value_is_parameter(keyword: ast.keyword, parameters: _ParameterSet) -> bool:
    if keyword.arg is None and isinstance(keyword.value, ast.Name):
        return keyword.value.id == parameters.kwarg
    return isinstance(keyword.value, ast.Name) and _name_is_parameter(keyword.value.id, parameters)


def _resolve_call_target(
    call: ast.Call,
    scope: _FunctionScope,
    parameters: _ParameterSet,
    index: _CallableIndex,
    bindings: dict[str, str],
) -> str | None:
    if isinstance(call.func, ast.Name):
        same_module = f"{scope.module}.{call.func.id}"
        return index.resolve(same_module) or _resolve_bound_name(call.func.id, index=index, bindings=bindings)
    if isinstance(call.func, ast.Attribute):
        return _resolve_attribute_target(call.func, scope=scope, parameters=parameters, index=index, bindings=bindings)
    return None


def _resolve_bound_name(name: str, *, index: _CallableIndex, bindings: dict[str, str]) -> str | None:
    bound = bindings.get(name)
    if bound is None:
        return None
    return index.resolve(bound)


def _resolve_attribute_target(
    node: ast.Attribute,
    *,
    scope: _FunctionScope,
    parameters: _ParameterSet,
    index: _CallableIndex,
    bindings: dict[str, str],
) -> str | None:
    dotted = _attribute_dotted_name(node)
    if dotted is None:
        return None
    receiver_target = _resolve_same_class_receiver(dotted, scope=scope, parameters=parameters, index=index)
    return receiver_target or _resolve_dotted_name(dotted, index=index, bindings=bindings)


def _resolve_same_class_receiver(
    dotted: str,
    *,
    scope: _FunctionScope,
    parameters: _ParameterSet,
    index: _CallableIndex,
) -> str | None:
    if scope.class_name is None:
        return None
    parts = dotted.split(".")
    if len(parts) < 2:
        return None
    receiver = parts[0]
    method = parts[-1]
    if receiver in parameters.regular or receiver in {scope.class_name, "cls"}:
        return index.resolve(f"{scope.module}.{scope.class_name}.{method}")
    return None


def _resolve_dotted_name(dotted: str, *, index: _CallableIndex, bindings: dict[str, str]) -> str | None:
    parts = dotted.split(".")
    for split_at in range(len(parts) - 1, 0, -1):
        prefix = ".".join(parts[:split_at])
        suffix = ".".join(parts[split_at:])
        bound_prefix = bindings.get(prefix, prefix)
        resolved = index.resolve(f"{bound_prefix}.{suffix}")
        if resolved is not None:
            return resolved
    return index.resolve(dotted)


def _attribute_dotted_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _attribute_dotted_name(node.value)
        return f"{parent}.{node.attr}" if parent else None
    return None


def _find_violations(parsed_modules: Sequence[ParsedModule]) -> list[Violation]:
    index = _callable_index(parsed_modules)
    violations: list[Violation] = []
    for parsed in parsed_modules:
        bindings = _import_bindings(parsed.tree, index)
        _add_module_violations(violations, parsed=parsed, index=index, bindings=bindings)
    return violations


def _add_module_violations(
    violations: list[Violation],
    *,
    parsed: ParsedModule,
    index: _CallableIndex,
    bindings: dict[str, str],
) -> None:
    for statement in parsed.tree.body:
        if isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef):
            _add_function_violation(
                violations,
                node=statement,
                scope=_FunctionScope(module=parsed.module, class_name=None),
                index=index,
                bindings=bindings,
            )
        elif isinstance(statement, ast.ClassDef):
            for child in statement.body:
                if isinstance(child, ast.FunctionDef | ast.AsyncFunctionDef):
                    _add_function_violation(
                        violations,
                        node=child,
                        scope=_FunctionScope(module=parsed.module, class_name=statement.name),
                        index=index,
                        bindings=bindings,
                    )


def _add_function_violation(
    violations: list[Violation],
    *,
    node: ast.FunctionDef | ast.AsyncFunctionDef,
    scope: _FunctionScope,
    index: _CallableIndex,
    bindings: dict[str, str],
) -> None:
    if node.decorator_list:
        return
    body = _effective_body(node)
    if len(body) != 1:
        return
    call = _call_from_statement(body[0])
    parameters = _parameters(node)
    if call is None or not _call_uses_only_parameters(call, parameters):
        return
    target = _resolve_call_target(call, scope, parameters, index, bindings)
    definition = index.definitions[_definition_name(scope, node.name)]
    if target is not None and target != definition.qualified_name:
        violations.append(Violation(definition=definition, target=target, call_line=call.lineno))


def _definition_name(scope: _FunctionScope, name: str) -> str:
    qualname = name if scope.class_name is None else f"{scope.class_name}.{name}"
    return f"{scope.module}.{qualname}"


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
            print(
                f"{_relative(definition.path)}:{definition.line}: {definition.display_name}: "
                "pure wrapper function is forbidden; call the leaf function directly instead of keeping a wrapper "
                f"(wraps `{violation.target}` at line {violation.call_line})",
                file=sys.stderr,
            )
        return 1

    print("ok no_pure_wrapper_functions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
