# PekWM + XLibre desktop session — design & setup spec

**Date:** 2026-06-15
**Machine:** `godlike-artix` (desktop; single monitor `DP-2`; pure AMD Navi 31 / amdgpu).
**Status:** design approved (brainstorming) — not yet implemented.
**Companion docs:** `docs/2026-06-15-x11-wm-research.md` (why PekWM), this repo's
`CLAUDE.md` (Hyprland/Wayland baseline, repo conventions).

> **Why this exists.** Jim is trialing a move off Hyprland to a stacking X11 WM.
> PekWM won the survey (lightweight stacking, native window grouping/tabbing,
> actively developed on Fossil). This spec captures a *full daily-driver-parity*
> first cut: enough of the current Hyprland/Waybar/rofi workflow reproduced under
> PekWM+Polybar to fairly judge whether to stay. **Additive and reversible** —
> nothing about the Hyprland session is removed; the two coexist behind one TTY
> command each.

---

## 1. Goals / non-goals

**Goals**
- Boot a clean, low-eye-candy PekWM session on XLibre from a TTY (no display
  manager), toggleable against the existing Hyprland session.
- Reproduce the current keybind muscle memory (`Super`-driven), the Waybar module
  set (as Polybar), rofi launching, notifications, and the autostart stack.
- Zero AUR exposure — every new package is in the official Artix/Arch repos.

**Non-goals (this cut)**
- Display-management scripts (`i3-screen-*`) — single monitor makes them moot.
- Scratchpads / special workspaces — **phase 2** (PekWM has no native scratchpad).
- Idle auto-lock / DPMS — manual lock only initially.
- A compositor — intentionally omitted (Jim chose none + amdgpu TearFree).
- Removing or altering anything Hyprland.

---

## 2. Session model & toggle

No display manager. TTY login, then pick a session by command — same explicit
model Jim already uses for Hyprland.

| Session | Command | Mechanism |
|---|---|---|
| Wayland | `start-hyprland` | existing launcher (unchanged) |
| X11/PekWM | `start-pekwm` | new wrapper → `exec startx ~/.xinitrc` |

- `start-pekwm` (new, `~/.local/bin/`, symlinked from this dotfiles convention)
  mirrors the **non-Wayland** half of `start-hyprland`'s env bootstrap: ssh-agent
  at the predictable socket (needed for `ssh node-0` / Open Brain), gnome-keyring,
  `GIO_USE_VFS=local`. It does **not** set Wayland/NVIDIA vars. Ends in
  `exec startx ~/.xinitrc`.
- `~/.xinitrc` sets X-only env, applies any `xrandr`/`xset` tweaks, launches the
  autostart stack (§8), then `exec pekwm`.
- **Reversibility:** back out by simply not running `start-pekwm`. No Hyprland file
  is touched. XLibre coexists with the `xorg-xwayland` Hyprland needs.

---

## 3. File layout (existing dotfiles convention)

Configs live in `~/projects/dotfiles/` and are symlinked into `$HOME`, following
the repo's established `-desktop`/`-laptop` suffix + symlink pattern (same as
`hyprland-desktop.lua`, `config-desktop.jsonc`).

| Artifact | Repo path | Symlink target |
|---|---|---|
| PekWM config dir | `dotfiles/.pekwm-desktop/` (or `.config/pekwm/`) | see note |
| Polybar | `dotfiles/.config/polybar/config-pekwm.ini` + `launch.sh` | `~/.config/polybar/` |
| X session init | `dotfiles/.xinitrc` | `~/.xinitrc` |
| Launcher wrapper | `dotfiles/.local/bin/start-pekwm` | `~/.local/bin/start-pekwm` |
| amdgpu TearFree | `dotfiles/etc/X11/.../20-amdgpu.conf` (staged copy) | `/etc/X11/xorg.conf.d/20-amdgpu.conf` (root-owned; copied, not symlinked) |

- **This design+runbook doc** lives in *this* repo (`i3-screen-manager/docs/`), the
  home of WM/session docs. The laptop's Claude can replay it later.
- **Config-dir note / verify at impl:** PekWM's documented default is `~/.pekwm/`
  (the `Files {}` block in `config` can redirect paths anywhere). Newer releases
  may honor `$XDG_CONFIG_HOME/pekwm`. At implementation: confirm whether 0.4.4
  reads `~/.config/pekwm/`; if yes, use it to match the repo's `.config` mirror;
  if no, symlink `~/.pekwm` → the repo dir. Either way the source of truth is the
  dotfiles repo.

---

## 4. Packages (100% official repos — no AUR)

Install: `xlibre-xserver xlibre-input-libinput pekwm polybar dunst feh i3lock`.

Already present and X11-native: `kitty brave emacs flameshot nm-applet udiskie
rofi` + the pipewire stack + `wpctl`/`playerctl`.

**Verify-at-impl availability** (used by a few binds; substitute if absent):
- `xdotool` — for the `Super+F1/F2/F3` focus-by-class binds (PekWM has no native
  "focus window by class" action). **`wmctrl` is NOT in the official repos** (and
  AUR is off-limits), so xdotool is the substitute: `xdotool search --class <name>
  windowactivate`. Confirmed in `world` at impl.
- `xidlehook` or `xss-lock` — only if idle auto-lock is added later (not this cut;
  `xss-lock` was NOT in repos as of survey — check again or use `xidlehook`).

---

## 5. XLibre + amdgpu

- `xlibre-xserver` `Provides`/`Conflicts` `xorg-server` (not installed → clean) and
  `Replaces xf86-video-modesetting` + `glamor-egl` — i.e. it **bundles** the
  modesetting DDX, so amdgpu needs no separate video-driver package. Input via
  `xlibre-input-libinput`.
- **Coexistence:** `xorg-xwayland` (installed for Hyprland's XWayland) is a separate
  binary, not `xorg-server` — XLibre as the native server and Xwayland-under-Hyprland
  do not conflict.
- **No compositor; TearFree instead.** Stage `/etc/X11/xorg.conf.d/20-amdgpu.conf`:
  ```
  Section "Device"
      Identifier "AMD"
      Driver     "modesetting"   # or "amdgpu" if xf86-video-amdgpu is added
      Option     "TearFree" "true"
  EndSection
  ```
  Kills tearing without picom. (Driver string verified at impl against what XLibre's
  bundled modesetting registers.)
- **Watch item — XLibre maturity.** XLibre is a young fork; this repo's CLAUDE.md
  already records a past `xlibre-xserver` 25.0.0.21 vblank lockup regression
  (`failed to queue next vblank event`). This is precisely why Hyprland stays one
  TTY command away. If X misbehaves, fall back to Hyprland and note the version.

---

## 6. PekWM configuration

PekWM config files: `config` (global + `Files {}` paths + `Screen { Workspaces }`),
`keys`, `mouse`, `menu`, `start`, `autoproperties`, `vars`, and a `themes/` dir.

> **PekWM model reminder (drives everything below):** PekWM is a **stacking** WM —
> all windows float by default; there is no tiling grid. Its signature feature is
> **frames**: a frame is a window that can hold multiple clients as tabs (a "window
> group"). This is the native analog of Hyprland's groups.

### 6.1 `config` — workspaces, placement, files

- `Screen { Workspaces = 10; WorkspacesPerRow = 10 }` (single row of 10 to match
  the Hyprland `1..0` workspaces). `WorkspaceNames` optional.
- `Placement { Model = "Smart MouseNotUnder CenteredOnParent" }` — sane auto-placement;
  covers most of what Hyprland's `center` float rules did for free.
- **Snapping (the stacking-world stand-in for tiling).** Jim is deliberately
  leaving tiling behind; PekWM's edge/window snapping is the substitute that keeps
  manual placement quick without a tiling grid. Set the `MoveResize {}` snap
  distances so dragged/keyboard-moved windows snap to screen edges and to each
  other: `EdgeAttract`, `WindowAttract` (snap-to distances) and `EdgeResist`,
  `WindowResist` (resistance distances), plus `OpaqueMove = True`/`OpaqueResize =
  True` for live feedback. Combined with `MoveToEdge` (bound to `Super+Shift+up/
  down`, §6.2), this gives fast half/edge placement by hand.
- `Files {}` points Keys/Mouse/Menu/Start/AutoProps/Theme at the repo paths.
- Focus: `FocusNew = True`; keep sloppy/`follow_mouse` parity with Hyprland's
  `follow_mouse = 1` (PekWM default is focus-follows-mouse via the `mouse` file's
  `Enter` actions — keep them).

### 6.2 `keys` — full keybind parity

`Mod4` = Super. Syntax: `KeyPress = "Mod4 Return" { Actions = "Exec kitty" }`.
Multiple actions separated by `;`. Keychains via `Chain = "..." { KeyPress ... }`.

Verified-action parity table (Hyprland Lua bind → PekWM action). Notes flag where
the stacking model has no clean tiling analog.

| Intent | Hyprland | PekWM action |
|---|---|---|
| Terminal | `Super+Return` | `Exec kitty` |
| Floating terminal | `Super+Shift+Return` | `Exec kitty --class KittyFloating` (all float anyway) |
| Browser | `Super+B` | `Exec brave …` (strip Wayland flags; keep `--remote-debugging-port=9222`) |
| Emacs | `Super+e` | `Exec emacs` |
| Password (rofi-rbw) | `Super+Shift+B` | `Exec rofi-rbw` |
| Lock | `Super+Shift+L` | `Exec i3lock -c 000000` |
| Close window | `Super+Q` | `Close` |
| **Quit WM** | `Super+Shift+Escape` | **verify**: PekWM has no default quit keybind — bind the root-menu `Exit` action, else `Exec pkill pekwm` as fallback |
| Launcher menu | `Super+Space` | `Exec rofi -modi drun,run -show drun` |
| Maximize | `Super+F` | `Maximize` (toggle H+V) |
| True fullscreen | `Super+Shift+F` | `Toggle FullScreen` |
| Mark client (group) | `Super+g` | `Toggle Marked` |
| Attach marked → frame | `Super+Shift+G` | `AttachMarked` |
| Tab next/prev in frame | `Super+Tab` / `Super+Shift+Tab` | `ActivateClientRel 1` / `ActivateClientRel -1` |
| Cycle frames | (alt-tab) | `NextFrameMRU` / `PrevFrameMRU` |
| Directional focus | `Super+arrows` | `FocusDirectional Up/Down/Left/Right` |
| Reorder client in frame | `Super+Shift+left/right` | `MoveClientRel -1 / 1` (nearest analog; no tiling-move) |
| Move-to-edge | `Super+Shift+up/down` | `MoveToEdge …` (best-effort analog) |
| Workspace switch 1–10 | `Super+1..0` | `GotoWorkspace 1..10` (⚠ indexing, §6.5) |
| Send window to ws | `Super+Shift+1..0` | `SendToWorkspace 1..10` |
| Workspace scroll | `Ctrl+Alt+left/right` | `GotoWorkspace Left/Right` |
| Focus Slack/Keybase/discord | `Super+F1/F2/F3` | `Exec xdotool search --class <name> windowactivate` (wmctrl not in repos) |
| Restart bar | `Super+Shift+W` | `Exec ~/.config/polybar/launch.sh` |
| Volume up/down/mute | `XF86Audio*` | `Exec wpctl …` (identical) |
| Mic mute | `Ctrl+F1` | `Exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |
| Media play/next/prev | `XF86Audio{Play,Next,Prev}` | `Exec playerctl …` (identical) |
| Screenshot | `Print` | `Exec flameshot gui` |
| Resize mode | `Super+Alt+R` | `MoveResize` (PekWM's modal move/resize; arrows resize, Enter accept) |
| Keyboard layout rofi | `Super+Ctrl+BackSpace` | `Exec i3-keyboard-rofi` (setxkbmap-based; works on X11) — keep |
| Display/DPI rofi | `Super+BackSpace`, `Super+Alt+BackSpace` | **dropped** (single monitor) |

**Rationalized double-binds:** the Hyprland Lua double-binds `Super+left/right` to
*both* `movefocus` and group tab-cycle. In PekWM these split cleanly: `Super+arrows`
→ `FocusDirectional`; tab-cycle within a frame → `Super+Tab`/`Super+Shift+Tab`
(`ActivateClientRel`). No ambiguity carried over.

### 6.3 Grouping (the headline mapping)

PekWM frames *are* Hyprland groups. Workflow on the bound keys:
`Super+g` marks/unmarks the focused client (`Toggle Marked`, shows `[M]` in the
title); focus the target frame and `Super+Shift+G` (`AttachMarked`) pulls the marked
clients in as tabs; `Super+Tab`/`Super+Shift+Tab` cycle tabs. Optionally autogroup
classes via autoproperties `Group {}` (§6.4) so e.g. terminals tab together
automatically.

### 6.4 `autoproperties` — the *shorter*-than-you'd-think port

Because PekWM stacks by default, the bare `float = true` from most Hyprland
`window_rule`s is a **no-op** (already floating). Port only the non-float intent:

- **Workspace assignment** — `msg-apps` (Slack/Keybase/discord → ws1):
  ```
  Property = "^Slack,.*"   { ApplyOn = "Start New Workspace" Workspace = "0" }
  ```
  (⚠ `Workspace` is **0-indexed** here — `"0"` = first desktop; see §6.5.)
- **Sticky + undecorated + fixed geometry** — PiP analog:
  `Sticky = "True" Titlebar = "False" FrameGeometry = "600x338-40+40" Layer = "OnTop"`.
- **Autogroup** (optional nicety) — tab terminals together:
  `Property = "^kitty,.*" { ApplyOn = "New" Group = "term" { Size = "0" } }`.
- **Centered dialogs** — handled by `Placement` (§6.1); pinentry/file-choosers/
  pavucontrol need no explicit rule (they float+center already).
- **Dropped as X11-irrelevant:** Hyprland's `no_screen_share` (Bitwarden),
  `idle_inhibit`, XWayland ghost-window fixes, `suppress_event` — these are
  Wayland/Hyprland-specific and have no PekWM equivalent or need.

Every Property **must** include `ApplyOn` or it silently won't apply. Match strings
are regex (`^` anchors; use `.*` not `*`). Find class via `xprop WM_CLASS`.

### 6.5 ⚠ Indexing & quit gotchas (verified, save the laptop-Claude the pain)

- **Workspace indexing is inconsistent across contexts.** `autoproperties`
  `Workspace` counts from **0** (docs are explicit). The `keys` `GotoWorkspace N`
  int form reads `1` as the first desktop in default configs. Do **not** assume
  they share a base — set workspace autoprops 0-indexed, keybinds 1-indexed, and
  verify both live.
- **No default "quit WM" key** — must be bound explicitly (see table).

### 6.6 Theme — clean, low-eye-candy

1px border, thin titlebar (kept *because* it renders the grouping tabs), no shadows/
gradients/animation — matches the current Hyprland look (rounding 0, anim off,
border 1). Start from a trimmed built-in (`/usr/share/pekwm/themes/`) or a minimal
custom theme; nord-ish palette to match rofi. Decision deferred to the plan.

---

## 7. Polybar (replaces Waybar)

Rebuild the Waybar module set, desktop-tuned. New `config-pekwm.ini` (the legacy
`~/.config/polybar/config.ini` is *laptop*-flavored — battery/thinkpad sensor/
headset input — so it's a skeleton, not a drop-in).

- **Layout (mirrors Waybar):** left `xworkspaces` + window title; center clock
  (`date +'%-I:%M %p %F'`); right `pulseaudio · network · cpu · memory ·
  temperature · tray`.
- **Workspaces:** `internal/xworkspaces` (EWMH `_NET_*`), **not** `internal/i3` —
  PekWM is EWMH, not i3-IPC. (Verify at impl that PekWM publishes the EWMH desktop
  hints xworkspaces reads; PekWM has EWMH support.)
- **Desktop-tuning vs the legacy laptop config:** drop `battery`, `cmos-battery`
  (laptop), `xkeyboard`, headset `pulseaudio-control-input`; point `temperature`
  at the amdgpu/`x86_pkg_temp` zone (not `thinkpad_hwmon`); `network` →
  `interface = eth*` (matches Waybar). Optionally re-add `cmos-battery` via the
  existing `i3-cmos-battery polybar` custom-script module **iff** the desktop has
  the it87 sensor (it already speaks polybar output).
- **Look:** TX-02 + JetBrainsMono Nerd Font (both installed); nord-ish palette to
  match rofi. `tray` once (single bar, single tray).
- **Launch:** `~/.config/polybar/launch.sh` (`pkill polybar; polybar example &`),
  called from the autostart stack and rebound to `Super+Shift+W`.

---

## 8. Supporting stack & autostart

Launched from `pekwm/start` (or the `.xinitrc` tail), reproducing the Hyprland
`hyprland.start` hook minus Wayland bits:

- **Audio:** `pipewire` → `sleep 0.5 && wireplumber` → `sleep 1 && pipewire-pulse`
  (same staggered-sleep pattern; the FD-leak rationale in the Hyprland config
  applies identically).
- **Bar/notifications/wallpaper:** `~/.config/polybar/launch.sh`; **dunst** (X11
  notifications; `~/.config/dunst/dunstrc` already exists); **feh**
  `--bg-fill ~/projects/wallpapers/earth.jpg`.
- **Agents/applets:** `nm-applet`, `udiskie`, `flameshot`, polkit-gnome agent,
  `i3-mouse-setup` (solaar DPI; X11-agnostic).
- **Launcher:** rofi reused **unchanged** (already X11-capable; `config.rasi` +
  nord theme + TX-02 untouched).
- **Lock:** manual only, `Super+Shift+L` → `i3lock`.

---

## 9. Deferred / known gaps (honest scope)

| Gap | Why deferred | Path when wanted |
|---|---|---|
| `i3-screen-*` display mgmt | single monitor → moot | port wlr-randr/hyprctl → xrandr |
| Scratchpads / special ws (`Super+S/m/z`, `Super+Shift+V`) | PekWM has no native scratchpad | dedicated high workspace + autoprops + toggle script (phase 2) |
| Idle auto-lock / DPMS | manual lock suffices for a desktop | `xidlehook` → `i3lock` + `xset dpms` |
| Compositor | Jim chose none | add picom (effects off) if an app needs it |
| `no_screen_share`, idle-inhibit | Wayland-specific | n/a on X11 |

---

## 10. Validation checklist

Boot `start-pekwm`, then verify:

- [ ] X comes up on amdgpu via XLibre; no tearing (TearFree active); no vblank lockup.
- [ ] Polybar renders with live modules (clock, audio, net, cpu, mem, temp, tray).
- [ ] `Super+Space` → rofi drun; launches an app.
- [ ] Terminal / browser / emacs / lock binds fire.
- [ ] Workspace switch (`Super+1..0`) and send-to (`Super+Shift+1..0`); bar tracks them.
- [ ] **Grouping:** open two terminals, `Super+g` mark one, focus the other,
      `Super+Shift+G` attach; `Super+Tab` cycles the tabs.
- [ ] Volume/media keys; `Ctrl+F1` mic mute.
- [ ] `Print` → flameshot overlay.
- [ ] `notify-send test` → dunst notification.
- [ ] `Super+F1/F2/F3` focuses Slack/Keybase/discord (xdotool).
- [ ] Quit (`Super+Shift+Escape`) returns to TTY; `start-hyprland` still works
      unchanged.

---

## 11. Open risks / watch items

- **XLibre is young** — past vblank regression on this repo's record (§5). Hyprland
  is the fallback; keep it.
- **EWMH coverage** — confirm PekWM publishes the desktop/active-window hints
  Polybar's `xworkspaces` and `xdotool` rely on. If thin, fall back to a custom
  workspace module or `pekwm`'s own panel (`pekwm_panel`).
- **Workspace indexing inconsistency** (§6.5) — most likely first-boot foot-gun.
- **Config-dir XDG support** (§3 note) — verify before deciding symlink target.
