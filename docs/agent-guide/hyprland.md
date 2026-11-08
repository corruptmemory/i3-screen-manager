# Hyprland and Quickshell

Read this guide for Lua config, session startup, focus/group behavior, bars,
screenshots, or monitor sleep. Sources here: `start-hyprland`, `hyprctl-live`,
`hypr-dpms-all`, `screenshot`, `screenshot.sh`, `flameshot.sh`. Configuration
sources are `dotfiles/.config/hypr/` and `dotfiles/.config/quickshell/`.

## Session and Configuration

The live Hyprland config directory points into dotfiles. `hyprland.lua` loads
`machine`, `vars`, `envs`, `monitors`, `workspaces`, `looknfeel`, `rules`,
`autostart`, and `bindings`. `machine.lua` selects static capabilities by hostname; branch on
traits for hardware behavior. `HYPR_MACHINE_OVERRIDE` supports the test harness.
Keep config-load code cheap and free of startup side effects: configuration
evaluation can happen more than once on a reload. Launch daemons from
`hl.on('hyprland.start', ...)`, and keep reload-specific work in its own hook.

Hyprland reloads when a loaded config file changes, so a `git pull` in dotfiles
can reload in the middle of the checkout. If a pull adds a module that an
existing file requires, the reload can stop at the missing file. Only the
built-in fallback binds are then live, and one is `Super+M`, which exits the
session. The new file was never loaded, so nothing watches it and no second
reload comes. Both machines therefore have a hook in dotfiles' `.git/hooks`,
installed by hand and not tracked: `post-merge`, with `post-rewrite` symlinked
to it. After a pull that changed `.config/hypr`, while Hyprland runs, it
reloads the config and reports `configerrors`, raising a critical notification
on errors. A fast-forward pull runs `post-merge` in either pull mode; a rebase
that replays local commits runs `post-rewrite` when it ends. Without the hook,
reload by hand with `hyprctl-live dispatch 'hl.dsp.reload_config()'`.

The root `start-hyprland` script is the laptop-oriented launcher. Dotfiles also
contains a desktop launcher with the same basename. Resolve the installed
command before editing it. Launchers set session identity, the user D-Bus
address, keyring and SSH-agent environment, GPU settings, and then execute
`/usr/bin/start-hyprland`. Do not invoke a session launcher inside a running
compositor. Desktop autostart launches audio; laptop OpenRC user services own
audio and must not be duplicated by compositor autostart.

Use Lua-mode `hl.dsp.*` dispatchers, `hl.monitor`, and `hl.config` in this
configuration. Legacy `hyprctl keyword` and bareword dispatcher strings do not
provide the same interface. Prefer current code and installed API definitions
over examples for another Hyprland version.

`hyprctl-live` resolves a signature via `hyprctl instances -j` on each call;
it picks the first discovered instance. This avoids stale
`HYPRLAND_INSTANCE_SIGNATURE` values in long-lived shells. The display CLI
wraps all its Hyprland calls through it, as do the lid helpers. DPMS, screenshot,
and keyboard helpers still use bare `hyprctl` and expect a current session environment.

## Focus and Groups

The configured layout is dwindle. `bindings.lua` owns split direction,
whole-group moves, group membership moves, and tab reordering; these are
separate operations and must retain their distinct bindings.

`focus_or_group` gives `Super+left/right` one action per press: focus a tile
outside a multi-window group, cycle an interior tab, leave an edge tab for a
same-row neighboring tile, or wrap within the group when no such tile exists.
Neighbor detection is geometric and workspace-scoped. Do not replace it with
a trial focus dispatch: empty-direction focus can select an off-axis window.
`binds.window_direction_monitor_fallback=false` confines directional focus to
the monitor. Cross-group vertical focus is on `Super+Ctrl+arrows`.

A chord i3 also binds does the same job here, and `tests/test_bindings.lua` holds
the list. The exceptions have no direct equivalent: `Super+F` maximizes and
`Super+Shift+F` fullscreens, and the `Super+-` scratchpad is a special workspace
that shows all its windows at once, tiled.

Use Lua callbacks for short compositor-event logic that reads live compositor
state. Keep blocking waits, external tool orchestration, and cross-session
logic in scripts. Chat layout waits must not block a Lua event callback.

## Bar Contracts

`shell.qml` creates one top bar per screen. Portrait screens use compact
content; the system widget cluster belongs on landscape bars, and a `Loader`
builds it only there, because hidden widgets would still run their polls. State
that several bars show lives in a root `pragma Singleton` file, so it is read,
and acted on, once: `NetProfileState.qml` and `DndState.qml`, each also one IPC
target, and `Connectivity.qml`, which sends one notification. `Theme.qml`
owns typography and colors. Keep the existing square, opaque, restrained
styling and immediate interactions. `Popout.qml` supplies anchoring, screen
clamping, and click-outside dismissal through `HyprlandFocusGrab`.

Keep `//@ pragma UseQApplication` in the shell root for tray platform menus.
Tray left-click uses `activate`, middle-click `secondaryActivate`, and
right-click `display(window, x, y)`; menu-only items also open on left-click.
Use `qs list` to inspect instances and `qs kill` followed by
`qs -p ~/.config/quickshell` (`Super+Shift+P`) to restart; QML edits need this,
because the running bar did not pick them up by itself. Broad `pkill -f`
patterns can match the invoking shell or fail to match Quickshell's re-exec.

Window titles are filtered per monitor. At startup, and after each Hyprland raw
event that opens, closes or moves windows, or changes workspaces, monitors or
fullscreen, `shell.qml` refreshes monitors, workspaces and toplevels, coalescing a
burst over 50 ms. Windows that predate the bar and moved workspaces therefore get
fresh associations. Workspace urgency uses `HyprlandWorkspace.urgent`;
focused appearance takes priority. Inspect both landscape and portrait bars
when changing widget widths or pools.

Where workspaces are per monitor ([Displays](displays.md#workspace-contract)),
each bar's `Workspaces.qml` shows its monitor's slots 1-10, then any workspace
from another block on that monitor, after a gap. The `MonitorBlocks.qml`
singleton reads which block each connector owns from Hyprland's state file.
`FileView` misses a file created after it loaded, so the singleton also rereads
the file 300 ms after a config reload or a monitor change. The slot a monitor
shows is filled with the accent while that monitor has focus, and outlined
otherwise. A click on a slot runs `workspaces.focus(slot, "OUTPUT")`; on the
slot already shown it only focuses the monitor, since a workspace focus there
would bounce back. A monitor without a block falls back to `shell.qml`'s pools.

`Pulseaudio.qml` holds an `AudioControl` each for speaker and mic, matching
Polybar: scroll changes volume on whole wheel notches, left-click mutes, right-click
opens pavucontrol, and middle-click on the mic switches input. Actions run `wpctl`.
Volume and mute come from Quickshell's PipeWire service as they change, matching
`wpctl get-volume`'s scale. A virtual default device has no typed audio there, so
while one is a default the widget polls `wpctl` every two seconds instead. The mic
turns `Theme.accent` while an unmuted capture stream exists. `Dnd.qml` shows a
bell-off glyph only while mako's `do-not-disturb` mode is on. A click or
`Super+Ctrl+Alt+Comma` toggles it, and `DndState` rereads `makoctl mode` at start
and on `qs ipc call dnd refresh`. Mako still shows critical notifications in that
mode. `Submap.qml` shows the active submap on
every bar from the `submap` raw event, because every other bind is dead inside one.
`NetProfile.qml`, and `Network.qml` with its `Connectivity.qml` singleton, are covered
in [Network profiles](network-profiles.md#captive-portals).

Weather reads machine-local `~/.config/quickshell/weather-location.json`
(`name`, `lat`, `lon`) at startup, falling back to its configured coordinates.
It polls Open-Meteo every 20 minutes for Fahrenheit current conditions and a
four-day forecast. The file is not supplied by the tracked config. Automatic
travel-location discovery is not implemented. Widgets without suitable
hardware, such as laptop CMOS monitoring, hide when their input is absent.
`WeatherGlyph.js` maps WMO codes to glyphs for Weather and the world clock.

Left-click on the clock opens the calendar; right-click opens the world clock, one
row per city with its weather, local time, hours from here and date. The cities are
the tracked `world-clock.json`, shared by both machines, in Omarchy Elsewhen's
`cities` shape: `{ "name", "zone" }` plus `lat` and `lon`, which its weather needs.
Edits show without a restart; an unreadable file shows its error in the popout.
`WorldClock.qml` holds the data once for every bar. While a world clock is open it
runs a `date` probe for the zones' offsets on opening and every five minutes, and
one Open-Meteo request for every city's weather, kept 20 minutes; nothing runs
while closed. The probe and row formatting are Elsewhen's `Model.js`, vendored
under `vendor/elsewhen/` from Omarchy 43c08a499 with its MIT license. Its one
local edit reads the local zone from `/etc/localtime` instead of systemd's
`timedatectl`; to re-sync, copy upstream's file and reapply that edit.

## Capture and Sleep

`Print` opens Flameshot. With `m.screenshot == 'tensaku'`, `Super+Print`
captures/annotates a region, `Shift+Print` captures/annotates the active monitor,
`Ctrl+Print` copies a region, and `Super+Ctrl+Print` annotates the clipboard.

`screenshot` uses grim, slurp, and wl-clipboard, saving under
`${XDG_PICTURES_DIR:-$HOME/Pictures}`. Region selection can freeze with
hyprpicker. `full` falls back to all outputs if active-monitor lookup fails.
`--annotate` uses `tensaku-edit` if present; clipboard mode requires it.
`screenshot.sh` is a separate hyprshot/satty pipeline, not a Flameshot wrapper.
`flameshot.sh` sets `QT_SCREEN_SCALE_FACTORS` for Flameshot.

Flameshot's Wayland and X11 settings are copied onto `flameshot.ini` at session
startup. Qt's config rewrites can replace a symlink, so the active file is
intentionally copied. Stable variant names may themselves be symlinks.
Check the session portal backends and stale portal processes for screenshot
failures; X11 uses its legacy capture path.

`hypr-dpms-all on|off` enumerates monitors and dispatches the table form
`hl.dsp.dpms({ monitor = ..., action = 'on'|'off' })` for each. Hypridle calls
this helper and uses elogind's `loginctl` for suspend. Do not substitute a
single string-form DPMS call when changing multi-monitor sleep.

## Hyprland Verification

For config changes, run dotfiles' Lua tests, inspect `hyprctl-live configerrors`,
then exercise the affected behavior in the actual compositor. Check both
machine branches, reload versus startup, focus at group edges, and every
monitor when relevant. Bar checks include duplicate instances, tray menus,
portrait overlap, popout dismissal, urgency, and missing-data states. Capture
checks include cancellation, clipboard output, and annotation availability.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
