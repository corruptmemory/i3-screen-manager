# i3 Desktop Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Return i3 to service as `godlike-artix`'s X11 window manager, modernised for Artix/OpenRC, Ghostty, brave-origin and the dual-monitor portrait layout.

**Architecture:** Three layers, each doing only what it can — `start-i3` for pre-X session bootstrap, `.xinitrc-i3` for X-side setup and the monitor layout, and the i3 config itself for window management and autostart. Two polybars, one per monitor, using i3's own IPC so each shows only its own workspaces.

**Tech Stack:** i3-wm 4.25.1 (Artix `world`), polybar 3.7.2, rofi 2.0.0, feh, ghostty, brave-origin.

**Design spec:** `docs/2026-07-20-i3-desktop-setup-plan.md` (committed `f3efa6a`). Read it first; this plan implements it and does not restate its rationale.

## Global Constraints

- **Additive and reversible.** Do NOT modify `.icewm/`, `.icewm-laptop/`, `.xinitrc-icewm`, `.fvwm3/`, `.xinitrc-fvwm3`, `.config/hypr/*`, `start-icewm`, `start-fvwm3`, or `.config/polybar/config.ini`. All three existing sessions must keep working.
- **No AUR, ever.** Official Artix/Arch repos only. `dex` is NOT in the repos — its autostart line is deleted, not replaced.
- **Always dry-run package removals** on Artix: `pacman -Rsp` before any `-Rs`. This plan removes nothing.
- **Never `git add -A` or `git add .`** — stage named files only.
- **Commit messages end with:**
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Monitors:** `DP-2` = 2560x1440 landscape at `+0+240` (primary, main). `HDMI-1` = 1200x1920 portrait at `+2560+0` (side). Under Wayland the latter is `HDMI-A-1`; that name is **wrong** here — X11/xrandr is `HDMI-1`.
- **Workspaces 1–6 → DP-2, 7–10 → HDMI-1.**
- **This is config, not code.** "Tests" are observable checks (`i3 -C`, `xprop`, `ps`, `i3-msg -t get_workspaces`), not unit tests. Each task still ends with a check that can fail before the change and pass after.
- **Verify, don't assume.** The FVWM3 build lost hours to an unchecked assumption about `~/.fvwm3` and shipped a duplicate-daemon bug from an unchecked assumption about `StartFunction`. Task 2 exists to break that pattern.

---

### Task 1: Preserve the live drift, then symlink

**This must be first.** `~/.config/i3/` is a real directory whose contents are AHEAD of the repo. Any symlink or rename before this step destroys work.

**Files:**
- Modify: `~/projects/dotfiles/.config/i3/config` (receives the live content)
- Rename: → `~/projects/dotfiles/.config/i3/config-desktop`

**Interfaces:**
- Produces: `~/.config/i3/config` as a symlink to `dotfiles/.config/i3/config-desktop`. Every later task edits the repo file and gets it live for free.

- [ ] **Step 1: Prove the drift exists (the failing check)**

```bash
diff ~/projects/dotfiles/.config/i3/config ~/.config/i3/config
```
Expected: a non-empty diff showing the repo has `waypaper --restore` while live has `feh --bg-fill`, plus three live-only lines (`set $browser`, `xdtpaste.sh`, `i3-mouse-rofi`). **If the diff is empty, stop and re-read — the situation has changed since this plan was written.**

- [ ] **Step 2: Back up, then propagate live → repo**

```bash
cp -a ~/.config/i3 ~/.config/i3.bak-2026-07-20
cp ~/.config/i3/config ~/projects/dotfiles/.config/i3/config
diff ~/projects/dotfiles/.config/i3/config ~/.config/i3/config && echo "repo now matches live — nothing will be lost"
```
Expected: `repo now matches live — nothing will be lost`

- [ ] **Step 3: Commit the recovery ON ITS OWN**

A separate commit from any modernisation, so the recovered lines are attributable.

```bash
cd ~/projects/dotfiles
git add .config/i3/config
git commit -m "$(cat <<'MSG'
fix(i3): recover live config changes lost to copy-deployment drift

~/.config/i3 is a directory of COPIES, not a symlink, so the live config had
drifted ahead of the tracked one. Recovered, verbatim:

  - feh --bg-fill ~/projects/dt-wallpapers/0007.jpg  (repo still had
    `waypaper --restore` — a WAYLAND tool, useless under X11)
  - set $browser brave --profile-directory="Default" --new-window
  - bindsym $mod+$alt+v exec .local/bin/xdtpaste.sh
  - bindsym $mod+Mod1+m exec i3-mouse-rofi

Same failure that ate the polybar cmos-battery module (7ed0c5b) and made the
Ghostty theme never apply. Committed BEFORE any i3 modernisation so the
recovered lines are attributable, and before symlinking so nothing is lost.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

- [ ] **Step 4: Rename to the desktop variant and symlink**

```bash
cd ~/projects/dotfiles
git mv .config/i3/config .config/i3/config-desktop
rm -rf ~/.config/i3
mkdir -p ~/.config/i3
ln -s ~/projects/dotfiles/.config/i3/config-desktop ~/.config/i3/config
stat -c '%N' ~/.config/i3/config
```
Expected: `'/home/jim/.config/i3/config' -> '/home/jim/projects/dotfiles/.config/i3/config-desktop'`

> Directory, not the whole `~/.config/i3`, is recreated — i3 writes other state
> there (e.g. `~/.config/i3/config.d` if ever used), so only the file is linked.

- [ ] **Step 5: Verify the symlink resolves to the recovered content**

```bash
grep -c "dt-wallpapers/0007.jpg" ~/.config/i3/config
grep -c "xdtpaste.sh" ~/.config/i3/config
```
Expected: `1` for each. If either is `0`, Step 2 was skipped and the recovery was lost.

- [ ] **Step 6: Commit the rename**

```bash
cd ~/projects/dotfiles
git add .config/i3/config-desktop
git commit -m "$(cat <<'MSG'
refactor(i3): config -> config-desktop, symlinked from ~

Matches the house convention for per-machine variants (hyprland-desktop.*,
.icewm vs .icewm-laptop), leaving room for a config-laptop later.

~/.config/i3/config is now a symlink into this repo, so the copy-deployment
drift fixed in the previous commit cannot recur.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: Install i3 and VERIFY the two assumptions

No config changes. This task exists solely to replace two guesses with facts, because guessing is what cost the FVWM3 build.

**Files:** none.

**Interfaces:**
- Produces: a confirmed answer to "does `exec` re-run on reload?", which Task 3 depends on for placing autostart lines.

- [ ] **Step 1: Confirm availability, then install**

```bash
pacman -Si i3-wm | head -3
sudo pacman -S --noconfirm i3-wm
i3 --version
```
Expected: version reports `4.25.1`.

- [ ] **Step 2: Check what else the old config assumes**

```bash
for c in nm-applet feh flameshot dunst udiskie rofi rofi-rbw playerctl brightnessctl wpctl ghostty brave-origin emacs i3lock; do
  printf '%-14s ' "$c"; command -v $c || echo "MISSING"
done
```
Expected: all present except possibly `subl`/`goland` (not checked — their binds are harmless if the binary is absent).

> **`dex` is NOT in the Artix repos** and the AUR is off-limits. Its line is
> deleted in Task 3, not replaced: it only ran XDG autostart `.desktop` files,
> and every daemon we want is launched explicitly instead.

- [ ] **Step 3: VERIFY `exec` vs `exec_always` — do not skip**

```bash
man 5 i3 | col -b | grep -B4 -A12 "exec_always" | head -30
```
Read it. Record the answer in the outcome doc. The expectation is `exec` = startup only, `exec_always` = startup **and** reload/restart — but **the FVWM3 build shipped a duplicate-daemon bug from exactly this assumption about `StartFunction`.** Task 7 proves it empirically regardless of what the man page says.

- [ ] **Step 4: Confirm `i3 -C` validates a config without starting a session**

```bash
i3 -C -c ~/.config/i3/config ; echo "exit=$?"
```
Expected: exit `0` and no output, or warnings about the not-yet-modernised config. **This command is the single biggest tooling advantage over the FVWM3 build**, which had no way to validate a config without launching it. Use it after every edit in Tasks 3–6.

---

### Task 3: Rewrite `config-desktop`

**Files:**
- Modify: `~/projects/dotfiles/.config/i3/config-desktop` (full rewrite)

**Interfaces:**
- Consumes: the symlink from Task 1; the `exec`/`exec_always` answer from Task 2.
- Produces: polybar bar names `i3-dp2` and `i3-hdmi1`, referenced by Task 4's config; `$browser`, `$mod`, `$alt` variables.

- [ ] **Step 1: Confirm the current state is the pre-modernisation config**

```bash
grep -c "kitty\|Morgen\|systemctl\|dex\|pactl\|waypaper" ~/.config/i3/config
```
Expected: a non-zero count (roughly 15). That count going to `0` is this task's success condition.

- [ ] **Step 2: Write the new config**

Replace the entire contents of `~/projects/dotfiles/.config/i3/config-desktop` with:

```
# ~/.config/i3/config-desktop — godlike-artix (desktop), i3 v4.
#
# Symlinked from ~/.config/i3/config. See i3-screen-manager
# docs/2026-07-20-i3-desktop-setup-plan.md for the design and rationale.
#
# Session bootstrap does NOT live here — start-i3 handles pre-X setup (D-Bus,
# keyring, ssh-agent) and .xinitrc-i3 handles X-side setup (toolkit backends,
# the xrandr monitor layout, pipewire). This file owns window management and
# autostart only.

set $mod Mod4
set $alt Mod1
set $browser brave-origin --profile-directory="Default" --new-window

font pango:TX-02 10

#-----------------------------------------------------------------------------
# MONITORS AND WORKSPACES
#
# i3 has ONE shared pool of workspaces, each living on a single output — unlike
# FVWM3, where every monitor had a private copy of desks 1-10. Super+N moves
# focus to whichever monitor holds workspace N.
#
# DP-2   2560x1440 landscape at +0+240   (main)
# HDMI-1 1200x1920 portrait  at +2560+0  (side)
#
# The layout itself is applied by .xinitrc-i3 via xrandr BEFORE i3 starts —
# see docs/2026-07-20-desktop-dual-monitor-portrait.md for the centring maths.
#-----------------------------------------------------------------------------
workspace 1  output DP-2
workspace 2  output DP-2
workspace 3  output DP-2
workspace 4  output DP-2
workspace 5  output DP-2
workspace 6  output DP-2
workspace 7  output HDMI-1
workspace 8  output HDMI-1
workspace 9  output HDMI-1
workspace 10 output HDMI-1

#-----------------------------------------------------------------------------
# AUTOSTART
#
# `exec` runs at startup only; `exec_always` runs at startup AND on reload.
# Long-running daemons therefore use `exec` — under FVWM3 the equivalent
# distinction (InitFunction vs StartFunction) was got wrong and every reload
# spawned another polybar and another udiskie. Task 7 of the implementation
# plan re-counts processes after a reload to prove this is right.
#
# feh is `exec_always` on purpose: it sets the root pixmap and exits, so
# re-running costs nothing and re-asserts the wallpaper if anything clobbers it.
#
# NOT here, deliberately:
#   dex --autostart   — not in the Artix repos, and every daemon we want is
#                       launched explicitly below anyway.
#   systemctl --user import-environment  — systemd-only, dead on OpenRC.
#   dbus-update-activation-environment   — needed, but belongs in .xinitrc-i3
#                                          (and without the --systemd flag).
#-----------------------------------------------------------------------------
exec --no-startup-id polybar --config=$HOME/.config/polybar/config-i3.ini i3-dp2
exec --no-startup-id polybar --config=$HOME/.config/polybar/config-i3.ini i3-hdmi1
exec --no-startup-id dunst
exec --no-startup-id udiskie
exec --no-startup-id flameshot
exec --no-startup-id nm-applet
exec --no-startup-id /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec --no-startup-id i3-mouse-setup
exec_always --no-startup-id feh --bg-fill ~/projects/dt-wallpapers/0007.jpg

#-----------------------------------------------------------------------------
# LOOK
#-----------------------------------------------------------------------------
default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart

# Drag floating windows with Super+mouse; drag tiling windows by the titlebar.
floating_modifier $mod
tiling_drag modifier titlebar

#-----------------------------------------------------------------------------
# LAUNCHERS
#-----------------------------------------------------------------------------
bindsym $mod+Return exec ghostty
bindsym $mod+E exec emacs
bindsym $mod+F12 exec emacs
bindsym $mod+F11 exec subl
bindsym $mod+F10 exec goland
bindsym $mod+B exec $browser
bindsym $mod+Shift+v exec /home/jim/.local/bin/volumecontrol.sh
bindsym $mod+$alt+v exec /home/jim/.local/bin/xdtpaste.sh
bindsym $mod+Shift+b exec --no-startup-id rofi-rbw
bindsym $mod+Mod1+m exec --no-startup-id i3-mouse-rofi
bindsym $mod+Shift+P exec pkill polybar && polybar --config=$HOME/.config/polybar/config-i3.ini i3-dp2

# rofi. The monitor it opens on is set once in ~/.config/rofi/config.rasi
# (monitor: -4) so the applets and powermenu scripts inherit it too.
bindsym $mod+space exec "rofi -modi drun,run -show drun"
bindsym $mod+Control+space exec "rofi -modi emoji -show emoji -kb-secondary-copy '' -kb-custom-1 Ctrl+c"

# Quick-focus messaging apps.
bindsym $mod+F1 [class="Slack"] focus
bindsym $mod+F2 [class="Keybase"] focus
bindsym $mod+F3 [class="discord"] focus

#-----------------------------------------------------------------------------
# MEDIA / HARDWARE KEYS
# wpctl (pipewire), matching every other config on this machine. The old pactl
# binds predate the pipewire migration.
#-----------------------------------------------------------------------------
bindsym XF86AudioRaiseVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindsym XF86AudioLowerVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym XF86AudioMute exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym XF86AudioMicMute exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindsym Control+F1 exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindsym XF86MonBrightnessUp exec brightnessctl s +5%
bindsym XF86MonBrightnessDown exec brightnessctl s 5%-
bindsym XF86AudioPlay exec playerctl play-pause
bindsym XF86AudioPause exec playerctl play-pause
bindsym XF86AudioNext exec playerctl next
bindsym XF86AudioPrev exec playerctl previous
bindsym Print exec QT_SCREEN_SCALE_FACTORS="1.0001" flameshot gui -c

#-----------------------------------------------------------------------------
# WINDOW MANAGEMENT
#-----------------------------------------------------------------------------
bindsym $mod+q kill

bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

bindsym $mod+h split h
bindsym $mod+v split v
bindsym $mod+Shift+e layout toggle split
bindsym $mod+s layout stacking
bindsym $mod+g layout tabbed
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle
bindsym $mod+$alt+space focus mode_toggle
bindsym $mod+Shift+f focus mode_toggle
bindsym $mod+a focus parent
bindsym $mod+Shift+a focus child

# Generic scratchpad — opt-in, nothing is forced into it. (The Morgen
# auto-scratchpad rules were removed: Morgen is no longer used at all.)
bindsym $mod+Shift+minus move scratchpad
bindsym $mod+minus scratchpad show

#-----------------------------------------------------------------------------
# WINDOW RULES
#
# Zoom floats and is otherwise left alone — no scratchpad, no forced workspace.
# Park its main window on the side monitor by hand. The special:zoom
# scratchpad-like hack is a HYPRLAND invention and never existed here.
#-----------------------------------------------------------------------------
for_window [class="zoom"] floating enable
for_window [class="pavucontrol"] floating enable
for_window [class="Keymapp"] floating enable
for_window [class="steam"] floating enable

#-----------------------------------------------------------------------------
# WORKSPACE SWITCHING
#-----------------------------------------------------------------------------
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+0 workspace number 10

bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
bindsym $mod+Shift+6 move container to workspace number 6
bindsym $mod+Shift+7 move container to workspace number 7
bindsym $mod+Shift+8 move container to workspace number 8
bindsym $mod+Shift+9 move container to workspace number 9
bindsym $mod+Shift+0 move container to workspace number 10

bindsym Mod1+Control+Right workspace next
bindsym Mod1+Control+Left workspace prev

#-----------------------------------------------------------------------------
# SESSION
#-----------------------------------------------------------------------------
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+l exec i3lock -c 000000
bindsym $mod+Shift+Escape exit

#-----------------------------------------------------------------------------
# RESIZE MODE
#-----------------------------------------------------------------------------
mode "resize" {
        bindsym Left  resize shrink width 10 px or 10 ppt
        bindsym Down  resize grow height 10 px or 10 ppt
        bindsym Up    resize shrink height 10 px or 10 ppt
        bindsym Right resize grow width 10 px or 10 ppt
        bindsym Return mode "default"
        bindsym Escape mode "default"
        bindsym $mod+r mode "default"
}
bindsym $mod+r mode "resize"
```

- [ ] **Step 3: Validate**

```bash
i3 -C -c ~/.config/i3/config ; echo "exit=$?"
```
Expected: exit `0`, no errors. Any syntax mistake surfaces here rather than at boot.

- [ ] **Step 4: Confirm every stale token is gone**

```bash
grep -n "kitty\|KittyFloating\|Morgen\|morgen\|systemctl\|dex --autostart\|pactl\|waypaper" ~/.config/i3/config || echo "clean — all stale tokens removed"
```
Expected: `clean — all stale tokens removed`

- [ ] **Step 5: Confirm the workspace assignments are present**

```bash
grep -c "^workspace [0-9]* output DP-2" ~/.config/i3/config
grep -c "^workspace [0-9]* output HDMI-1" ~/.config/i3/config
```
Expected: `6` and `4`.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/dotfiles
git add .config/i3/config-desktop
git commit -m "$(cat <<'MSG'
feat(i3): modernise the desktop config for Artix, Ghostty and dual monitors

Workspaces 1-6 pinned to DP-2, 7-10 to HDMI-1. i3 has ONE shared pool of
workspaces, each on a single output — unlike FVWM3, where each monitor had a
private copy of desks 1-10. Super+N moves focus to whichever monitor holds
workspace N.

Modernised: kitty -> ghostty, brave -> brave-origin, pactl -> wpctl.

Deleted rather than adapted:
  - systemctl --user import-environment   systemd-only, dead on OpenRC
  - dbus-update-activation-environment    needed, but belongs in .xinitrc-i3
                                          and without the --systemd flag
  - dex --autostart                       not in the Artix repos, AUR off
                                          limits, and every daemon is launched
                                          explicitly instead
  - all Morgen rules + autostart          no longer used at all
  - all KittyFloating rules               never used

Autostart uses `exec` for daemons and `exec_always` only for feh, which exits
immediately. The FVWM3 build got the equivalent distinction wrong
(StartFunction runs on every restart) and spawned a duplicate polybar and
udiskie on every reload; the plan re-counts processes after a reload to prove
this one is right.

Zoom floats with no scratchpad and no forced workspace — the special:zoom hack
is a Hyprland invention that never existed in this config.

Validated with `i3 -C`.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: Polybar — two bars, per-monitor workspaces

**Files:**
- Create: `~/projects/dotfiles/.config/polybar/config-i3.ini`
- Read-only reference: `~/projects/dotfiles/.config/polybar/config.ini`

**Interfaces:**
- Consumes: bar names `i3-dp2` / `i3-hdmi1` referenced by Task 3's `exec` lines.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Confirm `pin-workspaces` is supported**

```bash
strings /usr/bin/polybar | grep -x "pin-workspaces" && echo "supported"
```
Expected: `pin-workspaces` then `supported`. This is the whole reason polybar can own the entire bar here, where under FVWM3 it could not.

- [ ] **Step 2: Write the config**

Create `~/projects/dotfiles/.config/polybar/config-i3.ini`:

```ini
; ~/.config/polybar/config-i3.ini — bars for the i3 session.
;
; Derived from config.ini, which is left untouched as the historical
; single-bar version.
;
; THE KEY DIFFERENCE FROM config-fvwm3.ini: this one HAS a workspace module.
; Polybar's internal/i3 talks to i3's own IPC rather than EWMH, so
; `pin-workspaces = true` shows only the workspaces belonging to each bar's
; monitor. Under FVWM3 that was impossible — EWMH exposes a single global
; _NET_CURRENT_DESKTOP — which is why that setup needed a FvwmPager hybrid.

[colors]
background = #1d1f21
background-alt = #373b41
foreground = #c5c8c6
primary = #33ccff
secondary = #8abeb7
alert = #ff9580
disabled = #707880

;-----------------------------------------------------------------------------
; DP-2 — 2560x1440 landscape at +0+240. Full bar.
;-----------------------------------------------------------------------------
[bar/i3-dp2]
monitor = DP-2
width = 100%
height = 28
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 2
padding-right = 1
module-margin = 1
separator = |
separator-foreground = ${colors.disabled}
font-0 = "TX-02:pixelsize=14;2"
font-1 = "JetbrainsMono Nerd Font:pixelsize=14;2"
modules-left = i3 xwindow
modules-right = cmos-battery memory cpu temperature date systray
cursor-click = pointer
enable-ipc = true

;-----------------------------------------------------------------------------
; HDMI-1 — 1200x1920 portrait at +2560+0. Lean: workspaces and a clock.
; No tray (it only usefully lives on one screen) and no stats (1200px is
; narrow).
;-----------------------------------------------------------------------------
[bar/i3-hdmi1]
monitor = HDMI-1
width = 100%
height = 28
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 2
padding-right = 1
module-margin = 1
separator = |
separator-foreground = ${colors.disabled}
font-0 = "TX-02:pixelsize=14;2"
font-1 = "JetbrainsMono Nerd Font:pixelsize=14;2"
modules-left = i3
modules-right = date
cursor-click = pointer
enable-ipc = true

;-----------------------------------------------------------------------------
; Modules
;-----------------------------------------------------------------------------

; pin-workspaces = true is the load-bearing setting: without it BOTH bars show
; ALL ten workspaces, which defeats the point of assigning them to outputs.
[module/i3]
type = internal/i3
pin-workspaces = true
show-urgent = true
strip-wsnumbers = false
index-sort = true
enable-click = true
enable-scroll = false
format = <label-state><label-mode>
label-mode = %mode%
label-mode-padding = 1
label-focused = %name%
label-focused-foreground = ${colors.primary}
label-focused-padding = 1
label-unfocused = %name%
label-unfocused-foreground = ${colors.disabled}
label-unfocused-padding = 1
label-visible = %name%
label-visible-padding = 1
label-urgent = %name%
label-urgent-foreground = ${colors.alert}
label-urgent-padding = 1

[module/xwindow]
type = internal/xwindow
label = %title:0:60:...%

[module/memory]
type = internal/memory
interval = 2
format-prefix = "RAM "
format-prefix-foreground = ${colors.primary}
label = %percentage_used:2%%

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-foreground = ${colors.primary}
label = %percentage:2%%

[module/temperature]
type = internal/temperature
interval = 0.5

[module/date]
type = internal/date
interval = 1
date = %a %b %d  %H:%M
date-alt = %Y-%m-%d %H:%M:%S
label = %date%
label-foreground = ${colors.primary}

; CMOS battery voltage off the it87 Super I/O chip. Recovered from the live
; polybar config during the 2026-07-20 copy-deployment fix (dotfiles 7ed0c5b).
[module/cmos-battery]
type = custom/script
exec = i3-cmos-battery polybar
; Every 6 hours (21600 seconds)
interval = 21600
format-prefix = "CMOS "
format-prefix-foreground = ${colors.primary}

[module/systray]
type = internal/tray

[settings]
screenchange-reload = true
pseudo-transparency = false
```

- [ ] **Step 3: Validate both bars parse**

```bash
cd ~/projects/dotfiles/.config/polybar
polybar --config=config-i3.ini --dump=monitor i3-dp2
polybar --config=config-i3.ini --dump=monitor i3-hdmi1
```
Expected: `DP-2` then `HDMI-1`. Any parse error surfaces here.

- [ ] **Step 4: Confirm it is live**

`~/.config/polybar` is already a symlink into the repo (fixed 2026-07-20), so no copy step is needed — unlike the FVWM3 build, where forgetting that cost a debugging cycle.

```bash
stat -c '%N' ~/.config/polybar
test -f ~/.config/polybar/config-i3.ini && echo "live via symlink"
```
Expected: the symlink, then `live via symlink`.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add .config/polybar/config-i3.ini
git commit -m "$(cat <<'MSG'
feat(i3): polybar bars for the i3 session, per-monitor workspaces

Two bars, one per monitor. Unlike config-fvwm3.ini this one HAS a workspace
module: polybar's internal/i3 talks to i3's own IPC rather than EWMH, so
`pin-workspaces = true` shows only the workspaces belonging to each bar's
monitor. Under FVWM3 that was impossible — EWMH exposes a single global
_NET_CURRENT_DESKTOP — which is why that setup needed a FvwmPager hybrid and
this one does not.

pin-workspaces is load-bearing: without it BOTH bars show all ten workspaces,
defeating the workspace->output assignment entirely.

DP-2 gets the full bar; HDMI-1 gets workspaces and a clock only — a tray only
usefully lives on one screen and 1200px is narrow.

config.ini is untouched.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: Rofi — open on the focused monitor

**Files:**
- Modify: `~/projects/dotfiles/.config/rofi/config.rasi`

- [ ] **Step 1: Show the current behaviour**

```bash
grep -n "monitor" ~/projects/dotfiles/.config/rofi/config.rasi || echo "monitor NOT set — inheriting the default"
```
Expected: `monitor NOT set — inheriting the default`. The default is `-5`, which `rofi(1)` defines as *"the monitor that shows the mouse pointer"* — so menus follow the mouse, not focus.

- [ ] **Step 2: Add the setting**

Edit the existing `configuration { }` block in `~/projects/dotfiles/.config/rofi/config.rasi` to add one line:

```
configuration {
  show-icons: true;
  icon-theme: "Papirus";
  display-drun: ">";
  display-window: "W>";
  display-combi: "C>";
  font: "TX-02 11";
  /* Open on the monitor holding the FOCUSED WINDOW, not the mouse pointer.
     rofi(1): -4 = "the monitor with the focused window"; the default -5 is
     "the monitor that shows the mouse pointer". Set here rather than on the
     individual bindings so the applets and powermenu scripts inherit it too.
     If -4 misbehaves, -1 ("the currently focused monitor") is the fallback. */
  monitor: -4;
}
```

- [ ] **Step 3: Verify rofi still parses its config**

```bash
rofi -dump-config 2>/dev/null | grep -E "^\s*monitor"
```
Expected: a line showing `monitor: -4;`. A syntax error in `.rasi` makes rofi fall back to defaults silently, so this check matters.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add .config/rofi/config.rasi
git commit -m "$(cat <<'MSG'
feat(rofi): open menus on the monitor with the focused window

Default is -5, which rofi(1) defines as "the monitor that shows the mouse
pointer" — so menus followed the MOUSE rather than focus. -4 is "the monitor
with the focused window".

Set in config.rasi rather than on individual bindings so the applets and
powermenu scripts inherit it too, not just the two binds in the i3 config.

Fallback if -4 misbehaves: -1, "the currently focused monitor".

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: Session launcher and xinitrc

**Files:**
- Create: `~/projects/dotfiles/.xinitrc-i3`
- Create: `~/projects/dotfiles/.local/bin/start-i3`

**Interfaces:**
- Produces: `start-i3` on `PATH` as the TTY entry point.

- [ ] **Step 1: Read the two files being mirrored**

```bash
cat ~/projects/dotfiles/.local/bin/start-icewm
cat ~/projects/dotfiles/.xinitrc-icewm
```
Copy their structure exactly. Do not invent a new bring-up sequence — that bootstrap took several sessions to get right and encodes non-obvious fixes (keyring components, the ssh-agent socket path shared with Open Brain, portal reapers).

- [ ] **Step 2: Write `.xinitrc-i3`**

```sh
#!/bin/sh
# ~/.xinitrc-i3 — i3/X11 session contents on godlike-artix. Sourced by startx
# (invoked from start-i3).
#
# Session/daemon bootstrap (D-Bus, locale, keyring, ssh-agent, VA-API, session
# identity, GIO_USE_VFS) is done by start-i3 BEFORE `startx` and inherited
# here — do not duplicate it.
#
# Autostart apps are NOT here: i3 has its own exec/exec_always mechanism and
# owns them in ~/.config/i3/config. (The IceWM sibling backgrounds them here
# because IceWM has no equivalent hook.)

# --- X toolkit backends (force X11, not Wayland) ---
export QT_QPA_PLATFORM=xcb
export GDK_BACKEND=x11
export MOZ_ENABLE_WAYLAND=0
export _JAVA_AWT_WM_NONREPARENTING=1   # grey-window Java/Swing fix

# --- Display: native resolution at the panel's MAX refresh ---
x11-max-refresh

# --- Display layout: DP-2 landscape (left) + HDMI-1 portrait (right) ---
# IDENTICAL to the line in .xinitrc-icewm — the physical layout does not change
# with the window manager. See i3-screen-manager
# docs/2026-07-20-desktop-dual-monitor-portrait.md for the centring maths
# (y=240 puts both monitors' centres at y=960) and why the PA248QV needs
# `--rotate right`.
#
# This MUST run before i3 starts, or i3 sees a single monitor and has to
# re-place all ten workspaces afterwards.
xrandr --output DP-2   --primary --rotate normal --pos 0x240 \
       --output HDMI-1            --rotate right  --pos 2560x0

# --- Propagate the X display into the D-Bus activation environment ---
# NOTE: no --systemd flag. The old i3 config used
# `dbus-update-activation-environment --systemd ...` plus
# `systemctl --user import-environment ...`; both are systemd-isms and this
# machine is Artix/OpenRC. The command itself is still REQUIRED — it is what
# lets the gnome-keyring unlock dialog (gcr-prompter) draw.
dbus-update-activation-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP

# --- Audio: pipewire -> wireplumber -> pipewire-pulse (staggered) ---
pipewire &
sleep 0.5 && wireplumber &
sleep 1   && pipewire-pulse &

# --- Window manager ---
exec i3
```

- [ ] **Step 3: Write `start-i3`**

Copy `~/projects/dotfiles/.local/bin/start-icewm` verbatim, then change exactly three things:

1. The header comment — describe i3 rather than IceWM.
2. `XDG_CURRENT_DESKTOP=i3` and `XDG_SESSION_DESKTOP=i3` (was `icewm`).
3. The final line: `exec startx ~/.xinitrc-i3` (was `~/.xinitrc-icewm`).

Everything else — `XDG_RUNTIME_DIR`, locale, D-Bus socket, `XCOMPOSEFILE`, `LIBVA_DRIVER_NAME=radeonsi`, `GIO_USE_VFS=local`, the gnome-keyring and xdg-desktop-portal reapers, the keyring `--components=secrets,pkcs11` invocation, the ssh-agent socket, the flameshot config copy — stays byte-identical.

- [ ] **Step 4: Make executable and link**

```bash
chmod +x ~/projects/dotfiles/.local/bin/start-i3
ln -sfn ~/projects/dotfiles/.local/bin/start-i3 ~/.local/bin/start-i3
ln -sfn ~/projects/dotfiles/.xinitrc-i3 ~/.xinitrc-i3
command -v start-i3
```
Expected: `/home/jim/.local/bin/start-i3`

- [ ] **Step 5: Syntax-check both**

```bash
sh -n ~/projects/dotfiles/.xinitrc-i3          && echo "xinitrc OK"
bash -n ~/projects/dotfiles/.local/bin/start-i3 && echo "launcher OK"
```
Expected: both `OK`.

- [ ] **Step 6: Confirm no systemd-isms survived anywhere**

```bash
grep -rn "systemctl\|--systemd" ~/projects/dotfiles/.xinitrc-i3 ~/projects/dotfiles/.local/bin/start-i3 ~/.config/i3/config \
  || echo "clean — no systemd dependencies"
```
Expected: `clean — no systemd dependencies`

- [ ] **Step 7: Confirm nothing existing was touched**

```bash
cd ~/projects/dotfiles && git status --short
```
Expected: only NEW files (`??`) plus `.config/i3/config-desktop`. **No `M` on `.icewm*`, `.fvwm3`, `.xinitrc-icewm`, `.xinitrc-fvwm3`, `.config/hypr/`, `config.ini`, `start-icewm` or `start-fvwm3`.** If any appear, revert them.

- [ ] **Step 8: Commit**

```bash
cd ~/projects/dotfiles
git add .xinitrc-i3 .local/bin/start-i3
git commit -m "$(cat <<'MSG'
feat(i3): session launcher and xinitrc for the i3 session

start-i3 is start-icewm with exactly three changes: the header comment, the
session identity (XDG_CURRENT_DESKTOP/XDG_SESSION_DESKTOP=i3), and the handoff
target. Everything else stays byte-identical — that bootstrap encodes
non-obvious fixes (keyring components, the ssh-agent socket path shared with
Open Brain, the portal reapers) and is not worth re-deriving.

.xinitrc-i3 reuses the same xrandr layout line verbatim and runs it BEFORE i3
starts, so i3 never sees a single monitor and never has to re-place workspaces.

Autostart is NOT here — i3 owns it via exec/exec_always. The IceWM sibling
backgrounds daemons in its xinitrc only because IceWM has no equivalent hook.

Both systemd lines from the old i3 config are gone:
  systemctl --user import-environment      deleted outright
  dbus-update-activation-environment       kept, WITHOUT --systemd, here
                                           (it is what lets the keyring unlock
                                           prompt draw)

Additive: IceWM, Hyprland and the retained FVWM3 config are untouched.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: Validate on the real display, then document

**Files:**
- Create: `~/projects/i3-screen-manager/docs/2026-07-20-i3-x11-setup.md`
- Modify: `~/projects/i3-screen-manager/CLAUDE.md`

- [ ] **Step 1: Final config check before booting**

```bash
i3 -C -c ~/.config/i3/config ; echo "exit=$?"
```
Expected: exit `0`.

- [ ] **Step 2: Boot from a TTY**

From a TTY (Ctrl+Alt+F2), not from inside an X session:
```bash
start-i3
```
Escape hatch: `$mod+Shift+Escape` exits i3 to the TTY; `start-icewm` restores the previous session.

- [ ] **Step 3: Walk the checklist**

- [ ] Both monitors up with the correct layout (portrait on the right, not upside-down)
- [ ] `i3-msg -t get_workspaces | python3 -m json.tool | grep -E '"(num|output)"'` shows 1–6 on DP-2, 7–10 on HDMI-1
- [ ] **Each polybar shows only its own monitor's workspaces** (the `pin-workspaces` claim)
- [ ] rofi (`$mod+space`) opens on the monitor with the focused window
- [ ] `$mod+Return` opens Ghostty; `$mod+B` opens brave-origin
- [ ] Volume/media keys work (wpctl)
- [ ] Tray populated: nm-applet, udiskie, flameshot
- [ ] `CMOS` reads a voltage, not "command not found"
- [ ] Zoom floats when launched, and can be parked on the side monitor
- [ ] Wallpaper on both monitors

- [ ] **Step 4: PROVE the exec/exec_always answer — do not skip**

The FVWM3 build shipped a duplicate-daemon bug from assuming this.

```bash
ps -C polybar -o pid= | wc -l          # expect 2
i3-msg reload
sleep 3
ps -C polybar -o pid= | wc -l          # MUST still be 2
ps -C dunst -o pid= | wc -l            # expect 1
```
If the count grows, `exec` re-runs on reload and those lines must move — record the real semantics in the outcome doc either way.

- [ ] **Step 5: Write the outcome doc**

Create `docs/2026-07-20-i3-x11-setup.md` following the house pattern of
`docs/2026-06-16-icewm-x11-setup.md` and the FVWM3 outcome doc. Include a
"proven vs assumed" table, and record at minimum:
- the verified `exec` vs `exec_always` semantics from Step 4
- whether `pin-workspaces` actually worked
- whether `rofi -m -4` landed on the right monitor
- how the tiling paradigm feels versus the stacking preference

- [ ] **Step 6: Index it in CLAUDE.md**

Add the doc to the docs list, and update the WM rotation: `godlike-artix`
becomes **Hyprland (Wayland) · i3 (X11) · IceWM (X11) · ~~FVWM3~~**.

- [ ] **Step 7: Commit and push both repos**

```bash
cd ~/projects/i3-screen-manager
git add docs/2026-07-20-i3-x11-setup.md CLAUDE.md
git commit -m "docs: i3 X11 setup outcome on godlike-artix

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push origin master
cd ~/projects/dotfiles && git push origin master
```

---

## Rollback

1. **Run `start-icewm`** — IceWM is untouched and boots normally. Hyprland too.
2. **Unlink:** `rm ~/.config/i3/config ~/.xinitrc-i3 ~/.local/bin/start-i3` (all symlinks; the repo keeps the files).
3. **Uninstall:** `sudo pacman -Rsp i3-wm` to DRY-RUN first, inspect, then `-Rs` only if it removes nothing shared. Note `i3lock` is a *separate* package used by the other sessions — do not remove it.
