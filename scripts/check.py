"""Run the strict Python static-analysis checker suite."""

from __future__ import annotations

import argparse
import os
import subprocess  # noqa: S404
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

_REPO_ROOT = Path(__file__).resolve().parents[1]
_PYTHON_ROOTS = (
    "scripts/ios_check.py",
)
_DEFAULT_GATES = (
    "nested-event-loops",
    "no-vague-signatures",
    "no-single-use-one-line-functions",
    "no-pure-wrapper-functions",
    "no-dense-inline-comprehensions",
    "ruff",
    "basedpyright",
    "pylint",
    "semgrep",
)


@dataclass(frozen=True)
class _Gate:
    name: str
    description: str
    command: tuple[str, ...]
    skip_reason: str | None = None


def _has_python(path: Path) -> bool:
    if path.is_file():
        return path.suffix in {".py", ".pyi"}
    if path.is_dir():
        return any(child.suffix in {".py", ".pyi"} for child in path.rglob("*") if child.is_file())
    return path.suffix in {".py", ".pyi"}


def _normalize_paths(paths: Sequence[str]) -> tuple[str, ...]:
    normalized: list[str] = []
    for raw_path in paths:
        path = Path(raw_path).expanduser()
        if not path.is_absolute():
            path = _REPO_ROOT / path
        normalized.append(str(path.resolve(strict=False)))
    return tuple(normalized)


def _python_paths(paths: Sequence[str]) -> tuple[str, ...]:
    selected: list[str] = []
    for raw_path in paths:
        path = Path(raw_path)
        if path.is_file() and _is_checked_python_file(path):
            selected.append(str(path.resolve(strict=False)))
        elif path.is_dir():
            selected.extend(str(child.resolve(strict=False)) for child in _iter_checked_python_files(path))
    return tuple(dict.fromkeys(selected))


def _iter_checked_python_files(path: Path) -> tuple[Path, ...]:
    return tuple(
        child
        for child in sorted((*path.rglob("*.py"), *path.rglob("*.pyi")))
        if child.is_file() and _is_checked_python_file(child)
    )


def _is_checked_python_file(path: Path) -> bool:
    resolved = path.resolve(strict=False)
    return resolved.suffix in {".py", ".pyi"}


def _default_paths() -> tuple[str, ...]:
    return tuple(str((_REPO_ROOT / path).resolve(strict=False)) for path in _PYTHON_ROOTS)


def _scoped_or_default(paths: Sequence[str]) -> tuple[str, ...]:
    return tuple(paths) if paths else _default_paths()


def _python_command(*args: str, paths: Sequence[str]) -> tuple[str, ...]:
    selected = _python_paths(paths)
    if paths and not selected:
        return ()
    return (sys.executable, *args, *selected)


def _tool_executable(tool: str) -> str:
    local_tool_dirs = _local_tool_dirs()
    for local_tool_dir in local_tool_dirs:
        local_tool = local_tool_dir / tool
        if local_tool.is_file():
            return str(local_tool)
    return tool


def _local_tool_dirs() -> tuple[Path, ...]:
    tool_dirs: list[Path] = []
    launched_script = Path(sys.argv[0]).expanduser()
    launched_with_directory = launched_script.is_absolute() or launched_script.parent != Path(".")
    if launched_with_directory:
        tool_dirs.append(launched_script.resolve(strict=False).parent)
    python_dir = Path(sys.executable).resolve(strict=False).parent
    tool_dirs.append(python_dir)
    return tuple(dict.fromkeys(tool_dirs))


def _tool_command(tool: str, *args: str, paths: Sequence[str]) -> tuple[str, ...]:
    selected = _python_paths(paths)
    if paths and not selected:
        return ()
    return (_tool_executable(tool), *args, *selected)


def _gates(paths: Sequence[str]) -> dict[str, _Gate]:
    selected_paths = _scoped_or_default(paths)
    python_skip = "skipped for scoped run: selected paths contain no Python files"
    semgrep_target = tuple(paths) if paths else _default_paths()

    return {
        "nested-event-loops": _Gate(
            name="nested-event-loops",
            description="Architectural guard against nested event loop creation in runtime code.",
            command=_python_command("scripts/check_nested_event_loops.py", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "no-vague-signatures": _Gate(
            name="no-vague-signatures",
            description="Type-signature guard against object/Any/dict[str, object] top-type soup.",
            command=_python_command("scripts/check_no_vague_signatures.py", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "no-single-use-one-line-functions": _Gate(
            name="no-single-use-one-line-functions",
            description="Architectural guard against tiny helper functions that hide one expression or one guarded call.",
            command=_python_command("scripts/check_no_single_use_one_line_functions.py", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "no-pure-wrapper-functions": _Gate(
            name="no-pure-wrapper-functions",
            description="Architectural guard against functions that only pass through to another function.",
            command=_python_command("scripts/check_no_pure_wrapper_functions.py", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "no-dense-inline-comprehensions": _Gate(
            name="no-dense-inline-comprehensions",
            description="Architectural guard against dense comprehensions hidden inside nested expressions.",
            command=_python_command("scripts/check_no_dense_inline_comprehensions.py", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "ruff": _Gate(
            name="ruff",
            description="Strict Ruff linting for runtime code.",
            command=_tool_command("ruff", "check", "--no-cache", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "basedpyright": _Gate(
            name="basedpyright",
            description="BasedPyright strict type checking.",
            command=_tool_command("basedpyright", "--warnings", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "pylint": _Gate(
            name="pylint",
            description="Pylint structural checks.",
            command=_tool_command("pylint", "--rcfile", "pyproject.toml", "--fail-under=10", paths=selected_paths),
            skip_reason=python_skip if paths and not _python_paths(paths) else None,
        ),
        "semgrep": _Gate(
            name="semgrep",
            description="Semgrep security/static rules from the repo root configuration.",
            command=(
                _tool_executable("semgrep"),
                "--config",
                str(_REPO_ROOT / ".semgrep.yml"),
                "--error",
                "--metrics=off",
                *semgrep_target,
            ),
        ),
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run all strict static-analysis gates. `uv run check` is the no-server static checker suite."
    )
    parser.add_argument(
        "--only",
        action="append",
        choices=sorted(_DEFAULT_GATES),
        help="Run only this gate. May be repeated. Defaults to all gates.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List the gates and commands without running them.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Optional files or folders to check. Defaults to the full configured suite.",
    )
    return parser


def _print_gate(gate: _Gate) -> None:
    print(f"\n==> {gate.name}: {gate.description}", flush=True)
    if gate.skip_reason is not None:
        print(f"$ <skip> {gate.skip_reason}", flush=True)
        return
    quoted = " ".join(gate.command)
    print(f"$ {quoted}", flush=True)


def _run_gate(gate: _Gate, *, env: dict[str, str]) -> int:
    _print_gate(gate)
    if gate.skip_reason is not None:
        print(f"<== {gate.name}: skipped", flush=True)
        return 0
    proc = subprocess.run(gate.command, cwd=_REPO_ROOT, env=env, check=False)  # noqa: S603
    if proc.returncode == 0:
        print(f"<== {gate.name}: ok", flush=True)
    else:
        print(f"<== {gate.name}: failed rc={proc.returncode}", flush=True)
    return int(proc.returncode)


def main(argv: Sequence[str] | None = None) -> int:
    """Run the selected static-analysis gates."""
    args = _parser().parse_args(list(argv) if argv is not None else None)
    raw_paths = cast("list[str]", args.paths)
    requested_gates = cast("list[str] | None", args.only)
    list_only = cast("bool", args.list)

    paths = _normalize_paths(raw_paths)
    gates = _gates(paths)
    selected_names = tuple(requested_gates or _DEFAULT_GATES)
    selected = tuple(gates[name] for name in selected_names)

    if list_only:
        for gate in selected:
            _print_gate(gate)
        return 0

    env = dict(os.environ)
    env.setdefault("SEMGREP_SEND_METRICS", "off")

    failures: list[str] = []
    for gate in selected:
        if _run_gate(gate, env=env) != 0:
            failures.append(gate.name)

    if failures:
        print("\nFAILED static gates: " + ", ".join(failures), file=sys.stderr, flush=True)
        return 1

    print("\nAll static gates passed.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
