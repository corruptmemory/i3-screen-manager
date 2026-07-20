# i3 on `godlike-artix` — design/plan

Returning to **i3** as the desktop's X11 window manager, after the FVWM3 trial
was called a provisional failure the same day it was built
(`docs/2026-07-20-fvwm3-x11-setup.md`).

**Status:** design approved 2026-07-20. Not yet implemented. **i3 is not
installed** — `pacman -Q i3-wm` returns nothing; only `i3lock` is present, used
by the existing sessions for locking.

---

## 0. Why i3, and what it costs

The whole FVWM3 detour existed to get **independent per-monitor workspaces in a
stacking WM**. FVWM3 was the only stacking X11 WM that offers them, and that
part genuinely worked — it died on window-placement quirks arriving faster than
they could be fixed.

i3 has the workspace model, reliably, and has had it for years. The cost is the
paradigm: **i3 is tiling**, which is not the stated preference. This is a
deliberate trade — accept tiling to get a monitor model that behaves.

### The model is NOT the same as FVWM3's

Worth being explicit, because the difference will be felt:

| | FVWM3 | i3 |
| --- | --- | --- |
| Workspace numbering | each monitor had a **private copy** of desks 1–10 | **one shared pool** of 10 |
| "Workspace 3" | existed on both monitors, independently | exists once, on one output |
| Pressing `Super+3` | switched the **current monitor** to its own desk 3 | moves focus to whichever monitor holds workspace 3 |

What carries over is the property that actually matters: **switching workspace
on one monitor does not disturb the other.** What is lost is duplicate
numbering.

---

## 1. Prerequisite: preserve the live drift FIRST

`~/.config/i3/` is a **real directory, not a symlink**, and the live copy has
drifted **ahead** of the repo:

```diff
- exec --no-startup-id waypaper --restore              # repo (a WAYLAND tool)
+ exec --no-startup-id feh --bg-fill ~/projects/dt-wallpapers/0007.jpg
+ set $browser brave --profile-directory="Default" --new-window
+ bindsym $mod+$alt+v exec /home/jim/.local/bin/xdtpaste.sh
+ bindsym $mod+Mod1+m exec --no-startup-id i3-mouse-rofi
```

This is the same copy-deployment failure that silently ate the polybar
`cmos-battery` module (dotfiles `7ed0c5b`) and made the Ghostty theme never
apply. **Propagate live → repo and commit BEFORE touching anything else**, then
symlink so the class of bug becomes structurally impossible here as it now is
for `polybar`, `kitty` and `ghostty`.

---

## 2. Files

| File | Role |
| --- | --- |
| `dotfiles/.config/i3/config-desktop` | the config (renamed from `config`) |
| `dotfiles/.xinitrc-i3` | X-side setup, then `exec i3` |
| `dotfiles/.local/bin/start-i3` | pre-X bootstrap, copied from `start-icewm` |
| `dotfiles/.config/polybar/config-i3.ini` | the two bars |

`~/.config/i3/config` becomes a symlink to `config-desktop`, leaving room for a
`config-laptop` later — mirroring `hyprland-desktop.*` and `.icewm` /
`.icewm-laptop`.

---

## 3. Workspaces and outputs

```
workspace 1  output DP-2
...
workspace 6  output DP-2      # 2560x1440 landscape at +0+240, main
workspace 7  output HDMI-1
...
workspace 10 output HDMI-1    # 1200x1920 portrait at +2560+0, side
```

Six on the main panel, four on the side. `Super+1..0` goes to a workspace
(moving focus to its monitor); `Super+Shift+1..0` sends the focused container
there.

Layout rationale is in `docs/2026-07-20-desktop-dual-monitor-portrait.md` —
note the y-offset: the **shorter** panel carries it, because X11 has no negative
screen coordinates.

---

## 4. Startup — three layers, each doing only what it can

### `start-i3` (pre-X)

A near-copy of `start-icewm`, changing only the session identity and the handoff
target. Everything here **must** precede the X server:

`XDG_RUNTIME_DIR` · locale (OpenRC does not source `/etc/locale.conf`) ·
`XDG_CURRENT_DESKTOP=i3` · D-Bus session socket · `XCOMPOSEFILE` ·
`LIBVA_DRIVER_NAME=radeonsi` · `GIO_USE_VFS=local` · stale
gnome-keyring/xdg-desktop-portal reapers · keyring (`secrets,pkcs11` only —
never `ssh`) · ssh-agent at the shared socket · flameshot X11 config swap →
`exec startx ~/.xinitrc-i3`

### `.xinitrc-i3` (X-side, pre-WM)

Toolkit backends (`QT_QPA_PLATFORM=xcb`, `GDK_BACKEND=x11`,
`_JAVA_AWT_WM_NONREPARENTING=1`) · `x11-max-refresh` · **the same xrandr layout
line as `.xinitrc-icewm`, verbatim** · `dbus-update-activation-environment`
(**without `--systemd`**) · pipewire → wireplumber → pipewire-pulse →
`exec i3`

xrandr must run **before** i3 starts, or i3 sees one monitor and has to
re-place workspaces afterwards.

### `config-desktop` (autostart)

i3 distinguishes `exec` (startup only) from `exec_always` (startup **and
reload**). That is the same distinction as fvwm's `InitFunction` vs
`StartFunction`, which caused duplicate daemons on every reload there
(`docs/2026-07-20-fvwm3-x11-setup.md` §2). Use it deliberately:

```
exec        --no-startup-id polybar ... i3-dp2
exec        --no-startup-id polybar ... i3-hdmi1
exec        --no-startup-id dunst
exec        --no-startup-id udiskie
exec        --no-startup-id flameshot
exec        --no-startup-id /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec        --no-startup-id i3-mouse-setup
exec_always --no-startup-id feh --bg-fill ~/projects/dt-wallpapers/0007.jpg
```

**Both systemd lines are deleted**, not adapted:

- `systemctl --user import-environment …` — systemd-only, dead on Artix/OpenRC.
- `dbus-update-activation-environment --systemd …` — the command is fine and is
  needed (it is what makes the keyring unlock prompt able to draw); the
  `--systemd` **flag** is not. It moves to `.xinitrc-i3` in the same form
  `.xinitrc-icewm` already uses.

---

## 5. Polybar

New `config-i3.ini`; the existing `config.ini` is left untouched as the
historical single-bar version.

**The i3 module solves what FVWM3 could not.** Polybar's `internal/i3` talks to
i3's own IPC rather than EWMH, so `pin-workspaces = true` makes each bar show
only **its own monitor's** workspaces. Under FVWM3 this was impossible — EWMH
exposes a single global `_NET_CURRENT_DESKTOP` — which is why that setup needed
a FvwmPager/Polybar hybrid. **Here polybar does the whole bar.**

`pin-workspaces` confirmed present in the installed polybar binary.

| Bar | monitor | left | right |
| --- | --- | --- | --- |
| `i3-dp2` | DP-2 | `i3` `xwindow` | `cmos-battery memory cpu temperature date systray` |
| `i3-hdmi1` | HDMI-1 | `i3` | `date` |

No tray and no stats on the portrait bar: a tray only usefully lives on one
screen, and 1200px is narrow. Module bodies are copied verbatim from
`config.ini`, including the recovered `cmos-battery`.

The existing `[module/i3]` block is bare (`type = internal/i3` and nothing
else) and needs real configuration.

---

## 6. Window rules

```
for_window [class="zoom"]         floating enable
for_window [class="pavucontrol"]  floating enable
for_window [class="Keymapp"]      floating enable
for_window [class="steam"]        floating enable
```

**Zoom floats and is otherwise left alone** — no scratchpad, no forced
workspace. It gets parked on the side monitor by hand. The `special:zoom`
scratchpad-like hack was a *Hyprland* invention and never existed in the i3
config; the i3 config's Zoom handling was already correct.

**Removed entirely:**

- **All Morgen lines** — no longer used: the float rule, the
  `move scratchpad` rule, the `$mod+Shift+m` binding, and the
  `exec --no-startup-id morgen` autostart.
- **All `KittyFloating`** — never used, and the terminal is Ghostty now.

**Kept:** the generic `$mod+minus` / `$mod+Shift+minus` scratchpad bindings.
These are stock i3, entirely opt-in, and not the kind of forced-scratchpad rule
being rejected.

---

## 7. Rofi

Set **once** in `~/.config/rofi/config.rasi`:

```
monitor: -4;
```

so it applies to the applets and powermenu scripts too, not only the two
bindings in the i3 config.

The default is `-5`, and from `rofi(1)` that is *"the monitor that shows the
mouse pointer"* — i.e. menus currently follow the **mouse**, not focus. The
values, verbatim:

| | meaning |
| --- | --- |
| `-1` | the currently focused monitor |
| `-2` | the currently focused window (rofi drawn on top of it) |
| `-3` | position of mouse |
| `-4` | **the monitor with the focused window** |
| `-5` | the monitor that shows the mouse pointer (default) |

`-4` is the direct expression of "open on the monitor with focus". If it
misbehaves, `-1` is the fallback.

---

## 8. Modernisation

| Old | New | Why |
| --- | --- | --- |
| `kitty`, `KittyFloating` | `ghostty` | terminal swap (`kitty-to-ghostty-terminal-swap.md`); floating variant dropped as unused |
| `brave` | `brave-origin` | `brave-to-brave-origin-migration.md` |
| `waypaper --restore` | `feh --bg-fill` | waypaper is a **Wayland** tool; live config already fixed this |
| `pactl` volume binds | `wpctl` | matches every other config on this machine |
| `systemctl --user import-environment` | *(deleted)* | systemd-only |
| `dbus-update-activation-environment --systemd` | same, no `--systemd`, in `.xinitrc-i3` | flag is systemd-only; command is required |

---

## 9. Explicitly unchanged

- `default_border pixel 2` / `default_floating_border pixel 2` — already the
  2px preference.
- `hide_edge_borders smart`, `font pango:TX-02 10`.
- The `$mod+F1/F2/F3` focus-by-class binds for Slack / Keybase / Discord.
- Resize mode, split/layout binds, `$mod+Shift+r` restart, `$mod+Shift+c`
  reload.
- **IceWM and Hyprland.** This is additive; `start-icewm` continues to work.

---

## 10. Risks and unverified assumptions

- **`exec` vs `exec_always` semantics are not verified** — i3 is not installed,
  so its man page could not be read. The expectation (`exec` = startup only,
  `exec_always` = also on reload) is well-established, but this is *exactly* the
  assumption pattern that produced the FVWM3 duplicate-daemon bug. **Confirm
  against `man 5 i3` once installed**, then test by reloading and counting
  processes: `ps -C polybar -o pid= | wc -l` must stay at 2.
- **`pin-workspaces` is confirmed present in the binary but its behaviour is
  untested.** If each bar still shows all workspaces, that undermines §5's
  claim that polybar alone suffices.
- **`workspace N output` against this layout is untested.** The portrait monitor
  is rotated and the landscape one carries a y-offset; fvwm's per-monitor
  coordinate handling broke on exactly that (the strut double-count). i3 is
  expected to handle it, but "expected" is what the FVWM3 doc says about several
  things that did not.
- **`rofi -m -4` is documented but untested** on this two-monitor layout.
- **Nothing i3-specific has been run on this machine in over a year.** The
  config predates the Artix migration, the dual-monitor setup, and the terminal
  and browser swaps.

---

## 11. Verification plan

1. Install `i3-wm`. Check what else the old config assumes is present: `dex`,
   `nm-applet`. (`dmenu` is referenced nowhere in the config — do not install it
   reflexively.)
2. `i3 -C -c <config>` — validate the config file **without starting a session**.
   This is i3's built-in config check and has no fvwm equivalent; use it.
3. Boot from a TTY via `start-i3`.
4. Walk: both monitors up with the right layout · workspaces 1–6 land on DP-2
   and 7–10 on HDMI-1 · each polybar shows only its own monitor's workspaces ·
   rofi opens on the focused monitor · Zoom floats · terminal is Ghostty ·
   `Super+B` opens brave-origin · volume keys work · tray populated.
5. **Reload (`$mod+Shift+c`) and re-count daemons** — the FVWM3 lesson.
6. Only then write the outcome doc.

---

## 12. Deferred

- **Ghostty tab chrome**: `gtk-wide-tabs = false` + `gtk-toolbar-style = flat`
  to reclaim the space the GTK tab bar takes. Agreed but out of scope here.
- **Hyprland cleanup**: `special:zoom` and `special:morgen` rules still exist in
  all four hypr configs. Morgen is unused entirely now.
- **Laptop variant** (`config-laptop`), once the desktop settles.
- **FVWM3 config** stays on disk; it is additive and harmless
  (`docs/2026-07-20-fvwm3-x11-setup.md` §7 has the rollback).
