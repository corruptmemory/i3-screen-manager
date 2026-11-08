#!/usr/bin/env bash
#
# laptop-monitor.sh open|close: lid handling under Hyprland while an external monitor is on.
# Lid close turns the internal panel off; lid open turns it back on. With no active external
# monitor it does nothing, and lid open does nothing while clamshell mode's inhibitor runs.
#
# dotfiles' .config/hypr/bindings.lua binds it to the lid switch:
#   switch:on:Lid Switch  -> laptop-monitor.sh close
#   switch:off:Lid Switch -> laptop-monitor.sh open
#
# Hyprland's Lua config refuses `hyprctl keyword`, so the panel is set with
# `hyprctl eval 'hl.monitor({...})'`, whose errors are reported. hyprctl-live finds the
# running Hyprland from any shell. See docs/agent-guide/displays.md.
set -uo pipefail

INTERNAL=eDP-1
INTERNAL_SCALE=1.25
PIDFILE=/tmp/i3-screen-manager-inhibit.pid

fail() {
    echo "laptop-monitor.sh: $*" >&2
    command -v notify-send >/dev/null && notify-send -u critical "Lid" "$*"
    exit 1
}

hl_monitor() { # the fields of one hl.monitor table
    local out
    out=$(hyprctl-live eval "hl.monitor({ $1 })" 2>&1) || true
    [[ $out == ok ]] || fail "hl.monitor({ $1 }) failed: $out"
}

case "${1:-}" in
    open | close) ;;
    *) echo "usage: laptop-monitor.sh open|close" >&2; exit 2 ;;
esac

# Clamshell mode (i3-screen-manager clamshell) owns the display state. Turning the panel on
# here would fight it and pull workspaces back onto the internal display.
if [[ $1 == open && -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi

monitors=$(hyprctl-live monitors -j 2>&1) || fail "could not query Hyprland: $monitors"
jq -e --arg i "$INTERNAL" 'any(.[]; .name != $i)' <<<"$monitors" >/dev/null || exit 0

if [[ $1 == open ]]; then
    # `disabled = false` is required: the other fields alone leave a disabled monitor off.
    hl_monitor "output = \"$INTERNAL\", mode = \"preferred\", position = \"auto\", scale = $INTERNAL_SCALE, disabled = false"
else
    hl_monitor "output = \"$INTERNAL\", disabled = true"
    # The compositor's disable can leave the panel lit; cut the output too.
    wlr-randr --output "$INTERNAL" --off 2>/dev/null || true
fi
