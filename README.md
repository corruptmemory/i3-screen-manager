# i3-screen-manager

Quality-of-life scripts for i3/X11 — display management, mouse DPI control, hardware monitoring, and keyboard layout toggling, all accessible via rofi menus and Polybar.

## Modes

| Command | What it does |
|---------|-------------|
| `extend-left/right/above/below` | External monitor positioned relative to laptop |
| `clamshell` | External only, laptop screen off, lid-close safe |
| `clamshell <DPI>` | Clamshell with custom DPI (e.g., `clamshell 108`) |
| `mirror` | Both screens mirrored at best common resolution |
| `disconnect` | Revert to laptop screen only |
| `dpi [VALUE]` | Set Xft.dpi on the fly (rofi picker if no value given) |
| `status` | Show current display state |

## Requirements

- i3 window manager
- X11 (not Wayland)
- `xrandr`, `jq`, `rofi`
- `systemd-inhibit` (for clamshell lid-close prevention)
- `solaar` (for Logitech mouse DPI management — install with `yay -S solaar`)

## Installation

```bash
# Symlink to PATH
ln -sf "$(pwd)/i3-screen-manager" ~/.local/bin/i3-screen-manager
ln -sf "$(pwd)/i3-screen-rofi" ~/.local/bin/i3-screen-rofi
ln -sf "$(pwd)/i3-mouse-setup" ~/.local/bin/i3-mouse-setup
ln -sf "$(pwd)/i3-mouse-rofi" ~/.local/bin/i3-mouse-rofi
ln -sf "$(pwd)/i3-cmos-battery" ~/.local/bin/i3-cmos-battery
```

Add to your i3 config:

```
# Display management
bindsym $mod+BackSpace exec --no-startup-id i3-screen-rofi

# Keyboard layout toggle
bindsym $mod+Control+BackSpace exec --no-startup-id i3-keyboard-rofi

# DPI adjustment
bindsym $mod+$alt+BackSpace exec --no-startup-id i3-screen-manager dpi

# Mouse DPI
bindsym $mod+Mod1+m exec --no-startup-id i3-mouse-rofi
```

Add to your `~/.xinitrc` (before `exec i3`):

```bash
i3-mouse-setup &
```

Reload i3 with `$mod+Shift+r`.

## Usage

Via rofi menus:

| Keybinding | Menu |
|---|---|
| `Super+Backspace` | Display management |
| `Super+Ctrl+Backspace` | Keyboard layout toggle |
| `Super+Alt+Backspace` | DPI adjustment |
| `Super+Alt+M` | Mouse DPI |

Via CLI:

```bash
i3-screen-manager extend-right
i3-screen-manager clamshell
i3-screen-manager clamshell 108
i3-screen-manager dpi
i3-screen-manager dpi 96
i3-screen-manager disconnect
i3-screen-manager status
```

## Hybrid Graphics

Tested with Intel (modesetting) + Nvidia (proprietary) using PRIME display offloading. The laptop panel runs on Intel (`eDP-1`), external outputs run through Nvidia (`HDMI-1-0`, `DP-1-*`). The script auto-detects whichever external output becomes connected.

## DPI Management

Clamshell mode automatically adjusts `Xft.dpi` from the laptop's 120 to 96 for external monitors. `disconnect` restores it. For non-standard monitors (TVs, high-DPI externals), use "Clamshell (custom DPI)" in the rofi menu or `Super+Alt+Backspace` to adjust on the fly.

DPI presets: 72, 84, 96, 108, 120, 144 — or type any value.

## Mouse DPI Management

For Logitech mice connected via Bolt or Unifying receivers, `solaar` is used to adjust hardware DPI.

- **On login:** `i3-mouse-setup` runs from `~/.xinitrc` and applies the saved DPI automatically
- **On the fly:** `Super+Alt+M` opens a rofi picker with common DPI presets (800–2000)
- **Persistence:** Selected DPI is saved to `~/.config/i3-mouse-manager/dpi` and reapplied on boot

If no solaar-compatible mouse is detected, both scripts exit silently.

## CMOS Battery Monitoring

`i3-cmos-battery` reads the motherboard CMOS battery voltage via the it87 Super I/O chip and reports health status.

- **Polybar:** Displays `CMOS 3.29V` in the bar, refreshes every 6 hours
- **CLI:** `i3-cmos-battery cli` for a human-readable report with warnings
- **Thresholds:** OK (>= 2.8V), LOW/yellow (2.5–2.8V), DEAD/red (< 2.5V)

Requires the `it87` kernel module:

```bash
echo "it87" | sudo tee /etc/modules-load.d/it87.conf
```

On machines without the sensor (e.g., laptops), the script and Polybar module silently produce no output.

## GTK File Dialog Fix

GTK open/save dialogs hang for ~25 seconds on i3 because `gvfsd-trash` (the GNOME virtual filesystem trash backend) times out on a D-Bus call every time a FileChooserDialog builds its sidebar.

**Symptom:** Clicking "Open File" or "Save As" in any GTK app (Brave, Firefox, etc.) takes 25 seconds before the dialog appears.

**Diagnosis:**

```bash
# This will hang ~25 seconds if you have the bug:
time gio info trash:///

# This should be instant:
time GIO_USE_VFS=local gio info trash:///
```

**Fix:** Add to `~/.xinitrc` before `exec i3`:

```bash
export GIO_USE_VFS=local
```

This tells GLib to use direct POSIX file access instead of the gvfs D-Bus backend. The only loss is `trash://` and `network://` URIs in GTK apps — irrelevant on i3 where you use the terminal for file management.

**Applies to both desktop and laptop.**

## Clamshell Safety

When in clamshell mode with the lid closed, `disconnect` refuses to run and tells you to open the lid first. This prevents the "both screens go dark" scenario where `eDP-1` can't activate because the lid is physically closed.

## Keyboard Layout Toggle

`i3-keyboard-rofi` switches between laptop and external keyboard layouts:

| Mode | Layout |
|------|--------|
| Laptop | Caps Lock → Ctrl, both Shifts → Caps Lock |
| External | Default US layout |

The rofi menu shows the current mode and lets you switch. Bound to `Super+Ctrl+Backspace`.

**Note:** `i3-keyboard-rofi` lives in `~/.local/bin/` directly (not symlinked from this repo) since it's a standalone single-file utility.

## License

MIT
