# i3-screen-manager

Bash scripts for managing external displays, mouse settings, lid/clamshell behavior,
keyboard layout, and Hyprland session bring-up. Project originated as an i3/X11
toolkit; both machines migrated to Hyprland/Wayland in 2026-Q2. Script names
retain the `i3-` prefix deliberately — they're invoked everywhere by muscle
memory and from rofi menus, so changing the names would cost more than the
labels are worth.

## Environment

- **Distro:** Artix Linux (OpenRC, both machines). Both were originally Arch.
- **Compositor:** Hyprland on Wayland. Originally i3 on X11.
- **Package manager:** `yay` (AUR wrapper around pacman). Both Arch and Artix packages work.
- **Privileges:** `sudo` is available from the user account.
- **Machines:** `nomad-artix` (ThinkPad X1 Extreme Gen 5 laptop), `godlike-artix` (desktop).

## Migration history

The big migration runbooks live under `docs/`. Read them when working on
anything compositor- or tooling-adjacent:

- `docs/hyprland-migration.md` — initial i3/X11 → Hyprland/Wayland migration
  (laptop, on Artix). Phase-by-phase. Captures startup, env, NVIDIA hybrid,
  Waybar replacement of Polybar, the i3-screen-manager rewrite from xrandr to
  hyprctl/wlr-randr.
- `docs/desktop-artix-hyprland-migration.md` — desktop equivalent (pure AMD,
  no NVIDIA, no laptop-specific concerns).
- `docs/hyprland-lua-migration.md` — Hyprland 0.55+ hyprlang → Lua config
  migration. Both machines on Lua now. Includes Hyprland-side gotchas and the
  open waybar #5008 regression.
- `docs/artix-laptop-setup.md` — first-boot install/setup notes for the laptop.
- `docs/hyprland-first-boot.md` — Hyprland-specific first-boot checklist.
- `docs/claude-code-aur-to-native-migration.md` — switching Claude Code itself
  off the AUR `claude-code` package onto Anthropic's native installer
  (auto-updates, no more AUR exposure). Done on `godlike-artix` (2026-06-15);
  **`nomad-artix` (laptop) still pending** — read before doing it there. Key
  gotcha: the native install must be finalized from a clean terminal, *not*
  from inside a Claude Code session.

**IceWM is now the active X11 alternative on both machines.** PekWM was tried
on the desktop and **declared over** (verdict: PekWM oddities read as bugs;
IceWM noticeably more responsive and stable) — left installed and toggleable
on the desktop but no longer the recommendation, and **not replicated to the
laptop**. The full WM rotation:

- **`godlike-artix` (desktop):** Hyprland (Wayland) · IceWM (X11, daily) · PekWM (X11, deprecated)
- **`nomad-artix` (laptop):** Hyprland (Wayland) · IceWM (X11, scaffolded 2026-06-17 — pending first TTY-boot validation)

Docs:

- `docs/2026-06-15-x11-wm-research.md` — the "why PekWM" survey of living X11 WMs.
- `docs/2026-06-15-pekwm-x11-setup.md` (+ `…-plan.md`) — PekWM-on-XLibre on
  `godlike-artix`. **Trial over; setup retained but deprecated.** Config lives
  in dotfiles (`.pekwm-desktop/`, `polybar/config-pekwm.ini`,
  `.xinitrc-desktop`, `.local/bin/start-pekwm`).
- `docs/2026-06-16-icewm-x11-setup.md` (+ `…-plan.md`) — **IceWM 4.0-on-XLibre
  on the desktop** (`start-icewm`). Native taskbar (no Polybar), `icesh` control
  CLI. Border quirk: IceWM color-computes a Win95 bevel on every `Look`, so
  a uniform border isn't achievable — settled on 2px beveled cyan/slate.
  Config: `dotfiles/.icewm/`, `dotfiles/.xinitrc-icewm`,
  `dotfiles/.local/bin/start-icewm`.
- `docs/2026-06-17-icewm-laptop-setup.md` — **IceWM on the laptop**
  (`start-icewm-laptop`). Mirrors the desktop setup with hardware deltas:
  NVIDIA PRIME via `xorg.conf.d/10-nvidia-prime.conf` (Intel modesetting
  primary, NVIDIA secondary, externals bound via
  `xrandr --setprovideroutputsource`), touchpad config, brightness keys,
  battery widget. Config: `dotfiles/.icewm-laptop/`,
  `dotfiles/.xinitrc-icewm-laptop`, `dotfiles/.local/bin/start-icewm-laptop`.
  IceWM picks up the laptop config via `ICEWM_PRIVCFG` (no `~/.icewm`
  symlink needed).

All additive and reversible — Hyprland, IceWM, and PekWM are installed and
toggleable from a TTY on the desktop; nothing was removed. The laptop has
Hyprland + IceWM only (no PekWM — trial declared over before reaching here).

## Architecture

Scripts, no build step. All committed in this repo and symlinked from
`~/.local/bin/`:

**Display & input management (compositor-aware — Wayland AND X11):**
- `i3-screen-manager` — CLI for display layout (extend/clamshell/mirror/disconnect/scale/status). Dispatches internally on `$XDG_SESSION_TYPE`: Wayland uses `hyprctl dispatch 'hl.monitor({...})'` (Lua-mode-safe); X11 uses `xrandr`. Single source of truth; same UX both ways. (Until 2026-06-17 this was Hyprland-only and silently broken under Hyprland 0.55+ Lua mode.)
- `i3-screen-rofi` — Rofi menu frontend that calls `i3-screen-manager` (compositor-agnostic)
- `i3-keyboard-rofi` — Rofi toggle for laptop (Caps→Ctrl) vs external keyboard. Dispatches on `$XDG_SESSION_TYPE`: Wayland → `hyprctl keyword input:kb_options`; X11 → `setxkbmap -option`. Same UX both ways.
- `i3-mouse-setup` — Login-time script that applies saved mouse DPI via `solaar`. Compositor-agnostic (HID-level).
- `i3-mouse-rofi` — Rofi menu for mouse DPI adjustment (saves choice for persistence). Compositor-agnostic.
- `i3-cmos-battery` — CMOS battery voltage monitor (CLI + waybar output, formerly polybar)

**Hyprland session bring-up & maintenance:**
- `start-hyprland` — Hyprland session launcher: env, gnome-keyring, ssh-agent at predictable socket, NVIDIA hybrid `AQ_DRM_DEVICES`, `exec /usr/bin/start-hyprland`
- `laptop-monitor.sh` — Hyprland lid-switch handler; checks the clamshell inhibitor PID before re-enabling eDP-1
- `laptop-monitor-x11.sh` — X11/IceWM sibling of `laptop-monitor.sh`. **Not auto-wired** (no acpid hook by default); see `docs/2026-06-17-icewm-laptop-setup.md` for the manual-trigger pattern and the acpid wiring recipe.
- `hyprland-clamshell-restore` — Re-applies clamshell eDP-1 disable after every Hyprland config reload (wired via `hl.on("config.reloaded")` under Lua, or `exec=` under hyprlang)
- `screenshot.sh` — hyprshot + satty screenshot workflow (alternative path; main flow is flameshot via `Print`)
- `flameshot.sh` — flameshot wrapper with `QT_SCREEN_SCALE_FACTORS="1;1"` for correct DPI
- `volumecontrol.sh` — pavucontrol wrapper that forces Intel Vulkan ICD to avoid NVIDIA VA-API conflicts

**System maintenance & security:**
- `aur-malware-check` — Read-only audit of installed packages against the June 2026 "Atomic" AUR supply-chain denylist. Name intersection by default; `--deep` adds a pacman-scriptlet + filesystem IOC scan, `--near` flags confusable look-alikes (you have the safe name, a malicious twin exists), `--all` widens to every installed package, `--list`/`--url` override the source. Downloads + caches the denylist (offline fallback); exit `0`/`1`/`2` = clean/exposed/error, so it drops into a login hook or `&&` chain.

## Key Design Decisions

- **Internal display is hardcoded as `eDP-1`** — standard for modern Intel laptop panels.
- **External display is auto-detected** — `wlr-randr` (not `hyprctl monitors -j`) because hyprctl drops disabled outputs while wlr-randr sees all physically connected ones.
- **Lid state path is discovered dynamically** — ACPI names vary (`LID`, `LID0`, etc.) across boots.
- **Safe defaults** — if lid state can't be detected, assume closed (refuse disconnect rather than risk black screen).
- **Clamshell uses `elogind-inhibit`** — `elogind` is Artix's logind. Holds a `handle-lid-switch` block lock via a background `sleep infinity` process, PID tracked in `/tmp/i3-screen-manager-inhibit.pid`. (Pre-Artix this used `systemd-inhibit` with identical flags.)
- **`hyprctl keyword monitor X,disable` is unreliable** — known Hyprland issue where disable can leave a phantom monitor. Always follow with `wlr-randr --output X --off` to cut the physical DRM output.
- **`moveworkspacetomonitor` silently no-ops on disabled monitors** — when entering clamshell, enable the external first (at `auto` position) before moving workspaces, then disable eDP-1.
- **Disconnect enables internal BEFORE disabling external** — no window where zero displays are active. Internal goes up at `auto` first to avoid overlap warnings, then external goes down, then internal repositions to `0x0`.
- **Scale instead of `Xft.dpi`** — Wayland uses output scaling. `i3-screen-manager scale` calls `hyprctl keyword monitor "$target,preferred,auto,$scale"` with a rofi picker of 0.75/1.00/1.25/1.50/1.75/2.00. The old `Xft.dpi` knob is gone — there is no X resource database.
- **Mouse DPI via solaar** — `i3-mouse-setup` auto-detects Logitech mice at login and applies saved DPI from `~/.config/i3-mouse-manager/dpi`. `i3-mouse-rofi` provides on-the-fly adjustment that persists across reboots.
- **CMOS battery monitoring** — `i3-cmos-battery` reads Vbat from the it87 Super I/O chip. Requires `it87` kernel module (auto-loaded via `/etc/modules-load.d/it87.conf`). Refreshes every 6 hours. Exits silently on machines without the sensor (laptops).
- **Clamshell survives Hyprland config reload** — the `hyprland-clamshell-restore` script is wired into Hyprland (via `exec=` under hyprlang or `hl.on("config.reloaded")` under Lua) so saving the config file doesn't wake eDP-1 back up.
- **`aur-malware-check` is a standalone tenant** — it has nothing to do with displays. It lives here because this repo is the home for the machine's hand-rolled bash scripts and it follows the same "commit here, symlink from `~/.local/bin/`" convention. It has no dependency on the rest of the toolkit and can be lifted out at any time.

## Testing

No automated tests. Test manually with an external monitor:

1. `i3-screen-manager extend-right` — external should light up to the right of internal.
2. `i3-screen-manager mirror` — both screens same content.
3. `i3-screen-manager clamshell` — internal off, external only. Close lid safely.
4. `i3-screen-manager disconnect` (lid closed) — should refuse with an explanatory message.
5. Open lid, `i3-screen-manager disconnect` — should restore internal display.
6. `i3-screen-manager scale` — rofi picker should appear, selecting a value changes the output scale.
7. `i3-screen-manager scale 1.5 eDP-1` — direct scale set, bypasses the picker.
8. `i3-screen-manager status` — should show internal/external, active monitors with pos/scale, and inhibitor state.

## Common Issues

### Hyprland / Wayland

- **`hyprctl keyword monitor` is dead under Lua mode (Hyprland 0.55+)** — returns "keyword can't work with non-legacy parsers. Use eval." The dual-compositor refactor of `i3-screen-manager` (2026-06-17) replaced it with `hyprctl dispatch 'hl.monitor({...})'`. The dispatch wrapper itself errors ("hl.dispatch: expected a dispatcher") but the `hl.monitor()` side effect runs first — verified during the 75Hz experiment 2026-06-13 and the `i3-screen-manager disconnect` smoke test 2026-06-17. The `hl_apply` helper quiets the wrapper error and accepts the side effect.
- **Black screen on disconnect**: lid was closed and eDP-1 couldn't activate. The lid guard prevents this.
- **External not detected**: `wlr-randr` should see it. NVIDIA outputs follow `*-N-N` naming (e.g. `HDMI-1-0`, `DP-1-0`).
- **Phantom monitor after clamshell**: `hl.monitor disabled=true` is unreliable like the hyprlang `keyword monitor X,disable` it replaced. Always paired with `wlr-randr --output X --off` in the scripts. If it ever recurs, rerun `i3-screen-manager clamshell`.
- **Waybar workspace clicks do nothing under Lua mode**: known regression — waybar #5008. Hyprland 0.55+ tries to evaluate the IPC dispatch string as Lua, and waybar's old-style `dispatch workspace N` is not valid Lua. Workaround: `Super+N` keyboard shortcut (works), or mouse-wheel on the bar (works via configured `on-scroll-*`). See `docs/hyprland-lua-migration.md` § "Waybar workspace click regression".
- **GTK file dialog hangs 25 seconds**: `gvfsd-trash` D-Bus backend times out. Root fix: remove `gvfs` entirely (`sudo pacman -R gvfs evince`) and use `xreader` instead of evince. Keep `export GIO_USE_VFS=local` in `start-hyprland` as a safety net. Diagnose with `time gio info trash:///` (slow) vs `time GIO_USE_VFS=local gio info trash:///` (instant).

### X11 / IceWM (laptop-specific)

- **NVIDIA PRIME provider not yet bound**: external monitors don't appear in `xrandr --query` until `xrandr --setprovideroutputsource modesetting NVIDIA-G0` runs. The xinitrc-icewm-laptop fires it at session start; `i3-screen-manager`'s X11 path fires it again before any external operation (`ensure_nvidia_provider_x11`) as belt-and-suspenders. Sources disagree on the argument order (`provider source` vs `modesetting NVIDIA-*`), so the helper tries four orderings silently.
- **Scale under X11**: no Wayland-style per-output fractional scaling. `i3-screen-manager scale` under X11 applies a server-wide `Xft.dpi` via `xrdb -merge`, which only affects newly-launched apps (existing apps don't redraw). Different model from Hyprland's hot-applied scale.
- **Lid handling is manual under IceWM**: no native lid binding; auto-handling would require `acpid` + a script that crosses the root-to-user boundary. The current plan: enter clamshell explicitly via `i3-screen-rofi → Clamshell`. The `elogind-inhibit` inhibitor works under both compositors and prevents suspend on lid close. See `docs/2026-06-17-icewm-laptop-setup.md` § "Lid handling, deferred".

### Hardware / kernel

- **Mouse poll rate config ignored**: on the stock kernel, `usbhid` is built-in (not a module), so `/etc/modprobe.d/` has no effect. Use `usbhid.mousepoll=1` in GRUB's `GRUB_CMDLINE_LINUX_DEFAULT` and `grub-mkconfig -o /boot/grub/grub.cfg`.

### X11 historical (now mostly moot)

These bit us under i3/X11 and are kept here only because they document past pain
that could resurface if X11 is ever re-introduced (e.g. via an X11 app under
XWayland, or rollback).

- **`xorg.conf.d TargetRefresh` ignored**: the `TargetRefresh` monitor option doesn't work reliably (e.g. amdgpu). Use explicit `xrandr --rate` in `~/.xinitrc` instead.
- **xlibre-xserver 25.0.0.21 vblank regression (2026-02-22)**: 20→21 caused X lockup (`modeset(0): failed to queue next vblank event`). Userspace X server bug, NOT the desktop's PCIe/GPU hardware issue. Downgrade cached at `/var/cache/pacman/pkg/xlibre-xserver-25.0.0.20-1-x86_64.pkg.tar.zst`. No longer relevant under Hyprland but listed in case of X11 fallback.
- **Workspace move errors via `i3-msg`**: `"No output matched"` was usually harmless — workspace was already on the target output. (`i3-msg` no longer used; Hyprland uses `hyprctl dispatch moveworkspacetomonitor`.)
