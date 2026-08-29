# Keybase tray-icon popup lands off-screen under i3 — diagnose & fix

**Date:** 2026-08-13 · **Applies to:** i3/X11, both machines · **Desktop
(`godlike-artix`): DONE** (rule in `dotfiles/.config/i3/config-desktop`) ·
**Laptop (`nomad-artix`): DONE 2026-08-14** (rule in
`dotfiles/.config/i3/config-laptop`) — Option A landed, see below.

## Symptom

Clicking the Keybase tray icon (polybar systray, top-right) pops a small window
at the **wrong place** — bottom-right of the screen, partly clipped off the
bottom — and it **vanishes the instant the pointer leaves the tray area**, so you
can never mouse into it.

## Root cause (verified on the desktop 2026-08-13)

Keybase is Electron. Its tray popup is a **fixed-size 360x640 window**
(`WM_NORMAL_HINTS` min == max == 360x640, gravity Static). Electron computes the
popup position assuming a **bottom** system tray (the Windows/GNOME/KDE default),
so it anchors to the screen **bottom**. Polybar is at the **top**, so the popup
lands bottom-right. Being then far from the pointer, i3's default
`focus_follows_mouse yes` moves focus away as you traverse toward it, Electron's
blur handler fires, and the popup hides → unreachable.

Only the *vertical* placement is inverted; horizontal was already fine. i3
**auto-floats** the popup (equal min/max size hint) and **manages** it (it is
NOT override-redirect), so a `for_window` rule *can* reposition it. Moving it to
the top-right made it reachable — confirmed by hand on the desktop.

## Distinguishing the popup from the main Keybase window

Both share `WM_CLASS "keybase","Keybase"`, `WM_WINDOW_ROLE browser-window`, and
`_NET_WM_WINDOW_TYPE_NORMAL`. The only reliable distinguisher is the **title**:

- popup → exactly `"Keybase"`
- main app → `"Keybase: Chat"` (and other `"Keybase: <view>"` strings)

So `[class="Keybase" title="^Keybase$"]` matches the popup only. Edge case: if the
main window ever shows a bare `"Keybase"` title, the rule would catch it too —
rare, recover with `$mod+Shift+space`.

## Diagnostic commands (run on the laptop, popup open)

```sh
# 1. Confirm session + WM
echo "$XDG_SESSION_TYPE"; pgrep -a i3

# 2. Open the popup (click the tray icon), then find it: the 360x640 FLOATING
#    window whose title is exactly "Keybase".
i3-msg -t get_tree | python3 -c 'import sys,json
def w(n):
 for k in ("nodes","floating_nodes"):
  for c in n.get(k,[]):
   wp=c.get("window_properties") or {}
   if c.get("window") and "keybase" in (wp.get("class","")+(c.get("name") or "")).lower():
    print(c["window"], repr(c.get("name")), c.get("floating"), c.get("rect"))
   w(c)
w(json.load(sys.stdin))'

# 3. Confirm fixed-size (why it auto-floats) + NORMAL type:
xprop -id <popup-id> WM_CLASS WM_NAME _NET_WM_WINDOW_TYPE WM_NORMAL_HINTS

# 4. Current outputs (which one holds the tray) + polybar height:
i3-msg -t get_outputs | python3 -c 'import sys,json;[print(o["name"],o["rect"],"PRIMARY" if o.get("primary") else "") for o in json.load(sys.stdin) if o.get("active")]'
grep -nE "height" ~/.config/polybar/config-i3-laptop.ini
```

(`xwininfo`/`wmctrl` are not installed on the fleet; `xprop`, `xdotool`, `i3-msg`
are. `xdotool getwindowgeometry <id>` and `xdotool search --onlyvisible --class
keybase` are handy for watching the transient popup.)

## The fix — and why the DESKTOP's rule is WRONG for the laptop

The desktop rule (in `config-desktop`) hardcodes absolute coordinates:

```
for_window [class="Keybase" title="^Keybase$"] floating enable, move position 2200 272
```

Those numbers encode the desktop's **static** dual-monitor layout: DP-2's origin
is y=240 (pushed down by the portrait monitor), polybar is 28px, primary is
2560 wide, so 360px right-aligns at x=2200 and y=272 sits just under the bar.

**On the laptop those numbers are wrong — and wrong in *different* ways depending
on state.** Docked vs. clamshell changes which output carries the tray and its
origin/width; a dynamic scale change (`i3-screen-manager scale`) moves everything
again. A fixed `move position X Y` cannot track that. Pick one of the two
layout-aware options below instead.

### Option A (try first, cheapest): anchor to the pointer — LANDED on the laptop

You open the popup by *clicking the tray icon*, so the pointer is on the tray at
that instant. Move the popup to the mouse — layout-independent, survives clamshell
and DPI changes for free:

```sh
# live test, no config edit — open the popup first, then:
i3-msg '[class="Keybase" title="^Keybase$"] floating enable, move position mouse'
```

**Verify the right edge.** The concern going in was that i3 might not clamp
floating windows on-screen (that's *why* the bug clips off the bottom in the
first place), so with the pointer at the extreme top-right the popup could hang
off the right edge.

**Verified live on the laptop 2026-08-14 — it's fine.** `move position mouse`
specifically (not a plain absolute `move position X Y`) **does** clamp: it
centers the window at the pointer, then keeps the whole window on-screen. Live
test at the tray icon (2544,15 on a 2560-wide eDP-1), popup 400×589: intended
center-anchored top-left would be off-screen negative/overflowing, and i3
clamped it to `{x:2160, y:0}` — right edge flush with the screen edge, top
clamped to 0. A second run with a *different* popup size (459×809 — the
Keybase popup turned out not to be truly fixed-size on this Electron build)
clamped just as cleanly. So the right-edge worry from the design phase didn't
pan out in practice; no extra edge-handling needed.

One remaining wrinkle: `y` clamped to `0`, which sits *behind* the always-on-top
32px polybar bar rather than under it. Fixed with one more relative move:

```sh
for_window [class="Keybase" title="^Keybase$"] floating enable, move position mouse, move down 32px
```

(`32` = `height` in `polybar/config-i3-laptop.ini` — bump this if that value
ever changes.) This is the rule now live in `config-laptop`, verified end-to-end
after `i3-msg reload`: closed the popup, clicked the tray icon fresh, and the
persisted rule placed it at `{x:2101, y:32}` with no manual `i3-msg` needed.
Option B was not needed.

### Option B (robust for dynamic layouts): recompute from the live output

If Option A overflows, don't hardcode — compute the anchor from the **currently
active output** each time the popup opens, so it re-adapts on clamshell/DPI change.
A static rule can't compute; use a small move-on-open watcher launched from the
i3 `exec` / xinitrc:

```sh
#!/usr/bin/env bash
# keybase-popup-anchor — subscribe to i3 window events; when the Keybase popup
# appears, anchor it to the top-right of whatever output currently has focus.
# math each time:  x = out.x + out.width - 360 ;  y = out.y + <polybar height>
i3-msg -t subscribe -m '[ "window" ]' | while read -r _ev; do
  read -r x y < <(i3-msg -t get_workspaces | python3 -c '
import sys,json,subprocess
ws=json.load(sys.stdin)
foc=next((w for w in ws if w["focused"]), ws[0])["output"]
outs=json.load(subprocess.run(["i3-msg","-t","get_outputs"],capture_output=True,text=True).stdout and __import__("io").StringIO(subprocess.run(["i3-msg","-t","get_outputs"],capture_output=True,text=True).stdout))
r=next(o["rect"] for o in outs if o["name"]==foc)
BAR=28   # read from config-i3-laptop.ini
print(r["x"]+r["width"]-360, r["y"]+BAR)')
  i3-msg "[class=\"Keybase\" title=\"^Keybase$\"] floating enable, move position $x $y" >/dev/null
done
```

(Sketch — tighten the event filter so it only moves on the popup's map, and read
`BAR` from the polybar config rather than hardcoding. The principle is the thing:
**recompute from live geometry, never hardcode.** `i3-screen-manager status` /
`get_outputs` already expose the active-output rect.)

### If the popup reopens at the wrong spot DESPITE the rule (Electron re-race)

Some Electron builds set the popup position *after* the window maps, beating i3's
map-time `for_window`. Mitigations, in order:

1. i3 re-runs `for_window` on **title change** too — if Electron sets the title
   after positioning, the rule fires again and wins. Often enough on its own.
2. If not, the Option-B watcher (which reacts a beat later, and can also key off
   the `window::move` event) is the robust answer.

> The desktop's auto-fire behavior (does the `for_window` rule win the map/position
> race on reopen, or does Electron re-place it?) was **still being confirmed at
> write time.** Verify it fresh on the laptop regardless — the Keybase/Electron
> version there may differ.

## Success criteria

1. Click the tray icon → popup appears top-right, under the tray, on **any**
   layout (docked, clamshell, post-DPI-change).
2. You can slide the pointer from the tray icon into the popup without it hiding.

## Deploy note

`~/.config/i3/config` is symlinked into the dotfiles repo on both machines
(`config-desktop` / `config-laptop`), so editing the repo file *is* editing the
live config — but i3 only applies a new `for_window` to *future* window maps, so
close and reopen the popup to test. Whether Keybase even runs on the laptop
depends on whether the workspace-10 comms stack is wired there yet (it was
deferred — see `docs/2026-07-21-i3-laptop-setup.md`); this fix applies whenever
Keybase runs under i3.

## Hyprland port (2026-08-29): windowrules can't do it — daemon instead

The first Hyprland port attempted the same trick as the i3 rule: a
`hl.window_rule` matching class+title="Keybase" with a `float=true, move={x,y}`
action. It looked plausible. It broke Keybase.

### What was tried (and broken same day, 2026-08-29)

    if m.type == "desktop" then
      hl.window_rule({ name = "keybase-popup", match = { class = "^(Keybase)$",
        title = "^(Keybase)$" }, float = true, move = { 2200, 272 } })
    elseif m.type == "laptop" then
      hl.window_rule({ name = "keybase-popup", match = { class = "^(Keybase)$",
        title = "^(Keybase)$" }, float = true, move = { "100%-w", "28" } })
    end

Live smoke test on the laptop caught it: the rule fired for the MAIN Keybase
window at map time, floated it, and jammed it to `(-3, 23)` — because
`100%-w = 2048 − 2054 = -6` on a 2048-logical-px monitor when the main window
is 2054 wide. Screenshot in the desktop's screen showed the popup landing at
screen center instead (Electron re-races the popup's position **after** the
map, undoing the rule's move — only the wrecked-main effect stuck). Same
latent bug on the desktop's hardcoded-coord form: `{2200, 272}` would have
jammed the main window off the right of DP-2 the next time Keybase restarted.
It just hadn't been triggered yet — Keybase there had been running since
before the rule landed 2026-08-13, so no map event ever fired against it.

### Why no windowrule can solve this

    both windows have  class=Keybase, title=Keybase, initialTitle=Keybase
                       initialClass=Keybase, xdgTag="", xdgDescription=""

Verified by `hyprctl clients` on the popup and main side-by-side. The main
window's title renames from `"Keybase"` → `"Keybase: People"` (or whatever
tab is active) a beat AFTER map, too late for the rule to see. **And
windowrulev2 has no `size:` selector** — the one property that DOES separate
them (popup ~360x640 vs main ~2054x1263) can't be matched declaratively. So
any rule that catches the popup also catches the main. This is the whole
reason a daemon is needed here.

### The daemon — `keybase-popup-anchor`

Ships in this repo (`~/projects/i3-screen-manager/keybase-popup-anchor`,
symlinked into `~/.local/bin/`) and auto-launched from Hyprland's
`autostart.lua` shared-daemons block alongside `ydotoold`:

    hl.exec_cmd("keybase-popup-anchor")

Shape (~60 lines of bash):

1. Discover the live `HYPRLAND_INSTANCE_SIGNATURE` (env if valid → `hyprctl
   instances` → socket-file scan).
2. `socat -u UNIX-CONNECT:.../.socket2.sock -` — read the event stream.
3. Filter `openwindow>>address,workspace,class,title` where `class=Keybase`.
4. `hyprctl -j clients` → look up the window's `size` and `monitor`.
5. If `size.width > 1000` skip (main window). Popup widths observed:
   360, 400, 459 — 1000 divides safely.
6. `hyprctl -j monitors` → for that window's own monitor, compute
   `logical_width = round(width / scale)`, then target
   `x = logical_width − reserved[2] − popup.width`,
   `y = reserved[1]` (top-bar height).
7. `hyprctl dispatch 'hl.dsp.window.move({window="address:0x…", x=X, y=Y})'`.

Event-through-move measured at same-millisecond timestamps in the socat
buffer; no visible flash. Electron doesn't re-race the move (unlike its
map-time positioning) so a single dispatch sticks. If Hyprland restarts,
socat exits on EOF, this script exits, and autostart re-launches it on the
next `hyprland.start`.

### Why the raw pixel/logical distinction matters

`hyprctl -j monitors` reports `width` and `height` in **raw** pixels but no
`logical_width`. Coordinates in `at` / dispatch calls are in **logical**
pixels. So on `eDP-1` at 2560×1600 raw with `scale=1.25`, the logical width
is `round(2560/1.25) = 2048`. Skipping the scale division caused the
prototype to send the popup to `(2200, 28)` on a screen whose right edge is
at `x=2048` — Hyprland clamped it back to a position ~500px shy of flush-right,
which is exactly what the "better, but perhaps a bit more to the right?"
feedback in the visual smoke test showed. `reserved` is already in logical
pixels (matches the Quickshell bar's `Theme.barHeight = 28`), no conversion
there.

### If Hyprland ever grows a `size:` selector

Rip the whole daemon out — replace with:

    hl.window_rule({ name = "keybase-popup",
      match = { class = "^(Keybase)$", size_lt = { 1000, 1000 } },
      float = true, move = { "100%-w", "28" } })

Kill it from `autostart.lua` too. Track the Hyprland-plugin/upstream
issue for a size selector; this is the primary shrink path.

### Sibling reads

- `docs/2026-08-28-quickshell-bar-plan.md` § Update 2026-08-29 — Keybase's
  tray-icon churn is also what triggered the rare Quickshell SNI segfault.
- CLAUDE.md § "Common Issues → Hyprland/Wayland" — the sibling silent-fail
  gotcha for `hyprctl dispatch <verb>` under Lua mode (same gotcha class as
  why the un-float during diagnosis needed
  `hl.dsp.window.float({window="address:0x…", action="toggle"})` not
  `settiled address:0x…`).
