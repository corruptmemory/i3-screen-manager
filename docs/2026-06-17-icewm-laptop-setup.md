# IceWM-on-XLibre setup — laptop (nomad-artix)

**Date:** 2026-06-17 · **Machine:** `nomad-artix` (ThinkPad X1 Extreme Gen 5,
Artix/OpenRC, Intel Iris Xe + NVIDIA RTX 3050 Ti Mobile hybrid, eDP-1 internal
panel) · **Status:** scaffolded — all packages installed, configs written,
i3-screen-manager refactored for dual compositor. **Pending: TTY-boot
validation** (requires logout from the current Hyprland session).

A fourth toggleable WM in the rotation — but only the third still
*recommended*. Hyprland (Wayland) and IceWM (X11) are the two daily
drivers; PekWM (X11) is installed but deprecated after the user's
verdict against it on the desktop (see [PekWM trial][1]). Goal: replicate
the [desktop's IceWM setup][2] on the laptop, with the laptop's hardware
deltas accounted for.

[1]: 2026-06-15-pekwm-x11-setup-plan.md
[2]: 2026-06-16-icewm-x11-setup.md

This is **additive and reversible**: Hyprland and its config remain
untouched; nothing was removed. Toggle from a TTY:
`start-hyprland` (Wayland) · `start-icewm-laptop` (X11).

## What's different on the laptop vs the desktop

Eight concerns the desktop's IceWM setup didn't have to think about:

1. **NVIDIA hybrid GPU.** All external display ports on this ThinkPad route
   through the NVIDIA dGPU. Under Hyprland this is handled by Aquamarine's
   `AQ_DRM_DEVICES=Intel:NVIDIA`. Under X11 it's **NVIDIA PRIME / reverse
   PRIME**: Intel modesetting is the X server primary, NVIDIA loads as a
   secondary provider, and its outputs are bound to the modesetting screen
   via `xrandr --setprovideroutputsource`. Configured in
   `/etc/X11/xorg.conf.d/10-nvidia-prime.conf`.
2. **Intel VA-API (iHD).** `LIBVA_DRIVER_NAME=iHD` instead of the desktop's
   `radeonsi`. Set in `start-icewm-laptop`.
3. **Internal panel (eDP-1).** The desktop has only an external (DP-2). The
   laptop's eDP-1 is always present; externals come and go. `i3-screen-manager`
   handles add/remove via xrandr under X11 (and Hyprland-Lua dispatch under
   Wayland).
4. **Touchpad.** Configured at the X11 driver level via
   `/etc/X11/xorg.conf.d/40-touchpad.conf` (natural scroll + tap-to-click +
   disable-while-typing). Belt-and-suspenders `xinput` calls also live in
   `.xinitrc-icewm-laptop`.
5. **Brightness keys.** `XF86MonBrightnessUp/Down` bound in
   `.icewm-laptop/keys` to `brightnessctl s ±5%`.
6. **Battery widget.** `TaskBarShowAPMStatus=1` + `ShowAcpiStatusBattery="BAT0 BAT1"`
   in `.icewm-laptop/preferences`. (APMStatus is the legacy name; on modern
   kernels it reads `/sys/class/power_supply`.)
7. **Lid switch.** Under Hyprland this fires `bindl=,switch:on:Lid Switch,…`
   automatically. Under X11/IceWM there is no native lid binding — see
   [Lid handling, deferred](#lid-handling-deferred-no-auto-trigger) below.
8. **Wallpaper.** `DesktopBackgroundImage=/home/jim/projects/wallpapers/earthshot.jpg`
   matches the Hyprland session's swaybg.

## Architecture

### One-time machine setup (symlinks)

The dotfiles repo holds the files; the running machine needs symlinks into
`~/.local/bin/` and `~/` for them to be picked up. Mirrors the pattern already
in use for `start-hyprland` / `i3-screen-manager` / etc. Run once per new
machine clone of dotfiles:

```sh
ln -sf "$HOME/projects/dotfiles/.local/bin/start-icewm-laptop" "$HOME/.local/bin/start-icewm-laptop"
ln -sf "$HOME/projects/dotfiles/.xinitrc-icewm-laptop"          "$HOME/.xinitrc-icewm-laptop"
```

Verify: `which start-icewm-laptop` returns the symlink path, `ls -la
~/.xinitrc-icewm-laptop` shows it pointing into the dotfiles repo.

The IceWM config dir (`.icewm-laptop/`) does NOT need a symlink — the script
sets `ICEWM_PRIVCFG` to point at the repo location directly.

### Session bring-up

`start-icewm-laptop` (in dotfiles `.local/bin/`) is the TTY entry point.
Sibling of the desktop's `start-icewm`. Identical session/daemon bootstrap
(D-Bus, locale, gnome-keyring, ssh-agent, portal/keyring reapers,
`GIO_USE_VFS=local`, flameshot-x11 config copy); deltas:

- `LIBVA_DRIVER_NAME=iHD` (Intel iGPU).
- `VK_ICD_FILENAMES` lists Intel primary + NVIDIA available.
- `ICEWM_PRIVCFG=$HOME/projects/dotfiles/.icewm-laptop` — points IceWM at the
  per-machine config dir directly. Avoids the `~/.icewm` symlink setup
  step entirely. (`ICEWM_PRIVCFG` is documented in `icewm --help`.)
- `exec startx $HOME/.xinitrc-icewm-laptop`.

`.xinitrc-icewm-laptop` mirrors `.xinitrc-icewm` (desktop) with these laptop
deltas:

- `xrandr --setprovideroutputsource modesetting NVIDIA-G0` (best-effort,
  no-op if NVIDIA isn't yet bound) — makes NVIDIA-owned external ports
  visible to the modesetting X screen.
- `xinput set-prop 'ELAN0686:00 04F3:320D Touchpad' …` (belt-and-suspenders
  with the xorg.conf.d snippet).
- `setxkbmap -option ctrl:nocaps,shift:both_capslock_cancel` — laptop default.
- `nm-applet &` (network manager tray; the desktop is wired).

### IceWM config

Lives in `dotfiles/.icewm-laptop/` (not `~/.icewm`, picked up via
`ICEWM_PRIVCFG`). Files:

| File | Source | Laptop delta |
|---|---|---|
| `preferences` | `.icewm/preferences` (desktop) | Battery widget, `earthshot.jpg` wallpaper |
| `keys` | `.icewm/keys` (desktop) | Brightness keys; `i3-screen-rofi` (Super+BackSpace); `i3-tailscale-rofi` (Super+Shift+N) |
| `winoptions` | `.icewm/winoptions` (desktop) | identical (Brave focus-steal fix carries over) |
| `themes/godlike/default.theme` | desktop | identical (2px flat border) |
| `toolbar` | desktop | identical (empty) |

### xorg.conf.d snippets

`/etc/X11/xorg.conf.d/10-nvidia-prime.conf` — Intel modesetting primary,
NVIDIA secondary, with `AllowEmptyInitialConfiguration` so X can start
even with no NVIDIA outputs (the common case at boot, before externals are
plugged in).

`/etc/X11/xorg.conf.d/40-touchpad.conf` — libinput-driver InputClass
matching any touchpad, with `Tapping`, `NaturalScrolling`, and
`DisableWhileTyping`.

### Display management — `i3-screen-manager` is now compositor-aware

The Phase B1 refactor (see [Compositor-aware scripts](#compositor-aware-scripts)
below) made `i3-screen-manager` dispatch internally based on
`$XDG_SESSION_TYPE`:

| Subcommand | Wayland path | X11 path |
|---|---|---|
| `extend-{left,right,above,below}` | `hyprctl dispatch 'hl.monitor({...})'` | `xrandr --output … --auto --{right,left,above,below}-of` |
| `clamshell` | hl.monitor() ext at origin + disable internal + wlr-randr --off + inhibitor | xrandr ext primary + xrandr internal --off + inhibitor |
| `mirror` | hl.monitor() with `mirror = "$INTERNAL"` | `xrandr --output ext --same-as $INTERNAL` |
| `disconnect` | re-enable internal at origin, disable external | xrandr ext --off, internal --auto |
| `scale` | hl.monitor() scale param | Xft.dpi via `xrdb -merge` (toolkit-level; affects new windows only) |
| `status` | hyprctl monitors -j | xrandr --query parse |

The same UX (`Super+BackSpace` → `i3-screen-rofi` → menu) drives whichever
backend is live. Single source of truth, no per-compositor script
divergence.

### Keyboard layout — `i3-keyboard-rofi` dual-mode

Same `is_wayland()` detection. Wayland reads/writes via `hyprctl
getoption input:kb_options` / `hyprctl keyword input:kb_options`. X11
reads via `setxkbmap -query | grep options:` and writes via
`setxkbmap -option` (clear) + `setxkbmap -option ctrl:nocaps,…` (set).
Same rofi menu UX.

### Mouse — `i3-mouse-setup` and `i3-mouse-rofi` unchanged

Solaar is compositor-agnostic (HID-level via hidraw). The scripts JustWork
under both Hyprland and IceWM. `.xinitrc-icewm-laptop` invokes
`i3-mouse-setup &` for login-time DPI restore, mirroring what
`.xinitrc-icewm` (desktop) does and what the Hyprland session does via
`start-hyprland`'s own `i3-mouse-setup &` line.

### External keyboard

Two paths:

1. **Physical USB/Bluetooth keyboard plugged into the laptop while in
   clamshell or extended mode.** The OS sees it as a separate kernel
   input device. Under both compositors it picks up the same XKB config
   as the laptop keyboard. To switch to default (no Caps→Ctrl) layout
   when using the external, run `Super+Ctrl+BackSpace` → "External
   (Default)" via `i3-keyboard-rofi`. Toggle back to "Laptop (Caps→Ctrl)"
   when the external is unplugged.
2. **Keyboard layout differs.** Edit `i3-keyboard-rofi`'s `LAPTOP_OPTS`
   if the canonical layout changes.

### External mice

Logitech mice managed by `solaar` retain their saved DPI across compositor
switches (`~/.config/i3-mouse-manager/dpi`). Non-Logitech mice: speed/
acceleration controlled by `libinput` defaults, configurable per-session
via `xinput set-prop` (X11) or `hyprctl keyword input:sensitivity` (Wayland).

## Lid handling, deferred (no auto-trigger)

Under Hyprland, lid switch events fire automatically via
`bindl=,switch:on:Lid Switch,exec,laptop-monitor.sh` (subscribed to libinput
switch events by the compositor itself).

Under X11/IceWM there is **no native lid binding**. Auto-handling would
require:

1. **`acpid` as a system daemon** listening for kernel ACPI button-lid
   events.
2. **Handler script that crosses the root → user boundary** to invoke
   `xrandr` in the running X session (sets `DISPLAY`, `XAUTHORITY`).
3. **Compositor guard** so the acpid handler doesn't fight Hyprland's
   own `bindl` when the Hyprland session is the one running (the kernel
   event fires regardless of which compositor subscribed).

That's a lot of moving parts for a small UX win. **The current plan is
manual:** the user enters clamshell explicitly via `i3-screen-rofi →
Clamshell (external only)`, which under both compositors:

- Starts the `elogind-inhibit --what=handle-lid-switch` block lock
  (PID file at `/tmp/i3-screen-manager-inhibit.pid`).
- Disables the internal display (xrandr `--off` under X11,
  `hl.monitor disabled=true` + `wlr-randr --off` under Wayland).

The user closes the lid: elogind sees the inhibitor, does NOT suspend.
External monitor stays driving. Leave with `i3-screen-rofi → Disconnect`
(lid must be open).

If auto-handling is wanted later, `laptop-monitor-x11.sh` is in this repo
(symlinked to `~/.local/bin/`) — same shape as the Hyprland sibling. To
wire it via acpid:

```sh
# Install acpid + acpid-openrc (already done as part of Phase A2).
sudo rc-update add acpid default
sudo rc-service acpid start

# /etc/acpi/events/lid (handler dispatcher):
cat | sudo tee /etc/acpi/events/lid <<'EOF'
event=button/lid LID close
action=/etc/acpi/lid.sh close

event=button/lid LID open
action=/etc/acpi/lid.sh open
EOF

# /etc/acpi/lid.sh (script that crosses to user X session — needs the
# DISPLAY / XAUTHORITY + compositor guard work):
# TODO: write when needed.
```

## Verification plan

Cannot fully validate without logging out of Hyprland and booting to
`start-icewm-laptop` from a TTY. Pre-boot static validation:

- `bash -n` on `start-icewm-laptop`, `.xinitrc-icewm-laptop`, the
  refactored `i3-screen-manager` and `i3-keyboard-rofi`. **All passed.**
- `i3-screen-manager status` under the live Hyprland session, post-refactor:
  reports `Compositor: Wayland (Hyprland)`, monitor state matches
  `hyprctl monitors -j`. **Passed.**
- `i3-screen-manager disconnect` under live Hyprland with no external:
  re-applies eDP-1 at `0x0`/`scale=1.25` idempotently. **Passed** — this
  is the live proof that the Lua-mode keyword regression is fixed (the
  refactored `hl_apply` wrapper trips the `hl.monitor()` side effect even
  though the dispatch wrapper itself errors).

Post-boot live validation (after the user runs `start-icewm-laptop`):

- IceWM session boots to the TTY, IceWM mapping happens, taskbar appears
  with battery widget.
- Touchpad: natural scroll + tap-to-click working.
- Brightness keys: `brightnessctl` adjusts `/sys/class/backlight/intel_backlight`.
- `i3-screen-manager status` reports `Compositor: X11`.
- Plug external monitor: `i3-screen-manager extend-right` brings it up
  via xrandr (NVIDIA PRIME provider hookup happens first).
- `i3-keyboard-rofi`: toggle to "External (Default)" and back.

## Compositor-aware scripts

Reference implementation for "one script, two backends" — the pattern
used for `i3-screen-manager` and `i3-keyboard-rofi`:

```bash
is_wayland() {
    [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]
}

cmd_X() {
    # ... shared validation ...
    if is_wayland; then
        cmd_X_wayland "$@"
    else
        cmd_X_x11 "$@"
    fi
}
```

The detection is a 1-liner; the per-backend implementations are clean
separate functions. No script-splitting, no PATH ordering tricks, single
source of truth.

The Wayland path uses a wrapper for `hl.monitor()`:

```bash
hl_apply() {
    # The dispatch wrapper itself errors ("hl.dispatch: expected a
    # dispatcher (e.g. hl.dsp.window.close())") but hl.monitor()'s side
    # effect runs first. Quiet the error; accept the side effect.
    hyprctl dispatch "hl.monitor({ $1 })" >/dev/null 2>&1 || true
}
```

This is the Lua-mode fix for the Hyprland `keyword can't work with
non-legacy parsers` regression discovered 2026-06-13 during the 75Hz
external-monitor experiment.

## Open items / known gaps

- **Lid auto-handler not wired.** Manual via `i3-screen-rofi` → Clamshell.
  See [Lid handling, deferred](#lid-handling-deferred-no-auto-trigger).
- **PRIME provider syntax** (`xrandr --setprovideroutputsource <a> <b>`
  argument order varies across docs). The scripts try four orderings
  silently; whichever the driver accepts wins. If none work, externals
  won't show up under xrandr — confirm with `xrandr --listproviders` and
  patch the script's `ensure_nvidia_provider_x11` helper.
- **Wallpaper across sessions.** Both Hyprland (swaybg) and IceWM
  (icewmbg) use `earthshot.jpg`. If wallpapers diverge, edit both
  `.config/hypr/hyprland-laptop.lua` and `.icewm-laptop/preferences`.
- **xss-lock not in Artix repos.** `i3lock` is bound (`Super+Shift+L`)
  but there's no auto-lock-on-idle. Workarounds: bind a timer-triggered
  lock via a `keys` entry, or pull `xss-lock` from AUR after running
  `aur-malware-check`.

## Build order

1. ✓ Recon current X11 / NVIDIA / touchpad state.
2. ✓ Install `xlibre-xserver xlibre-input-libinput xlibre-input-evdev xorg-xinit icewm dunst i3lock acpid acpid-openrc` (skip `xss-lock` — not in repos).
3. ✓ Write `/etc/X11/xorg.conf.d/{10-nvidia-prime,40-touchpad}.conf`.
4. ✓ Write `dotfiles/.local/bin/start-icewm-laptop`,
       `dotfiles/.xinitrc-icewm-laptop`,
       `dotfiles/.icewm-laptop/{preferences,keys,winoptions,toolbar,themes/godlike/default.theme}`.
5. ✓ Refactor `i3-screen-manager` for dual compositor (Wayland + X11);
     fix the Hyprland-Lua `keyword can't work` regression in the same pass.
6. ✓ Refactor `i3-keyboard-rofi` for dual compositor.
7. ✓ Write `laptop-monitor-x11.sh` (companion to `laptop-monitor.sh`;
     not auto-wired).
8. ✓ Docs (this file) + CLAUDE.md updates.
9. ⏸ **TTY-boot validation** — pending logout from Hyprland.
10. ⏸ Execution log appended below after live validation rounds.

## Execution log

To be filled in after the first TTY boot.

### Round-1 — first boot, audio breakage (2026-06-17)

**Symptom:** After `start-icewm-laptop` from a TTY, IceWM came up cleanly,
but `pavucontrol` showed "output devices" with no sound. `wpctl status`
showed only `Dummy Output` as a sink, plus the NVIDIA `GA107 High Definition
Audio Controller` device (HDMI audio path, no real connector active) — the
laptop's Alder Lake codec was completely absent.

**Root cause:** I copy-pasted the desktop's `.xinitrc-icewm` audio block
verbatim into `.xinitrc-icewm-laptop`:

```sh
# (the offending block, now removed)
pipewire &
sleep 0.5 && wireplumber &
sleep 1   && pipewire-pulse &
```

The desktop *needs* that block because `godlike-artix` does not have the
PipeWire stack as OpenRC user services. The laptop *does* —
`rc-status --user` shows pipewire, wireplumber, and pipewire-pulse all
started under the default runlevel (per `artix-laptop-setup.md` § Audio).
PipeWire and pipewire-pulse self-deduplicate via D-Bus name registration
(only the first to register the name wins; the second exits or is refused),
but **WirePlumber doesn't have that protection**. So the live session ended
up with two WirePlumbers fighting over the Alder Lake codec, neither was
able to claim it cleanly, and WirePlumber's policy module fell back to
publishing a `Dummy Output` sink.

**Diagnosis path** (worth knowing next time):

```sh
pgrep -af 'pipewire|wireplumber'   # check for duplicate wireplumber procs
wpctl status                        # sinks → Dummy Output is the smoking gun
rc-status --user                    # confirm pipewire/wireplumber/pipewire-pulse
                                    # ARE running (i.e. duplication, not absence)
```

**Live recovery** (no re-login needed):

```sh
pkill -f 'wireplumber'              # kill BOTH wireplumbers; OpenRC restarts the supervised one
sleep 1
wpctl status                        # Alder Lake codec + Speaker sink should appear
wpctl set-default <speaker-sink-id> # the persistent saved default was a USB device not currently
                                    # connected; wireplumber didn't auto-fall-back
```

**Durable fix** (committed as dotfiles `37cb2e5`):

`.xinitrc-icewm-laptop` no longer launches the audio stack — comment in
place explaining why (the asymmetry vs the desktop). The OpenRC user
services cover it.

**Watch item for the desktop:** the same fix logic applies if/when the
desktop ever migrates to having those services as OpenRC user services.
For now the desktop's `.xinitrc-icewm` block is correct *for the desktop*
because that machine has no user services for the audio stack.
