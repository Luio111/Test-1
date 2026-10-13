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
oneliner="$(grep -m 1 '^d=; for c in ~/Developer/Test-1 ' "$scripts/../README.md")"
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
grep -q "git -C " "$root/out.txt" || fail "Stash-Hinweis nennt den Ordner nicht (git -C …)"
pass "Änderung liegt im Stash, neue Commits werden angezeigt, Hinweis klappt aus jedem Ordner"

run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "zweiter Lauf"; }
grep -q "Schon aktuell" "$root/out.txt" || fail "zweiter Lauf meldet nicht „Schon aktuell“"
pass "zweiter Lauf: schon aktuell"

publish "CopyPal 3b"
echo "staged" >> "$repo/CopyPal/version.txt"
git -C "$repo" add CopyPal/version.txt
git -C "$repo" show HEAD:CopyPal/version.txt > "$repo/CopyPal/version.txt"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "nur vorgemerkte Änderung"; }
expect_on "nur im Index vorgemerkte Änderung"

echo "lokal erzeugt" > "$repo/CopyPal/Package.resolved"
git -C "$seed" switch -q "$branch"
echo "von GitHub" > "$seed/CopyPal/Package.resolved"
git -C "$seed" add -A
git -C "$seed" commit -qm "Package.resolved eingecheckt"
git -C "$seed" push -q origin "$branch"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "Datei im Weg"; }
expect_on "unversionierte Datei im Weg der neuen Version"
[ "$(cat "$repo/CopyPal/Package.resolved")" = "von GitHub" ] || fail "Datei im Weg: Stand von GitHub fehlt"
grep -q "lokal erzeugt" "$(git -C "$repo" rev-parse --absolute-git-dir)"/copypal-backups/*-im-weg/CopyPal/Package.resolved \
    || fail "Datei im Weg nicht gesichert"
pass "Datei im Weg liegt in .git/copypal-backups"

publish "CopyPal 4"
git -C "$repo" switch -q main
[ ! -e "$repo/CopyPal" ] || fail "Testaufbau: main hat CopyPal"
run_command > /dev/null 2>&1 || fail "von main aus"
expect_on "auf main (Ordner CopyPal fehlt)"

publish "CopyPal 5"
git -C "$repo" checkout -q HEAD~1
run_command > /dev/null 2>&1 || fail "losgelöster HEAD"
expect_on "losgelöster HEAD auf älterem Commit"

publish "CopyPal 5b"
git -C "$repo" checkout -q --detach HEAD
echo "losgelöst" >> "$repo/CopyPal/version.txt"
git -C "$repo" commit -qam "Commit auf losgelöstem HEAD"
own="$(git -C "$repo" rev-parse HEAD)"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "losgelöster HEAD mit Commit"; }
expect_on "losgelöster HEAD mit eigenem Commit"
git -C "$repo" for-each-ref --format='%(objectname)' 'refs/heads/copypal-sicherung-*' | grep -q "$own" \
    || fail "Commit vom losgelösten HEAD nicht gesichert"
pass "Commit vom losgelösten HEAD liegt im Sicherungs-Branch"

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

git -C "$seed" switch -q "$branch"
git -C "$seed" commit -q --amend -m "CopyPal 6 (auf GitHub umgeschrieben)"
git -C "$seed" push -q -f origin "$branch"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "umgeschriebener Branch"; }
expect_on "GitHub hat den Branch umgeschrieben (force-push)"
grep -q "Eigene Commits" "$root/out.txt" && fail "GitHubs alte Commits werden als eigene gemeldet"
pass "umgeschriebener Branch: keine falsche Sicherungsmeldung"

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

if (cd / && COPYPAL_BRANCH=feature/tset "$user_shell" -c '. "$HOME/'"$(basename "$rc")"'"; copypal-update --no-open') > "$root/out.txt" 2>&1; then
    fail "Tippfehler in COPYPAL_BRANCH wird nicht gemeldet"
fi
grep -q "gibt es auf GitHub nicht" "$root/out.txt" || { cat "$root/out.txt"; fail "Tippfehler in COPYPAL_BRANCH: unklare Meldung"; }
[ "$(git -C "$repo" symbolic-ref -q --short HEAD)" = feature/test ] || fail "Tippfehler in COPYPAL_BRANCH wechselt den Branch"
pass "Tippfehler in COPYPAL_BRANCH: Abbruch mit Meldung, nichts verändert"

git -C "$seed" switch -q main
git -C "$seed" merge -q --squash "$branch" > /dev/null
git -C "$seed" commit -qm "Squash CopyPal"
git -C "$seed" push -q origin main
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "nach dem Squash-Merge"; }
expect_on "Branch per Squash gemergt, auf GitHub noch vorhanden: weiter mit main" main

publish "CopyPal 10"
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "Branch nach dem Merge weiterentwickelt"; }
expect_on "Branch nach dem Merge weiterentwickelt: zurück auf den Branch"

git -C "$seed" switch -q main
# The squash commit and the branch both add version.txt: the branch's content wins.
git -C "$seed" merge -q --no-ff -X theirs -m "Merge CopyPal" "$branch" > /dev/null
git -C "$seed" push -q origin main
run_command > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "nach dem Merge (Branch noch da)"; }
expect_on "Branch gemergt, auf GitHub noch vorhanden: weiter mit main" main

git -C "$seed" push -q origin --delete "$branch"
run_command > /dev/null 2>&1 || fail "nach dem Merge"
expect_on "Branch gemergt und gelöscht: weiter mit main" main

rm -rf "$repo"
git clone -q "$origin" "$repo"
echo "export SOMETHING=1" > "$rc"
(cd "$HOME" && "$user_shell" -c "$oneliner") > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "Einrichtung nach dem Merge"; }
expect_on "Einrichtungszeile aus der README nach Merge und Löschen des Branches" main
grep -q "copypal-update()" "$rc" || fail "Einrichtung nach dem Merge: Befehl fehlt"
pass "Einrichtungszeile fällt auf main zurück"

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

# A block whose end marker the user deleted by hand must not swallow what follows it.
printf '%s\n' 'export A=1' '# >>> copypal-update >>>' 'copypal-update() { echo alt; }' 'export B=2' 'alias ll="ls -l"' > "$HOME/dotfiles/rc"
COPYPAL_REPO="$repo" bash "$repo/CopyPal/scripts/update.sh" --install --no-open > /dev/null 2>&1 || fail "Einrichtung ohne Endmarke"
grep -q '^export B=2$' "$rc" && grep -q '^alias ll=' "$rc" || fail "Zeilen nach einer Endmarken-losen Einrichtung verloren"
[ "$(grep -c '^# <<< copypal-update <<<$' "$rc")" = 1 ] || fail "neue Einrichtung fehlt"
(cd / && "$user_shell" -c '. "$HOME/'"$(basename "$rc")"'"; copypal-update --no-open') > /dev/null 2>&1 || fail "Befehl nach Einrichtung ohne Endmarke"
pass "fehlende Endmarke: nichts geht verloren, der neue Befehl gilt"

if [ "$(basename "$user_shell")" = bash ]; then
    rm -f "$HOME/.bash_profile" "$HOME/.bash_login"
    echo 'export FROM_PROFILE=yes' > "$HOME/.profile"
    COPYPAL_REPO="$repo" bash "$repo/CopyPal/scripts/update.sh" --install --no-open > /dev/null 2>&1 || fail "Einrichtung für bash"
    [ "$(bash -l -c 'echo "$FROM_PROFILE"')" = yes ] || fail "neue .bash_profile überdeckt .profile"
    bash -l -c 'type copypal-update' > /dev/null 2>&1 || fail "copypal-update fehlt in der Login-Shell"
    pass "bash: neue .bash_profile liest .profile weiter"
fi

mv "$repo" "$root/moved"
if run_command > "$root/out.txt" 2>&1; then fail "fehlender Ordner meldet keinen Fehler"; fi
grep -q "kein Git-Ordner" "$root/out.txt" || fail "fehlender Ordner: unklare Meldung"
pass "fehlender Ordner: verständliche Meldung"
mv "$root/moved" "$repo"
(cd / && COPYPAL_REPO="$repo" "$user_shell" -c '. "$HOME/'"$(basename "$rc")"'"; copypal-update --no-open') > "$root/out.txt" 2>&1 \
    || { cat "$root/out.txt"; fail "COPYPAL_REPO im eingerichteten Befehl"; }
pass "eingerichteter Befehl beachtet COPYPAL_REPO"

# The clone lives somewhere unexpected and the user pastes the README line inside it.
mkdir -p "$HOME/Projects"
mv "$repo" "$HOME/Projects/Test-1"
repo="$HOME/Projects/Test-1"
echo "export SOMETHING=1" > "$rc"
(cd "$repo/CopyPal" && "$user_shell" -c "$oneliner") > "$root/out.txt" 2>&1 || { cat "$root/out.txt"; fail "Einrichtung aus dem Klon heraus"; }
expect_on "Einrichtungszeile im Klon an ungewöhnlichem Ort" main
grep -q "Projects/Test-1" "$rc" || fail "Einrichtung merkt sich den ungewöhnlichen Ort nicht"
(cd / && "$user_shell" -c '. "$HOME/'"$(basename "$rc")"'"; copypal-update --no-open') > /dev/null 2>&1 || fail "Befehl nach Einrichtung im Klon"
pass "eingerichteter Befehl kennt den ungewöhnlichen Ort"

echo "Alle Prüfungen von copypal-update bestanden."
