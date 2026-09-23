"""Expose the existing Make aggregate through the repository's uv command."""

from __future__ import annotations

import argparse
import subprocess
import sys


PYTHON_CHECK: tuple[str, ...] = ()


def main() -> int:
    """Run Apple checks and preserve any existing Python aggregate and failures."""
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--list", action="store_true", help="List configured Apple gates")
    mode.add_argument("--probe", action="store_true", help="Verify deliberate failing fixtures")
    arguments = parser.parse_args()
    target = "check"
    if arguments.list:
        target = "check-list"
    elif arguments.probe:
        target = "check-probe"
    native_status = subprocess.run(["make", target], check=False).returncode
    python_status = 0
    if PYTHON_CHECK and target == "check":
        python_status = subprocess.run(
            [sys.executable, *PYTHON_CHECK], check=False,
        ).returncode
    return native_status or python_status


if __name__ == "__main__":
    raise SystemExit(main())
