# lib/require.sh — shared _require helper for rofi menu scripts.
#
# Sourced (not executed) by scripts in this repo AND in the dotfiles repo.
# Machine-local install is a symlink at $HOME/.local/lib/sh/require.sh
# pointing at this file — see docs/2026-07-29-rofi-emoji-picker-fix.md § 8
# for the trap-class this guards against, and 2026-07-21-i3-laptop-setup.md
# § "One-time machine setup (symlinks)" for the install step.
#
# Sourcing pattern (verbatim in every consumer script):
#
#     . "$HOME/.local/lib/sh/require.sh"
#     _require rofi jq …
#
# BOOTSTRAP: if the symlink is missing, `. /nonexistent` under
# `set -euo pipefail` prints
#
#     bash: line N: /home/…/require.sh: No such file or directory
#
# and exits — better than the silent-vanish we're hardening against, and
# specific enough to diagnose. Scripts that DON'T use pipefail (e.g.,
# powermenu.sh) still get the visible bash error and continue running with
# `_require` undefined — subsequent `_require …` calls will fail with a
# clear "command not found" line. Either way, no silent vanish.
#
# WHY NOT BUNDLE INLINE: seven copies drift; one shared file is authoritative.
# WHY NOT SOURCE VIA RELATIVE PATH: scripts live in two different repos and
# get symlinked into ~/.local/bin/ or ~/.config/rofi/scripts/, so $0 doesn't
# point at their source location and relative-source lookups break.

_require() {
    local missing=() t name msg
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0
    name=$(basename "$0")
    msg="required tool(s) not installed: ${missing[*]}"
    command -v notify-send >/dev/null 2>&1 \
        && notify-send -u critical -t 6000 "$name" "$msg" \
        || true
    echo "$name: $msg" >&2
    exit 1
}
