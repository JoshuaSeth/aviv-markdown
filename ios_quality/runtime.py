# Copyright (c) 2026 PitchAI. All rights reserved.
"""Filesystem and process boundaries for the native quality runner."""

from __future__ import annotations

import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence
    from types import TracebackType

    from .model import CheckConfig

DEFAULT_EXCLUDES = frozenset(
    {
        ".build",
        ".git",
        ".nox",
        ".swiftpm",
        ".tox",
        ".venv",
        "Carthage",
        "DerivedData",
        "Pods",
        "__pycache__",
        "build",
        "fastlane/report.xml",
        "node_modules",
        "venv",
    },
)


class _WorkingDirectory:
    def __init__(self, target: Path) -> None:
        self._target: Path = target
        self._previous: Path = Path.cwd()

    def __enter__(self) -> None:
        os.chdir(self._target)

    def __exit__(
        self,
        exception_type: type[BaseException] | None,
        exception: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        os.chdir(self._previous)


@dataclass(frozen=True)
class ProcessRunner:
    """Execute trusted tool commands without a shell and preserve their status."""

    @staticmethod
    def run(command: Sequence[str], *, cwd: Path, log_path: Path | None = None) -> int:
        """Run a trusted executable in a selected working directory.

        Returns:
            The executable's exact exit status.
        """
        executable = shutil.which(command[0])
        if executable is None:
            sys.stderr.write(f"FAIL: executable is missing: {command[0]}\n")
            return 127
        arguments = (executable, *command[1:])
        sys.stdout.write(f"$ {' '.join(command)}\n")
        sys.stdout.flush()
        if log_path is None:
            with _WorkingDirectory(cwd):
                process_id = os.posix_spawn(executable, arguments, os.environ)
            _, wait_status = os.waitpid(process_id, 0)
            return os.waitstatus_to_exitcode(wait_status)

        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("wb") as log_file, _WorkingDirectory(cwd):
            file_actions = (
                (os.POSIX_SPAWN_DUP2, log_file.fileno(), 1),
                (os.POSIX_SPAWN_DUP2, log_file.fileno(), 2),
            )
            process_id = os.posix_spawn(executable, arguments, os.environ, file_actions=file_actions)
        _, wait_status = os.waitpid(process_id, 0)
        sys.stdout.buffer.write(log_path.read_bytes())
        return os.waitstatus_to_exitcode(wait_status)


def write_header(message: str) -> None:
    """Write and flush a gate section header."""
    sys.stdout.write(f"\n==> {message}\n")
    sys.stdout.flush()


def tool_exists(name: str) -> bool:
    """Return whether an executable is available on the current path.

    Returns:
        True when the executable can be resolved.
    """
    executable = shutil.which(name)
    return executable is not None and Path(executable).is_file()


def should_skip(path: Path, root: Path) -> bool:
    """Return whether a repository path belongs to an excluded tree.

    Returns:
        True for build outputs, dependencies, caches, and other excluded paths.
    """
    relative = path.relative_to(root)
    if set(relative.parts).intersection(DEFAULT_EXCLUDES):
        return True
    relative_text = relative.as_posix()
    return any(relative_text.startswith(f"{prefix.rstrip('/')}/") for prefix in DEFAULT_EXCLUDES)


def swift_files(root: Path) -> tuple[Path, ...]:
    """Find every checked Swift source file below a repository root.

    Returns:
        Sorted Swift source paths outside excluded trees.
    """
    candidates = root.rglob("*.swift")
    files_only = (path for path in candidates if path.is_file())
    files = [path for path in files_only if not should_skip(path, root)]
    return tuple(sorted(files))


def spm_package_root(config: CheckConfig) -> Path | None:
    """Resolve the configured SwiftPM root without allowing path escape.

    Returns:
        The resolved package root, or None when the configured path escapes.
    """
    root = config.project.root.resolve()
    candidate = (root / config.project.spm_path).resolve()
    return candidate if candidate.is_relative_to(root) else None


def _project_args(config: CheckConfig) -> tuple[str, ...]:
    if config.project.workspace:
        return ("-workspace", config.project.workspace)
    if config.project.project:
        return ("-project", config.project.project)
    return ()


def xcode_common_args(config: CheckConfig) -> tuple[str, ...]:
    """Build the shared fail-closed Xcode command arguments.

    Returns:
        Immutable arguments shared by build, analysis, and test commands.
    """
    authorization_args: tuple[str, ...] = ()
    if config.xcode.package_authorization_provider:
        authorization_args = (
            "-packageAuthorizationProvider",
            config.xcode.package_authorization_provider,
        )
    return (
        *_project_args(config),
        "-scheme",
        config.project.scheme,
        "-configuration",
        config.xcode.configuration,
        "-destination",
        config.xcode.destination,
        "-derivedDataPath",
        config.xcode.derived_data,
        *authorization_args,
        "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
        "GCC_TREAT_WARNINGS_AS_ERRORS=YES",
        "CLANG_TREAT_WARNINGS_AS_ERRORS=YES",
        "SWIFT_STRICT_CONCURRENCY=complete",
        "CODE_SIGNING_ALLOWED=NO",
    )
