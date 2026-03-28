# Artix Linux Laptop Setup

Setup notes for the laptop migration from Arch Linux to Artix Linux (OpenRC).

**Hardware:** ThinkPad, Intel i7-12800H (14C/28T), 64 GB RAM, Intel Iris Xe + NVIDIA RTX 3050 Ti Mobile, Intel AX211 wifi

## Installed Packages

### GPU & Display

```bash
# NVIDIA proprietary (open kernel modules) + OpenRC service
sudo pacman -S nvidia-open nvidia-utils nvidia-settings nvidia-utils-openrc

# Intel GPU
sudo pacman -S mesa vulkan-intel intel-media-driver

# X11 (XLibre is the default X server on Artix)
sudo pacman -S xlibre-xserver xlibre-input-libinput xlibre-xserver-common xlibre-input-evdev

# X11 utilities
sudo pacman -S xorg-xinit xorg-xinput xorg-xrandr xorg-xrdb xorg-xset xorg-xprop xorg-xdpyinfo xorg-setxkbmap xorg-xmodmap
```

### Window Manager & Desktop

```bash
sudo pacman -S i3-wm i3status i3lock rofi polybar picom dunst feh flameshot kitty
```

### Utilities

```bash
sudo pacman -S xdotool xclip xsel jq brightnessctl playerctl libglvnd
```

### Fonts

```bash
# Nerd Font (polybar icons, rofi button glyphs)
sudo pacman -S ttf-jetbrains-mono-nerd

# Emoji (polybar uses emoji for battery, volume, etc.)
yay -S ttf-joypixels
```

- **TX-02 (Berkeley Mono)** — copied from `/mnt/fonts/TX-02` to `/usr/share/fonts/`
- **User fonts** — copied from `/mnt/jim/.local/share/fonts/` to `~/.local/share/fonts/`

After installing fonts: `fc-cache -f`

**Rofi font:** The global rofi config (`~/.config/rofi/global/rofi.rasi`) should use `TX-02` not `Inter Regular`.

## Config Files Ported

All configs sourced from the old Arch backup at `/mnt/jim/`:

| Config | Source | Changes |
|--------|--------|---------|
| `~/.xinitrc` | `/mnt/jim/.xinitrc` | Removed: `gnome-keyring-daemon`, systemd env export lines. Kept: touchpad settings, keyboard layout, Vulkan ICD, `GIO_USE_VFS=local` |
| `~/.Xresources` | Direct copy | None |
| `~/.config/i3/config` | `/mnt/jim/.config/i3/config` | Removed: `nm-applet` (using connman), `dex` (not in Artix repos), `polkit-gnome`, systemd D-Bus env exports |
| `~/.config/polybar/config.ini` | `/mnt/jim/.config/polybar/config.ini` | Removed hardcoded `hwmon-path` (using `zone-type` instead) |
| `~/.config/kitty/kitty.conf` | Direct copy | None |
| `~/.config/dunst/dunstrc` | Direct copy | None |
| `~/.config/rofi/` | Direct copy (full directory) | None |
| `~/.config/picom/picom.conf` | New (old Arch had no picom config) | `backend = "glx"; vsync = true; unredir-if-possible = false;` |

## Systemd → OpenRC Differences

| systemd | OpenRC equivalent |
|---------|-------------------|
| `systemctl enable <service>` | `rc-update add <service> default` |
| `systemctl start <service>` | `rc-service <service> start` |
| `systemctl status <service>` | `rc-service <service> status` |
| `systemctl --user import-environment` | Not needed — `.xinitrc` env vars inherited naturally |
| `dbus-update-activation-environment --systemd` | Not needed on elogind |
| `systemd-inhibit` | Needs replacement (used by `i3-screen-manager` for clamshell lid-switch blocking) |
| `journalctl` | Check `/var/log/` or init-specific logs |

## Networking: NetworkManager + iwd

Using NetworkManager with iwd backend for wifi. Replaced ConnMan+wpa_supplicant — NM is far better for a laptop that roams between networks (nm-applet tray icon, `nmcli`/`nmtui` CLI tools).

### Setup

```bash
# Install
sudo pacman -S networkmanager networkmanager-openrc iwd iwd-openrc network-manager-applet

# Configure NM to use iwd backend (/etc/NetworkManager/NetworkManager.conf):
#   [device]
#   wifi.backend=iwd

# Enable services, remove old connman
sudo rc-update add iwd default
sudo rc-update add NetworkManager default
sudo rc-update del connmand sysinit

# i3 config autostart:
#   exec --no-startup-id nm-applet
```

### USB-C Ethernet

Works automatically — NetworkManager auto-connects wired interfaces. Kernel modules for common USB adapters (`cdc_ether`, `r8152`, `ax88179_178a`, `cdc_ncm`) are all present.

### Quick reference

```bash
nmcli device wifi list                                    # scan networks
nmcli device wifi connect "Name" password "pass"          # connect
nmcli connection show                                     # saved connections
nmtui                                                     # interactive TUI
```

### Why iwd over wpa_supplicant

| | wpa_supplicant | iwd |
|---|---|---|
| Config location | `/etc/wpa_supplicant/` | `/var/lib/iwd/` |
| Saved networks | One big conf file | One file per network |
| Connect speed | Slower | Noticeably faster |
| Memory | Heavier | Lighter |
| Enterprise (802.1X) | Mature | Still catching up |
| Roaming | Basic | Better (queries neighbor APs) |

Only downside: weaker WPA2-Enterprise support (corporate/eduroam networks).

## Audio: PipeWire

```bash
# Core PipeWire + OpenRC user services
sudo pacman -S pipewire pipewire-audio pipewire-pulse pipewire-alsa \
  pipewire-openrc pipewire-pulse-openrc wireplumber wireplumber-openrc pavucontrol

# SOF firmware (required for Intel HDA on 12th gen+ ThinkPads)
sudo pacman -S sof-firmware

# Enable as user services (start automatically on login via elogind)
rc-update add pipewire default --user
rc-update add pipewire-pulse default --user
rc-update add wireplumber default --user

# For polybar volume control module:
yay -S pulseaudio-control
```

**IMPORTANT:** `wireplumber-openrc` is a separate package from `wireplumber`. Without it, WirePlumber has no OpenRC user service and never starts — PipeWire will only show a "Dummy Output" sink with no real audio devices. Verify with `wpctl status` after login; if you only see "Dummy Output", WirePlumber isn't running.

**SOF firmware:** Intel laptops with Alder Lake (12th gen) and newer use SOF (Sound Open Firmware) for the HDA audio controller. Without `sof-firmware`, the kernel can't initialize the audio device at all. Reboot after installing.

PipeWire-Pulse provides full PulseAudio compatibility — `pactl`, `pavucontrol`, and polybar's `pulseaudio` and `pulseaudio-control-input` modules all work transparently.

## TODO

- [x] Test `startx` — verify X11, i3, NVIDIA PRIME all work
- [ ] Install and configure `rbw` + `rofi-rbw` (Bitwarden)
- [ ] Install Brave browser
- [x] Install PipeWire/WirePlumber for audio
- [x] Install sof-firmware for Intel HDA audio
- [x] Install wireplumber-openrc (WirePlumber user service)
- [x] Install ttf-joypixels for polybar emoji icons
- [x] Fix rofi font (TX-02 instead of Inter Regular)
- [x] Copy volumecontrol.sh to ~/.local/bin/
- [x] Replace ConnMan+wpa_supplicant with NetworkManager+iwd
- [x] Install solaar for mouse DPI
- [x] Add user to `video` group (brightnessctl backlight access)
- [x] Add user to `input` group (solaar, direct input device access)
- [ ] Set up `i3-screen-manager` and `i3-screen-rofi` symlinks
- [ ] Replace `systemd-inhibit` in `i3-screen-manager` for clamshell mode
- [ ] Restore projects from backup
