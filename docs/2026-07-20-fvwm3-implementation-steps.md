# FVWM3 Desktop Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up FVWM3 as a third, parallel session on `godlike-artix` with genuinely independent per-monitor workspaces, 2px flat borders, no window chrome, Super+mouse move/resize, and a hybrid FvwmPager + Polybar bar.

**Architecture:** All new files under `~/projects/dotfiles`, symlinked into `~` the way `.icewm` already is. A split FVWM3 config (`config` reads four sub-files) mirroring the existing `.icewm/` multi-file convention. Nothing existing is modified — IceWM and Hyprland are untouched, and reverting means simply not running `start-fvwm3`.

**Tech Stack:** fvwm3 1.1.5 (Artix `galaxy`), polybar 3.7.2 (installed), rofi 2.0.0-1 (installed), Xephyr (installed) + `dbus-run-session` for validation.

**Design spec:** `docs/2026-07-20-fvwm3-desktop-setup-plan.md` (committed `5ddf8a6`). Read it before starting; this plan implements it and does not restate its rationale.

## Global Constraints

- **Additive and reversible.** Create new files only. Do NOT modify `.icewm/`, `.icewm-laptop/`, `.xinitrc-icewm`, `.config/hypr/*`, or `.local/bin/start-icewm`.
- **No AUR, ever.** Official Artix/Arch repos only (June 2026 AUR malware incident). `fvwm3` is in `galaxy`.
- **Always dry-run package removals** on Artix: `pacman -Rsp` before any `-Rs`. This plan removes nothing.
- **Never `git add -A` or `git add .`** — stage named files only.
- **Commit messages end with:**
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Syntax authority is the shipped man page**, not the web. During research an AI source produced a confident but fabricated quote of `DesktopConfiguration`. Verify with `man fvwm3commands` / `man fvwm3styles` if in doubt.
- **Monitor names:** `DP-2` (2560x1440 landscape, primary, at `+0+240`) and `HDMI-1` (1200x1920 portrait, at `+2560+0`). Under Wayland the second is `HDMI-A-1`; that name is **wrong** here — X11/xrandr is `HDMI-1`.
- **Desks are 0-indexed.** `Super+1` → desk 0 … `Super+0` → desk 9.
- **These are config files, not code.** "Tests" are observable checks (`xprop`, `xdotool`, `FvwmCommand`, visual confirmation under Xephyr), not unit tests. Each task still ends with a check that can fail before the change and pass after.

---

### Task 1: Install fvwm3 and create the inert skeleton

Nothing becomes live in this task. Goal is a launchable session that starts, draws nothing surprising, and can be exited.

**Files:**
- Create: `~/projects/dotfiles/.fvwm3/config`
- Create: `~/projects/dotfiles/.fvwm3/styles` (empty placeholder — filled in Task 2)
- Create: `~/projects/dotfiles/.fvwm3/bindings` (empty placeholder — filled in Task 3)
- Create: `~/projects/dotfiles/.fvwm3/modules` (empty placeholder — filled in Task 4)
- Create: `~/projects/dotfiles/.fvwm3/autostart` (empty placeholder — filled in Task 6)

**Interfaces:**
- Produces: `~/.fvwm3/config` as the entry point, which `Read`s `styles`, `bindings`, `modules`, `autostart` from `$[FVWM_USERDIR]`. All later tasks fill those four files and add nothing new to `config` except where stated.

- [ ] **Step 1: Verify fvwm3 is available and not installed**

```bash
pacman -Q fvwm3 2>/dev/null || echo "not installed (expected)"
pacman -Si fvwm3 | head -4
```
Expected: `not installed (expected)`, then `Repository : galaxy`, `Version : 1.1.5-1`.

- [ ] **Step 2: Install it**

```bash
sudo pacman -S --noconfirm fvwm3
fvwm3 --version | head -2
```
Expected: version reports `1.1.5`.

- [ ] **Step 3: Create the config directory and the entry point**

```bash
mkdir -p ~/projects/dotfiles/.fvwm3
```

Write `~/projects/dotfiles/.fvwm3/config`:

```
# ~/.fvwm3/config — godlike-artix (desktop). Entry point only; the real
# content lives in the four files Read at the bottom, mirroring the
# .icewm/{preferences,keys,winoptions} split. See i3-screen-manager
# docs/2026-07-20-fvwm3-desktop-setup-plan.md for the design and rationale.
#
# Syntax here is quoted from the SHIPPED fvwm3 1.1.5 man pages
# (fvwm3, fvwm3commands, fvwm3styles). Do not trust web sources for fvwm3 —
# they are frequently wrong about DesktopConfiguration in particular.

#-----------------------------------------------------------------------------
# DESKTOPS — the entire reason this WM was chosen.
#
# per-monitor: "each RandR monitor has a separate copy of desktops, and hence
# function independently of one another when switching desks/pages."
#   -- fvwm3commands(1), DesktopConfiguration
#
# The shipped default-config ships `global`; per-monitor is opt-in.
#-----------------------------------------------------------------------------
DesktopConfiguration per-monitor

# 1x1 disables the 2D page grid entirely, so a "desk" behaves like an
# IceWM/Hyprland workspace. Without this, fvwm also pans a viewport within
# each desk, which is a different muscle memory for no gain here.
DesktopSize 1x1

#-----------------------------------------------------------------------------
# Sub-files. $[FVWM_USERDIR] expands to ~/.fvwm3 .
#-----------------------------------------------------------------------------
Read $[FVWM_USERDIR]/styles
Read $[FVWM_USERDIR]/bindings
Read $[FVWM_USERDIR]/modules
Read $[FVWM_USERDIR]/autostart
```

- [ ] **Step 4: Create the four sub-files as valid empty stubs**

An empty file is valid fvwm config, so this keeps `Read` from erroring before later tasks fill them.

```bash
cd ~/projects/dotfiles/.fvwm3
printf '# ~/.fvwm3/styles — filled in Task 2\n'    > styles
printf '# ~/.fvwm3/bindings — filled in Task 3\n'  > bindings
printf '# ~/.fvwm3/modules — filled in Task 4\n'   > modules
printf '# ~/.fvwm3/autostart — filled in Task 6\n' > autostart
ls -la ~/projects/dotfiles/.fvwm3/
```
Expected: five files.

- [ ] **Step 5: Symlink into `~`, matching how `.icewm` is deployed**

```bash
ln -sfn ~/projects/dotfiles/.fvwm3 ~/.fvwm3
stat -c '%N' ~/.fvwm3
```
Expected: `'/home/jim/.fvwm3' -> '/home/jim/projects/dotfiles/.fvwm3'`

- [ ] **Step 6: Check it parses under Xephyr — the failing-then-passing gate**

Run BEFORE trusting anything. Two fake monitors via `+xinerama`:

```bash
Xephyr -screen 1200x800 -screen 800x600 +xinerama :2 >/dev/null 2>&1 &
sleep 2
dbus-run-session -- env DISPLAY=:2 fvwm3 -f ~/.fvwm3/config 2>&1 | head -20 &
sleep 3
DISPLAY=:2 xterm -geometry 40x10 &
sleep 2
DISPLAY=:2 xdotool search --class xterm | head -1
```
Expected: an xterm window appears inside the Xephyr window and `xdotool` prints a window id. No fvwm parse errors in the output.

> **Xephyr caveat (spec §10):** launch only dumb X clients — `xterm`, `xeyes`,
> `xclock`. `ghostty`, `brave-origin` and `emacs` are all single-instance and
> will hand off to their live `:0` instance, opening the window on your REAL
> desktop. `dbus-run-session` above blocks the D-Bus-activation half of that.

- [ ] **Step 7: Tear down**

```bash
pkill -f "DISPLAY=:2" ; pkill -f "Xephyr.*:2" ; echo "torn down"
```

- [ ] **Step 8: Commit**

```bash
cd ~/projects/dotfiles
git add .fvwm3/config .fvwm3/styles .fvwm3/bindings .fvwm3/modules .fvwm3/autostart
git commit -m "$(cat <<'MSG'
feat(fvwm3): inert config skeleton with per-monitor desktops

Entry point plus four empty sub-files, mirroring the .icewm/ split.
DesktopConfiguration per-monitor is set here — the whole reason for the
WM choice — with DesktopSize 1x1 to disable fvwm's 2D page grid so a desk
behaves like an IceWM/Hyprland workspace.

Nothing is live: no session launcher yet, IceWM and Hyprland untouched.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: Styles — 2px flat borders, no chrome, SloppyFocus

**Files:**
- Modify: `~/projects/dotfiles/.fvwm3/styles` (replace stub)

**Interfaces:**
- Consumes: `config` from Task 1 (`Read $[FVWM_USERDIR]/styles`).
- Produces: colorsets `10` (unfocused border) and `11` (focused border), referenced by nothing else but reserved — do not reuse those numbers in later tasks.

- [ ] **Step 1: Define the check that currently fails**

Under Xephyr with only Task 1 applied, windows have default fvwm decorations — a title bar and thick borders. That is the "failing test". Confirm it:

```bash
Xephyr -screen 1200x800 -screen 800x600 +xinerama :2 >/dev/null 2>&1 &
sleep 2
dbus-run-session -- env DISPLAY=:2 fvwm3 -f ~/.fvwm3/config >/dev/null 2>&1 &
sleep 3
DISPLAY=:2 xterm -geometry 40x10 &
sleep 2
```
Expected: the xterm has a **title bar**. This is what Task 2 removes.

- [ ] **Step 2: Write the styles**

Write `~/projects/dotfiles/.fvwm3/styles`:

```
# ~/.fvwm3/styles — look and window behaviour.
# Palette carried verbatim from .icewm/preferences so the two X11 sessions
# read as siblings: ColorActiveBorder rgb:33/CC/FF, ColorNormalBorder
# rgb:55/5a/5f.

#-----------------------------------------------------------------------------
# Colorsets. Syntax: Colorset <num> <comma-separated options>
# (fvwm3commands(1): "options is a comma separated list containing some of
# the keywords: fg, Fore, Foreground, bg, Back, Background, ...")
#
# 10 = unfocused window border, 11 = focused window border.
# Numbers kept small on purpose: "The highest colorset number used determines
# memory consumption."  -- fvwm3commands(1)
#-----------------------------------------------------------------------------
Colorset 10 fg #c5c8c6, bg #555a5f
Colorset 11 fg #ffffff, bg #33ccff

#-----------------------------------------------------------------------------
# No chrome, 2px border.
#
# !Handles is what makes BorderWidth govern: "!Handles, the width from the
# BorderWidth style is used."  -- fvwm3styles(1)
#
# BorderColorset takes EIGHT colorsets (one per border component), but "if one
# integer is supplied, that is applied to all window border components" — which
# is what yields a genuinely FLAT, uniform border. IceWM cannot do this; it
# colour-computes a Win95 bevel on every Look (see docs/2026-06-16-icewm-x11-
# setup.md). This is a real improvement over the session being mirrored.
#-----------------------------------------------------------------------------
Style * !Title, !Handles, BorderWidth 2
Style * BorderColorset 10, HilightBorderColorset 11

#-----------------------------------------------------------------------------
# Focus. SloppyFocus, NOT IceWM's ClickToFocus — a deliberate departure.
#
# Monitor switching here is pointer-driven ($[monitor.current] is defined as
# "the monitor which has the mouse pointer"), so under ClickToFocus you would
# warp the pointer to the other monitor and still be typing into the old
# window. SloppyFocus "is similar [to MouseFocus], but doesn't give up the
# focus [when the pointer] leaves the window" -- fvwm3styles(1), which avoids
# focus dropping to the root window as the pointer crosses empty space.
#-----------------------------------------------------------------------------
Style * SloppyFocus

# Sensible placement for a stacking WM with no titlebars to grab.
Style * MinOverlapPlacement
Style * DecorateTransient
```

- [ ] **Step 3: Restart fvwm inside Xephyr and re-check**

```bash
DISPLAY=:2 FvwmCommand Restart 2>/dev/null || { pkill -f "fvwm3 -f" ; sleep 1; dbus-run-session -- env DISPLAY=:2 fvwm3 -f ~/.fvwm3/config >/dev/null 2>&1 & }
sleep 3
```

- [ ] **Step 4: Verify visually and by geometry**

Expected, by eye in the Xephyr window:
- xterm has **no title bar**
- border is **2px**, **uniform** (no 3D bevel, no lighter/darker edges)
- focused border is cyan `#33ccff`, unfocused is slate `#555a5f`

Move the pointer off the xterm onto the Xephyr root and back; focus should follow the pointer onto the window and NOT drop to root in between.

- [ ] **Step 5: Tear down and commit**

```bash
pkill -f "DISPLAY=:2" ; pkill -f "Xephyr.*:2"
cd ~/projects/dotfiles
git add .fvwm3/styles
git commit -m "$(cat <<'MSG'
feat(fvwm3): 2px flat borders, no titlebars, SloppyFocus

Palette carried verbatim from .icewm/preferences so the two X11 sessions
look like siblings.

Notable: a single-integer BorderColorset applies to all eight border
components, giving a genuinely FLAT uniform border. IceWM cannot do this —
it colour-computes a Win95 bevel on every Look, which the IceWM setup doc
records as an unavoidable compromise. It is avoidable here.

SloppyFocus is a deliberate departure from IceWM's ClickToFocus: monitor
switching is pointer-driven, so ClickToFocus would strand keyboard focus on
the old monitor after a warp.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: Bindings — Super+mouse, desks, monitor warp, apps

This is the task that proves per-monitor desks actually work. **If Step 6 fails, stop and reassess the whole project** — everything else is cosmetic by comparison.

**Files:**
- Modify: `~/projects/dotfiles/.fvwm3/bindings` (replace stub)

**Interfaces:**
- Consumes: `config` from Task 1.
- Produces: function `SwitchMonitor` (takes `$0` = a RandR monitor name) — not used elsewhere in this plan, but available if the pointer-only approach needs augmenting later.

- [ ] **Step 1: Write the bindings**

Write `~/projects/dotfiles/.fvwm3/bindings`:

```
# ~/.fvwm3/bindings — keyboard and mouse.
# Syntax (fvwm3commands(1)):
#   Key   [(window)] Keyname Context Modifiers Function
#   Mouse [(window)] Button  Context Modifiers Function
# Context: W = application window, S = window side/border, A = any, R = root.
# Modifiers: 4 = Mod4 = Super.  N = none.
#
# NB: with `Style * !Title, !Handles` every window is UNDECORATED, and
# "Only 'S' and 'W' are valid for an undecorated window" -- fvwm3commands(1).
# That is a hard constraint, not a preference: do not use T/F/[/] contexts.

#-----------------------------------------------------------------------------
# Super + mouse — ports IceWM's MouseWinMove / MouseWinSize
#   MouseWinMove="Super+Pointer_Button1"
#   MouseWinSize="Super+Pointer_Button3"
#-----------------------------------------------------------------------------
Mouse 1 W 4 Move
Mouse 3 W 4 Resize

#-----------------------------------------------------------------------------
# Desks. Two args to GotoDesk are "a relative and an absolute desk number",
# so a leading 0 means "no relative move" and the second arg is the target.
# Desks are 0-INDEXED, so the key labelled 1 goes to desk 0 — matching the
# existing IceWM binds, which already use `icesh -f setWorkspace 0` for key 1.
#
# No `screen` argument on purpose: without it the CURRENT monitor is used,
# which is exactly the per-monitor behaviour we want.
#-----------------------------------------------------------------------------
Key 1 A 4 GotoDesk 0 0
Key 2 A 4 GotoDesk 0 1
Key 3 A 4 GotoDesk 0 2
Key 4 A 4 GotoDesk 0 3
Key 5 A 4 GotoDesk 0 4
Key 6 A 4 GotoDesk 0 5
Key 7 A 4 GotoDesk 0 6
Key 8 A 4 GotoDesk 0 7
Key 9 A 4 GotoDesk 0 8
Key 0 A 4 GotoDesk 0 9

# Send the focused window to a desk without following it.
Key 1 A 4S MoveToDesk 0 0
Key 2 A 4S MoveToDesk 0 1
Key 3 A 4S MoveToDesk 0 2
Key 4 A 4S MoveToDesk 0 3
Key 5 A 4S MoveToDesk 0 4
Key 6 A 4S MoveToDesk 0 5
Key 7 A 4S MoveToDesk 0 6
Key 8 A 4S MoveToDesk 0 7
Key 9 A 4S MoveToDesk 0 8
Key 0 A 4S MoveToDesk 0 9

#-----------------------------------------------------------------------------
# Monitor switching — pointer-driven, and that is the whole trick.
#
# "$[monitor.current] ... the monitor which has the mouse pointer"  -- fvwm3(1)
#
# So warping the pointer ALSO retargets the desk keys above. One keybind does
# both jobs. $[monitor.prev] is "the previously focused monitor", giving a
# toggle that keeps working if a third monitor is ever added.
#
# CursorMove's screen form: "move the cursor to the absolute position ... as
# either percent values of the monitor's size" -- so 50 50 is dead centre.
#-----------------------------------------------------------------------------
Key grave A 4 CursorMove screen $[monitor.prev] 50 50
Key grave A 4S MoveToScreen $[monitor.prev]

# Explicit per-monitor warp, in case the toggle is not enough.
DestroyFunc SwitchMonitor
AddToFunc   SwitchMonitor
+ I CursorMove screen $0 50 50

Key bracketleft  A 4 SwitchMonitor DP-2
Key bracketright A 4 SwitchMonitor HDMI-1

#-----------------------------------------------------------------------------
# Applications — ported 1:1 from .icewm/keys.
#-----------------------------------------------------------------------------
Key Return A 4  Exec exec ghostty
Key Return A 4S Exec exec ghostty --x11-instance-name=ghostty-floating
Key b      A 4  Exec exec brave-origin --remote-debugging-port=9222 --profile-directory=Default --new-window
Key y      A 4  Exec exec brave-origin --remote-debugging-port=9222 '--profile-directory=Profile 3' --new-window
Key e      A 4  Exec exec emacs
Key b      A 4S Exec exec rofi-rbw
Key l      A 4S Exec exec i3lock -c 000000
Key space  A 4  Exec exec rofi -modi drun,run -show drun
Key d      A 4  Exec exec rofi -show run
Key Tab    A 4  Exec exec rofi -show window
Key Print  A N  Exec exec flameshot gui
Key BackSpace A 4C Exec exec /home/jim/.local/bin/i3-keyboard-rofi

#-----------------------------------------------------------------------------
# Window management
#-----------------------------------------------------------------------------
Key q     A 4  Close
Key Up    A 4  Maximize True
Key Down  A 4  Maximize False
Key Tab   A M  Next (CurrentDesk, !Iconic) Focus

# NB: there is NO `Fullscreen` command in fvwm3 — `fullscreen` is a FLAG to
# Maximize ("following key words: fullscreen, ewmhiwa, growonwindowlayer ...").
# Writing `Fullscreen toggle` fails silently. This mirrors IceWM's
# KeyWinFullscreen="Super+Shift+f".
Key f     A 4S Maximize fullscreen

#-----------------------------------------------------------------------------
# Media keys — verbatim from .icewm/keys
#-----------------------------------------------------------------------------
Key XF86AudioRaiseVolume A N Exec exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
Key XF86AudioLowerVolume A N Exec exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
Key XF86AudioMute        A N Exec exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
Key XF86AudioPlay        A N Exec exec playerctl play-pause
Key XF86AudioNext        A N Exec exec playerctl next
Key XF86AudioPrev        A N Exec exec playerctl previous

#-----------------------------------------------------------------------------
# Session exit — back to the TTY, mirroring Super+Shift+Escape under IceWM.
#-----------------------------------------------------------------------------
Key Escape A 4S Quit
```

- [ ] **Step 2: Restart under Xephyr**

```bash
Xephyr -screen 1200x800 -screen 800x600 +xinerama :2 >/dev/null 2>&1 &
sleep 2
dbus-run-session -- env DISPLAY=:2 fvwm3 -f ~/.fvwm3/config >/dev/null 2>&1 &
sleep 3
```

- [ ] **Step 3: Verify Super+mouse move**

```bash
DISPLAY=:2 xterm -geometry 40x10 &
sleep 2
```
Hold Super and drag the xterm with the LEFT button — it should move. Hold Super and drag with the RIGHT button — it should resize. Both without any titlebar to grab.

- [ ] **Step 4: Put a marker window on each fake monitor**

```bash
DISPLAY=:2 xterm -geometry 30x8+50+50    -T LEFTMON  &
sleep 1
DISPLAY=:2 xterm -geometry 30x8+1250+50  -T RIGHTMON &
sleep 2
```
Expected: one xterm on each half of the Xephyr window (screen 0 is 1200 wide, so `+1250` lands on screen 1).

- [ ] **Step 5: Verify desks switch at all**

Put the pointer over LEFTMON, press `Super+2`, then `Super+1`. LEFTMON should disappear and reappear.

- [ ] **Step 6: THE CRITICAL CHECK — per-monitor independence**

1. Pointer over the LEFT monitor. Press `Super+2`. LEFTMON vanishes (desk 1 is empty).
2. **Look at the RIGHT monitor. RIGHTMON must still be visible.**

```bash
DISPLAY=:2 xdotool search --name RIGHTMON getwindowgeometry
```
Expected: RIGHTMON still mapped and on screen.

**PASS** = per-monitor desks work; this is the entire premise of the project.
**FAIL** = `DesktopConfiguration per-monitor` is not taking effect. Do not
proceed. Check `DISPLAY=:2 FvwmCommand 'Echo $[monitor.current]'`, confirm
Xephyr really presented two Xinerama monitors (`DISPLAY=:2 xrandr --listmonitors`
should show 2), and re-read `man fvwm3commands` on `DesktopConfiguration`.

- [ ] **Step 7: Verify the monitor warp retargets desk keys**

With the pointer on the LEFT monitor:
```bash
DISPLAY=:2 FvwmCommand 'Echo current=$[monitor.current]'
```
Press `Super+grave`, then re-run the same command. Expected: the reported monitor **changes**. Then press `Super+3` and confirm the desk change lands on the monitor the pointer just moved to, not the one it left.

- [ ] **Step 8: Tear down and commit**

```bash
pkill -f "DISPLAY=:2" ; pkill -f "Xephyr.*:2"
cd ~/projects/dotfiles
git add .fvwm3/bindings
git commit -m "$(cat <<'MSG'
feat(fvwm3): keybinds, Super+mouse, and pointer-driven monitor switching

Ports .icewm/keys 1:1 (apps, media, screenshot, lock) and IceWM's
MouseWinMove/MouseWinSize as `Mouse 1 W 4 Move` / `Mouse 3 W 4 Resize`.

Contexts are restricted to W and S by necessity, not taste: with
`Style * !Title, !Handles` every window is undecorated, and fvwm3commands(1)
states only S and W are valid for an undecorated window.

Monitor switching is one keybind rather than two. $[monitor.current] is
DEFINED as the monitor holding the pointer, so CursorMove both warps you and
retargets the desk keys; $[monitor.prev] makes it a toggle that still works
if a third monitor appears.

Desks are 0-indexed, so Super+1 -> desk 0, matching the existing IceWM binds.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: FvwmPager — one per monitor, with MiniIcons

**Files:**
- Modify: `~/projects/dotfiles/.fvwm3/modules` (replace stub)

**Interfaces:**
- Consumes: `config` from Task 1; desks defined by `DesktopSize`/`DesktopConfiguration` there.
- Produces: two module aliases, `FvwmPagerDP2` and `FvwmPagerHDMI1`, started from `StartFunction`. Task 6's `autostart` must NOT also start them.

- [ ] **Step 1: Write the module config**

The structure below follows the worked example in `FvwmPager(1)`, which uses `DP-2` as its own sample monitor name.

Write `~/projects/dotfiles/.fvwm3/modules`:

```
# ~/.fvwm3/modules — FvwmPager, one instance per monitor.
#
# "FvwmPager fully supports multiple monitors and fvwm's DesktopConfiguration.
#  The Monitor option can be used to show only the windows and virtual desktop
#  area used by specific monitor."  -- FvwmPager(1)
#
# MiniIcons: "Allow the pager to display a window's mini icon in the pager, if
# it has one, instead of showing the window's label." -- FvwmPager(1)
# That is the IceWM-style "which apps are on which workspace" look.
#
# Font None suppresses desk labels so the strip stays compact.

DestroyModuleConfig FvwmPagerDP2: *
*FvwmPagerDP2: Monitor DP-2
*FvwmPagerDP2: MiniIcons
*FvwmPagerDP2: Font None
*FvwmPagerDP2: Rows 1
*FvwmPagerDP2: Geometry 420x28+0+0
*FvwmPagerDP2: Colorset  * 10
*FvwmPagerDP2: HilightColorset * 11
*FvwmPagerDP2: WindowColorsets 10 11

DestroyModuleConfig FvwmPagerHDMI1: *
*FvwmPagerHDMI1: Monitor HDMI-1
*FvwmPagerHDMI1: MiniIcons
*FvwmPagerHDMI1: Font None
*FvwmPagerHDMI1: Rows 1
*FvwmPagerHDMI1: Geometry 420x28+2560+0
*FvwmPagerHDMI1: Colorset  * 10
*FvwmPagerHDMI1: HilightColorset * 11
*FvwmPagerHDMI1: WindowColorsets 10 11

# Modules must be started from StartFunction, not from the fvwm command line:
# "starting the pager this way hangs fvwm until the timeout, but the following
# should work well: fvwm -c 'AddToFunc StartFunction I Module FvwmPager'"
#   -- fvwm3(1)
DestroyFunc StartPagers
AddToFunc   StartPagers
+ I Module FvwmPager FvwmPagerDP2
+ I Module FvwmPager FvwmPagerHDMI1

AddToFunc StartFunction I StartPagers
```

- [ ] **Step 2: Restart under Xephyr and check the pagers appear**

Xephyr's fake monitors are NOT named `DP-2`/`HDMI-1`, so both `Monitor` lines will fail to match there. Find the real names first:

```bash
Xephyr -screen 1200x800 -screen 800x600 +xinerama :2 >/dev/null 2>&1 &
sleep 2
DISPLAY=:2 xrandr --listmonitors
```
Expected: two monitors with Xephyr-assigned names (commonly `XEPHYR-0` / `XEPHYR-1`).

- [ ] **Step 3: Test with a temporary Xephyr-named override**

Do NOT edit the committed file for this. Use a scratch copy:

```bash
mkdir -p /tmp/fvwm3-xephyr
sed -e 's/Monitor DP-2/Monitor XEPHYR-0/' \
    -e 's/Monitor HDMI-1/Monitor XEPHYR-1/' \
    -e 's/+2560+0/+1200+0/' \
    ~/.fvwm3/modules > /tmp/fvwm3-xephyr/modules
diff ~/.fvwm3/modules /tmp/fvwm3-xephyr/modules | head
```
Adjust the names above to whatever Step 2 actually printed.

- [ ] **Step 4: Verify per-monitor pager behaviour**

Start fvwm with a config that reads the scratch modules file, put an xterm on each monitor, and confirm:
- Two pager strips, one per monitor.
- The DP-2-equivalent pager shows **only** the left monitor's windows; the other shows only the right's.
- Switching desks on one monitor changes only that pager's highlight.

> **`MiniIcons` cannot be validated here.** Bare `xterm`/`xeyes` supply little
> or no `_NET_WM_ICON`, so the pager may draw nothing for them. Confirm the
> per-monitor split now; defer the icon check to Task 7 in the real session
> with ghostty/brave/emacs, which do set icons.

- [ ] **Step 5: Tear down and commit**

```bash
pkill -f "DISPLAY=:2" ; pkill -f "Xephyr.*:2" ; rm -rf /tmp/fvwm3-xephyr
cd ~/projects/dotfiles
git add .fvwm3/modules
git commit -m "$(cat <<'MSG'
feat(fvwm3): per-monitor FvwmPager with MiniIcons

One pager instance per monitor via FvwmPager's Monitor option, which is the
configuration FvwmPager(1) explicitly recommends for DesktopConfiguration
per-monitor. MiniIcons gives the IceWM-style "which apps live on which
workspace" look that motivated the bar design.

Started from StartFunction rather than the fvwm command line — fvwm3(1)
warns that starting the pager as a command-line module hangs fvwm until a
timeout.

Geometry offsets assume DP-2 at x=0 and HDMI-1 at x=2560, matching the
xrandr layout in .xinitrc-icewm.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: Polybar — derived config, no workspace module

**Files:**
- Create: `~/projects/dotfiles/.config/polybar/config-fvwm3.ini`
- Read-only reference: `~/projects/dotfiles/.config/polybar/config.ini`

**Interfaces:**
- Consumes: nothing from earlier tasks (Polybar is independent of fvwm).
- Produces: bar names `fvwm3-dp2` and `fvwm3-hdmi1`, launched by Task 6's `autostart`.

- [ ] **Step 1: Read the existing config to copy its modules verbatim**

```bash
grep -nE "^\[module/(xwindow|cpu|memory|temperature|date|systray)\]" ~/projects/dotfiles/.config/polybar/config.ini
sed -n '1,10p' ~/projects/dotfiles/.config/polybar/config.ini
```
Expected: the six module sections exist, plus a `[colors]` block at the top.

- [ ] **Step 2: Write the derived config**

Write `~/projects/dotfiles/.config/polybar/config-fvwm3.ini`. Copy the `[module/...]` bodies verbatim from `config.ini` — do not retype them from memory.

```ini
; ~/.config/polybar/config-fvwm3.ini — bars for the FVWM3 session.
;
; Derived from config.ini. TWO deliberate differences:
;
;  1. NO workspace module. Under DesktopConfiguration per-monitor each monitor
;     has its OWN current desk, but EWMH exposes a single global
;     _NET_CURRENT_DESKTOP — so any EWMH-based workspace module can only ever
;     show one monitor's state on both bars. Workspaces are FvwmPager's job
;     (see ~/.fvwm3/modules); this file must never grow an xworkspaces or
;     ewmh module.
;  2. offset-x clears the FvwmPager strip on each monitor.

[colors]
background = #1d1f21
foreground = #c5c8c6
alert      = #ff9580

[bar/fvwm3-dp2]
monitor = DP-2
; FvwmPager occupies 420px at x=0, so start after it.
offset-x = 420
width    = 2140
height   = 28
background = ${colors.background}
foreground = ${colors.foreground}
font-0 = "TX-02:pixelsize=13;2"
font-1 = "JetbrainsMono Nerd Font:pixelsize=13;2"
modules-left   = xwindow
modules-right  = cpu memory temperature date
tray-position  = right

[bar/fvwm3-hdmi1]
monitor = HDMI-1
offset-x = 420
width    = 780
height   = 28
background = ${colors.background}
foreground = ${colors.foreground}
font-0 = "TX-02:pixelsize=13;2"
font-1 = "JetbrainsMono Nerd Font:pixelsize=13;2"
modules-left  = xwindow
modules-right = date
; No tray here — a tray can only usefully live on one monitor.

; ---------------------------------------------------------------------------
; Modules: copy the bodies verbatim from config.ini rather than retyping.
; ---------------------------------------------------------------------------
[module/xwindow]
type = internal/xwindow
label = %title:0:80:...%

[module/cpu]
type = internal/cpu
interval = 2
label = CPU %percentage:2%%

[module/memory]
type = internal/memory
interval = 2
label = RAM %percentage_used:2%%

[module/temperature]
type = internal/temperature
interval = 5
label = %temperature-c%

[module/date]
type = internal/date
interval = 1
date  = %a %b %d
time  = %H:%M
label = %date%  %time%

[settings]
screenchange-reload = true
```

- [ ] **Step 3: Validate the config parses**

```bash
polybar --config=$HOME/projects/dotfiles/.config/polybar/config-fvwm3.ini --list-monitors
polybar --config=$HOME/projects/dotfiles/.config/polybar/config-fvwm3.ini --dump=width fvwm3-dp2
```
Expected: monitors listed; `--dump` prints `2140`. Any parse error surfaces here rather than at session start.

- [ ] **Step 3a: DEPLOY it — polybar is copy-deployed, not symlinked**

**This step is mandatory and easy to forget.** Unlike `.fvwm3`, `.icewm` and
`.config/hypr` — which are symlinks into the repo and therefore cannot drift —
`~/.config/polybar` is a **plain directory of copies**:

```bash
stat -c '%N' ~/.config/polybar          # NOT a symlink
stat -c '%i' ~/.config/polybar/config.ini ~/projects/dotfiles/.config/polybar/config.ini
```
The two inodes differ, which means **a file committed to the repo is not a file
that is live.** This is precisely the failure mode that made the Ghostty theme
silently never apply (see `docs/kitty-to-ghostty-terminal-swap.md` §1b), and it
is recorded there as an open watch-list item.

```bash
cp ~/projects/dotfiles/.config/polybar/config-fvwm3.ini ~/.config/polybar/config-fvwm3.ini
test -f ~/.config/polybar/config-fvwm3.ini && echo "deployed" || echo "NOT DEPLOYED"
```
Expected: `deployed`. Task 6's autostart references
`$[HOME]/.config/polybar/config-fvwm3.ini`; without this step the bars launch
nothing and fail quietly.

> If you would rather kill this whole bug class, symlink the directory instead —
> `mv ~/.config/polybar{,.bak} && ln -s ~/projects/dotfiles/.config/polybar ~/.config/polybar`.
> That is a change to EXISTING deployment and therefore outside this plan's
> additive-only constraint; raise it separately.

- [ ] **Step 4: Confirm no workspace module crept in**

```bash
grep -cE "xworkspaces|internal/ewmh|modules.*i3" ~/projects/dotfiles/.config/polybar/config-fvwm3.ini
```
Expected: `0`. This check exists because adding one would silently produce a bar that lies about which desk you are on.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add .config/polybar/config-fvwm3.ini
git commit -m "$(cat <<'MSG'
feat(fvwm3): polybar bars for the FVWM3 session

NOTE: ~/.config/polybar is copy-deployed, NOT symlinked, so committing this
file does not make it live — it must also be cp'd into ~/.config/polybar/.
Same trap that made the Ghostty theme silently never apply.

Two bars, one per monitor, offset to clear the FvwmPager strip.

Deliberately carries NO workspace module. Under DesktopConfiguration
per-monitor each monitor has its own current desk, but EWMH exposes a single
global _NET_CURRENT_DESKTOP — so an EWMH-based workspace module can only
ever show one monitor's state on both bars. Workspaces are FvwmPager's job.
A grep check in the plan guards against this regressing.

Derived from config.ini rather than replacing it; the IceWM/i3-era config is
untouched.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: Autostart, focus consent, and the session launcher

**Files:**
- Modify: `~/projects/dotfiles/.fvwm3/autostart` (replace stub)
- Create: `~/projects/dotfiles/.xinitrc-fvwm3`
- Create: `~/projects/dotfiles/.local/bin/start-fvwm3`

**Interfaces:**
- Consumes: pager module aliases from Task 4; polybar bar names `fvwm3-dp2` / `fvwm3-hdmi1` from Task 5.
- Produces: `start-fvwm3` on `PATH` as the TTY entry point.

- [ ] **Step 1: Read the IceWM launcher to mirror it**

```bash
cat ~/projects/dotfiles/.local/bin/start-icewm
cat ~/projects/dotfiles/.xinitrc-icewm
```
Copy its structure exactly — D-Bus, keyring, ssh-agent, `GIO_USE_VFS=local`, VA-API. Do not invent a new bring-up sequence.

- [ ] **Step 2: Write the autostart**

Write `~/projects/dotfiles/.fvwm3/autostart`:

```
# ~/.fvwm3/autostart — things launched with the session.
# The pagers are started in ~/.fvwm3/modules; do NOT start them again here.

DestroyFunc AutostartApps
AddToFunc   AutostartApps
+ I Exec exec polybar --config=$[HOME]/.config/polybar/config-fvwm3.ini fvwm3-dp2
+ I Exec exec polybar --config=$[HOME]/.config/polybar/config-fvwm3.ini fvwm3-hdmi1
+ I Exec exec dunst
+ I Exec exec udiskie
+ I Exec exec flameshot
+ I Exec exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
+ I Exec exec i3-mouse-setup

AddToFunc StartFunction I AutostartApps

#-----------------------------------------------------------------------------
# Focus-stealing consent.
#
# "When a compliant taskbar asks fvwm to activate a window [...] fvwm calls
#  the complex function EWMHActivateWindowFunc which by default is
#  Iconify Off, Focus and Raise. You can redefine this function."  -- fvwm3(1)
#
# This is the FVWM3 equivalent of the IceWM winoptions block that stops Brave
# yanking focus (.icewm/winoptions: ignoreActivationMessages). IceWM offers a
# per-window boolean; fvwm offers a FUNCTION, so the policy can be conditional.
#
# Policy: de-iconify and mark the window, but do NOT raise it or move the
# pointer. The window announces itself; it does not hijack the view.
#-----------------------------------------------------------------------------
DestroyFunc EWMHActivateWindowFunc
AddToFunc   EWMHActivateWindowFunc
+ I Iconify Off
+ I FlipFocus NoWarp
```

- [ ] **Step 3: Write `.xinitrc-fvwm3`**

Mirror `.xinitrc-icewm`, changing only the WM and dropping IceWM-specific bits. **Reuse the same xrandr layout line verbatim** — the display geometry is identical.

```sh
#!/bin/sh
# ~/.xinitrc-fvwm3 — FVWM3/X11 session contents on godlike-artix.
# Mirrors .xinitrc-icewm; session/daemon bootstrap is done by start-fvwm3
# BEFORE startx and inherited here. Autostart apps live in ~/.fvwm3/autostart
# (fvwm StartFunction), NOT here — unlike the IceWM sibling, which has no
# equivalent hook.

export QT_QPA_PLATFORM=xcb
export GDK_BACKEND=x11
export MOZ_ENABLE_WAYLAND=0
export _JAVA_AWT_WM_NONREPARENTING=1

x11-max-refresh

# Identical layout to .xinitrc-icewm — see
# docs/2026-07-20-desktop-dual-monitor-portrait.md for the centring maths and
# the --rotate right derivation.
xrandr --output DP-2   --primary --rotate normal --pos 0x240 \
       --output HDMI-1            --rotate right  --pos 2560x0

dbus-update-activation-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP

pipewire &
sleep 0.5 && wireplumber &
sleep 1   && pipewire-pulse &

exec fvwm3
```

- [ ] **Step 4: Write `start-fvwm3`**

Copy `start-icewm` and change only: the `XDG_CURRENT_DESKTOP`/`XDG_SESSION_DESKTOP` values to `fvwm3`, and the xinitrc it launches to `~/.xinitrc-fvwm3`. Then:

```bash
chmod +x ~/projects/dotfiles/.local/bin/start-fvwm3
ln -sfn ~/projects/dotfiles/.local/bin/start-fvwm3 ~/.local/bin/start-fvwm3
ln -sfn ~/projects/dotfiles/.xinitrc-fvwm3 ~/.xinitrc-fvwm3
command -v start-fvwm3
```
Expected: `/home/jim/.local/bin/start-fvwm3`

- [ ] **Step 5: Syntax-check both shell files**

```bash
sh -n ~/projects/dotfiles/.xinitrc-fvwm3        && echo "xinitrc OK"
sh -n ~/projects/dotfiles/.local/bin/start-fvwm3 && echo "launcher OK"
```
Expected: both `OK`.

- [ ] **Step 6: Confirm nothing existing was touched**

```bash
cd ~/projects/dotfiles && git status --short
```
Expected: only NEW files (`??`) plus the `.fvwm3/*` modifications. **No `M` on `.icewm/`, `.xinitrc-icewm`, `.config/hypr/`, or `start-icewm`.** If any appear, revert them — the additive-and-reversible constraint has been violated.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/dotfiles
git add .fvwm3/autostart .xinitrc-fvwm3 .local/bin/start-fvwm3
git commit -m "$(cat <<'MSG'
feat(fvwm3): autostart, focus-consent policy, and TTY launcher

start-fvwm3 + .xinitrc-fvwm3 mirror the IceWM pair, reusing the same xrandr
layout line verbatim. Autostart lives in fvwm's StartFunction rather than the
xinitrc, since fvwm has that hook and IceWM does not.

EWMHActivateWindowFunc is redefined so a window demanding attention
de-iconifies and takes focus WITHOUT raising itself or warping the pointer.
This is the fvwm counterpart to the IceWM winoptions block that stops Brave
hijacking the view — and strictly more capable, since fvwm exposes a function
where IceWM exposes a per-window boolean.

Additive only: IceWM and Hyprland are untouched, and reverting is simply not
running start-fvwm3.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: Real-session validation and the outcome doc

Xephyr cannot validate everything (spec §11). This task is the second pass.

**Files:**
- Create: `~/projects/i3-screen-manager/docs/2026-07-20-fvwm3-x11-setup.md`
- Modify: `~/projects/i3-screen-manager/CLAUDE.md` (index entry + WM rotation list)

- [ ] **Step 1: Boot it for real**

From a TTY (not from inside an X session):
```bash
start-fvwm3
```

- [ ] **Step 2: Walk the checklist**

- [ ] Both monitors light up with the layout from `.xinitrc-icewm` (DP-2 at `+0+240`, HDMI-1 portrait at `+2560+0`)
- [ ] Windows have 2px flat uniform borders, cyan focused / slate unfocused, no titlebars
- [ ] `Super+LMB` moves, `Super+RMB` resizes
- [ ] `Super+1..0` switches desks on the **pointer's** monitor only
- [ ] `Super+grave` toggles monitors; `Super+3` afterwards targets the new one
- [ ] Two FvwmPager strips, each showing only its own monitor's desks
- [ ] **MiniIcons render** — launch ghostty, brave-origin and emacs, confirm their icons appear in the pager (the check Xephyr could not do)
- [ ] Two polybar bars, correctly offset, not overlapping the pagers
- [ ] Tray works: `udiskie` and `flameshot` icons appear
- [ ] `Super+space` rofi, `Super+Return` ghostty, `Print` flameshot
- [ ] `Super+Shift+Escape` exits cleanly back to the TTY

- [ ] **Step 3: Measure the EWMH unknown from spec §11**

```bash
xprop -root _NET_CURRENT_DESKTOP _NET_NUMBER_OF_DESKTOPS _NET_DESKTOP_GEOMETRY
```
Record the result in the outcome doc. This answers what FVWM3 reports for a single global desktop when it actually has N — the open question from the spec, and the same trap that makes per-monitor workspaces unrepresentable to a standard bar.

- [ ] **Step 4: Write the outcome doc**

Create `docs/2026-07-20-fvwm3-x11-setup.md` following the house pattern of `docs/2026-06-16-icewm-x11-setup.md`: what was built, what was verified vs assumed, the gotchas hit, and a watch list. Record at minimum:
- the strut/offset numbers that actually worked (spec §11 predicted tuning)
- the `_NET_CURRENT_DESKTOP` finding from Step 3
- whether SloppyFocus is comfortable in daily use, or wants reverting

- [ ] **Step 5: Index it in CLAUDE.md**

Add an entry to the docs list, and update the WM rotation section — `godlike-artix` becomes **Hyprland (Wayland) · IceWM (X11) · FVWM3 (X11)**.

- [ ] **Step 6: Commit and push both repos**

```bash
cd ~/projects/i3-screen-manager
git add docs/2026-07-20-fvwm3-x11-setup.md CLAUDE.md
git commit -m "docs: FVWM3 X11 setup outcome on godlike-artix

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin master
```

---

## Rollback

At any point, in order of severity:

1. **Stop using it** — don't run `start-fvwm3`. IceWM and Hyprland are untouched and still boot normally. This is the whole point of the additive constraint.
2. **Unlink** — `rm ~/.fvwm3 ~/.xinitrc-fvwm3 ~/.local/bin/start-fvwm3` (all symlinks; removes nothing from the repo).
3. **Uninstall** — `sudo pacman -Rsp fvwm3` to DRY-RUN first, inspect the list, then `-Rs` only if it removes nothing shared.
