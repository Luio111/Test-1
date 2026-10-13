#!/usr/bin/env bash
# Brings your Mac to the newest CopyPal state in one step, from any folder:
#   1. finds the Test-1 clone (COPYPAL_REPO, the checkout this script is in, or the
#      usual places such as ~/Developer/Test-1)
#   2. sets local changes aside (git stash) – usually files Xcode touched – so the
#      update never stops at "Your local changes … would be overwritten"
#   3. puts the clone on the CopyPal branch exactly as it is on GitHub, or on main once
#      that branch is merged and deleted; own commits stay on a backup branch
#   4. regenerates the Xcode project (bootstrap.sh) and opens it
# Usage: update.sh [--install] [--no-open]
#   --install   also adds the command "copypal-update" to your shell (once). It runs
#               the newest version of this script from GitHub, from any folder.
#   --no-open   does not open Xcode at the end
# Compatible with the bash 3.2 that ships with macOS.
set -euo pipefail

trap 'status=$?; if [ "$status" -ne 0 ]; then echo "Abgebrochen – der Grund steht in der Meldung darüber. Lokale Änderungen und Commits bleiben erhalten." >&2; fi' EXIT

branch="${COPYPAL_BRANCH:-claude/amazing-volta-1uce5i}"
marker_start="# >>> copypal-update >>>"
marker_end="# <<< copypal-update <<<"

# The clone's top folder, or nothing.
find_repo() {
    if [ -n "${COPYPAL_REPO:-}" ]; then
        git -C "$COPYPAL_REPO" rev-parse --show-toplevel 2>/dev/null
        return
    fi
    local here="${BASH_SOURCE[0]:-}"
    if [ -f "$here" ] && git -C "$(dirname "$here")" rev-parse --show-toplevel 2>/dev/null; then
        return
    fi
    local dir
    for dir in "$HOME/Developer/Test-1" "$HOME/Test-1" "$HOME/Documents/Test-1" "$HOME/Desktop/Test-1"; do
        if [ -d "$dir/.git" ]; then
            printf '%s\n' "$dir"
            return
        fi
    done
    return 1
}

# The CopyPal branch while it exists on GitHub, afterwards the default branch.
target_branch() {
    local status=0
    git ls-remote --exit-code --heads origin "refs/heads/$branch" > /dev/null || status=$?
    case "$status" in
        0) printf '%s\n' "$branch" ;;
        2)
            local default
            default="$(git ls-remote --symref origin HEAD | awk '$1 == "ref:" && $3 == "HEAD" { sub("^refs/heads/", "", $2); print $2 }')"
            printf '%s\n' "${default:-main}"
            ;;
        *) return 1 ;;
    esac
}

# Keeps the files of an interrupted operation as a patch before it is undone.
save_patch() {
    local dir stamp patch n=1
    dir="$(git rev-parse --git-path copypal-backups)"
    mkdir -p "$dir"
    stamp="$(date '+%Y%m%d-%H%M%S')"
    patch="$dir/$stamp.patch"
    while [ -e "$patch" ]; do
        n=$((n + 1))
        patch="$dir/$stamp-$n.patch"
    done
    git diff HEAD > "$patch" || true
    echo "Zwischenstand gesichert: $(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")"
}

# Ends an unfinished "git pull", merge, rebase or "git stash pop" with conflicts,
# then stashes what is left, so the tree is clean.
set_aside_changes() {
    if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
        echo "Ein unterbrochenes git rebase/am wird beendet."
        save_patch
        if [ -f "$(git rev-parse --git-path rebase-apply/applying)" ]; then git am --abort; else git rebase --abort; fi
    fi
    if git rev-parse -q --verify MERGE_HEAD > /dev/null \
        || git rev-parse -q --verify CHERRY_PICK_HEAD > /dev/null \
        || git rev-parse -q --verify REVERT_HEAD > /dev/null \
        || [ -n "$(git ls-files --unmerged)" ]; then
        echo "Ein unterbrochenes git pull/merge wird beendet."
        save_patch
        git reset -q --hard
    fi
    if ! git diff --quiet HEAD --; then
        git stash push -q -m "copypal-update $(date '+%Y-%m-%d %H:%M')"
        echo "Lokale Änderungen (meist von Xcode) beiseitegelegt. Ansehen: git stash list – zurückholen: git stash pop"
    fi
}

# Adds "copypal-update" to the shell's startup file, replacing an earlier version.
install_command() {
    local repo="$1" rc tmp
    case "$(basename "${SHELL:-/bin/zsh}")" in
        bash) rc="$HOME/.bash_profile" ;;
        *) rc="$HOME/.zshrc" ;;
    esac
    tmp="$(mktemp)"
    if [ -f "$rc" ]; then
        awk -v s="$marker_start" -v e="$marker_end" '$0 == s { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$rc" > "$tmp"
    fi
    # Runs the script from GitHub, not from the folder: works on any branch and
    # always with the newest fixes.
    cat >> "$tmp" <<EOF
$marker_start
# Holt den neuesten Stand von CopyPal und öffnet Xcode (CopyPal/scripts/update.sh).
copypal-update() {
    local repo=$(quote "$repo") ref script
    for ref in $(quote "$branch") main; do
        if git -C "\$repo" fetch -q origin "+refs/heads/\${ref}:refs/remotes/origin/\${ref}" 2> /dev/null &&
            script="\$(git -C "\$repo" show "origin/\${ref}:CopyPal/scripts/update.sh" 2> /dev/null)"; then
            COPYPAL_REPO="\$repo" bash -c "\$script" copypal-update "\$@"
            return
        fi
    done
    echo "copypal-update: GitHub ist nicht erreichbar, oder \$repo ist kein Git-Ordner mehr." >&2
    return 1
}
$marker_end
EOF
    # Writing through keeps a symlinked startup file (dotfile managers) intact.
    cat "$tmp" > "$rc"
    rm -f "$tmp"
    echo "Eingerichtet in $rc: Ab dem nächsten Terminal-Fenster reicht der Befehl copypal-update"
}

# Single-quoted for the shell.
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

main() {
    local install=0 open_xcode=1 arg
    for arg in "$@"; do
        case "$arg" in
            --install) install=1 ;;
            --no-open) open_xcode=0 ;;
            *)
                echo "Unbekannte Option: $arg (möglich: --install, --no-open)" >&2
                exit 2
                ;;
        esac
    done

    local repo
    if ! repo="$(find_repo)"; then
        echo "Den Ordner Test-1 habe ich nicht gefunden (gesucht: ~/Developer, ~, ~/Documents, ~/Desktop)." >&2
        echo "Gib ihn an, z. B.: COPYPAL_REPO=~/Pfad/zu/Test-1 copypal-update" >&2
        exit 1
    fi
    cd "$repo"
    echo "Ordner: $repo"

    local target
    if ! target="$(target_branch)"; then
        echo "GitHub ist nicht erreichbar (Internet? Anmeldung mit: gh auth login)." >&2
        exit 1
    fi
    git fetch -q origin "+refs/heads/$target:refs/remotes/origin/$target"

    set_aside_changes

    local before
    before="$(git rev-parse -q --verify HEAD || true)"
    # Own commits on the branch (or on a detached HEAD) that GitHub does not have.
    local tip="refs/heads/$target"
    git show-ref -q --verify "$tip" || tip=""
    if [ -z "$tip" ] && ! git symbolic-ref -q HEAD > /dev/null; then tip="HEAD"; fi
    if [ -n "$tip" ] && ! git merge-base --is-ancestor "$tip" "origin/$target"; then
        local backup
        backup="copypal-sicherung-$(date '+%Y%m%d-%H%M%S')-$(git rev-parse --short "$tip")"
        git branch -f "$backup" "$tip"
        echo "Eigene Commits gesichert im Branch $backup"
    fi
    git switch -q -C "$target" --no-track "origin/$target"
    # Set by hand: "--track" refuses clones made with only main (git clone --single-branch).
    git config "branch.$target.remote" origin
    git config "branch.$target.merge" "refs/heads/$target"

    if [ "$before" = "$(git rev-parse HEAD)" ]; then
        echo "Schon aktuell: $(git log -1 --format='%h %s')"
    else
        echo "Aktualisiert auf $target:"
        if [ -n "$before" ] && git merge-base --is-ancestor "$before" HEAD; then
            git log --format='  %h %s' -n 10 "$before..HEAD"
        else
            git log --format='  %h %s' -n 1
        fi
    fi

    if [ "$install" = 1 ]; then
        install_command "$repo"
    fi

    echo
    if [ "$open_xcode" = 1 ]; then
        CopyPal/scripts/bootstrap.sh --open
        echo
        echo "Fertig. In Xcode jetzt ⌘R drücken."
    else
        CopyPal/scripts/bootstrap.sh
        echo
        echo "Fertig."
    fi
}

# On one line, so bash has read it completely before the update rewrites this file.
main "$@"; exit
