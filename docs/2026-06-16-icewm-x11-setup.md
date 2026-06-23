# IceWM-on-XLibre setup — design spec (godlike-artix)

**Date:** 2026-06-16 · **Machine:** `godlike-artix` (desktop, Artix/OpenRC, AMD Navi 31, single monitor DP-2) · **Status:** built, tuned, and in daily use (2026-06-16) — judged more responsive + stable than the PekWM trial; see `…-plan.md` for the execution log + verdict

A third toggleable WM in the rotation, alongside Hyprland (Wayland) and PekWM
(X11/XLibre). Goal: reproduce the current PekWM daily-driver setup in IceWM —
or come close — and evaluate it as a candidate. This is **additive and
reversible**: Hyprland and PekWM are untouched and remain the fallbacks.

See the PekWM siblings for the pattern this mirrors:
`docs/2026-06-15-pekwm-x11-setup.md` (design) and `…-plan.md` (execution log).

## Why IceWM, and why now

- **Mature, batteries-included stacking WM.** Built-in taskbar, EWMH-compliant,
  plain-text config. The "even more old-school than PekWM" end of the experiment.
- **In the official repo, not the AUR.** `icewm 4.0.0-1` in Artix's `world`
  repo, so the June-2026 AUR-malware ground rule does not apply. (PekWM was also
  repo-sourced; the AUR ban remains in force for anything else.)
- **Runs on the same XLibre X server** already in use for PekWM — no X-server
  changes; `start-icewm` is an X11 sibling of `start-pekwm`.

## Success criteria

Parity (or close) with the current PekWM setup, specifically:

1. Stacking/all-floating, 10 named workspaces, click-to-focus **+ raise**
   (focused window is topmost — the stacking-WM preference settled under PekWM).
2. GNOME-style `Super+Up`/`Super+Down` maximize/restore (maximize honors the
   bar's strut).
3. `Super+N` goto-workspace, `Super+Shift+N` send-window-to-workspace **with
   focus surviving on the source workspace**.
4. Rofi launcher (`Super+Space`) and window picker (`Super+Tab`); the rest of the
   app/audio/lock/screenshot binds at parity.
5. Titlebarless, clean, low-eye-candy look with an obvious **cyan focused-window
   border**.
6. A bar showing workspaces, window list, tray, and clock.
7. Session bring-up at parity: keyring unlock, ssh-agent socket, D-Bus activation
   environment, portal/keyring reapers, flameshot working.

## Known gaps / non-goals

- **Exact `Super`+drag move / `Super`+right-drag resize** is best-effort. IceWM's
  mouse-modifier binding is less configurable than PekWM's `mouse{}`; **Alt+drag
  is the guaranteed fallback** for move.
- **Half-screen snapping** has no guaranteed native equivalent (see §6).
- Not chasing pixel-identical bar styling — we deliberately use IceWM's **native
  taskbar**, not Polybar (Polybar stays in reserve).

## Architecture

### 1. Session & toggle

`start-icewm` is a near-clone of `start-pekwm` (the X11 bootstrap): same
`XDG_RUNTIME_DIR`, locale, `dbus-daemon` (Artix/OpenRC has no per-user bus),
gnome-keyring (`secrets,pkcs11`), ssh-agent at the predictable
`ssh-agent.sock`, AMD VA-API (`radeonsi`), `GIO_USE_VFS=local`, and the
**portal + keyring reapers** (kill orphans by executable, not cmdline). Deltas
from `start-pekwm`:

- `XDG_CURRENT_DESKTOP=icewm`, `XDG_SESSION_DESKTOP=icewm` (`XDG_SESSION_TYPE=x11`).
- **Flameshot**: copies the **same `flameshot-x11.ini`** PekWM uses
  (`useX11LegacyScreenshot=true`) — IceWM is X11 with no portal screenshot
  backend, identical situation to PekWM. No new flameshot variant.
- Hands off with `exec startx ~/.xinitrc-icewm`.

`.xinitrc-icewm` (new; symlinked `~/.xinitrc-icewm`) mirrors `.xinitrc-desktop`:
keeps `dbus-update-activation-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP …`
(the keyring/portal draw fix) and the autostart block, but:

- execs **`icewm-session`** (brings up `icewmbg` + `icewm` + tray/taskbar)
  instead of `pekwm`.
- **Drops `feh`** — IceWM owns the wallpaper via `DesktopBackgroundImage`
  (`icewmbg`).

Toggle from a TTY: `start-hyprland` (Wayland) · `start-pekwm` (X11) ·
`start-icewm` (X11).

### 2. The bar — IceWM native taskbar

IceWM's own taskbar, configured in `preferences`: workspace pager + window list
+ system tray + clock, with optional CPU/net/mem monitors. `ShowTaskBar=1`; no
Polybar process. Polybar's `config-pekwm.ini` is left in place as the reserve
option if the native bar disappoints.

### 3. Keymap parity

IceWM splits keybinds two ways: built-in window/workspace actions live in
`preferences` as `KeySys*`/`KeyWin*` values; arbitrary launches live in the
`keys` file as shell commands.

| Current PekWM bind | IceWM mechanism |
|---|---|
| `Super+Up` / `Super+Down` maximize/restore | **native** `KeyWinMaximize` / `KeyWinRestore` |
| `Super+1..0` goto-workspace | **native** `KeySysWorkspace1..10` |
| `Super+Shift+1..0` send-to-workspace | **native** `KeySysWorkspaceTakeWindow1..10` |
| `Super+Q` close / `Super+Shift+F` fullscreen | **native** `KeyWinClose` / `KeyWinFullscreen` |
| `Super+F` maximize-toggle | **native** `KeyWinMaximize` (toggle; `Super+Up`/`Down` map to the same toggle/restore actions — the always-max vs toggle nuance is a build-time tweak) |
| `Super+Space` (rofi drun), `Super+Tab` (`icewm-window-switcher`, see §4a) | `keys` file → shell |
| `Super+Return` kitty, `Super+B` brave, `Super+E` emacs, lock, screenshot, audio keys | `keys` file → shell |
| `Alt+Tab` MRU cycle | IceWM native **QuickSwitch** (kept) |

`keys`-file commands run through a shell, so **`~` expands** — none of the
absolute-path workaround PekWM's `Exec` forced.

### 4. Look & behavior

- **Titlebarless** via `winoptions` `noTitleBar` (functional in IceWM — no
  pekwm-0.4.4 dead-autoprops saga).
- **Cyan active border**: `ColorActiveBorder=rgb:33CCFF`,
  `ColorNormalBorder=rgb:333333` (with titlebars off, the border is the focus
  cue).
- **Click-to-focus + raise**: `ClickToFocus=1`, `RaiseOnClickClient=1`.
- **Wallpaper**: `DesktopBackgroundImage` (IceWM/`icewmbg` owns it; `feh`
  dropped from this session).
- `Super+Tab` → **`icewm-window-switcher`** for the cross-window picker
  (complements native QuickSwitch). Originally `rofi -show window`; replaced
  2026-06-22 to fix a raise bug and a taskbar-flash bug — see §4a.

### 4a. Window switcher (`Super+Tab`) — `icewm-window-switcher`

`Super+Tab` runs `~/.local/bin/icewm-window-switcher` (lives in the dotfiles repo
at `.local/bin/icewm-window-switcher`, symlinked into `~/.local/bin/`, alongside
`start-icewm`/`x11-max-refresh`). It replaced the original `rofi -show window` on
**2026-06-22** after two bugs surfaced in daily use:

1. **It didn't raise the chosen window.** `rofi -show window` activates purely by
   sending the EWMH `_NET_ACTIVE_WINDOW` message and leaving the rest to the WM.
   IceWM honored it only halfway — switched to the window's workspace but left the
   window at its old stacking depth (the request bypasses IceWM's normal focus
   path, so `RaiseOnFocus=1` never fired). You landed on the right workspace
   staring at whatever was already on top.
2. **Flashing taskbar entry.** The obvious native fix — `icesh activate`/`raise` —
   raises an *unfocused* window by setting `_NET_WM_STATE_DEMANDS_ATTENTION` on it,
   which IceWM renders as a taskbar button that flashes and follows you to **every**
   workspace until clicked.

The script steers IceWM explicitly, in three steps, to sidestep both:

```text
icesh goto <ws>            # 1. switch to the window's workspace
icesh -window <id> raise   # 2. lift it to the top of the stacking order
xdotool windowfocus <id>   # 3. real XSetInputFocus — focuses AND clears the
                           #    demands-attention flag, so no flash
```

The explicit `goto` (step 1) is required because this machine runs
`FocusChangesWorkspace=0`, so focusing alone won't follow a window across
workspaces. The two stock paths are mirror images and neither does both jobs:
rofi's `_NET_ACTIVE_WINDOW` switches workspace but won't raise; `icesh activate`
raises but won't switch workspace. Step 3 uses `xdotool windowfocus`
(low-level `XSetInputFocus`) rather than `icesh activate` precisely because a
genuine input-focus is what makes IceWM clear demands-attention — it's also
self-healing (clears a pre-existing flash on the target).

Windows are picked from `icesh clients` (real client windows only — IceWM frames,
the dock and the tray are filtered out for free) via `rofi -dmenu`, displayed as
`WS<n>  <Class>  <title>`.

**Dependencies** (all already present in this setup): `icesh` (ships with IceWM),
`xdotool`, `rofi`.

**Install (once per machine):**

```bash
# 1. Symlink the script into ~/.local/bin (already first on PATH).
ln -s ~/projects/dotfiles/.local/bin/icewm-window-switcher \
      ~/.local/bin/icewm-window-switcher

# 2. The binding already lives in dotfiles' .icewm/keys (desktop) and
#    .icewm-laptop/keys (laptop):
#        key "Super+Tab"   /home/jim/.local/bin/icewm-window-switcher
#    IceWM reads its keys file only at start/restart, so reload it once:
killall -HUP icewm
```

### 5. The focus-fallback bug — expected absent

PekWM 0.4.4 left the source workspace with no focused window after
`SendToWorkspace`, forcing the `pekwm-send-to-ws` helper. IceWM's
`KeySysWorkspaceTakeWindow*` is a first-class action with proper focus handling,
so the bug is **expected not to occur**. Plan: bind the native action, **verify**
focus survives, and add a helper only if it actually recurs.

### 6. Half-screen snapping — best method

`Super+Shift+arrows` (PekWM `FillEdge`, the "stacking-world tiling helper").

1. If IceWM 4.0 ships native tile key-actions (e.g. `KeyWinTile*`), bind those.
2. Otherwise, a small `xdotool`/`wmctrl` geometry helper computing half-screen
   rects against the active monitor's work area, bound via the `keys` file.

Determined at build time once IceWM's actual 4.0 capabilities are confirmed.

## Decoration-lever decision

Use `winoptions noTitleBar` + `Color*Border` preferences rather than authoring a
custom minimal IceWM theme. Rationale: winoptions and color prefs are guaranteed
to work and require no theme-format authoring; a custom theme is more surface
area for the cyan-border + titlebarless goal than it's worth.

## Verification plan

- Install `icewm` from the official **`world`** repo (`yay`/`pacman`, not AUR).
- Bring it up first in a **nested Xephyr** IceWM to confirm config parses and
  behavior is right without disturbing the live session (the technique that
  cracked the PekWM titlebar work).
- Assert behavior with `xdotool` / `wmctrl` / EWMH (`_NET_*`) against throwaway
  marked-class windows — the same harness used this session: focus model
  (hover does/doesn't steal focus), maximize geometry vs strut, send-to-workspace
  + focus survival, keybind firing.

## Open items to confirm at build (not blockers)

- Exact IceWM 4.0 pref names for the maximize/restore/take-window key actions and
  the border colors (verify against the installed `man icewm-preferences`).
- Whether IceWM 4.0 has native half-tiling key actions (§6).
- Whether `Super` is bindable as the mouse move/resize modifier, or we accept the
  Alt+drag default (§ Known gaps).

## Build order

1. Install `icewm`; dump defaults (`icewm --version`, `man` pages, `/usr/share/icewm`).
2. Author `.icewm/{preferences,keys,winoptions,toolbar,startup}` in dotfiles.
3. Nested-Xephyr smoke test → iterate config.
4. `start-icewm` + `.xinitrc-icewm` (clone/adapt the PekWM siblings).
5. Live TTY-boot validation; xdotool/EWMH assertions for the success criteria.
6. Execution log → `docs/2026-06-16-icewm-x11-setup-plan.md`; commit both repos.

## Docs / commit plan

Design spec (this file) and a later `…-plan.md` execution log, same naming and
commit cadence as the PekWM pair. The IceWM config itself lives in the **dotfiles
repo** (`.icewm/`, `.xinitrc-icewm`, `.local/bin/start-icewm`), not here.
