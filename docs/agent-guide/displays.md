# Displays

Read this guide for layout, docking, scaling, lid handling, monitor discovery,
or workspace-placement changes. Sources: `i3-screen-manager`, `i3-screen-rofi`,
`laptop-monitor.sh`, `laptop-monitor-x11.sh`, and
dotfiles' `hypr/monitors.lua`, `hypr/machine.lua`, `hypr/workspaces.lua`,
`hypr/vendor/omarchy/`, `hypr/autostart.lua`, and `quickshell/shell.qml` under
`.config/`.

## Backend and Scope

`XDG_SESSION_TYPE=wayland` or a nonempty `WAYLAND_DISPLAY` selects Hyprland;
otherwise the CLI uses X11. The laptop's internal output is `eDP-1` under
Wayland and under X11 in Hybrid mode (Intel modesetting). In Discrete mode the
NVIDIA X driver names it after its DP head (`DP-4`) with `ConnectorType: Panel`,
so the X11 path resolves it at run time (`x11_internal_output`, falling back to
`eDP-1`); `laptop-monitor-x11.sh` and the laptop polybar launcher do the same.
The layout commands select the first connected non-internal output. They are not a
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
`disconnect`, `scale [VALUE] [OUTPUT]`, `dpi [VALUE] [OUTPUT]`, and `status`.
`dpi` is an alias for `scale`.

Wayland uses `hl.monitor({...})` through the script's `hl_apply` helper and
`hyprctl-live dispatch`. The helper suppresses dispatcher errors because the
monitor-setting call can apply its side effect before the wrapper complains;
its exit status alone does not prove success. The script moves no workspaces
([Workspace Contract](#workspace-contract)). After a layout change it restarts
a running `swaybg` with the same arguments through `hl.dsp.exec_cmd`, so
Hyprland owns it whichever shell ran the command.

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
- Enable the monitor that will receive workspaces before disabling the one
  that holds them: Hyprland moves a disabled monitor's workspaces onto a
  monitor still on. Clamshell enables the external before disabling `eDP-1`.
- Place outputs by the sizes the command sets, each output's preferred mode at
  its default scale, not by their current sizes. From clamshell the panel is
  disabled and missing from `hyprctl monitors`, and Hyprland replaces a
  malformed position such as `x0` with `auto`, an error `hl_apply` hides.
  Extend stops before changing the layout if it finds no preferred mode.
- Free the internal output's destination position before restoring it. The
  disconnect sequence moves the external to `10000x0`, enables internal at
  `0x0`, then disables the external.
- Pair the Hyprland disable with `wlr-randr --output OUTPUT --off` as the
  existing scripts do; compositor state and physical output state can differ.
- Preserve the lid guard. `disconnect` refuses if the lid is closed or cannot
  be read from `/proc/acpi/button/lid/*/state`.
- Clamshell uses an `elogind-inhibit` background process with PID recorded in
  `/tmp/i3-screen-manager-inhibit.pid`. It inhibits lid-triggered suspend on
  both backends. Extend, mirror, and disconnect stop that inhibitor.
- Clamshell takes that lock before changing the layout, and counts it only once
  `elogind-inhibit --list` shows it. polkit grants it only to the seat's active
  session, so from an SSH or Rex shell clamshell changes nothing and exits 1
  with a critical notification. A layout change that aborts releases the lock.

## Workspace Contract

On Hyprland, on both machines, every monitor has its own workspaces 1-10; X11
layout commands do not implement this. Hyprland numbers workspaces globally, so
each physical monitor, identified by make, model and serial, owns a block of
ten ids: block b is ids 10b+1 to 10b+10. `Super+N` shows slot N on the focused
monitor, `Super+Shift+N` moves the window there and follows it, and
`Super+comma` or `Super+period` focus the previous or next monitor (with Shift,
the window goes there). `Super+N` for the slot already shown returns to that
monitor's previous workspace where `workspace_back_and_forth` is on (the
desktop), and only focuses that monitor where it is off (the laptop).

`workspaces.lua` loads Omarchy's `monitor-workspaces.lua`, vendored under
`hypr/vendor/omarchy/` from 43c08a499 with its MIT license. Its header lists
the local edits to reapply when re-syncing, and `tests/test_monitor_workspaces.lua`
runs upstream's scenarios against a fake Hyprland. A connector given a `block`
in `machine.lua` keeps that block, and `monitors.lua` creates each of its ids
on it: the desktop pins DP-2 to 1-10 and the portrait HDMI-A-1 to 11-20, and
the laptop pins `eDP-1` to 1-10 (`monitors.internal.block`). Any other monitor,
such as a laptop external, takes the lowest free block when first seen. The
panel's pin matters when the module first runs clamshelled: the disabled panel
is not in `hl.get_monitors()`, and unpinned, the external would take 1-10.
Blocks persist in `$XDG_STATE_HOME/hypr/monitor-workspaces` (default
`~/.local/state`), which the bar reads.

On `hyprland.start`, `config.reloaded`, and monitor addition or removal, the
module puts each workspace back on its monitor and each monitor on one of its
own. A removed monitor's workspaces join the remaining monitor's block after
its own, and `monitor-workspaces-merged` sends them home when it returns. A
script shows a slot with `hyprctl dispatch 'workspaces.focus(N, "OUTPUT")'`.

Disabling a monitor is a removal to Hyprland 0.57.1: `hl.monitor` with
`disabled = true` reaches `CMonitor::onDisconnect`, which emits
`monitor.removed`, drops the monitor from `hl.get_monitors()`, and moves its
workspaces onto a monitor still on. So `i3-screen-manager` moves no workspaces.
Disabling `eDP-1`, by clamshell or by closing the lid with an external on, puts
the panel's workspaces after the external's own; `disconnect` and lid open
re-enable the panel and its workspaces return. Extend gives a new external the lowest free block, and it
starts on its own first workspace. The laptop's comms wall, `chat_workspace`,
is 10, the panel's slot 10; the desktop's is 20, the portrait's slot 10.

## Lid Helpers

Dotfiles' `bindings.lua` runs `laptop-monitor.sh close` and `open` from the lid
switch. While any monitor other than `eDP-1` is active, close records the
panel's position with the other monitors' names, positions, sizes and scales
in `$XDG_RUNTIME_DIR/laptop-monitor-panel`, disables `eDP-1`, and cuts it with
`wlr-randr`. Open re-enables it at scale 1.25: at the recorded position if the
other monitors still match the record, otherwise at `auto`, because a monitor
that moved could overlap the old spot. With no other monitor active, close does
nothing. Open does nothing while the panel is on, or while the clamshell
inhibitor runs and another monitor is active. Hyprland's headless `FALLBACK`
output, added when the last monitor goes, doesn't count, so opening the lid
after the external is gone brings the panel back. Both set the panel with
`hyprctl-live eval 'hl.monitor({...})'` and raise a critical notification when
it fails.

A config reload leaves the panel as it was. Hyprland 0.57.1's reload clears
every monitor rule, and `wlr-randr`'s off lasts only while its client is
connected. So a re-added panel rule without `disabled` would turn a panel that
clamshell or a closed lid switched off back on. Hyprland would hand it its
workspaces, and the module would merge them back onto the external under new
numbers once something turned it off again. Instead, when Hyprland already
runs an external and not the panel at config load, `monitors.lua` adds the
panel with `disabled = true`. At startup nothing runs yet, so the panel always
comes up. A runtime `hl.monitor` eval differs from a reload: it starts from the
output's current rule, so fields it omits, `disabled` included, keep their
values.

## Known Limitations

Lid open puts the panel at `auto`, to the right of the other monitors, when
they changed while the lid was shut. The X11 lid script has no automatic acpid
wiring supplied by this repo.

The script suppresses several compositor errors, so printed success is
insufficient.

## Display Verification

With the relevant session and an external monitor available, check all four
extend directions, mirror, clamshell, the closed-lid disconnect refusal,
open-lid restoration, focused and explicit-output scaling, and status output.
Check transitions from clamshell as well as from a normal extended layout.
Inspect monitor state and visible output after every operation. On Hyprland,
also check config reload, including while clamshelled, physical
unplug/replug, and hot-plug at startup. Run dotfiles' `tests/run.sh`, then
check `Super+N` on each monitor, the monitor chords, bar clicks on the
unfocused monitor, the state file, and where a disabled or removed monitor's
workspaces go and return. On X11, check PRIME discovery and newly launched apps
after DPI changes. Do not claim these hardware checks passed based on syntax
checks.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
