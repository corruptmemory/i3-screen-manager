# i3-screen-manager

External display management for i3/X11 on laptops with hybrid graphics (Intel + Nvidia).

Provides a rofi menu and CLI for switching between display modes without manually wrangling `xrandr`.

## Modes

| Command | What it does |
|---------|-------------|
| `extend-left/right/above/below` | External monitor positioned relative to laptop |
| `clamshell` | External only, laptop screen off, lid-close safe |
| `mirror` | Both screens mirrored at best common resolution |
| `disconnect` | Revert to laptop screen only |
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
bindsym $mod+BackSpace exec --no-startup-id i3-screen-rofi
```

Reload i3 with `$mod+Shift+r`.

## Usage

Via rofi menu: press `Super+Backspace`.

Via CLI:

```bash
i3-screen-manager extend-right
i3-screen-manager clamshell
i3-screen-manager disconnect
i3-screen-manager status
```

## Hybrid Graphics

Tested with Intel (modesetting) + Nvidia (proprietary) using PRIME display offloading. The laptop panel runs on Intel (`eDP-1`), external outputs run through Nvidia (`HDMI-1-0`, `DP-1-*`). The script auto-detects whichever external output becomes connected.

## Clamshell Safety

When in clamshell mode with the lid closed, `disconnect` refuses to run and tells you to open the lid first. This prevents the "both screens go dark" scenario where `eDP-1` can't activate because the lid is physically closed.

## License

MIT
