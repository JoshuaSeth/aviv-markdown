# Copyright (c) 2026 PitchAI. All rights reserved.
"""PitchAI-specific source analysis for runtime Swift files."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from typing import TYPE_CHECKING

from .runtime import swift_files, write_header

if TYPE_CHECKING:
    from pathlib import Path

    from .model import CheckConfig

FORBIDDEN_PATTERNS: tuple[tuple[str, re.Pattern[str], str], ...] = (
    (
        "force-unwrap",
        re.compile(r"(?<=[A-Za-z0-9_)\]}])!(?!=)"),
        "force unwrap is forbidden in runtime code without a pitchai-allow marker",
    ),
    ("force-try", re.compile(r"\btry!(?!\w)"), "force try is forbidden in runtime code"),
    ("silent-try", re.compile(r"\btry\?(?!\w)"), "try? is forbidden outside an explicitly documented edge"),
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
    ("xctest-import", re.compile(r"^\s*import\s+XCTest\b", re.MULTILINE), "runtime source must not import XCTest"),
)


@dataclass
class _SwiftLexicalState:
    block_comment_depth: int = 0
    in_multiline_string: bool = False

    def strip_literals(self, line: str) -> str:
        """Blank comments and strings while preserving source offsets.

        Returns:
            A same-length source line containing only executable Swift code.
        """
        output = [" "] * len(line)
        index = 0
        while index < len(line):
            if self.in_multiline_string:
                index = self._finish_multiline_string(line, index)
                continue
            if self.block_comment_depth:
                index = self._advance_block_comment(line, index)
                continue
            if line.startswith("//", index):
                break
            if line.startswith("/*", index):
                self.block_comment_depth = 1
                index += 2
                continue
            if line.startswith('"""', index):
                self.in_multiline_string = True
                index += 3
                continue
            if line[index] == '"':
                index = self._finish_quoted_string(line, index + 1)
                continue
            output[index] = line[index]
            index += 1
        return "".join(output)

    def _finish_multiline_string(self, line: str, index: int) -> int:
        end = line.find('"""', index)
        if end == -1:
            return len(line)
        self.in_multiline_string = False
        return end + 3

    def _advance_block_comment(self, line: str, index: int) -> int:
        if line.startswith("/*", index):
            self.block_comment_depth += 1
            return index + 2
        if line.startswith("*/", index):
            self.block_comment_depth -= 1
            return index + 2
        return index + 1

    @staticmethod
    def _finish_quoted_string(line: str, index: int) -> int:
        while index < len(line):
            if line[index] == "\\":
                index += 2
                continue
            if line[index] == '"':
                return index + 1
            index += 1
        return index


@dataclass(frozen=True)
class SwiftPatternScanner:
    """Scan non-test Swift source for forbidden runtime patterns."""

    _config: CheckConfig

    def run(self) -> int:
        """Run the Swift source policy scan.

        Returns:
            Zero when no forbidden patterns are present; otherwise one.
        """
        write_header("PitchAI Swift pattern rules")
        failures = self._find_failures()
        if failures:
            failure_report = "\n".join(failures)
            sys.stderr.write(f"{failure_report}\n")
            return 1
        return 0

    def _find_failures(self) -> list[str]:
        failures: list[str] = []
        root = self._config.project.root
        for path in swift_files(root):
            relative = path.relative_to(root)
            if self._is_test_path(relative) or self._is_generated(relative):
                continue
            self._scan_file(path, relative, failures)
        return failures

    @staticmethod
    def _scan_file(path: Path, relative: Path, failures: list[str]) -> None:
        previous = ""
        lexical_state = _SwiftLexicalState()
        lines = path.read_text(encoding="utf-8").splitlines()
        for line_number, line in enumerate(lines, start=1):
            code = lexical_state.strip_literals(line)
            if "pitchai-allow-" in line or "pitchai-allow-" in previous:
                previous = line
                continue
            for rule_id, pattern, message in FORBIDDEN_PATTERNS:
                if pattern.search(code):
                    failures.append(f"{relative}:{line_number}: {rule_id}: {message}")
            previous = line

    def _is_generated(self, relative: Path) -> bool:
        relative_text = relative.as_posix()
        for prefix in self._config.project.generated_allowlist:
            if relative_text.startswith(f"{prefix.rstrip('/')}/"):
                return True
        return False

    @staticmethod
    def _is_test_path(path: Path) -> bool:
        relative = path.as_posix().lower()
        return "/tests/" in relative or relative.endswith("tests.swift") or "testsupport" in relative
