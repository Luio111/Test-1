#!/usr/bin/env bash
# Runs the app's self-test (CopyPal --self-test) on a CI Mac and prints its log.
# Exit code 2 (event tap not available on the runner) is a warning, not a failure.
# Usage: ci-self-test.sh <path to CopyPal.app>
set -euo pipefail

app="$1/Contents/MacOS/CopyPal"
log="selftest.log"
"$app" --self-test > "$log" 2>&1 &
pid=$!

# macOS only lets an app take the focus cooperatively; on the runner nobody hands it
# over, so bring the test app to the front via System Events (allowed for job steps)
# until it reports that it is active.
for _ in $(seq 1 30); do
    grep -q "CopyPal ist aktiv\|CopyPal wurde nicht aktiv\|Event-Tap nicht verfügbar" "$log" && break
    # perl's alarm keeps a pending permission prompt from blocking the step.
    perl -e 'alarm 5; exec @ARGV' osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" >/dev/null 2>&1 || true
    sleep 0.5
done

set +e
wait "$pid"
status=$?
set -e
cat "$log"
if [ "$status" -eq 2 ]; then
    echo "::warning::Selbsttest nicht möglich: Event-Tap auf diesem Runner nicht verfügbar."
    exit 0
fi
exit "$status"
