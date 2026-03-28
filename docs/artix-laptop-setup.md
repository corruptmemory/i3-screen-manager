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

- **TX-02 (Berkeley Mono)** — copied from `/mnt/fonts/TX-02` to `/usr/share/fonts/`
- **JetBrains Mono Nerd** — `sudo pacman -S ttf-jetbrains-mono-nerd`
- **User fonts** — copied from `/mnt/jim/.local/share/fonts/` to `~/.local/share/fonts/`

After installing fonts: `fc-cache -f`

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

## Networking: ConnMan

Currently using ConnMan with `wpa_supplicant` for wifi.

### USB-C Ethernet

Works automatically — connman's `DefaultAutoConnectTechnologies` includes `ethernet` by default. Kernel modules for common USB adapters (`cdc_ether`, `r8152`, `ax88179_178a`, `cdc_ncm`) are all present. Plug in a USB-C Ethernet adapter and it gets DHCP automatically.

### Switching to iwd (from wpa_supplicant)

**Why:** iwd is faster to connect, lighter, cleaner config, better roaming. The only downside is weaker WPA2-Enterprise support (corporate/eduroam networks).

**IMPORTANT: Do this on-device, not over SSH.** If the swap fails you lose wifi and your only connection.

**Steps:**

```bash
# 1. Install iwd
sudo pacman -S iwd iwd-openrc

# 2. Note your current wifi network name and password
#    (you'll need to reconnect after the swap)
connmanctl services    # shows connected network

# 3. Tell connman to use iwd instead of wpa_supplicant
#    Edit /etc/connman/main.conf, add under [General]:
#    Wifi = iwd

# 4. Stop wpa_supplicant, start iwd
sudo rc-service wpa_supplicant stop
sudo rc-update del wpa_supplicant default
sudo rc-service iwd start
sudo rc-update add iwd default

# 5. Restart connman so it picks up iwd
sudo rc-service connmand restart

# 6. Reconnect to wifi
#    iwd has its own interactive tool:
iwctl
#    > station wlan0 scan
#    > station wlan0 get-networks
#    > station wlan0 connect "YourNetworkName"
#    > exit

#    Or let connman handle it:
connmanctl scan wifi
connmanctl services
connmanctl connect wifi_<hash>_managed_psk

# 7. Verify connectivity
ping -c 3 archlinux.org

# 8. If everything works, optionally remove wpa_supplicant:
sudo pacman -R wpa_supplicant
```

**Rollback (if wifi breaks):**

```bash
# Undo the connman config change
sudo sed -i '/^Wifi = iwd/d' /etc/connman/main.conf

# Stop iwd, restart wpa_supplicant
sudo rc-service iwd stop
sudo rc-update del iwd default
sudo rc-service wpa_supplicant start
sudo rc-update add wpa_supplicant default
sudo rc-service connmand restart
```

**Config comparison:**

| | wpa_supplicant | iwd |
|---|---|---|
| Config location | `/etc/wpa_supplicant/` | `/var/lib/iwd/` |
| Saved networks | `wpa_supplicant.conf` (one big file) | One file per network (`NetworkName.psk`) |
| Connect speed | Slower | Noticeably faster |
| Memory | Heavier | Lighter |
| Enterprise (802.1X) | Mature | Still catching up |
| Roaming | Basic | Better (queries neighbor APs) |

### Alternative: NetworkManager

If connman becomes annoying, NetworkManager is available on Artix:

```bash
sudo rc-service connmand stop
sudo rc-update del connmand default
sudo pacman -S networkmanager networkmanager-openrc network-manager-applet
sudo rc-update add NetworkManager default
sudo rc-service NetworkManager start
```

Then add `exec --no-startup-id nm-applet` back to the i3 config. Provides `nmcli`/`nmtui` CLI tools and the system tray applet.

## Audio: PipeWire

```bash
sudo pacman -S pipewire pipewire-audio pipewire-pulse pipewire-alsa \
  pipewire-openrc pipewire-pulse-openrc wireplumber pavucontrol

# Enable as user services (start automatically on login via elogind)
rc-update add pipewire default --user
rc-update add pipewire-pulse default --user

# WirePlumber is auto-launched by PipeWire as session manager — no separate service needed

# For polybar volume control module:
yay -S pulseaudio-control
```

PipeWire-Pulse provides full PulseAudio compatibility — `pactl`, `pavucontrol`, and polybar's `pulseaudio` and `pulseaudio-control-input` modules all work transparently.

## TODO

- [x] Test `startx` — verify X11, i3, NVIDIA PRIME all work
- [ ] Install and configure `rbw` + `rofi-rbw` (Bitwarden)
- [ ] Install Brave browser
- [x] Install PipeWire/WirePlumber for audio
- [ ] Replace `systemd-inhibit` in `i3-screen-manager` for clamshell mode
- [ ] Try iwd swap (on-device)
- [ ] Install solaar for mouse DPI (if Logitech mouse used with laptop)
- [ ] Set up `i3-screen-manager` and `i3-screen-rofi` symlinks
- [ ] Restore projects from backup
