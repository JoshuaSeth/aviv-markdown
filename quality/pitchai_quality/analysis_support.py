# Copyright (c) 2026 PitchAI. All rights reserved.
"""Shared source parsing and command-line support for preference checkers."""

from __future__ import annotations

import argparse
import ast
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from pitchai_quality.source_files import REPOSITORY_ROOT, iter_python_files

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable, Sequence

_SOURCE_CONTAINER_NAMES = {"quality", "src"}


@dataclass(frozen=True)
class ParsedModule:
    """One parsed Python source module and its repository identity."""

    path: Path
    module: str
    tree: ast.Module


def _module_name(path: Path) -> str:
    resolved = path.resolve(strict=False)
    relative = (
        resolved.relative_to(REPOSITORY_ROOT) if resolved.is_relative_to(REPOSITORY_ROOT) else Path(resolved.name)
    )
    parts = relative.with_suffix("").parts
    if parts and parts[0] in _SOURCE_CONTAINER_NAMES:
        parts = parts[1:]
    if parts[-1] == "__init__":
        parts = parts[:-1]
    return ".".join(parts)


def parse_modules(paths: Iterable[Path]) -> tuple[ParsedModule, ...]:
    """Parse every selected Python file in deterministic path order.

    Returns:
        Parsed modules in deterministic path order.
    """
    modules: list[ParsedModule] = []
    for path in iter_python_files(paths):
        source = path.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(path))
        modules.append(ParsedModule(path=path, module=_module_name(path), tree=tree))
    return tuple(modules)


def function_body_without_docstring(node: ast.FunctionDef | ast.AsyncFunctionDef) -> list[ast.stmt]:
    """Return a function body after removing its optional leading docstring."""
    body = list(node.body)
    first_statement = body[0] if body else None
    is_docstring = (
        isinstance(first_statement, ast.Expr)
        and isinstance(first_statement.value, ast.Constant)
        and isinstance(first_statement.value.value, str)
    )
    return body[1:] if is_docstring else body


def collect_file_violations[ViolationT](
    paths: Iterable[Path],
    checker: Callable[[Path], Iterable[ViolationT]],
) -> list[ViolationT]:
    """Collect typed checker violations across the complete source selection.

    Returns:
        Violations from every selected Python source file.
    """
    violations: list[ViolationT] = []
    for path in iter_python_files(paths):
        violations.extend(checker(path))
    return violations


def checker_parser(description: str) -> argparse.ArgumentParser:
    """Build the common preference-checker command-line parser.

    Returns:
        A parser accepting optional repository paths.
    """
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("paths", nargs="*", help="Optional files or folders. Defaults to the repository root.")
    return parser


def scan_roots(raw_paths: Sequence[str]) -> tuple[Path, ...]:
    """Resolve selected paths or return the complete repository root.

    Returns:
        Absolute scan roots.
    """
    if not raw_paths:
        return (REPOSITORY_ROOT,)
    resolved_paths = (Path(raw).resolve(strict=False) for raw in raw_paths)
    return tuple(resolved_paths)


def relative_path(path: Path) -> Path:
    """Return a stable repository-relative display path when possible."""
    return path.relative_to(REPOSITORY_ROOT) if path.is_relative_to(REPOSITORY_ROOT) else path


def write_failure(message: str) -> None:
    """Write one checker failure line to standard error."""
    sys.stderr.write(f"{message}\n")


def write_success(message: str) -> None:
    """Write one checker success line to standard output."""
    sys.stdout.write(f"{message}\n")
