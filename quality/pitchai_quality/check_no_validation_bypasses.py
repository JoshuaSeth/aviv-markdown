# Copyright (c) 2026 PitchAI. All rights reserved.
"""Reject validation suppressions, source exclusions, and fail-open wiring."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast

from pitchai_quality.source_files import NON_SOURCE_DIRECTORY_NAMES, REPOSITORY_ROOT, iter_python_files
from pitchai_quality.strict_policy import EXPECTED_NORMALIZED_STRICT_WORKFLOW_SHA256, INLINE_BYPASS

if TYPE_CHECKING:
    from pathlib import Path

_QUALITY_ROOT = REPOSITORY_ROOT / "quality"
_MANIFEST_PATH = _QUALITY_ROOT / "portable-enforcement-manifest.json"
_STRICT_WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "python-strict.yml"
_ANTI_BYPASS_PATH = "quality/pitchai_quality/check_no_validation_bypasses.py"
_MANIFEST_RELATIVE_PATH = "quality/portable-enforcement-manifest.json"
_STRICT_WORKFLOW_RELATIVE_PATH = ".github/workflows/python-strict.yml"
_EXPECTED_PORTABLE_MANIFEST_SHA256 = "2d00a20f544e626a8402d775233f5b83773a7671eba5b3429de1868d8663ec2a"
_EXPECTED_MANIFESTED_PATHS = (
    "QUALITY.md", "quality/.gitignore", "quality/.semgrep.yml", "quality/.semgrepignore",
    "quality/pitchai_quality/__init__.py", "quality/pitchai_quality/analysis_support.py",
    "quality/pitchai_quality/check.py", "quality/pitchai_quality/check_nested_event_loops.py",
    "quality/pitchai_quality/check_no_dense_inline_comprehensions.py",
    "quality/pitchai_quality/check_no_pure_wrapper_functions.py",
    "quality/pitchai_quality/check_no_single_use_one_line_functions.py",
    "quality/pitchai_quality/check_no_vague_signatures.py",
    "quality/pitchai_quality/pure_wrapper_index.py", "quality/pitchai_quality/pure_wrapper_resolution.py",
    "quality/pitchai_quality/single_use_reporting.py", "quality/pitchai_quality/source_files.py",
    "quality/pitchai_quality/strict_policy.py", "quality/pyproject.toml", "quality/uv.lock",
)
_CONFIG_PATHS = (
    _QUALITY_ROOT / "pyproject.toml", _QUALITY_ROOT / ".semgrep.yml",
    _QUALITY_ROOT / ".semgrepignore", _STRICT_WORKFLOW_PATH,
)
_DIRECT_TOOLCHAIN = re.compile(
    r"\b(?:ruff|basedpyright|pyright|pylint|semgrep)\b|"
    r"uv\s+run[^\n]*\b(?:quality|check)\b|pitchai_quality\.check",
    re.IGNORECASE,
)
_ACTION_REFERENCE = re.compile(r"^\s*(?:-\s*)?uses:\s*(\S+)")
_PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-fA-F]{40}$")
_CONTINUE_ON_ERROR_TRUE = re.compile(
    r"^\s*continue-on-error:\s*(?:true|[\"']true[\"'])\s*(?:#.*)?$", re.IGNORECASE,
)
_VERIFIER_DIGEST_ASSIGNMENT = re.compile(
    r'^(?P<prefix>\s*expected_verifier_sha256=")(?P<digest>[0-9a-f]{64})(?P<suffix>"\s*)$', re.MULTILINE,
)
_CONFLICTING_ROOT_CONFIGS = (
    ".ruff.toml", "ruff.toml", "pyrightconfig.json", "basedpyrightconfig.json",
    ".pylintrc", "pylintrc", "setup.cfg", "tox.ini",
)


@dataclass(frozen=True)
class Violation:
    """One validation bypass with source location and explanation."""

    path: Path
    line: int
    reason: str


def _portable_disk_paths() -> set[str]:
    paths: set[str] = set()
    for path in _QUALITY_ROOT.rglob("*"):
        relative_parts = path.relative_to(_QUALITY_ROOT).parts
        generated = NON_SOURCE_DIRECTORY_NAMES.intersection(relative_parts) or any(
            part.endswith(".egg-info") for part in relative_parts
        )
        if not generated and (path.is_file() or path.is_symlink()):
            paths.add(path.relative_to(REPOSITORY_ROOT).as_posix())
    for relative in (_STRICT_WORKFLOW_RELATIVE_PATH, "QUALITY.md"):
        path = REPOSITORY_ROOT / relative
        if path.is_file() or path.is_symlink():
            paths.add(relative)
    return paths


def _manifest_files(manifest_bytes: bytes) -> dict[str, str] | None:
    payload_value = cast("object", json.loads(manifest_bytes))
    if not isinstance(payload_value, dict):
        return None
    payload = cast("dict[object, object]", payload_value)
    if set(payload) != {"schema", "files"} or payload.get("schema") != 1:
        return None
    raw_files_value = payload.get("files")
    if not isinstance(raw_files_value, dict):
        return None
    raw_files = cast("dict[object, object]", raw_files_value)
    if not all(isinstance(path, str) and isinstance(digest, str) for path, digest in raw_files.items()):
        return None
    return cast("dict[str, str]", raw_files)


def _portable_manifest_violations() -> list[Violation]:
    if not _MANIFEST_PATH.is_file():
        return [Violation(_MANIFEST_PATH, 1, "portable enforcement manifest is missing")]
    manifest_bytes = _MANIFEST_PATH.read_bytes()
    violations: list[Violation] = []
    if hashlib.sha256(manifest_bytes).hexdigest() != _EXPECTED_PORTABLE_MANIFEST_SHA256:
        violations.append(Violation(_MANIFEST_PATH, 1, "portable enforcement manifest digest changed"))
    files = _manifest_files(manifest_bytes)
    if files is None:
        return [*violations, Violation(_MANIFEST_PATH, 1, "portable enforcement manifest is malformed")]
    if set(files) != set(_EXPECTED_MANIFESTED_PATHS):
        violations.append(Violation(_MANIFEST_PATH, 1, "portable enforcement manifest membership changed"))
    unmanifested = {_ANTI_BYPASS_PATH, _MANIFEST_RELATIVE_PATH, _STRICT_WORKFLOW_RELATIVE_PATH}
    expected_disk_paths = {*_EXPECTED_MANIFESTED_PATHS, *unmanifested}
    disk_paths = _portable_disk_paths()
    violations.extend(
        Violation(REPOSITORY_ROOT / path, 1, "unexpected portable enforcement file")
        for path in sorted(disk_paths - expected_disk_paths)
    )
    violations.extend(
        Violation(REPOSITORY_ROOT / path, 1, "required portable enforcement file is missing")
        for path in sorted(expected_disk_paths - disk_paths)
    )
    for relative in sorted(expected_disk_paths):
        path = REPOSITORY_ROOT / relative
        if path.is_symlink():
            violations.append(Violation(path, 1, "portable enforcement file may not be a symlink"))
    for relative, expected_digest in files.items():
        path = REPOSITORY_ROOT / relative
        actual_digest = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
        if not path.is_symlink() and actual_digest is not None and actual_digest != expected_digest:
            violations.append(Violation(path, 1, "portable enforcement file hash changed"))
    return violations


def _workflow_block(workflow_text: str, heading: str) -> tuple[str, ...] | None:
    lines = workflow_text.splitlines()
    indexes: list[int] = []
    for index, line in enumerate(lines):
        if line == f"{heading}:":
            indexes.append(index)
    if len(indexes) != 1:
        return None
    block: list[str] = []
    for line in lines[indexes[0] + 1 :]:
        if line and not line.startswith(" "):
            break
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            block.append(stripped)
    return tuple(block)


def _strict_workflow_violations() -> list[Violation]:
    if not _STRICT_WORKFLOW_PATH.is_file():
        return []
    workflow_text = _STRICT_WORKFLOW_PATH.read_text(encoding="utf-8")
    violations: list[Violation] = []
    if _workflow_block(workflow_text, "on") != ("pull_request:", "push:", "workflow_dispatch:"):
        violations.append(Violation(_STRICT_WORKFLOW_PATH, 1, "strict workflow triggers must cover every PR and push"))
    if _workflow_block(workflow_text, "permissions") != ("contents: read",):
        violations.append(Violation(_STRICT_WORKFLOW_PATH, 1, "strict workflow permissions must be read-only contents"))
    stripped_lines = tuple(line.strip() for line in workflow_text.splitlines())
    required_commands = (
        "run: uv sync --project quality --python 3.12 --frozen",
        "run: uv run --project quality --python 3.12 --frozen check",
    )
    for command in required_commands:
        if stripped_lines.count(command) != 1:
            violations.append(Violation(_STRICT_WORKFLOW_PATH, 1, "strict workflow frozen commands changed"))
            break
    digest_matches = list(_VERIFIER_DIGEST_ASSIGNMENT.finditer(workflow_text))
    if len(digest_matches) != 1:
        violations.append(Violation(_STRICT_WORKFLOW_PATH, 1, "strict workflow verifier trust anchor is missing"))
        return violations
    match = digest_matches[0]
    verifier_path = REPOSITORY_ROOT / _ANTI_BYPASS_PATH
    actual_verifier_digest = hashlib.sha256(verifier_path.read_bytes()).hexdigest()
    if match.group("digest") != actual_verifier_digest:
        violations.append(Violation(_STRICT_WORKFLOW_PATH, 1, "strict workflow verifier trust anchor is stale"))
    workflow_before_digest = workflow_text[: match.start("digest")]
    workflow_after_digest = workflow_text[match.end("digest") :]
    normalized_workflow = f"{workflow_before_digest}<VERIFIER_SHA256>{workflow_after_digest}"
    normalized_digest = hashlib.sha256(normalized_workflow.encode()).hexdigest()
    if normalized_digest != EXPECTED_NORMALIZED_STRICT_WORKFLOW_SHA256:
        violations.append(Violation(_STRICT_WORKFLOW_PATH, 1, "strict workflow semantics changed"))
    return violations


def _inline_violations() -> list[Violation]:
    violations: list[Violation] = []
    for path in (*iter_python_files((REPOSITORY_ROOT,)), *_CONFIG_PATHS):
        if not path.is_file():
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if INLINE_BYPASS.search(line):
                violations.append(Violation(path, line_number, "inline validation suppression is forbidden"))
    return violations


def _workflow_and_toolchain_violations() -> list[Violation]:
    violations: list[Violation] = []
    for relative in _CONFLICTING_ROOT_CONFIGS:
        path = REPOSITORY_ROOT / relative
        if path.exists():
            violations.append(Violation(path, 1, "alternate root quality-tool configuration is forbidden"))
    for workflow in sorted((REPOSITORY_ROOT / ".github" / "workflows").glob("*")):
        if workflow.suffix not in {".yml", ".yaml"}:
            continue
        workflow_text = workflow.read_text(encoding="utf-8")
        if workflow != _STRICT_WORKFLOW_PATH and _DIRECT_TOOLCHAIN.search(workflow_text):
            violations.append(Violation(workflow, 1, "alternate workflow quality-tool entrypoint is forbidden"))
        for line_number, line in enumerate(workflow_text.splitlines(), start=1):
            match = _ACTION_REFERENCE.match(line)
            action = match.group(1).strip("\"'") if match is not None else None
            if action is not None and not action.startswith("./") and _PINNED_ACTION.fullmatch(action) is None:
                violations.append(Violation(workflow, line_number, f"mutable workflow action reference: {action}"))
            if _CONTINUE_ON_ERROR_TRUE.match(line):
                violations.append(Violation(workflow, line_number, "workflow continue-on-error is forbidden"))
    return [*violations, *_strict_workflow_violations()]


def main() -> int:
    """Validate that every strict gate is complete and fail-closed.

    Returns:
        Zero when the complete policy is intact; otherwise one.
    """
    violations = [
        *_portable_manifest_violations(), *_workflow_and_toolchain_violations(), *_inline_violations(),
    ]
    if violations:
        for violation in violations:
            relative = violation.path.relative_to(REPOSITORY_ROOT)
            sys.stderr.write(f"{relative}:{violation.line}: {violation.reason}\n")
        return 1
    sys.stdout.write("ok no_validation_bypasses\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
