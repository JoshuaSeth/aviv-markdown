#!/usr/bin/env python3
# Copyright (c) 2026 PitchAI. All rights reserved.
"""Launch Aviv's native quality gate from the repository root."""

from __future__ import annotations

import os
import runpy
import sys
from pathlib import Path


def main() -> None:
    """Run the repository-root quality CLI with deterministic imports."""
    repository_root = Path(__file__).resolve().parents[1]
    os.chdir(repository_root)
    sys.path.insert(0, str(repository_root))
    runpy.run_module("ios_quality.cli", run_name="__main__")


if __name__ == "__main__":
    main()
