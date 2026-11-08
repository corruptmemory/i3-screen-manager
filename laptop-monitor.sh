#!/usr/bin/env bash
#
# laptop-monitor.sh open|close: lid handling under Hyprland while an external monitor is on.
# Lid close turns the internal panel off and remembers where it was; lid open turns it back on
# there if the other monitors are laid out as they were, and at `auto` otherwise. Close does
# nothing with no other monitor active. Open does nothing while the panel is on, or while
# clamshell mode's inhibitor runs and another monitor is active.
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
SAVED=${XDG_RUNTIME_DIR:-/tmp}/laptop-monitor-panel # "POSITION<TAB>LAYOUT", written by close

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

monitors=$(hyprctl-live monitors -j 2>&1) || fail "could not query Hyprland: $monitors"

panel_on() { jq -e --arg i "$INTERNAL" 'any(.[]; .name == $i)' <<<"$monitors" >/dev/null; }
# Hyprland adds a headless FALLBACK output when the last monitor goes; it shows nothing.
others_on() { jq -e --arg i "$INTERNAL" 'any(.[]; .name != $i and .name != "FALLBACK")' <<<"$monitors" >/dev/null; }
layout() { # every active monitor but the panel, with where it is and how big
    jq -c --arg i "$INTERNAL" 'map(select(.name != $i) | [.name, .x, .y, .width, .height, .scale]) | sort' <<<"$monitors"
}

if [[ $1 == open ]]; then
    panel_on && exit 0
    # Clamshell mode (i3-screen-manager clamshell) owns the display state while its external is
    # on. Turning the panel on would fight it and pull workspaces back onto the internal display.
    if others_on && [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        exit 0
    fi

    # Put the panel back where close found it, unless the other monitors have changed since:
    # then the old spot may overlap one, and `auto` places it to their right instead.
    position=auto
    if [[ -r $SAVED ]] && IFS=$'\t' read -r saved_position saved_layout <"$SAVED" &&
        [[ $saved_position =~ ^-?[0-9]+x-?[0-9]+$ && $saved_layout == "$(layout)" ]]; then
        position=$saved_position
    fi
    # `disabled = false` is required: the other fields alone leave a disabled monitor off.
    hl_monitor "output = \"$INTERNAL\", mode = \"preferred\", position = \"$position\", scale = $INTERNAL_SCALE, disabled = false"
    rm -f "$SAVED"
else
    others_on || exit 0
    if position=$(jq -re --arg i "$INTERNAL" '.[] | select(.name == $i) | "\(.x)x\(.y)"' <<<"$monitors"); then
        printf '%s\t%s\n' "$position" "$(layout)" >"$SAVED"
    fi
    hl_monitor "output = \"$INTERNAL\", disabled = true"
    # The compositor's disable can leave the panel lit; cut the output too.
    wlr-randr --output "$INTERNAL" --off 2>/dev/null || true
fi
