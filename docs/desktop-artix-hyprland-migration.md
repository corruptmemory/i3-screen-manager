# Desktop Migration: Arch → Artix + i3/X11 → Hyprland/Wayland

Migration guide for the desktop machine (godlike-linux).

**Hardware:** AMD Ryzen Threadripper 3970X (32C/64T), 125 GB RAM, AMD Radeon RX 7900 XT (Navi 31, amdgpu), single monitor DP-2 2560x1440@74.97Hz, 3× 1TB NVMe (nvme0=Windows, nvme1=Linux, nvme2=data)

**Current state:** Arch Linux, systemd, i3-wm + polybar + picom + dunst, PipeWire already installed

**Target state:** Artix Linux, OpenRC, Hyprland + waybar + mako

**Key advantage over laptop:** AMD GPU with single card. No hybrid graphics, no NVIDIA, no DRM device path juggling. amdgpu "just works" on Wayland — the entire NVIDIA section from the laptop migration doesn't apply here.

---

## Risk Areas (Read First)

1. **Arch → Artix is an OS reinstall.** Unlike the WM swap (which is reversible), changing the init system means either a fresh install or a risky in-place migration. Fresh install is recommended — `/home` is on a separate btrfs partition and survives.
2. **/home is 98% full (18 GB free of 718 GB).** This needs attention before or during the migration. If the install needs temp space on `/home`, you're in trouble.
3. **Windows dual boot** — GRUB + os-prober needs the same manual EFI mount trick documented in `docs/artix-laptop-setup.md`.
4. **btrfs** — Both `/` and `/home` are btrfs. Artix supports btrfs fine, but the installer may default to ext4. Ensure btrfs-progs is included in the install.
5. **The Hyprland part is the easy part.** Laptop learnings eliminate most gotchas. AMD GPU eliminates the rest. Focus your worry on the Artix transition.

---

## Phase 0: Pre-Migration Backup & Prep

### Critical data audit

- [ ] Push all git repos (check `~/projects/`, `~/ae/`, `~/bhf/`, `~/idpair/` etc.)
- [ ] Verify dotfiles repo is current (`~/projects/dotfiles/`)
- [ ] Back up any non-git data on `/home` that can't be recreated
- [ ] Export browser profiles / bookmarks if needed (Brave sync should handle this)
- [ ] Note rbw is cloud-synced (Bitwarden) — just needs `rbw register` + `rbw sync` post-install
- [ ] Export/note any cron jobs: `crontab -l`
- [ ] Save package list for reference:
  ```bash
  pacman -Qqe > ~/pkglist-explicit.txt
  pacman -Qqm > ~/pkglist-aur.txt
  ```

### Disk space triage

`/home` is at 98%. Before migrating:
```bash
# Find space hogs
du -sh ~/projects/* ~/ae ~/bhf ~/idpair ~/{.cache,.local} 2>/dev/null | sort -rh | head -20

# Common culprits:
# ~/.cache — often gigabytes of browser/build caches, safe to nuke
# ~/projects/*/node_modules — if any JS projects
# ~/.local/share/Trash — empty it
# Steam library — if games are installed
```

### Prepare Artix install media

Download Artix OpenRC ISO from https://artixlinux.org/download.php (base or XFCE live ISO for a GUI installer, or base for manual install). Write to USB.

### Document current state

```bash
# Partition layout (save this)
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID > ~/disk-layout.txt

# Kernel parameters
cat /proc/cmdline > ~/kernel-params.txt

# Active services
systemctl list-unit-files --state=enabled > ~/enabled-services.txt

# Network config
nmcli connection show > ~/network-connections.txt
```

---

## Phase 1: Artix Installation

### Partition plan

**Reuse existing layout — only wipe `/` (root).**

| Partition | Size | Current | Action |
|-----------|------|---------|--------|
| nvme1n1p1 | 150G | `/` (btrfs) | **Format** — fresh Artix root |
| nvme1n1p2 | 64G | swap | **Keep** — reuse |
| nvme1n1p3 | 718G | `/home` (btrfs) | **Keep** — mount as-is |
| nvme0n1p5 | 577M | `/boot` (vfat) | **Keep** — shared EFI partition |
| nvme0n1 (rest) | — | Windows | **Don't touch** |
| nvme2n1p1 | 932G | data? | **Don't touch** — verify what's on it first |

**WARNING:** Verify nvme2n1p1 contents before the install. It's unmounted currently — check what's on it:
```bash
sudo mkdir -p /mnt/nvme2 && sudo mount /dev/nvme2n1p1 /mnt/nvme2 && ls /mnt/nvme2
```

### Base installation

Follow the Artix wiki installation guide for OpenRC. Key steps that differ from Arch:

```bash
# Partition: only format nvme1n1p1
mkfs.btrfs -f /dev/nvme1n1p1

# Mount
mount /dev/nvme1n1p1 /mnt
mkdir -p /mnt/home /mnt/boot
mount /dev/nvme1n1p3 /mnt/home
mount /dev/nvme0n1p5 /mnt/boot

# Base packages — note: base-openrc, NOT base
basestrap /mnt base base-devel openrc elogind-openrc linux linux-firmware \
  btrfs-progs grub efibootmgr os-prober \
  networkmanager networkmanager-openrc \
  dbus dbus-openrc \
  fish git vim

# Generate fstab
fstabgen -U /mnt >> /mnt/etc/fstab

# Chroot
artix-chroot /mnt
```

### In chroot

```bash
# Timezone, locale, hostname
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "godlike-linux" > /etc/hostname

# User
useradd -m -G wheel,video,input -s /usr/bin/fish jim
passwd jim
# Edit /etc/sudoers — uncomment %wheel ALL=(ALL:ALL) ALL

# Enable services
rc-update add dbus default
rc-update add elogind default
rc-update add NetworkManager default

# GRUB — with os-prober for Windows
echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
# Carry over kernel params:
# Edit /etc/default/grub:
#   GRUB_CMDLINE_LINUX_DEFAULT="pcie_aspm=off loglevel=3 usbhid.mousepoll=1"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
# Mount Windows EFI before grub-mkconfig (os-prober 1.84+ doesn't auto-mount)
# The Windows EFI partition is nvme0n1p1 (100M, vfat)
mkdir -p /mnt/win-efi
mount /dev/nvme0n1p1 /mnt/win-efi
grub-mkconfig -o /boot/grub/grub.cfg
umount /mnt/win-efi

# Swap
echo "UUID=eb4954d6-dda4-4283-a919-e297150b750f none swap defaults 0 0" >> /etc/fstab
# Verify fstab has root, home, boot, and swap
```

### Reboot into Artix

```bash
exit  # leave chroot
umount -R /mnt
reboot
```

At this point you should have a working Artix CLI. Log in as jim, verify network:
```bash
ping -c1 archlinux.org
```

---

## Phase 2: Core System Packages

```bash
# AUR helper
git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si

# GPU — AMD is simple: mesa + vulkan
sudo pacman -S mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon libva-mesa-driver

# Audio — PipeWire on OpenRC
sudo pacman -S pipewire pipewire-audio pipewire-pulse pipewire-alsa \
  pipewire-openrc pipewire-pulse-openrc wireplumber wireplumber-openrc pavucontrol

# Enable PipeWire user services
rc-update add pipewire default --user
rc-update add pipewire-pulse default --user
rc-update add wireplumber default --user

# Fonts
sudo pacman -S ttf-jetbrains-mono-nerd
yay -S ttf-joypixels
# TX-02 (Berkeley Mono) — copy from backup or laptop:
#   scp -r jim@laptop:/usr/share/fonts/berkeley-mono/ /tmp/tx02
#   sudo cp -r /tmp/tx02 /usr/share/fonts/
#   fc-cache -f

# Essential tools
sudo pacman -S jq eza bat mpv ffmpeg brightnessctl playerctl \
  xdotool xclip xsel npm \
  kitty rofi wl-clipboard

# Password manager
yay -S rbw
pipx install rofi-rbw
# rbw register && rbw sync

# Solaar (mouse DPI)
sudo pacman -S solaar

# Power management — TLP handles CPU frequency scaling, PCIe PM, USB autosuspend
# Not critical on desktop but reduces heat and noise under light load
sudo pacman -S tlp tlp-openrc
sudo rc-update add tlp default
sudo rc-service tlp start
```

### Desktop-specific: it87 CMOS battery module

```bash
# The it87 module may need dkms on Artix (check if it's built into the kernel)
sudo modprobe it87
# If that works, persist it:
echo "it87" | sudo tee /etc/modules-load.d/it87.conf
# If it fails, install via dkms:
# yay -S it87-dkms-git
```

---

## Phase 3: Hyprland Installation

```bash
# Core Hyprland ecosystem
# NOTE: do NOT install hyprpaper — the stable package (0.8.3-4) is broken:
# it silently ignores its config file (confirmed via strace, GitHub issue open).
# Use swaybg instead (see exec-once in Phase 4).
sudo pacman -S hyprland hyprlock hypridle swaybg \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  waybar mako wlr-randr wayland-protocols

# Screenshot stack (learned from laptop)
sudo pacman -S grim
yay -S flameshot-git    # NOT stable flameshot — git version has native Wayland
yay -S satty            # backup annotator

# Misc tools the config uses
sudo pacman -S udiskie pamixer nm-applet
# nm-applet is from network-manager-applet package:
sudo pacman -S network-manager-applet

# Do NOT install xdg-desktop-portal-wlr or xdg-desktop-portal-gnome — they conflict
```

**Note:** No NVIDIA packages. No mkinitcpio module ordering. No `nvidia_drm modeset=1`. None of that applies — amdgpu has native KMS and DRM, always on.

---

## Phase 4: Hyprland Config (from dotfiles)

### Symlink desktop config

```bash
mkdir -p ~/.config/hypr ~/.config/waybar
ln -sf ~/projects/dotfiles/.config/hypr/hyprland-desktop.conf ~/.config/hypr/hyprland.conf
ln -sf ~/projects/dotfiles/.config/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf
# Note: hyprpaper.conf is NOT symlinked — we use swaybg instead (hyprpaper stable is broken)
ln -sf ~/projects/dotfiles/.config/waybar/config-desktop.jsonc ~/.config/waybar/config
```

### Config changes needed for Artix/OpenRC

The existing desktop config in dotfiles has systemd assumptions. These MUST be fixed before first boot:

#### 1. dbus-update-activation-environment — drop `--systemd`

```
# OLD (lines 31, 37):
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY ...
exec-once = dbus-update-activation-environment --systemd PATH

# NEW:
exec-once = dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = dbus-update-activation-environment PATH
```

#### 2. Remove systemctl --user import-environment

```
# OLD (line 40):
exec-once = systemctl --user import-environment QT_QPA_PLATFORMTHEME

# DELETE this line entirely — not needed on OpenRC
```

#### 3. Add OpenRC portal startup (no socket activation)

```
# ADD — portals need manual launch on OpenRC (learned from laptop)
exec-once = sleep 1 && /usr/lib/xdg-desktop-portal-hyprland &
exec-once = sleep 2 && /usr/lib/xdg-desktop-portal &
```

#### 4. Add polkit agent

```
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
```

#### 5. Add session env vars (learned from laptop)

```
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = ELECTRON_OZONE_PLATFORM_HINT,wayland
env = GIO_USE_VFS,local
```

#### 6. Update flameshot window rules (learned from laptop)

The old `windowrule` single-line syntax still works, but flameshot needs specific treatment:

```
# REPLACE the old flameshot rule with:
windowrule {
    name = flameshot
    match:class = ^(flameshot)$
    float = on
    fullscreen = true
    no_anim = true
}
```

Run flameshot as a daemon:
```
exec-once = flameshot
```

**Do NOT** set `useGrimAdapter=true` — flameshot-git has native Wayland and breaks with it.

#### 7. Wallpaper — use swaybg, not hyprpaper

Replace any `exec-once = hyprpaper` in the config with swaybg:

```
# In exec-once section:
exec-once = swaybg -i ~/projects/wallpapers/0003.jpg -m stretch
```

hyprpaper stable (0.8.3-4) silently ignores its config file entirely. strace confirms it never opens `hyprpaper.conf`. The GitHub issue is open but not fixed in stable. swaybg is simpler and reliable.

#### 8. Update waybar config

The desktop waybar config uses `sway/workspaces` and `sway/window` — these need to be Hyprland modules:

```jsonc
// OLD:
"modules-left": ["sway/workspaces", "sway/window"],

// NEW:
"modules-left": ["hyprland/workspaces", "hyprland/window"],
```

Also remove the `wlr/workspaces` block (dead config).

#### 9. hypridle — remove battery/suspend check

The desktop has no battery. The existing hypridle.conf has a `systemctl suspend` call gated on battery state — remove or adapt:

```
# Desktop: just DPMS off after 5 min, no suspend
general {
    lock_cmd = hyprlock
    ignore_dbus_inhibit = false
}

listener {
    timeout = 300
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}

# Optional: lock after 10 min
listener {
    timeout = 600
    on-timeout = hyprlock
}
```

#### 10. Replace hy3 with built-in layout

The desktop config uses `layout = hy3` — a third-party plugin that's uncomfortably quirky. **Don't use it.** Switch to a built-in layout:

```
# Change in general section:
layout = master    # or dwindle — laptop uses master
```

Hyprland's built-in grouping (`togglegroup`, `changegroupactive`, `movewindoworgroup` — already in the keybinds) provides the i3-style grouped-window workflow without hy3.

#### 11. Groupbar color requires `gradients = true` (counter-intuitive)

If you use Hyprland groups, the groupbar `col.active` / `col.inactive` colors **only render if `gradients = true`**, even if you want solid colors. Without it the bar is fully transparent regardless of what you set. This is Hyprland issue #9352, present in 0.54.x.

```
group {
    groupbar {
        gradients = true      # REQUIRED for any color to show — not just gradients
        height = 20
        indicator_height = 0  # hides the thin indicator bar at the bottom of the groupbar
        gaps_in = 0
        gaps_out = 0
        col.active = rgb(2d4d6e)
        col.inactive = rgb(1a1a2e)
    }
}
```

#### 11. Fix application references

```
# nautilus → probably not installed, change to thunar or remove
$fileManager = thunar

# firefox → brave (if that's what you're using on desktop)
# Update any exec-once that launches firefox

# morgen — keep or remove depending on whether you install it
```

### Create start-hyprland script

```bash
cat > ~/.local/bin/start-hyprland << 'SCRIPT'
#!/usr/bin/env bash

# Desktop start-hyprland — much simpler than laptop (no NVIDIA)

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Artix OpenRC does not export DBUS_SESSION_BUS_ADDRESS — apps (Brave, Azure
# Storage Explorer, rbw) will report "no secret store" without this.
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# gnome-keyring: start daemon and pick up SSH_AUTH_SOCK + GNOME_KEYRING_CONTROL.
# Must use eval, not just call it — the daemon prints exports that need sourcing.
eval $(gnome-keyring-daemon --start --components=secrets,pkcs11,ssh)
export GNOME_KEYRING_CONTROL
export SSH_AUTH_SOCK

# Vulkan ICD — AMD
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json:/usr/share/vulkan/icd.d/radeon_icd.i686.json

# VA-API — AMD
export LIBVA_DRIVER_NAME=radeonsi

# GTK file dialog fix (avoids 25s hang in GTK open/save dialogs)
export GIO_USE_VFS=local

# Use the system-installed /usr/bin/start-hyprland wrapper, not Hyprland directly.
# Calling Hyprland directly skips its instance setup and triggers a
# "launched without start-hyprland" warning on every startup.
exec /usr/bin/start-hyprland
SCRIPT
chmod +x ~/.local/bin/start-hyprland
```

`★ Insight ─────────────────────────────────────`
Compare this to the laptop's start-hyprland: no `AQ_DRM_DEVICES`, no `readlink` DRI path resolution, no `__GLX_VENDOR_LIBRARY_NAME`, no `GBM_BACKEND`, no `NVD_BACKEND`. AMD GPU simplifies the launcher from ~20 lines of NVIDIA workarounds to a handful of straightforward exports.
`─────────────────────────────────────────────────`

### Fish auto-start

Add to `~/.config/fish/config.fish`:

```fish
# Auto-start Hyprland on TTY1
if test (tty) = /dev/tty1; and not set -q WAYLAND_DISPLAY
    exec start-hyprland
end
```

---

## Phase 5: Application Restoration

```bash
# Browser
sudo pacman -S brave-bin   # or: yay -S brave-bin

# Development
sudo pacman -S emacs sublime-text-4   # or from AUR
# GoLand — install via JetBrains Toolbox or AUR

# Chat apps
sudo pacman -S slack-desktop discord
yay -S keybase-bin

# Zoom
yay -S zoom

# Claude Code
# npm already installed in Phase 2
# npm i -g @anthropic-ai/claude-code   # or however you install it

# Other tools from laptop setup
sudo pacman -S sshpass calcurse nsxiv
yay -S aws-cli-v2

# Azure CLI (same recipe as laptop — direct .pkg.tar.zst download)
# See docs/artix-laptop-setup.md → "Azure CLI on Artix"
```

### Restore projects

If `/home` was kept intact, all `~/projects/`, `~/ae/`, `~/bhf/`, `~/idpair/` should still be there. Verify:
```bash
ls ~/projects/ ~/ae/ ~/bhf/ ~/idpair/ 2>/dev/null
```

If `/home` was reformatted, restore from backup.

---

## Phase 6: Desktop-Specific Setup

### CMOS battery monitoring (i3-cmos-battery)

```bash
# Verify it87 module loads
sudo modprobe it87
cat /sys/class/hwmon/hwmon*/name | grep -n it87

# If working, the i3-cmos-battery script should work as-is
# TODO: port to waybar custom module (currently polybar)
```

### Mouse DPI (solaar + i3-mouse-setup)

```bash
# solaar should auto-detect Logitech receivers
solaar show

# i3-mouse-setup reads saved DPI from ~/.config/i3-mouse-manager/dpi
# This script is X11-independent (uses solaar CLI), so it works on Wayland
```

### Monitor setup

Single monitor, simple:
```
monitor = DP-2, 2560x1440@74.97, auto, 1
```

Verify the actual output name after first Hyprland boot — it might be `DP-1` or `DP-3` under Wayland (connector names can differ from X11's `xrandr` names):
```bash
hyprctl monitors
```

### Kernel parameters

Ensure GRUB carries over the desktop-specific params:

```
GRUB_CMDLINE_LINUX_DEFAULT="pcie_aspm=off loglevel=3 usbhid.mousepoll=1"
```

- `pcie_aspm=off` — GPU stability (AMD RX 7900 XT, documented in desktop-maint)
- `usbhid.mousepoll=1` — 1000Hz mouse polling (usbhid built-in, modprobe.d won't work)

---

## Phase 7: First Boot Verification

```bash
# 1. Wayland session
echo $WAYLAND_DISPLAY        # wayland-1 or similar
echo $XDG_SESSION_TYPE       # wayland

# 2. GPU
hyprctl monitors             # should show DP-? at 2560x1440@74.97
vulkaninfo --summary | head  # should show radeonsi

# 3. Audio
wpctl status                 # should show real sinks, not "Dummy Output"
pactl info | grep "Server Name"  # PipeWire

# 4. Portals
pgrep -a xdg-desktop-portal  # both portal and portal-hyprland running

# 5. Flameshot
flameshot gui                # should show annotation overlay

# 6. D-Bus / libsecret
echo $DBUS_SESSION_BUS_ADDRESS   # should be set
rbw unlock                       # should prompt, not error about missing secret store

# 7. VA-API
vainfo                       # should show radeonsi profiles

# 8. CMOS battery
i3-cmos-battery               # should print voltage (desktop-specific)
```

---

## Phase 8: Waybar Module Migration

Port the polybar modules to waybar. The desktop waybar config is minimal (clock, audio, tray). Consider adding:

| Current polybar module | Waybar equivalent | Priority |
|---|---|---|
| `i3` workspaces | `hyprland/workspaces` | **Done** (in config) |
| `xwindow` | `hyprland/window` | **Done** (in config) |
| `pulseaudio` | `pulseaudio` | **Done** (in config) |
| `clock` | `clock` | **Done** (in config) |
| `tray` | `tray` | **Done** (in config) |
| `cpu` | `cpu` | Nice to have |
| `memory` | `memory` | Nice to have |
| `temperature` | `temperature` | Nice to have |
| CMOS battery | `custom/cmos-battery` | Port later |

CMOS battery waybar module (custom):
```jsonc
"custom/cmos-battery": {
    "exec": "i3-cmos-battery --short",
    "interval": 21600,
    "format": "CMOS: {}"
}
```

---

## Phase 9: i3-screen-manager Considerations

The desktop is single-monitor, so `i3-screen-manager` is less critical here than on the laptop. However:

- `i3-mouse-setup` / `i3-mouse-rofi` — these use `solaar` (X11-independent) and should work as-is
- `i3-cmos-battery` — reads `/sys/class/hwmon/`, X11-independent, works as-is
- `i3-screen-manager` / `i3-screen-rofi` — not needed unless you add an external monitor to the desktop
- `i3-keyboard-rofi` — needs porting from `setxkbmap` to `hyprctl keyword input:kb_layout` (laptop already did this)

---

## Phase 10: Post-Migration Cleanup

- [ ] Remove i3-wm, polybar, picom, dunst packages (defer until stable)
- [ ] Update `~/.xinitrc` to launch Hyprland as fallback (or remove)
- [ ] Update CLAUDE.md in `i3-screen-manager` repo
- [ ] Update `docs/artix-laptop-setup.md` with any new learnings
- [ ] Verify Brave sync restored bookmarks/extensions
- [ ] Test Zoom screen sharing
- [ ] Test Steam (if applicable)

---

## Laptop Gotchas That DON'T Apply Here

For reference — these were laptop issues that the desktop doesn't have:

| Laptop gotcha | Why N/A on desktop |
|---|---|
| NVIDIA DRM modeset, mkinitcpio module order | AMD GPU — native KMS always on |
| `AQ_DRM_DEVICES` colon-splitting | Single AMD GPU, no device selection |
| `__GLX_VENDOR_LIBRARY_NAME=nvidia` | No NVIDIA |
| `GBM_BACKEND=nvidia-drm` breaking Firefox | No NVIDIA |
| `i915` must be first in MODULES | No Intel GPU |
| Electron 1-minute stall at boot | Intel GPU race condition, N/A |
| External monitor 30fps on hybrid | Single GPU |
| NVIDIA RTD3 power management / laptop runs warm | No NVIDIA — amdgpu handles power states natively via runtime PM without configuration |
| Touchpad configuration | Desktop, no touchpad |
| Lid switch handling | Desktop, no lid |
| Battery in hypridle | Desktop, no battery |
| SOF firmware for audio | Threadripper uses standard HD Audio |
| iwd wifi backend | Desktop is wired only |

## Laptop Gotchas That DO Apply Here

| Gotcha | Desktop equivalent |
|---|---|
| `dbus-update-activation-environment --systemd` → drop `--systemd` | Same fix |
| `systemctl --user` calls fail on OpenRC | Same — use `exec-once` or OpenRC user services |
| `DBUS_SESSION_BUS_ADDRESS` not set on OpenRC | Same — set in `start-hyprland` |
| gnome-keyring: just setting `DBUS_SESSION_BUS_ADDRESS` is not enough | Must `eval $(gnome-keyring-daemon --start ...)` and export `SSH_AUTH_SOCK` + `GNOME_KEYRING_CONTROL`. Without this, Brave and Azure Storage Explorer report "no secret store" even when the bus address is correct. |
| Portal startup needs sleep delays (no socket activation) | Same — `sleep 1 && portal-hyprland`, `sleep 2 && portal` |
| `xdg-desktop-portal-gtk` needed for Screenshot portal Access interface | Same |
| Flameshot needs `float + fullscreen + no_anim` window rules | Same. No `suppress_event = fullscreen` — that causes the returning window to fullscreen after flameshot closes. |
| Use `flameshot-git`, NOT stable; don't set `useGrimAdapter=true` | Same |
| hyprpaper stable broken — use swaybg | Same — hyprpaper 0.8.3-4 never reads its config on Artix |
| Groupbar `gradients = true` required for any color to render | Same — Hyprland 0.54.x issue #9352 |
| `exec Hyprland` in custom start script → "launched without start-hyprland" | Use `exec /usr/bin/start-hyprland` instead — it's a wrapper binary that sets up the instance correctly |
| Rofi works on Wayland (2.0+ has native Wayland) | Same |
| `GIO_USE_VFS=local` for GTK file dialog fix | Same |
| Mako default font is `monospace 10` — small and ugly | `font=Adwaita Sans Light 12` in `~/.config/mako/config`. Mako uses Pango — any installed font works. |
| Sub-pixel rendering not enabled by default | `sudo ln -sf /usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/ && fc-cache -f`. Verify: `fc-match --verbose "Adwaita Sans" \| grep rgba` → `rgba: 1`. Desktop at scale 1.0 benefits more than laptop at 1.25. |
| Waybar network module shows `lo` (loopback) | Desktop is wired — set `"interface": "en*"` (or the specific NIC name). Use `{ifname}` in `format-ethernet`. |

---

## References

- [Artix installation guide](https://wiki.artixlinux.org/Main/Installation)
- [Laptop Artix setup](artix-laptop-setup.md) — package lists, OpenRC service mapping, audio setup
- [Laptop Hyprland migration](hyprland-migration.md) — detailed gotchas, flameshot rules, portal setup
- [Hyprland first boot checklist](hyprland-first-boot.md) — verification steps (laptop-focused but principles apply)
- [Dotfiles repo](~/projects/dotfiles/) — existing Hyprland desktop config
- [Wayland compositor comparison](wayland-compositor-comparison.md) — why Hyprland
