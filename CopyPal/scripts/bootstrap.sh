#!/usr/bin/env bash
# Prepares the Xcode project on your Mac:
#   1. checks that XcodeGen is installed
#   2. creates Config/Signing.local.xcconfig (team ID is detected when possible)
#   3. generates CopyPal.xcodeproj
# Usage: ./scripts/bootstrap.sh [--open]
# Compatible with the bash 3.2 that ships with macOS.
set -euo pipefail

cd "$(dirname "$0")/.."

signing="Config/Signing.local.xcconfig"

detect_team() {
    security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' \
        | head -n 1
}

setting() {
    sed -n "s/^$1 *= *\\([^ ]*\\).*$/\\1/p" "$signing" | tail -n 1
}

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen fehlt. Installiere es mit: brew install xcodegen" >&2
    exit 1
fi

if [ ! -f "$signing" ]; then
    cp Config/Signing.local.xcconfig.example "$signing"
    echo "Angelegt: $signing"
fi

if [ -z "$(setting DEVELOPMENT_TEAM)" ]; then
    team="$(detect_team || true)"
    if [ -n "$team" ]; then
        sed "s/^DEVELOPMENT_TEAM *=.*/DEVELOPMENT_TEAM = $team/" "$signing" > "$signing.tmp"
        mv "$signing.tmp" "$signing"
        echo "Team-ID erkannt und eingetragen: $team"
    else
        echo "Keine Team-ID gefunden. Melde dich in Xcode → Einstellungen → Accounts mit deiner Apple-ID an"
        echo "und trage die Team-ID in $signing ein (siehe Docs/Troubleshooting.md)."
    fi
fi

echo "Team-ID:  $(setting DEVELOPMENT_TEAM)"
echo "Bundle-ID (Debug): $(setting BUNDLE_ID_PREFIX).CopyPal.dev"

xcodegen generate

if [ "${1:-}" = "--open" ]; then
    open CopyPal.xcodeproj
fi
