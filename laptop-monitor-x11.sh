#!/usr/bin/env bash
#
# laptop-monitor-x11.sh — X11/IceWM sibling of laptop-monitor.sh.
#
# Handles lid open/close events under X11. Called with "open" or "close" as $1.
# Only acts when an external monitor is already active. If clamshell mode is
# already on (the inhibitor PID file exists), ignores lid-open events so that
# i3-screen-manager's clamshell state isn't fought.
#
# This script is NOT wired into anything by default. Two reasons:
#   1. Under IceWM there is no native lid binding — wiring needs acpid as a
#      system daemon, plus the standard `acpid → su → DISPLAY/XAUTHORITY`
#      shuffle for the handler to actually reach the user's X session.
#   2. With acpid always-on across both compositors, the Hyprland `bindl`
#      and the acpid handler can both fire on a single lid event (idempotent
#      but noisy).
#
# Canonical flow on X11/IceWM: enter clamshell explicitly via
#   `i3-screen-rofi → Clamshell (external only)`
# which starts the inhibitor + disables eDP-1 via xrandr. Leave via
#   `i3-screen-rofi → Disconnect`.
#
# If you do want acpid wiring later, see the recipe in
#   docs/2026-06-17-icewm-laptop-setup.md (section: Lid handling, deferred).

PIDFILE="/tmp/i3-screen-manager-inhibit.pid"
INTERNAL="eDP-1"

# Clamshell-mode guard for lid-open: i3-screen-manager clamshell already owns
# the display state; re-enabling eDP-1 here would fight it.
if [[ $1 == "open" ]]; then
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        exit 0
    fi
fi

# Only act when at least one external is currently up (xrandr "connected" with
# a geometry). Mirrors the Hyprland sibling's HDMI-A-* / DP-* check.
if xrandr --query 2>/dev/null | awk -v internal="$INTERNAL" '
       / connected.*[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/ && $1 != internal { found=1 }
       END { exit !found }
   '; then
    if [[ $1 == "open" ]]; then
        xrandr --output "$INTERNAL" --auto --pos 0x0
    else
        xrandr --output "$INTERNAL" --off
    fi
fi
