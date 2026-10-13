#!/usr/bin/env bash
# Prepares the Xcode project on your Mac:
#   1. checks that XcodeGen and Xcode are set up
#   2. creates Config/Signing.local.xcconfig and fills in your team ID when it is unambiguous
#   3. generates CopyPal.xcodeproj
# Usage: ./scripts/bootstrap.sh [--open]
# Compatible with the bash 3.2 that ships with macOS.
set -euo pipefail

cd "$(dirname "$0")/.."

signing="Config/Signing.local.xcconfig"

setting() {
    sed -n "s/^$1 *= *\\([^ ]*\\).*$/\\1/p" "$signing" | tail -n 1
}

# Team IDs known to Xcode (Settings → Accounts) and from existing
# "Apple Development" certificates, one per line, deduplicated.
team_candidates() {
    local tmp
    tmp="$(mktemp -d)"
    {
        for key in IDEProvisioningTeamByIdentifier IDEProvisioningTeams; do
            defaults read com.apple.dt.Xcode "$key" 2>/dev/null || true
        done | sed -n 's/.*teamID = "*\([A-Z0-9]\{10\}\)"*;.*/\1/p'

        security find-certificate -a -c "Apple Development" -p 2>/dev/null \
            | awk -v dir="$tmp" '/BEGIN CERTIFICATE/ { n++ } n { print > (dir "/cert" n ".pem") }' || true
        for pem in "$tmp"/cert*.pem; do
            [ -f "$pem" ] || continue
            openssl x509 -noout -subject -in "$pem" 2>/dev/null || true
        done | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p'
    } | sort -u
    rm -rf "$tmp"
}

print_team_help() {
    cat <<'HELP'
So findest du deine Team-ID (kostenloses „Personal Team“ reicht):
  1. Xcode → Settings… → Accounts → „+“ → Apple ID (falls noch nicht angemeldet)
  2. Team „… (Personal Team)“ auswählen → Manage Certificates… → „+“ → Apple Development
  3. copypal-update (oder ./scripts/bootstrap.sh im Ordner CopyPal) erneut ausführen – die Team-ID wird dann erkannt.
Oder von Hand eintragen in $PWD/$signing (siehe Docs/Troubleshooting.md).
HELP
}

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen fehlt. Installiere es mit: brew install xcodegen" >&2
    exit 1
fi

case "$(xcode-select -p 2>/dev/null || true)" in
    "" | *CommandLineTools*)
        echo "Hinweis: Das aktive Developer-Verzeichnis ist nicht Xcode."
        echo "         Bitte ausführen: sudo xcode-select -s /Applications/Xcode.app"
        ;;
esac

if [ ! -f "$signing" ]; then
    cp Config/Signing.local.xcconfig.example "$signing"
    echo "Angelegt: $signing"
fi

if [ -z "$(setting DEVELOPMENT_TEAM)" ]; then
    candidates="$(team_candidates)"
    count="$(printf '%s' "$candidates" | grep -c . || true)"
    if [ "$count" -eq 1 ]; then
        sed "s/^DEVELOPMENT_TEAM *=.*/DEVELOPMENT_TEAM = $candidates/" "$signing" > "$signing.tmp"
        mv "$signing.tmp" "$signing"
        echo "Team-ID erkannt und eingetragen: $candidates"
    elif [ "$count" -gt 1 ]; then
        echo "Mehrere Team-IDs gefunden – bitte die richtige in $signing eintragen:"
        printf '%s\n' "$candidates" | while read -r id; do echo "  $id"; done
    else
        echo "Keine Team-ID gefunden."
        print_team_help
    fi
fi

echo "Team-ID:           $(setting DEVELOPMENT_TEAM)"
echo "Bundle-ID (Debug): $(setting BUNDLE_ID_PREFIX).CopyPal.dev"

xcodegen generate

if [ "${1:-}" = "--open" ]; then
    open CopyPal.xcodeproj
fi
