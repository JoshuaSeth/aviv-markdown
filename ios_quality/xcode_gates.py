# Copyright (c) 2026 PitchAI. All rights reserved.
"""Xcode build, analysis, test, dead-code, and snapshot gates."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from typing import TYPE_CHECKING

from .model import Gate
from .runtime import tool_exists, write_header, xcode_common_args

if TYPE_CHECKING:
    from .model import CheckConfig
    from .runtime import ProcessRunner


@dataclass(frozen=True)
class XcodeGateRunner:
    """Provide Xcode-oriented native build and validation gates."""

    _config: CheckConfig
    _process: ProcessRunner

    def gates(self) -> tuple[Gate, ...]:
        """Build this runner's ordered gate definitions.

        Returns:
            Xcode, Periphery, and snapshot gate definitions.
        """
        return (
            Gate(
                "xcode-build-for-testing",
                "xcodebuild build-for-testing with warnings as errors",
                self._xcode_build,
            ),
            Gate("swiftlint-analyze", "SwiftLint analyzer rules from compiler log", self._swiftlint_analyze),
            Gate("xcode-analyze", "xcodebuild static analyzer", self._xcode_analyze),
            Gate("xcode-test", "XCTest/XCUITest simulator tests", self._xcode_test),
            Gate("periphery", "Periphery dead-code scan", self._periphery),
            Gate("ui-snapshots", "project-specific UI/snapshot marker", self._snapshot_marker),
        )

    def _xcode_build(self) -> int:
        if not self._config.build.xcode:
            write_header("xcode build not configured")
            return 0
        write_header("xcodebuild build-for-testing")
        if not tool_exists("xcodebuild"):
            sys.stderr.write("FAIL: xcodebuild is required for configured Xcode gates\n")
            return 1
        command = ("xcodebuild", *xcode_common_args(self._config), "build-for-testing")
        log_path = self._config.project.root / ".build" / "logs" / "xcodebuild-build.log"
        return self._process.run(command, cwd=self._config.project.root, log_path=log_path)

    def _swiftlint_analyze(self) -> int:
        if not self._config.static.swiftlint or not self._config.build.xcode:
            write_header("SwiftLint analyze not applicable")
            return 0
        write_header("swiftlint analyze")
        log_path = self._config.project.root / ".build" / "logs" / "xcodebuild-build.log"
        if not log_path.exists():
            sys.stderr.write("FAIL: compiler log missing; run xcode-build-for-testing before swiftlint-analyze\n")
            return 1
        if not tool_exists("swiftlint"):
            sys.stderr.write("FAIL: swiftlint is required but missing\n")
            return 1
        command = ("swiftlint", "analyze", "--strict", "--compiler-log-path", str(log_path))
        return self._process.run(command, cwd=self._config.project.root)

    def _xcode_analyze(self) -> int:
        if not self._config.build.xcode:
            write_header("xcode analyze not configured")
            return 0
        write_header("xcodebuild analyze")
        if not tool_exists("xcodebuild"):
            sys.stderr.write("FAIL: xcodebuild is required for configured Xcode gates\n")
            return 1
        command = ("xcodebuild", *xcode_common_args(self._config), "analyze")
        log_path = self._config.project.root / ".build" / "logs" / "xcodebuild-analyze.log"
        return self._process.run(command, cwd=self._config.project.root, log_path=log_path)

    def _xcode_test(self) -> int:
        if not self._config.build.tests:
            write_header("xcode test not configured")
            return 0
        write_header("xcodebuild test")
        if not self._config.build.xcode:
            sys.stderr.write("FAIL: tests are enabled but Xcode gates are disabled\n")
            return 1
        if not tool_exists("xcodebuild"):
            sys.stderr.write("FAIL: xcodebuild is required for configured test gates\n")
            return 1
        command = ("xcodebuild", *xcode_common_args(self._config), "test")
        log_path = self._config.project.root / ".build" / "logs" / "xcodebuild-test.log"
        return self._process.run(command, cwd=self._config.project.root, log_path=log_path)

    def _periphery(self) -> int:
        if not self._config.static.periphery:
            write_header("Periphery not enabled")
            return 0
        write_header("periphery")
        if not tool_exists("periphery"):
            sys.stderr.write("FAIL: periphery is enabled but missing\n")
            return 1
        return self._process.run(("periphery", "scan"), cwd=self._config.project.root)

    def _snapshot_marker(self) -> int:
        if not self._config.build.snapshots:
            write_header("snapshot/UI checks not enabled")
            return 0
        write_header("snapshot/UI project gate")
        marker = self._config.project.root / "Tests" / "SnapshotTests"
        if not marker.exists():
            sys.stderr.write("FAIL: snapshot checks are enabled but Tests/SnapshotTests is missing\n")
            return 1
        return 0
