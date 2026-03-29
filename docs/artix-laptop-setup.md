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
sudo pacman -S eza bat yt-dlp mpv ffmpeg
sudo pacman -S postgresql postgresql-openrc
sudo pacman -S npm  # for npx / MCP servers
```

### Password Manager

```bash
# rbw (Bitwarden CLI) — install via cargo or AUR
yay -S rbw
# rofi-rbw — AUR often broken (upstream 503s); use pipx instead
pipx install rofi-rbw
# Then: rbw register && rbw sync
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

## Hardware Video Decoding (VA-API)

Intel Iris Xe uses the iHD driver (from `intel-media-driver`). Without explicitly setting the driver, VA-API falls back to the older i965 driver which may not work.

```bash
# ~/.xinitrc — add before startx
export LIBVA_DRIVER_NAME=iHD
```

**mpv config** (`~/.config/mpv/mpv.conf`):
```
hwdec=vaapi
hwdec-codecs=all
vo=gpu
gpu-api=opengl
gpu-context=x11
scale=ewa_lanczossharp
cscale=ewa_lanczossharp
```

Verify: `mpv --hwdec=vaapi <video>` — check OSD shows `VO: [gpu] ... (vaapi)`.

**ffmpeg** does not need extra config — it auto-detects VA-API when `LIBVA_DRIVER_NAME` is set. Use `-hwaccel vaapi` flag explicitly if needed for one-off encodes.

## Pacman Mirror Optimization

```bash
sudo pacman -S pacman-contrib

# Rank top 10 fastest Artix mirrors (takes ~30s)
sudo rankmirrors -n 10 /etc/pacman.d/mirrorlist | sudo tee /etc/pacman.d/mirrorlist.new
sudo mv /etc/pacman.d/mirrorlist.new /etc/pacman.d/mirrorlist
```

Note: `artix-mlg` is a developer tool for maintaining the official Artix mirror list — not for users. Use `rankmirrors` from `pacman-contrib` instead.

## Windows Dual Boot (os-prober)

os-prober 1.84+ no longer performs temporary mounts. The Windows EFI partition must be mounted before running `grub-mkconfig`.

```bash
# Add to /etc/fstab (noauto — only mount when needed):
# UUID=<windows-efi-uuid>  /mnt/win-efi  vfat  ro,noauto  0  0

# Then before grub-mkconfig:
sudo mkdir -p /mnt/win-efi
sudo mount /mnt/win-efi
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Find the UUID with `lsblk -o NAME,UUID | grep nvme`.

## Gnome-keyring / Brave Password Prompt

The "correct" fix (PAM integration in `/etc/pam.d/system-login`) does not work cleanly with `startx` because PAM starts before the X/D-Bus session exists. Two keyring daemon instances end up running.

**Pragmatic fix:** Open `seahorse` (GNOME Passwords & Keys), change the "Login" keyring password to blank. Brave stops prompting.

```bash
yay -S seahorse
```

## Systemd → OpenRC Differences

| systemd | OpenRC equivalent |
|---------|-------------------|
| `systemctl enable <service>` | `rc-update add <service> default` |
| `systemctl start <service>` | `rc-service <service> start` |
| `systemctl status <service>` | `rc-service <service> status` |
| `systemctl --user import-environment` | Not needed — `.xinitrc` env vars inherited naturally |
| `dbus-update-activation-environment --systemd` | Not needed on elogind |
| `systemd-inhibit` | `elogind-inhibit` (same flags, drop-in replacement) |
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

## Claude Code / MCP Setup

```bash
# npm required for npx (MCP servers use npx to run)
sudo pacman -S npm

# Playwright MCP — configure for Brave (NOT chromium/chrome):
# Edit ~/.claude/plugins/marketplaces/.../playwright/.mcp.json:
# {
#   "playwright": {
#     "command": "npx",
#     "args": ["@playwright/mcp@latest", "--executable-path", "/usr/bin/brave"]
#   }
# }

# playwright-cli (microsoft/playwright-cli) — for browser automation via extension bridge
# Config at ~/.playwright/cli.config.json:
# {
#   "browser": {
#     "browserName": "chromium",
#     "launchOptions": {
#       "executablePath": "/usr/bin/brave",
#       "headless": false
#     }
#   }
# }
# Connect: playwright-cli --config ~/.playwright/cli.config.json open --extension
# (Requires Playwright MCP Bridge extension installed in Brave)
```

**MCP tool permissions** must be enumerated explicitly in `.claude/settings.local.json` — the `mcp__*` wildcard in global settings does NOT suppress prompts. See global `~/.claude/CLAUDE.md` for the full list.

## TODO

- [x] Test `startx` — verify X11, i3, NVIDIA PRIME all work
- [x] Install and configure `rbw` + `rofi-rbw` (Bitwarden via pipx)
- [x] Install Brave browser
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
- [x] Set up `i3-screen-manager` and `i3-screen-rofi` symlinks
- [x] Replace `systemd-inhibit` with `elogind-inhibit` in `i3-screen-manager`
- [x] Configure VA-API hardware video decoding (iHD driver)
- [x] Optimize pacman mirrors with rankmirrors
- [x] Windows dual boot via os-prober (manual EFI mount required)
- [x] Fix gnome-keyring/Brave keyring prompt (blank password via seahorse)
- [x] Install postgresql + postgresql-openrc
- [x] Install npm (for npx/MCP servers)
- [x] Configure playwright-cli + Playwright MCP with Brave
- [x] Create Grayjay .desktop entry
- [x] Install eza, yt-dlp, bat, mpv
- [x] Restore projects from backup (`~/projects`, `~/ae`, `~/bhf`, `~/idpair`)
- [ ] `rbw register` + `rbw sync` (if not restored from backup)
- [ ] Install remaining CLI tools: `sshpass`, `calcurse`, `nsxiv`, `aws-cli-v2`
- [ ] Azure CLI (deferred — install via `pipx install azure-cli` when needed)
