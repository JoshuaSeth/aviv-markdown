#!/usr/bin/env python3
"""Fail on vague top-type soup in checked Python function signatures."""

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
    "tests",
    "venv",
}
ALLOW_MARKER = "pitchai-allow-vague-signature"
_ANY_IMPORT_MODULES = {"typing", "typing_extensions"}


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    name: str
    annotation: str
    reason: str


class _Visitor(ast.NodeVisitor):
    def __init__(self, path: Path, source: str) -> None:
        self.path = path
        self.source = source
        self.violations: list[Violation] = []

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        self._check_function(node)
        self.generic_visit(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        self._check_function(node)
        self.generic_visit(node)

    def _check_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        if _node_has_allow_marker(self.source, node):
            return

        arguments = [*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs]
        if node.args.vararg is not None:
            arguments.append(node.args.vararg)
        if node.args.kwarg is not None:
            arguments.append(node.args.kwarg)

        for arg in arguments:
            if arg.annotation is None:
                continue
            self._check_annotation(arg.annotation, node.name, arg.lineno)

        if node.returns is not None:
            self._check_annotation(node.returns, node.name, node.lineno)

    def _check_annotation(self, annotation: ast.AST, function_name: str, line: int) -> None:
        reason = _vague_reason(annotation)
        if reason is None:
            return
        self.violations.append(
            Violation(
                path=self.path,
                line=line,
                name=function_name,
                annotation=ast.unparse(annotation),
                reason=reason,
            )
        )


def _node_has_allow_marker(source: str, node: ast.AST) -> bool:
    lines = source.splitlines()
    start = max(getattr(node, "lineno", 1) - 2, 0)
    end = min(getattr(node, "lineno", 1) + 1, len(lines))
    return any(ALLOW_MARKER in line for line in lines[start:end])


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
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(path))
    visitor = _Visitor(path, source)
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
            print(
                f"{rel}:{violation.line}: {violation.name}: vague annotation `{violation.annotation}` ({violation.reason})",
                file=sys.stderr,
            )
        return 1

    print("ok no_vague_signatures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
