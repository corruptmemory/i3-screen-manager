# Laptop parity guide — Quickshell bar + tensaku screenshots

**STATUS: EXECUTED on `nomad-artix` 2026-08-29** — quickshell + hyprpicker
(rung-1) + tensaku (rung-2 GitHub-release prebuilt) installed; `shell.qml`
pools gained an eDP-1 entry (all 10 workspaces); new `Widgets/Battery.qml`
(BAT* poll, self-hides on machines without a battery); `Weather.qml`
de-hardcoded to read machine-local `~/.config/quickshell/weather-location.json`
with a Ridgewood fallback (the file lives inside the symlinked dotfiles dir
and is **gitignored**); `machine.lua` bridge flipped
`bar="quickshell"`/`screenshot="tensaku"`; waybar retired live via `pkill`.
End state: 1 qs-bar layer at y=0 (reserved 28px), zero configerrors, offline
suite still all-green from both machine branches. Doc kept as the historical
runbook + reference for the design decisions.

**For a future Claude session on `nomad-artix` (the laptop).** The 2026-08-28
desktop session (`godlike-artix`) built two things the laptop will want: a
hand-written **Quickshell bar** (replacing Waybar) and a **grim/slurp/tensaku
screenshot flow**. Everything is committed and pushed; the desktop implementation
is your reference. This doc tells you exactly what to install, what is shared
vs. machine-specific, what to adapt, and what to deliberately NOT copy.

Companion docs (read for the full story + the gotchas):
- `2026-08-28-quickshell-bar-plan.md` — the blow-by-blow bar build (13 tasks) and
  every QML gotcha hit along the way.
- `2026-08-28-hyprland-fresh-start-rebuild.md` — design + the portrait-monitor and
  dispatch fixes.

---

## What was built (desktop) and where it lives

| Thing | Files | Shared or machine-specific? |
|---|---|---|
| **Quickshell bar** (replaces Waybar) | `dotfiles/.config/quickshell/` (Theme, PollText, BarText, shell.qml, Widgets/*) | **config SHARED** (symlinked); `shell.qml` monitor-pool map is desktop-specific |
| Bar launch + restart bind | `dotfiles/.config/hypr/hyprland-desktop.lua` (autostart ~line 134, `Super+Shift+W` ~line 548) | **machine-specific** (laptop = `hyprland-laptop.lua`) |
| **Screenshot script** | `i3-screen-manager/screenshot` (symlinked to `~/.local/bin/screenshot`) | **SHARED** (no change needed) |
| Screenshot binds + tensaku/flameshot window rules | `dotfiles/.config/hypr/hyprland-desktop.lua` (Print family ~line 610; rules ~line 482-497) | **machine-specific** |

Key desktop commits to read: `dotfiles` `39cddc7`..`e3acc64` (bar + screenshots),
`i3-screen-manager` `8dca40c` (clamshell dispatch fix), `08ac46c` (screenshot script).

---

## Step 1 — Installs (respect the rungs; AUR stays off-limits)

```bash
# Bar: rung-1 official
sudo pacman -S --needed quickshell hyprpicker

# tensaku (screenshot annotator): rung-2 PREBUILT BINARY.
#   Do NOT `cargo install tensaku` — it fails on a yanked crates.io dep
#   (gl_generator -> xml-rs 0.7.0/0.7.1 yanked). The AUR pkg is off-limits.
#   The prebuilt binary sidesteps both. GTK4 + libadwaita (runtime) are already
#   present on both machines.
d=$(mktemp -d); cd "$d"
gh release download --repo jondkinney/tensaku --pattern '*x86_64.tar.gz' --dir "$d"
tar xzf *x86_64.tar.gz
install -Dm755 bin/tensaku      ~/.local/bin/tensaku
install -Dm755 bin/tensaku-edit ~/.local/bin/tensaku-edit
cp -r share/* ~/.local/share/          # desktop entry + icon + completions
update-desktop-database ~/.local/share/applications 2>/dev/null
tensaku --version    # expect 0.28.0 (or newer)
```
(See `install-paths-cheatsheet.md` — tensaku is the rung-2 worked example.)

`grim`, `slurp`, `wl-clipboard` are already present on both machines.

---

## Step 2 — Quickshell bar on the laptop

The bar CONFIG is **already there** once you pull dotfiles and symlink it
(same as the hypr config): `ln -sfn ~/projects/dotfiles/.config/quickshell ~/.config/quickshell`.
Theme, widgets, and shell.qml come over as-is. Two laptop adaptations:

**A. Per-monitor workspace pools (`shell.qml`).** shell.qml has a hardcoded map:
```lua
readonly property var pools: ({ "DP-2": [1,2,3,4,5,6], "HDMI-A-1": [7,8,9,10] })
function poolFor(name) { return pools[name] || [1,2,3,4,5] }   -- fallback
```
Those are the *desktop's* monitors. The laptop's are `eDP-1` + dynamic externals
(NVIDIA PRIME names like `HDMI-A-1`/`DP-*`). Decide:
- **Clamshell / single-panel life:** the `|| [1,2,3,4,5]` fallback already gives
  eDP-1 a sane pool — you may not need to touch it.
- **Docked with a fixed external:** add the laptop's monitor names to the map
  (e.g. `"eDP-1": [1,2,3,4,5]`, external: `[6,7,8,9,10]`), mirroring whatever
  workspace split the laptop i3 config uses.
- Since `shell.qml` is SHARED, ADD the laptop entries alongside the desktop ones
  (both machines read the same map; each only matches its own monitor names).

**B. Launch it from `hyprland-laptop.lua`.** Copy the desktop pattern:
- Autostart: replace the laptop's `waybar` launch with
  `qs -p ~/.config/quickshell` (keep `mako`); leave the waybar line commented for
  a one-line revert. (Desktop reference: `hyprland-desktop.lua` autostart block.)
- Restart bind: `Super+Shift+W` → `pkill -f '^qs '; qs -p ~/.config/quickshell`.
- Verify like the desktop did: launch `qs -p ~/.config/quickshell`, check
  `hyprctl layers` for 1 `qs-bar` surface per monitor, read the qs log for
  `Configuration Loaded` with no errors.

**QML gotchas already solved (don't rediscover them):**
- `Rectangle`/`Item` delegates in a `RowLayout` need `Layout.preferredWidth/Height`,
  NOT bare `implicitWidth/Height`, or they collapse to zero.
- `font.families` (list) is unsupported here — use single `font.family`.
- `transform` is a FINAL Item property — the PollText stdout hook is `format`.
- Icons render in an explicit `Symbols Nerd Font` (TX-02 has no nerd glyphs);
  network uses `f0200` (Waybar's `f796` is Font-Awesome-only, absent here).
- CPU% folds `iowait` into idle to match Waybar (else it floats ~3% on idle).
- `qs` caches a compile after a failed reload — restart `qs` to clear it.
- One instance per config; launch with `-n` (no-duplicate) if unsure.

**Laptop-specific bar modules to consider:** the desktop bar has no battery
(desktop). The laptop will want a **battery** widget (read `/sys/class/power_supply/BAT*/`)
— add a `Widgets/Battery.qml` PollText, same pattern as Cpu/Memory. The laptop's
old Waybar/polybar config shows what else it surfaced (brightness, etc.).

**Popouts (calendar + weather) — SHARED, but weather has a desktop hardcode.**
The bar's two popouts (`Popout.qml`, `Widgets/Calendar.qml`,
`Widgets/Weather.qml`, `Widgets/WeatherForecast.qml`, plus the `Weather {}` slot
in `shell.qml` and the clickable `Clock.qml`) all arrive with the `git pull` —
see `2026-08-28-quickshell-popouts-calendar-weather.md` for how they work.
**One laptop change is mandatory:** `Weather.qml` hardcodes Ridgewood, NJ
lat/lon, which is desktop-only. The laptop must make the location dynamic (read a
machine-local `~/.config/quickshell/weather-location` file, or geolocate) — do
NOT ship the Ridgewood hardcode. The calendar needs no laptop change (pure local
date math); its future "upcoming events" pane is meant to come from
`~/projects/life-dashboard/`'s local JSON, not a bar-local cache.

**Tray context menus — SHARED, nothing to do.** `Tray.qml` now opens the SNI
context menu on right-click (`display()`; left = activate, middle = secondary),
which is the only way to fully quit apps like Discord. It arrives with the pull
and works as-is on the laptop (the shell already declares `//@ pragma
UseQApplication`, the requirement for platform menus).

**Per-monitor compact bar — SHARED, auto-applies.** `shell.qml` now gives each
bar a `compact` flag (`modelData.height > modelData.width`): on a **portrait**
panel the right-side system cluster (weather/audio/net/cpu/mem/temp/idle) is
hidden, leaving only workspaces + window title (left), clock (center), and tray
(right) — so nothing collides with the centered clock on a narrow panel. It keys
on orientation, not monitor name, so any portrait external the laptop drives gets
the reduced bar automatically — nothing to configure. Landscape panels keep the
full cluster.

Also note: **`morgen` was removed fleet-wide** (2026-08-29) — the laptop no longer
autostarts it and `morgen-bin` is uninstalled; don't expect a morgen window rule
or `Super+m`.

---

## Step 3 — Screenshot flow on the laptop

The `screenshot` script is SHARED (symlink `~/.local/bin/screenshot` →
`i3-screen-manager/screenshot`) — no change. Just:
- Install `tensaku` + `hyprpicker` (Step 1).
- Port the Print-family binds into `hyprland-laptop.lua` (copy the block from
  `hyprland-desktop.lua`): `Print`=flameshot (primary — FLIPPED 2026-08-29), `Super+Print`=region+annotate,
  `Shift+Print`=full+annotate, `Ctrl+Print`=region copy-only,
  `Super+Ctrl+Print`=annotate clipboard.
- Add the **tensaku float rule**: `hl.window_rule({ match = { class =
  "^(dev\\.tensaku\\.Tensaku)$" }, float = true, center = true })`.
- If the laptop keeps flameshot, mirror the centered-float rule fix too
  (`float + center`, not `fullscreen` — fullscreen was too big for the picker).

---

## Step 4 — Do NOT copy these to the laptop (desktop-only)

- **nm-applet drop.** The desktop dropped `nm-applet` (wired eth0). **The laptop
  NEEDS nm-applet (wifi)** — leave its launch in `hyprland-laptop.lua` intact.
- **Portrait `transform=3` + `vrr=0` on HDMI-A-1.** Desktop-only hardware (the
  pivoted PA248QV). The laptop has no such panel.
- **Per-monitor workspace confinement DP-2=1-6 / HDMI-A-1=7-10.** Desktop
  dual-head. The laptop's external is dynamic — pick a laptop-appropriate scheme
  (or none) if you want confinement there.

## Step 5 — Already applies to both (no action needed)

- **`i3-screen-manager` clamshell dispatch fix** (`hl.dsp.workspace.move`, replacing
  the Lua-mode-dead `moveworkspacetomonitor` string). The script is shared, so the
  laptop's clamshell/disconnect workspace migration is already fixed once it pulls.
