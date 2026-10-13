#!/usr/bin/env bash
# Syncs App/Resources/Localizable.xcstrings with the strings the compiler extracted
# (*.stringsdata), as Xcode does after every build, and fails when that changes the
# file. The synced file is left as Localizable.synced.xcstrings for CI to upload.
# Usage: ci-sync-string-catalog.sh <DerivedData folder>
set -euo pipefail

derived="$1"
catalog="CopyPal/App/Resources/Localizable.xcstrings"

args=()
while IFS= read -r -d '' file; do
    args+=(--stringsdata "$file")
done < <(find "$derived/Build/Intermediates.noindex/CopyPal.build" -name '*.stringsdata' -print0)
echo "${#args[@]} Argumente aus $(find "$derived/Build/Intermediates.noindex/CopyPal.build" -name '*.stringsdata' | wc -l | tr -d ' ') .stringsdata-Dateien"
if [ "${#args[@]}" -eq 0 ]; then
    echo "::error::Keine .stringsdata gefunden (SWIFT_EMIT_LOC_STRINGS?)"
    exit 1
fi

if ! xcrun xcstringstool sync "$catalog" "${args[@]}"; then
    echo "Aufruf von xcstringstool sync fehlgeschlagen. Hilfe:"
    xcrun xcstringstool help sync || xcrun xcstringstool sync --help || true
    exit 1
fi

if git diff --quiet -- "$catalog"; then
    echo "Localizable.xcstrings ist so, wie Xcode es schreibt."
    exit 0
fi
git diff --stat -- "$catalog"
git diff -- "$catalog" | head -n 200
cp "$catalog" Localizable.synced.xcstrings
echo "::error::Xcode würde Localizable.xcstrings umschreiben. Die abgeglichene Fassung liegt im Artefakt „string-catalog“."
exit 1
