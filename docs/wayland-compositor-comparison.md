# Wayland Compositor Comparison

Evaluating Hyprland, Wayfire, River, and Niri for laptop migration (ThinkPad X1 Extreme Gen 5, Intel Iris Xe + NVIDIA RTX 3050 Ti, Artix/OpenRC).

Research date: 2026-03-31

---

## Quick Reference

| Aspect | Hyprland | Wayfire | River | Niri |
|--------|----------|---------|-------|------|
| **Type** | Dynamic tiling | Floating/stacking (+ tiling plugin) | Modular (compositor + separate WM) | Scrollable tiling |
| **Language** | C++ | C++ | Zig | Rust |
| **Base** | Aquamarine (custom) | wlroots | wlroots | Smithay |
| **XWayland** | Native, integrated | Native, integrated | Native, integrated | External (xwayland-satellite) |
| **Maturity** | Most popular, large community | Mature, smaller community | Production-ready (0.4.0), growing | Young, growing fast |
| **NVIDIA hybrid** | Documented, community-tested | Problematic | wlroots-dependent, similar issues | VRAM leak, Gamescope crashes |
| **Gamescope** | Works (with caveats) | Avoid (conflicts) | Should work (wlroots) | Crashes on NVIDIA |
| **Zoom** | Works-ish via XWayland | First share works, subsequent shares black | Untested (likely similar to wlroots compositors) | Broken via xwayland-satellite |
| **Overview/Expo** | Via plugins | Built-in Expo plugin (excellent) | Depends on WM choice | Built-in |
| **Config** | Custom .conf format | INI (wayfire.ini) | Shell script (`init`) + riverctl | KDL format |
| **Bling disable** | Full control | Full control | Minimal by design | Full control |
| **Community size** | Largest | Moderate | Growing | Growing |

---

## Hyprland

**Status: Current plan A.** Full migration checklist at `docs/hyprland-migration.md`.

### Strengths
- Largest Wayland tiling WM community (~3rd most popular Linux environment per 2025 Arch survey)
- Native XWayland — Zoom, Steam, legacy apps work without extra bridges
- Gamescope works (essential fallback for problem games)
- Proton native Wayland support well-documented (`PROTON_ADD_CONFIG=wayland %command%`)
- NVIDIA hybrid documented extensively, community-tested workarounds exist
- Full control over animations/bling (disable everything for instant responses)
- Dynamic tiling with floating support

### Weaknesses
- No built-in Expo/overview (plugin ecosystem, not as polished as Gnome/Wayfire)
- Tiling-first means floating workflow requires explicit window rules
- NVIDIA DX12 performance gap persists (driver-level, not Hyprland's fault)
- Mouse capture issues in XWayland games (workaround: `no_hardware_cursors = true`, or Gamescope, or native Wine Wayland)
- OpenRC needs workarounds (no `systemctl --user`, manual portal startup)
- Configuration format is unique (not INI, not YAML, not KDL)

### Gaming
See `docs/hyprland-migration.md` → "Steam Gaming on Hyprland" for full details.

**TL;DR:** Most games work through XWayland + Proton. Native Wine Wayland (opt-in) improving rapidly. Gamescope available as fallback. Mouse capture is the main gotcha — multiple workarounds exist.

### Zoom
Works-ish via native XWayland. Floating toolbar, mini-window, participant thumbnails function because XWayland handles positioning. Screen sharing via `enableWaylandShare=true` + PipeWire mode. Better than any non-XWayland compositor.

---

## Wayfire

**Status: Interesting alternative.** Floating-first with optional tiling — addresses the "sometimes I wish I wasn't using a tiling WM" frustration.

### Strengths
- **Floating/stacking by default** — windows behave like a traditional desktop. Tiling available as a plugin (`simple-tile`) when you want it
- **Expo plugin** — the killer feature. Gnome-style workspace overview, keyboard-navigable as of 0.8.0. This is the overview you liked.
- **Workspace sets** (0.8.0) — multiple independent workspace grids per output, switchable. Approximates Sway's workspace model while maintaining floating focus
- **3D effects** (Compiz heritage) — cube, wobbly windows, burn animations. All disableable. The point is the compositor is *capable*, not that you'd enable bling
- **Plugin architecture** — modular, C++ plugins. Community-developed firedecor for window decorations. Extensive customization without forking
- **INI config** — `wayfire.ini`, familiar format
- **wlroots-based** — benefits from wlroots ecosystem improvements

### Weaknesses
- **NVIDIA hybrid: broken for external monitors.** External monitors on NVIDIA discrete GPU while Intel iGPU handles primary = failure. Workaround: NVIDIA-only mode (kills battery life) or reverse-PRIME (fragile). This is a **dealbreaker for your laptop** unless you only use the internal display.
- **Zoom screen sharing: breaks after first share.** First share works, subsequent shares produce black screens. PipeWire threading errors in logs. Documented, unresolved.
- **Gamescope: avoid entirely.** Community consensus is Gamescope conflicts with Wayfire's architecture. Use Proton directly instead.
- **Input latency: ~25ms** (vs X11's ~14ms). Fine for desktop work, noticeable for competitive gaming. Your puzzle games won't care.
- **Non-systemd: reported failures.** Wayfire fails to initialize DRM backend on non-systemd systems (runit, OpenRC). This is potentially a **blocker for Artix/OpenRC**.
- **GTK rendering bugs** — occasional damage tracking failures where GTK apps don't repaint
- **Touchscreen crashes** — multi-finger swipe gestures crash the compositor
- **Smaller community** than Hyprland — fewer documented workarounds, less NVIDIA testing

### Gaming
Proton-GE with `PROTON_ENABLE_WAYLAND=1` works for most games. Avoid Gamescope. Users report "just works" for most titles without the intermediate compatibility layers. Less battle-tested than Hyprland for gaming edge cases.

### The Floating+Tiling Question
This is Wayfire's real selling point for you. The times you wish you weren't using a tiling WM — dragging a reference image next to your editor, floating a terminal over a browser, having interaction between floated and tiled things — Wayfire handles this natively because floating *is* the default. Tiling is the opt-in, not the other way around.

`★ Insight ─────────────────────────────────────`
- Wayfire's Expo is the closest thing to Gnome's overview outside of Gnome. Keyboard-navigable workspace grid, smooth transitions, integrated into the compositor. Not a third-party plugin bolted on.
- The OpenRC compatibility issue is the elephant in the room. If Wayfire can't initialize DRM on non-systemd, it's dead on arrival for Artix. This needs testing before any further evaluation.
- The "first Zoom share works, second doesn't" bug is specific and reproducible — PipeWire threading error. This is worse than Hyprland's Zoom story (which works repeatedly, just with positioning quirks).
`─────────────────────────────────────────────────`

---

## River

**Status: Architecturally fascinating.** The "separate compositor from window manager" approach is the right idea, but practical concerns remain.

### The Architecture

River splits what every other Wayland compositor combines:

| Traditional (Hyprland, Sway, etc.) | River |
|-------------------------------------|-------|
| Display server + compositor + WM = one process | Display server + compositor = River |
| | Window manager = separate process (via `river-window-management-v1` protocol) |
| | Layout generator = yet another separate process (via `river-layout-v3` protocol) |

This means:
- **You can swap window managers without restarting the compositor.** No session loss.
- **WMs can be written in any language** — shell scripts, Lua, Rust, Python, whatever speaks the Wayland protocol. No performance impact because the protocol is asynchronous (not per-frame roundtrips).
- **9+ independent WMs** developed within 6 weeks of the stable protocol release.
- Isaac Freund daily-drives a deliberately slow, garbage-collected WM on a 10-year-old ThinkPad X220 without performance issues. The architecture genuinely works.

The `river-window-management-v1` protocol is committed-stable: "we do not break window managers." This mirrors Linus's kernel ABI stability principle.

### Strengths
- **Architectural purity** — the compositor/WM separation is the correct abstraction. X11 got this right (X server vs window manager), Wayland monoliths got it wrong, River restores it.
- **Layout generators** — window arrangement is a pluggable protocol. `rivertile` (built-in) for basic tiling, or community generators for i3-style, floating, experimental layouts. Both tiling and floating possible depending on generator choice.
- **Runtime configuration** — `~/.config/river/init` is just an executable (shell script, Python, whatever). `riverctl` commands work at any time, no restart needed.
- **wlroots-based** — inherits multi-monitor, XWayland, screen sharing from wlroots
- **Zig** — memory-safe, small binary, fast compilation. Though if you care about the language (and you mentioned Zig interest for your display library project), this is noteworthy.
- **Protocol stability** — stable `river-window-management-v1`, 0.4.0 release, path to 1.0

### Weaknesses
- **NVIDIA hybrid: same wlroots challenges.** External monitors on discrete GPU, refresh rate issues on hybrid systems. Not River-specific but not solved either.
- **Zoom: untested on River specifically.** Uses `xdg-desktop-portal-wlr` for screen sharing. Likely similar to other wlroots compositors — basic monitor sharing works, window selection limited.
- **Screen sharing setup is manual.** Requires `xdg-desktop-portal` + `xdg-desktop-portal-wlr` + `xdg-desktop-portal-gtk`, plus explicit environment variable propagation in the init script. The `systemctl --user` commands in the docs are a problem for Artix/OpenRC.
- **No built-in overview/expo.** Would depend on the WM implementation providing this.
- **Smaller ecosystem** than Hyprland — fewer documented workarounds, less NVIDIA hybrid testing
- **Documentation gap** — the protocol spec is complete, but beginner-friendly docs planned for 1.0, not yet available
- **Gamescope:** should work (wlroots-based) but less tested than on Hyprland

### Gaming
XWayland supported natively. Proton-GE with `PROTON_ENABLE_WAYLAND=1` should work (same wlroots path as other compositors). Less community documentation for gaming-specific River configs than Hyprland.

### The X11 Parallel

You noted River went "all X11" in philosophy — separating compositor from WM. This is exactly right. X11's great insight was that the display server (X) and the window manager (i3, awesome, openbox) were separate processes communicating via protocol. Wayland threw this out ("the compositor IS the window manager"), and River brings it back with a modern protocol. The `river-window-management-v1` protocol is to River what ICCCM/EWMH was to X11, but designed properly from the start rather than accumulated over decades.

`★ Insight ─────────────────────────────────────`
- River's architecture is philosophically the most correct of all four. It separates concerns cleanly, enables ecosystem diversity, and proves that the "Wayland must be monolithic" assumption was wrong. Isaac Freund's blog post on this is worth reading: https://isaacfreund.com/blog/river-window-management/
- The practical question is whether "architecturally correct" translates to "best daily driver." River is younger, less tested on NVIDIA hybrid, and requires more manual setup (especially for screen sharing on OpenRC). The *idea* is right; the *ecosystem* isn't there yet.
- If Phoenix (the from-scratch X11 server in Zig) had River's compositor/WM separation *and* X11 protocol compatibility, it would be the ideal system. Both projects share the insight that compositor and WM should be separate; they just disagree on which protocol to speak.
`─────────────────────────────────────────────────`

---

## Niri

**Status: No-go.** Full evaluation at `docs/niri-evaluation.md`.

**TL;DR:** Nice ideas (scrollable tiling, overview, window blocking during screencasts) but XWayland via xwayland-satellite breaks Zoom, Gamescope crashes on NVIDIA, keyboard input latency 150-200ms on NVIDIA, VRAM leak. Not ready for NVIDIA hybrid laptop with Zoom requirement.

---

## Comparison Matrix for Jim's Use Case

Requirements: NVIDIA hybrid laptop, Artix/OpenRC, occasional Zoom, light Steam gaming (puzzles), minimal bling, values screen real-estate and instant response, sometimes wants floating windows mixed with tiled.

| Requirement | Hyprland | Wayfire | River | Niri |
|-------------|----------|---------|-------|------|
| NVIDIA hybrid | Documented, works with config | **Broken** for external monitors | wlroots-dependent, untested | VRAM leak, crashes |
| Artix/OpenRC | Needs workarounds (documented) | **May not initialize DRM** | `systemctl` in docs, needs adaptation | Unknown |
| Zoom | Works-ish (best of the four) | First share only | Untested | Broken |
| Steam/puzzles | Well-tested, Gamescope fallback | Works via Proton directly | Should work, less tested | Latency issues |
| Floating + tiled mix | Possible but tiling-first | **Native** — floating default, tile optional | Depends on WM/layout generator | Scrollable only |
| Overview/Expo | Plugin (less polished) | **Built-in, excellent** | Depends on WM | Built-in |
| Minimal bling | Full control to disable | Full control to disable | Minimal by design | Full control |
| Community/docs | **Best** | Good | Growing | Growing |

---

## Verdict

**Hyprland remains Plan A.** It's the only compositor that checks all the hard requirements: NVIDIA hybrid works (with config), Zoom works (with XWayland), Gamescope works (fallback for games), Artix/OpenRC has documented workarounds, and the community is large enough that edge cases get solved.

**Wayfire would be Plan A if:**
1. NVIDIA hybrid external monitors worked (dealbreaker)
2. It initialized on OpenRC (potential dealbreaker)
3. Zoom screen sharing didn't break after first share

The floating-first model with Expo is genuinely what you want for the "sometimes I wish I wasn't tiling" moments. If you ever move to AMD GPU or a desktop-only setup (no hybrid), Wayfire deserves another look.

**River is the long-term bet.** The architecture is right, the protocol is stable, and the ecosystem is growing. When it has: better NVIDIA hybrid docs, an Expo-capable WM, and OpenRC-friendly screen sharing setup — it could be the one. Worth watching, not ready to daily-drive on your specific hardware.

**Niri is out** for the foreseeable future on NVIDIA hardware.

## References

- [Hyprland NVIDIA wiki](https://wiki.hypr.land/Nvidia/)
- [Wayfire introduction](https://wayfire.org/2019/01/13/Introduction-to-Wayfire.html)
- [Wayfire 0.8.0 release notes](https://wayfire.org/2023/10/07/Wayfire-0-8.html)
- [River architecture blog](https://isaacfreund.com/blog/river-window-management/)
- [River GitHub](https://github.com/riverwm/river)
- [River layout generators wiki](https://github.com/riverwm/river/wiki)
- [The Register: River's WM separation](https://www.theregister.com/2026/02/11/river_wayland_with_wms/)
- [Niri evaluation](niri-evaluation.md)
- [Hyprland migration checklist](hyprland-migration.md)
