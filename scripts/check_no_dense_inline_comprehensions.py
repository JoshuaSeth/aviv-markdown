#!/usr/bin/env python3
"""Fail on dense inline comprehensions that should be named in steps."""

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
class ParsedModule:
    path: Path
    module: str
    tree: ast.Module


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    column: int
    reason: str


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


def _contains_named_expr(node: ast.AST) -> bool:
    return any(isinstance(child, ast.NamedExpr) for child in ast.walk(node))


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


def _is_direct_assignment(ancestors: Sequence[ast.AST]) -> bool:
    return bool(ancestors) and isinstance(ancestors[0], ast.Assign | ast.AnnAssign)


def _first_generator(node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp) -> ast.comprehension | None:
    return node.generators[0] if node.generators else None


def _is_named_source(node: ast.AST) -> bool:
    return isinstance(node, ast.Name | ast.Attribute | ast.Subscript)


def _target_name(target: ast.AST) -> str | None:
    return target.id if isinstance(target, ast.Name) else None


def _projects_target_value(node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp, target: ast.AST) -> bool:
    target_name = _target_name(target)
    if target_name is None or isinstance(node, ast.DictComp):
        return True
    if not isinstance(node.elt, ast.Name):
        return True
    return node.elt.id != target_name


def _has_filter(node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp) -> bool:
    return any(generator.ifs for generator in node.generators)


def _has_compound_filter(node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp) -> bool:
    filter_count = sum(len(generator.ifs) for generator in node.generators)
    if filter_count > 1:
        return True
    return any(isinstance(condition, ast.BoolOp) for generator in node.generators for condition in generator.ifs)


def _assigned_comprehension_reason(
    node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp,
    ancestors: Sequence[ast.AST],
) -> str | None:
    if not _is_direct_assignment(ancestors):
        return None
    generator = _first_generator(node)
    if generator is None:
        return None
    has_source_lookup = not _is_named_source(generator.iter)
    has_projection = _projects_target_value(node, generator.target)
    has_filter = _has_filter(node)
    if _has_compound_filter(node):
        return "assigned comprehension has a compound filter; split each filter into a short named vertical step"
    responsibility_count = sum((has_source_lookup, has_projection, has_filter))
    if responsibility_count > 1:
        return (
            "assigned comprehension still does multiple things; use multiple short named comprehensions for source lookup, "
            "filtering, mapping, and final materialization"
        )
    return None


def _violation_reason(node: ast.GeneratorExp | ast.ListComp | ast.SetComp | ast.DictComp, ancestors: Sequence[ast.AST]) -> str | None:
    if _contains_named_expr(node):
        return "walrus inside comprehension makes compute-and-filter logic too dense"
    if _call_ancestor_count(ancestors) >= 2:
        return "comprehension is hidden inside nested calls; name the computed values before final materialization"
    if _is_inside_inline_conditional_with_call(ancestors):
        return "comprehension is mixed with an inline conditional and a call; split the condition and values into named steps"
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
            print(
                f"{_relative(violation.path)}:{violation.line}:{violation.column}: "
                f"dense inline comprehension is not allowed; {violation.reason}",
                file=sys.stderr,
            )
        print(f"\n{ADVICE}", file=sys.stderr)
        return 1

    print("ok no_dense_inline_comprehensions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
