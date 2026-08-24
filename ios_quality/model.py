# Copyright (c) 2026 PitchAI. All rights reserved.
"""Typed configuration and gate models for the native quality runner."""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path


@dataclass(frozen=True)
class ProjectConfig:
    """Repository paths and target identifiers used by native checks."""

    root: Path
    spm_path: str
    workspace: str
    project: str
    scheme: str
    generated_allowlist: tuple[str, ...]
    semgrep_config: str


@dataclass(frozen=True)
class XcodeConfig:
    """Xcode command settings shared by build, analysis, and test gates."""

    configuration: str
    destination: str
    derived_data: str
    package_authorization_provider: str


@dataclass(frozen=True)
class StaticGateConfig:
    """Enablement switches for formatter, linter, and security gates."""

    swift_format: bool
    swiftformat: bool
    swiftlint: bool
    semgrep: bool
    gitleaks: bool
    periphery: bool


@dataclass(frozen=True)
class BuildGateConfig:
    """Enablement switches for SwiftPM, Xcode, and UI build gates."""

    xcode: bool
    require_xcode: bool
    tests: bool
    ui_tests: bool
    spm: bool
    spm_tests: bool
    snapshots: bool


@dataclass(frozen=True)
class CheckConfig:
    """Complete immutable configuration for one quality-gate run."""

    project: ProjectConfig
    xcode: XcodeConfig
    static: StaticGateConfig
    build: BuildGateConfig


@dataclass(frozen=True)
class Gate:
    """One named quality check and its executable callback."""

    name: str
    description: str
    run: Callable[[], int]


def _env_bool(name: str, *, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", maxsplit=1)
        normalized_value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key.strip(), normalized_value)


def _generated_allowlist() -> tuple[str, ...]:
    entries: list[str] = []
    for item in os.getenv("IOS_CHECK_GENERATED_ALLOWLIST", "").split(":"):
        normalized = item.strip()
        if normalized:
            entries.append(normalized)
    return tuple(entries)


def config_from_env(root: Path) -> CheckConfig:
    """Load one strict gate configuration from the repository environment.

    Returns:
        The immutable native quality configuration.
    """
    _load_env_file(root / "scripts" / "ios_check.env")
    spm_path = os.getenv("IOS_CHECK_SPM_PATH", ".").strip() or "."
    workspace = os.getenv("IOS_CHECK_WORKSPACE", "")
    project = os.getenv("IOS_CHECK_PROJECT", "")
    scheme = os.getenv("IOS_CHECK_SCHEME", "")
    has_xcode_target = bool(scheme and (workspace or project))
    enable_spm = _env_bool(
        "IOS_CHECK_ENABLE_SPM",
        default=(root / spm_path / "Package.swift").exists(),
    )
    return CheckConfig(
        project=ProjectConfig(
            root=root,
            spm_path=spm_path,
            workspace=workspace,
            project=project,
            scheme=scheme,
            generated_allowlist=_generated_allowlist(),
            semgrep_config=os.getenv("IOS_CHECK_SEMGREP_CONFIG", ".semgrep.yml"),
        ),
        xcode=XcodeConfig(
            configuration=os.getenv("IOS_CHECK_CONFIGURATION", "Debug"),
            destination=os.getenv(
                "IOS_CHECK_DESTINATION",
                "platform=iOS Simulator,name=iPhone 16,OS=latest",
            ),
            derived_data=os.getenv("IOS_CHECK_DERIVED_DATA", ".build/DerivedData/check"),
            package_authorization_provider=os.getenv(
                "IOS_CHECK_XCODE_PACKAGE_AUTHORIZATION_PROVIDER",
                "",
            ).strip(),
        ),
        static=StaticGateConfig(
            swift_format=_env_bool("IOS_CHECK_ENABLE_SWIFT_FORMAT", default=True),
            swiftformat=_env_bool("IOS_CHECK_ENABLE_SWIFTFORMAT", default=False),
            swiftlint=_env_bool("IOS_CHECK_ENABLE_SWIFTLINT", default=True),
            semgrep=_env_bool("IOS_CHECK_ENABLE_SEMGREP", default=True),
            gitleaks=_env_bool("IOS_CHECK_ENABLE_GITLEAKS", default=True),
            periphery=_env_bool("IOS_CHECK_ENABLE_PERIPHERY", default=False),
        ),
        build=BuildGateConfig(
            xcode=_env_bool("IOS_CHECK_ENABLE_XCODE", default=has_xcode_target),
            require_xcode=_env_bool("IOS_CHECK_REQUIRE_XCODE", default=has_xcode_target),
            tests=_env_bool("IOS_CHECK_ENABLE_TESTS", default=has_xcode_target),
            ui_tests=_env_bool("IOS_CHECK_ENABLE_UI_TESTS", default=False),
            spm=enable_spm,
            spm_tests=_env_bool("IOS_CHECK_ENABLE_SPM_TESTS", default=enable_spm),
            snapshots=_env_bool("IOS_CHECK_ENABLE_SNAPSHOTS", default=False),
        ),
    )
