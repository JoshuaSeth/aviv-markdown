#!/usr/bin/env python3
"""PitchAI hyper-strict iOS quality gate.

This script is intentionally self-contained so iOS repositories can copy it into
`scripts/ios_check.py` and expose it through `make check`.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


ROOT = Path.cwd()
DEFAULT_EXCLUDES = {
    ".build",
    ".git",
    ".nox",
    ".swiftpm",
    ".tox",
    ".venv",
    "DerivedData",
    "Pods",
    "Carthage",
    "__pycache__",
    "fastlane/report.xml",
    "build",
    "node_modules",
    "venv",
}


@dataclass(frozen=True)
class CheckConfig:
    root: Path
    spm_path: str
    workspace: str
    project: str
    scheme: str
    configuration: str
    destination: str
    derived_data: str
    enable_xcode: bool
    require_xcode: bool
    enable_tests: bool
    enable_ui_tests: bool
    enable_periphery: bool
    enable_swift_format: bool
    enable_swiftformat: bool
    enable_swiftlint: bool
    enable_semgrep: bool
    enable_gitleaks: bool
    enable_spm: bool
    enable_spm_tests: bool
    enable_snapshots: bool
    generated_allowlist: tuple[str, ...]
    semgrep_config: str


@dataclass(frozen=True)
class Gate:
    name: str
    description: str
    run: Callable[[CheckConfig], int]


def env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def config_from_env(root: Path) -> CheckConfig:
    load_env_file(root / "scripts" / "ios_check.env")
    spm_path = os.getenv("IOS_CHECK_SPM_PATH", ".").strip() or "."
    workspace = os.getenv("IOS_CHECK_WORKSPACE", "")
    project = os.getenv("IOS_CHECK_PROJECT", "")
    scheme = os.getenv("IOS_CHECK_SCHEME", "")
    has_xcode_target = bool(scheme and (workspace or project))
    allowlist = tuple(
        item.strip()
        for item in os.getenv("IOS_CHECK_GENERATED_ALLOWLIST", "").split(":")
        if item.strip()
    )
    enable_spm = env_bool(
        "IOS_CHECK_ENABLE_SPM",
        (root / spm_path / "Package.swift").exists(),
    )
    return CheckConfig(
        root=root,
        spm_path=spm_path,
        workspace=workspace,
        project=project,
        scheme=scheme,
        configuration=os.getenv("IOS_CHECK_CONFIGURATION", "Debug"),
        destination=os.getenv(
            "IOS_CHECK_DESTINATION",
            "platform=iOS Simulator,name=iPhone 16,OS=latest",
        ),
        derived_data=os.getenv("IOS_CHECK_DERIVED_DATA", ".build/DerivedData/check"),
        enable_xcode=env_bool("IOS_CHECK_ENABLE_XCODE", has_xcode_target),
        require_xcode=env_bool("IOS_CHECK_REQUIRE_XCODE", has_xcode_target),
        enable_tests=env_bool("IOS_CHECK_ENABLE_TESTS", has_xcode_target),
        enable_ui_tests=env_bool("IOS_CHECK_ENABLE_UI_TESTS", False),
        enable_periphery=env_bool("IOS_CHECK_ENABLE_PERIPHERY", False),
        enable_swift_format=env_bool("IOS_CHECK_ENABLE_SWIFT_FORMAT", True),
        enable_swiftformat=env_bool("IOS_CHECK_ENABLE_SWIFTFORMAT", False),
        enable_swiftlint=env_bool("IOS_CHECK_ENABLE_SWIFTLINT", True),
        enable_semgrep=env_bool("IOS_CHECK_ENABLE_SEMGREP", True),
        enable_gitleaks=env_bool("IOS_CHECK_ENABLE_GITLEAKS", True),
        enable_spm=enable_spm,
        enable_spm_tests=env_bool("IOS_CHECK_ENABLE_SPM_TESTS", enable_spm),
        enable_snapshots=env_bool("IOS_CHECK_ENABLE_SNAPSHOTS", False),
        generated_allowlist=allowlist,
        semgrep_config=os.getenv("IOS_CHECK_SEMGREP_CONFIG", ".semgrep.yml"),
    )


def print_header(message: str) -> None:
    print(f"\n==> {message}", flush=True)


def run_command(command: list[str], *, cwd: Path, log_path: Path | None = None) -> int:
    printable = " ".join(command)
    print(f"$ {printable}", flush=True)
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8") as log_file:
            process = subprocess.run(
                command,
                cwd=cwd,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            log_file.write(process.stdout)
            print(process.stdout, end="")
            return process.returncode
    return subprocess.run(command, cwd=cwd, check=False).returncode


def tool_exists(name: str) -> bool:
    return shutil.which(name) is not None


def swift_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*.swift"):
        if not path.is_file():
            continue
        if should_skip(path, root):
            continue
        files.append(path)
    return sorted(files)


def should_skip(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    rel_text = rel.as_posix()
    parts = set(rel.parts)
    if parts & DEFAULT_EXCLUDES:
        return True
    return any(rel_text.startswith(prefix.rstrip("/") + "/") for prefix in DEFAULT_EXCLUDES)


def spm_package_root(config: CheckConfig) -> Path | None:
    root = config.root.resolve()
    candidate = (root / config.spm_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    return candidate


def project_args(config: CheckConfig) -> list[str]:
    if config.workspace:
        return ["-workspace", config.workspace]
    if config.project:
        return ["-project", config.project]
    return []


def xcode_common_args(config: CheckConfig) -> list[str]:
    return [
        *project_args(config),
        "-scheme",
        config.scheme,
        "-configuration",
        config.configuration,
        "-destination",
        config.destination,
        "-derivedDataPath",
        config.derived_data,
        "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
        "GCC_TREAT_WARNINGS_AS_ERRORS=YES",
        "CLANG_TREAT_WARNINGS_AS_ERRORS=YES",
        "SWIFT_STRICT_CONCURRENCY=complete",
        "CODE_SIGNING_ALLOWED=NO",
    ]


def gate_preflight(config: CheckConfig) -> int:
    print_header("preflight")
    swift_count = len(swift_files(config.root))
    print(f"Swift files scanned: {swift_count}")
    if swift_count == 0:
        print("FAIL: no Swift files found under the project root", file=sys.stderr)
        return 1
    print(f"swift: {shutil.which('swift') or 'missing'}")
    print(f"xcodebuild: {shutil.which('xcodebuild') or 'missing'}")
    for tool in ("swift-format", "swiftformat", "swiftlint", "semgrep", "gitleaks", "periphery"):
        print(f"{tool}: {shutil.which(tool) or 'missing'}")
    if config.require_xcode and not tool_exists("xcodebuild"):
        print("FAIL: xcodebuild is required for this project but is missing", file=sys.stderr)
        return 1
    if config.enable_xcode and not ((config.workspace or config.project) and config.scheme):
        print(
            "FAIL: Xcode gates are enabled but IOS_CHECK_WORKSPACE/PROJECT and "
            "IOS_CHECK_SCHEME are not configured",
            file=sys.stderr,
        )
        return 1
    if config.enable_spm:
        package_root = spm_package_root(config)
        if package_root is None:
            print("FAIL: IOS_CHECK_SPM_PATH must stay inside the repository root", file=sys.stderr)
            return 1
        if not (package_root / "Package.swift").is_file():
            print(
                f"FAIL: IOS_CHECK_ENABLE_SPM=1 but {config.spm_path}/Package.swift is missing",
                file=sys.stderr,
            )
            return 1
        relative_root = package_root.relative_to(config.root.resolve())
        print(f"SwiftPM package root: {relative_root or Path('.')}")
    for rel in config.generated_allowlist:
        if not (config.root / rel).exists():
            print(f"FAIL: generated allowlist path does not exist: {rel}", file=sys.stderr)
            return 1
    return 0


def gate_swift_format(config: CheckConfig) -> int:
    if not config.enable_swift_format:
        print_header("swift-format lint skipped by IOS_CHECK_ENABLE_SWIFT_FORMAT=0")
        return 0
    print_header("swift-format lint")
    if not tool_exists("swift-format"):
        print("FAIL: swift-format is required but missing", file=sys.stderr)
        return 1
    files = [str(path.relative_to(config.root)) for path in swift_files(config.root)]
    return run_command(["swift-format", "lint", "--recursive", *files], cwd=config.root)


def gate_swiftformat(config: CheckConfig) -> int:
    if not config.enable_swiftformat:
        print_header("SwiftFormat lint not enabled")
        return 0
    print_header("swiftformat --lint")
    if not tool_exists("swiftformat"):
        print("FAIL: swiftformat is enabled but missing", file=sys.stderr)
        return 1
    return run_command(["swiftformat", "--lint", "."], cwd=config.root)


def gate_swiftlint(config: CheckConfig) -> int:
    if not config.enable_swiftlint:
        print_header("SwiftLint skipped by IOS_CHECK_ENABLE_SWIFTLINT=0")
        return 0
    print_header("swiftlint")
    if not tool_exists("swiftlint"):
        print("FAIL: swiftlint is required but missing", file=sys.stderr)
        return 1
    command = ["swiftlint", "lint", "--strict"]
    if (config.root / ".swiftlint.yml").exists():
        command.extend(["--config", ".swiftlint.yml"])
    return run_command(command, cwd=config.root)


FORBIDDEN_PATTERNS: tuple[tuple[str, re.Pattern[str], str], ...] = (
    (
        "force-unwrap",
        re.compile(r"(?<=[A-Za-z0-9_)\]}])!(?!=)"),
        "force unwrap is forbidden in runtime code without a pitchai-allow marker",
    ),
    (
        "force-try",
        re.compile(r"\btry!(?!\w)"),
        "force try is forbidden in runtime code",
    ),
    (
        "silent-try",
        re.compile(r"\btry\?(?!\w)"),
        "try? is forbidden outside an explicitly documented edge",
    ),
    (
        "unchecked-sendable",
        re.compile(r"@unchecked\s+Sendable"),
        "@unchecked Sendable requires an audited exception",
    ),
    (
        "detached-task",
        re.compile(r"\bTask\s*\.\s*detached\b"),
        "Task.detached is forbidden outside concurrency gateways",
    ),
    (
        "assume-isolated",
        re.compile(r"\bMainActor\s*\.\s*assumeIsolated\b"),
        "MainActor.assumeIsolated requires an audited UI boundary exception",
    ),
    (
        "empty-catch",
        re.compile(r"\bcatch\s*\{\s*(?://[^\n]*)?\s*\}", re.MULTILINE),
        "empty catch blocks are forbidden",
    ),
    (
        "print-logging",
        re.compile(r"\bprint\s*\("),
        "print logging is forbidden in runtime code; use the project logger",
    ),
    (
        "xctest-import",
        re.compile(r"^\s*import\s+XCTest\b", re.MULTILINE),
        "runtime source must not import XCTest",
    ),
)


def is_test_path(path: Path) -> bool:
    rel = path.as_posix().lower()
    return "/tests/" in rel or rel.endswith("tests.swift") or "testsupport" in rel


def has_allow_marker(line: str, previous: str) -> bool:
    return "pitchai-allow-" in line or "pitchai-allow-" in previous


def swift_code_without_literals(
    line: str,
    block_comment_depth: int,
    in_multiline_string: bool,
) -> tuple[str, int, bool]:
    """Blank comments and strings while preserving source offsets for regex rules."""
    output = [" "] * len(line)
    index = 0
    while index < len(line):
        if in_multiline_string:
            end = line.find('"""', index)
            if end == -1:
                return "".join(output), block_comment_depth, True
            index = end + 3
            in_multiline_string = False
            continue
        if block_comment_depth:
            if line.startswith("/*", index):
                block_comment_depth += 1
                index += 2
            elif line.startswith("*/", index):
                block_comment_depth -= 1
                index += 2
            else:
                index += 1
            continue
        if line.startswith("//", index):
            break
        if line.startswith("/*", index):
            block_comment_depth = 1
            index += 2
            continue
        if line.startswith('"""', index):
            in_multiline_string = True
            index += 3
            continue
        if line[index] == '"':
            index += 1
            while index < len(line):
                if line[index] == "\\":
                    index += 2
                    continue
                if line[index] == '"':
                    index += 1
                    break
                index += 1
            continue
        output[index] = line[index]
        index += 1
    return "".join(output), block_comment_depth, in_multiline_string


def gate_pitchai_patterns(config: CheckConfig) -> int:
    print_header("PitchAI Swift pattern rules")
    failures: list[str] = []
    for path in swift_files(config.root):
        rel = path.relative_to(config.root)
        if is_test_path(rel):
            continue
        if any(rel.as_posix().startswith(prefix.rstrip("/") + "/") for prefix in config.generated_allowlist):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        previous = ""
        block_comment_depth = 0
        in_multiline_string = False
        for line_number, line in enumerate(lines, start=1):
            code, block_comment_depth, in_multiline_string = swift_code_without_literals(
                line,
                block_comment_depth,
                in_multiline_string,
            )
            if has_allow_marker(line, previous):
                previous = line
                continue
            for rule_id, pattern, message in FORBIDDEN_PATTERNS:
                if pattern.search(code):
                    failures.append(f"{rel}:{line_number}: {rule_id}: {message}")
            previous = line
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


SECRET_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("generic-api-key", re.compile(r"(?i)(api[_-]?key|secret|token)\s*[:=]\s*[\"'][A-Za-z0-9_\-]{20,}[\"']")),
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
)


def gate_builtin_secrets(config: CheckConfig) -> int:
    print_header("built-in secret pattern scan")
    failures: list[str] = []
    for path in config.root.rglob("*"):
        if not path.is_file() or should_skip(path, config.root):
            continue
        if path.stat().st_size > 1_000_000:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        rel = path.relative_to(config.root)
        for name, pattern in SECRET_PATTERNS:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                failures.append(f"{rel}:{line}: {name}: secret-like string is forbidden")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


def gate_gitleaks(config: CheckConfig) -> int:
    if not config.enable_gitleaks:
        print_header("gitleaks skipped by IOS_CHECK_ENABLE_GITLEAKS=0")
        return 0
    print_header("gitleaks")
    if not tool_exists("gitleaks"):
        print("FAIL: gitleaks is required but missing", file=sys.stderr)
        return 1
    command = ["gitleaks", "detect", "--source", ".", "--no-banner", "--redact"]
    if (config.root / ".gitleaks.toml").exists():
        command.extend(["--config", ".gitleaks.toml"])
    return run_command(command, cwd=config.root)


def gate_semgrep(config: CheckConfig) -> int:
    if not config.enable_semgrep:
        print_header("semgrep skipped by IOS_CHECK_ENABLE_SEMGREP=0")
        return 0
    print_header("semgrep")
    if not (config.root / config.semgrep_config).exists():
        print(f"FAIL: {config.semgrep_config} is required for the Semgrep gate", file=sys.stderr)
        return 1
    if not tool_exists("semgrep"):
        print("FAIL: semgrep is required but missing", file=sys.stderr)
        return 1
    return run_command(
        ["semgrep", "--config", config.semgrep_config, "--error", "--metrics=off", "."],
        cwd=config.root,
    )


def gate_spm_resolve(config: CheckConfig) -> int:
    if not config.enable_spm:
        print_header("SwiftPM checks not applicable")
        return 0
    print_header("SwiftPM manifest, resolve, strict build, and test")
    package_root = spm_package_root(config)
    if package_root is None:
        print("FAIL: IOS_CHECK_SPM_PATH must stay inside the repository root", file=sys.stderr)
        return 1
    if not (package_root / "Package.swift").is_file():
        print(
            f"FAIL: IOS_CHECK_ENABLE_SPM=1 but {config.spm_path}/Package.swift is missing",
            file=sys.stderr,
        )
        return 1
    if not tool_exists("swift"):
        print("FAIL: swift is required for SwiftPM checks but missing", file=sys.stderr)
        return 1
    commands = [
        ["swift", "package", "dump-package"],
        ["swift", "package", "resolve"],
        [
            "swift",
            "build",
            "-Xswiftc",
            "-warnings-as-errors",
            "-Xswiftc",
            "-strict-concurrency=complete",
        ],
    ]
    if config.enable_spm_tests:
        commands.append(
            [
                "swift",
                "test",
                "-Xswiftc",
                "-warnings-as-errors",
                "-Xswiftc",
                "-strict-concurrency=complete",
            ]
        )
    else:
        print("SwiftPM tests explicitly disabled by IOS_CHECK_ENABLE_SPM_TESTS=0")
    for command in commands:
        code = run_command(command, cwd=package_root)
        if code != 0:
            return code
    return 0


def gate_xcode_build(config: CheckConfig) -> int:
    if not config.enable_xcode:
        print_header("xcode build not configured")
        return 0
    print_header("xcodebuild build-for-testing")
    if not tool_exists("xcodebuild"):
        print("FAIL: xcodebuild is required for configured Xcode gates", file=sys.stderr)
        return 1
    command = ["xcodebuild", *xcode_common_args(config), "build-for-testing"]
    return run_command(command, cwd=config.root, log_path=config.root / ".build" / "logs" / "xcodebuild-build.log")


def gate_swiftlint_analyze(config: CheckConfig) -> int:
    if not config.enable_swiftlint or not config.enable_xcode:
        print_header("SwiftLint analyze not applicable")
        return 0
    print_header("swiftlint analyze")
    log_path = config.root / ".build" / "logs" / "xcodebuild-build.log"
    if not log_path.exists():
        print("FAIL: compiler log missing; run xcode-build-for-testing before swiftlint-analyze", file=sys.stderr)
        return 1
    if not tool_exists("swiftlint"):
        print("FAIL: swiftlint is required but missing", file=sys.stderr)
        return 1
    return run_command(["swiftlint", "analyze", "--strict", "--compiler-log-path", str(log_path)], cwd=config.root)


def gate_xcode_analyze(config: CheckConfig) -> int:
    if not config.enable_xcode:
        print_header("xcode analyze not configured")
        return 0
    print_header("xcodebuild analyze")
    if not tool_exists("xcodebuild"):
        print("FAIL: xcodebuild is required for configured Xcode gates", file=sys.stderr)
        return 1
    command = ["xcodebuild", *xcode_common_args(config), "analyze"]
    return run_command(command, cwd=config.root, log_path=config.root / ".build" / "logs" / "xcodebuild-analyze.log")


def gate_xcode_test(config: CheckConfig) -> int:
    if not config.enable_tests:
        print_header("xcode test not configured")
        return 0
    print_header("xcodebuild test")
    if not config.enable_xcode:
        print("FAIL: tests are enabled but Xcode gates are disabled", file=sys.stderr)
        return 1
    if not tool_exists("xcodebuild"):
        print("FAIL: xcodebuild is required for configured test gates", file=sys.stderr)
        return 1
    command = ["xcodebuild", *xcode_common_args(config), "test"]
    return run_command(command, cwd=config.root, log_path=config.root / ".build" / "logs" / "xcodebuild-test.log")


def gate_periphery(config: CheckConfig) -> int:
    if not config.enable_periphery:
        print_header("Periphery not enabled")
        return 0
    print_header("periphery")
    if not tool_exists("periphery"):
        print("FAIL: periphery is enabled but missing", file=sys.stderr)
        return 1
    return run_command(["periphery", "scan"], cwd=config.root)


def gate_snapshot_marker(config: CheckConfig) -> int:
    if not config.enable_snapshots:
        print_header("snapshot/UI checks not enabled")
        return 0
    print_header("snapshot/UI project gate")
    marker = config.root / "Tests" / "SnapshotTests"
    if not marker.exists():
        print("FAIL: snapshot checks are enabled but Tests/SnapshotTests is missing", file=sys.stderr)
        return 1
    return 0


def gates() -> list[Gate]:
    return [
        Gate("preflight", "toolchain and project-shape preflight", gate_preflight),
        Gate("format-swift-format", "swift-format lint", gate_swift_format),
        Gate("format-swiftformat", "SwiftFormat lint mode", gate_swiftformat),
        Gate("swiftlint", "SwiftLint strict lint", gate_swiftlint),
        Gate("pitchai-patterns", "PitchAI forbidden Swift patterns", gate_pitchai_patterns),
        Gate("secrets-builtin", "built-in secret scan", gate_builtin_secrets),
        Gate("gitleaks", "Gitleaks secret scan", gate_gitleaks),
        Gate("semgrep", "Semgrep Swift/iOS rules", gate_semgrep),
        Gate(
            "spm-resolve",
            "SwiftPM manifest, dependency, strict build, and test checks",
            gate_spm_resolve,
        ),
        Gate("xcode-build-for-testing", "xcodebuild build-for-testing with warnings as errors", gate_xcode_build),
        Gate("swiftlint-analyze", "SwiftLint analyzer rules from compiler log", gate_swiftlint_analyze),
        Gate("xcode-analyze", "xcodebuild static analyzer", gate_xcode_analyze),
        Gate("xcode-test", "XCTest/XCUITest simulator tests", gate_xcode_test),
        Gate("periphery", "Periphery dead-code scan", gate_periphery),
        Gate("ui-snapshots", "project-specific UI/snapshot marker", gate_snapshot_marker),
    ]


def run_gates(config: CheckConfig, *, only: str | None, skip: set[str]) -> int:
    selected = [gate for gate in gates() if only is None or gate.name == only]
    if only is not None and not selected:
        print(f"Unknown gate: {only}", file=sys.stderr)
        return 2
    failures: list[str] = []
    for gate in selected:
        if gate.name in skip:
            print_header(f"{gate.name} skipped by explicit --skip")
            continue
        code = gate.run(config)
        if code != 0:
            failures.append(f"{gate.name}={code}")
    if failures:
        print("\nFAILED iOS quality gates: " + ", ".join(failures), file=sys.stderr)
        return 1
    print("\nAll selected iOS quality gates passed.")
    return 0


def print_gate_list() -> None:
    for gate in gates():
        print(f"{gate.name}: {gate.description}")


def write_probe_project(root: Path) -> None:
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
        'let api_key = "' + "abcdefghijklmnopqrstuvwxyz" + '123456"\n',
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


def run_probe() -> int:
    print_header("activation probe")
    with tempfile.TemporaryDirectory(prefix="pitchai-ios-probe-") as tmp:
        root = Path(tmp)
        write_probe_project(root)
        config = config_from_env(root)
        required_failures = {
            "pitchai-patterns": gate_pitchai_patterns,
            "secrets-builtin": gate_builtin_secrets,
        }
        failures: list[str] = []
        for name, runner in required_failures.items():
            code = runner(config)
            if code == 0:
                failures.append(f"{name} did not fail on injected violation")
        aggregate_code = run_gates(config, only=None, skip=set())
        if aggregate_code == 0:
            failures.append("aggregate command did not fail on injected violations")
        if tool_exists("swift"):
            old_spm = os.environ.get("IOS_CHECK_ENABLE_SPM")
            old_spm_tests = os.environ.get("IOS_CHECK_ENABLE_SPM_TESTS")
            os.environ["IOS_CHECK_ENABLE_SPM"] = "1"
            os.environ["IOS_CHECK_ENABLE_SPM_TESTS"] = "1"
            try:
                test_code = gate_spm_resolve(config_from_env(root))
            finally:
                if old_spm is None:
                    os.environ.pop("IOS_CHECK_ENABLE_SPM", None)
                else:
                    os.environ["IOS_CHECK_ENABLE_SPM"] = old_spm
                if old_spm_tests is None:
                    os.environ.pop("IOS_CHECK_ENABLE_SPM_TESTS", None)
                else:
                    os.environ["IOS_CHECK_ENABLE_SPM_TESTS"] = old_spm_tests
            if test_code == 0:
                failures.append(
                    "SwiftPM strict build/test gate did not fail on injected XCTest violation"
                )
        else:
            print("swift missing; XCTest failure probe requires macOS/Xcode or Swift toolchain")
        shim_code = run_probe_with_failing_tools(root)
        if shim_code != 0:
            failures.append("external tool failure probe did not behave as expected")
        if failures:
            print("\n".join(failures), file=sys.stderr)
            return 1
    print("Activation probe confirmed representative nonzero failures.")
    return 0


def write_failing_tool(path: Path, message: str) -> None:
    path.write_text(f"#!/usr/bin/env bash\necho '{message}' >&2\nexit 1\n", encoding="utf-8")
    path.chmod(0o755)


def run_probe_with_failing_tools(root: Path) -> int:
    print_header("external tool failure shims")
    bin_dir = root / "fake-bin"
    bin_dir.mkdir()
    write_failing_tool(bin_dir / "swift-format", "simulated swift-format lint violation")
    write_failing_tool(bin_dir / "swiftlint", "simulated SwiftLint violation")
    write_failing_tool(bin_dir / "gitleaks", "simulated gitleaks secret finding")
    write_failing_tool(bin_dir / "semgrep", "simulated Semgrep finding")
    write_failing_tool(bin_dir / "xcodebuild", "simulated xcodebuild warning-as-error/test failure")

    old_path = os.environ.get("PATH", "")
    old_values = {key: os.environ.get(key) for key in os.environ if key.startswith("IOS_CHECK_")}
    os.environ["PATH"] = f"{bin_dir}{os.pathsep}{old_path}"
    os.environ["IOS_CHECK_ENABLE_SWIFT_FORMAT"] = "1"
    os.environ["IOS_CHECK_ENABLE_SWIFTLINT"] = "1"
    os.environ["IOS_CHECK_ENABLE_GITLEAKS"] = "1"
    os.environ["IOS_CHECK_ENABLE_SEMGREP"] = "1"
    os.environ["IOS_CHECK_ENABLE_SPM"] = "0"
    os.environ["IOS_CHECK_ENABLE_SPM_TESTS"] = "0"
    os.environ["IOS_CHECK_ENABLE_XCODE"] = "1"
    os.environ["IOS_CHECK_REQUIRE_XCODE"] = "1"
    os.environ["IOS_CHECK_ENABLE_TESTS"] = "1"
    os.environ["IOS_CHECK_WORKSPACE"] = "ProbeApp.xcworkspace"
    os.environ["IOS_CHECK_SCHEME"] = "ProbeApp"
    try:
        (root / ".semgrep.yml").write_text("rules: []\n", encoding="utf-8")
        config = config_from_env(root)
        expected = {
            "format-swift-format": gate_swift_format,
            "swiftlint": gate_swiftlint,
            "gitleaks": gate_gitleaks,
            "semgrep": gate_semgrep,
            "xcode-build-for-testing": gate_xcode_build,
            "xcode-test": gate_xcode_test,
        }
        failures: list[str] = []
        for name, runner in expected.items():
            code = runner(config)
            if code == 0:
                failures.append(f"{name} did not fail with failing shim")
        if failures:
            print("\n".join(failures), file=sys.stderr)
            return 1
        print("External formatter/linter/security/build/test failure shims returned nonzero as expected.")
        return 0
    finally:
        os.environ["PATH"] = old_path
        for key in [key for key in os.environ if key.startswith("IOS_CHECK_")]:
            if key not in old_values:
                del os.environ[key]
        for key, value in old_values.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list gates and exit")
    parser.add_argument("--only", help="run one named gate")
    parser.add_argument("--skip", action="append", default=[], help="skip one named gate")
    parser.add_argument("--ci", action="store_true", help="CI mode marker; gates remain fail-closed")
    parser.add_argument("--probe", action="store_true", help="run activation probes")
    args = parser.parse_args(argv)

    if args.list:
        print_gate_list()
        return 0
    if args.probe:
        return run_probe()

    config = config_from_env(ROOT)
    return run_gates(config, only=args.only, skip=set(args.skip))


if __name__ == "__main__":
    raise SystemExit(main())
