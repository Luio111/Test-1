#!/usr/bin/env bash
# shellcheck disable=SC1111 # German quotation marks in messages are intended.
# Builds a signed, notarized CopyPal release on your Mac (ROADMAP M9). Certificates
# and keys never leave the Mac, so this does not run in CI.
#
#   ./scripts/release.sh 0.9.0            # stable
#   ./scripts/release.sh 0.9.1 --beta     # beta channel
#
# One-time setup (Docs/Release.md):
#   - Apple Developer Program, certificate "Developer ID Application" in the keychain
#   - xcrun notarytool store-credentials CopyPal   (App Store Connect API key or app-specific password)
#   - Sparkle EdDSA key: ./scripts/release.sh --setup-sparkle, then back it up twice
#   - COPYPAL_FEED_URL and COPYPAL_SPARKLE_PUBLIC_KEY in Config/Release.xcconfig
#
# Output in build/release/<version>/: CopyPal-<version>.dmg and appcast.xml.
# Compatible with the bash 3.2 that ships with macOS.
set -euo pipefail

cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.6"
NOTARY_PROFILE="${NOTARY_PROFILE:-CopyPal}"
tools="build/sparkle-$SPARKLE_VERSION"

fail() {
    echo "✘ $*" >&2
    exit 1
}

sparkle_tools() {
    if [ ! -x "$tools/bin/generate_appcast" ]; then
        echo "Lade Sparkle $SPARKLE_VERSION (Werkzeuge für Schlüssel und Appcast) …"
        mkdir -p "$tools"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
            | tar -xJ -C "$tools"
    fi
}

if [ "${1:-}" = "--setup-sparkle" ]; then
    sparkle_tools
    "$tools/bin/generate_keys"
    echo
    echo "Den öffentlichen Schlüssel oben in Config/Release.xcconfig als COPYPAL_SPARKLE_PUBLIC_KEY eintragen."
    echo "Den privaten Schlüssel an ZWEI Orten sichern (Docs/Release.md):"
    echo "  $tools/bin/generate_keys -x sparkle-private-key.txt"
    exit 0
fi

version="${1:-}"
channel=""
[ "${2:-}" = "--beta" ] && channel="beta"
case "$version" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) fail "Aufruf: ./scripts/release.sh <version, z. B. 0.9.0> [--beta]" ;;
esac

# --- Checks --------------------------------------------------------------------
command -v xcodegen >/dev/null || fail "XcodeGen fehlt: brew install xcodegen"
[ -f Config/Signing.local.xcconfig ] || fail "Config/Signing.local.xcconfig fehlt: ./scripts/bootstrap.sh"
team="$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*$/\1/p' Config/Signing.local.xcconfig | tail -n 1)"
[ -n "$team" ] || fail "DEVELOPMENT_TEAM in Config/Signing.local.xcconfig fehlt"
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || fail "Zertifikat „Developer ID Application“ fehlt im Schlüsselbund (Docs/Release.md)"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "notarytool-Profil „$NOTARY_PROFILE“ fehlt: xcrun notarytool store-credentials $NOTARY_PROFILE"
grep -q '^COPYPAL_SPARKLE_PUBLIC_KEY *= *[A-Za-z0-9+/=]\{20,\}' Config/Release.xcconfig \
    || fail "COPYPAL_SPARKLE_PUBLIC_KEY in Config/Release.xcconfig fehlt (./scripts/release.sh --setup-sparkle)"
[ -z "$(git status --porcelain)" ] || fail "Arbeitskopie nicht sauber – erst committen"

out="build/release/$version"
rm -rf "$out"
mkdir -p "$out"
build_number="$(git rev-list --count HEAD)"

# --- Build ---------------------------------------------------------------------
echo "▸ Projekt erzeugen"
xcodegen generate >/dev/null

echo "▸ Archiv bauen ($version, Build $build_number)"
xcodebuild archive \
    -project CopyPal.xcodeproj -scheme CopyPal -configuration Release \
    -archivePath "$out/CopyPal.xcarchive" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" | tail -n 3

echo "▸ Mit Developer ID exportieren"
sed "s/TEAM_ID/$team/" Config/ExportOptions.plist > "$out/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$out/CopyPal.xcarchive" \
    -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out/export" | tail -n 2
app="$out/export/CopyPal.app"
[ -d "$app" ] || fail "Export fehlgeschlagen"

echo "▸ App notarisieren und stapeln"
ditto -c -k --keepParent "$app" "$out/CopyPal.zip"
xcrun notarytool submit "$out/CopyPal.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"

echo "▸ DMG erstellen, signieren, notarisieren"
staging="$out/dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Programme"
dmg="$out/CopyPal-$version.dmg"
hdiutil create -volname "CopyPal $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"

echo "▸ Prüfen"
spctl -a -vvv -t install "$dmg"
xcrun stapler validate "$dmg"

echo "▸ Appcast erzeugen"
sparkle_tools
updates="build/release/updates"
mkdir -p "$updates"
cp "$dmg" "$updates/"
channel_args=()
[ -n "$channel" ] && channel_args=(--channel "$channel")
"$tools/bin/generate_appcast" ${channel_args[@]+"${channel_args[@]}"} "$updates"
cp "$updates/appcast.xml" "$out/appcast.xml"

cat <<DONE

✔ Fertig: $dmg

Nächste Schritte (Docs/Release.md):
  1. GitHub-Release „v$version“ anlegen und $(basename "$dmg") hochladen
  2. $out/appcast.xml auf GitHub Pages veröffentlichen (Feed-URL aus Release.xcconfig)
  3. Update von der Vorversion aus testen: CopyPal → Nach Updates suchen …
DONE
