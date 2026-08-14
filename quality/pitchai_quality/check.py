# Copyright (c) 2026 PitchAI. All rights reserved.
"""Run the complete strict Python static-analysis checker suite."""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, cast

import anyio

from pitchai_quality.source_files import PYTHON_SUFFIXES, REPOSITORY_ROOT, RUNTIME_PYTHON_SUFFIXES, iter_python_files
from pitchai_quality.strict_policy import EXPECTED_GATES, RUFF_ARGUMENTS, SEMGREP_ARGUMENTS

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence

_DEFAULT_GATES = EXPECTED_GATES


@dataclass(frozen=True)
class _Gate:
    name: str
    description: str
    command: tuple[str, ...]
    skip_reason: str | None = None


def _normalize_paths(paths: Sequence[str]) -> tuple[Path, ...]:
    normalized: list[Path] = []
    for raw_path in paths:
        path = Path(raw_path).expanduser()
        if not path.is_absolute():
            path = REPOSITORY_ROOT / path
        normalized.append(path.resolve(strict=False))
    return tuple(normalized)


def _selected_files(paths: Sequence[Path], *, suffixes: frozenset[str]) -> tuple[str, ...]:
    roots = tuple(paths) if paths else (REPOSITORY_ROOT,)
    return tuple(str(path) for path in iter_python_files(roots, suffixes=suffixes))


def _tool_executable(tool: str) -> str:
    for local_tool_dir in _local_tool_dirs():
        local_tool = local_tool_dir / tool
        if local_tool.is_file():
            return str(local_tool)
    return tool


def _local_tool_dirs() -> tuple[Path, ...]:
    tool_dirs: list[Path] = []
    launched_script = Path(sys.argv[0]).expanduser()
    if launched_script.is_absolute() or launched_script.parent != Path():
        tool_dirs.append(launched_script.resolve(strict=False).parent)
    tool_dirs.append(Path(sys.executable).resolve(strict=False).parent)
    return tuple(dict.fromkeys(tool_dirs))


def _tool_command(tool: str, arguments: Sequence[str], files: Sequence[str]) -> tuple[str, ...]:
    return (_tool_executable(tool), *arguments, *files) if files else ()


def _gate(
    name: str,
    description: str,
    command: tuple[str, ...],
    *,
    scoped: bool,
) -> _Gate:
    skip_reason = "selected paths contain no applicable Python source" if scoped and not command else None
    return _Gate(name=name, description=description, command=command, skip_reason=skip_reason)


def _gates(paths: Sequence[Path]) -> dict[str, _Gate]:
    all_python = _selected_files(paths, suffixes=PYTHON_SUFFIXES)
    runtime_python = _selected_files(paths, suffixes=RUNTIME_PYTHON_SUFFIXES)
    scoped = bool(paths)
    custom_checks = {
        "nested-event-loops": (
            "Architectural guard against nested event-loop creation.",
            "pitchai_quality.check_nested_event_loops",
        ),
        "no-vague-signatures": (
            "Type-signature guard against vague top-type contracts.",
            "pitchai_quality.check_no_vague_signatures",
        ),
        "no-single-use-one-line-functions": (
            "Architectural guard against tiny helpers that hide one expression.",
            "pitchai_quality.check_no_single_use_one_line_functions",
        ),
        "no-pure-wrapper-functions": (
            "Architectural guard against pass-through wrappers.",
            "pitchai_quality.check_no_pure_wrapper_functions",
        ),
        "no-dense-inline-comprehensions": (
            "Architectural guard against dense nested comprehensions.",
            "pitchai_quality.check_no_dense_inline_comprehensions",
        ),
    }
    gates = {
        "no-validation-bypasses": _Gate(
            name="no-validation-bypasses",
            description="Repository-wide guard against suppressions and source exclusions.",
            command=(sys.executable, "-m", "pitchai_quality.check_no_validation_bypasses"),
        ),
    }
    for name, (description, script) in custom_checks.items():
        command = (sys.executable, "-m", script, *all_python) if all_python else ()
        gates[name] = _gate(name, description, command, scoped=scoped)
    gates.update(
        {
            "ruff": _gate(
                "ruff",
                "Strict Ruff linting for every executable Python source file.",
                _tool_command("ruff", RUFF_ARGUMENTS, runtime_python),
                scoped=scoped,
            ),
            "basedpyright": _gate(
                "basedpyright",
                "Strict BasedPyright checking for every Python and stub file.",
                _tool_command("basedpyright", ("--project", "quality/pyproject.toml", "--warnings"), all_python),
                scoped=scoped,
            ),
            "pylint": _gate(
                "pylint",
                "Full Pylint analysis for every executable Python source file.",
                _tool_command("pylint", ("--rcfile", "quality/pyproject.toml", "--fail-under=10"), runtime_python),
                scoped=scoped,
            ),
            "semgrep": _gate(
                "semgrep",
                "Repository security and architecture rules for every executable Python file.",
                _tool_command(
                    "semgrep",
                    (
                        "--config",
                        str(REPOSITORY_ROOT / "quality" / ".semgrep.yml"),
                        *SEMGREP_ARGUMENTS,
                    ),
                    runtime_python,
                ),
                scoped=scoped,
            ),
        },
    )
    return gates


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run all strict static-analysis gates over the repository's complete Python source surface.",
    )
    parser.add_argument(
        "--only",
        action="append",
        choices=sorted(_DEFAULT_GATES),
        help="Run only this gate. May be repeated. Defaults to all gates.",
    )
    parser.add_argument("--list", action="store_true", help="List selected gates and commands without running them.")
    parser.add_argument("paths", nargs="*", help="Optional files or folders. The default is the repository root.")
    return parser


def _print_gate(gate: _Gate) -> None:
    sys.stdout.write(f"\n==> {gate.name}: {gate.description}\n")
    if gate.skip_reason is not None:
        sys.stdout.write(f"$ <skip> {gate.skip_reason}\n")
    else:
        sys.stdout.write(f"$ {' '.join(gate.command)}\n")
    sys.stdout.flush()


async def _run_gate(gate: _Gate, env: Mapping[str, str]) -> int:
    _print_gate(gate)
    if gate.skip_reason is not None:
        sys.stdout.write(f"<== {gate.name}: skipped\n")
        return 0
    completed = await anyio.run_process(gate.command, cwd=REPOSITORY_ROOT, env=env, check=False)
    if completed.stdout:
        sys.stdout.buffer.write(completed.stdout)
    if completed.stderr:
        sys.stderr.buffer.write(completed.stderr)
    status = "ok" if completed.returncode == 0 else f"failed rc={completed.returncode}"
    sys.stdout.write(f"<== {gate.name}: {status}\n")
    return completed.returncode


async def _run_selected(gates: Sequence[_Gate], env: Mapping[str, str]) -> tuple[str, ...]:
    failures: list[str] = []
    for gate in gates:
        return_code = await _run_gate(gate, env)
        if return_code != 0:
            failures.append(gate.name)
    return tuple(failures)


def main(argv: Sequence[str] | None = None) -> int:
    """Run selected gates and return a nonzero status when any gate fails.

    Returns:
        Zero when every selected gate passes; otherwise one.
    """
    arguments = _parser().parse_args(list(argv) if argv is not None else None)
    raw_paths = cast("list[str]", arguments.paths)
    requested_gates = cast("list[str] | None", arguments.only)
    list_only = cast("bool", arguments.list)
    gates = _gates(_normalize_paths(raw_paths))
    selected = tuple(gates[name] for name in (requested_gates or _DEFAULT_GATES))

    if list_only:
        for gate in selected:
            _print_gate(gate)
        return 0

    env = dict(os.environ)
    env.setdefault("SEMGREP_SEND_METRICS", "off")
    failures = anyio.run(_run_selected, selected, env)
    if failures:
        sys.stderr.write(f"\nFAILED static gates: {', '.join(failures)}\n")
        return 1
    sys.stdout.write("\nAll static gates passed.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
