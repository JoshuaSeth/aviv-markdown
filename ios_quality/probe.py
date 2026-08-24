# Copyright (c) 2026 PitchAI. All rights reserved.
"""Activation probes proving that representative violations fail closed."""

from __future__ import annotations

import os
import string
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

from .model import config_from_env
from .registry import run_gates
from .runtime import tool_exists, write_header

if TYPE_CHECKING:
    from collections.abc import Mapping
    from types import TracebackType


class _EnvironmentOverride:
    def __init__(self, values: Mapping[str, str | None]) -> None:
        self._values: Mapping[str, str | None] = values
        self._previous: dict[str, str | None] = {}

    def __enter__(self) -> None:
        for key, value in self._values.items():
            self._previous[key] = os.environ.get(key)
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def __exit__(
        self,
        exception_type: type[BaseException] | None,
        exception: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        for key, value in self._previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def _write_probe_project(root: Path) -> None:
    (root / "Sources" / "ProbeApp").mkdir(parents=True)
    (root / "Tests" / "ProbeAppTests").mkdir(parents=True)
    (root / "scripts").mkdir()
    (root / "Package.swift").write_text(
        """// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProbeApp",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ProbeApp", targets: ["ProbeApp"])],
    targets: [
        .target(name: "ProbeApp"),
        .testTarget(name: "ProbeAppTests", dependencies: ["ProbeApp"]),
    ]
)
""",
        encoding="utf-8",
    )
    (root / "Sources" / "ProbeApp" / "Probe.swift").write_text(
        """private func risky() throws -> String {
    "ok"
}

public struct Probe {
    public init() {}

    public func value(_ input: String?) -> String {
        print("debug")
        _ = try? risky()
        _ = try! risky()
        return input!
    }
}
""",
        encoding="utf-8",
    )
    (root / "Tests" / "ProbeAppTests" / "ProbeTests.swift").write_text(
        """import XCTest
@testable import ProbeApp

final class ProbeTests: XCTestCase {
    func testFailureProbe() {
        XCTAssertEqual(Probe().value("ok"), "not-ok")
    }
}
""",
        encoding="utf-8",
    )
    (root / "Secrets.swift").write_text(
        'let api_key = "' + string.ascii_lowercase + '123456"\n',
        encoding="utf-8",
    )
    (root / "scripts" / "ios_check.env").write_text(
        """IOS_CHECK_ENABLE_SWIFT_FORMAT=0
IOS_CHECK_ENABLE_SWIFTLINT=0
IOS_CHECK_ENABLE_SEMGREP=0
IOS_CHECK_ENABLE_GITLEAKS=0
IOS_CHECK_ENABLE_SPM=0
IOS_CHECK_ENABLE_SPM_TESTS=0
IOS_CHECK_ENABLE_XCODE=0
IOS_CHECK_ENABLE_TESTS=0
""",
        encoding="utf-8",
    )


def _write_failing_tool(path: Path, message: str) -> None:
    script = f"#!/usr/bin/env bash\necho '{message}' >&2\nexit 1\n"
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)


def _probe_required_failures(root: Path) -> list[str]:
    failures: list[str] = []
    config = config_from_env(root)
    for name in ("pitchai-patterns", "secrets-builtin"):
        status = run_gates(config, only=name, skip=frozenset())
        if status == 0:
            failures.append(f"{name} did not fail on injected violation")
    aggregate_status = run_gates(config, only=None, skip=frozenset())
    if aggregate_status == 0:
        failures.append("aggregate command did not fail on injected violations")
    return failures


def _probe_swift_test_failure(root: Path) -> list[str]:
    if not tool_exists("swift"):
        sys.stdout.write("swift missing; XCTest failure probe requires macOS/Xcode or Swift toolchain\n")
        return []
    overrides = {
        "IOS_CHECK_ENABLE_SPM": "1",
        "IOS_CHECK_ENABLE_SPM_TESTS": "1",
    }
    with _EnvironmentOverride(overrides):
        status = run_gates(config_from_env(root), only="spm-resolve", skip=frozenset())
    return [] if status != 0 else ["SwiftPM strict build/test gate did not fail on injected XCTest violation"]


def _probe_failing_tools(root: Path) -> list[str]:
    write_header("external tool failure shims")
    bin_dir = root / "fake-bin"
    bin_dir.mkdir()
    tools = {
        "swift-format": "simulated swift-format lint violation",
        "swiftlint": "simulated SwiftLint violation",
        "gitleaks": "simulated gitleaks secret finding",
        "semgrep": "simulated Semgrep finding",
        "xcodebuild": "simulated xcodebuild warning-as-error/test failure",
    }
    for name, message in tools.items():
        _write_failing_tool(bin_dir / name, message)
    (root / ".semgrep.yml").write_text("rules: []\n", encoding="utf-8")

    overrides = {
        "PATH": f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}",
        "IOS_CHECK_ENABLE_SWIFT_FORMAT": "1",
        "IOS_CHECK_ENABLE_SWIFTLINT": "1",
        "IOS_CHECK_ENABLE_GITLEAKS": "1",
        "IOS_CHECK_ENABLE_SEMGREP": "1",
        "IOS_CHECK_ENABLE_SPM": "0",
        "IOS_CHECK_ENABLE_SPM_TESTS": "0",
        "IOS_CHECK_ENABLE_XCODE": "1",
        "IOS_CHECK_REQUIRE_XCODE": "1",
        "IOS_CHECK_ENABLE_TESTS": "1",
        "IOS_CHECK_WORKSPACE": "ProbeApp.xcworkspace",
        "IOS_CHECK_SCHEME": "ProbeApp",
    }
    failures: list[str] = []
    with _EnvironmentOverride(overrides):
        config = config_from_env(root)
        expected = (
            "format-swift-format",
            "swiftlint",
            "gitleaks",
            "semgrep",
            "xcode-build-for-testing",
            "xcode-test",
        )
        for name in expected:
            status = run_gates(config, only=name, skip=frozenset())
            if status == 0:
                failures.append(f"{name} did not fail with failing shim")
    return failures


def run_probe() -> int:
    """Run activation probes against injected source and tool failures.

    Returns:
        Zero only when every injected violation is detected.
    """
    write_header("activation probe")
    with tempfile.TemporaryDirectory(prefix="pitchai-ios-probe-") as temporary_directory:
        root = Path(temporary_directory)
        _write_probe_project(root)
        failures = _probe_required_failures(root)
        failures.extend(_probe_swift_test_failure(root))
        failures.extend(_probe_failing_tools(root))
        if failures:
            failure_report = "\n".join(failures)
            sys.stderr.write(f"{failure_report}\n")
            return 1
    sys.stdout.write("Activation probe confirmed representative nonzero failures.\n")
    return 0
