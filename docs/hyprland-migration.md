# Hyprland Migration Checklist

Migration from i3/X11 → Hyprland/Wayland on ThinkPad X1 Extreme Gen 5
(Intel Iris Xe + NVIDIA RTX 3050 Ti Mobile, Artix Linux / OpenRC)

Research date: 2026-03-30

---

## Risk Areas (Read First)

Three things make this migration non-trivial on this specific machine:

1. **Hybrid NVIDIA GPU** — needs careful `mkinitcpio` module ordering, persistent DRI paths, and selective env vars. External monitor performance may need tuning.
2. **OpenRC (no systemd)** — no `hyprland-openrc` package exists. Hyprland's tooling has systemd assumptions scattered throughout (`systemctl --user`, `dbus-update-activation-environment --systemd`). Each needs a workaround.
3. **i3-screen-manager rewrite** — the display management scripts are deeply X11. `xrandr` and `i3-msg` both need replacing. Plan for this to be the biggest chunk of work.

Driver 580 has a known regression (fails to load on some Arch systems). If hit, downgrade to 575.x.

---

## Phase 1: Pre-Migration Prep

- [ ] Back up current i3 config: `cp -r ~/.config/i3 ~/.config/i3.bak`
- [ ] Back up polybar config: `cp -r ~/.config/polybar ~/.config/polybar.bak`
- [ ] Back up picom config if any: `cp -r ~/.config/picom ~/.config/picom.bak`
- [ ] Commit any outstanding changes in this repo
- [ ] Verify `elogind` and `dbus` are already running (they should be from the Artix setup):
  ```bash
  rc-service elogind status
  rc-service dbus status
  ```
- [ ] Note the PCI addresses of both GPUs (needed for `AQ_DRM_DEVICES`):
  ```bash
  lspci -d ::03xx
  # Note the 0000:XX:XX.X addresses — Intel first, NVIDIA second
  ```
- [ ] Note persistent DRI device paths:
  ```bash
  ls -la /dev/dri/by-path/
  # e.g. pci-0000:00:02.0-card (Intel), pci-0000:01:00.0-card (NVIDIA)
  ```

---

## Phase 2: NVIDIA DRM/KMS Setup

**This must be done before attempting to start Hyprland.**

- [ ] Create `/etc/modprobe.d/nvidia.conf`:
  ```
  options nvidia_drm modeset=1
  ```
- [ ] Update `/etc/mkinitcpio.conf` MODULES — `i915` MUST come first (prevents 1-minute stall in Electron/Chromium apps):
  ```
  MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)
  ```
- [ ] Rebuild initramfs:
  ```bash
  sudo mkinitcpio -P
  ```
- [ ] Reboot and verify:
  ```bash
  cat /sys/module/nvidia_drm/parameters/modeset
  # Must return: Y
  ```

---

## Phase 3: Install Hyprland Ecosystem

```bash
# Core
sudo pacman -S hyprland hyprpaper hyprlock hypridle xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

# Wayland utilities
sudo pacman -S wl-clipboard wlr-randr wayland-protocols

# Screenshot stack — flameshot v13+ is the primary tool
# v13 added native Wayland support using grim as capture backend
sudo pacman -S flameshot grim   # grim is required by flameshot's Wayland backend
yay -S satty                    # backup annotator if flameshot has issues

# Screen sharing / portal support
sudo pacman -S wireplumber pipewire-pulse  # already installed from audio setup

# Rofi: 2.0.0 merged Wayland support — just upgrade
sudo pacman -S rofi  # or: yay -S rofi-wayland if 2.0 not in repos yet

# Notification daemon — dunst already works on Wayland, keep it
# nm-applet — already works on Wayland, keep it

# Waybar (replaces polybar)
sudo pacman -S waybar
```

**Do NOT install:**
- `xdg-desktop-portal-wlr` — conflicts with hyprland portal
- `xdg-desktop-portal-gnome` — conflicts

---

## Phase 4: Hyprland Startup (replaces startx)

Hyprland launches directly from TTY — no xinit, no display manager.

- [ ] Create `~/.local/bin/start-hyprland`:
  ```bash
  #!/bin/sh
  export XDG_CURRENT_DESKTOP=Hyprland
  export XDG_SESSION_TYPE=wayland
  export XDG_SESSION_DESKTOP=Hyprland
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  export XCURSOR_SIZE=24
  export XCURSOR_THEME=Adwaita

  # NVIDIA hybrid — use persistent DRI paths (not card0/card1 which shuffle on boot)
  # Fill in actual paths from Phase 1:
  export AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/by-path/pci-0000:01:00.0-card

  exec Hyprland
  ```
- [ ] Make executable: `chmod +x ~/.local/bin/start-hyprland`

- [ ] Add auto-start to `~/.config/fish/config.fish` (replaces the `startx` equivalent):
  ```fish
  # Auto-start Hyprland on TTY1
  if test (tty) = /dev/tty1; and not set -q WAYLAND_DISPLAY
      exec start-hyprland
  end
  ```

---

## Phase 5: Hyprland Core Config

Create `~/.config/hypr/hyprland.conf`. Start minimal, build up.

### Environment variables

```
# Wayland session
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland

# NVIDIA (be selective — some break things)
env = __GLX_VENDOR_LIBRARY_NAME,nvidia   # Remove if screensharing breaks
env = GBM_BACKEND,nvidia-drm             # Remove if Firefox crashes
env = NVD_BACKEND,direct                 # VA-API hardware video via NVIDIA
env = LIBVA_DRIVER_NAME,iHD             # Use Intel iHD for VA-API (hybrid)
env = AQ_FORCE_LINEAR_BLIT,0            # Fixes external monitor perf on hybrid

# App compatibility
env = MOZ_ENABLE_WAYLAND,1
env = ELECTRON_OZONE_PLATFORM_HINT,wayland
```

### Monitor setup (initial — will be managed by i3-screen-manager rewrite)

```
# Hyprland auto-detects monitors. Minimal starting config:
monitor = eDP-1, preferred, 0x0, 1      # Internal display, auto res, scale 1
# External monitor: Hyprland will detect and enable; configure after seeing output of:
# hyprctl monitors
```

### Startup (exec-once)

```
# OpenRC/Artix: Drop --systemd flag from dbus command
exec-once = dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

# XDG portal — delay needed on OpenRC (no socket activation)
exec-once = sleep 1 && /usr/lib/xdg-desktop-portal-hyprland
exec-once = sleep 2 && /usr/lib/xdg-desktop-portal

# Polkit agent (must invoke binary directly, not systemctl --user)
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

# Tray / notifications (same as i3)
exec-once = nm-applet --indicator
exec-once = dunst
exec-once = hyprpaper

# Idle / lock
exec-once = hypridle

# Waybar (replaces polybar)
exec-once = waybar
```

### Keybindings (port from i3 config)

```
$mod = SUPER

# Applications
bind = $mod, Return, exec, kitty
bind = $mod SHIFT, Return, exec, kitty --class KittyFloating
bind = $mod, E, exec, emacs
bind = $mod, B, exec, brave --profile-directory=Default --new-window
bind = $mod, F10, exec, goland
bind = $mod, F11, exec, subl
bind = $mod, F12, exec, emacs
bind = $mod SHIFT, V, exec, ~/.local/bin/volumecontrol.sh

# Window management
bind = $mod, Q, killactive
bind = $mod, F, fullscreen
bind = $mod SHIFT, Space, togglefloating
bind = $mod, D, exec, rofi -show drun
bind = $mod, Tab, exec, rofi -show window

# Workspaces
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
# ... (3-0 same pattern)
bind = $mod SHIFT, 1, movetoworkspace, 1
# ... etc.

# Screenshots — flameshot v13+ with native Wayland backend
bind = , Print, exec, flameshot gui
bind = $mod SHIFT, Print, exec, flameshot full

# Audio (same as i3)
bind = , XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
bind = , XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
bind = , XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
bind = , XF86AudioMicMute, exec, pactl set-source-mute @DEFAULT_SOURCE@ toggle
bind = CTRL, F1, exec, pactl set-source-mute @DEFAULT_SOURCE@ toggle

# Brightness
bind = , XF86MonBrightnessUp, exec, brightnessctl s +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl s 5%-

# Media
bind = , XF86AudioPlay, exec, playerctl play-pause
bind = , XF86AudioPause, exec, playerctl play-pause
bind = , XF86AudioNext, exec, playerctl next
bind = , XF86AudioPrev, exec, playerctl previous

# Focus / move (hjkl + arrow keys)
bind = $mod, left, movefocus, l
bind = $mod, right, movefocus, r
bind = $mod, up, movefocus, u
bind = $mod, down, movefocus, d
```

### Window rules (required for flameshot)

flameshot's capture overlay can open as a regular window on Hyprland instead of a fullscreen overlay. These rules fix it:

```
# Force flameshot overlay to float and cover the full screen at 0,0
windowrulev2 = float, class:^(flameshot)$
windowrulev2 = move 0 0, class:^(flameshot)$
windowrulev2 = pin, class:^(flameshot)$
windowrulev2 = noanim, class:^(flameshot)$

# Suppress idle inhibitor while flameshot is open
windowrulev2 = idleinhibit always, class:^(flameshot)$
```

If multi-monitor capture is still broken (overlay on only one screen), try launching flameshot as a daemon in `exec-once` and triggering via `flameshot gui` rather than launching fresh each time:
```
exec-once = flameshot
```

---

## Phase 6: Waybar Config (replaces polybar)

Waybar modules mapping from current polybar setup:

| polybar module | waybar equivalent |
|---|---|
| `i3` | `hyprland/workspaces` |
| `xwindow` | `hyprland/window` |
| `pulseaudio` | `pulseaudio` (same) |
| `pulseaudio-control-input` | `pulseaudio#input` |
| `memory` | `memory` |
| `cpu` | `cpu` |
| `temperature` | `temperature` |
| `battery` | `battery` |
| `date` | `clock` |
| `systray` | `tray` |

- [ ] Create `~/.config/waybar/config.jsonc` and `~/.config/waybar/style.css`
- [ ] Port TX-02 font from polybar config
- [ ] Port color scheme from polybar to waybar CSS

---

## Phase 7: i3-screen-manager Rewrite

This is the biggest chunk. The logic stays the same; the plumbing changes.

### API mapping

| Current (X11) | Hyprland equivalent |
|---|---|
| `xrandr` (detect monitors) | `hyprctl monitors -j` |
| `xrandr --output X --mode M --right-of Y` | `hyprctl keyword monitor X,preferred,auto,1` + position |
| `xrandr --output X --off` | `hyprctl keyword monitor X,disable` |
| `xrandr --output X --same-as Y` | `hyprctl keyword monitor X,preferred,auto,1,mirror,Y` |
| `i3-msg get_workspaces` | `hyprctl workspaces -j` |
| `i3-msg "workspace W; move workspace to output O"` | `hyprctl dispatch moveworkspacetomonitor W O` |
| `echo "Xft.dpi: N" \| xrdb -merge` | `hyprctl keyword monitor eDP-1,preferred,auto,SCALE` (scale = dpi/96) |

### DPI → Scale conversion

Wayland uses output scaling instead of `Xft.dpi`. Mapping:
- 96 DPI → scale 1.0
- 120 DPI → scale 1.25
- 144 DPI → scale 1.5
- 192 DPI → scale 2.0

The `dpi` subcommand becomes a `scale` subcommand, or accepts a DPI and converts.

### What stays the same
- Lid state detection (kernel ACPI — unchanged)
- `elogind-inhibit` clamshell lock (unchanged)
- Rofi menus (`i3-screen-rofi`) — just update the commands it calls
- Safe-default logic (refuse disconnect if lid closed)

### Plan
- [ ] Add new `hyprland` branch or gate in `i3-screen-manager` on `WAYLAND_DISPLAY` being set
- [ ] Rewrite `detect_external()` using `hyprctl monitors -j | jq`
- [ ] Rewrite `extend_right/left/above/below()` using `hyprctl keyword monitor`
- [ ] Rewrite `mirror()` using Hyprland mirror syntax
- [ ] Rewrite `clamshell()` — disable eDP-1, move workspaces to external
- [ ] Rewrite `disconnect()` — enable eDP-1, disable external, move workspaces back
- [ ] Rewrite `dpi()` → `scale()` using `hyprctl keyword monitor`
- [ ] Update `i3-screen-rofi` to call new subcommand names

---

## Phase 8: Remaining Tool Replacements

- [ ] **Wallpaper**: Replace `feh` with `hyprpaper`
  - Config: `~/.config/hypr/hyprpaper.conf`
  ```
  preload = ~/wallpapers/current.jpg
  wallpaper = eDP-1,~/wallpapers/current.jpg
  ```
- [ ] **Screen lock**: Replace `i3lock` with `hyprlock`
  - Config: `~/.config/hypr/hyprlock.conf`
- [ ] **Idle management**: `hypridle` (replaces any xautolock/xidlehook)
  - Config: `~/.config/hypr/hypridle.conf`
- [ ] **picom**: Remove/disable — Hyprland has blur/animations built in
- [ ] **Keyboard layout toggle**: `~/.local/bin/i3-keyboard-rofi` uses `xkb-switch` or similar — verify it works under Wayland or replace with `hyprctl switchxkblayout`

---

## Phase 9: Screen Sharing Verification

- [ ] Verify portal is running: `ps aux | grep xdg-desktop-portal-hyprland`
- [ ] Test capture works: `grim /tmp/test.png` → should produce a screenshot
- [ ] Test Zoom screen share (window share, not whole screen first)
- [ ] Test Brave tab share
- [ ] If Discord: install `xwaylandvideobridge` (AUR), add to `exec-once`

**OpenRC gotcha**: Replace any `systemctl --user restart xdg-desktop-portal` calls with direct process restarts:
```bash
pkill xdg-desktop-portal; sleep 1; /usr/lib/xdg-desktop-portal-hyprland &
```

---

## Phase 10: Post-Migration Cleanup

- [ ] Remove picom: `sudo pacman -R picom`
- [ ] Remove polybar: `sudo pacman -R polybar` (after waybar is working)
- [ ] Remove i3: `sudo pacman -R i3-wm i3status` (after Hyprland stable)
- [ ] Update `~/.xinitrc` — no longer used; keep as backup but it won't be called
- [ ] Remove `LIBVA_DRIVER_NAME=iHD` from `.xinitrc` — move to `start-hyprland` or `hyprland.conf` env block
- [ ] Update CLAUDE.md in this repo to reflect Hyprland architecture

---

## Known Gotchas Summary

| Gotcha | Fix |
|---|---|
| `systemctl --user` calls fail under OpenRC | Use `exec-once` in hyprland.conf or OpenRC user services |
| `dbus-update-activation-environment --systemd` | Drop `--systemd` flag |
| `XDG_RUNTIME_DIR` not set | Add to `start-hyprland` script |
| elogind race condition with parallel OpenRC | Disable `rc_parallel` or ensure explicit ordering |
| External monitor 30fps on hybrid | Set `AQ_FORCE_LINEAR_BLIT=0`, or `nvidia-smi -pm 1` |
| Resume from suspend drops display | Add `nvidia_drm.fbdev=0` kernel param |
| Electron/Chromium 1-minute stall at boot | `i915` MUST be first in mkinitcpio MODULES |
| Rofi font config | Same `configuration { font: "TX-02 12"; }` trick applies in Wayland mode |
| `GBM_BACKEND=nvidia-drm` breaks Firefox | Remove that env var, Firefox uses EGL directly |
| Flameshot overlay opens as regular window | Add window rules: `float`, `move 0 0`, `pin`, `noanim` for class `flameshot`. Run as daemon via `exec-once = flameshot` for multi-monitor. Do NOT use `QT_QPA_PLATFORM=xcb`. |

---

## Reference

- Hyprland NVIDIA wiki: https://wiki.hyprland.org/Nvidia/
- Hyprland master tutorial: https://wiki.hyprland.org/Getting-Started/Master-Tutorial/
- xdg-desktop-portal-hyprland: https://wiki.hyprland.org/Useful-Utilities/Hyprland-desktop-portal/
- Community Artix+OpenRC+Hyprland reference: https://github.com/dassarthak18/ArtixOpenRC-Hyprland
- Waybar wiki: https://github.com/Alexays/Waybar/wiki
