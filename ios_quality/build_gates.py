# Copyright (c) 2026 PitchAI. All rights reserved.
"""Preflight and Swift Package Manager quality gates."""

from __future__ import annotations

import shutil
import sys
from dataclasses import dataclass
from typing import TYPE_CHECKING

from .model import Gate
from .runtime import spm_package_root, swift_files, tool_exists, write_header

if TYPE_CHECKING:
    from pathlib import Path

    from .model import CheckConfig
    from .runtime import ProcessRunner


@dataclass(frozen=True)
class BuildGateRunner:
    """Provide toolchain preflight and SwiftPM gates."""

    _config: CheckConfig
    _process: ProcessRunner

    def gates(self) -> tuple[Gate, ...]:
        """Build this runner's ordered gate definitions.

        Returns:
            Preflight and SwiftPM gate definitions.
        """
        return (
            Gate("preflight", "toolchain and project-shape preflight", self._preflight),
            Gate("spm-resolve", "SwiftPM manifest, dependency, strict build, and test checks", self._spm_resolve),
        )

    def _preflight(self) -> int:
        write_header("preflight")
        root = self._config.project.root
        swift_count = len(swift_files(root))
        sys.stdout.write(f"Swift files scanned: {swift_count}\n")
        failure_count = 0
        if swift_count == 0:
            sys.stderr.write("FAIL: no Swift files found under the project root\n")
            failure_count += 1
        sys.stdout.write(f"swift: {shutil.which('swift') or 'missing'}\n")
        sys.stdout.write(f"xcodebuild: {shutil.which('xcodebuild') or 'missing'}\n")
        for tool in ("swift-format", "swiftformat", "swiftlint", "semgrep", "gitleaks", "periphery"):
            sys.stdout.write(f"{tool}: {shutil.which(tool) or 'missing'}\n")
        if self._config.build.require_xcode and not tool_exists("xcodebuild"):
            sys.stderr.write("FAIL: xcodebuild is required for this project but is missing\n")
            failure_count += 1
        if self._config.build.xcode and not self._has_xcode_target():
            sys.stderr.write(
                "FAIL: Xcode gates are enabled but IOS_CHECK_WORKSPACE/PROJECT and "
                "IOS_CHECK_SCHEME are not configured\n",
            )
            failure_count += 1
        if self._config.xcode.package_authorization_provider not in {"", "keychain", "netrc"}:
            sys.stderr.write(
                "FAIL: IOS_CHECK_XCODE_PACKAGE_AUTHORIZATION_PROVIDER must be 'keychain', 'netrc', or empty\n",
            )
            failure_count += 1
        failure_count += self._validate_spm_root()
        for relative in self._config.project.generated_allowlist:
            if not (root / relative).exists():
                sys.stderr.write(f"FAIL: generated allowlist path does not exist: {relative}\n")
                failure_count += 1
        return 1 if failure_count else 0

    def _has_xcode_target(self) -> bool:
        project = self._config.project
        return bool(project.scheme and (project.workspace or project.project))

    def _validate_spm_root(self) -> int:
        if not self._config.build.spm:
            return 0
        package_root = spm_package_root(self._config)
        if package_root is None:
            sys.stderr.write("FAIL: IOS_CHECK_SPM_PATH must stay inside the repository root\n")
            return 1
        if not (package_root / "Package.swift").is_file():
            sys.stderr.write(
                f"FAIL: IOS_CHECK_ENABLE_SPM=1 but {self._config.project.spm_path}/Package.swift is missing\n",
            )
            return 1
        relative_root = package_root.relative_to(self._config.project.root.resolve())
        display_root = relative_root.as_posix() if relative_root.parts else "."
        sys.stdout.write(f"SwiftPM package root: {display_root}\n")
        return 0

    def _spm_resolve(self) -> int:
        if not self._config.build.spm:
            write_header("SwiftPM checks not applicable")
            return 0
        write_header("SwiftPM manifest, resolve, strict build, and test")
        package_root = spm_package_root(self._config)
        validation_status = self._validate_package_for_execution(package_root)
        if validation_status != 0 or package_root is None:
            return validation_status
        commands = self._spm_commands()
        for command in commands:
            status = self._process.run(command, cwd=package_root)
            if status != 0:
                return status
        return 0

    def _validate_package_for_execution(self, package_root: Path | None) -> int:
        if package_root is None:
            sys.stderr.write("FAIL: IOS_CHECK_SPM_PATH must stay inside the repository root\n")
            return 1
        if not (package_root / "Package.swift").is_file():
            sys.stderr.write(
                f"FAIL: IOS_CHECK_ENABLE_SPM=1 but {self._config.project.spm_path}/Package.swift is missing\n",
            )
            return 1
        if not tool_exists("swift"):
            sys.stderr.write("FAIL: swift is required for SwiftPM checks but missing\n")
            return 1
        return 0

    def _spm_commands(self) -> tuple[tuple[str, ...], ...]:
        commands = [
            ("swift", "package", "dump-package"),
            ("swift", "package", "resolve"),
            ("swift", "build", "-Xswiftc", "-warnings-as-errors", "-Xswiftc", "-strict-concurrency=complete"),
        ]
        if self._config.build.spm_tests:
            commands.append(
                ("swift", "test", "-Xswiftc", "-warnings-as-errors", "-Xswiftc", "-strict-concurrency=complete"),
            )
        else:
            sys.stdout.write("SwiftPM tests explicitly disabled by IOS_CHECK_ENABLE_SPM_TESTS=0\n")
        return tuple(commands)
