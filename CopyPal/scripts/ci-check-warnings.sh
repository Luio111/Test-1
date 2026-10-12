#!/usr/bin/env bash
# Fails when a build log contains compiler warnings in CopyPal's own Swift sources.
# Warnings from Xcode tools or dependencies are ignored. Used by CI (Docs/ADR/0002).
# Usage: ci-check-warnings.sh <log> [<log> ...]
set -euo pipefail

pattern='/CopyPal/(App|Packages/CopyPalKit/(Sources|Tests))/[^:]+\.swift:[0-9]+:[0-9]+: warning:'
warnings="$(cat "$@" | grep -E "$pattern" | sort -u || true)"

if [ -n "$warnings" ]; then
    echo "Compiler-Warnungen im eigenen Code:"
    echo "$warnings"
    echo "::error::Compiler-Warnungen im eigenen Code – bitte beheben (Docs/ADR/0002)."
    exit 1
fi
echo "Keine Compiler-Warnungen im eigenen Code."
