# i3-screen-manager

Desktop automation scripts for **Hyprland/Wayland and X11 (i3/IceWM)** on
Artix Linux with OpenRC: display layout, scaling, input settings, session
startup, screenshots, hardware monitoring, and coding-agent usage statistics.
Rofi supplies the menus; Quickshell and Polybar consume script output.

The project began as an i3 toolkit. The `i3-` names remain because existing
keybindings and menus use them. X11 support remains in the display and keyboard
scripts alongside the Hyprland backend.

## Repository Layout

There is **no build step**. Shell scripts and two Python collectors live at the
repo root and are symlinked into `~/.local/bin/`.

| Files | Purpose |
|-------|---------|
| `i3-screen-manager`, `i3-screen-rofi` | Display CLI and rofi frontend |
| `i3-keyboard-rofi`, `i3-mouse-setup`, `i3-mouse-rofi` | Keyboard remapping and Logitech mouse DPI |
| `start-hyprland`, `hyprctl-live`, `hypr-dpms-all` | Session startup, live compositor discovery, and monitor sleep |
| `laptop-monitor.sh`, `laptop-monitor-x11.sh`, `hyprland-clamshell-restore` | Lid events and clamshell reload handling |
| `screenshot`, `screenshot.sh`, `flameshot.sh`, `volumecontrol.sh` | Capture/annotation and desktop utility wrappers |
| `i3-cmos-battery`, `keybase-popup-anchor-x11` | CMOS voltage reporting and the i3 Keybase tray-popup workaround |
| `i3-tailscale-rofi` | Tailscale control and Claude Code's Open Brain URL switch |
| `agent-usage`, `agent-usage-claude`, `agent-usage-codex` | JSON usage records for the Quickshell agent widget |
| `aur-malware-check`, `win11-vm-setup.sh` | Standalone package audit and VM setup utilities |
| `lib/require.sh` | Shared missing-command diagnostics for rofi scripts |
| `docs/`, `nvidia-problems/` | Setup runbooks, design history, research, and troubleshooting |

The companion `~/projects/dotfiles` repo owns Hyprland's Lua configuration,
i3/IceWM configs, bar UI, and most session wiring. In particular,
`~/.config/hypr` and `~/.config/quickshell` are directory symlinks into dotfiles.
This repo provides the scripts used by those configs; installing the scripts
alone does not install a desktop configuration.

## Modes

`i3-screen-manager <command>`:

| Command | What it does |
|---------|-------------|
| `extend-left/right/above/below` | External monitor positioned relative to the internal panel |
| `clamshell` | External only, internal (`eDP-1`) off, lid-close safe |
| `mirror` | Mirror the internal panel on Wayland; use `xrandr --same-as` on X11, with each output's preferred mode |
| `disconnect` | Revert to the internal panel only |
| `scale [VALUE] [OUTPUT]` | Wayland output scale or X11 `Xft.dpi`; rofi picker if no value (presets `0.75`-`2.00`) |
| `dpi [VALUE] [OUTPUT]` | Alias for `scale`, retained for the desktop binding |
| `status` | Show detected outputs, monitor geometry (plus scale on Wayland), and inhibitor state |
| `apply-ws-split` | Wayland only: move workspaces 7-10 to the detected external; no-op if none is attached |

Backend selection uses `XDG_SESSION_TYPE=wayland` or a nonempty
`WAYLAND_DISPLAY`; otherwise the script uses X11. The display workflow assumes
an internal panel named **`eDP-1` and one external monitor**, selected as the
first connected non-internal output. It is a laptop-docking tool, not an
arbitrary multi-monitor layout editor.

## Requirements

Use the dependencies for the features you install. The scripts assume Linux,
Bash, GNU core utilities, `grep`, `sed`, and GNU awk (`gawk`).

| Feature | Additional requirements |
|---------|-------------------------|
| Hyprland displays | Hyprland with Lua config (the 0.55+ setup documented here), `hyprctl`, `wlr-randr`, `jq`, installed `hyprctl-live` wrapper |
| X11 displays and scaling | An X11 session, `xrandr`, `xrdb` |
| Rofi menus | `rofi`, installed `lib/require.sh`; `notify-send` for notifications |
| Clamshell | `elogind-inhibit` and a readable lid state under `/proc/acpi/button/lid/` |
| Keyboard / mouse | `hyprctl` on Wayland or `setxkbmap` on X11; `solaar` for Logitech DPI |
| Session launcher | `gnome-keyring-daemon`, OpenSSH agent tools, `/usr/bin/start-hyprland`, Artix/OpenRC session setup |
| Screenshots | `grim`, `slurp`, `wl-clipboard`, `hyprctl`, `jq`; optional `hyprpicker` for frozen selection and `tensaku-edit` for annotation |
| Older utility wrappers | `flameshot` or `pavucontrol`, as applicable |
| Tailscale menu | `tailscale`, `jq`, Python 3, `curl`, `xdg-open`, configured `~/.claude.json` |
| Agent usage | Python 3.10+, `jq`, and the relevant agent login; Codex limits require the `codex` executable |
| CMOS monitoring | An it87 Vbat sensor |
| Keybase popup on i3 | `i3-msg`, `jq`, `flock` |
| AUR audit | `pacman`, `curl` (or a local denylist with `--list`) |

Quickshell is needed for the current Wayland bar widgets, and Polybar for the
X11 bar integration. Neither is required to use the display CLI. See the
[Lua migration notes](docs/hyprland-lua-migration.md) for compositor setup.

## Installation

Run from the repo root. Install the shared helper as well as the display and
input scripts; the rofi menus source it by its installed path:

```bash
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/sh"
ln -sfn "$(pwd)/lib/require.sh" "$HOME/.local/lib/sh/require.sh"

for script in i3-screen-manager i3-screen-rofi hyprctl-live \
    i3-keyboard-rofi i3-mouse-setup i3-mouse-rofi i3-cmos-battery; do
    ln -sfn "$(pwd)/$script" "$HOME/.local/bin/$script"
done
```

Ensure `~/.local/bin` is on the desktop session's `PATH`. Install optional
Hyprland helpers and agent collectors using the same convention:

```bash
for script in start-hyprland hypr-dpms-all hyprland-clamshell-restore \
    laptop-monitor.sh screenshot agent-usage agent-usage-claude agent-usage-codex; do
    ln -sfn "$(pwd)/$script" "$HOME/.local/bin/$script"
done
```

Other utilities in the inventory can be symlinked individually. Review the
machine-specific Tailscale and VM settings below before using those utilities.
The `start-hyprland` wrapper is a session launcher to run from a TTY; it is not
an autostart command to run inside an existing compositor.

The existing dotfiles already supply display keybindings. For a separate Lua
configuration, equivalent bindings are:

```lua
hl.bind("SUPER + BackSpace", hl.dsp.exec_cmd("i3-screen-rofi"))
hl.bind("SUPER + CONTROL + BackSpace", hl.dsp.exec_cmd("i3-keyboard-rofi"))
hl.bind("SUPER + ALT + BackSpace", hl.dsp.exec_cmd("i3-screen-manager scale"))
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd("i3-mouse-rofi"))

-- Optional login-time mouse DPI restore.
hl.on("hyprland.start", function() hl.exec_cmd("i3-mouse-setup") end)
```

Reload with `hyprctl-live reload`. The wrapper resolves the current compositor
instance, including from terminals or agent shells that outlived a Hyprland
restart. For i3, equivalent bindings use `bindsym`:

```i3
bindsym $mod+BackSpace exec --no-startup-id i3-screen-rofi
bindsym $mod+Control+BackSpace exec --no-startup-id i3-keyboard-rofi
bindsym $mod+Mod1+BackSpace exec --no-startup-id i3-screen-manager scale
```

`nomad-artix` uses dynamic laptop docking. `godlike-artix` is an AMD desktop
with a fixed dual-monitor layout, including a portrait display; its layout and
workspace assignments live in dotfiles' `machine.lua` and `monitors.lua`.
The shared scale binding works on the desktop, but the laptop layout commands
assume `eDP-1` and are not its monitor configuration mechanism.

## Usage

Common bindings (availability depends on the session config and installed tools):

| Keybinding | Action |
|---|---|
| `Super+Backspace` | Display management menu (`i3-screen-rofi`) |
| `Super+Ctrl+Backspace` | Keyboard layout toggle |
| `Super+Alt+Backspace` | Scale picker (`scale`, or its desktop alias `dpi`) |
| `Super+Alt+M` | Mouse DPI picker, where installed |
| `Super+Shift+B` | Bitwarden lookup (`rofi-rbw --typer ydotool` under Hyprland) |
| `Super+Shift+N` | Tailscale and Open Brain URL menu (laptop binding) |

Via CLI:

```bash
i3-screen-manager extend-right
i3-screen-manager clamshell
i3-screen-manager mirror
i3-screen-manager scale              # focused Wayland output, or X11 font DPI
i3-screen-manager scale 1.5 eDP-1     # direct Wayland output selection
i3-screen-manager dpi 1.25           # scale alias; 120 DPI on X11
i3-screen-manager disconnect
i3-screen-manager status
```

## Hybrid Graphics (laptop)

The ThinkPad is Intel Iris Xe + NVIDIA RTX 3050 Ti. Under Wayland the GPUs are
selected via `AQ_DRM_DEVICES` in `start-hyprland`: Intel (`eDP-1`) is the
compositor GPU listed first, NVIDIA is included so the external ports (all wired
through NVIDIA) light up. The launcher also handles the laptop's discrete-only
BIOS mode. These PCI paths and driver choices are hardware-specific.

On X11, the display script attempts the NVIDIA PRIME provider hookup before
external-output detection. Output names differ between X11 and Wayland, so the
script discovers the connected external rather than assuming an HDMI/DP name.
See [NVIDIA hybrid notes](docs/nvidia-hybrid-gpu.md) and the
[X11 laptop setup](docs/2026-06-17-icewm-laptop-setup.md).

## Output Scaling

On Wayland, `scale` applies `hl.monitor({...})` through `hyprctl-live dispatch`,
using the Lua configuration API rather than the old `hyprctl keyword monitor`
syntax. With no output argument it targets the focused monitor, falling back
to `eDP-1`. The picker offers `0.75 / 1.00 / 1.25 / 1.50 / 1.75 / 2.00`;
`scale 1.5 eDP-1` bypasses the picker. The current implementation also reapplies
the preferred mode and automatic output position when changing scale.

Script defaults: internal `eDP-1` at scale **1.25**, external outputs at **1.0**.
`clamshell`, `extend-*`, and `mirror` apply those automatically.

On X11, this command sets the session-wide **`Xft.dpi = VALUE * 96`** through
`xrdb -merge`. It is font/toolkit DPI, not per-output framebuffer scaling;
the output argument has no effect. Relaunch apps to pick up the change.
These commands change runtime state; persistent monitor defaults belong in
the session configuration.

## Workspace Split and Clamshell

Under Hyprland, laptop extend mode moves workspaces **7-10 to the external**;
the configured internal pool is **1-6**. Clamshell moves all existing workspaces
to the external, and disconnect moves them back from that output to the internal.
The X11 backend changes display geometry without applying this workspace split.

The laptop dotfiles declare persistent workspaces 1-10 on `eDP-1` and invoke
`apply-ws-split` on `monitor.added`, with a delayed startup fallback. The script
does not install these hooks or workspace rules. Keep `EXTERNAL_WORKSPACES` in
this repo aligned with dotfiles' `machine.lua` and Quickshell's workspace pools.
See the [workspace split and disconnect runbook](docs/2026-08-31-hyprland-workspace-split-and-disconnect-fix.md).

Clamshell holds an `elogind-inhibit handle-lid-switch` block using a background
process tracked in `/tmp/i3-screen-manager-inhibit.pid`. `disconnect` refuses
when the lid is closed **or its state cannot be read**; open the lid before
returning to the internal panel. On Wayland, disconnect explicitly re-enables
the internal panel and moves workspaces before disabling the external.

The Hyprland dotfiles call `hyprland-clamshell-restore` on `config.reloaded`.
`laptop-monitor.sh` supplies lid-event handling; its X11 sibling
`laptop-monitor-x11.sh` is available but has no automatic acpid wiring.
See the compatibility notes below for remaining legacy Hyprland calls.

## Mouse DPI Management

For Logitech mice on Bolt/Unifying receivers, `solaar` sets hardware DPI.

- **On login:** run `i3-mouse-setup` from session startup (Lua example above); it
  auto-detects the mouse and applies the saved DPI.
- **On the fly:** bind `i3-mouse-rofi` (e.g. `Super+Alt+M`) for a rofi picker of
  common presets (800–2000).
- **Persistence:** the choice is saved to `~/.config/i3-mouse-manager/dpi` and
  reapplied on the next login.

The login helper exits silently when no compatible mouse is found. The rofi
picker instead displays an error for missing `solaar` or an undetected mouse.

## CMOS Battery Monitoring

`i3-cmos-battery` reads the motherboard CMOS battery voltage via the it87 Super
I/O chip and reports health.

- **Quickshell:** `i3-cmos-battery quickshell` emits `<volts> <status>` for
  `Widgets/CmosBattery.qml` in dotfiles
- **Polybar:** `i3-cmos-battery polybar` (also the default) emits Polybar markup
- **CLI:** `i3-cmos-battery cli` for a human-readable report with warnings
- **Thresholds:** OK (>= 2.8V), LOW/yellow (2.5–2.8V), DEAD/red (< 2.5V)

Requires the `it87` kernel module:

```bash
echo "it87" | sudo tee /etc/modules-load.d/it87.conf
```

On machines without the sensor (e.g. the laptop), the script produces no
output, allowing the Quickshell widget to hide. Polling intervals belong to
the bar configuration; the script performs one read per invocation.

## Screenshots and Monitor Sleep

The `screenshot` command captures Wayland images to
`${XDG_PICTURES_DIR:-$HOME/Pictures}` and copies them to the clipboard:

```bash
screenshot region
screenshot full
screenshot region --annotate
screenshot clipboard
```

Region selection uses `slurp`, optionally freezing the screen with `hyprpicker`.
`full` captures the active monitor, falling back to all outputs if it cannot
resolve one. `--annotate` opens `tensaku-edit` when available; `clipboard`
requires it and opens the clipboard image for editing. The older
`screenshot.sh` and `flameshot.sh` wrappers remain for Flameshot workflows.

`hypr-dpms-all off` and `hypr-dpms-all on` sleep or wake every active Hyprland
monitor. They are used by hypridle and handle each monitor explicitly.

## Agent Usage

`agent-usage-claude` and `agent-usage-codex` are Python collectors vendored from
`basecamp/omarchy` (MIT). They combine account rate limits with local usage
statistics, including tokens by model. They read agent data and write their own
caches; they do not modify agent credentials or transcripts.

```bash
agent-usage                  # merged JSON array
agent-usage --limits-only    # refresh limits, reuse recent local-stat scans
agent-usage --force          # bypass collector caches
agent-usage-codex            # one agent's JSON record
```

The Bash orchestrator runs both collectors concurrently and atomically stores
successful records under `${XDG_STATE_HOME:-$HOME/.local/state}/agent-usage/` as
`claude.json` and `codex.json`. Failed collectors are omitted from stdout;
`[]` means neither produced a usable JSON record. Earlier cache files can
remain after a failed collection, so their presence alone does not mean fresh data.

Collectors honor `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, and XDG cache settings.
Claude limits use the existing OAuth login; Codex limits use its app-server
RPC. Local statistics can still exist when live account limits are unavailable.
The Quickshell UI (`Widgets/Agents.qml`, `Widgets/AgentsPanel.qml`) lives in
dotfiles, polls the orchestrator, and hides until an agent is ready. After
first installing the script symlinks, restart the bar or wait for its next poll.
See the [record contract and widget design](docs/2026-09-03-agent-usage-cards-design.md).

## GTK File Dialog Fix

GTK open/save dialogs can hang ~25s because `gvfsd-trash` (the GNOME virtual
filesystem trash backend) times out on a D-Bus call every time a
FileChooserDialog builds its sidebar.

**Symptom:** "Open File"/"Save As" in any GTK app (Brave, Firefox, …) takes 25s
before the dialog appears.

**Diagnosis:**

```bash
time gio info trash:///                  # hangs ~25s if you have the bug
time GIO_USE_VFS=local gio info trash:///  # instant
```

The recorded fix on these machines was replacing Evince with Xreader and
removing `gvfs` after checking its reverse dependencies. Those package
relationships are machine state, not installation prerequisites for this repo.
`GIO_USE_VFS=local` can also be set in the session environment before launching
affected apps; it bypasses GVfs backends such as `trash://` and `network://`.
See [Common Issues](CLAUDE.md#common-issues) for the investigation.

## Tailscale + Open Brain URL toggle

`i3-tailscale-rofi` brings Tailscale up or down and, in lockstep,
rewrites the Open Brain MCP `url` in `~/.claude.json` between the home-LAN
hostname (`http://open-brain/`, only reachable on the HOME VLAN) and node-0's
Tailscale IP (reachable from anywhere on the tailnet). This is the "Option B"
explicit URL switch described in the global setup notes. Prerequisite: Open Brain
on node-0 must listen on `0.0.0.0:8000` so the tailnet IP can reach it.

This utility is machine-specific: its endpoints and
`tailscale up --hostname=nomad-artix --accept-dns=false` are hardcoded. It needs
permission to control the local Tailscale daemon. Review those values before
installing elsewhere. It updates **Claude Code's `~/.claude.json` only**, not
Codex's MCP configuration.

## Bitwarden via Rofi (rbw + rofi-rbw)

Quick password lookup from any window via rofi, powered by `rbw` (unofficial
Bitwarden CLI with a persistent agent).

**Install & configure:**

```bash
sudo pacman -S rbw rofi-rbw
rbw config set email you@example.com
rbw config set pinentry pinentry-gtk    # GTK dialog for master password
rbw register                            # enter master password
rbw unlock                              # unlock agent, sync vault
```

**Hyprland Lua keybind:**

```lua
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("rofi-rbw --typer ydotool"))
```

Wayland typing requires `ydotoold` running with access to `/dev/uinput`;
the shared dotfiles start it. X11 uses `xdotool` and a plain `rofi-rbw` binding.

- `Super+Shift+B` opens a rofi menu of your whole vault — type to filter, Enter to copy
- `rbw-agent` starts on demand and caches the unlock for 1h (`rbw config set lock_timeout <s>`)
- When the lock expires, the next call pops `pinentry-gtk`
- For fields that reject paste, `rofi-rbw --action type` types the credential (via `xdotool` on X11, `ydotool` on Wayland — the Hyprland bind explicitly passes `--typer ydotool` to bypass rofi-rbw's default `wtype` autopick, which mangles layout-dependent characters; see `docs/2026-08-29-hyprland-rofi-parity-and-ydotool.md`)

For vault management use the browser extension or web vault. **Applies to both machines.**

## Keyboard Layout Toggle

`i3-keyboard-rofi` (`Super+Ctrl+Backspace`) switches between:

| Mode | Layout |
|------|--------|
| Laptop | Caps Lock → Ctrl, both Shifts → Caps Lock |
| External | Default US layout |

The rofi menu shows the current mode and lets you switch.

## Standalone System Utilities

`aur-malware-check` compares installed packages against the 2026 Atomic AUR
incident denylist. `--deep` scans scriptlets and filesystem indicators, `--near`
reports look-alike names, `--all` includes all installed packages, and
`--list FILE` uses a local denylist. It downloads/caches its list with an offline
fallback. Exit codes are `0` (no exposure found), `1` (exposure found), and `2`
(usage/runtime error). It reports findings without removing packages or files.
See [the AUR assessment](docs/2026-08-10-aur-supply-chain-assessment.md).

`win11-vm-setup.sh` installs and configures QEMU/KVM, libvirt, OpenRC services,
and a VM storage pool for Windows 11/Garmin Express. It is a privileged setup
script run as the normal user with `sudo`, not a display utility. Its AMD-V
preflight and `/data/vms` pool are specific to the desktop; read the
[VM setup runbook](docs/2026-08-13-win11-vm-kvm-setup.md) before running it.

## Compatibility and Validation

- **Remaining legacy Hyprland calls:** `i3-keyboard-rofi`, `laptop-monitor.sh`,
  and `hyprland-clamshell-restore` still contain `hyprctl keyword` calls. The
  main display CLI uses Lua dispatch, but these helpers have not been fully
  ported. Do not assume keyboard remapping or lid-open restoration works in
  Lua mode; the lid helpers also use `wlr-randr` for their output-off path.
- **Stale compositor environment:** use `hyprctl-live` from long-lived shells.
  The display CLI uses it; the DPMS, screenshot, keyboard, and lid helpers
  still call bare `hyprctl` and expect a current session environment. The
  wrapper selects the first discovered instance if several run.
- **Missing rofi dependencies:** confirm the `~/.local/lib/sh/require.sh`
  symlink exists. `_require` reports missing commands through stderr and a
  desktop notification. New shell tools should use the same shared guard.

There is no automated test suite in this repo. Syntax checks do not exercise
compositor behavior; display changes need an external monitor and the relevant
session. The [manual checklist](CLAUDE.md#testing) covers extend, mirror,
clamshell, the closed-lid disconnect refusal, open-lid restoration, and scaling.
Also check workspace placement, hot-plug, reload handling, and both backends
when changing their code. Dotfiles' Lua configuration tests live separately in
`~/projects/dotfiles/.config/hypr/tests/`.

## Further Reading

- [Shared agent instructions and operating notes](CLAUDE.md): `AGENTS.md` is a
  relative symlink to this file, so Codex and Claude Code share one source.
- [Unified Hyprland configuration](docs/2026-08-29-hyprland-unified-config-design.md)
- [Quickshell and screenshot parity](docs/2026-08-28-quickshell-bar-and-screenshots-laptop-parity.md)
- [X11 i3 desktop setup](docs/2026-07-20-i3-x11-setup.md) and
  [laptop setup](docs/2026-07-21-i3-laptop-setup.md)
- [Install-path conventions](docs/install-paths-cheatsheet.md)

`CLAUDE.md` includes a long historical record and exceeds Codex's default
32 KiB instruction-loading budget. To load it fully, set
`project_doc_max_bytes = 98304` in your Codex user config and start a new
session; see the [AGENTS.md documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
Older dated runbooks describe the state at the time; check the current scripts
and newer notes before repeating a migration.

## License

MIT
