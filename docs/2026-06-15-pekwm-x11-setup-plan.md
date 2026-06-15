# PekWM + XLibre Desktop Session — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a low-eye-candy PekWM session on XLibre on `godlike-artix`, toggleable against the existing Hyprland session, reproducing the current keybind/bar/launcher/notification workflow.

**Architecture:** Additive and reversible. Config lives in the dotfiles repo (`~/projects/dotfiles`) and is symlinked into `$HOME`, anchored to PekWM's vendored upstream defaults so edits stay small and reviewable. Session entered from a TTY via a new `start-pekwm` wrapper → `startx` → `.xinitrc` → `exec pekwm`. Hyprland is untouched and remains the fallback.

**Tech Stack:** XLibre (`xlibre-xserver`), PekWM 0.4.4, Polybar, rofi (reused), dunst, feh, i3lock, pipewire stack, amdgpu/modesetting + TearFree. All from official Artix/Arch repos — zero AUR.

**Spec:** `docs/2026-06-15-pekwm-x11-setup.md` (read it first).

---

## Conventions for this plan

- **Two repos.** Config artifacts commit to **`~/projects/dotfiles`** (use `git -C ~/projects/dotfiles …`). This plan/spec lives in **`i3-screen-manager`** and is not modified during execution.
- **"Verify" replaces "test."** No unit-test harness exists for WM config; each task's verification is a concrete command or observable. The syntax-error class is caught by the Xephyr smoke-test (Task 12) and the TTY boot (Task 13).
- **Passwordless sudo** is authorized on this machine (Tasks 1, 11).
- **PekWM model:** pure stacking WM — every window floats by default; "frames" hold multiple clients as tabs (= window groups). Workspace indexing differs by context: `autoproperties` count from **0**, `keys`/`GotoWorkspace` from **1** (spec §6.5).

---

## File structure

| File | Responsibility | Repo path → symlink |
|---|---|---|
| `~/.pekwm/config` | Workspaces, placement, snap distances, file paths | `dotfiles/.pekwm-desktop/config` → `~/.pekwm` (dir symlink) |
| `~/.pekwm/keys` | Keybind parity (Global section) | same dir |
| `~/.pekwm/mouse` | Super-drag move/resize, focus-follows-mouse | same dir |
| `~/.pekwm/autoproperties` | Workspace assignment, sticky/PiP, autogroup | same dir |
| `~/.pekwm/menu` | Minimal root menu incl. Exit (powers the quit bind) | same dir |
| `~/.config/polybar/config-pekwm.ini` | Bar modules (Waybar parity, desktop-tuned) | `dotfiles/.config/polybar/` |
| `~/.config/polybar/launch.sh` | Bar (re)launch | `dotfiles/.config/polybar/` |
| `~/.xinitrc` | X env + autostart stack + `exec pekwm` | `dotfiles/.xinitrc` → `~/.xinitrc` |
| `~/.local/bin/start-pekwm` | TTY session launcher (env bootstrap + `startx`) | `dotfiles/.local/bin/start-pekwm` |
| `/etc/X11/xorg.conf.d/20-amdgpu.conf` | TearFree (root-owned; copied, not symlinked) | `dotfiles/etc/X11/xorg.conf.d/20-amdgpu.conf` (staged copy) |

---

## Task 1: Install packages

**Files:** none (system state).

- [ ] **Step 1: Install the X/WM/bar stack from official repos**

```bash
sudo pacman -S --needed --noconfirm \
  xlibre-xserver xlibre-input-libinput xorg-xinit pekwm polybar dunst feh i3lock xdotool \
  xorg-server-xephyr
```

> **`xorg-xinit` is mandatory** — it provides `startx`/`xinit`, which `start-pekwm`
> execs. A Wayland-only machine won't have it; omitting it fails the launcher at
> `exec: startx: not found` (discovered on godlike-artix at the first TTY boot). Its
> deps (`xorg-xauth`/`xorg-xrdb`/`xorg-xmodmap`) come along; the setuid `Xorg.wrap`
> (from `xlibre-xserver-common`) lets the active-VT user start X rootless.

(`xdotool` powers the focus-by-class binds — `wmctrl` is **not** in the official repos and AUR is off-limits, so xdotool is the substitute; `xorg-server-xephyr` is the nested-X smoke-test harness for Task 11. Both small, both official-repo.)

> **OBSERVED on godlike-artix (2026-06-15) — you WILL hit this on the laptop too:**
> the install stops with `xlibre-xserver-common and xorg-server-common are in conflict.
> Remove xorg-server-common? [y/N]` and `--noconfirm` aborts (defaults to No). This is
> **safe to accept**: `xlibre-xserver-common` *Provides* `xorg-server-common`, and the
> only thing depending on `xorg-server-common` is `xorg-xwayland` (Hyprland's XWayland)
> — pacman replaces the `-common` package and `xorg-xwayland` stays satisfied via the
> Provides (it is NOT removed). Verified post-install: `xorg-xwayland` still present,
> `/usr/bin/Xwayland` intact, `pactree -r xorg-server-common` shows
> `xlibre-xserver-common provides xorg-server-common → xorg-xwayland → hyprland`.
> Accept the replacement non-interactively with `yes | sudo pacman -S --needed …`
> (the only prompt in the transaction is this conflict removal). Reversible via
> `sudo pacman -S xorg-server-common`. `xorg-server` proper is not installed, so it's
> not part of the conflict.

- [ ] **Step 2: Verify all installed**

Run:
```bash
pacman -Q xlibre-xserver xlibre-input-libinput pekwm polybar dunst feh i3lock xdotool xorg-server-xephyr
```
Expected: a version line for each, no "was not found".

- [ ] **Step 3: Note the bundled video driver string** (for Task 10)

Run:
```bash
pacman -Ql xlibre-xserver | grep -E 'modesetting_drv|amdgpu_drv' || echo "check drivers dir"
ls /usr/lib/xorg/modules/drivers/ 2>/dev/null
```
Expected: confirms whether `modesetting_drv.so` (and/or `amdgpu_drv.so`) is present. Record which exists; Task 10's `Driver` line uses it.

No commit (system action).

---

## Task 2: Vendor PekWM upstream defaults as the baseline

**Files:**
- Create dir: `~/projects/dotfiles/.pekwm-desktop/`
- Symlink: `~/.pekwm` → `~/projects/dotfiles/.pekwm-desktop`

- [ ] **Step 1: Locate the shipped default config**

Run:
```bash
pacman -Ql pekwm | grep -E '/(config|keys|mouse|menu|autoproperties|start|vars)$'
```
Expected: paths under `/usr/share/pekwm/` or `/etc/pekwm/`. Record the directory (call it `$PEKWM_SHARE`).

- [ ] **Step 2: Copy defaults into the dotfiles repo**

```bash
mkdir -p ~/projects/dotfiles/.pekwm-desktop
# Replace /usr/share/pekwm with the dir found in Step 1 if different:
cp -r /usr/share/pekwm/config /usr/share/pekwm/keys /usr/share/pekwm/mouse \
      /usr/share/pekwm/menu /usr/share/pekwm/autoproperties /usr/share/pekwm/start \
      /usr/share/pekwm/vars ~/projects/dotfiles/.pekwm-desktop/ 2>/dev/null
# Autostart is owned by ~/.xinitrc (Task 8). Neutralize the vendored `start` so a
# pekwm in-session restart can't double-launch anything PekWM ships in it.
printf '#!/bin/sh\n# intentionally empty — autostart lives in ~/.xinitrc\n' \
  > ~/projects/dotfiles/.pekwm-desktop/start
chmod +x ~/projects/dotfiles/.pekwm-desktop/start
ls ~/projects/dotfiles/.pekwm-desktop/
```
Expected: `config keys mouse menu autoproperties start vars` present.

- [ ] **Step 3: Symlink `~/.pekwm` to the repo dir**

```bash
[ -e ~/.pekwm ] && mv ~/.pekwm ~/.pekwm.bak.$(date +%s)   # preserve any pre-existing
ln -s ~/projects/dotfiles/.pekwm-desktop ~/.pekwm
readlink ~/.pekwm
```
Expected: prints `/home/jim/projects/dotfiles/.pekwm-desktop`.

- [ ] **Step 4: Commit the untouched baseline (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .pekwm-desktop
git -C ~/projects/dotfiles commit -m "pekwm: vendor upstream default config as baseline"
```

---

## Task 3: PekWM `config` — workspaces, placement, snapping, file paths

**Files:** Modify `~/projects/dotfiles/.pekwm-desktop/config`

- [ ] **Step 1: Inspect the baseline to find the sections to edit**

Run:
```bash
grep -nE 'Workspaces|WorkspacesPerRow|FocusNew|Placement|Model|EdgeAttract|EdgeResist|WindowAttract|WindowResist|OpaqueMove|OpaqueResize|Theme =' ~/.pekwm/config
```
Expected: line numbers for the `Screen { … }`, `Placement { … }`, `MoveResize { … }`, and `Files { … }` keys below.

- [ ] **Step 2: Set the values** (edit in-place; each is an existing key in the vendored file)

In the `Screen { … }` block:
```
Workspaces = "10"
WorkspacesPerRow = "10"
FocusNew = "True"
```
In `Screen { … }` → `Placement { … }`:
```
Model = "Smart MouseNotUnder CenteredOnParent"
```
In the `Screen { … }` → `MoveResize { … }` block (snapping — the stacking-world stand-in for tiling, spec §6.1):
```
EdgeAttract = "10"
EdgeResist = "10"
WindowAttract = "10"
WindowResist = "10"
OpaqueMove = "True"
OpaqueResize = "True"
```
In `Files { … }`, confirm `Theme` points at an installed theme:
```
Theme = "/usr/share/pekwm/themes/default"
```
(Verify the path exists: `ls /usr/share/pekwm/themes/`. Pick any clean installed theme if `default` is absent.)

- [ ] **Step 3: Verify the edits landed**

Run:
```bash
grep -E 'Workspaces = "10"|WorkspacesPerRow = "10"|Model = "Smart|EdgeAttract = "10"|OpaqueMove = "True"' ~/.pekwm/config
```
Expected: all five lines echoed back.

- [ ] **Step 4: Commit (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .pekwm-desktop/config
git -C ~/projects/dotfiles commit -m "pekwm: 10 workspaces, smart placement, edge/window snapping"
```

---

## Task 4: PekWM `keys` — keybind parity (Global section)

**Files:** Modify `~/projects/dotfiles/.pekwm-desktop/keys`

- [ ] **Step 1: Replace the `Global { … }` section with the parity bindings**

Open `~/.pekwm/keys`. Leave the `MoveResize { … }`, `InputDialog { … }`, and any `Menu { … }`/keychain sections **as vendored** (the modal move/resize arrow bindings come from there untouched). Replace the entire `Global { … }` block with:

```
Global {
    # --- Applications ---
    KeyPress = "Mod4 Return"       { Actions = "Exec kitty" }
    KeyPress = "Mod4 Shift Return" { Actions = "Exec kitty --class KittyFloating" }
    KeyPress = "Mod4 b"            { Actions = "Exec brave --remote-debugging-port=9222 --profile-directory=Default --new-window" }
    KeyPress = "Mod4 e"            { Actions = "Exec emacs" }
    KeyPress = "Mod4 Shift b"      { Actions = "Exec rofi-rbw" }
    KeyPress = "Mod4 Shift l"      { Actions = "Exec i3lock -c 000000" }

    # --- Launcher / menu ---
    KeyPress = "Mod4 space"        { Actions = "Exec rofi -modi drun,run -show drun" }

    # --- Window management ---
    KeyPress = "Mod4 q"            { Actions = "Close" }
    KeyPress = "Mod4 f"            { Actions = "Maximize" }
    KeyPress = "Mod4 Shift f"      { Actions = "Toggle FullScreen" }
    KeyPress = "Mod4 Alt r"        { Actions = "MoveResize" }

    # --- Grouping (frames = Hyprland groups) ---
    KeyPress = "Mod4 g"            { Actions = "Toggle Marked" }
    KeyPress = "Mod4 Shift g"      { Actions = "AttachMarked" }
    KeyPress = "Mod4 Tab"          { Actions = "ActivateClientRel 1" }
    KeyPress = "Mod4 Shift Tab"    { Actions = "ActivateClientRel -1" }
    KeyPress = "Mod1 Tab"          { Actions = "NextFrameMRU" }
    KeyPress = "Mod1 Shift Tab"    { Actions = "PrevFrameMRU" }

    # --- Directional focus ---
    KeyPress = "Mod4 Left"         { Actions = "FocusDirectional Left" }
    KeyPress = "Mod4 Right"        { Actions = "FocusDirectional Right" }
    KeyPress = "Mod4 Up"           { Actions = "FocusDirectional Up" }
    KeyPress = "Mod4 Down"         { Actions = "FocusDirectional Down" }

    # --- Reorder client in frame / edge slam (stacking analogs of move) ---
    KeyPress = "Mod4 Shift Left"   { Actions = "MoveClientRel -1" }
    KeyPress = "Mod4 Shift Right"  { Actions = "MoveClientRel 1" }
    KeyPress = "Mod4 Shift Up"     { Actions = "MoveToEdge Top" }
    KeyPress = "Mod4 Shift Down"   { Actions = "MoveToEdge Bottom" }

    # --- Workspaces (GotoWorkspace is 1-indexed here; autoprops are 0-indexed) ---
    KeyPress = "Mod4 1" { Actions = "GotoWorkspace 1" }
    KeyPress = "Mod4 2" { Actions = "GotoWorkspace 2" }
    KeyPress = "Mod4 3" { Actions = "GotoWorkspace 3" }
    KeyPress = "Mod4 4" { Actions = "GotoWorkspace 4" }
    KeyPress = "Mod4 5" { Actions = "GotoWorkspace 5" }
    KeyPress = "Mod4 6" { Actions = "GotoWorkspace 6" }
    KeyPress = "Mod4 7" { Actions = "GotoWorkspace 7" }
    KeyPress = "Mod4 8" { Actions = "GotoWorkspace 8" }
    KeyPress = "Mod4 9" { Actions = "GotoWorkspace 9" }
    KeyPress = "Mod4 0" { Actions = "GotoWorkspace 10" }

    KeyPress = "Mod4 Shift 1" { Actions = "SendToWorkspace 1" }
    KeyPress = "Mod4 Shift 2" { Actions = "SendToWorkspace 2" }
    KeyPress = "Mod4 Shift 3" { Actions = "SendToWorkspace 3" }
    KeyPress = "Mod4 Shift 4" { Actions = "SendToWorkspace 4" }
    KeyPress = "Mod4 Shift 5" { Actions = "SendToWorkspace 5" }
    KeyPress = "Mod4 Shift 6" { Actions = "SendToWorkspace 6" }
    KeyPress = "Mod4 Shift 7" { Actions = "SendToWorkspace 7" }
    KeyPress = "Mod4 Shift 8" { Actions = "SendToWorkspace 8" }
    KeyPress = "Mod4 Shift 9" { Actions = "SendToWorkspace 9" }
    KeyPress = "Mod4 Shift 0" { Actions = "SendToWorkspace 10" }

    KeyPress = "Ctrl Mod1 Right" { Actions = "GotoWorkspace Right" }
    KeyPress = "Ctrl Mod1 Left"  { Actions = "GotoWorkspace Left" }

    # --- Quick-focus messaging apps (needs xdotool; wmctrl not in repos) ---
    KeyPress = "Mod4 F1" { Actions = "Exec xdotool search --class slack windowactivate" }
    KeyPress = "Mod4 F2" { Actions = "Exec xdotool search --class keybase windowactivate" }
    KeyPress = "Mod4 F3" { Actions = "Exec xdotool search --class discord windowactivate" }

    # --- Bar restart / keyboard layout ---
    KeyPress = "Mod4 Shift w"      { Actions = "Exec ~/.config/polybar/launch.sh" }
    KeyPress = "Mod4 Ctrl BackSpace" { Actions = "Exec i3-keyboard-rofi" }

    # --- Audio / media (identical to Hyprland; pipewire is session-agnostic) ---
    KeyPress = "XF86AudioRaiseVolume" { Actions = "Exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+" }
    KeyPress = "XF86AudioLowerVolume" { Actions = "Exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" }
    KeyPress = "XF86AudioMute"        { Actions = "Exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" }
    KeyPress = "Ctrl F1"              { Actions = "Exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle" }
    KeyPress = "XF86AudioPlay"        { Actions = "Exec playerctl play-pause" }
    KeyPress = "XF86AudioPause"       { Actions = "Exec playerctl play-pause" }
    KeyPress = "XF86AudioNext"        { Actions = "Exec playerctl next" }
    KeyPress = "XF86AudioPrev"        { Actions = "Exec playerctl previous" }

    # --- Screenshot ---
    KeyPress = "Print" { Actions = "Exec flameshot gui" }

    # --- Quit WM (confirm action matches the vendored menu's Exit entry, Step 2) ---
    KeyPress = "Mod4 Shift Escape" { Actions = "Exit" }
}
```

- [ ] **Step 2: Confirm the quit action name against the vendored menu**

Run:
```bash
grep -i exit ~/.pekwm/menu
```
Expected: an entry like `Entry = "Exit" { Actions = "Exit" }`. If the action string differs (e.g. some builds use a different token), change the `Mod4 Shift Escape` binding to match exactly what the menu's Exit entry uses.

- [ ] **Step 3: Commit (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .pekwm-desktop/keys
git -C ~/projects/dotfiles commit -m "pekwm: port Hyprland keybinds (Super-driven parity)"
```

(Syntax is validated at first launch — Task 12 Xephyr / Task 13 TTY. PekWM logs parse errors to stderr / `~/.pekwm/log`.)

---

## Task 5: PekWM `mouse` — Super-drag move/resize

**Files:** Modify `~/projects/dotfiles/.pekwm-desktop/mouse`

- [ ] **Step 1: Find the `Client { … }` and `Frame { … }`/`FrameTitle { … }` sections**

Run:
```bash
grep -nE '^(Client|Frame|FrameTitle|Border|ScreenEdge) \{' ~/.pekwm/mouse
```

- [ ] **Step 2: Add Super (Mod4) drag bindings inside the `Client { … }` section**

Add these three lines inside `Client { … }` (alongside the existing focus bindings; do not remove the vendored focus-follows-mouse `Enter` line):
```
ButtonPress  = "Mod4 1" { Actions = "Move" }
ButtonPress  = "Mod4 3" { Actions = "Resize" }
Motion       = "Mod4 1" { Threshold = "4"; Actions = "Move" }
```

- [ ] **Step 3: Verify focus-follows-mouse is intact**

Run:
```bash
grep -nE 'Enter = "Any Any"|Actions = "Focus"' ~/.pekwm/mouse
```
Expected: at least one `Enter … Focus` line present (matches Hyprland `follow_mouse = 1`). If absent, add `Enter = "Any Any" { Actions = "Focus" }` to `Client { … }`.

- [ ] **Step 4: Commit (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .pekwm-desktop/mouse
git -C ~/projects/dotfiles commit -m "pekwm: Super+drag move / Super+right-drag resize"
```

---

## Task 6: PekWM `autoproperties` — workspace assignment, PiP, autogroup

**Files:** Overwrite `~/projects/dotfiles/.pekwm-desktop/autoproperties`

- [ ] **Step 1: Write the autoproperties file** (stacking-aware port — bare `float` rules are no-ops here, spec §6.4; `Workspace` is 0-indexed)

```
# pekwm autoproperties — godlike-artix / PekWM trial.
# Match strings are regexp (^ anchors, .* not *). Find class via: xprop WM_CLASS.
# Workspace is 0-INDEXED here ("0" = first desktop) — keybinds are 1-indexed.

# Messaging apps -> first workspace (Hyprland msg-apps rule).
Property = "^[Ss]lack,.*" { ApplyOn = "Start New Workspace" Workspace = "0" }
Property = "^[Kk]eybase,.*" { ApplyOn = "Start New Workspace" Workspace = "0" }
Property = "^discord,.*"   { ApplyOn = "Start New Workspace" Workspace = "0" }

# Picture-in-Picture style: sticky, undecorated, fixed small geometry, on top.
# OLD-style title match (the `Title` keyword) — avoids needing
# `Require { Templates = "True" }` that the new 3-field syntax requires.
Property = ".*,.*" {
    Title = "Picture.?in.?[Pp]icture"
    ApplyOn = "Start New"
    Sticky = "True"
    Titlebar = "False"
    Border = "False"
    FrameGeometry = "600x338-40+40"
    Layer = "OnTop"
}

# Auto-tab terminals into one frame (optional grouping nicety; Size 0 = unlimited).
Property = "^kitty,.*" { ApplyOn = "New" Group = "term" { Size = "0" } }
```

- [ ] **Step 2: Verify the file is syntactically plausible (every Property has ApplyOn)**

Run:
```bash
grep -c 'Property =' ~/.pekwm/autoproperties
grep -c 'ApplyOn' ~/.pekwm/autoproperties
```
Expected: the two counts are equal (every Property carries an ApplyOn, or pekwm silently ignores it).

- [ ] **Step 3: Commit (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .pekwm-desktop/autoproperties
git -C ~/projects/dotfiles commit -m "pekwm: autoproperties (msg-apps workspace, PiP, term autogroup)"
```

---

## Task 7: Polybar config + launch script

**Files:**
- Create: `~/projects/dotfiles/.config/polybar/config-pekwm.ini`
- Create: `~/projects/dotfiles/.config/polybar/launch.sh`
- Symlink: `~/.config/polybar/config-pekwm.ini`, `~/.config/polybar/launch.sh`

- [ ] **Step 1: Write `config-pekwm.ini`** (Waybar module parity, desktop-tuned — EWMH `xworkspaces`, not `internal/i3`)

```ini
[colors]
background = #282A2E
foreground = #C5C8C6
primary    = #8ABEB7
alert      = #A54242
disabled   = #707880

[bar/main]
width = 100%
height = 28pt
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 2pt
padding-left = 1
padding-right = 2
module-margin = 1
separator = |
separator-foreground = ${colors.disabled}
font-0 = "TX-02:pixelsize=12;2"
font-1 = "JetBrainsMono Nerd Font:pixelsize=12;2"
enable-ipc = true

modules-left   = xworkspaces xwindow
modules-center = clock
modules-right  = pulseaudio network cpu memory temperature tray

[module/xworkspaces]
type = internal/xworkspaces
pin-workspaces = false
enable-click = true
enable-scroll = true
label-active = %name%
label-active-foreground = ${colors.primary}
label-active-padding = 1
label-occupied = %name%
label-occupied-padding = 1
label-empty = %name%
label-empty-foreground = ${colors.disabled}
label-empty-padding = 1

[module/xwindow]
type = internal/xwindow
label = %title:0:80:...%

[module/clock]
type = custom/script
exec = date +'%-I:%M %p %F'
interval = 60

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <ramp-volume> <label-volume>
label-volume = %percentage%%
label-muted = muted
label-muted-foreground = ${colors.disabled}
ramp-volume-0 = 
ramp-volume-1 = 
ramp-volume-2 = 
click-right = pavucontrol

[module/network]
type = internal/network
interface-type = wired
interval = 5
format-connected =  <label-connected>
label-connected = %ifname%
format-disconnected =  disconnected
format-disconnected-foreground = ${colors.alert}

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-foreground = ${colors.primary}
label = %percentage:2%%

[module/memory]
type = internal/memory
interval = 10
format-prefix = "RAM "
format-prefix-foreground = ${colors.primary}
label = %gb_used%/%gb_total%

[module/temperature]
type = internal/temperature
interval = 2
thermal-zone = 0
zone-type = x86_pkg_temp
warn-temperature = 80
format = <ramp> <label>
format-warn = <ramp> <label-warn>
label = %temperature-c%
label-warn = %temperature-c%
label-warn-foreground = ${colors.alert}
ramp-0 = 

[module/tray]
type = internal/tray
tray-size = 66%
tray-spacing = 8pt
```

> Note: `temperature` `thermal-zone`/`zone-type` may need adjustment — Step 4 verifies the live reading. The legacy laptop config's `thinkpad_hwmon` path is intentionally dropped.

- [ ] **Step 2: Write `launch.sh`**

```bash
#!/usr/bin/env bash
# Relaunch polybar for the PekWM session.
pkill -x polybar
sleep 0.3
polybar --config="$HOME/.config/polybar/config-pekwm.ini" main &
```

- [ ] **Step 3: Make executable and symlink both files**

```bash
chmod +x ~/projects/dotfiles/.config/polybar/launch.sh
ln -sf ~/projects/dotfiles/.config/polybar/config-pekwm.ini ~/.config/polybar/config-pekwm.ini
ln -sf ~/projects/dotfiles/.config/polybar/launch.sh        ~/.config/polybar/launch.sh
ls -l ~/.config/polybar/config-pekwm.ini ~/.config/polybar/launch.sh
```
Expected: both symlinks resolve into `~/projects/dotfiles/.config/polybar/`.

- [ ] **Step 4: Verify the bar config parses (no WM needed)**

Run:
```bash
polybar --config="$HOME/.config/polybar/config-pekwm.ini" --dump=width main 2>&1 | head
```
Expected: prints `100%` (config parsed). If a module errors, polybar names it — fix before committing. Confirm the temperature zone with `polybar -m` / `cat /sys/class/thermal/thermal_zone*/type` and adjust `thermal-zone` if `x86_pkg_temp` isn't zone 0.

- [ ] **Step 5: Commit (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .config/polybar/config-pekwm.ini .config/polybar/launch.sh
git -C ~/projects/dotfiles commit -m "polybar: PekWM bar (Waybar module parity, desktop-tuned)"
```

---

## Task 8: `.xinitrc` — X env + autostart stack + exec pekwm

**Files:**
- Create: `~/projects/dotfiles/.xinitrc`
- Symlink: `~/.xinitrc`

Autostart daemons live here (runs **once** per X session) rather than in pekwm's `start` file, so a PekWM in-session restart can't double-launch pipewire/agents.

- [ ] **Step 1: Write `.xinitrc`**

```bash
#!/bin/sh
# ~/.xinitrc — PekWM/X11 session contents on godlike-artix. Sourced by startx.
# Session/daemon bootstrap (D-Bus, locale, keyring, ssh-agent, VA-API, session
# identity, GIO_USE_VFS) is done by start-pekwm BEFORE `startx` and inherited
# here — do not duplicate it. This file only sets X-toolkit backends + autostart.

# --- X toolkit backends (force X11, not Wayland) ---
export QT_QPA_PLATFORM=xcb
export GDK_BACKEND=x11
export MOZ_ENABLE_WAYLAND=0
export _JAVA_AWT_WM_NONREPARENTING=1   # fixes grey-window Java/Swing under non-reparenting WMs

# --- Audio: pipewire -> wireplumber -> pipewire-pulse (staggered; see spec §8) ---
pipewire &
sleep 0.5 && wireplumber &
sleep 1   && pipewire-pulse &

# --- Bar / notifications / wallpaper ---
( sleep 1 && ~/.config/polybar/launch.sh ) &
dunst &
feh --bg-fill ~/projects/wallpapers/earth.jpg &

# --- Agents / applets ---
nm-applet &
udiskie &
flameshot &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
i3-mouse-setup &

# --- Window manager (replaces the shell; ends the session on exit) ---
exec pekwm
```

- [ ] **Step 2: Symlink and sanity-check shell syntax**

```bash
ln -sf ~/projects/dotfiles/.xinitrc ~/.xinitrc
sh -n ~/.xinitrc && echo "SYNTAX OK"
```
Expected: `SYNTAX OK` (no shell parse error). Confirm the wallpaper path exists: `ls ~/projects/wallpapers/earth.jpg`.

- [ ] **Step 3: Commit (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .xinitrc
git -C ~/projects/dotfiles commit -m "xinitrc: PekWM X11 session env + autostart stack"
```

---

## Task 9: `start-pekwm` launcher wrapper

**Files:**
- Create: `~/projects/dotfiles/.local/bin/start-pekwm`
- Symlink: `~/.local/bin/start-pekwm`

This is a faithful mirror of `start-hyprland`'s session/daemon bootstrap (verified against `~/.local/bin/start-hyprland` lines 7–60) minus the Wayland/Hyprland-specific bits. It is the *session* bootstrap — D-Bus, locale, keyring, ssh-agent, VA-API — all of which Artix/OpenRC does not provide automatically.

- [ ] **Step 1: Write `start-pekwm`** (verbatim — no fields to fill)

```bash
#!/usr/bin/env bash
# start-pekwm — launch the PekWM/X11 session from a TTY.
# Mirrors start-hyprland's session/daemon bootstrap (D-Bus, locale, keyring,
# ssh-agent, VA-API) minus Wayland/Hyprland bits, then hands off to startx.
# KEEP IN SYNC with ~/.local/bin/start-hyprland. No `set -e` — the idempotent
# blocks below intentionally tolerate nonzero exits (matches start-hyprland).

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Locale — OpenRC does not source /etc/locale.conf (no pam_systemd).
export LANG=en_US.UTF-8
export LC_COLLATE=C

# Session identity (X11/PekWM).
export XDG_CURRENT_DESKTOP=pekwm
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=pekwm

# D-Bus session bus — Artix/OpenRC does NOT auto-launch a per-user session bus.
# Without it every GDBus/libsecret client (nm-applet, gnome-keyring, brave) fails.
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
if [ ! -S "${XDG_RUNTIME_DIR}/bus" ]; then
    dbus-daemon --session --address="${DBUS_SESSION_BUS_ADDRESS}" --fork --syslog-only
    for _ in $(seq 1 40); do
        [ -S "${XDG_RUNTIME_DIR}/bus" ] && break
        sleep 0.05
    done
fi

# XCompose
export XCOMPOSEFILE="$HOME/.XCompose"

# AMD VA-API
export LIBVA_DRIVER_NAME=radeonsi

# GTK file dialog fix (gvfsd-trash 25s hang).
export GIO_USE_VFS=local

# gnome-keyring: secrets + pkcs11 only. The "ssh" component is deprecated upstream
# and silently breaks SSH — do NOT add it; the separate ssh-agent below owns SSH.
eval "$(gnome-keyring-daemon --start --components=secrets,pkcs11)"
export GNOME_KEYRING_CONTROL

# ssh-agent at a predictable socket (idempotent). Keys added manually via ssh-add.
# Note: ssh-agent.sock (not .socket) — must match start-hyprland for node-0/Open Brain.
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock"
if ! SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ssh-add -l >/dev/null 2>&1; then
    rm -f "$SSH_AUTH_SOCK"
    ssh-agent -a "$SSH_AUTH_SOCK" >/dev/null
fi

# Hand off to X; ~/.xinitrc execs pekwm.
exec startx ~/.xinitrc
```

- [ ] **Step 2: Confirm it still matches the current `start-hyprland`** (guards against drift)

Run:
```bash
grep -E 'ssh-agent.sock|components=secrets|DBUS_SESSION_BUS_ADDRESS|LIBVA_DRIVER_NAME|LANG=' ~/.local/bin/start-hyprland
```
Expected: the socket path (`ssh-agent.sock`), keyring components (`secrets,pkcs11`), dbus address, VA-API driver, and locale match the values baked into `start-pekwm` above. If `start-hyprland` has since drifted, reconcile.

- [ ] **Step 3: Make executable, symlink, syntax-check**

```bash
chmod +x ~/projects/dotfiles/.local/bin/start-pekwm
ln -sf ~/projects/dotfiles/.local/bin/start-pekwm ~/.local/bin/start-pekwm
bash -n ~/.local/bin/start-pekwm && echo "SYNTAX OK"
command -v start-pekwm
```
Expected: `SYNTAX OK`; `start-pekwm` resolves on PATH.

- [ ] **Step 4: Commit (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add .local/bin/start-pekwm
git -C ~/projects/dotfiles commit -m "start-pekwm: TTY launcher mirroring start-hyprland env bootstrap"
```

---

## Task 10: amdgpu TearFree (XLibre, no compositor)

**Files:**
- Create (root): `/etc/X11/xorg.conf.d/20-amdgpu.conf`
- Stage a copy: `~/projects/dotfiles/etc/X11/xorg.conf.d/20-amdgpu.conf`

- [ ] **Step 1: Write the staged copy in the repo** (use the `Driver` confirmed in Task 1 Step 3 — `modesetting` unless only `amdgpu_drv.so` exists)

```
Section "Device"
    Identifier "AMD"
    Driver     "modesetting"
    Option     "TearFree" "true"
EndSection
```

- [ ] **Step 2: Install it system-wide (root-owned; copied, not symlinked — XLibre reads it as root)**

```bash
sudo install -Dm644 ~/projects/dotfiles/etc/X11/xorg.conf.d/20-amdgpu.conf \
  /etc/X11/xorg.conf.d/20-amdgpu.conf
cat /etc/X11/xorg.conf.d/20-amdgpu.conf
```
Expected: the file echoes back at the system path.

- [ ] **Step 3: Commit the staged copy (dotfiles repo)**

```bash
git -C ~/projects/dotfiles add etc/X11/xorg.conf.d/20-amdgpu.conf
git -C ~/projects/dotfiles commit -m "xorg: amdgpu TearFree for the XLibre PekWM session"
```

---

## Task 11: Xephyr smoke-test (optional but recommended — catches syntax errors before TTY boot)

**Files:** none (validation only). Runs PekWM + Polybar nested inside the current Wayland session. **Does NOT** validate XLibre/amdgpu/TearFree or real input grabs (Super may be captured by Hyprland) — those are Task 12.

- [ ] **Step 1: Launch a nested X server**

```bash
Xephyr -br -ac -reset -screen 1600x900 :7 &
sleep 1
```
Expected: a 1600x900 black window appears.

- [ ] **Step 2: Start PekWM into it and watch for parse errors**

```bash
DISPLAY=:7 pekwm 2>&1 | tee /tmp/pekwm-xephyr.log &
sleep 1
grep -iE 'error|parse|warning|cannot|failed' /tmp/pekwm-xephyr.log || echo "no parse errors"
```
Expected: PekWM draws in the Xephyr window; `no parse errors` (or a named file:line to fix). Fix any reported config error in the relevant repo file, amend/commit, re-run.

- [ ] **Step 3: Start the bar in the nested display**

```bash
DISPLAY=:7 polybar --config="$HOME/.config/polybar/config-pekwm.ini" main 2>&1 | tee /tmp/polybar-xephyr.log &
sleep 1
grep -iE 'error|unknown|fail' /tmp/polybar-xephyr.log || echo "bar OK"
```
Expected: the bar renders at the top of the Xephyr window; modules populate; `bar OK`.

- [ ] **Step 4: Tear down**

```bash
pkill -f 'DISPLAY=:7' 2>/dev/null; pkill -x Xephyr 2>/dev/null; true
```

No commit unless config fixes were made (commit those to the relevant file in the dotfiles repo).

---

## Task 12: Live TTY validation (Jim) + iterate

**Files:** none initially; fixes fold back into the dotfiles repo + the spec's gotchas.

This is the real session and **cannot be driven from inside the current Claude Code session** — XLibre, amdgpu/TearFree, and real Super-key grabs only exist on a true TTY login. Hand the boot to Jim; iterate on findings.

- [ ] **Step 1: Boot the session** — from a TTY (e.g. Ctrl+Alt+F2), log in, run:

```bash
start-pekwm
```
Expected: XLibre starts on amdgpu; PekWM draws; Polybar appears; wallpaper set.

- [ ] **Step 2: Walk the spec §10 checklist** — rofi (`Super+Space`), terminal/browser/emacs/lock binds, workspace switch+send (`Super+1..0` / `Super+Shift+1..0`), **grouping** (open two kitty windows, `Super+g` mark one, focus the other, `Super+Shift+G` attach, `Super+Tab` cycle tabs), volume/media keys, `Print`→flameshot, `notify-send test`→dunst, `Super+F1/F2/F3` focus, then `Super+Shift+Escape` to quit and confirm `start-hyprland` still works untouched.

- [ ] **Step 3: Triage the likely first-boot foot-guns** (spec §6.5, §11)
  - Workspace indexing: if msg-apps land on the wrong desktop, the autoprops `Workspace` base is off — adjust (0-indexed).
  - No tearing: confirm TearFree took (`xrandr --verbose | grep -i tearfree` or visual scroll test). If absent, recheck the `Driver` string in Task 10.
  - EWMH: if Polybar `xworkspaces` shows nothing, PekWM's `_NET_*` desktop hints may be thin — fall back to `pekwm_panel` or a custom module (note it).
  - Quit: if `Super+Shift+Escape` doesn't exit, fix the action to match the menu's Exit entry (Task 4 Step 2).

- [ ] **Step 4: Fold fixes back** — commit any config changes to the dotfiles repo (per-file, as above); record any non-obvious gotcha in the spec's §11 (or a short "lessons" addendum) so the laptop replay benefits.

- [ ] **Step 5: Decide** — after living in it briefly, judge PekWM vs Hyprland (spec's framing: missing *tiling specifically* is the real signal; "windows land badly" is a snapping/placement tune, not a verdict).

---

## Notes on execution order & repos

- Tasks 1–10 can run start-to-finish in this session (system install, config authoring, Xephyr smoke-test). Task 12 is the human-in-the-loop TTY boot.
- **All config commits target `~/projects/dotfiles`.** Nothing in this implementation modifies the `i3-screen-manager` repo (only this plan/spec live there, already committed).
- Pushing the dotfiles repo is a separate explicit step — not part of any task above.

---

## Execution log & deviations — godlike-artix, 2026-06-15

Tasks 1–11 executed autonomously and committed to the dotfiles repo; **Task 12
(TTY boot) is the user's** and remains pending. What actually differed from the
task bodies above — apply these when replaying on the laptop:

1. **wmctrl → xdotool** (Task 1): `wmctrl` is not in the official repos; `xdotool`
   (world) substitutes for the `Super+F1/F2/F3` focus-by-class binds. Already
   reflected in Tasks 1/4.
2. **Install conflict (Task 1): `xlibre-xserver-common` vs `xorg-server-common`.**
   The install stops on this; accept it with `yes | sudo pacman -S --needed …`.
   `xorg-xwayland` survived via the Provides bridge — **Hyprland stayed intact**
   (verified: `/usr/bin/Xwayland` present, `pactree -r xorg-server-common` →
   `… provides xorg-server-common → xorg-xwayland → hyprland`). See the Task 1 note.
3. **PekWM config is modular** (Task 2): defaults live in **`/etc/pekwm/`** (not
   `/usr/share/pekwm`), with `INCLUDE`d sub-files (`config_system`, `keys_moveresize`,
   `mouse_system`, `autoproperties_typerules`) resolved via `$_PEKWM_ETC_PATH`.
   Vendored the whole tree: `cp -r /etc/pekwm/. ~/projects/dotfiles/.pekwm-desktop/`.
4. **Snapping was already on** (Task 3): `config_system` already defines `MoveResize{}`
   (EdgeAttract/WindowAttract/OpaqueMove). Only bumped `WindowAttract` to 10.
5. **keys: adopted native `FillEdge`** (Task 4) for `Super+Shift+arrows` half-screen
   snapping — better than the planned `MoveClientRel`/`MoveToEdge`. `Exit` confirmed
   a real action (default keychain). Replaced the whole `Global{}` block (lines
   11–280), kept the `INCLUDE` lines 1–9.
6. **mouse: no edit needed** (Task 5): `mouse_system` already binds `Mod4`-drag move
   and sloppy focus — matches Hyprland. Left vendored.
7. **autoproperties appended, not overwritten** (Task 6) — preserves the
   `autoproperties_typerules` include (DESKTOP/DOCK window-type handling).
8. **Polybar temp sensor: `k10temp`, not `x86_pkg_temp`** (Task 7): this AMD box has
   no `x86_pkg_temp` zone. Used `hwmon-path = /sys/class/hwmon/hwmon5/temp1_input`
   (k10temp Tctl). `hwmonN` can shift across reboots — re-find if the reading looks
   wrong. (Laptop differs: `thinkpad_hwmon`, per the legacy `polybar/config.ini`.)
9. **Session files suffixed + symlinked** (Tasks 8–9): `.xinitrc-desktop` (repo) →
   `~/.xinitrc`; `start-pekwm` (repo `.local/bin`) → `~/.local/bin`. The repo's bare
   `.xinitrc` is the stale laptop i3 one — left untouched. (Laptop: `start-pekwm`'s
   `LIBVA_DRIVER_NAME=radeonsi` is desktop-specific; the laptop needs intel/nvidia.)
10. **TearFree via `modesetting`** (Task 10): XLibre bundles `modesetting_drv.so`
    under `/usr/lib/xorg/modules/xlibre-25.0/drivers/`. `xf86-video-amdgpu` (world)
    is the fallback if modesetting misbehaves.
11. **Xephyr smoke-test: PASS** (Task 11): pekwm parsed `~/.pekwm/config` and ran;
    polybar loaded all 9 modules. **Known cosmetic issue:** `fc-match "TX-02"`
    resolves to FreeSans on this machine (an fc-match-level quirk — Waybar/rofi use
    TX-02 fine via GTK/pango), so polybar renders the TX-02 slots in FreeSans.
    Non-blocking; tune at the TTY or investigate the system fontconfig TX-02 mapping.

### First TTY boot — Task 12 (2026-06-15)

`start-pekwm` failed immediately at `exec: startx: not found`. **Root cause:
`xorg-xinit` was never installed** (a Wayland-only box has no `startx`/`xinit`) —
a gap in the Task 1 list, now fixed there. Installed `xorg-xinit` (pulls
`xorg-xauth`/`xorg-xrdb`/`xorg-xmodmap`); confirmed `/usr/lib/Xorg.wrap` is setuid
and XLibre provides `/usr/bin/X`, so the rootless-X chain is complete. The
`keyring/control: No such file` line in the error log is benign first-run noise,
not the failure. Retry pending.

### In-session refinements (2026-06-15) — PekWM live tweaks

After the session came up, a few adjustments (all in the vendored pekwm config,
applied live with `pekwm_ctrl -a run Reload`):
- **Super + right-drag = resize** — added `Client { Motion = "Mod4 3" {...Resize} }`
  to `mouse` (the default only gave Super+left-drag = move).
- **Super + Shift + M = maximize + hide titlebar** — `Toggle Maximized True True;
  Toggle DecorTitlebar` in `keys` (distinct from FullScreen: keeps the bar).
- Snapping needed no work — `EdgeAttract`/`WindowAttract` (config_system) +
  `FillEdge` half-screen (`Super+Shift+arrows`) + the `Ctrl+Super+C` corner chain
  are all default.

### Flameshot under dual-WM + the stale-portal trap (2026-06-15)

Running Flameshot under BOTH WMs needs different capture backends, and bouncing
between them corrupts the Wayland portal — two separate problems:

- **Per-session backend.** PekWM/X11 has no `xdg-desktop-portal` Screenshot backend
  (none exists for a bare X11 WM), so Flameshot must bypass the portal:
  `useX11LegacyScreenshot=true` (Qt native X11 grab). Hyprland/Wayland needs the
  *opposite* — the portal (`xdg-desktop-portal-hyprland`); the legacy flag breaks it.
  **Toggle:** two configs `~/.config/flameshot/flameshot-{wayland,x11}.ini`; each
  launcher `cp`s the right one onto `flameshot.ini` before `exec` — **copy, not
  symlink** (Qt QSettings atomic-writes would clobber a symlink).
- **Stale-portal trap.** Every Hyprland start spawns an `xdg-desktop-portal`
  frontend; switching to PekWM and back leaves the old ones alive. A leftover
  frontend squats the `org.freedesktop.portal.Desktop` D-Bus name unresponsively →
  Flameshot (and any portal screenshot) hangs, while `grim` (direct wlroots
  screencopy) still works — that asymmetry is the diagnostic tell. **Fix:** both
  launchers reap stale `xdg-desktop-portal*` at start, **matched by executable, not
  cmdline** (a `pkill -f xdg-desktop-portal` matches — and kills — the launcher's own
  shell). Health check:
  `busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep Screenshot`.

### Commit trail
dotfiles: `vendor baseline → config/keys/vars → autoproperties → polybar →
session files → xorg TearFree → gitignore runtime`. i3-screen-manager: spec, plan,
execution log, wmctrl→xdotool, CLAUDE.md pointer + research-note loop-closure.
**Both repos pushed** (the `xorg-xinit` fix above lands in a follow-up commit).
