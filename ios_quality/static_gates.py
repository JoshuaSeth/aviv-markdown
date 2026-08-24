# Copyright (c) 2026 PitchAI. All rights reserved.
"""Formatter, linter, source-policy, and secret gates."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from typing import TYPE_CHECKING

from .model import Gate
from .runtime import should_skip, swift_files, tool_exists, write_header
from .swift_source import SwiftPatternScanner

if TYPE_CHECKING:
    from pathlib import Path

    from .model import CheckConfig
    from .runtime import ProcessRunner

SECRET_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "generic-api-key",
        re.compile(r"(?i)(api[_-]?key|secret|token)\s*[:=]\s*[\"'][A-Za-z0-9_\-]{20,}[\"']"),
    ),
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
)
_MAX_SECRET_SCAN_BYTES = 1_000_000


@dataclass(frozen=True)
class StaticGateRunner:
    """Provide formatter, linter, source-policy, and security gates."""

    _config: CheckConfig
    _process: ProcessRunner

    def gates(self) -> tuple[Gate, ...]:
        """Build this runner's ordered gate definitions.

        Returns:
            Static and security gate definitions.
        """
        return (
            Gate("format-swift-format", "swift-format lint", self._swift_format),
            Gate("format-swiftformat", "SwiftFormat lint mode", self._swiftformat),
            Gate("swiftlint", "SwiftLint strict lint", self._swiftlint),
            Gate("pitchai-patterns", "PitchAI forbidden Swift patterns", self._pitchai_patterns),
            Gate("secrets-builtin", "built-in secret scan", self._builtin_secrets),
            Gate("gitleaks", "Gitleaks secret scan", self._gitleaks),
            Gate("semgrep", "Semgrep Swift/iOS rules", self._semgrep),
        )

    def _swift_format(self) -> int:
        if not self._config.static.swift_format:
            write_header("swift-format lint skipped by IOS_CHECK_ENABLE_SWIFT_FORMAT=0")
            return 0
        write_header("swift-format lint")
        if not tool_exists("swift-format"):
            sys.stderr.write("FAIL: swift-format is required but missing\n")
            return 1
        root = self._config.project.root
        files = swift_files(root)
        relative_files = [str(path.relative_to(root)) for path in files]
        command = ("swift-format", "lint", "--strict", "--recursive", *relative_files)
        return self._process.run(command, cwd=root)

    def _swiftformat(self) -> int:
        if not self._config.static.swiftformat:
            write_header("SwiftFormat lint not enabled")
            return 0
        write_header("swiftformat --lint")
        if not tool_exists("swiftformat"):
            sys.stderr.write("FAIL: swiftformat is enabled but missing\n")
            return 1
        return self._process.run(("swiftformat", "--lint", "."), cwd=self._config.project.root)

    def _swiftlint(self) -> int:
        if not self._config.static.swiftlint:
            write_header("SwiftLint skipped by IOS_CHECK_ENABLE_SWIFTLINT=0")
            return 0
        write_header("swiftlint")
        if not tool_exists("swiftlint"):
            sys.stderr.write("FAIL: swiftlint is required but missing\n")
            return 1
        command = ["swiftlint", "lint", "--strict"]
        if (self._config.project.root / ".swiftlint.yml").exists():
            command.extend(("--config", ".swiftlint.yml"))
        return self._process.run(command, cwd=self._config.project.root)

    def _pitchai_patterns(self) -> int:
        scanner = SwiftPatternScanner(self._config)
        status = scanner.run()
        if status != 0:
            return status
        return 0

    def _builtin_secrets(self) -> int:
        write_header("built-in secret pattern scan")
        failures: list[str] = []
        root = self._config.project.root
        for path in root.rglob("*"):
            if not path.is_file() or path.is_symlink() or should_skip(path, root):
                continue
            if path.stat().st_size > _MAX_SECRET_SCAN_BYTES:
                continue
            self._scan_secret_file(path, failures)
        if failures:
            failure_report = "\n".join(failures)
            sys.stderr.write(f"{failure_report}\n")
            return 1
        return 0

    def _scan_secret_file(self, path: Path, failures: list[str]) -> None:
        text = path.read_text(encoding="utf-8", errors="surrogateescape")
        relative = path.relative_to(self._config.project.root)
        for name, pattern in SECRET_PATTERNS:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                failures.append(f"{relative}:{line}: {name}: secret-like string is forbidden")

    def _gitleaks(self) -> int:
        if not self._config.static.gitleaks:
            write_header("gitleaks skipped by IOS_CHECK_ENABLE_GITLEAKS=0")
            return 0
        write_header("gitleaks")
        if not tool_exists("gitleaks"):
            sys.stderr.write("FAIL: gitleaks is required but missing\n")
            return 1
        command = ["gitleaks", "detect", "--source", ".", "--no-banner", "--redact"]
        if (self._config.project.root / ".gitleaks.toml").exists():
            command.extend(("--config", ".gitleaks.toml"))
        return self._process.run(command, cwd=self._config.project.root)

    def _semgrep(self) -> int:
        if not self._config.static.semgrep:
            write_header("semgrep skipped by IOS_CHECK_ENABLE_SEMGREP=0")
            return 0
        write_header("semgrep")
        config_path = self._config.project.root / self._config.project.semgrep_config
        if not config_path.exists():
            sys.stderr.write(f"FAIL: {self._config.project.semgrep_config} is required for the Semgrep gate\n")
            return 1
        if not tool_exists("semgrep"):
            sys.stderr.write("FAIL: semgrep is required but missing\n")
            return 1
        command = ("semgrep", "--config", self._config.project.semgrep_config, "--error", "--metrics=off", ".")
        return self._process.run(command, cwd=self._config.project.root)
