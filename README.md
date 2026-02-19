# i3-screen-manager

Quality-of-life scripts for i3/X11 on laptops — display management and keyboard layout toggling, all accessible via rofi menus.

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

## Installation

```bash
# Symlink to PATH
ln -sf "$(pwd)/i3-screen-manager" ~/.local/bin/i3-screen-manager
ln -sf "$(pwd)/i3-screen-rofi" ~/.local/bin/i3-screen-rofi
```

Add to your i3 config:

```
# Display management
bindsym $mod+BackSpace exec --no-startup-id i3-screen-rofi

# Keyboard layout toggle
bindsym $mod+Control+BackSpace exec --no-startup-id i3-keyboard-rofi

# DPI adjustment
bindsym $mod+$alt+BackSpace exec --no-startup-id i3-screen-manager dpi
```

Reload i3 with `$mod+Shift+r`.

## Usage

Via rofi menus:

| Keybinding | Menu |
|---|---|
| `Super+Backspace` | Display management |
| `Super+Ctrl+Backspace` | Keyboard layout toggle |
| `Super+Alt+Backspace` | DPI adjustment |

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
