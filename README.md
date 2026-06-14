# i3-screen-manager

Quality-of-life scripts for **Hyprland / Wayland** on Artix — display layout,
output scaling, mouse DPI, hardware monitoring, keyboard-layout toggling, and a
couple of standalone utilities — driven from rofi menus and Waybar.

> The project began as an i3/X11 toolkit, hence the name and the `i3-` script
> prefixes. Both machines migrated to Hyprland in 2026; the names stay because
> they're wired into muscle memory and rofi menus. The X11-era instructions have
> been retired from this README — see `docs/` and the `git log` if you ever need
> them back.

## Modes

`i3-screen-manager <command>`:

| Command | What it does |
|---------|-------------|
| `extend-left/right/above/below` | External monitor positioned relative to the internal panel |
| `clamshell` | External only, internal (`eDP-1`) off, lid-close safe |
| `mirror` | Both outputs mirrored at the best common mode |
| `disconnect` | Revert to the internal panel only |
| `scale [VALUE] [OUTPUT]` | Set Wayland output scale (rofi picker if no value; presets `0.75`–`2.00`) |
| `status` | Show internal/external, active monitors (pos/scale), and inhibitor state |

## Requirements

- **Hyprland** on Wayland (Hyprland 0.55+, Lua config — see `docs/hyprland-lua-migration.md`)
- `hyprctl`, `wlr-randr`, `jq`, `rofi`
- `elogind-inhibit` (Artix's logind; holds the `handle-lid-switch` block for clamshell)
- `solaar` (Logitech mouse DPI — `yay -S solaar`)
- `rbw`, `rofi-rbw` (Bitwarden lookup via rofi)
- Waybar (the `i3-cmos-battery` module renders into the bar)

## Installation

Symlink the repo scripts onto `PATH` (run from the repo root):

```bash
ln -sf "$(pwd)/i3-screen-manager"  ~/.local/bin/i3-screen-manager
ln -sf "$(pwd)/i3-screen-rofi"     ~/.local/bin/i3-screen-rofi
ln -sf "$(pwd)/i3-keyboard-rofi"   ~/.local/bin/i3-keyboard-rofi
ln -sf "$(pwd)/i3-tailscale-rofi"  ~/.local/bin/i3-tailscale-rofi
ln -sf "$(pwd)/i3-mouse-setup"     ~/.local/bin/i3-mouse-setup
ln -sf "$(pwd)/i3-mouse-rofi"      ~/.local/bin/i3-mouse-rofi
ln -sf "$(pwd)/i3-cmos-battery"    ~/.local/bin/i3-cmos-battery

# Standalone system-maintenance utility (no relation to the display scripts)
ln -sf "$(pwd)/aur-malware-check"  ~/.local/bin/aur-malware-check
```

Add the binds to your Hyprland config (hyprlang shown; under Lua use
`hl.bind(mainMod .. " + BackSpace", hl.dsp.exec_cmd("i3-screen-rofi"))` etc.):

```ini
bind = $mainMod, BackSpace,          exec, i3-screen-rofi       # display menu
bind = $mainMod CONTROL, BackSpace,  exec, i3-keyboard-rofi     # keyboard layout
bind = $mainMod ALT, BackSpace,      exec, i3-screen-manager scale
bind = $mainMod SHIFT, B,            exec, rofi-rbw             # Bitwarden
bind = $mainMod SHIFT, N,            exec, i3-tailscale-rofi    # Tailscale + Open Brain URL
# Optional: mouse DPI picker
bind = $mainMod ALT, M,              exec, i3-mouse-rofi
```

Apply mouse DPI at login by adding to your Hyprland config:

```ini
exec-once = i3-mouse-setup
```

Reload Hyprland with `hyprctl reload` (the live config is symlinked from
`~/projects/dotfiles/.config/hypr/`).

Display layout and scaling are a **laptop-docking** workflow: `nomad-artix` uses
these binds when an external monitor is plugged in. `godlike-artix` (desktop) is
single-monitor by design and never adjusts displays, so its display binds are
vestigial — the laptop/desktop asymmetry is deliberate, not drift to fix.

## Usage

Recommended keybindings (as wired on these machines):

| Keybinding | Action |
|---|---|
| `Super+Backspace` | Display management menu (`i3-screen-rofi`) |
| `Super+Ctrl+Backspace` | Keyboard layout toggle |
| `Super+Alt+Backspace` | Output scale picker (`i3-screen-manager scale`) |
| `Super+Shift+B` | Bitwarden password lookup (`rofi-rbw`) |
| `Super+Shift+N` | Tailscale up/down + Open Brain MCP URL switch |

Via CLI:

```bash
i3-screen-manager extend-right
i3-screen-manager clamshell
i3-screen-manager mirror
i3-screen-manager scale              # rofi picker
i3-screen-manager scale 1.5 eDP-1    # direct set, bypass the picker
i3-screen-manager disconnect
i3-screen-manager status
```

## Hybrid Graphics (laptop)

The ThinkPad is Intel Iris Xe + NVIDIA RTX 3050 Ti. Under Wayland the GPUs are
selected via `AQ_DRM_DEVICES` in `start-hyprland`: Intel (`eDP-1`) is the
compositor GPU listed first, NVIDIA is included so the external ports (all wired
through NVIDIA) light up. NVIDIA outputs follow `*-N-N` naming (`HDMI-1-0`,
`DP-1-*`); the script auto-detects whichever external becomes connected. The
desktop (`godlike-artix`) is pure AMD with no hybrid concerns.

## Output Scaling

Wayland uses per-output scaling, not `Xft.dpi` (there is no X resource database).
`i3-screen-manager scale` calls `hyprctl keyword monitor "$out,preferred,auto,$scale"`
with a rofi picker of `0.75 / 1.00 / 1.25 / 1.50 / 1.75 / 2.00`, or takes a value
and optional output directly (`scale 1.5 eDP-1`).

Script defaults: internal `eDP-1` at scale **1.25**, external outputs at **1.0**.
`clamshell`, `extend-*`, and `mirror` apply those automatically.

## Mouse DPI Management

For Logitech mice on Bolt/Unifying receivers, `solaar` sets hardware DPI.

- **On login:** add `exec-once = i3-mouse-setup` to your Hyprland config — it
  auto-detects the mouse and applies the saved DPI.
- **On the fly:** bind `i3-mouse-rofi` (e.g. `Super+Alt+M`) for a rofi picker of
  common presets (800–2000).
- **Persistence:** the choice is saved to `~/.config/i3-mouse-manager/dpi` and
  reapplied on the next login.

If no solaar-compatible mouse is detected, both scripts exit silently.

## CMOS Battery Monitoring

`i3-cmos-battery` reads the motherboard CMOS battery voltage via the it87 Super
I/O chip and reports health.

- **Waybar:** a custom module shows e.g. `CMOS 3.29V`, refreshed every 6 hours
- **CLI:** `i3-cmos-battery cli` for a human-readable report with warnings
- **Thresholds:** OK (>= 2.8V), LOW/yellow (2.5–2.8V), DEAD/red (< 2.5V)

Requires the `it87` kernel module:

```bash
echo "it87" | sudo tee /etc/modules-load.d/it87.conf
```

On machines without the sensor (e.g. the laptop), the script and Waybar module
produce no output.

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

**Fix (root-cause removal):**

```bash
sudo pacman -S xreader                 # evince fork, same UI, no gvfs dep
sudo pacman -R evince gvfs             # evince is the only hard dep on gvfs
xdg-mime default xreader.desktop application/pdf
```

As a safety net (in case a future package pulls gvfs back in), set the env var in
your Hyprland config so it covers the whole session:

```ini
env = GIO_USE_VFS,local
```

`gvfs` provides GNOME VFS backends (`trash://`, `network://`, …) over D-Bus —
useful on GNOME, dead weight on Hyprland. Removing it eliminates the timeout
entirely. **Applies to both machines.**

## Tailscale + Open Brain URL toggle

`i3-tailscale-rofi` (`Super+Shift+N`) brings Tailscale up or down and, in lockstep,
rewrites the Open Brain MCP `url` in `~/.claude.json` between the home-LAN
hostname (`http://open-brain/`, only reachable on the HOME VLAN) and node-0's
Tailscale IP (reachable from anywhere on the tailnet). This is the "Option B"
explicit URL switch described in the global setup notes. Prerequisite: Open Brain
on node-0 must listen on `0.0.0.0:8000` so the tailnet IP can reach it.

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

**Hyprland keybind:** `bind = $mainMod SHIFT, B, exec, rofi-rbw`

- `Super+Shift+B` opens a rofi menu of your whole vault — type to filter, Enter to copy
- `rbw-agent` starts on demand and caches the unlock for 1h (`rbw config set lock_timeout <s>`)
- When the lock expires, the next call pops `pinentry-gtk`
- For fields that reject paste, `rofi-rbw --action type` types the credential (via `wtype` on Wayland)

For vault management use the browser extension or web vault. **Applies to both machines.**

## Clamshell Safety

In clamshell mode with the lid closed, `disconnect` refuses to run and tells you
to open the lid first — preventing the "both screens go dark" scenario where
`eDP-1` can't reactivate because the lid is physically shut. Clamshell holds an
`elogind-inhibit handle-lid-switch` block (PID in `/tmp/i3-screen-manager-inhibit.pid`)
and survives Hyprland config reloads via `hyprland-clamshell-restore`.

## Keyboard Layout Toggle

`i3-keyboard-rofi` (`Super+Ctrl+Backspace`) switches between:

| Mode | Layout |
|------|--------|
| Laptop | Caps Lock → Ctrl, both Shifts → Caps Lock |
| External | Default US layout |

The rofi menu shows the current mode and lets you switch.

## License

MIT
