#!/usr/bin/env bash
set -euo pipefail

if command -v swift-format >/dev/null 2>&1; then
  swift-format format --recursive --in-place .
fi

if [[ "${IOS_CHECK_ENABLE_SWIFTFORMAT:-0}" == "1" ]]; then
  if ! command -v swiftformat >/dev/null 2>&1; then
    echo "swiftformat requested but missing" >&2
    exit 1
  fi
  swiftformat .
fi
