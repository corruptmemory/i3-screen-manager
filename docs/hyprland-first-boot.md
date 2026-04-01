# Hyprland First Boot Checklist

Run these after rebooting from Phase 2 (NVIDIA DRM/KMS setup).

## 1. Verify NVIDIA modeset (before launching Hyprland)

Boot into i3 first to confirm X11 still works, then run:

```bash
# Should print 'Y'
cat /sys/module/nvidia_drm/parameters/modeset

# Should show pci-0000:01:00.0-card (NVIDIA) alongside 00:02.0 (Intel)
ls /dev/dri/by-path/
```

If `pci-0000:01:00.0-card` is missing, NVIDIA DRM modesetting didn't activate — do NOT proceed to Hyprland yet. Check dmesg for nvidia_drm errors.

## 2. Launch Hyprland

Switch to TTY1 (Ctrl+Alt+F1). Fish will auto-start Hyprland via `start-hyprland`. If you're already on TTY1 logged in:

```bash
exec start-hyprland
```

## 3. Post-boot verification

```bash
# Wayland session is live
echo $WAYLAND_DISPLAY        # should be wayland-1 or similar
echo $XDG_SESSION_TYPE       # should be wayland

# Check both monitors detected
hyprctl monitors

# Confirm NVIDIA is the active render node (not just Intel)
hyprctl version              # sanity check Hyprland is running
```

## 4. Note external monitor name

`hyprctl monitors` output will show the real connector name for your external display (e.g. `DP-7`, `HDMI-A-1`, etc.). The laptop config currently hardcodes `DP-7` — update if different:

- `~/.config/hypr/hyprland.conf` (symlink → `~/projects/dotfiles/.config/hypr/hyprland-laptop.conf`)
  - Line 3: `monitor=DP-7,preferred,-2560x0,1`

## 5. Check XDG portals started

Portals have a 1s/2s sleep delay on OpenRC (no socket activation). Wait ~5s after login then:

```bash
# Both should be running
pgrep -a xdg-desktop-portal
```

If screensharing or file pickers don't work, portals likely didn't start. Re-run manually:

```bash
/usr/lib/xdg-desktop-portal-hyprland &
sleep 1 && /usr/lib/xdg-desktop-portal &
```

## 6. Flameshot

```bash
# Should already be running via exec-once
pgrep flameshot

# Test screenshot
flameshot gui
```

If it shows a black overlay or doesn't appear, check the window rules are active:

```bash
hyprctl clients | grep -A5 flameshot
```

## Known issues to watch for

- **Black screen**: If eDP-1 goes dark and external is also blank — TTY2 (Ctrl+Alt+F2), `killall Hyprland`, fix config, retry.
- **NVIDIA DRI path wrong**: If `AQ_DRM_DEVICES` path is stale (e.g. post-kernel-update), check `ls /dev/dri/by-path/` and update `~/.local/bin/start-hyprland`.
- **Waybar not rendering**: `pkill waybar && waybar &` or `Super+Shift+W` per the keybind.
- **No cursor on Wayland**: Check `XCURSOR_THEME=Adwaita` is set; install `xcursor-vanilla-dmz` if Adwaita isn't found.
