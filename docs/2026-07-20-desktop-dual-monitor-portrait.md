# Desktop dual-monitor: portrait secondary (`godlike-artix`)

Adding a second display to the desktop — an **ASUS PA248QV** (24", 1920x1200,
16:10) physically **pivoted** and sitting to the right of the main **ASUS PB328**
(32", 2560x1440) — with both at native resolution and their vertical centers
aligned.

Done **2026-07-19** on `godlike-artix` (Threadripper + Radeon RX 7900 XT, Navi 31).
Applied and verified live under **IceWM/X11**; the Hyprland side is written but
**not yet exercised** (see §5).

The second half of this doc (§7) records a research result that is independent of
the layout: **IceWM cannot give the new monitor its own workspaces or its own
bar**, why that is architectural rather than a missing setting, and what a
different bar can and cannot fix.

---

## 0. Final layout

| Output (X11 / Wayland) | Panel | Geometry | Rate | Center |
| --- | --- | --- | --- | --- |
| `DP-2` / `DP-2` | ASUS PB328 32" | `2560x1440+0+240` (primary) | 74.97 Hz | y=960 |
| `HDMI-1` / `HDMI-A-1` | ASUS PA248QV 24" | `1200x1920+2560+0`, rotated | 74.93 Hz | y=960 |

Framebuffer: **3760x1920**. Confirmed with `icesh xinerama`:

```
0: 2560x1440+0+240
1: 1200x1920+2560+0
```

---

## 1. Rotation: which way, and why

The PA248QV is pivoted so its **bottom bezel faces right** — that is a **90°
counter-clockwise** physical rotation. To compensate, the framebuffer must be
rotated **clockwise**, which is `xrandr --rotate right`.

The general rule, which is easy to get backwards:

| Physical pivot | Bottom bezel ends up | xrandr |
| --- | --- | --- |
| counter-clockwise | **right** | `--rotate right` |
| clockwise | left | `--rotate left` |

The compensation is always the *opposite* sense of the physical pivot.

**The failure mode is benign**: get it backwards and the image is 180° upside-down
— still portrait, still the right resolution, obviously wrong at a glance, fixed
by swapping one word. There is no way to damage anything, so when in doubt just
try one and look. Verified visually here before persisting.

---

## 2. The centering math

The requirement was that the two panels share a vertical center.

Rotated, the PA248QV presents as **1200x1920** — it is **taller** (1920) than the
PB328 (1440). So the tall panel sits at `y=0` and the *short* one is pushed down:

```
offset = (1920 - 1440) / 2 = 240
```

- `HDMI-1` at y=0 spans 0..1920 → center **960**
- `DP-2` at y=240 spans 240..1680 → center **960** ✓

**X11 has no negative screen coordinates**, so the shorter monitor is always the
one that carries the offset. You cannot express this as "the tall one at y=-240".

---

## 3. Name gotcha: `HDMI-1` (X11) vs `HDMI-A-1` (Wayland)

The same physical port has **two different names** depending on the stack:

- **xrandr / X11** → `HDMI-1`
- **kernel DRM connector, therefore wlroots/Hyprland** → `HDMI-A-1`

```bash
# The authoritative Wayland-side name, readable from an X11 session:
for c in /sys/class/drm/card*-*; do
  [ "$(cat "$c/status" 2>/dev/null)" = connected ] && basename "$c"
done
# card1-DP-2 / card1-HDMI-A-1
```

Copying the xrandr layout into the Hyprland config verbatim would match nothing
and silently fall through to the catch-all. `DP-2` happens to be spelled the same
in both, which makes the mismatch easy to miss.

---

## 4. What changed

All three files are symlinked into `~`, so they went live immediately.

| File | Change |
| --- | --- |
| `dotfiles/.xinitrc-icewm` | layout `xrandr` line after `x11-max-refresh` |
| `dotfiles/.config/hypr/hyprland-desktop.lua` | explicit `DP-2` + `HDMI-A-1` monitors; catch-all defused |
| `dotfiles/.config/hypr/hyprland-desktop.conf` | same, hyprlang spelling |

The X11 line deliberately carries **no `--mode`/`--rate`**: `x11-max-refresh`
(which runs immediately before it) already selects each panel's native mode at its
highest rate, and xrandr preserves the current mode when only `--rotate`/`--pos`
are given. That keeps the layout line resolution-agnostic.

```sh
xrandr --output DP-2   --primary --rotate normal --pos 0x240 \
       --output HDMI-1            --rotate right  --pos 2560x0
```

**Verified by replay, not by assumption**: the displays were reset to X's default
auto-layout and the persisted sequence (`x11-max-refresh` → the line above) was
re-run from scratch. It reproduces the target geometry exactly, and both panels
keep 74.97/74.93 Hz through the rotation.

### The old Hyprland catch-all was a latent landmine

```
monitor=,2560x1440@74.97,auto,1     # was
```

That applied a **hardcoded 2560x1440 to every output**. Harmless with one
monitor; the moment a 1920x1200 panel appeared it would have forced an impossible
mode on it. Now:

```
monitor=,preferred,auto,1                              # catch-all, no hardcoded mode
monitor=DP-2,2560x1440@74.97,0x240,1
monitor=HDMI-A-1,1920x1200@74.93,2560x0,1,transform,1
```

---

## 5. UNVERIFIED: the Hyprland `transform` value

`transform = 1` (90°) is the wlroots spelling of `--rotate right`. The key name
and type were confirmed against the shipped Lua API stub:

```bash
grep -A25 "class HL.MonitorSpec" /usr/share/hypr/stubs/hl.meta.lua
# ---@field transform? integer|boolean
```

…but the **direction** was not tested, because all of this was done from an X11
session and Hyprland was not running.

**On the next Hyprland boot: look at the portrait panel.** If it is upside-down,
change `transform = 1` to `transform = 3` in
`hyprland-desktop.lua` (and `transform,1` → `transform,3` in the `.conf`). Those
are the only two candidates — both produce portrait, they differ by 180°.

---

## 6. Fixed in passing: stale `primary` on a disconnected output

RANDR reported `DP-1 disconnected primary` — a leftover pointing at an output
that no longer exists. Anything asking RANDR for "the primary output"
(notification placement, some fullscreen paths) was being handed a dead one.

Harmless with a single monitor, worth being explicit with two, so the layout line
now sets `--primary DP-2`.

Notably this was **not** breaking the taskbar: IceWM is Xinerama-aware and had
already placed it correctly at `2560x25+0+240` (top of DP-2, correct width). It
did not move when primary changed — measured before and after.

---

## 7. IceWM: no per-monitor workspaces, no per-monitor bar

Two things the new monitor **cannot** have under IceWM 4.0. Both were researched
against the installed version rather than assumed, because the answers are
counterintuitive if you are coming from Hyprland/i3.

### 7a. Independent workspaces — no. This is architectural.

A workspace in IceWM is a property of the **X screen**, not of a monitor. Read
straight off the running root window:

| Property | Value | Meaning |
| --- | --- | --- |
| `_NET_NUMBER_OF_DESKTOPS` | `10` | ten workspaces |
| `_NET_CURRENT_DESKTOP` | `9` | **one scalar for everything** |
| `_NET_DESKTOP_GEOMETRY` | `3760, 1920` | one desktop spanning **both** panels |
| `_NET_DESKTOP_VIEWPORT` | all zeros | no desktop is bound to a monitor |

```bash
xprop -root _NET_CURRENT_DESKTOP _NET_DESKTOP_GEOMETRY _NET_DESKTOP_VIEWPORT
```

This is the EWMH **global-desktop** model: switching workspace switches *both*
monitors together. Per-monitor workspaces require the WM to maintain a separate
workspace set per output — a different architecture, not a setting. Nothing in
IceWM 4.0's preference set exposes it; every workspace option (`KeySysWorkspace*`,
`TaskBarShowWorkspaces`, …) is global.

### 7b. Independent bar — no, not natively.

- `XineramaPrimaryScreen` is documented as *"Primary screen for xinerama where
  taskbar is shown"* — **singular**, `[0-63]`, one screen.
- All ~40 `TaskBar*` options: nothing per-monitor / all-monitor.
- **There is no standalone taskbar binary.** The taskbar is compiled into `icewm`
  itself — `/usr/bin/` ships only `icewm`, `icesh`, `icewmbg`, `icewmhint`,
  `icesound`, `icehelp`, the two menu helpers and `icewm-session`. So the "run a
  second instance on the other monitor" trick is unavailable.

### 7c. Would a different bar help?

**For the bar: yes.** Polybar (3.7.2, already installed) does per-monitor bars in
one line — `monitor = HDMI-1` in the bar section, one instance per output.

**For the workspaces: no, and it never can.** A bar is a *view* of WM state, not a
source of it. Every bar reads the same global `_NET_CURRENT_DESKTOP`, so two bars
would display identical workspace state.

Specifically: polybar's `xworkspaces` module has a `pin-workspaces` option that
filters workspaces to the bar's own monitor — the exact feature you would reach
for. It works by reading `_NET_DESKTOP_VIEWPORT`, which **IceWM reports as all
zeros**. There is nothing to pin against. That lever is dead here.

### 7d. The practical workaround: sticky windows

What people usually want from "independent workspaces" on a secondary panel is
narrower than it sounds: *reference content stays put while I switch workspaces on
the main monitor.* IceWM offers that directly, no workspace independence needed —
per-window `allWorkspaces` in `winoptions`:

```
# ~/.icewm/winoptions — NAME.CLASS.OPTION
SomeApp.allWorkspaces: 1
SomeApp.ignoreQuickSwitch: 1
```

`man icewm-winoptions` documents it as *"show it on all workspaces"* and its own
examples (`wmtime`, `xeyes`) use exactly this pattern for persistent utility
windows. **Not currently applied** — recorded as the cheap option if the itch
returns.

`icesh` also has `-X, -Xinerama MONITOR` to limit operations to clients on one
monitor, which is enough to script *pseudo*-per-monitor behavior. That would mean
reimplementing workspace logic against the WM's grain; noted for completeness, not
recommended.

### 7e. If independent workspaces are ever a hard requirement

That is a WM swap, not a config change. X11 WMs that model workspaces per-output:
**i3, awesome, xmonad, herbstluftwm, bspwm, spectrwm, qtile**.

Worth remembering: **Hyprland already does this natively** — per-monitor
workspaces are first-class there. So the capability exists on this machine today;
it just lives on the Wayland side.

---

## 8. Tested and benign — do not let this become folklore

`_NET_WORKAREA` is reported as a **single global rect** `0, 0, 3760, 1680`, which
stops 240px short of the portrait panel's bottom edge (it spans to 1920). That
looks exactly like a bug that would clip maximized windows on the new monitor.

**It does not.** Maximizing a window on the portrait panel yields the full
`1200x1920+2560+0`:

```bash
icesh -w "$wid" maximize && xdotool getwindowgeometry "$wid"
# Position: 2560,0   Geometry: 1200x1920
```

IceWM's own maximize is Xinerama-aware and uses per-monitor geometry. The global
`_NET_WORKAREA` rect only affects **third-party** apps that read that property for
placement. If some app ever does misplace itself on the portrait panel, the knob
is `NetWorkAreaBehaviour` (default `0`, currently unset in
`~/.icewm/preferences`; values `0`/`1`/`2` per `/usr/share/icewm/preferences`).

---

## 9. Watch list

- **Hyprland `transform` direction is unverified** (§5) — check on next Wayland
  boot; the fix is `1` → `3`.
- **`i3-screen-manager` does not know about this machine.** It is built around the
  laptop's internal-`eDP-1`-plus-one-external model; the desktop's two-external
  portrait layout is expressed purely in the two session configs. Fine today, but
  it means there is no rofi-driven way to re-apply the layout after a
  monitor sleep/replug that scrambles it. If that turns out to be a real
  annoyance, promoting the `xrandr` line to a small `x11-desktop-layout` script
  (callable from `i3-screen-rofi`) is the obvious next step.
- **Sticky-window rules (§7d) are documented but not applied.**
