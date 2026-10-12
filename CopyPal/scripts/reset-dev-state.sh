#!/usr/bin/env bash
# Resets the development state of the CopyPal Debug build on this Mac:
# Accessibility grant, settings, data folders and Keychain item.
# Use it to test onboarding from scratch or to fix a stuck permission.
# Quit CopyPal before running it.
# Usage: ./scripts/reset-dev-state.sh [bundle-id]
set -euo pipefail

cd "$(dirname "$0")/.."

prefix_from() {
    [ -f "$1" ] || return 0
    sed -n 's/^BUNDLE_ID_PREFIX *= *\([^ ]*\).*$/\1/p' "$1" | tail -n 1
}

prefix="$(prefix_from Config/Signing.local.xcconfig)"
if [ -z "$prefix" ]; then
    prefix="$(prefix_from Config/Base.xcconfig)"
fi
bundle_id="${1:-$prefix.CopyPal.dev}"

echo "Setzt den Entwicklungsstand zurück für: $bundle_id"
echo "Bitte CopyPal vorher beenden."
read -r -p "Fortfahren? [j/N] " answer || answer=""
case "$answer" in
    j | J | y | Y) ;;
    *) echo "Abgebrochen."; exit 0 ;;
esac

tccutil reset Accessibility "$bundle_id" || true
tccutil reset ListenEvent "$bundle_id" >/dev/null 2>&1 || true
defaults delete "$bundle_id" >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Application Support/$bundle_id" "$HOME/Library/Caches/$bundle_id"
security delete-generic-password -s "$bundle_id.storage" >/dev/null 2>&1 || true

echo "Fertig. Starte CopyPal neu und erteile die Freigaben erneut."
