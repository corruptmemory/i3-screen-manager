# i3 on `nomad-artix` — laptop setup

i3 4.25.1 as the laptop's X11 window manager, mirroring the desktop's
[i3 setup][desktop-outcome] (built 2026-07-20, "provisional complete success")
with laptop-specific deltas for dynamic external monitors, HiDPI, brightness,
touchpad, NVIDIA hybrid, and battery.

**Additive and reversible.** Hyprland (Wayland) and IceWM (X11) are untouched
and remain the fallbacks. Toggle from a TTY:
`start-hyprland` · `start-icewm-laptop` · `start-i3-laptop`.

[desktop-outcome]: 2026-07-20-i3-x11-setup.md
[icewm-laptop]:    2026-06-17-icewm-laptop-setup.md

## STATUS: SCAFFOLDED, PENDING TTY-BOOT VALIDATION (2026-07-21)

Config validates (`i3 -C` exit 0), all four machine-local symlinks in place,
i3-wm and polybar installed. Live-boot validation deferred until the user logs
out of the current session.

Everything below is either **directly reused from IceWM-laptop's already-live
infrastructure** (xorg.conf.d snippets, `i3-screen-manager` X11 backend,
`i3-keyboard-rofi` dual-mode, HiDPI recipe) or **derived from the desktop's
i3 config** (window management, launcher binds, chat quick-focus, wpctl audio,
flameshot float rule). The novel work is small: laptop-specific brightness
binds, single-bar polybar with a battery module, and the six-file scaffold.

## 0. What was reused vs. newly written

| Reused from | Kind |
|---|---|
| **`/etc/X11/xorg.conf.d/{10-nvidia-prime,40-touchpad}.conf`** (from IceWM-laptop) | System — X11-WM-agnostic |
| **`i3-screen-manager`, `i3-screen-rofi`, `i3-keyboard-rofi`** (dual-compositor) | User scripts — no changes needed |
| **`i3-mouse-setup`, `i3-mouse-rofi`** | Compositor-agnostic |
| **`i3-tailscale-rofi`, `laptop-monitor-x11.sh`, `x11-max-refresh`** | Already installed |
| **`~/.Xresources`** (Xft.dpi=120, from the i3 era, unchanged since) | User config |
| **`~/.config/flameshot/flameshot-{wayland,x11}.ini`** (laptop-flavored variants) | Symlinked to dotfiles |
| **HiDPI recipe** (Xresources + `xrandr --dpi` + Qt/GTK env vars) | Copied verbatim from `.xinitrc-icewm-laptop` |

| Newly written | Location |
|---|---|
| `dotfiles/.local/bin/start-i3-laptop` | pre-X bootstrap (mirror of `start-i3`) |
| `dotfiles/.xinitrc-i3-laptop` | X-side setup (mirror of `.xinitrc-i3`, no hardcoded xrandr) |
| `dotfiles/.config/i3/config-laptop` | i3 config (mirror of `config-desktop` with the SKIP list applied) |
| `dotfiles/.config/polybar/config-i3-laptop.ini` | Single-bar polybar for eDP-1 with battery module |
| Machine-local symlink `~/.config/i3/config` → dotfiles | one-time |
| Machine-local symlink `~/.local/share/applications/com.mitchellh.ghostty.desktop` → dotfiles | the Ghostty one-process-per-window override |

## 1. Deliberate skips (things that don't apply to a laptop)

Documented so it's clear this wasn't an oversight and someone re-porting doesn't
"restore" them.

| From `config-desktop` | Not ported because |
|---|---|
| `workspace 1..6 output DP-2` / `7..10 output HDMI-1` | Laptop is single-monitor most of the time; externals come/go. Fixed pins would fight the dynamic model. `i3-screen-manager` handles add/remove. |
| Two polybar bars (`i3-dp2`, `i3-hdmi1`) | Boot has one monitor. Single `[bar/i3-edp1]`. `pin-workspaces = true` is kept so adding a second bar later needs no changes here. |
| `xrandr --output DP-2 --pos 0x240 --output HDMI-1 --rotate right --pos 2560x0` in xinitrc | No fixed physical layout to hardcode. |
| `LIBVA_DRIVER_NAME=radeonsi` | AMD-only. Laptop uses `iHD` (Intel iGPU). |
| Audio-stack launches in xinitrc (`pipewire &`, `wireplumber &`, `pipewire-pulse &`) | Laptop runs these as OpenRC user services already. The IceWM Round-1 exercise showed adding them here creates a duplicate wireplumber and starves ALSA — only "Dummy Output" survives. Desktop needs them because godlike-artix has no user services for them. |
| `exec --no-startup-id i3-chat-layout` + `chat-layout.json` | User directive: no comms-stack wall "at least not in that form" while cooking on an alternate design. |
| `bindsym $mod+$alt+v exec xdtpaste.sh` | Script exists only on the desktop. Dropped rather than left dangling. |
| Wallpaper `~/projects/dt-wallpapers/0007.jpg` | Laptop uses `~/projects/wallpapers/earthshot.jpg` (matches Hyprland/IceWM). |
| `cmos-battery` polybar module | Reads it87 Super I/O chip on the desktop's motherboard; laptop has no such sensor. `i3-cmos-battery` exits silently on machines without it, so the module would render blank forever. |

## 2. Laptop-specific additions

| Added | Location |
|---|---|
| **Brightness binds** (`XF86MonBrightness{Up,Down}` → `brightnessctl s ±5%`) | `config-laptop` |
| **NVIDIA PRIME provider hookup** (`xrandr --setprovideroutputsource modesetting NVIDIA-G0`) | `.xinitrc-i3-laptop` |
| **Touchpad `xinput` calls** (belt-and-suspenders with `/etc/X11/xorg.conf.d/40-touchpad.conf`) | `.xinitrc-i3-laptop` |
| **`setxkbmap -option ctrl:nocaps,shift:both_capslock_cancel`** (laptop default; `i3-keyboard-rofi` toggles) | `.xinitrc-i3-laptop` |
| **HiDPI: `xrdb -merge` + `xrandr --dpi 120`** + Qt/GTK env vars in start-i3-laptop | `.xinitrc-i3-laptop` and `start-i3-laptop` |
| **`internal/battery`** polybar module for BAT0 | `config-i3-laptop.ini` |
| **Display / keyboard / tailscale rofi menus** (Super+BackSpace / Super+Ctrl+BackSpace / Super+Shift+N) | `config-laptop` |

## 3. The Ghostty tweak that HAD to come across

The desktop shipped a user-level shadow of `/usr/share/applications/com.mitchellh.ghostty.desktop`
at `~/.local/share/applications/com.mitchellh.ghostty.desktop`. Purpose:
**stop Ghostty running as a single shared "server" process** — one crash takes
every terminal window on the machine with it.

Upstream forces single-instance in three places, and all three must be
neutralised:

1. `Exec=/usr/bin/ghostty --gtk-single-instance=true` — dropped in the override.
2. `[Desktop Action new-window] Exec=... --gtk-single-instance=true` — dropped.
3. `/usr/share/dbus-1/services/com.mitchellh.ghostty.service` — neutralised by
   `DBusActivatable=false` in the override, since GIO prefers D-Bus activation
   over Exec whenever `DBusActivatable=true`.

`~/.config/ghostty/config` already carries `gtk-single-instance = false` (via
the dotfiles symlink), but a CLI flag OVERRIDES that config — so shadowing the
`.desktop` was the necessary second step. Now that the laptop has both, rofi
drun / xdg-open / app menu launches will all get a fresh Ghostty process per
window.

Verification (from a fresh shell after next login):
```bash
grep -H '^Exec=\|^DBusActivatable=' ~/.local/share/applications/com.mitchellh.ghostty.desktop
# expect: no --gtk-single-instance=true anywhere; DBusActivatable=false
```

## 4. Deploying to the laptop (this section is the runbook)

Assumes `git pull` on both `i3-screen-manager` and `dotfiles` is already done
(it is — the four new files were committed by this run).

```sh
# Prerequisites (installed by this run):
#   sudo pacman -S i3-wm polybar network-manager-applet
# (network-manager-applet is the correct package name for `nm-applet`;
#  don't be misled by the binary name.)

# Machine-local symlinks (one-time). ~/.config/i3/config gets moved aside
# rather than overwritten so the pre-Hyprland config from March is recoverable.
mv ~/.config/i3/config ~/.config/i3/config.pre-symlink-2026-07-21
ln -sf ~/projects/dotfiles/.config/i3/config-laptop         ~/.config/i3/config
ln -sf ~/projects/dotfiles/.local/bin/start-i3-laptop       ~/.local/bin/start-i3-laptop
ln -sf ~/projects/dotfiles/.xinitrc-i3-laptop               ~/.xinitrc-i3-laptop
ln -sf ~/projects/dotfiles/.local/share/applications/com.mitchellh.ghostty.desktop \
       ~/.local/share/applications/com.mitchellh.ghostty.desktop

# Validate before booting:
i3 -C  # must exit 0

# Live boot: log out to a TTY, then
start-i3-laptop
```

## 5. Post-boot validation checklist

After the first live boot, verify these — the equivalent of the desktop's §0
"Proven vs. assumed" table.

- [ ] i3 comes up; polybar visible with workspaces / xwindow / battery /
      pulseaudio / mic / memory / cpu / temperature / date / systray.
- [ ] Emoji glyphs render (audio icons, battery icons). If they're blank, the
      polybar log will say `Dropping unmatched character '🔉'` — the JoyPixels
      font-2 line is missing or the font isn't installed. `ttf-joypixels` from
      the AUR.
- [ ] `wpctl` volume keys move the level; `Control+F1` mic-mute toggles.
- [ ] Brightness keys move `/sys/class/backlight/*/brightness`.
- [ ] Touchpad: natural scroll + tap-to-click.
- [ ] Ghostty on `Super+Return` opens a **fresh process per window** (per
      §3): `pgrep -c ghostty` should climb by one for each new window, not stay
      at one shared server.
- [ ] `Super+space` rofi drun opens on the focused monitor.
- [ ] `Super+BackSpace` opens `i3-screen-rofi` (display layout menu).
- [ ] Plug an external monitor: `i3-screen-rofi → Extend Right` brings it up
      via xrandr; NVIDIA PRIME provider hookup either happens automatically at
      xinitrc time or via `i3-screen-manager`'s `ensure_nvidia_provider_x11`
      helper.
- [ ] `Super+Ctrl+BackSpace` opens `i3-keyboard-rofi` and can toggle laptop /
      external XKB layout.
- [ ] `Super+F1..F5` focus binds — F3/F4/F5 (Discord/Keybase/Slack) match if
      the app is open; F1/F2 (Messages/WhatsApp) match nothing unless the Brave
      PWAs are installed (that's the design — harmless no-ops).
- [ ] `Super+Shift+Escape` exits i3, `startx` returns, back at the TTY.

## 6. Files

All new files in this scaffold:

```
dotfiles/.local/bin/start-i3-laptop                          pre-X bootstrap
dotfiles/.xinitrc-i3-laptop                                  X-side setup
dotfiles/.config/i3/config-laptop                            i3 config (symlinked as ~/.config/i3/config)
dotfiles/.config/polybar/config-i3-laptop.ini                single-bar polybar for eDP-1
```

Untouched but critical to this working:

```
dotfiles/.local/share/applications/com.mitchellh.ghostty.desktop  (Ghostty override — brought across via symlink)
dotfiles/.config/flameshot/flameshot-laptop-{wayland,x11}.ini     (already live from IceWM-laptop work)
dotfiles/.config/ghostty/{config,themes/dracula-pro}              (already the ~/.config/ghostty symlink target)
/etc/X11/xorg.conf.d/{10-nvidia-prime,40-touchpad}.conf           (already installed by IceWM-laptop work)
~/.Xresources                                                     (Xft.dpi=120, from the March i3 era)
```

## 7. Backlog / watch items

- **`config-laptop` mirrors config-desktop's F1-F5 chat quick-focus verbatim** —
  F1 (Messages) and F2 (WhatsApp) are Brave PWA `crx_<app-id>` matches. If those
  PWAs are never installed on the laptop, those two binds silently match
  nothing (harmless). Cross-machine muscle memory holds either way.
- **Chat-workspace-wall (`i3-chat-layout`) not yet ported.** User is cooking on
  an alternate design; revisit when there's a design.
- **Second polybar bar on external monitor not automated.** Manual respawn via
  `polybar --config config-i3-laptop.ini <name>` for now; wire into
  `i3-screen-manager`'s extend-* path later if the pattern gets tiring.
- **Lid handler is manual** (same as under IceWM). `laptop-monitor-x11.sh`
  exists but is not `acpid`-wired. Enter clamshell explicitly via
  `i3-screen-rofi → Clamshell`. See `docs/2026-06-17-icewm-laptop-setup.md`
  § "Lid handling, deferred" for the deferred-auto-handling rationale.
- **Old pre-Hyprland `~/.config/i3/config`** preserved at
  `~/.config/i3/config.pre-symlink-2026-07-21` — rollback is one `mv`. Delete
  when comfortable.

## 8. Rollback

If this doesn't survive first boot or has some load-bearing bug:

```sh
# Restore the March i3 config (WM only — this doesn't undo the WM install)
rm ~/.config/i3/config
mv ~/.config/i3/config.pre-symlink-2026-07-21 ~/.config/i3/config

# Or, easier: just log out and use start-hyprland / start-icewm-laptop from
# the TTY. Neither was touched by this scaffold.
```

## 9. Round-1 execution log (2026-07-21)

First live boot from TTY. Working out of the gate:

- i3 comes up, wallpaper renders, rofi menus (`Super+space`,
  `Super+BackSpace`, `Super+Ctrl+BackSpace`) all resolve.
- Ghostty on `Super+Return`.

**Two issues found and fixed live:**

### 9a. No bar (any bar) — copy-deployment trap, third instance in a month

`~/.config/polybar/` was a real directory holding only the March
`config.ini` — `config-i3-laptop.ini` sat in dotfiles but was never
installed. Polybar's log made this obvious the moment we ran it in the
foreground:

```
polybar|error: Uncaught exception, shutting down: Failed to open config file
/home/jim/.config/polybar/config-i3-laptop.ini: No such file or directory
```

Same failure shape as ghostty (2026-07-19) and kitty (same day): file
committed to dotfiles, not live on the machine. Fix: `mv` the live dir
aside, `ln -s` dotfiles' `.config/polybar` into place. The old
`config.ini` (drifted from dotfiles since March — same third occurrence
during the desktop's own build recorded in
`docs/2026-07-20-i3-x11-setup.md` §5a) is preserved in
`~/.config/polybar.pre-symlink-2026-07-21/`.

**Broader sweep done in the same session** — see §10.

### 9b. `Super+y` opened the wrong Brave profile — profile-dir numbers are per-machine

`config-laptop` inherited `--profile-directory="Profile 3"` from
`config-desktop`. On the desktop that's the YouTube Premium account; on
the laptop `Profile 3` is "Personal" and `Profile 1` is
"Pennystinker@Gmail" (the actual YT Premium account here). Brave assigns
profile-dir numbers in the order profiles are added, so the mapping is
per-machine, not portable.

Fix: bump the arg to `Profile 1` in `config-laptop` and reload i3. Now
the config carries a comment explaining the trap plus the jq recipe to
verify on future machines:

```bash
jq -r '.profile.info_cache | to_entries[] | "\(.key): \(.value.name)"' \
    ~/.config/BraveSoftware/Brave-Origin/Local\ State
```

The laptop's IceWM keys file already had this right (`Profile 1`) — the
lesson is to port from the same-machine sibling config when possible,
not the different-machine sibling.

## 10. Broader dotfile-symlink sweep (2026-07-21)

After §9a, we did a full sweep of `~/.config/<subdir>` for anything else
sitting in the copy-deployment failure mode.

| Subdir | Before | Action | After |
|---|---|---|---|
| `ghostty` | symlink | none | symlink |
| `kitty` | symlink | none | symlink |
| `polybar` | copy-dir (drift) | mv aside, dir symlink | symlink |
| `dunst` | copy-dir (no drift) | mv aside, dir symlink | symlink |
| `mako` | copy-dir (no drift) | mv aside, dir symlink | symlink |
| `rofi` | copy-dir (real drift) | mv aside, dir symlink | symlink (adopts desktop's `monitor: -4` fix + font 12→11) |
| `waybar/style.css` | real file (no `style-laptop.css` in dotfiles) | copy live → dotfiles as `style-laptop.css`, symlink | symlink (matches the existing `config-laptop.jsonc` per-machine pattern) |
| `hypr` | per-file symlinks (`hyprland.conf` → `-laptop.conf`, `hyprland.lua` → `-laptop.lua`) | none (correct pattern) | per-file symlinks |
| `i3` | per-file symlink (`config` → `config-laptop`) | none (correct pattern) | per-file symlink |
| `waybar` (config.jsonc) | per-file symlink → `config-laptop.jsonc` | none | per-file symlink |
| `flameshot` | per-file symlinks (`flameshot-{wayland,x11}.ini`) + local `flameshot.ini` (per-session state) | none (correct pattern) | per-file symlinks |
| `fish` | copy-dir with real per-machine content (`local.fish`, `conf.d/`, `functions/`, `completions/`) | none (deliberately) | copy-dir |

**Result:** every `~/.config/<x>` that CAN be a symlink now is. The three
copy-deployment traps that bit this month (ghostty, kitty, polybar) are
now structurally impossible on the laptop — `git pull` on dotfiles
suffices. Backups at `~/.config/{dunst,mako,rofi,polybar}.pre-symlink-2026-07-21/`
+ `~/.config/waybar/style.css.pre-symlink-2026-07-21` retained pending
rollback confidence; delete when comfortable.

**Deliberately not touched:**
- `hypr`, `i3`, `waybar` (config.jsonc), `flameshot`: per-file symlink
  is the correct pattern for the per-machine variant selection they do.
- `fish`: real shell with per-machine `local.fish` / `completions/`
  (which get auto-generated on-demand, e.g. by `codex completion fish`)
  / `conf.d/` / `functions/`. Sharing via dotfiles would be a mistake.
