#!/usr/bin/env bash
# Checks scripts/update.sh (copypal-update) against a stand-in for GitHub: a bare
# repository with main and the CopyPal branch, a clone like the one on the Mac, and a
# bootstrap.sh that only records where it ran. Covers the states a manual "git pull"
# gets stuck in. Runs in CI on macOS (/bin/bash 3.2, zsh) and locally:
#   scripts/test-update.sh
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
branch="claude/amazing-volta-1uce5i"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

# A home folder with a space and a quote, so every path is quoted correctly.
export HOME="$root/home o'test"
mkdir -p "$HOME/Developer" "$root/bin"
git config --global user.name "CopyPal Test"
git config --global user.email "test@example.invalid"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# The user's shell: zsh as on the Mac; bash if zsh is missing (Linux) or with
# COPYPAL_TEST_SHELL=bash.
if [ "${COPYPAL_TEST_SHELL:-zsh}" = zsh ] && command -v zsh > /dev/null 2>&1; then
    user_shell="$(command -v zsh)"
    rc="$HOME/.zshrc"
else
    user_shell="$(command -v bash)"
    rc="$HOME/.bash_profile"
fi
export SHELL="$user_shell"
# On macOS the script must work with the bash 3.2 there, even if Homebrew's bash is first.
if [ -x /bin/bash ] && [ "$(uname)" = Darwin ]; then
    ln -s /bin/bash "$root/bin/bash"
    export PATH="$root/bin:$PATH"
fi
echo "Shell: $user_shell, bash: $(bash -c 'echo $BASH_VERSION'), git: $(git --version)"

fail() {
    echo "FEHLER: $*" >&2
    exit 1
}

pass() {
    echo "ok – $*"
}

# --- GitHub stand-in -------------------------------------------------------------

seed="$root/seed"
origin="$root/origin.git"
git init -q "$seed"
cd "$seed"
echo "Test-1" > README.md
git add README.md
git commit -qm "main: start"
git switch -q -c "$branch"
mkdir -p CopyPal/scripts CopyPal/App/Resources
cp "$scripts/update.sh" CopyPal/scripts/update.sh
cat > CopyPal/scripts/bootstrap.sh <<'EOF'
#!/usr/bin/env bash
# Stand-in for bootstrap.sh: records the commit and the arguments it ran with.
cd "$(dirname "$0")/.."
echo "$(git rev-parse HEAD) ${1:-}" >> "$HOME/bootstrap.log"
EOF
chmod +x CopyPal/scripts/update.sh CopyPal/scripts/bootstrap.sh
echo '{ "strings" : { } }' > CopyPal/App/Resources/Localizable.xcstrings
echo "1" > CopyPal/version.txt
git add -A
git commit -qm "CopyPal 1"
git clone -q --bare "$seed" "$origin"
git -C "$origin" symbolic-ref HEAD refs/heads/main
git remote add origin "$origin"

# A new commit on GitHub's CopyPal branch (or another branch).
publish() {
    local message="$1" on="${2:-$branch}"
    git -C "$seed" switch -q "$on"
    echo "$message" >> "$seed/CopyPal/version.txt"
    git -C "$seed" commit -qam "$message"
    git -C "$seed" push -q origin "$on"
}

repo="$HOME/Developer/Test-1"
git clone -q "$origin" "$repo"
git -C "$repo" switch -q "$branch"

# Runs the installed command like a new Terminal window, from another folder.
run_command() {
    (cd / && "$user_shell" -c '. "$HOME/'"$(basename "$rc")"'"; copypal-update --no-open "$@"' copypal-update "$@")
}

expect_on() {
    local name="$1" want="${2:-$branch}"
    [ "$(git -C "$repo" symbolic-ref -q --short HEAD)" = "$want" ] || fail "$name: nicht auf $want"
    [ "$(git -C "$repo" rev-parse HEAD)" = "$(git -C "$origin" rev-parse "refs/heads/$want")" ] \
        || fail "$name: nicht auf dem Stand von GitHub"
    [ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ] || fail "$name: Ordner nicht sauber"
    [ "$(tail -n 1 "$HOME/bootstrap.log" | cut -d ' ' -f 1)" = "$(git -C "$repo" rev-parse HEAD)" ] \
        || fail "$name: bootstrap.sh lief nicht auf dem neuen Stand"
    pass "$name"
}

# --- First run: the line from the README, pasted into the Terminal in the home folder

publish "CopyPal 2"
echo "export SOMETHING=1" > "$rc"
oneliner="$(grep -m 1 '^d=~/Developer/Test-1;' "$scripts/../README.md")"
[ -n "$oneliner" ] || fail "Einrichtungszeile fehlt in README.md"
(cd "$HOME" && "$user_shell" -c "$oneliner") > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "Einrichtung"; }
expect_on "Einrichtung mit der Zeile aus der README"
[ "$(tail -n 1 "$HOME/bootstrap.log" | cut -d ' ' -f 2)" = "--open" ] || fail "Einrichtung: Xcode nicht geöffnet"
grep -q '^export SOMETHING=1$' "$rc" || fail "Einrichtung: bestehende $rc verändert"
grep -q "copypal-update" "$root/out.txt" || fail "Einrichtung: kein Hinweis auf den Befehl"
pass "bestehende $(basename "$rc") bleibt erhalten"

# --- Everyday use ------------------------------------------------------------------

publish "CopyPal 3"
echo '{"strings":{"x":{}}}' > "$repo/CopyPal/App/Resources/Localizable.xcstrings"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "Xcode-Änderung"; }
expect_on "Xcode hat Localizable.xcstrings verändert"
[ "$(git -C "$repo" stash list | wc -l | tr -d ' ')" = 1 ] || fail "Änderung nicht im Stash"
[ -z "$(tail -n 1 "$HOME/bootstrap.log" | cut -d ' ' -f 2)" ] || fail "--no-open nicht beachtet"
grep -q "CopyPal 3" "$root/out.txt" || fail "neue Commits nicht angezeigt"
pass "Änderung liegt im Stash, neue Commits werden angezeigt"

run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "zweiter Lauf"; }
grep -q "Schon aktuell" "$root/out.txt" || fail "zweiter Lauf meldet nicht „Schon aktuell“"
pass "zweiter Lauf: schon aktuell"

publish "CopyPal 4"
git -C "$repo" switch -q main
[ ! -e "$repo/CopyPal" ] || fail "Testaufbau: main hat CopyPal"
run_command > /dev/null 2>&1 || fail "von main aus"
expect_on "auf main (Ordner CopyPal fehlt)"

publish "CopyPal 5"
git -C "$repo" checkout -q HEAD~1
run_command > /dev/null 2>&1 || fail "losgelöster HEAD"
expect_on "losgelöster HEAD auf älterem Commit"

# --- Interrupted git operations ------------------------------------------------------

publish "CopyPal 6"
echo "lokal" >> "$repo/CopyPal/version.txt"
git -C "$repo" commit -qam "eigener Commit"
own="$(git -C "$repo" rev-parse HEAD)"
run_command > /dev/null 2>&1 || fail "eigener Commit"
expect_on "eigener Commit, GitHub ist weiter"
git -C "$repo" for-each-ref --format='%(objectname)' 'refs/heads/copypal-sicherung-*' | grep -q "$own" \
    || fail "eigener Commit nicht gesichert"
pass "eigener Commit liegt im Sicherungs-Branch"

publish "CopyPal 7"
echo "lokal 2" >> "$repo/CopyPal/version.txt"
git -C "$repo" commit -qam "eigener Commit 2"
git -C "$repo" -c pull.rebase=false pull -q origin "$branch" > /dev/null 2>&1 && fail "Testaufbau: kein Konflikt"
git -C "$repo" rev-parse -q --verify MERGE_HEAD > /dev/null || fail "Testaufbau: kein MERGE_HEAD"
run_command > /dev/null 2>&1 || fail "abgebrochenes git pull (merge)"
expect_on "git pull mit Konflikt (merge) war offen"

publish "CopyPal 8"
echo "lokal 3" >> "$repo/CopyPal/version.txt"
git -C "$repo" commit -qam "eigener Commit 3"
git -C "$repo" pull -q --rebase origin "$branch" > /dev/null 2>&1 && fail "Testaufbau: kein Konflikt"
[ -d "$(git -C "$repo" rev-parse --absolute-git-dir)/rebase-merge" ] || [ -d "$(git -C "$repo" rev-parse --absolute-git-dir)/rebase-apply" ] \
    || fail "Testaufbau: kein Rebase offen"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "abgebrochenes git pull --rebase"; }
expect_on "git pull --rebase mit Konflikt war offen"

publish "CopyPal 9"
echo "gestasht" >> "$repo/CopyPal/version.txt"
git -C "$repo" stash push -q
echo "anders" >> "$repo/CopyPal/version.txt"
git -C "$repo" commit -qam "eigener Commit 4"
git -C "$repo" stash pop -q > /dev/null 2>&1 && fail "Testaufbau: kein Konflikt beim stash pop"
[ -n "$(git -C "$repo" ls-files --unmerged)" ] || fail "Testaufbau: keine Konfliktdateien"
run_command > /dev/null 2>&1 || fail "git stash pop mit Konflikt"
expect_on "git stash pop mit Konflikt war offen"
ls "$(git -C "$repo" rev-parse --absolute-git-dir)"/copypal-backups/*.patch > /dev/null 2>&1 \
    || fail "Zwischenstand nicht als Patch gesichert"
pass "Zwischenstände liegen als Patch in .git/copypal-backups"

# --- Running the script file itself, while the update rewrites it ---------------------

git -C "$seed" switch -q "$branch"
printf '\n# changed on GitHub\n' >> "$seed/CopyPal/scripts/update.sh"
git -C "$seed" commit -qam "update.sh geändert"
git -C "$seed" push -q origin "$branch"
git -C "$repo" reset -q --hard HEAD~1
(cd / && "$repo/CopyPal/scripts/update.sh" --no-open) > /dev/null 2>&1 || fail "Skript direkt aufgerufen"
expect_on "Skript direkt aufgerufen, ändert sich beim Update selbst"

# --- Clones that lack the branch, other branches, the merge ---------------------------

rm -rf "$repo"
git clone -q --single-branch --branch main "$origin" "$repo"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "Klon nur mit main"; }
expect_on "Klon kennt nur main"

git -C "$seed" switch -q -c feature/test "$branch"
publish "Feature" feature/test
(cd / && COPYPAL_BRANCH=feature/test "$user_shell" -c '. "$HOME/'"$(basename "$rc")"'"; copypal-update --no-open') > /dev/null 2>&1 \
    || fail "COPYPAL_BRANCH"
expect_on "COPYPAL_BRANCH=feature/test" feature/test

git -C "$seed" switch -q main
git -C "$seed" merge -q --no-ff -m "Merge CopyPal" "$branch"
git -C "$seed" push -q origin main
git -C "$seed" push -q origin --delete "$branch"
run_command > /dev/null 2>&1 || fail "nach dem Merge"
expect_on "Branch gemergt und gelöscht: weiter mit main" main

# --- Installing again, a symlinked startup file ------------------------------------------

mkdir -p "$HOME/dotfiles"
mv "$rc" "$HOME/dotfiles/rc"
ln -s "$HOME/dotfiles/rc" "$rc"
for _ in 1 2; do
    COPYPAL_REPO="$repo" bash "$repo/CopyPal/scripts/update.sh" --install --no-open > /dev/null 2>&1 || fail "erneut einrichten"
done
[ -L "$rc" ] || fail "Symlink $(basename "$rc") ersetzt"
[ "$(grep -c '^# >>> copypal-update >>>$' "$rc")" = 1 ] || fail "Befehl mehrfach eingetragen"
grep -q '^export SOMETHING=1$' "$rc" || fail "bestehende Zeilen verloren"
pass "erneutes Einrichten: einmal eingetragen, Symlink bleibt"

mv "$repo" "$root/moved"
if run_command > "$root/out.txt" 2>&1; then fail "fehlender Ordner meldet keinen Fehler"; fi
grep -q "kein Git-Ordner" "$root/out.txt" || fail "fehlender Ordner: unklare Meldung"
pass "fehlender Ordner: verständliche Meldung"

echo "Alle Prüfungen von copypal-update bestanden."
