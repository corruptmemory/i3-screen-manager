# Hyprland and Quickshell

Read this guide for Lua config, session startup, focus/group behavior, bars,
screenshots, or monitor sleep. Sources here: `start-hyprland`, `hyprctl-live`,
`hypr-dpms-all`, `screenshot`, `screenshot.sh`, `flameshot.sh`. Configuration
sources are `dotfiles/.config/hypr/` and `dotfiles/.config/quickshell/`.

## Session and Configuration

The live Hyprland config directory points into dotfiles. `hyprland.lua` loads
`machine`, `vars`, `envs`, `monitors`, `looknfeel`, `rules`, `autostart`, and
`bindings`. `machine.lua` selects static capabilities by hostname; branch on
traits for hardware behavior. `HYPR_MACHINE_OVERRIDE` supports the test harness.
Keep config-load code cheap and free of startup side effects: configuration
evaluation can happen more than once on a reload. Launch daemons from
`hl.on('hyprland.start', ...)`, and keep reload-specific work in its own hook.

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
wraps all its Hyprland calls through it. DPMS, screenshot, keyboard, and lid
helpers still use bare `hyprctl` and expect a current session environment.

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

Use Lua callbacks for short compositor-event logic that reads live compositor
state. Keep blocking waits, external tool orchestration, and cross-session
logic in scripts. Chat layout waits must not block a Lua event callback.

## Bar Contracts

`shell.qml` creates one top bar per screen. Portrait screens use compact
content; the system widget cluster belongs on landscape bars. `Theme.qml`
owns typography and colors. Keep the existing square, opaque, restrained
styling and immediate interactions. `Popout.qml` supplies anchoring, screen
clamping, and click-outside dismissal through `HyprlandFocusGrab`.

Keep `//@ pragma UseQApplication` in the shell root for tray platform menus.
Tray left-click uses `activate`, middle-click `secondaryActivate`, and
right-click `display(window, x, y)`; menu-only items also open on left-click.
Use `qs list` to inspect instances and `qs kill` followed by
`qs -p ~/.config/quickshell` for a deliberate restart. Broad `pkill -f`
patterns can match the invoking shell or fail to match Quickshell's re-exec.

Window titles are filtered per monitor. `Hyprland.refreshToplevels()` runs
every three seconds so windows predating bar startup and moved workspaces
have fresh associations. Workspace urgency uses `HyprlandWorkspace.urgent`;
focused appearance takes priority. Inspect both landscape and portrait bars
when changing widget widths or pools.

Weather reads machine-local `~/.config/quickshell/weather-location.json`
(`name`, `lat`, `lon`) at startup, falling back to its configured coordinates.
It polls Open-Meteo every 20 minutes for Fahrenheit current conditions and a
four-day forecast. The file is not supplied by the tracked config. Automatic
travel-location discovery is not implemented. Widgets without suitable
hardware, such as laptop CMOS monitoring, hide when their input is absent.

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
