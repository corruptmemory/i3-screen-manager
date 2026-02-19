# i3-screen-manager

Bash scripts for managing external displays on i3/X11 with hybrid graphics, plus keyboard layout toggling.

## Architecture

Scripts, no build step:
- `i3-screen-manager` — CLI that wraps `xrandr` and `i3-msg` for display management
- `i3-screen-rofi` — Rofi menu frontend that calls `i3-screen-manager`
- `~/.local/bin/i3-keyboard-rofi` — Standalone rofi toggle for laptop vs external keyboard layout

## Key Design Decisions

- **Internal display is hardcoded as `eDP-1`** — standard for modern Intel laptop panels
- **External display is auto-detected** — finds first connected non-internal output via `xrandr`
- **Lid state path is discovered dynamically** — ACPI names vary (`LID`, `LID0`, etc.) across boots
- **Safe defaults** — if lid state can't be detected, assume closed (refuse disconnect rather than risk black screen)
- **Clamshell uses `systemd-inhibit`** — holds a `handle-lid-switch` block lock via a background `sleep infinity` process, PID tracked in `/tmp/i3-screen-manager-inhibit.pid`
- **Disconnect enables internal BEFORE disabling external** — no window where zero displays are active

## Testing

No automated tests. Test manually with an external monitor:
1. `i3-screen-manager extend-right` — external should light up
2. `i3-screen-manager mirror` — both screens same content
3. `i3-screen-manager clamshell` — laptop off, external only, close lid safely
4. `i3-screen-manager disconnect` (lid closed) — should refuse
5. Open lid, `i3-screen-manager disconnect` — should restore laptop screen

## Common Issues

- **Black screen on disconnect**: Usually means lid was closed and eDP-1 couldn't activate. The lid guard should prevent this now.
- **Workspace move errors**: `"No output matched"` from i3-msg is usually harmless — workspace was already on the target output.
- **External not detected**: Check `xrandr` — the output might use a different name than expected. Nvidia outputs follow `*-N-N` naming pattern (e.g., `HDMI-1-0`, `DP-1-0`).
