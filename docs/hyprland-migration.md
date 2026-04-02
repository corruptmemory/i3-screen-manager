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

- [x] Back up current i3 config (dotfiles repo serves as backup)
- [x] Back up polybar config (dotfiles repo)
- [x] Back up picom config (dotfiles repo)
- [x] Commit any outstanding changes in this repo
- [x] Verify `elogind` and `dbus` are already running
  ```bash
  rc-service elogind status
  rc-service dbus status
  ```
- [x] Note the PCI addresses of both GPUs (Intel 00:02.0, NVIDIA 01:00.0)
  ```bash
  lspci -d ::03xx
  # Note the 0000:XX:XX.X addresses — Intel first, NVIDIA second
  ```
- [x] Note persistent DRI device paths (confirmed, used in start-hyprland)
  ```bash
  ls -la /dev/dri/by-path/
  # e.g. pci-0000:00:02.0-card (Intel), pci-0000:01:00.0-card (NVIDIA)
  ```

---

## Phase 2: NVIDIA DRM/KMS Setup

**This must be done before attempting to start Hyprland.**

- [x] Create `/etc/modprobe.d/nvidia.conf`
  ```
  options nvidia_drm modeset=1
  ```
- [x] Update `/etc/mkinitcpio.conf` MODULES — `i915` MUST come first (prevents 1-minute stall in Electron/Chromium apps):
  ```
  MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)
  ```
- [x] Rebuild initramfs
  ```bash
  sudo mkinitcpio -P
  ```
- [x] Reboot and verify (modeset=Y confirmed)
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

# Tools the laptop conf uses
sudo pacman -S pamixer mako udiskie

# Notification daemon: mako (simpler, Wayland-native) replaces dunst
# nm-applet — already works on Wayland, keep it

# Waybar (replaces polybar)
sudo pacman -S waybar
```

**Do NOT install:**
- `xdg-desktop-portal-wlr` — conflicts with hyprland portal
- `xdg-desktop-portal-gnome` — conflicts

---

## Phase 4: Hyprland Startup (replaces startx)

**Already done.** `~/.local/bin/start-hyprland` is written and executable. Fish auto-start is in `~/.config/fish/config.fish`. Both committed.

DRI paths confirmed:
- Intel: `/dev/dri/by-path/pci-0000:00:02.0-card` ✓
- NVIDIA: `/dev/dri/by-path/pci-0000:01:00.0-card` — **will only appear after Phase 2** (nvidia_drm modeset=1 + mkinitcpio -P + reboot). Script has correct path already.

---

## Phase 5: Hyprland Core Config

**You have a working laptop config in dotfiles — use it, don't start from scratch.**

```bash
mkdir -p ~/.config/hypr
ln -sf ~/projects/dotfiles/.config/hypr/hyprland-laptop.conf ~/.config/hypr/hyprland.conf
```

The laptop conf has been updated for Artix/OpenRC (dropped `--systemd`, removed `systemctl --user import-environment`, `foot` → `kitty`, `uwsm app --` wrapper removed). Key things already in it: TX-02 font, flameshot as daemon, master layout, groups, special workspaces (terminal/volume/claude/chatgpt/zoom), JetBrains window rules, lid switch bindings, scale 1.25 on eDP-1.

**Things to verify/adjust before first boot:**
- `monitor=DP-7,...` — check actual external output name with `hyprctl monitors` once running
- `morgen` in exec-once — remove/comment if not installed
- `mako` in exec-once — install (`sudo pacman -S mako`) or swap for dunst

The rest of this section documents what's in the config for reference.

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

flameshot's capture overlay is placed inside the active window group on Hyprland unless forced to float and fullscreen. The working rule set (Hyprland 0.54.x, new `windowrule {}` syntax):

```
windowrule {
    name = flameshot
    match:class = ^(flameshot)$
    float = on
    fullscreen = true
    no_anim = true
}
```

`float = on` — pulls flameshot out of any group so the canvas isn't caged to the group area.
`fullscreen = true` — Hyprland forces true fullscreen covering all layer shells (waybar, groupbar, etc.).
`no_anim = true` — prevents the fullscreen animation flash.
**No `suppress_event = fullscreen` needed** — that caused the returning window to be fullscreened after flameshot closed.

Run as a daemon so the canvas is ready immediately:
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

- [x] Waybar symlinked from dotfiles
- [x] TX-02 font in waybar config
- [x] Color scheme ported
- [x] Network module: set `interface` or it defaults to `lo` (loopback) — useless

  ```jsonc
  "network": {
    "interface": "wl*",
    "format-wifi": "󰤢 {essid}",
    "format-ethernet": "󰈀 {ifname}",
    "format-disconnected": "󰤠 disconnected",
    "interval": 5,
    "tooltip": false
  }
  ```

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
- [ ] Add new `hyprland` branch or gate in `i3-screen-manager` on `WAYLAND_DISPLAY` being set *(needs external monitor)*
- [ ] Rewrite `detect_external()` using `hyprctl monitors -j | jq`
- [ ] Rewrite `extend_right/left/above/below()` using `hyprctl keyword monitor`
- [ ] Rewrite `mirror()` using Hyprland mirror syntax
- [ ] Rewrite `clamshell()` — disable eDP-1, move workspaces to external
- [ ] Rewrite `disconnect()` — enable eDP-1, disable external, move workspaces back
- [ ] Rewrite `dpi()` → `scale()` using `hyprctl keyword monitor`
- [ ] Update `i3-screen-rofi` to call new subcommand names

---

## Phase 8: Remaining Tool Replacements

- [x] **Wallpaper**: swaybg (hyprpaper stable package was broken)
  - Config: `~/.config/hypr/hyprpaper.conf`
  ```
  preload = ~/wallpapers/current.jpg
  wallpaper = eDP-1,~/wallpapers/current.jpg
  ```
- [x] **Screen lock**: hyprlock configured, SUPER+SHIFT+L
  - Config: `~/.config/hypr/hyprlock.conf`
- [x] **Idle management**: hypridle — screen off 5min, suspend on battery 15min
  - Config: `~/.config/hypr/hypridle.conf`
- [ ] **picom**: Remove/disable (defer to Phase 10 cleanup)
- [x] **Keyboard layout toggle**: i3-keyboard-rofi ported to hyprctl, working

---

## Phase 9: Screen Sharing Verification

- [x] Verify portal is running: `ps aux | grep xdg-desktop-portal-hyprland`
- [x] Test capture works: `grim /tmp/test.png` → should produce a screenshot
- [x] Test Zoom screen share — **verified working 2026-04-01**
- [ ] Test Brave tab share (minor — portal working, likely fine)
- [x] Discord: all apps running native Wayland, xwaylandvideobridge not needed

**OpenRC gotcha**: Replace any `systemctl --user restart xdg-desktop-portal` calls with direct process restarts:
```bash
pkill xdg-desktop-portal; sleep 1; /usr/lib/xdg-desktop-portal-hyprland &
```

---

## Phase 10: Post-Migration Cleanup

- [ ] Remove picom, polybar, i3 (defer — keep until fully stable on Hyprland)


- [ ] Update `~/.xinitrc` (keep as backup, won't be called)
- [x] `LIBVA_DRIVER_NAME=iHD` in start-hyprland
- [ ] Update CLAUDE.md in this repo to reflect Hyprland architecture

---

## Verified Working (2026-04-01)

| App / Feature | Status | Notes |
|---|---|---|
| Hyprland boot | ✅ | Via `~/.local/bin/start-hyprland` → `/usr/bin/start-hyprland` |
| NVIDIA hybrid | ✅ | `AQ_DRM_DEVICES` resolved via `readlink` to avoid colon-splitting |
| gnome-keyring / libsecret | ✅ | `DBUS_SESSION_BUS_ADDRESS` must be set explicitly on OpenRC |
| Brave browser | ✅ | Wayland-native, keyring working |
| Azure Storage Explorer | ✅ | libsecret working |
| flameshot-git | ✅ | Annotation working. Required `xdg-desktop-portal-gtk` for Screenshot portal |
| Zoom | ✅ | Stays in special workspace, screen sharing works |
| Slack / Discord / Keybase | ✅ | Kinetic scrolling working |
| JetBrains GoLand 2026.1 | ✅ | Wayland-native |
| xdg-desktop-portal | ✅ | Screenshot portal requires `xdg-desktop-portal-gtk` for Access interface |

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
| Flameshot canvas doesn't cover full screen (waybar/groupbar excluded) | Use `float = on` + `fullscreen = true` + `no_anim = true` in windowrule. `float` pulls it out of groups; `fullscreen` covers all layer shells. Do NOT add `suppress_event = fullscreen` — that makes the returning window fullscreen after flameshot closes. Use `flameshot-git` (AUR), NOT stable `flameshot`. Do NOT set `useGrimAdapter=true` — git version has native Wayland and breaks with it. |
| `org.freedesktop.portal.Screenshot` missing | `xdg-desktop-portal` 1.18+ requires `org.freedesktop.impl.portal.Access` for Screenshot's confirmation dialog. Install `xdg-desktop-portal-gtk` to provide it. |
| `DBUS_SESSION_BUS_ADDRESS` not set on OpenRC | Artix OpenRC puts session bus at `/run/user/$UID/bus` but doesn't export the env var. Set `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus` in `start-hyprland`. Without it libsecret consumers report "no secret store". |
| Mako default font is `monospace 10` — small and ugly | Use a proportional font at a larger size. `Adwaita Sans Light 12` reads well. Mako uses Pango so any installed font works: `font=Adwaita Sans Light 12` in `~/.config/mako/config`. |
| Sub-pixel rendering not enabled by default on Artix | Symlink the preset and rebuild the font cache: `sudo ln -sf /usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/ && fc-cache -f`. Verify with `fc-match --verbose "font name" \| grep rgba` — should show `rgba: 1`. Note: at fractional scale (1.25) the benefit is less pronounced than at 1.0. |
| Waybar network module shows `lo` (loopback) | No `interface` set — Waybar picks the first interface alphabetically. Set `"interface": "wl*"` to target wifi; use `{essid}` in `format-wifi` and `{ifname}` in `format-ethernet`. |

---

## Steam Gaming on Hyprland

Research date: 2026-03-31

### What Works

- **Steam client** launches fine via XWayland (not Wayland-native itself)
- **Most Proton games** work through XWayland — "just works" for the majority of recent titles
- **Gamescope** works on Hyprland (unlike Niri where it core dumps on NVIDIA) — reliable fallback for problematic games
- **Native Wine Wayland** landing in Wine 10 / Proton 10 — games can talk directly to Wayland, bypassing XWayland entirely. Not default yet but opt-in via launch options

### Known Gotchas

| Issue | Severity | Workaround |
|-------|----------|------------|
| **Mouse cursor jumps / won't lock in XWayland games** | High for FPS/RTS | Set `cursor { no_hardware_cursors = true }`, or use Gamescope, or use native Wine Wayland (`PROTON_ADD_CONFIG=wayland %command%`) |
| **Game launches on wrong monitor** | Moderate | Use `PROTON_WAYLAND_MONITOR=eDP-1 %command%` (GE-Proton), or Hyprland window rules |
| **Direct scanout freezes game on notification** | Moderate | Disable `render:direct_scanout` for affected games via window rules |
| **VRR not working despite being enabled** | Low | Remove animation rules with `loop` keyword — they break VRR timing |
| **DX12 games slower than Windows on NVIDIA** | Low-Moderate | Driver-level issue with vkd3d-proton translation. NVIDIA 570+ improving but gap persists |
| **Controller input bleeds to background windows** | Low | Wayland-wide issue — gamepad events still sent when window unfocused |
| **Flickering in XWayland on NVIDIA** | Low (fixed) | NVIDIA 555+ has explicit sync. Set `explicit_sync = 2` in config |

### Launch Options Cheat Sheet

```bash
# Native Wine Wayland (standard Proton)
PROTON_ADD_CONFIG=wayland %command%

# Native Wine Wayland (CachyOS/Proton-EM)
PROTON_ENABLE_WAYLAND=1 %command%

# Explicit monitor for Wine Wayland (GE-Proton)
PROTON_ADD_CONFIG=wayland PROTON_WAYLAND_MONITOR=eDP-1 %command%

# Gamescope wrapper (fallback for problematic games)
gamescope -W 1920 -H 1080 -r 60 -- %command%

# Gamescope with HDR
gamescope --hdr-enabled -W 1920 -H 1080 -- %command%
```

### Hyprland Gaming Config Recommendations

```
cursor {
    no_hardware_cursors = true
}

xwayland {
    force_zero_scaling = true   # Games handle their own scaling
}

render {
    explicit_sync = 2
    explicit_sync_kms = 2
}

misc {
    vfr = true                  # Reduce power when idle
    vrr = 1                     # Variable refresh rate
    allow_tearing = true        # For games that support tearing (reduces latency)
}

# Disable blur/shadow if you want max performance (Jim: you disable all bling anyway)
decoration {
    blur { enabled = false }
    shadow { enabled = false }
}
```

### Proton Native Wayland: The Future

Wine 10 (early 2026) shipped with Wayland driver enabled in default config. Key improvements:
- Direct Wayland protocol communication (no XWayland translation)
- Better mouse capture (native pointer confinement)
- Proper multi-monitor handling via `PROTON_WAYLAND_MONITOR`
- OpenGL support in Wine Wayland driver

Not yet the default in Proton (still falls back to XWayland when X11 available), but opt-in works for many games. Valve is invested — Steam Deck uses Gamescope (Wayland compositor), so the ecosystem will keep improving.

### Zoom on Hyprland

Zoom runs via XWayland on Hyprland (native XWayland support, unlike Niri's xwayland-satellite). The floating toolbar, mini-window, and participant thumbnails mostly work because Hyprland's XWayland handles window positioning.

For screen sharing, configure `~/.config/zoomus.conf`:
```ini
enableWaylandShare=true
```
Then in Zoom: Settings → Share Screen → Advanced → Screen Capture Mode → **PipeWire** (not Automatic).

Alternatively, set `xwayland=false` to force full Wayland mode (skips XWayland entirely), but this may break `ZoomWebviewHost`. Test both approaches.

---

## Reference

- Hyprland NVIDIA wiki: https://wiki.hyprland.org/Nvidia/
- Hyprland master tutorial: https://wiki.hyprland.org/Getting-Started/Master-Tutorial/
- xdg-desktop-portal-hyprland: https://wiki.hyprland.org/Useful-Utilities/Hyprland-desktop-portal/
- Community Artix+OpenRC+Hyprland reference: https://github.com/dassarthak18/ArtixOpenRC-Hyprland
- Waybar wiki: https://github.com/Alexays/Waybar/wiki
