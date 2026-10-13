#!/usr/bin/env bash
# Brings your Mac to the newest CopyPal state in one step, from any folder:
#   1. finds the Test-1 clone (COPYPAL_REPO, the checkout this script is in, or the
#      usual places such as ~/Developer/Test-1)
#   2. sets local changes aside (git stash) – usually files Xcode touched – so the
#      update never stops at "Your local changes … would be overwritten"
#   3. puts the clone on the CopyPal branch exactly as it is on GitHub, or on main once
#      that branch is merged; own commits stay on a backup branch
#   4. regenerates the Xcode project (bootstrap.sh) and opens it
# Usage: update.sh [--install] [--no-open]
#   --install   also adds the command "copypal-update" to your shell (once). It runs
#               the newest version of this script from GitHub, from any folder.
#   --no-open   does not open Xcode at the end
# COPYPAL_BRANCH=<branch> updates to that branch instead (no fallback to main).
# Compatible with the bash 3.2 that ships with macOS.
set -euo pipefail

# Without a login, git would ask for a user name and password (twice): fail at once
# and point to gh auth login instead.
export GIT_TERMINAL_PROMPT=0

bootstrap_failed=0
trap 'status=$?; if [ "$status" -ne 0 ] && [ "$bootstrap_failed" -eq 0 ]; then echo "Abgebrochen – der Grund steht in der Meldung darüber. Lokale Änderungen und Commits bleiben erhalten." >&2; fi' EXIT

branch="${COPYPAL_BRANCH:-claude/amazing-volta-1uce5i}"
target=""
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

# GitHub's default branch (main).
default_branch() {
    local name
    name="$(git ls-remote --symref origin HEAD | awk '$1 == "ref:" && $3 == "HEAD" { sub("^refs/heads/", "", $2); print $2 }')" || return 1
    printf '%s\n' "${name:-main}"
}

# The branch to put the clone on: the CopyPal branch while GitHub has it and it is
# not yet merged into the default branch, afterwards the default branch. A branch
# named in COPYPAL_BRANCH is taken as it is. Exit 1: GitHub unreachable; 3: the
# named branch does not exist.
target_branch() {
    local status=0 default
    git ls-remote --exit-code --heads origin "refs/heads/$branch" > /dev/null || status=$?
    case "$status" in
        0)
            if [ -z "${COPYPAL_BRANCH:-}" ]; then
                default="$(default_branch)" || return 1
                git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" \
                    "+refs/heads/$default:refs/remotes/origin/$default" || return 1
                if git merge-base --is-ancestor "origin/$branch" "origin/$default"; then
                    printf '%s\n' "$default"
                    return 0
                fi
            fi
            printf '%s\n' "$branch"
            ;;
        2)
            [ -z "${COPYPAL_BRANCH:-}" ] || return 3
            default_branch
            ;;
        *) return 1 ;;
    esac
}

# Single-quoted for the shell.
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# A folder for things set aside during this run (inside .git, never committed).
backup_dir() {
    local dir stamp n=1
    dir="$(git rev-parse --git-path copypal-backups)"
    stamp="$(date '+%Y%m%d-%H%M%S')"
    while [ -e "$dir/$stamp$1" ]; do
        n=$((n + 1))
        stamp="$(date '+%Y%m%d-%H%M%S')-$n"
    done
    printf '%s\n' "$dir/$stamp$1"
}

# Keeps the files of an interrupted operation as a patch before it is undone.
save_patch() {
    local patch
    patch="$(backup_dir .patch)"
    mkdir -p "$(dirname "$patch")"
    git diff --binary HEAD > "$patch" || true
    echo "Zwischenstand gesichert: $PWD/$patch (zurückspielen: git -C $(quote "$PWD") apply $(quote "$patch"))"
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
        # --merge (what git merge --abort uses) keeps edits in files outside the conflict,
        # so the stash below catches them; it refuses in rare mixed states.
        git reset -q --merge 2> /dev/null || git reset -q --hard
    fi
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        git stash push -q -m "copypal-update $(date '+%Y-%m-%d %H:%M')"
        echo "Lokale Änderungen (meist von Xcode, die braucht man nicht zurück) beiseitegelegt." \
            "Ansehen: git -C $(quote "$PWD") stash list · zurückholen: git -C $(quote "$PWD") stash pop"
    fi
}

# Untracked files that the new state also contains (e.g. written by SwiftPM) would
# stop the switch ("untracked working tree files would be overwritten"): move them aside.
move_blocking_files() {
    local file dir=""
    while IFS= read -r -d '' file; do
        git cat-file -e "origin/$target:$file" 2> /dev/null || continue
        if [ -z "$dir" ]; then
            dir="$(backup_dir -im-weg)"
        fi
        mkdir -p "$dir/$(dirname "$file")"
        mv "$file" "$dir/$file"
        echo "Datei im Weg beiseitegelegt: $file → $PWD/$dir/"
    done < <(git ls-files -o --exclude-standard -z)
}

# Commits GitHub does not have – on the local target branch, on the branch being left,
# or on a detached HEAD – go to a backup branch. Commits GitHub itself replaced
# (force-push; `old_remote_tips` are the remote tips before this run) are not the
# user's and get none.
back_up_own_commits() {
    local old_remote_tips="$1" current tips tip backup what
    current="$(git symbolic-ref -q --short HEAD || true)"
    tips="refs/heads/$target"
    if [ -z "$current" ]; then
        tips="$tips HEAD"
    elif [ "$current" != "$target" ]; then
        tips="$tips refs/heads/$current"
    fi
    for tip in $tips; do
        git rev-parse -q --verify "$tip^{commit}" > /dev/null 2>&1 || continue
        # shellcheck disable=SC2086 – the tips are meant to be split into words.
        if [ -n "$(git rev-list -n 1 "$tip" --not "origin/$target" $old_remote_tips)" ]; then
            backup="copypal-sicherung-$(date '+%Y%m%d-%H%M%S')-$(git rev-parse --short "$tip")"
            git branch -f "$backup" "$tip"
            case "$tip" in
                HEAD) what="vom losgelösten Stand" ;;
                *) what="aus ${tip#refs/heads/}" ;;
            esac
            echo "Eigene Commits $what gesichert im Branch $backup"
        fi
    done
}

# Adds "copypal-update" to the shell's startup file, replacing an earlier version.
install_command() {
    local repo="$1" rc tmp first_line=""
    case "$(basename "${SHELL:-/bin/zsh}")" in
        bash)
            # A login bash reads only the first of these that exists; ~/.profile is
            # left alone (sh rejects the function name) but sourced from a new file.
            if [ -f "$HOME/.bash_profile" ]; then
                rc="$HOME/.bash_profile"
            elif [ -f "$HOME/.bash_login" ]; then
                rc="$HOME/.bash_login"
            else
                rc="$HOME/.bash_profile"
                [ -f "$HOME/.profile" ] && first_line='[ -f ~/.profile ] && . ~/.profile'
            fi
            ;;
        *) rc="$HOME/.zshrc" ;;
    esac
    tmp="$(mktemp)"
    if [ -f "$rc" ]; then
        awk -v s="$marker_start" -v e="$marker_end" '$0 == s { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$rc" > "$tmp"
    elif [ -n "$first_line" ]; then
        printf '%s\n' "$first_line" > "$tmp"
    fi
    # Runs the script from GitHub, not from the folder: works on any branch and
    # always with the newest fixes.
    cat >> "$tmp" <<EOF
$marker_start
# Holt den neuesten Stand von CopyPal und öffnet Xcode (CopyPal/scripts/update.sh).
copypal-update() {
    # "st", not "status": that name is read-only in zsh.
    local default=$(quote "$repo") repo ref err script st
    repo="\${COPYPAL_REPO:-\$default}"
    if ! git -C "\$repo" rev-parse --git-dir > /dev/null 2>&1; then
        echo "copypal-update: \$repo ist kein Git-Ordner (mehr). Ordner verschoben? Die Einrichtungszeile aus CopyPal/README.md erneut einfügen, oder COPYPAL_REPO=<Ordner> copypal-update" >&2
        return 1
    fi
    for ref in $(quote "$branch") main; do
        st=0
        err="\$(GIT_TERMINAL_PROMPT=0 git -C "\$repo" ls-remote --exit-code --heads origin "refs/heads/\${ref}" 2>&1 > /dev/null)" || st=\$?
        case "\$st" in
            0) break ;;
            2) ref=""; continue ;;
            *)
                printf '%s\\n' "\$err" >&2
                echo "copypal-update: Keine Verbindung zu GitHub oder nicht angemeldet – Internet prüfen, dann: gh auth login" >&2
                return 1
                ;;
        esac
    done
    if [ -z "\$ref" ]; then
        echo "copypal-update: Weder den CopyPal-Branch noch main gibt es auf GitHub." >&2
        return 1
    fi
    # Into its own ref: origin/* must stay as it is until the script has looked at it.
    git -C "\$repo" fetch -q origin "+refs/heads/\${ref}:refs/copypal/\${ref}" || return 1
    script="\$(git -C "\$repo" show "refs/copypal/\${ref}:CopyPal/scripts/update.sh")" || return 1
    COPYPAL_REPO="\$repo" bash -c "\$script" copypal-update "\$@"
}
$marker_end
EOF
    # Writing through keeps a symlinked startup file (dotfile managers) intact.
    cat "$tmp" > "$rc"
    rm -f "$tmp"
    echo "Eingerichtet in $rc: Ab dem nächsten Terminal-Fenster reicht der Befehl copypal-update"
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

    # Before anything is fetched: everything GitHub's branches ever pointed to here
    # (current tips and their reflogs), so commits GitHub rewrote are not mistaken for
    # the user's own.
    local old_remote_tips ref
    old_remote_tips="$({
        git for-each-ref --format='%(objectname)' refs/remotes/origin/
        git for-each-ref --format='%(refname)' refs/remotes/origin/ | while IFS= read -r ref; do
            git rev-list -g "$ref" 2> /dev/null || true
        done
    } | sort -u | tr '\n' ' ')"

    local status=0
    target="$(target_branch)" || status=$?
    case "$status" in
        0) ;;
        3)
            echo "Den Branch $branch gibt es auf GitHub nicht. Tippfehler in COPYPAL_BRANCH? Ohne COPYPAL_BRANCH holt copypal-update den CopyPal-Branch." >&2
            exit 1
            ;;
        *)
            echo "GitHub ist nicht erreichbar, oder du bist nicht angemeldet (Internet prüfen, dann: gh auth login)." >&2
            exit 1
            ;;
    esac
    git fetch -q origin "+refs/heads/$target:refs/remotes/origin/$target"

    set_aside_changes
    move_blocking_files

    local before
    before="$(git rev-parse -q --verify HEAD || true)"
    back_up_own_commits "$old_remote_tips"
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
    local bootstrap_status=0
    if [ "$open_xcode" = 1 ]; then
        CopyPal/scripts/bootstrap.sh --open || bootstrap_status=$?
    else
        CopyPal/scripts/bootstrap.sh || bootstrap_status=$?
    fi
    if [ "$bootstrap_status" -ne 0 ]; then
        bootstrap_failed=1
        echo
        echo "Der Code ist aktuell, aber das Xcode-Projekt wurde nicht neu erzeugt. Bitte das Problem oben beheben und copypal-update erneut ausführen." >&2
        exit 1
    fi
    echo
    if [ "$open_xcode" = 1 ]; then
        echo "Fertig. In Xcode jetzt ⌘R drücken."
    else
        echo "Fertig."
    fi
}

# On one line, so bash has read it completely before the update rewrites this file.
main "$@"; exit
