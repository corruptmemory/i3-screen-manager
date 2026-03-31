# Niri Evaluation: Plan B to Hyprland

Research date: 2026-03-31

**Verdict: No-go** for current use case. Documented here for future reference.

## What Niri Gets Right

- **Scrollable tiling** — genuinely interesting paradigm, infinite horizontal workspace
- **Overview feature** — the Gnome killer feature, done well
- **Screencasting infrastructure** — xdg-desktop-portal-gnome + PipeWire works great (OBS, Firefox, Telegram all share fine)
- **Window blocking** — can replace sensitive windows (password managers) with black rectangles during screencasts
- **Dynamic cast targets** — change what you're sharing without restarting the screencast
- **Self-hosting simplicity** — Rust binary, clean design
- **Privacy-first** — window rules to protect content during screen sharing

## Why It's a No-Go

### 1. Zoom: The XWayland-Satellite Problem

Niri doesn't have native XWayland — it delegates to `xwayland-satellite`, a separate tool. This creates a fundamental problem for Zoom:

Zoom's UI assumes it can float toolbars, reposition mini-windows, and pop up participant thumbnails. On X11, apps position windows wherever they want. On Wayland, the compositor owns positioning. So Zoom in xwayland-satellite gets the worst of both worlds: it *thinks* it's on X11 but xwayland-satellite maps into Niri's model. Toolbar gets tiled, mini-window gets swallowed, participant strip goes missing.

**Workarounds exist but are compromises:**
- Zoom web app in Firefox works (Wayland-native), but reduced features
- `xwayland=false` + `enableWaylandShare=true` in `~/.config/zoomus.conf` + manually set PipeWire mode in Zoom settings — forces Zoom into Wayland mode, but `ZoomWebviewHost` may crash, and results are inconsistent
- `xwaylandvideobridge` (KDE's bridge) — stop-gap with explicit permission prompts

By contrast, Hyprland has native XWayland integration. Zoom "works-ish" — not perfect, but the floating toolbar and window positioning at least function.

### 2. Gaming: NVIDIA Issues

| Issue | Severity |
|-------|----------|
| Keyboard input latency 150-200ms (reported on NVIDIA) | Severe — fast-paced games unplayable |
| NVIDIA VRAM leak (doesn't release after app close) | Moderate — needs `GLVidHeapReuseRatio 0` workaround |
| Gamescope core dumps on NVIDIA | Blocker — removes major gaming workaround |
| Multi-monitor input routing (mouse/keyboard to wrong display) | Moderate |
| Can't disable triple buffering (Hyprland can) | Contributes to latency |
| Gamepad/SDL incomplete overlap with Wayland backend | Low for keyboard/mouse gamers |

The Gamescope crash on NVIDIA is particularly bad — it's the standard escape hatch for problematic games, and it's broken on Niri.

### 3. Maturity Gap

- Niri is younger with a smaller community than Hyprland
- Fewer documented workarounds for edge cases
- NVIDIA hybrid (Intel+NVIDIA) less tested than on Hyprland
- Must launch via `niri-session` (not bare `niri`) or portals don't initialize — easy to get wrong

## Configuration Notes (for future reference if revisiting)

### Portal setup (required for screen sharing)
```
xdg-desktop-portal + xdg-desktop-portal-gnome + PipeWire + WirePlumber
```
Must use `niri-session` launcher, not bare `niri`.

Portal config at `/usr/local/share/xdg-desktop-portal/niri-portals.conf` — must specify gnome backend for screenshot/screencast.

### NVIDIA VRAM workaround
Set `GLVidHeapReuseRatio 0` as NVIDIA profile for Niri process. Reduces initial VRAM footprint from ~1 GB to ~75 MB.

### Hybrid GPU
Set `debug.render-drm-device` in niri config if screen capture shows black frames on multi-GPU systems.

## When to Revisit

- If NVIDIA fixes the VRAM leak in a driver update
- If Gamescope stops crashing on NVIDIA + Niri
- If the keyboard latency issue gets resolved
- If Zoom ships native Wayland support (don't hold your breath)
- If xwayland-satellite matures to handle Zoom's window positioning model

## References

- [Niri GitHub](https://github.com/niri-wm/niri)
- [Niri screencasting docs](https://niri-wm.github.io/niri/Screencasting.html)
- [Niri NVIDIA wiki](https://github.com/YaLTeR/niri/wiki/Nvidia)
- [xwayland-satellite Zoom issue](https://github.com/Supreeeme/xwayland-satellite/issues/297)
- [Niri screen sharing discussion](https://github.com/niri-wm/niri/discussions/1453)
- [KDE xwaylandvideobridge](https://github.com/KDE/xwaylandvideobridge)
- [Niri gaming input latency](https://github.com/niri-wm/niri/discussions/3176)
- [NVIDIA VRAM bug analysis](https://nickjanetakis.com/blog/gpu-memory-allocation-bugs-with-nvidia-on-linux-and-wayland-adventures)
