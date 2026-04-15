#!/usr/bin/env bash
#
# Handles lid open/close events from Hyprland's bindl switch bindings.
# Only acts when an external monitor is already active.
#
# Called by hyprland.conf:
#   bindl=,switch:off:Lid Switch,exec,~/.local/bin/laptop-monitor.sh open
#   bindl=,switch:on:Lid Switch,exec,~/.local/bin/laptop-monitor.sh close

PIDFILE="/tmp/i3-screen-manager-inhibit.pid"

# If clamshell mode is active (inhibitor running), ignore lid-open events.
# i3-screen-manager clamshell already handles the display state; re-enabling
# eDP-1 here would fight it and put workspaces back on the internal display.
if [[ $1 == "open" ]]; then
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        exit 0
    fi
fi

if [[ "$(hyprctl monitors)" =~ [[:space:]]HDMI-A-[0-9]+ ]] || \
   [[ "$(hyprctl monitors)" =~ [[:space:]]DP-[0-9]+ ]]; then
    if [[ $1 == "open" ]]; then
        hyprctl keyword monitor "eDP-1,preferred,auto,1.25"
    else
        hyprctl keyword monitor "eDP-1,disable"
        wlr-randr --output eDP-1 --off 2>/dev/null || true
    fi
fi
