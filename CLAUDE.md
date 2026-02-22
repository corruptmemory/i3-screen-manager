# i3-screen-manager

Bash scripts for managing external displays and mouse settings on i3/X11, plus keyboard layout toggling.

## Environment

- **Distro:** Arch Linux
- **Package manager:** `yay` (AUR-enabled wrapper around pacman)
- **Privileges:** `sudo` is available from the user account
- **Machines:** Laptop and desktop, both running i3/X11 on Arch

## Architecture

Scripts, no build step:
- `i3-screen-manager` — CLI that wraps `xrandr` and `i3-msg` for display management
- `i3-screen-rofi` — Rofi menu frontend that calls `i3-screen-manager`
- `i3-mouse-setup` — Login-time script that applies saved mouse DPI via `solaar`
- `i3-mouse-rofi` — Rofi menu for mouse DPI adjustment (saves choice for persistence)
- `~/.local/bin/i3-keyboard-rofi` — Standalone rofi toggle for laptop vs external keyboard layout

## Key Design Decisions

- **Internal display is hardcoded as `eDP-1`** — standard for modern Intel laptop panels
- **External display is auto-detected** — finds first connected non-internal output via `xrandr`
- **Lid state path is discovered dynamically** — ACPI names vary (`LID`, `LID0`, etc.) across boots
- **Safe defaults** — if lid state can't be detected, assume closed (refuse disconnect rather than risk black screen)
- **Clamshell uses `systemd-inhibit`** — holds a `handle-lid-switch` block lock via a background `sleep infinity` process, PID tracked in `/tmp/i3-screen-manager-inhibit.pid`
- **Disconnect enables internal BEFORE disabling external** — no window where zero displays are active
- **DPI adjustment via `Xft.dpi`** — clamshell sets 96 (external), disconnect restores 120 (laptop). Custom DPI via CLI arg or rofi picker. Only affects new windows; `Xft.dpi` is overridden in the live X resource DB, `.Xresources` is never modified
- **Mouse DPI via solaar** — `i3-mouse-setup` auto-detects Logitech mice at login and applies saved DPI from `~/.config/i3-mouse-manager/dpi`. `i3-mouse-rofi` provides on-the-fly adjustment that persists across reboots

## Testing

No automated tests. Test manually with an external monitor:
1. `i3-screen-manager extend-right` — external should light up
2. `i3-screen-manager mirror` — both screens same content
3. `i3-screen-manager clamshell` — laptop off, external only, close lid safely
4. `i3-screen-manager disconnect` (lid closed) — should refuse
5. Open lid, `i3-screen-manager disconnect` — should restore laptop screen
6. `i3-screen-manager dpi` — rofi picker should appear, selecting a value changes `Xft.dpi`
7. `i3-screen-manager clamshell 108` — clamshell with custom DPI

## Common Issues

- **Black screen on disconnect**: Usually means lid was closed and eDP-1 couldn't activate. The lid guard should prevent this now.
- **Workspace move errors**: `"No output matched"` from i3-msg is usually harmless — workspace was already on the target output.
- **External not detected**: Check `xrandr` — the output might use a different name than expected. Nvidia outputs follow `*-N-N` naming pattern (e.g., `HDMI-1-0`, `DP-1-0`).
- **Mouse poll rate config ignored**: On Arch's stock kernel, `usbhid` is built-in (not a module), so `/etc/modprobe.d/` has no effect. Use `usbhid.mousepoll=1` in GRUB's `GRUB_CMDLINE_LINUX_DEFAULT` instead, then `grub-mkconfig -o /boot/grub/grub.cfg`.
- **xorg.conf.d TargetRefresh ignored**: The `TargetRefresh` monitor option doesn't work reliably with all drivers (e.g., amdgpu). Use an explicit `xrandr --rate` call in `~/.xinitrc` instead.
