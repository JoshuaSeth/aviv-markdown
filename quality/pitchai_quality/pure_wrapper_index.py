# Copyright (c) 2026 PitchAI. All rights reserved.
"""Build the repository-local callable index used by the wrapper checker."""

from __future__ import annotations

import ast
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator, Sequence
    from pathlib import Path

    from pitchai_quality.analysis_support import ParsedModule


@dataclass(frozen=True)
class FunctionDefinition:
    """One top-level or class-level function definition."""

    path: Path
    module: str
    qualname: str
    line: int

    @property
    def qualified_name(self) -> str:
        """Return the repository-qualified callable name."""
        return f"{self.module}.{self.qualname}"

    @property
    def display_name(self) -> str:
        """Return the concise callable name used in diagnostics."""
        return self.qualname


@dataclass(frozen=True)
class Violation:
    """One function that only forwards its parameters to another function."""

    definition: FunctionDefinition
    target: str
    call_line: int


@dataclass(frozen=True)
class CallableIndex:
    """Definitions plus resolvable repository-local aliases."""

    definitions: dict[str, FunctionDefinition]
    aliases: dict[str, str]

    def resolve(self, qualified_name: str) -> str | None:
        """Resolve an alias chain to a local function definition.

        Returns:
            The resolved local definition name, when one exists.
        """
        seen: set[str] = set()
        current = qualified_name
        while current in self.aliases:
            if current in seen:
                return None
            seen.add(current)
            current = self.aliases[current]
        return current if current in self.definitions else None

    def has_callables_below(self, module_name: str) -> bool:
        """Return whether a module prefix contains an indexed callable."""
        prefix = f"{module_name}."
        return any(name.startswith(prefix) for name in (*self.definitions, *self.aliases))


def _definition_specs(parsed: ParsedModule) -> Iterator[tuple[str, int]]:
    for statement in parsed.tree.body:
        if isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef):
            yield (statement.name, statement.lineno)
        if isinstance(statement, ast.ClassDef):
            for child in statement.body:
                if isinstance(child, ast.FunctionDef | ast.AsyncFunctionDef):
                    yield (f"{statement.name}.{child.name}", child.lineno)


def _definitions(parsed_modules: Sequence[ParsedModule]) -> dict[str, FunctionDefinition]:
    definitions: dict[str, FunctionDefinition] = {}
    for parsed in parsed_modules:
        for qualname, line in _definition_specs(parsed):
            definition = FunctionDefinition(path=parsed.path, module=parsed.module, qualname=qualname, line=line)
            definitions[definition.qualified_name] = definition
    return definitions


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


def _same_module_alias(
    statement: ast.stmt,
    *,
    parsed: ParsedModule,
    definitions: dict[str, FunctionDefinition],
) -> tuple[str, str] | None:
    target = _single_name_assignment_target(statement)
    value = _assignment_value(statement)
    if target is None or not isinstance(value, ast.Name):
        return None
    source = f"{parsed.module}.{value.id}"
    return (f"{parsed.module}.{target}", source) if source in definitions else None


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
    index = CallableIndex(definitions=definitions, aliases=aliases)
    for alias in statement.names:
        resolved = index.resolve(f"{statement.module}.{alias.name}")
        if resolved is not None:
            imported_aliases[f"{parsed.module}.{alias.asname or alias.name}"] = resolved
    return imported_aliases


def build_callable_index(parsed_modules: Sequence[ParsedModule]) -> CallableIndex:
    """Build definitions and aliases for all selected modules.

    Returns:
        A complete local callable index.
    """
    definitions = _definitions(parsed_modules)
    aliases: dict[str, str] = {}
    for parsed in parsed_modules:
        for statement in parsed.tree.body:
            alias = _same_module_alias(statement, parsed=parsed, definitions=definitions)
            if alias is not None:
                aliases[alias[0]] = alias[1]
            imported = _imported_function_aliases(
                statement,
                parsed=parsed,
                definitions=definitions,
                aliases=aliases,
            )
            aliases.update(imported)
    return CallableIndex(definitions=definitions, aliases=aliases)


def import_bindings(tree: ast.Module, index: CallableIndex) -> dict[str, str]:
    """Resolve import names visible within one module.

    Returns:
        Local names mapped to indexed callables or module prefixes.
    """
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
