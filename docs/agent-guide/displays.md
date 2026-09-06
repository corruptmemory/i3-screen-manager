# Displays

Read this guide for layout, docking, scaling, lid handling, monitor discovery,
or workspace-placement changes. Sources: `i3-screen-manager`, `i3-screen-rofi`,
`laptop-monitor.sh`, `laptop-monitor-x11.sh`, `hyprland-clamshell-restore`, and
dotfiles' `hypr/monitors.lua`, `hypr/machine.lua`, `hypr/autostart.lua`, and
`quickshell/shell.qml` under `.config/`.

## Backend and Scope

`XDG_SESSION_TYPE=wayland` or a nonempty `WAYLAND_DISPLAY` selects Hyprland;
otherwise the CLI uses X11. The laptop layout commands assume internal output
`eDP-1` and select the first connected non-internal output. They are not a
general multi-external-monitor layout manager. The desktop's fixed layout
belongs to dotfiles; `scale`/`dpi` can still be used on its focused output.

Wayland discovery uses `wlr-randr` to include connected but disabled outputs.
X11 discovery uses `xrandr --query` after attempting the NVIDIA PRIME provider
hookup. Provider errors must remain off stdout because discovery output is
captured as an output name. X11 and Wayland names differ: the desktop's
secondary output is `HDMI-1` on X11 and `HDMI-A-1` on Wayland. Query names
instead of transferring them between backends by assumption.

## Layout and Scaling

The commands are `extend-left/right/above/below`, `clamshell`, `mirror`,
`disconnect`, `scale [VALUE] [OUTPUT]`, `dpi [VALUE] [OUTPUT]`, `status`, and
Wayland-only `apply-ws-split`. `dpi` is an alias for `scale`.

Wayland uses `hl.monitor({...})` through the script's `hl_apply` helper and
`hyprctl-live dispatch`. The helper suppresses dispatcher errors because the
monitor-setting call can apply its side effect before the wrapper complains;
its exit status alone does not prove success. Workspace moves use
`hl.dsp.workspace.move({ workspace = ..., monitor = ... })`.

Default scales are 1.25 internal and 1.0 external. The picker offers 0.75, 1.00,
1.25, 1.50, 1.75, and 2.00. The default target is the focused Wayland output,
falling back to `eDP-1`. Scaling also sets preferred mode and automatic
position; it is not a position-preserving operation. These are runtime
settings; persistent defaults are in the session configuration.

X11 scaling sets session-wide `Xft.dpi` to the integer value of `96 * scale`
through `xrdb -merge`. It ignores the output argument and needs newly launched
apps to take effect. It does not apply per-output framebuffer scaling.
Mirroring uses Hyprland's mirror property or X11 `--same-as`, with preferred
modes rather than a negotiated common resolution.

## Transition Constraints

- Explicitly pass `disabled = false` when re-enabling a Hyprland monitor.
- Enable a workspace's target monitor before moving workspaces onto it.
- Free the internal output's destination position before restoring it. The
  disconnect sequence moves the external to `10000x0`, enables internal at
  `0x0`, moves workspaces back, then disables the external.
- Pair the Hyprland disable with `wlr-randr --output OUTPUT --off` as the
  existing scripts do; compositor state and physical output state can differ.
- Preserve the lid guard. `disconnect` refuses if the lid is closed or cannot
  be read from `/proc/acpi/button/lid/*/state`.
- Clamshell uses an `elogind-inhibit` background process with PID recorded in
  `/tmp/i3-screen-manager-inhibit.pid`. It inhibits lid-triggered suspend on
  both backends. Extend, mirror, and disconnect stop that inhibitor.

## Workspace Contract

The laptop's configured pools are 1-6 internal and 7-10 external in extend
mode, all 1-10 on external in clamshell, and all 1-10 internal when undocked.
Clamshell moves all existing workspaces to the external; disconnect moves
workspaces from that external back to the internal. X11 layout commands do not
implement this Hyprland workspace split.

Keep three consumers aligned: `EXTERNAL_WORKSPACES` in the display script,
workspace data/rules in dotfiles' `machine.lua` and `monitors.lua`, and
Quickshell's `shell.qml` pools. Persistent workspace rules instantiate 1-10;
`autostart.lua` invokes `apply-ws-split` on `monitor.added` and after startup.
The command succeeds silently without an external and rejects X11 sessions.
It moves workspaces; it is not an output-enabling command.

## Known Limitations

`laptop-monitor.sh` and `hyprland-clamshell-restore` still contain legacy
`hyprctl keyword` calls and use bare `hyprctl`. Their output-off paths also
call `wlr-randr`, but lid-open restoration is not fully ported to Lua mode.
The reload helper is wired through `config.reloaded`; the X11 lid script has
no automatic acpid wiring supplied by this repo.

Extend reads internal geometry before re-enabling the internal monitor;
transitioning directly from clamshell needs special attention. The script
suppresses several compositor errors, so printed success is insufficient.
Quickshell checks named desktop pools before its dynamic laptop fallback;
verify pool behavior when a laptop external happens to use `DP-2` or
`HDMI-A-1`.

## Display Verification

With the relevant session and an external monitor available, check all four
extend directions, mirror, clamshell, the closed-lid disconnect refusal,
open-lid restoration, focused and explicit-output scaling, and status output.
Check transitions from clamshell as well as from a normal extended layout.
Inspect monitor state and visible output after every operation. On Hyprland,
also check workspace pools, config reload, physical unplug/replug, and hot-plug
at startup. On X11, check PRIME discovery and newly launched apps after DPI
changes. Do not claim these hardware checks passed based on syntax checks.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
