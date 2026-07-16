#!/usr/bin/env python3
"""Fail when runtime code creates nested asyncio event loops."""

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
ALLOWED_EDGE_FILES: set[Path] = set()


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    expression: str


class _Visitor(ast.NodeVisitor):
    def __init__(self, path: Path) -> None:
        self.path = path
        self.violations: list[Violation] = []

    def visit_Call(self, node: ast.Call) -> None:  # noqa: N802
        expression = _call_name(node.func)
        if expression in {
            "asyncio.run",
            "asyncio.new_event_loop",
            "asyncio.get_event_loop",
            "asyncio.get_event_loop_policy",
        } or expression.endswith(".run_until_complete"):
            self.violations.append(Violation(self.path, node.lineno, expression))
        self.generic_visit(node)


def _call_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _call_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    return ""


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


def _check_file(path: Path) -> list[Violation]:
    resolved = path.resolve(strict=False)
    if resolved in {allowed.resolve(strict=False) for allowed in ALLOWED_EDGE_FILES}:
        return []
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    visitor = _Visitor(path)
    visitor.visit(tree)
    return visitor.violations


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="Optional files or folders. Defaults to runtime roots.")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(list(argv) if argv is not None else None)
    roots = tuple(Path(raw).resolve(strict=False) for raw in args.paths) if args.paths else DEFAULT_SCAN_ROOTS
    violations: list[Violation] = []
    for path in _iter_python_files(roots):
        violations.extend(_check_file(path))

    if violations:
        for violation in violations:
            rel = violation.path.relative_to(REPO_ROOT) if violation.path.is_relative_to(REPO_ROOT) else violation.path
            print(f"{rel}:{violation.line}: nested event-loop creation is forbidden: {violation.expression}", file=sys.stderr)
        return 1

    print("ok nested_event_loops")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
