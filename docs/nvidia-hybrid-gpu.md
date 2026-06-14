# Hybrid GPU + external monitors under Hyprland (X1 Extreme Gen 5)

Date: 2026-06-14.

## The machine

ThinkPad X1 Extreme Gen 5 (21DE): **Intel Iris Xe iGPU** (drives the internal eDP panel)
+ **NVIDIA RTX 3050 Ti dGPU** (all external ports — HDMI/DP — are wired through NVIDIA).
DRM: `card1` = Intel (`pci-0000:00:02.0`), `card0` = NVIDIA (`pci-0000:01:00.0`).

## The problem

With an external monitor plugged into the NVIDIA ports, **the external monitor is
sluggish** (≈30 FPS on a 60 Hz panel, erratic frametimes) while the internal panel is
buttery-smooth at 165 Hz.

Why: Hyprland/aquamarine uses **one primary render GPU** for all compositing; other GPUs are
**scanout-only**. With Intel as primary (`AQ_DRM_DEVICES` lists it first), every frame for
the NVIDIA-attached external monitor is composited on Intel and then **copied (blitted)
across the bus to NVIDIA just to scan out**. There is no per-output render GPU in
aquamarine. The Hyprland NVIDIA wiki: *"This might slow down rendering to secondary monitors
… it's the best we can do on Nvidia."* The dGPU does no useful rendering — only scanout.

`AQ_FORCE_LINEAR_BLIT=0` (the one documented multi-GPU blit knob) is already set and does
not fix it. The penalty is structural, not a missing config line.

## The fix: go single-GPU when docked (BIOS Discrete)

The X1 Extreme Gen 5 has a **MUX**. In UEFI: **Config → Display → Graphics Device →
Discrete Graphics** disables the iGPU and routes the internal panel to the dGPU too. Now
NVIDIA is the *sole* GPU driving *both* displays → no cross-GPU copies → both monitors
smooth. This is the clean fix for docked use; the tradeoff is worse battery/heat (NVIDIA
always on) and it requires a reboot to switch (not a runtime toggle).

| Mode | BIOS | Primary GPU | Internal | External | Battery |
|---|---|---|---|---|---|
| **Mobile** | Hybrid | Intel | smooth | sluggish | best |
| **Docked** | Discrete | NVIDIA (only) | smooth | smooth | worst |

## `start-hyprland` auto-detection

`start-hyprland` now derives the GPU env from **which cards are actually present**, so the
same script works in both BIOS modes with no edits:

- **Hybrid** (Intel + NVIDIA present): `AQ_DRM_DEVICES=<intel>:<nvidia>` (Intel primary),
  `LIBVA_DRIVER_NAME=iHD`, `NVD_BACKEND=direct`, `AQ_FORCE_LINEAR_BLIT=0`.
  `GBM_BACKEND`/`__GLX_VENDOR_LIBRARY_NAME` are deliberately **omitted** (forcing NVIDIA on
  hybrid breaks Firefox/screensharing).
- **Discrete-only** (only NVIDIA present): `AQ_DRM_DEVICES=<nvidia>`, plus the NVIDIA stack
  `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `LIBVA_DRIVER_NAME=nvidia`,
  `NVD_BACKEND=direct` (safe — no Intel to conflict).
- **Intel-only** (no dGPU): just Intel.

`by-path` symlinks are used so the logic survives card-number reshuffles; an absent card
yields an empty string and is skipped.

## Recovery

`start-hyprland` is launched **manually** from a shell, so a failed launch just returns to
the shell — no login loop. Revert the script with
`git -C ~/projects/i3-screen-manager checkout start-hyprland`, or flip the BIOS back to
Hybrid.

## Notes / untried long-shots (keep Intel primary)

- `opengl { nvidia_anti_flicker = false }` — a documented fix for external-monitor FPS
  drops in some Hyprland versions; not yet tried here.
- Fullscreen **direct scanout** to a dGPU output is unreliable on NVIDIA hybrid (per NVIDIA
  dev forum) — don't rely on it.
- Related (game side): `~/projects/game-bootstrap/docs/research/2026-06-14-hybrid-gpu-external-monitor-pacing.md`
  confirms the game/renderer is healthy; this is purely a compositor multi-GPU matter.
