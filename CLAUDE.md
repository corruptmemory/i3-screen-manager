# i3-screen-manager

Shared instructions for Codex and Claude Code. `AGENTS.md` is a relative symlink
to this file; edit `CLAUDE.md` to update both.

## Scope and Ownership

This is an Artix Linux/OpenRC desktop toolkit: shell scripts, two Python usage
collectors, and their operating documentation. There is no application build.
The `i3-` command names are public interfaces used by keybindings and menus.
Display and keyboard scripts have both Hyprland/Wayland and X11 branches.

The companion `~/projects/dotfiles` repository owns desktop configuration and
Quickshell UI. Paths written as `dotfiles/...` below refer to that sibling
repository, not to a directory in this one. Read its instructions before editing
it. A change to a shared contract may need matching changes in both repositories.

| Machine | Configured role |
|---------|-----------------|
| `nomad-artix` | ThinkPad X1 Extreme Gen 5, Intel/NVIDIA graphics, dynamic docking, battery/backlight, OpenRC-managed user audio |
| `godlike-artix` | AMD desktop, fixed landscape plus portrait monitors, audio launched by the desktop session |

Both Hyprland profiles select Quickshell and enable the tensaku screenshot
bindings. X11 i3/IceWM configurations also exist. Inspect the active session,
installed tools, and resolved config paths before making machine-specific
claims; repository configuration alone does not establish runtime state.

## Working Rules

- Read the affected scripts and their consumers before changing behavior.
  Preserve command names, arguments, output formats, and machine distinctions
  unless the task calls for changing those interfaces.
- Scripts are installed through `~/.local/bin` symlinks. Rofi scripts source
  `lib/require.sh` through `~/.local/lib/sh/require.sh`; use `_require` for
  non-universal commands so missing tools produce visible diagnostics.
- Resolve symlinks before editing deployed files. Preserve machine-local
  settings and understand whether a program rewrites its own config.
- Use `hyprctl-live` for compositor queries from agent or other long-lived
  shells. Preserve a usable display when changing docking or lid behavior.
- Treat Bash pipelines and expected command failures deliberately under
  `set -euo pipefail`. Keep diagnostics on stderr where stdout is an interface.
- Retain third-party copyright and license notices in vendored code.
- Documentation describes implemented behavior, constraints, and verification.
  Update the relevant fact in place when behavior changes. Use Git for history;
  do not append migration narratives, session logs, or completed task lists.
- Give each detailed fact one primary documentation home. Keep known defects
  separate from intended behavior, and verify discrepancies against code or
  the active machine rather than preserving contradictory claims.

## Verification

Run `bash -n` on changed Bash scripts and `sh -n` on POSIX shell scripts.
Parse changed Python collectors without executing account probes merely for
syntax validation. This repository has no automated runtime test suite.
Use focused behavioral checks described in the relevant section below; report
which live checks were actually performed.

Display commands, compositor reloads, bar restarts, package installs, and the
VM setup script affect the running machine. A documentation-only change needs
documentation checks, not a live desktop reconfiguration. The separate
`dotfiles/.config/hypr/tests/run.sh` exercises Lua configuration with a stub;
it does not establish real multi-monitor behavior.

## Displays

Load this section for layout, docking, scaling, lid handling, monitor discovery,
or workspace-placement changes. Sources: `i3-screen-manager`, `i3-screen-rofi`,
`laptop-monitor.sh`, `laptop-monitor-x11.sh`, `hyprland-clamshell-restore`, and
dotfiles' `hypr/monitors.lua`, `hypr/machine.lua`, `hypr/autostart.lua`, and
`quickshell/shell.qml` under `.config/`.

### Backend and Scope

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

### Layout and Scaling

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

### Transition Constraints

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

### Workspace Contract

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

### Known Limitations

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

### Display Verification

With the relevant session and an external monitor available, check all four
extend directions, mirror, clamshell, the closed-lid disconnect refusal,
open-lid restoration, focused and explicit-output scaling, and status output.
Check transitions from clamshell as well as from a normal extended layout.
Inspect monitor state and visible output after every operation. On Hyprland,
also check workspace pools, config reload, physical unplug/replug, and hot-plug
at startup. On X11, check PRIME discovery and newly launched apps after DPI
changes. Do not claim these hardware checks passed based on syntax checks.

## Hyprland and Quickshell

Load this section for Lua config, session startup, focus/group behavior, bars,
screenshots, or monitor sleep. Sources here: `start-hyprland`, `hyprctl-live`,
`hypr-dpms-all`, `screenshot`, `screenshot.sh`, `flameshot.sh`. Configuration
sources are `dotfiles/.config/hypr/` and `dotfiles/.config/quickshell/`.

### Session and Configuration

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

### Focus and Groups

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

### Bar Contracts

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

### Capture and Sleep

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

### Hyprland Verification

For config changes, run dotfiles' Lua tests, inspect `hyprctl-live configerrors`,
then exercise the affected behavior in the actual compositor. Check both
machine branches, reload versus startup, focus at group edges, and every
monitor when relevant. Bar checks include duplicate instances, tray menus,
portrait overlap, popout dismissal, urgency, and missing-data states. Capture
checks include cancellation, clipboard output, and annotation availability.

## X11 and Input

Load this section for i3/IceWM, X11 window identity, keyboard/mouse settings,
rofi dependencies, or clipboard typing. Sources here: `i3-keyboard-rofi`,
`i3-mouse-setup`, `i3-mouse-rofi`, `keybase-popup-anchor-x11`, and `lib/require.sh`.
Desktop configs and X11 launchers live in dotfiles.

### X11 Configuration

Dotfiles has `start-i3`, `start-i3-laptop`, `start-icewm`, and
`start-icewm-laptop` under `.local/bin`, with corresponding `.xinitrc-*` files.
For i3, `.config/i3/config` selects `config-desktop` or `config-laptop`;
Polybar has matching configs and launchers. IceWM uses `.icewm/` on desktop
and `ICEWM_PRIVCFG` for `.icewm-laptop/`. Resolve live symlinks before edits.

i3's desktop config pins workspaces 1-6 to `DP-2` and 7-10 to `HDMI-1`.
The laptop does not use fixed external-output pins. X11 screen layout belongs
in the session setup or display CLI. IceWM's desktops are global; its native
taskbar does not implement independent per-monitor workspaces.

In the configured i3 setup, `exec` runs at session startup and `exec_always`
also runs on an i3 restart; a config reload does not rerun them. Use startup
for long-running daemons and retain single-instance guards on restart hooks.
Validate config with `i3 -C -c PATH`. Live behavior requires the real session;
a single-screen nested X server cannot verify physical multi-monitor layout.

### Keyboard, Mouse, and Clipboard

`i3-keyboard-rofi` toggles `ctrl:nocaps,shift:both_capslock_cancel` versus no
keyboard options. X11 clears options through `setxkbmap -option` before
applying the chosen set. Its Wayland branch still uses legacy `hyprctl
getoption`/`keyword` and needs Lua-mode work; do not describe that branch as
fully compatible with the current config.

Mouse DPI uses solaar at the HID level on either backend. `i3-mouse-setup`
defaults to 1200 and restores the saved value; the menu offers 800-2000.
Mouse identity and DPI are stored under `~/.config/i3-mouse-manager/`.
The login helper quietly skips unavailable hardware; the menu reports a
missing solaar installation or an undetected mouse. Inspect whether `usbhid`
is built into the running kernel before using modprobe configuration for poll
rate; built-in driver parameters belong in the kernel command line.

All four `i3-*-rofi` menus source `~/.local/lib/sh/require.sh`. Keep its symlink
to this repo's `lib/require.sh` installed. `_require` checks commands and
reports failures on stderr and through `notify-send` when available. Put
dependency checks before pipelines whose failure could make a menu disappear.

The dotfiles emoji picker uses wl-copy on Wayland and xclip on X11; rofi's
selection and the clipboard tool both need to be present. `Super+period` is
the Hyprland emoji binding; its float toggle occupies `Super+Ctrl+Space`.
Check keysyms case-insensitively when looking for duplicate Hyprland binds.

Bitwarden lookup is provided by external `rbw`/`rofi-rbw`. Hyprland launches
`rofi-rbw --typer ydotool`; `ydotoold` must be running with `/dev/uinput`
access and a matching runtime socket. Check the actual user ACL before adding
device rules. X11 uses xdotool with a plain rofi-rbw binding. Keep typing tests
to non-secret sample text. An unavailable clipboard owner can block X11 paste;
inspect the configured clipboard manager and the owning app before blaming
the consumer.

### Keybase Popup and Application Identity

`keybase-popup-anchor-x11` subscribes to i3 window events. It matches a small
floating Keybase window by class, size, and floating state, then positions it
below the bar on the output containing it. The main window can share the
popup's title during startup; a title-only rule is not sufficient.
`BAR` defaults to 28 and `POPUP_MAX_W` to 1000; the laptop launcher supplies
its bar height. Preserve the `flock` guard and test main-window startup as
well as popup opening.

Hyprland handles the Keybase popup in dotfiles' `autostart.lua`: its
`window.open` callback moves the cursor to the popup's center. Moving the
Wayland popup itself can dismiss it. Keep this backend-specific behavior.

Brave Origin's X11 main class is `Brave-origin`; helper windows can use other
classes. Its X11 PWAs share that class and use `crx_<app-id>` instances.
Wayland PWA classes include the app ID and profile. Electron main and helper
windows can differ in capitalization. Inspect `xprop` or `hyprctl-live clients
-j` and match the intended window, including its size/role when needed.

### X11 and Input Verification

Check the relevant WM config, missing-tool notification, picker cancellation,
both keyboard modes, saved DPI restoration, and clipboard contents. For the
Keybase watcher, test each monitor's tray, opening the main app, i3 restart,
and duplicate-process prevention. Claims about X11 limitations must be checked
against the installed XLibre implementation and application backend; avoid
generalizing from another server version or an app's missing integration.

## Agent Usage

Load this section for the Python collectors, their caches, JSON output, or the
agent widget. Sources: `agent-usage`, `agent-usage-claude`,
`agent-usage-codex`, and dotfiles' `Widgets/Agents.qml` and `AgentsPanel.qml`
under `.config/quickshell/`.

### Collection and Storage

The collectors are vendored from `basecamp/omarchy` (MIT); retain attribution.
They use Python's standard library and print one JSON record each. The Bash
orchestrator resolves sibling collectors with `readlink -f`, runs them in
parallel, checks successful stdout with jq, and prints an array in
Claude/Codex order. A failed collector is omitted; both failing produces `[]`.
Success here means parseable JSON, not schema validation.

Successful records are atomically cached to
`${XDG_STATE_HOME:-$HOME/.local/state}/agent-usage/{claude,codex}.json`.
Failures do not remove previous records. Collector caches live beneath
`${XDG_CACHE_HOME:-$HOME/.cache}/agent-usage/`. A retained file is not proof
of a fresh measurement. Agent credentials/transcripts are inputs; cache/state
files are outputs. Do not expose credentials in JSON, logs, or tests.

Claude reads `CLAUDE_CONFIG_DIR` (default `~/.claude`), project transcripts,
aggregate/history fallbacks, and supported pi/omp/opencode usage. Limits come
from its OAuth usage endpoint using the existing login. The collector does
not refresh that login. It can reuse cached limits on failure, excluding
windows whose reset time has passed; transport failures can set `retryAdvised`.

Codex scans `CODEX_HOME` (default `~/.codex`) session and archived-session
JSONL plus supported pi/omp/opencode sources. Limits are read via a temporary
`codex app-server` subprocess using `initialize`, `account/read`, and
`account/rateLimits/read`. The collector reads primary and secondary limit
windows; do not assume it implements every shape a newer server might expose.
The subprocess is terminated after the query. Scanner support is limited to
the formats the code parses; a new CLI storage format needs verification.

Normal local-scan reuse is 20 seconds; `--limits-only` permits reuse for 900
seconds. `--force` bypasses that reuse. Claude also throttles successful limit
probes over a 15-second interval unless forced; Codex probes limits each run.
Preserve date-sensitive caches, file locking, and token accounting when
changing these paths. In native Codex usage, cached input is already included
in input totals and reasoning is included in output; do not count either twice.

### JSON Contract

| Field | Meaning |
|-------|---------|
| `schemaVersion` | Integer `1` |
| `id`, `name`, `updatedAt` | Agent identifier, display name, UTC timestamp |
| `ready`, `hasLocalStats` | Booleans used by consumers; readiness is not an authentication guarantee |
| `tierLabel`, `usageStatusText`, `authHelpText` | Plan/status/help strings |
| `limits` | Array with `label`, `percent`, `resetsAt`, and optional `title` |
| `todayPrompts`, `todaySessions`, `todayTotalTokens` | Today's integer counters |
| `todayTokensByModel` | Object mapping model names to token totals |
| `modelUsage` | Object keyed by model, with `inputTokens`, `outputTokens`, `cacheCreationInputTokens`, `cacheReadInputTokens` |
| `recentDays` | Array of `{date, messageCount}`; `messageCount` contains token totals |
| `totalPrompts`, `totalSessions`, `activeDays` | Aggregate counters |
| `retryAdvised` | Optional retry hint; not acted on by the current widget |

`limits[].percent` is a fraction, not an integer percentage. Consumers multiply
by 100 for labels and clamp meter fill. `resetsAt` is a timestamp or an empty
string. `modelUsage` is an object, not an array; per-model totals sum its four
token fields. Do not hardcode plan names, model names, or a fixed number of
limit windows.

### UI and Known Limitations

`Agents.qml` starts a collection at bar startup and every 600000 ms. It reads
stdout, not the saved record files. A malformed result leaves its prior UI
state; an array replaces it. The widget filters on `ready`, displays the
highest limit, and uses warning/critical thresholds of 0.75/0.9. Its panel
shows agent limits, reset countdowns, today counters, and the top four models.

Readiness differs between collectors: Claude requires prompts or limits;
Codex currently sets `ready=true` even when its limit probe fails. An
unauthenticated Codex record may therefore keep the bar item visible.
The current QML has no manual refresh control and no fast retry for
`retryAdvised`; do not document either as available. Antigravity has no
collector in this repo. Account limits describe account usage; local token
statistics only cover the sources available on this machine.

### Agent-Usage Verification

Check each record and the merged array with jq; verify schema types, empty
data, absent tools/auth, expired reset windows, failures retaining old cache
files, and simultaneous invocations. Use isolated cache/state directories and
fixtures for automated checks. Verify fractional meters and model totals
against the records in the actual widget when changing its contract. Syntax
checks alone do not verify remote account limits or UI rendering.

## System Maintenance

Load this section for hardware, OpenRC services, the Tailscale helper, CMOS
monitoring, or VM setup. Sources: `start-hyprland`, `i3-tailscale-rofi`,
`i3-cmos-battery`, `volumecontrol.sh`, and `win11-vm-setup.sh`. Check active
machine state before applying configuration outside this repository.

### Service and GPU Boundaries

Use OpenRC service tools on these machines and elogind's `loginctl` for session
operations. The user D-Bus socket is `/run/user/<uid>/bus`; launchers export
its address. Gnome-keyring owns secrets/PKCS#11; a separate OpenSSH agent uses
`$XDG_RUNTIME_DIR/ssh-agent.sock`. Check whether that agent is live and whether
keys are loaded separately. Keep desktop-session and laptop-user-service
ownership of PipeWire distinct.

The laptop launcher uses stable DRM PCI paths for Intel `0000:00:02.0` and
NVIDIA `0000:01:00.0`. Hybrid mode lists Intel first in `AQ_DRM_DEVICES`, then
NVIDIA for the external ports; discrete mode selects NVIDIA alone. Only the
discrete branch forces `GBM_BACKEND=nvidia-drm` and NVIDIA GLX. Hybrid uses
Intel VA-API (`iHD`). Do not apply these laptop-specific paths or driver
overrides to the AMD desktop launcher in dotfiles.

The laptop firmware supports Hybrid and Discrete graphics modes. Changing
that mode requires a reboot and changes GPU availability and power use.
For poor external rendering, inspect actual GPU routing, DRM modeset state,
and frame behavior before adjusting compositor settings. A historical symptom
does not establish the current driver stack's performance.

`volumecontrol.sh` forces the Intel Vulkan ICD for pavucontrol. Treat this as
a hardware-specific wrapper rather than a universal audio requirement.

### CMOS Monitoring

`i3-cmos-battery` reads an it87-family `Vbat` hwmon input in millivolts.
Thresholds are OK at >=2800, LOW at 2500-2799, and DEAD below 2500. No sensor
produces no output. `polybar` is the default output and emits markup;
`quickshell` emits `<volts> <status>`; `cli`/`--cli` emits a report. Polling is
owned by the bar. Keep thresholds and output shapes shared between consumers.

### Tailscale and Open Brain

`i3-tailscale-rofi` controls the local daemon and rewrites only the Open Brain
URL in `~/.claude.json`. It does not update Codex's MCP configuration. Its LAN
URL, tailnet endpoint, and `tailscale up --hostname=nomad-artix
--accept-dns=false` arguments are machine-specific. Read them before adapting
the script. Open Brain must be reachable on its configured interface/port.
The menu also supports login and a manual URL toggle. Preserve other JSON
fields and avoid logging authentication headers while investigating failures.

### VM Setup

`win11-vm-setup.sh` is a privileged host-setup program for QEMU/KVM and libvirt,
run as the normal user with sudo available. It checks AMD `svm` and `/dev/kvm`,
installs packages, configures libvirt group access, enables OpenRC services,
starts NAT networking, creates the `vms` pool at `/data/vms`, and optionally
downloads virtio drivers. On btrfs it applies nodatacow to the image directory.
Group changes require a fresh login. It may restart services on a rerun.

Its AMD preflight, storage path, and libvirt `auth_unix_rw=none` choice must be
reviewed before use on another host. It does not create or install the Windows
guest. Do not run it as a documentation or syntax check.

For a guest, use the system libvirt connection, select UEFI/Secure Boot and a
TPM 2.0 device, allocate suitable memory/CPU and disk in the intended pool,
and supply the Windows installation ISO. A virtio disk needs its matching
Windows driver; SATA avoids that installation-time dependency. Install Garmin
Express in Windows and attach the device via USB Host Device or the console's
USB-redirection control. USB-device passthrough is distinct from PCI/VFIO
passthrough. Check `virsh list --all`, `net-list --all`, and `pool-list --all`
for actual host/guest state instead of relying on an old completion checklist.

### System Verification

Use read-only configuration, package, service, device, and connection queries
first. Verify both the intended state and user-visible behavior after a system
change. Check absent-sensor output, Tailscale failure/auth paths, and the
actual VM storage and service state when their respective tools change.

## Applications

Load this section for Ghostty/Brave identity and config deployment, chat layout,
GTK dialogs, or application-specific desktop integration. Sources are chiefly
dotfiles' launchers, `.desktop` overrides, WM rules, and terminal configs.

### Configuration and Window Identity

Resolve `~/.config/ghostty`, `~/.config/kitty`, and browser launcher paths on the
machine before editing. Shared files in dotfiles and live copies can differ.
Ghostty is the configured default terminal. Validate its parsed settings with
`ghostty +show-config`; keep comments on their own lines. Use a valid dotted
application ID with `--class` for Wayland rules and the configured
`--x11-instance-name` for X11 rules. Inspect user `.desktop` overrides when
single-instance or D-Bus activation changes window placement.

Brave Origin's profile directories are machine-local. `machine.lua` supplies
the alternate-profile directory to Hyprland launchers; do not assume identical
`Profile N` slots across hosts. Browser/PWA flags are determined by the first
process using the profile. If remote-debugging flags are required, launching
a PWA first without them can prevent a later browser command from applying
them. Inspect the running command and local launcher before changing flags.

Native-messaging host manifests and MIME associations are local integration
points. Recheck their paths when changing browser packages or profiles. For
broken Gmail link navigation, inspect the new tab's request chain: a redirect
into an extension resource indicates a different problem from a blocked
request or a window-manager focus rule. Fix a request-matching extension rule
at the affected request domain rather than assuming the originating tab's
domain is the relevant setting.

### Chat Layout

Dotfiles' `i3-chat-launch` selects the session-specific builder. The i3 path
uses `append_layout` and swallow criteria; its rebuild helper can close and
relaunch the chat windows. The Hyprland builder `hypr-chat-layout` launches
missing apps, selects their primary windows, parks targets on a special
workspace, and serially forms Messages/WhatsApp and Discord/Keybase/Slack
groups on workspace 10. Group order and group locking are part of the
algorithm; app startup and largest-window selection handle transient helpers.
Rerunning rebuilds the grouping of existing windows. It can visibly move
windows and must remain a shell workflow because it waits for mapping.

The desktop has the chat builder integration. Shared Hyprland rules place
chat apps on workspace 10 on the laptop, but do not infer an automatic laptop
chat-wall build. Consult the actual autostart entries; a provided helper is
not necessarily enabled at login. Verify repeat invocation, missing apps,
main-window selection, tab order, and focus restoration after builder changes.

### GTK File Dialogs

For slow file dialogs, compare `gio info trash:///` with the same query under
`GIO_USE_VFS=local`. A GVfs trash-backend timeout can delay dialog construction.
The local VFS setting bypasses GVfs backends such as trash and network shares;
place it in the intended session/app environment if that behavior is wanted.
Check package reverse dependencies before removing GVfs. Do not reproduce
package-removal commands from an assumed dependency graph.

### Application Verification

Check the resolved config, effective settings, actual window identity, and
fresh versus already-running app launches. Exercise both Wayland and X11
paths when the change affects shared launchers. Prefer non-secret fixtures
for browser, clipboard, and password-manager integration checks.

## Package Installation

Load this section before installing, updating, replacing, or removing tools,
reviewing an AUR package, or changing pacman repositories. Sources:
`aur-malware-check`, `/etc/pacman.conf`, installed package metadata, and the
vendor's current distribution instructions.

### Selection Policy

Prefer these paths in order, checking suitability for the specific tool:

1. Official packages from the machine's configured Artix/Arch repositories.
2. The vendor's own native distribution, installer, or signed binary repository.
3. An isolated language-tool installation, such as pipx for a Python CLI.
4. A vendor container image for tools suited to occasional containerized use.
5. A locally maintained PKGBUILD when pacman integration warrants its upkeep.
6. An individually reviewed AUR recipe when the other paths do not fit.

Inspect the vendor/source identity, update path, and removal path. Keep Python
tools out of system site-packages; use an owned virtual environment or pipx.
Avoid sudo-driven global npm installs for project tooling. A vendor URL or
container namespace must actually belong to the publisher; retain available
signature/checksum verification. Read installer behavior before executing it.

### Pacman and XLibre

Inspect `/etc/pacman.conf` and sync metadata before assuming a package is AUR
only. An installed foreign package can have a matching official package now;
`pacman -Qm` alone does not establish its source or trust. The Arch `extra`
overlay is configured after Artix repositories on these machines; preserve
Artix package precedence and check init-system dependencies before changing
that arrangement. Do not perform partial upgrades as an installation shortcut.

The configured XLibre vendor source is `[xlibre-stable]`, with
`https://packages.xlibre.net/arch/stable/$arch` before `[world]` and an
`IgnorePkg` entry for `xorg-server xorg-server-common`. Preserve signature
checking and verify publisher keys through current authoritative instructions
before bootstrapping trust on another machine. Query package versions, owners,
and repositories instead of recording a version inventory as enduring fact.

For a dbus reload-hook error, compare the system hook, any local override,
and `/usr/share/libalpm/scripts/openrc-hook`. A local override can shadow a
correct packaged hook. The relevant dispatcher verb is `dbus_reload`; check
the installed implementation before prescribing an override. Do not carry
completed workaround deadlines forward as active tasks.

### AUR Audit Contract

Run `aur-malware-check` before and after AUR operations as the repository's
package-maintenance convention. It defaults to installed foreign packages,
checks the Atomic-incident denylist, and can scan related filesystem and
scriptlet indicators. It is an incident-specific check, not a general guarantee
that a package is trustworthy. Review the recipe and changes independently.

Options: `--all` includes every installed package, `--deep` scans indicators,
`--near` checks similar names, `--list FILE` supplies a local list, and
`--url URL` changes the source. The tool downloads/caches the list with an
offline fallback and reports without removing packages or payload files.
Exit codes are 0 for no exposure found, 1 for exposure found, and 2 for errors.

### Package Verification

Check origin, signature policy, transaction contents, and dependency effects
before a package change, then verify installed ownership, the executable
resolved on PATH, and relevant service or desktop behavior. Validate the audit
tool with a local denylist and controlled package/indicator fixtures when
changing its matching logic; a live incident-list check is not broad test
coverage. Use current vendor documentation for native CLI installation and
authentication instead of retaining dated migration recipes here.
