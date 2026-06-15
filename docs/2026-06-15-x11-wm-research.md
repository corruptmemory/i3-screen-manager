# Meeting notes — X11 window manager survey (leaving Hyprland?)

**Date:** 2026-06-15
**Present:** Jim, Claude (godlike-artix / desktop)
**Impetus:** Jim is "strongly inclined to leave Hyprland." Wants an X11 WM with
life in it (actively maintained/developed). Disinclined toward full DEs. Tiling
or stacking both fine, but **leaning stacking** these days. Config must be
files — either a config file or a *program* file (Qtile/Python, Lua, Lisp all
acceptable). Lived in i3 for a while; floated **Openbox** as a *directional*
suggestion (the vibe, not a literal target — he already knew Openbox is dead).

> **Methodology note:** Maintenance status was verified against the actual
> upstream repos/release pages, NOT taken from an LLM synthesis. The first
> deep-research pass *hallucinated* precise-looking versions (claimed "Openbox
> 3.7.2, late 2024" and "Fluxbox 1.3.8, March 2026" — both fiction). Treat any
> un-sourced version/date in WM research with suspicion; check the repo.

## Headline: Openbox is dead upstream (as expected)

- Last real release **3.6.1 (2015)**; declared "feature-complete" since ~2010.
- **No mainstream maintained fork** — the GitHub mirrors are archives.
- Still runs fine on X; just not "developed." Treated here as a *direction*
  (lightweight stacking, file config), not a candidate.

## Verified landscape — stacking WMs that are actually alive

| WM | Latest release (verified) | Activity | Config | Notes |
|---|---|---|---|---|
| **IceWM** | **4.0.0** (2026-01-01); 3.9.0 Aug'25, 3.7.5 May'25 | **Very active** (~monthly) | Plain-text (`~/.icewm/`: `preferences`, `keys`, `menu`, `toolbar`) | "Openbox but maintained." Built-in taskbar/menu/systray. Batteries-included, slightly retro-DE feel. |
| **PekWM** | GitHub 0.3.2 (Dec'24); **Fossil 0.4.x, commits into Feb 2026** | **Active** | Plain-text (`~/.pekwm/`: `config`, `keys`, `mouse`, `menu`, `autoproperties`, `themes`) | **Front-runner.** Signature **window grouping/tabbing**. `autoproperties` ≈ i3 criteria. Descends from aewm++. Dev lives on **Fossil** at pekwm.se (GitHub is a mirror). |
| **FVWM3** | **1.1.4** (1.1.3 = 2025-06-01, 1.1.2 = 2025-02-08) | **Active** | Plain-text, deeply scriptable (config-as-code) | Power-user stacking WM. Infinitely configurable, steep curve. Scratches the Qtile/Lua "program my WM" itch while staying stacking. |
| **JWM** | **2.4.6** (2024-11-09) | Slow but releasing; solo dev | **XML** (like Openbox `rc.xml`) | Ultralight. Most Openbox-like config *format* still shipping. |
| **Fluxbox** | 1.3.7 (**2015**) | Frozen / "feature complete" | Plain-text | Blackbox family, Openbox-adjacent. Works, but no release in a decade — same boat as Openbox. |
| **Window Maker** | occasional releases (~2024) | Slow but alive | Mostly **GUI** (WPrefs) | NeXTSTEP aesthetic. Weak fit for the "config = files" rule. |
| **cwm** | OpenBSD in-tree; portable fork exists | Alive (within OpenBSD) | `~/.cwmrc` (tiny, simple) | Minimalist stacking. If you want *less* than Openbox. |

## The "config-as-a-program" branch (Jim mentioned Qtile/Lua)

- **awesome** — **Lua** config, **X11-only by design** (no Wayland, ever — model
  is too X11-tied). Git-active, but tagged releases infrequent (4.3 is last
  stable). dwm-derived → **tiling-first** (does floating too). The Lua answer,
  but leans tiling, against the stacking drift.
- **Sawfish** — **Lisp** config, genuinely **stacking**. Purest "program-config
  + stacking" combo. Maintenance sleepy but not dead.
- **herbstluftwm** — config is a **shell script** of IPC commands. Manual tiling,
  X11, maintained.
- **Qtile** — **Python** config, has an X11 backend (+ Wayland). Tiling-first.

**Gap identified:** Lua + stacking + maintained basically doesn't exist. awesome
is the only living Lua WM and it's tiling-rooted; the only mature stacking +
program-config option is Sawfish (Lisp).

## Recommendation / current leaning

1. **PekWM** — best spirit match (lightweight stacking, Blackbox-family feel,
   grouping/tabbing bonus, *actively developed on Fossil*). Jim reacted strongly
   to the Fossil choice — signals a maintainer optimizing for 15-year
   longevity, the right temperament for a WM you live in. **Front-runner.**
2. **IceWM** — best objective "alive" match; revisit. Trade-off vs PekWM is
   menu/panel philosophy: IceWM ships an opinionated bar (batteries-included);
   PekWM is barer ("bring your own furniture" — fits Jim's existing rofi/Waybar
   muscle memory better).
3. **FVWM3** — if the config-as-code itch wins out but he wants to stay stacking.

All three are in Arch/AUR → trivial to trial on Artix (`yay -S icewm pekwm fvwm3`).

## Open questions / next actions

- [x] Jim did his reading and **chose PekWM** to trial first (Fossil dev,
      stacking, native frame-tabbing). IceWM stays the backup if PekWM disappoints.
- [x] PekWM config **built and smoke-tested** (2026-06-15): full Hyprland-parity
      keybinds, Polybar, rofi, dunst, autostart — on XLibre, toggleable against
      Hyprland. Display scripts (`i3-screen-*`) were **not** ported — godlike-artix
      is single-monitor, so they're moot. Adopted PekWM's native `FillEdge`
      half-screen snapping as the stacking-world stand-in for tiling. See
      `2026-06-15-pekwm-x11-setup.md` (spec) and `…-plan.md` (build + execution log).
- [ ] **Pending:** TTY-boot validation (only Jim can do it from a real session),
      then the verdict — PekWM vs Hyprland, and vs IceWM if PekWM falls short.
