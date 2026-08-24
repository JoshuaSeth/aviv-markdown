# Copyright (c) 2026 PitchAI. All rights reserved.
"""Run Aviv's fail-closed Swift, security, build, and test quality gates."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import cast

from .model import config_from_env
from .probe import run_probe
from .registry import run_gates, write_gate_list


def main(argv: list[str] | None = None) -> int:
    """Run the requested quality gates.

    Returns:
        Zero when every requested gate passes; otherwise a nonzero status.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list gates and exit")
    parser.add_argument("--only", help="run one named gate")
    parser.add_argument("--skip", action="append", default=[], help="skip one named gate")
    parser.add_argument("--ci", action="store_true", help="CI mode marker; gates remain fail-closed")
    parser.add_argument("--probe", action="store_true", help="run activation probes")
    arguments = parser.parse_args(argv)

    list_requested = cast("bool", arguments.list)
    probe_requested = cast("bool", arguments.probe)
    only = cast("str | None", arguments.only)
    skip = set(cast("list[str]", arguments.skip))

    if list_requested:
        write_gate_list(config_from_env(Path.cwd()))
        return 0
    if probe_requested:
        return run_probe()

    return run_gates(config_from_env(Path.cwd()), only=only, skip=skip)


if __name__ == "__main__":
    raise SystemExit(main())
