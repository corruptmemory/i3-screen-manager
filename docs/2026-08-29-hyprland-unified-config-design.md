# Hyprland single adaptive config — design spec (2026-08-29)

**Status:** EXECUTED on `godlike-artix` 2026-08-29 (desktop cold-boot verified —
zero config errors, monitors/pins/binds/autostart all correct via the unified
config). Laptop (`nomad-artix`) cutover pending — see §10.
**Repos touched:** `dotfiles` (the config), `i3-screen-manager` (this doc).
**Goal:** collapse `hyprland-desktop.lua` + `hyprland-laptop.lua` into ONE adaptive
Lua config that detects the machine at load time and branches, so every shared
change lands on both machines automatically and the two copies stop drifting.

---

## 1. Motivation

Today each machine symlinks `~/.config/hypr/hyprland.lua` to a per-machine file
(`hyprland-desktop.lua` / `hyprland-laptop.lua`). The two files are ~645 / ~600
lines, ~90% identical (120 `hl.*` calls each), but they have **drifted**: the
laptop copy was last touched 2026-07-19 while the desktop absorbed 40 days of
solo work (Quickshell bar, screenshot flow, screen-share rule, ws10 chat pin).
Every desktop-only improvement is a silent laptop regression-in-waiting.

Because the Hyprland config is Lua, we can detect the machine and branch in one
file. This spec defines that structure.

## 2. Runtime facts (verified against Hyprland v0.56.1 source + offline proof)

These are load-bearing and were confirmed from
`src/config/lua/ConfigManager.cpp` (not folklore):

1. **Full Lua stdlib is available.** `reinitLuaState()` calls
   `luaL_newstate()` + `luaL_openlibs()`; the protected stdlib list includes
   `io`, `os`, `package`. So `io.open`, `io.popen`, `os.getenv`, `require` all work.
2. **The config directory is auto-prepended to `package.path`** as
   `<configdir>/?.lua;<configdir>/?/init.lua`. `require("machine")` resolves
   `~/.config/hypr/machine.lua` with **zero** bootstrap. Directory modules
   (`machine/init.lua`) also work.
3. **`hyprctl reload` re-executes user modules automatically** — reload clears
   `package.loaded` (except stdlib) and then builds a **fresh `lua_State`**. No
   manual `package.loaded` clearing is needed (unlike Omarchy's `bootstrap.lua`).
4. **The config runs TWICE per reload** — a syntax-check pass on the old state,
   then the real pass on the fresh state. => detection must be **cheap and
   side-effect-free** (a `/etc/hostname` read is ideal; never launch or mutate in
   the detection path).
5. **A syntax error keeps the OLD config** (phase-1 gate). => migration is
   low-risk; a typo in a half-built module cannot brick a live session.
6. **`hl.exec_cmd` returns `nil`** (fire-and-forget). => detection reads **stdout
   from `io.popen`**, never an `os.execute` exit code (Hyprland reaps its own
   children, so exit status is unreliable — a gotcha Omarchy documents).

Detection was proven end-to-end on `lua5.4` and `luajit`: a `machine.lua` that
reads `/etc/hostname`, looks it up in a host table with a safe default, and
returns the record; `require` caches it (single execution per state).

## 3. Detection mechanism (DECIDED: nominal / hostname)

`machine.lua` reads `/etc/hostname` (no subprocess; fast), falling back to
`io.popen("uname -n")`. It maps the hostname to a machine record via a table,
with a safe default for an unknown host (assume desktop layout + a visible
warning via `hl` error/print, never a hard failure).

Rationale for nominal over structural: there are exactly two named machines, the
monitor layouts are keyed to machine-specific output names anyway (`DP-2`,
`HDMI-A-1`, `eDP-1`), and hostname is the most explicit/debuggable signal
("which am I?" -> `cat /etc/hostname`). Structural signals (chassis type,
`/sys/class/power_supply/BAT*`) remain available as a future refinement but are
not used now.

## 4. `machine.lua` — the hybrid record

`machine.lua` returns ONE table. Genuinely tabular data (the static monitor
layout, the location) lives as data; imperative deltas are decided by modules
branching on **capability traits** — the durable desktop/laptop axis (hardware
capabilities), not the transient app-rule noise that converges away over time.

```lua
-- machine.lua  (shape; exact values finalized in the plan)
local function read_hostname()
  local override = rawget(_G, "HYPR_MACHINE_OVERRIDE")   -- test/debug hook; unset in normal use
  if type(override) == "string" and #override > 0 then return override end
  local f = io.open("/etc/hostname", "r")
  if f then local h = f:read("*l"); f:close(); if h and #h > 0 then return h end end
  local p = io.popen("uname -n")                          -- stdout, never os.execute exit code
  if p then local h = p:read("*l"); p:close(); if h and #h > 0 then return h end end
  return "unknown"
end

-- traits = STATIC hardware capabilities (the durable axis). Modules branch on the
-- capability, not the type: "brightness because backlight", "touchpad because
-- trackpad", "nm-applet because wifi".
local HOSTS = {
  ["godlike-artix"] = {
    type = "desktop",
    traits = {
      displays = "static", clamshell = false, battery = false,
      trackpad = false, backlight = false, wifi = false, audio_openrc = false,
    },
    location = { name = "Ridgewood, NJ", lat = 40.9793, lon = -74.1165, tz = "America/New_York" },
    fileManager = "pcmanfm",
    bar = "quickshell", screenshot = "tensaku",   -- tool selectors (the compatibility bridge)
    monitors = {
      list = {
        -- catch-all first, then explicit (order preserved on apply)
        { output = "",         mode = "preferred",       position = "auto",   scale = 1 },
        { output = "DP-2",     mode = "2560x1440@74.97", position = "0x240",  scale = 1,
          workspaces = { 1, 2, 3, 4, 5, 6 }, default_ws = 1 },
        { output = "HDMI-A-1", mode = "1920x1200@74.93", position = "2560x0", scale = 1,
          transform = 3, vrr = 0, workspaces = { 7, 8, 9, 10 }, default_ws = 7 },
      },
    },
  },
  ["nomad-artix"] = {
    type = "laptop",
    traits = {
      displays = "dynamic", clamshell = true, battery = true,
      trackpad = true, backlight = true, wifi = true, audio_openrc = true,
    },
    -- seeded to home; laptop location goes dynamic in the weather-parity effort
    location = { name = "Ridgewood, NJ", lat = 40.9793, lon = -74.1165, tz = "America/New_York" },
    fileManager = "nautilus",
    -- bridge: laptop rides waybar/flameshot until parity; flip these to graduate it
    bar = "waybar", screenshot = "flameshot",
    monitors = {   -- externals owned by i3-screen-manager at runtime; no numbered pins
      internal = { output = "eDP-1", mode = "preferred", position = "auto", scale = 1.25 },
    },
  },
}

local name = read_hostname()
local m = HOSTS[name] or {
  type = "desktop", unknown = true,
  traits = { displays = "static", clamshell = false, battery = false,
             trackpad = false, backlight = false, wifi = false, audio_openrc = false },
  location = { name = "unknown" },
  fileManager = "pcmanfm", bar = "quickshell", screenshot = "tensaku",
  monitors = { list = {} },
}
m.name = name
return m
```

Notes:
- `traits` are STATIC hardware facts (has-a-battery), NOT runtime state. "On
  battery vs AC" and "a mouse is currently plugged in" change during a session and
  stay with the tools that own them (hypridle's AC check, the clamshell inhibitor +
  i3-screen-manager, a future trackpad-on-mouse input watcher). `machine.lua`
  enables the *wiring* (`traits.battery = true`); whether it *acts* is a runtime
  decision made elsewhere.
- Modules key on the capability: `traits.audio_openrc` (launch the pipewire trio or
  not), `traits.wifi` (nm-applet), `traits.backlight` (brightness keys),
  `traits.trackpad` (touchpad config), `traits.clamshell` (reload restore hook),
  `traits.displays` (static list vs dynamic internal).
- **Tools in transition are selector fields, not `type` branches — the "compatibility
  bridge".** `bar` (`"quickshell"`/`"waybar"`) and `screenshot` (`"tensaku"`/`"flameshot"`)
  are explicit fields so the config supports BOTH during the migration; the laptop
  graduates by flipping one value (no branch-logic edit). Today: laptop `bar="waybar"`,
  `screenshot="flameshot"`; desktop already `"quickshell"`/`"tensaku"`. Residual
  profile/app choices with no active transition (env set, morgen, tailscale bind) stay
  on the coarse `type`.
- `location` is the SSOT seed for weather/timezone — the natural home for the
  Quickshell weather Ridgewood hardcode when it goes dynamic. No Hyprland-config
  module consumes it yet; it exists so the eventual Lua->JSON emit seam has a source.
- The `monitors` table is the single source of truth for BOTH the `hl.monitor`
  calls and the workspace->monitor pins (`workspaces`/`default_ws`), killing the
  duplication between the monitor block and the old `for i=1,10` pin loop.
- A future third machine is a new `HOSTS` row. A future capability is a new
  `traits` field consumed by one module.

## 5. Module layout (~8 files, light entry)

`~/.config/hypr` becomes a whole-directory symlink to
`dotfiles/.config/hypr/`. The entry `hyprland.lua` only orchestrates:

```
dotfiles/.config/hypr/
  hyprland.lua    -- ENTRY (light): local m = require("machine"); then require the rest in order
  machine.lua     -- detection + hybrid record (section 4)
  monitors.lua    -- consumes m.monitors: static list (+ workspace pins) OR dynamic internal
  envs.lua        -- shared env; small branches (x11-fallback / cursor / _JAVA per machine)
  autostart.lua   -- shared execs + branches: audio trio (not traits.audio_openrc), nm-applet (traits.wifi),
                  --   clamshell restore hook (traits.clamshell), morgen/bar (residual type branch)
  bindings.lua    -- shared binds + branches: brightness (traits.backlight), tailscale (type residual)
  rules.lua       -- window rules (shared) + special-workspace rules
  looknfeel.lua   -- hl.config aesthetic sections (general/decoration/animations/misc/group/dwindle/master/input)
                  --   input touchpad block guarded on traits.trackpad
```

Ordering in `hyprland.lua`: `machine` -> `envs` -> `monitors` ->
`looknfeel` -> `rules` -> `autostart` -> `bindings` (env before anything that
reads it; autostart late so it runs after config is defined). Exact order pinned
in the plan.

How modules see `m`: the entry passes it explicitly where practical, or
`machine.lua` returns a cached table each module `require`s (same table within a
state — proven). The plan picks one; explicit-return-and-require is preferred over
a mutable global (the fresh-state-per-reload model makes a global safe, but
explicit is clearer and matches the "explicit > implicit" house style).

## 6. Reconciliation policy (the real work)

Unification is NOT a mechanical extract — the env and autostart sections have
genuinely diverged. Every drifted line gets one of three dispositions, decided
during implementation:

- **shared** — applies to both; lives in the shared module body. (Default.)
- **per-machine** — a real hardware/OS difference; lives behind an
  `if m.traits.X` (or a residual `if m.type == …`) branch. Examples: audio trio, nm-applet,
  brightness binds, touchpad, clamshell hook, eDP-1 scale, portrait transform,
  the intentional `_JAVA_AWT_WM_NONREPARENTING` 0-vs-1.
- **stale** — drift to be brought current, applying the newer value to both.
  Examples (machine-agnostic, safe to converge now): the laptop missing the
  screen-share rule, the tensaku float rule, the ws10 chat pin — all arrive via the
  unioned `rules.lua`. (The bar and the screenshot *tool* are handled by the
  selector-field bridge above — supported both ways, flipped when the laptop is
  ready — not force-converged in this pass.)

Net effect: the laptop inherits the desktop's shared improvements immediately and
stays current thereafter. The plan will present the drifted lines as an explicit
checklist so the disposition of each is a recorded decision, not a silent merge.

### Known machine deltas (complete map)

| Concern | Desktop | Laptop |
|---|---|---|
| Monitors | static dual-head DP-2 + portrait HDMI-A-1 (transform 3, vrr 0) | eDP-1 scale 1.25 + dynamic externals |
| WS->monitor pins | `for i=1,10` DP-2(1-6)/HDMI-A-1(7-10) | none (dynamic) |
| Audio autostart | pipewire/wireplumber/pipewire-pulse | none (OpenRC user services) |
| nm-applet | no (wired) | yes (wifi) |
| Bar | `bar="quickshell"` | `bar="waybar"` (selector-field bridge; flip to graduate) |
| Screenshot tool | `screenshot="tensaku"` | `screenshot="flameshot"` (bridge; flip to graduate) |
| morgen autostart | no | yes |
| Clamshell restore hook | no | yes (`config.reloaded`) |
| Touchpad input | no | `natural_scroll` |
| Brightness binds | no | `XF86MonBrightness` -> brightnessctl |
| Tailscale bind | no | `Super+Shift+N` -> i3-tailscale-rofi |
| Env deltas | `GIO_USE_VFS`, `MOZ_DBUS_REMOTE`, XDG session vars, `_JAVA=0` | HYPRCURSOR_SIZE, x11 fallback, OZONE/CHROMIUM flags, XCompose, `_JAVA=1` |
| fileManager var | pcmanfm | nautilus |

NVIDIA is **not** a config delta — it lives in `start-hyprland`.

### Post-execution simplification (2026-08-29)

A cleanup pass right after the cutover (recorded so the delta map stays accurate):
- **morgen removed entirely** — window rule, `special:morgen` ws-rule, `Super+m`
  bind, and the laptop autostart are gone; `morgen-bin` uninstalled.
- **zoom taken off its special workspace** — it now just floats on whatever
  workspace it opens on (still suppresses activate/fullscreen); `special:zoom` +
  `Super+z` dropped (the special-workspace confinement was "endless pain").
- **`special:terminal` removed** (unused) — its ws-rule + `Super+S` gone, and the
  now-unused `require("vars")` dropped from `rules.lua`.
- **Duplicate rules converged** — `flameshot`, `float-apps`, and the GTK-portal
  rule collapsed from per-machine `if/else` pairs into one shared rule each.
  GTK-portal is now **float+center on both** (the laptop's old 800x600 cap dropped;
  re-add a laptop `xdg-portal-size` in-situ if ever needed). `flameshot` → shared center.
- Net: the only per-machine window rule left is `msg-apps` (ws10/ws1); the only
  special workspaces are `special:volume` and `special:sharing`.

## 7. Deployment & migration

1. Author the modules alongside the existing files in `dotfiles/.config/hypr/`
   (additive — nothing removed yet). `hyprland.lua` in the repo becomes the new
   unified entry.
2. Validate on the desktop first: point `~/.config/hypr/hyprland.lua` at the new
   entry (or flip the whole-dir symlink) and `hyprctl reload`. Because a syntax
   error keeps the old config, this is safe; verify with `hyprctl monitors`,
   workspace pins, autostart, binds.
3. Flip `~/.config/hypr` to a whole-dir symlink ->
   `dotfiles/.config/hypr/` (retires the per-machine `hyprland.lua` selection
   symlink). Re-verify.
4. Commit. Laptop picks it up on `git pull` + the same whole-dir symlink flip;
   its first boot validates the laptop branch (the reconciliation gives it the
   qs bar etc. at the same time).
5. Keep `hyprland-desktop.lua` / `hyprland-laptop.lua` in the repo as the
   revert path until the unified config has daily-use time; remove later. The
   dead `.conf` (hyprlang) files can be archived in the same pass.

Rollback: repoint the `~/.config/hypr` symlink back to the per-file layout, or
`git revert`. The old files remain intact until explicitly removed.

## 8. Out of scope (recorded, not done here)

- Sharing the monitor->workspace map with Quickshell's `shell.qml` `pools` table
  (a real third duplication). Would require a neutral format (JSON) both read;
  the `machine.lua` record is the natural future source, but Lua can't be read by
  QML. Deferred — YAGNI for now; noted as a future seam.
- `hyprpaper.conf` cleanup (dead config referencing eDP-1; swaybg does wallpaper).
- `hypridle.conf` `systemctl suspend` -> `loginctl suspend` on these
  OpenRC/elogind boxes (pre-existing smell, unrelated).
- Laptop-parity for the Quickshell bar itself (separate effort:
  `2026-08-28-quickshell-bar-and-screenshots-laptop-parity.md`).

## 9. Testing

Per-machine after reload: `hyprctl monitors` shows the expected layout;
`Super+1..0` land on the owning monitor (desktop); autostart set correct per
machine (`nm-applet` laptop-only, audio trio desktop-only); brightness/tailscale
binds present laptop-only; a deliberate syntax error in a module is rejected with
the old config retained. `require("machine").name` matches `cat /etc/hostname`.

## 10. Laptop cutover (follow-up, on `nomad-artix`)

The desktop is done; the laptop is a short follow-up in its own session. The
offline suite already proves the laptop branch (run it there first), so the live
cutover is low-risk:

1. `cd ~/projects/dotfiles && git pull` (brings the unified config + modules).
2. Run the offline suite from the config dir: `.config/hypr/tests/run.sh` — all
   green (it exercises BOTH machine branches, so the laptop branch is pre-verified).
3. Flip the symlink (same as the desktop): `mv ~/.config/hypr ~/.config/hypr.bak-$(date +%Y%m%d)`
   then `ln -sfn ~/projects/dotfiles/.config/hypr ~/.config/hypr`.
4. Reload with the live signature (discover it from
   `$(ls -t /run/user/$(id -u)/hypr/ | head -1)`), then `hyprctl configerrors`
   (expect none) and verify: eDP-1 @ scale 1.25, `nm-applet` present, NO
   pipewire trio (OpenRC owns audio), brightness + tailscale binds, touchpad
   natural-scroll, the clamshell `config.reloaded` hook, and the lid-switch binds.
5. A full log-out / TTY `start-hyprland` is the real test (exercises the
   `hyprland.start` autostart branch).

The laptop rides `bar="waybar"` and `screenshot="flameshot"` until its Quickshell
+ tensaku parity lands; graduate it then by flipping those two fields in
`machine.lua` (one line each — the compatibility bridge). Its `location` is seeded
to Ridgewood and should be made dynamic when the weather popout is wired there.
