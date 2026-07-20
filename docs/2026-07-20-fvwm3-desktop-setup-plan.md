# FVWM3 on `godlike-artix` — design/plan

Standing up **FVWM3** as a third, parallel session on the desktop, alongside the
existing IceWM (X11) and Hyprland (Wayland) ones. Additive and reversible: new
files only, nothing existing is modified or removed.

**Why FVWM3 and not something else:** it is the *only* stacking X11 window
manager with genuinely independent per-monitor workspaces. That finding came out
of a five-source fan-out research pass on 2026-07-20 (Perplexity, Agy, Codex, and
two primary-source verification agents). Refuted in that pass, all confirmed
**global**-workspace: Window Maker, CWM, ctwm, fluxbox, openbox, pekwm, jwm,
sawfish, xfwm4, marco, IceWM. On the Wayland side three qualify — Wayfire, KWin
6.7 (`PerOutputVirtualDesktops`, new in 6.7), and COSMIC — but Hyprland already
covers Wayland on this machine, so the X11 gap is the one worth closing.

*(That research is not yet written up as its own doc. If it ever is, link it
here; until then this section is the record.)*

The one line that matters, quoted from the shipped `fvwm3commands(1)`:

> **DesktopConfiguration** global | per-monitor | shared
>
> With **per-monitor**, each RandR monitor has a separate copy of desktops, and
> hence function independently of one another when switching desks/pages.

FVWM3 was already ranked #3 in `docs/2026-06-15-x11-wm-research.md` ("if the
config-as-code itch wins out but he wants to stay stacking"). It lost to
PekWM/IceWM then — but that evaluation happened while `godlike-artix` was
single-monitor, so per-monitor workspaces could not count in its favour. The
desktop went dual-head on 2026-07-19
(`docs/2026-07-20-desktop-dual-monitor-portrait.md`), which is what reopened it.

**Status:** design approved 2026-07-20. Not yet implemented.

---

## 0. Syntax provenance

Every FVWM3 construct below was read out of the **shipped man pages** of
`galaxy/fvwm3 1.1.5-1`, extracted read-only from the Artix mirror — not from
recollection or web sources. During the research pass a web source produced a
confident but **fabricated** quote of the `DesktopConfiguration` docs, so shipped
man pages are the only accepted authority here.

Anything not yet verified is called out explicitly in §11.

---

## 1. Decisions (and why)

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | **Hybrid bar**: FvwmPager for workspaces, Polybar for everything else | Of the five bar segments, only workspaces needs per-monitor awareness. The other four already exist and work in `config.ini`. |
| 2 | **10 flat desks per monitor**, `DesktopSize 1x1` (pages disabled) | Mirrors the IceWM/Hyprland mental model exactly. FVWM's 2D page grid is a different muscle memory for no gain — and is the specific thing that made Wayfire's workspace grid feel cumbersome. |
| 3 | **No FvwmIconMan** | It is a window *list*. The desired bar shows the *focused* window title, which is Polybar's `xwindow`. |
| 4 | **SloppyFocus** (departure from IceWM's ClickToFocus) | Monitor switching is pointer-driven (§6). Under ClickToFocus you would warp the pointer and still be typing into the old window. |
| 5 | **No stalonetray** | Polybar's `systray` module already covers it; `stalonetray` (`galaxy 1.5.0-1`) is the fallback only if that disappoints. |

An earlier decision to go **all-native** (FvwmPager + FvwmIconMan, no Polybar)
was **reversed** once the target bar layout was known — it would have meant
hand-rolling a focused-title widget, CPU/memory readouts and a clock in
`FvwmButtons`/`FvwmScript`, rebuilding four things that already work.

---

## 2. Target bar layout

```
<workspaces> | <foreground app title> | <machine stats> | <time/date> | <tray>
```

Split by owner:

| Segment | Owner | Notes |
| --- | --- | --- |
| workspaces | **FvwmPager** | per-monitor; `MiniIcons` gives the app-icon-in-workspace look |
| foreground app title | Polybar | `xwindow` |
| machine stats | Polybar | `cpu`, `memory`, `temperature` |
| time/date | Polybar | `date` |
| tray | Polybar | `systray`, main monitor only |

**No launchers anywhere.** Launching is rofi + keybinds, exclusively.

---

## 3. Files (all new)

```
dotfiles/.fvwm3/config       # entry point; Read's the rest
dotfiles/.fvwm3/styles       # borders, no-chrome, per-app window rules
dotfiles/.fvwm3/bindings     # keyboard + Super+mouse
dotfiles/.fvwm3/modules      # FvwmPager, one instance per monitor
dotfiles/.fvwm3/autostart    # StartFunction: polybar, dunst, udiskie, ...
dotfiles/.xinitrc-fvwm3      # session contents
dotfiles/.local/bin/start-fvwm3   # TTY launcher
dotfiles/.config/polybar/config-fvwm3.ini   # derived from config.ini
```

Split rather than one monolith, mirroring the existing `.icewm/` convention
(`preferences` / `keys` / `winoptions` / `toolbar`). FVWM configs grow long.

`~/.fvwm3` is symlinked to the repo, matching how `.icewm` is deployed.

---

## 4. Look — 2px, flat, no chrome

```
Style * !Title, !Handles, BorderWidth 2

Colorset 10 bg #555a5f          # unfocused border  (IceWM ColorNormalBorder)
Colorset 11 bg #33ccff          # focused border    (IceWM ColorActiveBorder)
Style * BorderColorset 10, HilightBorderColorset 11
```

`!Title` removes title bars; `!Handles` removes resize handles so
`BorderWidth` governs (per `fvwm3styles(1)`: *"!Handles, the width from the
BorderWidth style is used"*).

**This is strictly better than the IceWM setup it mirrors.**
`docs/2026-06-16-icewm-x11-setup.md` records that IceWM "color-computes a Win95
bevel on every `Look`, so a uniform border isn't achievable — settled on 2px
beveled cyan/slate." FVWM3's `BorderColorset` documents that *"if one integer is
supplied, that is applied to all window border components"* — i.e. a genuinely
**flat, uniform** 2px border. The compromise IceWM forced is not needed here.

Palette is carried over verbatim so the two X11 sessions read as siblings.

---

## 5. Workspaces

```
DesktopConfiguration per-monitor
DesktopSize 1x1
```

Ten desks, an independent set per monitor.

| Bind | Action |
| --- | --- |
| `Super+1..0` | `GotoDesk 0 <n>` — focused monitor only |
| `Super+Shift+1..0` | `MoveToDesk 0 <n>` — send window, stay put |

Verified signatures: `GotoDesk [screen RANDRNAME] [prev | arg1 [arg2] [min max]]`
and `MoveToDesk [prev | arg1 [arg2] [min max]]`. Two arguments are read as *"a
relative and an absolute desk number"*, so the leading `0` means "no relative
move" and `<n>` is the absolute target — `GotoDesk 0 3` goes to desk 3 outright.

**Desks are 0-indexed**, so the label-to-desk mapping is `Super+1` → desk 0 …
`Super+0` → desk 9. This matches the existing IceWM binds, which already use
0-indexed `icesh -f setWorkspace 0` for the key labelled `1`.

The optional `screen` argument is deliberately omitted from these binds — without
it the **current** monitor is used, which is exactly the desired behaviour.

---

## 6. Monitor switching (pointer-driven)

The pivotal fact, from `fvwm3(1)` on `$[monitor.current]`:

> "current" is the same as the deprecated `$[screen.pointer]` variable; **the
> monitor which has the mouse pointer**.

So the pointer *defines* the current monitor. Warping it is therefore both the
"look over there" action and the "retarget my desk keys" action — one command,
both effects. `$[monitor.prev]` returns the previously focused monitor.

| Bind | Action | Effect |
| --- | --- | --- |
| `Super+grave` | `CursorMove screen $[monitor.prev] 50 50` | toggle between monitors — one key, and still correct if a third monitor is ever added |
| `Super+Shift+grave` | `MoveToScreen $[monitor.prev]` | throw the focused window to the other monitor |

`CursorMove`'s `screen` form is documented with this exact example:
`CursorMove screen DP-1 50 50` → *"move the cursor to the absolute position …
given by the arguments, as … percent values of the monitor's size"*, and values
are clamped inside that monitor's current page.

This is why §1 decision 4 (SloppyFocus) exists: pointer moves → focus follows →
you type on the new monitor. Under ClickToFocus the warp would leave keyboard
focus stranded.

---

## 7. Input

```
Mouse 1 W 4 Move        # Super + LMB  = move    (IceWM MouseWinMove)
Mouse 3 W 4 Resize      # Super + RMB  = resize  (IceWM MouseWinSize)
```

Syntax is `Mouse [(window)] Button Context Modifiers Function`; `4` is
Mod4/Super. Context `W` is the application window — note `fvwm3commands(1)`
warns *"Only 'S' and 'W' are valid for an undecorated window"*, which is exactly
what `!Title, !Handles` produces, so `W` (and `S` for the 2px border) are the
only usable contexts. This is a real constraint, not a stylistic choice.

Keybinds otherwise ported 1:1 from `.icewm/keys`:

| Bind | Command |
| --- | --- |
| `Super+Return` | `ghostty` |
| `Super+Shift+Return` | `ghostty --x11-instance-name=ghostty-floating` |
| `Super+space` | `rofi -modi drun,run -show drun` |
| `Super+d` | `rofi -show run` |
| `Super+b` / `Super+y` | brave-origin (Default / Profile 3) |
| `Super+e` | `emacs` |
| `Super+Shift+b` | `rofi-rbw` |
| `Super+Shift+l` | `i3lock -c 000000` |
| `Super+q` | close window |
| `Super+Up` / `Super+Down` | maximize / restore |
| `Super+Ctrl+BackSpace` | `i3-keyboard-rofi` |
| `Print` | `flameshot gui` |
| `XF86Audio*` | `wpctl` / `playerctl` (verbatim from `.icewm/keys`) |
| `Super+Shift+Escape` | quit FVWM3 back to the TTY |

`Super+Tab` / `Alt+Tab`: FVWM3's `WindowList`, or `rofi -show window` (see §9).

---

## 8. Focus and consent

SloppyFocus, plus a deliberate port of the anti-focus-stealing policy already
proven under IceWM (`.icewm/winoptions` blocks Brave's `_NET_ACTIVE_WINDOW`
grabs via `ignoreActivationMessages`).

FVWM3's equivalent is strictly more capable — from `fvwm3(1)`:

> When a compliant taskbar asks fvwm to activate a window […] fvwm calls the
> complex function **`EWMHActivateWindowFunc`** which by default is
> `Iconify Off, Focus and Raise`. **You can redefine this function.**

IceWM offers a per-window boolean (obey/ignore); FVWM3 offers a *function*, so
policy can be conditional. Intent: an activation request for a window on the
monitor you are already looking at behaves normally; one from the *other*
monitor flashes or marks the window instead of yanking your view. Exact
implementation is an implementation-plan detail.

---

## 9. Out of scope / deferred

- **Expose.** No packaged option: `skippy-xd` and `xfdashboard` are both absent
  from the Artix repos and the AUR is off-limits. Stand-in is `rofi -show window`
  (rofi 2.0.0-1 already installed). FvwmPager's live window miniatures cover part
  of the same itch. Revisit only if it becomes a real irritation.
- **The laptop** (`nomad-artix`). Desktop only. If FVWM3 sticks, the laptop gets
  its own config the way `.icewm-laptop/` mirrors `.icewm/`.
- **`i3-screen-manager` integration.** Not touched. Display layout stays owned by
  `.xinitrc-fvwm3` (same `xrandr` line as `.xinitrc-icewm`).

---

## 10. Verification plan

Manual, in this order — each step gates the next.

### Xephyr caveat: single-instance apps escape to `:0`

A previous Xephyr session on this machine produced "mixed bag" results — apps
launched *inside* Xephyr appeared on the **real** desktop instead. That is not
Xephyr misbehaving, and it is fully explained:

**Every app in the keybind set is single-instance.** `ghostty` runs with
`--gtk-single-instance=true` (a daemon is typically already alive — verified
running as a separate process during the Ghostty swap), `brave-origin` is
Chromium single-instance, and `emacs` does server/client. Each sees a live
instance on `:0`, hands the request off to it, and *that* process opens the
window on its own display. The nested `DISPLAY` never gets a vote.

Mitigations, in order of usefulness:

1. **Test with dumb X clients, not real apps.** `xterm`, `xorg-xeyes`,
   `xorg-xclock`, `xorg-xmessage` (all in `world`) have no single-instance or
   D-Bus-activation logic and always honour `DISPLAY`. They are sufficient for
   everything that actually needs proving here.
2. **Give the nested session its own D-Bus**, so D-Bus activation cannot reach
   the `:0` session: wrap the whole thing in `dbus-run-session`.
3. Only if a real app is genuinely needed: force a fresh instance —
   `ghostty --gtk-single-instance=false`, or `brave-origin --user-data-dir=/tmp/…`.

**Reframing: this barely matters.** Launching apps is the *least* interesting
thing to validate in Xephyr — those keybinds are one-line `Exec` calls that
either fire or don't, and are better checked in the real session. What Xephyr is
genuinely for is the thing that is risky to get wrong on a live display:
**per-monitor desks**, border rendering, pager behaviour, and pointer warping.
All of those are fully exercisable with `xterm` windows.

### Steps

1. **Xephyr first**, before touching the real session. Two fake monitors is
   enough to prove per-monitor desks without risking the live display:
   ```bash
   Xephyr -screen 1200x800 -screen 800x600 +xinerama :2 &
   dbus-run-session -- env DISPLAY=:2 fvwm3 -f ~/.fvwm3/config
   ```
   Populate desks with `DISPLAY=:2 xterm &` / `DISPLAY=:2 xeyes &`.
2. `DesktopConfiguration per-monitor` — switch desks on screen 0, confirm screen
   1 is unchanged. **This is the whole point of the exercise; if it fails, stop.**
3. Borders: 2px, uniform, cyan when focused, slate when not.
4. `Super+LMB` move, `Super+RMB` resize on an undecorated window.
5. `Super+grave` monitor toggle; confirm `Super+3` afterwards targets the *new*
   monitor's desk 3.
6. FvwmPager on each monitor showing only its own desks. **`MiniIcons` cannot be
   fully validated under Xephyr** — bare `xterm`/`xeyes` supply little or no
   `_NET_WM_ICON`, so there may be nothing for the pager to draw. Confirm the
   pager is per-monitor here; defer the icon-rendering check to the real session
   with ghostty/brave/emacs, which do set icons.
7. Polybar `offset-x` clears the pager on both outputs without overlap.
8. Only then boot it for real from a TTY via `start-fvwm3`.

---

## 11. Known risks and unverified assumptions

- **Xephyr cannot validate everything** (see §10): app-launch keybinds and
  `MiniIcons` rendering both need the real session. Plan on a second validation
  pass after `start-fvwm3` rather than treating a green Xephyr run as done.
- **Strut collision (expected to need tuning).** FvwmPager and Polybar are
  separate top-docked windows that both reserve strut space. The `offset-x`
  arithmetic will likely need a round of fiddling against real pixel widths.
  Not a design flaw — just don't expect a clean first hit.
- **`Colorset` command argument syntax is not yet verified** — only the
  `BorderColorset` / `HilightBorderColorset` *styles* that consume it were read.
  Confirm against `fvwm3commands(1)` when writing the config.
- **Polybar under FVWM3 is untested here.** Polybar is EWMH-based and FVWM3 is
  EWMH-compliant, so it should dock, but the `xwindow` module's behaviour under
  per-monitor desks has not been checked. It may report the globally-focused
  window rather than a per-monitor one — acceptable (there is only one keyboard
  focus), but confirm it is not *blank*.
- **What FVWM3 reports as `_NET_CURRENT_DESKTOP` under `per-monitor` is unknown.**
  EWMH has one global scalar and FVWM3 has N. Irrelevant to this design (Polybar
  carries no workspace module) but worth measuring — it is the same trap that
  makes per-monitor workspaces unrepresentable to a standard bar.
- **SloppyFocus is a behavioural departure** from every other session on this
  machine. If it grates, §1 decision 4 is the thing to revisit, and the fallback
  is the explicit `SwitchMonitor` function that pairs `CursorMove` with a focus
  command.
- **`Style * !Title` interacts with `ghostty-floating`.** Under IceWM the
  floating scratch terminal deliberately *keeps* its title bar as a grab handle.
  With no title bars anywhere, that affordance is gone; Super+LMB move replaces
  it. Confirm this is acceptable in practice.
