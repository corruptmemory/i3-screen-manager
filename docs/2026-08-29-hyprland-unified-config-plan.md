# Hyprland Unified Config — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two drifting per-machine Hyprland configs (`hyprland-desktop.lua`, `hyprland-laptop.lua`) with ONE adaptive Lua config that detects the machine by hostname and branches, so both machines share a single source and stop diverging.

**Architecture:** A light `hyprland.lua` entry `require()`s ~9 focused modules. `machine.lua` reads `/etc/hostname` and returns a hybrid record (`type` + `flags` + a monitor data table). Shared modules carry the identical-in-effect config (aesthetic `hl.config`, the union of window rules, shared binds/env); genuine per-machine deltas branch on the machine record. The refactor is **behavior-preserving**: each machine ends up doing exactly what it does today.

**Tech Stack:** Hyprland 0.56.1 Lua config (`hl` API), standalone `lua5.4`/`luajit` for offline tests, bash test runner. No new dependencies.

**Spec:** `docs/2026-08-29-hyprland-unified-config-design.md` (this plan implements it).

## Global Constraints

- **Repos:** config lives in `dotfiles` (`~/projects/dotfiles/.config/hypr/`); docs live in `i3-screen-manager`. Branch `dotfiles` before editing (never work on its default branch); this session is on the desktop `godlike-artix`.
- **Git:** stage specific files only — NEVER `git add -A` / `git add .`. Commit only when Jim says so; the "commit" steps stage the exact files and hold for his go-ahead. Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3`.
- **Behavior-preserving:** default disposition for any per-machine difference is to reproduce today's behavior exactly. Convergence of stale items (laptop→qs bar, laptop→tensaku screenshots) is explicitly OUT of scope (blocked on other efforts).
- **Detection is cheap + side-effect-free** (config runs twice per reload): `machine.lua` only reads `/etc/hostname`; it launches and mutates nothing.
- **AUR is off-limits.** No new packages needed anyway.
- **Laptop execution is a separate session** on `nomad-artix`. This plan takes the DESKTOP end-to-end and verifies the laptop branch OFFLINE (via the `hl` stub + `HYPR_MACHINE_OVERRIDE`); the laptop's live cutover is a short follow-up (Task 12).
- **Verified runtime facts** (from Hyprland v0.56.1 `src/config/lua/ConfigManager.cpp`): full stdlib open; config dir auto on `package.path` (`require("machine")` just works); reload rebuilds a fresh `lua_State` (no manual `package.loaded` clearing); a syntax error keeps the OLD config (safe migration); `hl.exec_cmd` returns nil (detection must use `io.popen` stdout, never `os.execute`).

---

## File Structure

New files in `dotfiles/.config/hypr/` (authored additively; existing `hyprland-*.lua` kept as the revert path):

| File | Responsibility |
|---|---|
| `hyprland.lua` | ENTRY (new unified). Light: `require("machine")`, then `require` each module in order. Replaces the per-machine selection symlink. |
| `machine.lua` | Detection. Reads `/etc/hostname` (honoring a `HYPR_MACHINE_OVERRIDE` global test/debug hook), returns `{ name, type, flags, monitors, vars_override }`. Pure except one file read. |
| `vars.lua` | Shared program strings (`terminal`, `termFloat`, `mainMod`, `browser`, `menu`) + `fileManager` from the machine record. |
| `monitors.lua` | Consumes `machine.monitors`: applies the static list + workspace→monitor pins (desktop) or the single internal panel (laptop). |
| `envs.lua` | Shared env vars + per-machine branch (GDK/QT platform strings, `_JAVA`, machine-only vars). |
| `looknfeel.lua` | The `hl.config` aesthetic sections (general/decoration/animations/misc/group/dwindle/master/binds/input) + laptop touchpad block. |
| `rules.lua` | Window rules (the UNION of both machines' rules) + the 4 special-workspace rules. |
| `autostart.lua` | `hl.on("hyprland.start", …)` shared execs + per-machine branches (audio trio, nm-applet, morgen, bar, portals) + laptop `config.reloaded` clamshell hook. |
| `bindings.lua` | Keybinds: shared set + per-machine (brightness, tailscale, screenshot family, bar-restart). |

Test scaffolding in `dotfiles/.config/hypr/tests/`:

| File | Responsibility |
|---|---|
| `hl_stub.lua` | Recording stub of the `hl` API surface, so modules load offline and record their calls for assertions. |
| `run.sh` | Runs every `test_*.lua` under `lua5.4`; non-zero exit on any failure. |
| `test_*.lua` | One per module; assert the recorded `hl.*` calls per machine (desktop AND laptop, via the override). |

Load order in `hyprland.lua`: `machine → vars → envs → monitors → looknfeel → rules → autostart → bindings`. (Env before consumers; autostart/bindings last. No inter-module ordering dependency beyond `machine`/`vars` first — verified: the current single file sets these as independent top-level `hl.*` calls.)

---

## Task 1: Test scaffolding — the `hl` recording stub + runner

**Files:**
- Create: `dotfiles/.config/hypr/tests/hl_stub.lua`
- Create: `dotfiles/.config/hypr/tests/run.sh`
- Create: `dotfiles/.config/hypr/tests/assert.lua` (tiny assert helpers)

**Interfaces:**
- Produces: `require("tests.hl_stub")` returns a fresh stub table; installs a global `hl` whose config-affecting calls (`monitor`, `env`, `config`, `window_rule`, `workspace_rule`, `bind`, `on`, `define_submap`) append `{fn=<name>, args={...}}` to `hl._calls`; `hl.dsp` is a deep auto-table whose leaves are callable and return marker tables `{__dsp=<path>, args={...}}`. Provides `hl._reset()` and `hl._install()`.
- Produces: `assert.lua` → `{ eq(a,b,msg), truthy(v,msg), count_calls(hl, fn)->n, calls_of(hl, fn)->list, find_call(hl, fn, pred)->call|nil }`.

- [ ] **Step 1: Write `hl_stub.lua`**

```lua
-- tests/hl_stub.lua — records config-affecting hl.* calls; auto-stubs hl.dsp.*
local function make_dsp(path)
  return setmetatable({}, {
    __index = function(_, k) return make_dsp(path .. "." .. k) end,
    __call  = function(_, ...) return { __dsp = path, args = { ... } } end,
  })
end

local M = {}
function M.new()
  local hl = { _calls = {} }
  local function rec(name)
    return function(...) hl._calls[#hl._calls + 1] = { fn = name, args = { ... } }; end
  end
  for _, n in ipairs({ "monitor", "env", "config", "window_rule", "workspace_rule",
                       "bind", "on", "define_submap", "exec_cmd" }) do
    hl[n] = rec(n)
  end
  hl.dsp = make_dsp("dsp")
  function hl._reset() hl._calls = {} end
  function hl._install() _G.hl = hl; return hl end
  return hl
end
return M
```

- [ ] **Step 2: Write `assert.lua`**

```lua
-- tests/assert.lua
local A = {}
function A.eq(a, b, msg) assert(a == b, (msg or "eq") .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end
function A.truthy(v, msg) assert(v, msg or "expected truthy") end
function A.calls_of(hl, fn) local o = {} for _, c in ipairs(hl._calls) do if c.fn == fn then o[#o+1] = c end end return o end
function A.count_calls(hl, fn) return #A.calls_of(hl, fn) end
function A.find_call(hl, fn, pred) for _, c in ipairs(A.calls_of(hl, fn)) do if pred(c) then return c end end return nil end
return A
```

- [ ] **Step 3: Write `run.sh`**

```bash
#!/usr/bin/env bash
# tests/run.sh — run every test_*.lua from the hypr config dir so require() resolves modules.
set -euo pipefail
cd "$(dirname "$0")/.."          # -> dotfiles/.config/hypr (so require("machine") etc. resolve)
fail=0
for t in tests/test_*.lua; do
  [ -e "$t" ] || continue
  if lua5.4 "$t"; then echo "PASS $t"; else echo "FAIL $t"; fail=1; fi
done
exit $fail
```

- [ ] **Step 4: Smoke-test the harness**

Create `tests/test_harness.lua`:
```lua
package.path = "./?.lua;" .. package.path
local hl = require("tests.hl_stub").new()._install()
local A = require("tests.assert")
hl.env("FOO", "bar")
hl.dsp.window.close()  -- must not error
A.eq(A.count_calls(hl, "env"), 1, "one env call recorded")
A.eq(hl._calls[1].args[1], "FOO", "env key recorded")
print("harness ok")
```

- [ ] **Step 5: Run it**

Run: `chmod +x dotfiles/.config/hypr/tests/run.sh && dotfiles/.config/hypr/tests/run.sh`
Expected: `PASS tests/test_harness.lua` and overall exit 0.

- [ ] **Step 6: Commit** (stage only these files; hold for Jim's go-ahead)

```bash
git -C ~/projects/dotfiles add .config/hypr/tests/hl_stub.lua .config/hypr/tests/assert.lua .config/hypr/tests/run.sh .config/hypr/tests/test_harness.lua
# commit on Jim's go
```

---

## Task 2: `machine.lua` — hostname detection + hybrid record

**Files:**
- Create: `dotfiles/.config/hypr/machine.lua`
- Create: `dotfiles/.config/hypr/tests/test_machine.lua`

**Interfaces:**
- Produces: `require("machine")` → `{ name=string, type="desktop"|"laptop", traits={displays,clamshell,battery,trackpad,backlight,wifi,audio_openrc}, location={name,lat,lon,tz}, monitors=<table>, fileManager=string, unknown?=true }`. Consumed by every other module. `traits` are STATIC hardware capabilities (the durable axis); modules branch on the capability, not on `type`.
- Detection honors a `_G.HYPR_MACHINE_OVERRIDE` string (test/debug hook) before `/etc/hostname`.

- [ ] **Step 1: Write the failing test `test_machine.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")

local function load_as(host)
  _G.HYPR_MACHINE_OVERRIDE = host
  package.loaded["machine"] = nil        -- force re-exec (require caches)
  return require("machine")
end

local d = load_as("godlike-artix")
A.eq(d.type, "desktop", "desktop type")
A.eq(d.traits.audio_openrc, false, "desktop launches audio itself")
A.eq(d.traits.displays, "static", "desktop displays static")
A.eq(d.traits.backlight, false, "desktop no backlight")
A.eq(#d.monitors.list, 3, "desktop has 3 monitor entries (catch-all + 2)")
A.eq(d.location.name, "Ridgewood, NJ", "desktop location seeded")

local l = load_as("nomad-artix")
A.eq(l.type, "laptop", "laptop type")
A.eq(l.traits.wifi, true, "laptop has wifi")
A.eq(l.traits.audio_openrc, true, "laptop audio via OpenRC")
A.eq(l.traits.trackpad, true, "laptop has trackpad")
A.eq(l.traits.displays, "dynamic", "laptop displays dynamic")
A.eq(l.monitors.internal.output, "eDP-1", "laptop internal is eDP-1")
A.truthy(l.location.lat, "laptop location seeded (dynamic later)")
A.eq(d.bar, "quickshell", "desktop bar selector"); A.eq(d.screenshot, "tensaku", "desktop screenshot selector")
A.eq(l.bar, "waybar", "laptop bar (bridge)"); A.eq(l.screenshot, "flameshot", "laptop screenshot (bridge)")

local u = load_as("some-new-box")
A.eq(u.type, "desktop", "unknown falls back to desktop")
A.truthy(u.unknown, "unknown flagged")
A.eq(u.traits.displays, "static", "unknown default traits present")
A.eq(u.name, "some-new-box", "name preserved")
print("machine ok")
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotfiles/.config/hypr/tests/run.sh`
Expected: FAIL `test_machine.lua` — `module 'machine' not found`.

- [ ] **Step 3: Write `machine.lua`**

```lua
-- machine.lua — hostname-based machine detection. Cheap + side-effect-free
-- (the Hyprland config runs twice per reload; this only reads /etc/hostname).
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
-- capability ("brightness because backlight"), not on type. Runtime state
-- (on-battery-now, mouse-plugged-now, lid-closed-now) is owned elsewhere.
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

local DEFAULT_TRAITS = { displays = "static", clamshell = false, battery = false,
                         trackpad = false, backlight = false, wifi = false, audio_openrc = false }

local name = read_hostname()
local m = HOSTS[name]
if not m then
  m = { type = "desktop", traits = DEFAULT_TRAITS, location = { name = "unknown" },
        fileManager = "pcmanfm", bar = "quickshell", screenshot = "tensaku",
        monitors = { list = {} }, unknown = true }
end
m.name = name
return m
```

- [ ] **Step 4: Run to verify it passes**

Run: `dotfiles/.config/hypr/tests/run.sh`
Expected: PASS `test_machine.lua`.

- [ ] **Step 5: Commit** — stage `machine.lua` + `test_machine.lua` (hold for go-ahead).

---

## Task 3: `vars.lua` — shared program strings

**Files:**
- Create: `dotfiles/.config/hypr/vars.lua`
- Create: `dotfiles/.config/hypr/tests/test_vars.lua`

**Interfaces:**
- Consumes: `require("machine")` (for `fileManager`).
- Produces: `require("vars")` → `{ terminal, termFloat, mainMod, browser, menu, fileManager }`. Consumed by `bindings`, `rules`, `autostart`.

- [ ] **Step 1: Write failing test `test_vars.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")
_G.HYPR_MACHINE_OVERRIDE = "godlike-artix"; package.loaded["machine"] = nil; package.loaded["vars"] = nil
local v = require("vars")
A.eq(v.mainMod, "SUPER", "mainMod")
A.eq(v.terminal, "ghostty", "terminal")
A.truthy(v.termFloat:find("com.mitchellh.ghostty.Floating", 1, true), "termFloat class")
A.eq(v.fileManager, "pcmanfm", "desktop fileManager")
_G.HYPR_MACHINE_OVERRIDE = "nomad-artix"; package.loaded["machine"] = nil; package.loaded["vars"] = nil
A.eq(require("vars").fileManager, "nautilus", "laptop fileManager")
print("vars ok")
```

- [ ] **Step 2: Run — expect FAIL** (`module 'vars' not found`). Run: `tests/run.sh`.

- [ ] **Step 3: Write `vars.lua`** (values lifted verbatim from `hyprland-desktop.lua:69-79`; `browser` string is identical on both machines)

```lua
-- vars.lua — shared program strings. Machine-specific bits come from machine.lua.
local m = require("machine")
local terminal = "ghostty"
return {
  terminal    = terminal,
  -- Ghostty needs a dotted GTK app-id or the float rule misses (see hyprland-desktop.lua:70-74).
  termFloat   = terminal .. " --class=com.mitchellh.ghostty.Floating",
  mainMod     = "SUPER",
  menu        = "pkill rofi || rofi -modi drun,run -show drun",
  browser     = "brave-origin --remote-debugging-port=9222 --profile-directory=\"Default\" --enable-wayland-ime --enable-features=WaylandWindowDecorations --enable-features=UseOzonePlatform --new-window --ozone-platform=wayland",
  fileManager = m.fileManager,
}
```

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh`.
- [ ] **Step 5: Commit** — stage `vars.lua` + `test_vars.lua`.

---

## Task 4: `monitors.lua` — data-driven monitor + workspace pins

**Files:**
- Create: `dotfiles/.config/hypr/monitors.lua`
- Create: `dotfiles/.config/hypr/tests/test_monitors.lua`

**Interfaces:**
- Consumes: `require("machine").monitors`.
- Produces: side-effecting `hl.monitor(...)` + `hl.workspace_rule(...)` calls. This module is the SINGLE source for both the monitor definitions and the numbered workspace→monitor pins (retires the old separate `for i=1,10` loop).

- [ ] **Step 1: Write failing test `test_monitors.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")

local function load_for(host)
  _G.HYPR_MACHINE_OVERRIDE = host
  local hl = require("tests.hl_stub").new()._install()
  for _, mod in ipairs({ "machine", "monitors" }) do package.loaded[mod] = nil end
  require("monitors")
  return hl
end

-- desktop: 3 monitors, 10 workspace pins (1-6 DP-2, 7-10 HDMI-A-1), portrait transform+vrr
local d = load_for("godlike-artix")
A.eq(A.count_calls(d, "monitor"), 3, "desktop 3 monitors")
A.eq(A.count_calls(d, "workspace_rule"), 10, "desktop 10 ws pins")
local hdmi = A.find_call(d, "monitor", function(c) return c.args[1].output == "HDMI-A-1" end)
A.truthy(hdmi, "HDMI-A-1 present"); A.eq(hdmi.args[1].transform, 3, "portrait transform 3"); A.eq(hdmi.args[1].vrr, 0, "vrr off")
local ws7 = A.find_call(d, "workspace_rule", function(c) return c.args[1].workspace == "7" end)
A.eq(ws7.args[1].monitor, "HDMI-A-1", "ws7 on HDMI-A-1"); A.eq(ws7.args[1].default, true, "ws7 default on its monitor")

-- laptop: 1 monitor (eDP-1 scale 1.25), 0 numbered pins
local l = load_for("nomad-artix")
A.eq(A.count_calls(l, "monitor"), 1, "laptop 1 monitor")
A.eq(A.count_calls(l, "workspace_rule"), 0, "laptop no numbered pins")
A.eq(l._calls[1].args[1].output, "eDP-1", "laptop eDP-1"); A.eq(l._calls[1].args[1].scale, 1.25, "laptop scale 1.25")
print("monitors ok")
```

- [ ] **Step 2: Run — expect FAIL.** Run: `tests/run.sh`.

- [ ] **Step 3: Write `monitors.lua`**

```lua
-- monitors.lua — applies the machine's monitor layout + workspace pins from data.
local m = require("machine")
local mon = m.monitors

if m.traits.displays == "static" then
  for _, spec in ipairs(mon.list) do
    -- pass through the hl.monitor fields (output/mode/position/scale/transform/vrr)
    local t = { output = spec.output, mode = spec.mode, position = spec.position, scale = spec.scale }
    if spec.transform then t.transform = spec.transform end
    if spec.vrr ~= nil then t.vrr = spec.vrr end
    hl.monitor(t)
    -- numbered workspace -> monitor pins, from the same data (SSOT)
    if spec.workspaces then
      for _, ws in ipairs(spec.workspaces) do
        hl.workspace_rule({
          workspace = tostring(ws),
          monitor   = spec.output,
          default   = (ws == spec.default_ws) or nil,
        })
      end
    end
  end
else -- dynamic (laptop): internal panel only; externals owned by i3-screen-manager at runtime
  local i = mon.internal
  hl.monitor({ output = i.output, mode = i.mode, position = i.position, scale = i.scale })
end
```

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh`.
- [ ] **Step 5: Commit** — stage `monitors.lua` + `test_monitors.lua`.

---

## Task 5: `envs.lua` — shared env + per-machine branch

**Files:**
- Create: `dotfiles/.config/hypr/envs.lua`
- Create: `dotfiles/.config/hypr/tests/test_envs.lua`

**Reconciliation ledger** (from `hyprland-desktop.lua:84-112` vs `hyprland-laptop.lua:44-71`):
- **SHARED (identical both):** `XCURSOR_SIZE=24`, `MOZ_ENABLE_WAYLAND=1`, `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`, `QT_QPA_PLATFORMTHEME=qt5ct`, `SDL_VIDEODRIVER=wayland`, `ELECTRON_OZONE_PLATFORM_HINT=wayland`, `CLUTTER_BACKEND=wayland`.
- **PER-MACHINE (differ / intentional):** `GDK_BACKEND` (desktop `wayland` / laptop `wayland,x11,*`), `QT_QPA_PLATFORM` (desktop `wayland` / laptop `wayland;xcb`), `_JAVA_AWT_WM_NONREPARENTING` (desktop `0` / laptop `1` — laptop comment says intentional).
- **DESKTOP-only:** `MOZ_DBUS_REMOTE=1`, `GIO_USE_VFS=local`, `XDG_CURRENT_DESKTOP=Hyprland`, `XDG_SESSION_TYPE=wayland`, `XDG_SESSION_DESKTOP=Hyprland`.
- **LAPTOP-only:** `HYPRCURSOR_SIZE=24`, `QT_STYLE_OVERRIDE=Fusion`, `OZONE_PLATFORM=wayland`, `CHROMIUM_FLAGS=…`, `XCOMPOSEFILE=~/.XCompose`.
- Disposition: behavior-preserving (reproduce each machine's exact current set). No convergence.

**Interfaces:** Consumes `require("machine")`. Produces `hl.env(...)` calls.

- [ ] **Step 1: Write failing test `test_envs.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")
local function load_for(host)
  _G.HYPR_MACHINE_OVERRIDE = host
  local hl = require("tests.hl_stub").new()._install()
  for _, mod in ipairs({ "machine", "envs" }) do package.loaded[mod] = nil end
  require("envs"); return hl
end
local function env_val(hl, key)
  local c = A.find_call(hl, "env", function(c) return c.args[1] == key end); return c and c.args[2] or nil
end
local d = load_for("godlike-artix")
A.eq(env_val(d, "XCURSOR_SIZE"), "24", "shared cursor")
A.eq(env_val(d, "GDK_BACKEND"), "wayland", "desktop GDK plain")
A.eq(env_val(d, "_JAVA_AWT_WM_NONREPARENTING"), "0", "desktop java 0")
A.eq(env_val(d, "GIO_USE_VFS"), "local", "desktop-only GIO")
A.eq(env_val(d, "HYPRCURSOR_SIZE"), nil, "no laptop-only var on desktop")
local l = load_for("nomad-artix")
A.eq(env_val(l, "GDK_BACKEND"), "wayland,x11,*", "laptop GDK x11 fallback")
A.eq(env_val(l, "_JAVA_AWT_WM_NONREPARENTING"), "1", "laptop java 1")
A.eq(env_val(l, "XCOMPOSEFILE"), "~/.XCompose", "laptop-only XCompose")
A.eq(env_val(l, "GIO_USE_VFS"), nil, "no desktop-only var on laptop")
print("envs ok")
```

- [ ] **Step 2: Run — expect FAIL.** Run: `tests/run.sh`.

- [ ] **Step 3: Write `envs.lua`** (values copied verbatim from the ledger sources)

```lua
-- envs.lua — session env vars. Shared block + per-machine branch (behavior-preserving).
local m = require("machine")

-- shared (identical on both machines today)
hl.env("XCURSOR_SIZE", "24")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

if m.type == "desktop" then
  hl.env("GDK_BACKEND", "wayland")
  hl.env("QT_QPA_PLATFORM", "wayland")
  hl.env("_JAVA_AWT_WM_NONREPARENTING", "0")
  hl.env("MOZ_DBUS_REMOTE", "1")
  hl.env("GIO_USE_VFS", "local")
  hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
  hl.env("XDG_SESSION_TYPE", "wayland")
  hl.env("XDG_SESSION_DESKTOP", "Hyprland")
else
  hl.env("HYPRCURSOR_SIZE", "24")
  hl.env("GDK_BACKEND", "wayland,x11,*")
  hl.env("QT_QPA_PLATFORM", "wayland;xcb")
  hl.env("QT_STYLE_OVERRIDE", "Fusion")
  hl.env("OZONE_PLATFORM", "wayland")
  hl.env("CHROMIUM_FLAGS", "--enable-features=UseOzonePlatform --ozone-platform=wayland --gtk-version=4")
  hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
  hl.env("XCOMPOSEFILE", "~/.XCompose")
end
```

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh`.
- [ ] **Step 5: Commit** — stage `envs.lua` + `test_envs.lua`.

---

## Task 6: `looknfeel.lua` — aesthetic config + laptop touchpad

**Files:**
- Create: `dotfiles/.config/hypr/looknfeel.lua`
- Create: `dotfiles/.config/hypr/tests/test_looknfeel.lua`

**Port source:** `hyprland-desktop.lua:156-266` (the `hl.config({...})` blocks: input, xwayland, ecosystem, general, misc, group, decoration, animations, dwindle, master, binds). These are the shared no-frills aesthetic and are identical in intent on both machines — port them verbatim as shared. The laptop adds a touchpad block inside `input` (`hyprland-laptop.lua:108-120`, `touchpad = { natural_scroll = true }`) — branch that on `m.traits.trackpad`.

**Interfaces:** Consumes `require("machine")`. Produces `hl.config(...)` calls.

- [ ] **Step 1: Write failing test `test_looknfeel.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")
local function load_for(host)
  _G.HYPR_MACHINE_OVERRIDE = host
  local hl = require("tests.hl_stub").new()._install()
  for _, mod in ipairs({ "machine", "looknfeel" }) do package.loaded[mod] = nil end
  require("looknfeel"); return hl
end
local function section(hl, key)
  return A.find_call(hl, "config", function(c) return c.args[1][key] ~= nil end)
end
local d = load_for("godlike-artix")
A.truthy(section(d, "general"), "general section present")
A.truthy(section(d, "animations"), "animations section present")
local anim = section(d, "animations"); A.eq(anim.args[1].animations.enabled, false, "animations off (no-frills)")
local d_input = section(d, "input"); A.eq(d_input.args[1].input.touchpad, nil, "desktop has no touchpad block")
local l = load_for("nomad-artix")
local l_input = section(l, "input"); A.truthy(l_input.args[1].input.touchpad, "laptop has touchpad block")
A.eq(l_input.args[1].input.touchpad.natural_scroll, true, "laptop natural_scroll")
print("looknfeel ok")
```

- [ ] **Step 2: Run — expect FAIL.** Run: `tests/run.sh`.

- [ ] **Step 3: Write `looknfeel.lua`** — port `hyprland-desktop.lua:156-266` verbatim (all `hl.config` blocks), with the `input` block built conditionally:

```lua
-- looknfeel.lua — aesthetic config (no-frills: no animations, square corners, opaque).
-- Ported verbatim from hyprland-desktop.lua:156-266; input gains a laptop touchpad block.
local m = require("machine")

local input = { kb_layout = "us", follow_mouse = 1, sensitivity = 0 }
if m.traits.trackpad then
  input.touchpad = { natural_scroll = true }   -- hyprland-laptop.lua:115-117
end
hl.config({ input = input })

-- >>> PORT: paste the remaining hl.config({...}) blocks from hyprland-desktop.lua:164-266
--     verbatim (xwayland, ecosystem, general, misc, group, decoration, animations,
--     dwindle, master, binds). They are shared, unchanged.
```

Note to executor: the `>>> PORT` block is a mechanical copy of an existing, known-good region; reproduce those lines exactly (do not paraphrase). Verify with the test above and the live reload in Task 11.

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh`.
- [ ] **Step 5: Commit** — stage `looknfeel.lua` + `test_looknfeel.lua`.

---

## Task 7: `rules.lua` — union of window rules + special-workspace rules

**Files:**
- Create: `dotfiles/.config/hypr/rules.lua`
- Create: `dotfiles/.config/hypr/tests/test_rules.lua`

**Reconciliation ledger** (rule NAMES; window rules are machine-agnostic in effect — a rule that floats class X is a no-op if X isn't running, so we take the UNION):
- Shared base: `hyprland-desktop.lua:271-508` (30 rules) — the newer, fuller set.
- ADD the laptop-only rules from `hyprland-laptop.lua`: `firefox-extension-popup`, `firefox-file-dialog`, `idle-inhibit-firefox` (harmless on desktop). 
- DEDUPE the portal drift: desktop `xdg-portal-dialog` vs laptop `xdg-portal-size` — keep the desktop `xdg-portal-dialog` (float+center on `xdg-desktop-portal-gtk`); confirm the laptop's `xdg-portal-size` isn't targeting a genuinely different window at live-verify (Task 11/12). Default: desktop version wins.
- The 4 special-workspace rules (`special:terminal/volume/morgen/zoom`, `hyprland-desktop.lua:514-517`) are identical — shared. `special:terminal` uses `vars.termFloat`.

**Interfaces:** Consumes `require("vars")`. Produces `hl.window_rule(...)` + `hl.workspace_rule(...)` (special only; numbered pins live in `monitors.lua`).

- [ ] **Step 1: Write failing test `test_rules.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")
_G.HYPR_MACHINE_OVERRIDE = "godlike-artix"
local hl = require("tests.hl_stub").new()._install()
for _, mod in ipairs({ "machine", "vars", "rules" }) do package.loaded[mod] = nil end
require("rules")
local function has_rule(name) return A.find_call(hl, "window_rule", function(c) return c.args[1].name == name end) ~= nil end
A.truthy(has_rule("msg-apps"), "shared msg-apps rule")
A.truthy(has_rule("screenshare-indicator"), "desktop screenshare rule in union")
A.truthy(has_rule("firefox-file-dialog"), "laptop firefox rule in union")
A.truthy(has_rule("tensaku"), "tensaku float rule in union")
A.eq(A.count_calls(hl, "workspace_rule"), 4, "4 special-workspace rules (numbered pins are in monitors.lua)")
-- union has no duplicate rule names
local seen = {}
for _, c in ipairs(A.calls_of(hl, "window_rule")) do
  local n = c.args[1].name; A.eq(seen[n], nil, "no duplicate rule: " .. tostring(n)); seen[n] = true
end
print("rules ok")
```

- [ ] **Step 2: Run — expect FAIL.** Run: `tests/run.sh`.

- [ ] **Step 3: Write `rules.lua`** — port `hyprland-desktop.lua:271-517` window+special rules; append the 3 laptop-only firefox rules (port from `hyprland-laptop.lua`); ensure `special:terminal` references `require("vars").termFloat`. Structure:

```lua
-- rules.lua — window rules (UNION of both machines; machine-agnostic in effect) + special ws.
local vars = require("vars")
-- >>> PORT: hyprland-desktop.lua:271-508 window_rule blocks verbatim (30 rules).
-- >>> PORT: append the laptop-only rules from hyprland-laptop.lua:
--            firefox-extension-popup, firefox-file-dialog, idle-inhibit-firefox.
-- >>> DEDUPE: keep desktop's xdg-portal-dialog; omit laptop's xdg-portal-size (same intent).
-- special-workspace rules (shared); termFloat comes from vars:
hl.workspace_rule({ workspace = "special:terminal", on_created_empty = vars.termFloat })
hl.workspace_rule({ workspace = "special:volume",   on_created_empty = "pavucontrol" })
hl.workspace_rule({ workspace = "special:morgen",   on_created_empty = "morgen" })
hl.workspace_rule({ workspace = "special:zoom",     on_created_empty = "zoom" })
```

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh`.
- [ ] **Step 5: Commit** — stage `rules.lua` + `test_rules.lua`.

---

## Task 8: `autostart.lua` — shared execs + per-machine branches + clamshell hook

**Files:**
- Create: `dotfiles/.config/hypr/autostart.lua`
- Create: `dotfiles/.config/hypr/tests/test_autostart.lua`

**Reconciliation ledger** (`hyprland-desktop.lua:126-151` vs `hyprland-laptop.lua:76-103`):
- **SHARED (both, in `hyprland.start`):** the dbus-update-activation-environment lines, `udiskie`, `flameshot`, `hypridle`, polkit agent, `swaybg` (per-machine wallpaper arg), the xdg portals.
- **audio trio** (`pipewire`, `sleep 0.5 && wireplumber`, `sleep 1 && pipewire-pulse`) — guarded by `not m.traits.audio_openrc` (desktop only).
- **nm-applet** — guarded by `m.traits.wifi` (kept INSIDE the `hyprland.start` handler — it's an autostart, not a parse-time action). `morgen`, `xdg-desktop-portal-gtk` — laptop, residual `type` branch.
- **Bar (compatibility bridge):** branch on `m.bar` (`"quickshell"` → `qs … & mako`, else `waybar & mako`), NOT on type. Laptop is `bar="waybar"` today; it graduates by flipping the field, and the config supports both meanwhile.
- **Clamshell hook** (`m.traits.clamshell`): `hl.on("config.reloaded", …)` → `hyprland-clamshell-restore` (`hyprland-laptop.lua:101-103`).
- Wallpaper: desktop `swaybg -i ~/projects/wallpapers/earth.jpg -m fill`; laptop `swaybg -i /home/jim/projects/wallpapers/earthshot.jpg -m stretch`. Branch.
- Note: the dbus var SET differs per machine (laptop includes SSH_AUTH_SOCK/GNOME_KEYRING/VK_ICD). Behavior-preserving: keep each machine's exact dbus line.

**Interfaces:** Consumes `require("machine")`. Produces `hl.on(...)` registrations. (The stub records `hl.on` calls; the test asserts the event names registered. To assert the execs inside the handler, the test invokes the recorded handler fn with a stubbed `hl.exec_cmd`.)

- [ ] **Step 1: Write failing test `test_autostart.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")
local function load_for(host)
  _G.HYPR_MACHINE_OVERRIDE = host
  local hl = require("tests.hl_stub").new()._install()
  for _, mod in ipairs({ "machine", "autostart" }) do package.loaded[mod] = nil end
  require("autostart"); return hl
end
-- capture the exec_cmd strings a given event handler emits
local function execs_for(hl, event)
  local reg = A.find_call(hl, "on", function(c) return c.args[1] == event end)
  if not reg then return {} end
  local emitted = {}
  hl.exec_cmd = function(cmd) emitted[#emitted+1] = cmd end   -- override recorder for capture
  reg.args[2]()                                               -- invoke the handler
  return emitted
end
local function any(list, sub) for _, s in ipairs(list) do if tostring(s):find(sub, 1, true) then return true end end return false end

local d = load_for("godlike-artix")
local de = execs_for(d, "hyprland.start")
A.truthy(any(de, "pipewire"), "desktop launches audio trio")
A.truthy(any(de, "qs -p ~/.config/quickshell"), "desktop bar = qs")
A.truthy(not any(de, "nm-applet"), "desktop has no nm-applet")
A.truthy(A.find_call(d, "on", function(c) return c.args[1] == "config.reloaded" end) == nil, "desktop has no clamshell hook")

local l = load_for("nomad-artix")
local le = execs_for(l, "hyprland.start")
A.truthy(not any(le, "pipewire"), "laptop does NOT launch audio (OpenRC)")
A.truthy(any(le, "nm-applet"), "laptop launches nm-applet")
A.truthy(any(le, "waybar"), "laptop bar = waybar (deferred convergence)")
A.truthy(A.find_call(l, "on", function(c) return c.args[1] == "config.reloaded" end) ~= nil, "laptop has clamshell hook")
print("autostart ok")
```

- [ ] **Step 2: Run — expect FAIL.** Run: `tests/run.sh`.

- [ ] **Step 3: Write `autostart.lua`** (port exec strings verbatim from the two sources per the ledger)

```lua
-- autostart.lua — hyprland.start execs (shared + per-machine) + laptop clamshell hook.
local m = require("machine")

hl.on("hyprland.start", function()
  -- dbus env propagation — keep each machine's exact var set (behavior-preserving).
  if m.type == "desktop" then
    hl.exec_cmd("dbus-update-activation-environment WAYLAND_DISPLAY MOZ_ENABLE_WAYLAND MOZ_DBUS_REMOTE _JAVA_AWT_WM_NONREPARENTING QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION SDL_VIDEODRIVER XCURSOR_SIZE")
    hl.exec_cmd("dbus-update-activation-environment PATH")
  else
    hl.exec_cmd("dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XCURSOR_SIZE HYPRCURSOR_SIZE GDK_BACKEND QT_QPA_PLATFORM QT_STYLE_OVERRIDE SDL_VIDEODRIVER MOZ_ENABLE_WAYLAND ELECTRON_OZONE_PLATFORM_HINT OZONE_PLATFORM QT_WAYLAND_DISABLE_WINDOWDECORATION QT_QPA_PLATFORMTHEME _JAVA_AWT_WM_NONREPARENTING CLUTTER_BACKEND CHROMIUM_FLAGS XDG_DATA_DIRS VK_ICD_FILENAMES GNOME_KEYRING_CONTROL SSH_AUTH_SOCK DBUS_SESSION_BUS_ADDRESS")
  end

  hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

  if not m.traits.audio_openrc then          -- desktop launches the audio stack itself
    hl.exec_cmd("pipewire")
    hl.exec_cmd("sleep 0.5 && wireplumber")
    hl.exec_cmd("sleep 1 && pipewire-pulse")
  end

  -- bar (compatibility bridge: laptop flips m.bar -> "quickshell" when parity lands)
  if m.bar == "quickshell" then
    hl.exec_cmd("sleep 1 && qs -p ~/.config/quickshell & mako")
  else
    hl.exec_cmd("waybar & mako")
  end
  -- per-machine wallpaper (+ laptop extras)
  if m.type == "desktop" then
    hl.exec_cmd("swaybg -i ~/projects/wallpapers/earth.jpg -m fill")
  else
    hl.exec_cmd("swaybg -i /home/jim/projects/wallpapers/earthshot.jpg -m stretch")
    hl.exec_cmd("morgen")
  end

  if m.traits.wifi then hl.exec_cmd("nm-applet --indicator") end   -- wifi tray (capability; stays INSIDE the handler)

  hl.exec_cmd("udiskie")
  hl.exec_cmd("flameshot")
  hl.exec_cmd("hypridle")

  -- xdg portals (desktop: hyprland+generic; laptop also gtk)
  hl.exec_cmd("sleep 1 && /usr/lib/xdg-desktop-portal-hyprland" .. (m.type == "desktop" and " &" or ""))
  if m.type == "laptop" then hl.exec_cmd("sleep 1 && /usr/lib/xdg-desktop-portal-gtk") end
  hl.exec_cmd("sleep 2 && /usr/lib/xdg-desktop-portal" .. (m.type == "desktop" and " &" or ""))
end)

-- re-apply clamshell eDP-1 disable after every config reload (no-op fast when not clamshelled)
if m.traits.clamshell then
  hl.on("config.reloaded", function() hl.exec_cmd("hyprland-clamshell-restore") end)
end
```

Executor note: reconcile the portal `&` backgrounding and exact sleep values against the two source files during Task 11/12 live-verify; the branch structure above preserves each machine's current set.

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh`.
- [ ] **Step 5: Commit** — stage `autostart.lua` + `test_autostart.lua`.

---

## Task 9: `bindings.lua` — shared binds + per-machine binds

**Files:**
- Create: `dotfiles/.config/hypr/bindings.lua`
- Create: `dotfiles/.config/hypr/tests/test_bindings.lua`

**Reconciliation ledger** (`hyprland-desktop.lua:534-645` vs laptop binds):
- **SHARED:** the bulk — app launchers (terminal/browser/emacs/rofi-rbw/hyprlock), window management, groups, special-workspace toggles, focus/move, workspace switch/move (`for i=1,10`), scroll, mouse drag/resize, volume/media (`wpctl`/`playerctl`), the resize submap. Use `require("vars")` for `terminal`/`termFloat`/`mainMod`/`browser`/`menu`.
- **DESKTOP-only:** `Super+F1/F2/F3` chat focus (Slack/Keybase/discord), `Super+Backspace`→i3-screen-rofi etc., `Super+Shift+W`→qs restart.
- **Capability/laptop:** brightness `XF86MonBrightnessUp/Down`→brightnessctl (guarded `m.traits.backlight`), tailscale `Super+Shift+N`→i3-tailscale-rofi (residual `type`), `Super+Shift+W`→waybar restart (machine-coupled).
- **Screenshot binds (compatibility bridge):** branch on `m.screenshot` — `"tensaku"` → the family (`Print`/`Shift+Print`/`Ctrl+Print`/`Super+Print`/`Super+Ctrl+Print`, `hyprland-desktop.lua:631-635`); else the laptop's single `Print → flameshot gui`. Laptop is `screenshot="flameshot"` until tensaku is installed there, then flip the field.
- **Bar-restart bind** keys on `m.bar` (same bridge).

**Interfaces:** Consumes `require("vars")`, `require("machine")`. Produces `hl.bind(...)` + `hl.define_submap(...)`.

- [ ] **Step 1: Write failing test `test_bindings.lua`**

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")
local function load_for(host)
  _G.HYPR_MACHINE_OVERRIDE = host
  local hl = require("tests.hl_stub").new()._install()
  for _, mod in ipairs({ "machine", "vars", "bindings" }) do package.loaded[mod] = nil end
  require("bindings"); return hl
end
local function has_key(hl, keys) return A.find_call(hl, "bind", function(c) return c.args[1] == keys end) ~= nil end
-- capture exec_cmd string for a bind (dispatcher marker has __dsp="dsp.exec_cmd")
local function exec_of(hl, keys)
  local c = A.find_call(hl, "bind", function(c) return c.args[1] == keys end)
  local d = c and c.args[2]; return (d and d.__dsp == "dsp.exec_cmd") and d.args[1] or nil
end
local d = load_for("godlike-artix")
A.truthy(has_key(d, "SUPER + F1"), "desktop chat-focus bind")
A.eq(exec_of(d, "Print"), "screenshot region --annotate", "desktop Print = tensaku flow")
A.eq(exec_of(d, "SUPER + SHIFT + W"), "pkill -f '^qs '; qs -p ~/.config/quickshell", "desktop bar restart = qs")
A.truthy(not has_key(d, "XF86MonBrightnessUp"), "no brightness bind on desktop")
local l = load_for("nomad-artix")
A.truthy(has_key(l, "XF86MonBrightnessUp"), "laptop brightness bind")
A.truthy(has_key(l, "SUPER + SHIFT + N"), "laptop tailscale bind")
A.eq(exec_of(l, "Print"), "flameshot gui", "laptop Print = flameshot (deferred convergence)")
print("bindings ok")
```

- [ ] **Step 2: Run — expect FAIL.** Run: `tests/run.sh`.

- [ ] **Step 3: Write `bindings.lua`** — port `hyprland-desktop.lua:534-645` shared binds using `vars`; branch the per-machine binds per the ledger:

```lua
-- bindings.lua — keybinds. Shared set (via vars) + per-machine branches.
local m    = require("machine")
local v    = require("vars")
local mod  = v.mainMod
-- >>> PORT: shared binds from hyprland-desktop.lua:536-626 verbatim, substituting
--     `mainMod`->`mod`, `terminal`->v.terminal, `termFloat`->v.termFloat,
--     `browser`->v.browser, `menu`->v.menu. (apps, window mgmt, groups, special ws,
--     focus/move, workspace switch/move for i=1,10, scroll, mouse, volume/media.)

-- display/keyboard management (shared)
hl.bind(mod .. " + BackSpace",           hl.dsp.exec_cmd("i3-screen-rofi"))
hl.bind(mod .. " + CONTROL + BackSpace", hl.dsp.exec_cmd("i3-keyboard-rofi"))
hl.bind(mod .. " + ALT + BackSpace",     hl.dsp.exec_cmd("i3-screen-manager dpi"))

-- chat quick-focus (shared; harmless if an app isn't running)
hl.bind(mod .. " + F1", hl.dsp.focus({ window = "class:Slack" }))
hl.bind(mod .. " + F2", hl.dsp.focus({ window = "class:Keybase" }))
hl.bind(mod .. " + F3", hl.dsp.focus({ window = "class:discord" }))

-- bar restart (compatibility bridge: keys on m.bar)
if m.bar == "quickshell" then
  hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd("pkill -f '^qs '; qs -p ~/.config/quickshell"))
else
  hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd("pkill waybar; waybar"))
end

-- screenshots (compatibility bridge: keys on m.screenshot; laptop flips to tensaku at parity)
if m.screenshot == "tensaku" then
  hl.bind("Print",                   hl.dsp.exec_cmd("screenshot region --annotate"))
  hl.bind("SHIFT + Print",           hl.dsp.exec_cmd("screenshot full --annotate"))
  hl.bind("CONTROL + Print",         hl.dsp.exec_cmd("screenshot region"))
  hl.bind(mod .. " + Print",         hl.dsp.exec_cmd("flameshot gui"))
  hl.bind(mod .. " + CONTROL + Print", hl.dsp.exec_cmd("screenshot clipboard"))
else
  hl.bind("Print", hl.dsp.exec_cmd("flameshot gui"))
end

-- capability/laptop binds
if m.traits.backlight then
  hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s +5%"), { repeating = true })
  hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { repeating = true })
end
if m.type == "laptop" then
  hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd("i3-tailscale-rofi"))
end

-- resize submap (shared) — PORT hyprland-desktop.lua:638-645 verbatim.
```

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh`.
- [ ] **Step 5: Commit** — stage `bindings.lua` + `test_bindings.lua`.

---

## Task 10: `hyprland.lua` entry + full-config smoke test

**Files:**
- Create: `dotfiles/.config/hypr/hyprland.lua` (the new unified entry)
- Create: `dotfiles/.config/hypr/tests/test_full.lua`

**Interfaces:** Consumes all modules. The whole config for a machine = requiring this file with `hl` installed.

- [ ] **Step 1: Write failing test `test_full.lua`** (loads the entry per machine under the stub, asserts it runs clean and produces the expected high-level shape)

```lua
package.path = "./?.lua;" .. package.path
local A = require("tests.assert")
local function load_entry(host)
  _G.HYPR_MACHINE_OVERRIDE = host
  local hl = require("tests.hl_stub").new()._install()
  for _, mod in ipairs({ "machine","vars","envs","monitors","looknfeel","rules","autostart","bindings" }) do
    package.loaded[mod] = nil
  end
  package.loaded["hyprland_entry"] = nil
  assert(loadfile("hyprland.lua"))()   -- run the entry file
  return hl
end
local d = load_entry("godlike-artix")
A.truthy(A.count_calls(d, "monitor") == 3, "desktop 3 monitors via entry")
A.truthy(A.count_calls(d, "bind") > 30, "desktop binds loaded")
A.truthy(A.count_calls(d, "window_rule") > 25, "desktop rules loaded")
local l = load_entry("nomad-artix")
A.eq(A.count_calls(l, "monitor"), 1, "laptop 1 monitor via entry")
A.truthy(A.find_call(l, "on", function(c) return c.args[1] == "config.reloaded" end), "laptop clamshell hook via entry")
print("full ok")
```

- [ ] **Step 2: Run — expect FAIL.** Run: `tests/run.sh`.

- [ ] **Step 3: Write `hyprland.lua`** (the light entry)

```lua
-- hyprland.lua — unified adaptive entry for godlike-artix (desktop) + nomad-artix (laptop).
-- Detects the machine (machine.lua) and requires the modules in order. See
-- i3-screen-manager/docs/2026-08-29-hyprland-unified-config-design.md.
---@module 'hl'
local m = require("machine")
require("vars")
require("envs")
require("monitors")
require("looknfeel")
require("rules")
require("autostart")
require("bindings")
```

- [ ] **Step 4: Run — expect PASS.** Run: `tests/run.sh` (all `test_*.lua` green).

- [ ] **Step 5: Commit** — stage `hyprland.lua` + `test_full.lua`.

---

## Task 11: Live desktop cutover + whole-dir symlink

**Files:** Modify: `~/.config/hypr` symlink (machine-local, not in repo).

- [ ] **Step 1: Back up the current symlink state**

Run: `ls -la ~/.config/hypr > /tmp/hypr-symlinks-before.txt` (records the current per-file symlinks for rollback).

- [ ] **Step 2: Provisional in-place test (safe — a syntax error keeps the old config)**

Point just the entry first (least disruptive): `ln -sfn ~/projects/dotfiles/.config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua`. Reload with the live signature:
```bash
HIS=$(tr '\0' '\n' < /proc/$(pgrep -x Hyprland | head -1)/environ | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p')
HYPRLAND_INSTANCE_SIGNATURE="$HIS" hyprctl reload
```
BUT: with per-file symlinks the sibling modules (`machine.lua`, etc.) aren't in `~/.config/hypr`, so `require` would fail. Therefore do Step 3 (whole-dir symlink) as the actual cutover; this step is only to confirm the entry parses.

- [ ] **Step 3: Flip `~/.config/hypr` to a whole-dir symlink**

```bash
mv ~/.config/hypr ~/.config/hypr.bak-$(date +%Y%m%d)
ln -sfn ~/projects/dotfiles/.config/hypr ~/.config/hypr
```
(The dir symlink exposes all modules so `require("machine")` etc. resolve; it retires the per-machine `hyprland.lua` selection symlink. The `.bak` dir is the rollback.)

- [ ] **Step 4: Reload and verify live**

```bash
HYPRLAND_INSTANCE_SIGNATURE="$HIS" hyprctl reload && echo OK
```
Verify:
- `hyprctl monitors -j | jq '.[].name'` → `DP-2`, `HDMI-A-1` (portrait upright).
- `Super+1..6` land on DP-2, `Super+7..0` on HDMI-A-1.
- Tray/bar (qs) up; `nm-applet` absent; audio works (`wpctl status`).
- A few binds fire (`Super+Return`, `Print` → tensaku flow).

- [ ] **Step 5: Verify the syntax-error safety net**

Temporarily introduce a Lua syntax error in a copy path (e.g. `echo 'syntax(' >> ~/projects/dotfiles/.config/hypr/monitors.lua` in a scratch check ONLY if safe), reload, confirm Hyprland keeps the working config and logs the error; then revert. (Optional — the source guarantees it; skip if risky.)

- [ ] **Step 6: Confirm with Jim, then commit** the config (all module files + entry) on his go-ahead. Do NOT delete `hyprland-desktop.lua`/`hyprland-laptop.lua` yet (revert path).

---

## Task 12: Docs + laptop follow-up note

**Files:**
- Modify: `i3-screen-manager/docs/2026-08-29-hyprland-unified-config-design.md` (status → executed on desktop)
- Modify: `i3-screen-manager/CLAUDE.md` (architecture: note the unified config + `machine.lua`)
- Create/append: a short laptop cutover checklist (in the design doc)

- [ ] **Step 1** Update the design doc status block to "executed on `godlike-artix` <date>; laptop cutover pending", and add a **Laptop cutover** section: `git pull` dotfiles on `nomad-artix`; run `tests/run.sh` (the offline suite already proves the laptop branch); flip `~/.config/hypr` to the whole-dir symlink; reload; verify eDP-1 scale 1.25, nm-applet present, no audio-trio launch, brightness+tailscale binds, clamshell hook; note the still-deferred bar (waybar) + screenshot (flameshot) until the laptop-qs/tensaku parity effort.

- [ ] **Step 2** Update `i3-screen-manager/CLAUDE.md`: under Architecture / Hyprland session, note the config is now a single adaptive Lua config (`dotfiles/.config/hypr/hyprland.lua` + `machine.lua` hostname detection + `~/.config/hypr` whole-dir symlink), replacing the per-machine files. Add a one-line Common-Issues entry: "config runs twice per reload; `machine.lua` must stay side-effect-free."

- [ ] **Step 3** Commit docs on Jim's go-ahead (stage the specific doc files).

- [ ] **Step 4 (later, separate session on the laptop)** Execute the Laptop cutover checklist on `nomad-artix`. Then, once laptop qs + tensaku parity lands, graduate the laptop by flipping `nomad-artix`'s `bar = "quickshell"` and `screenshot = "tensaku"` in `machine.lua` — one line each, no branch-logic change (the compatibility bridge).

---

## Self-Review

- **Spec coverage:** every spec section maps to a task — detection (§3→T2), hybrid record (§4→T2), module layout (§5→T3-T10), reconciliation (§6→ledgers in T5-T9), deployment/migration (§7→T11-T12), out-of-scope fences (§8 respected: bar/screenshots kept per-machine, no Quickshell SSOT, no hyprpaper/hypridle edits), testing (§9→the offline suite + T11 live checks).
- **Placeholder scan:** the `>>> PORT` markers are deliberate references to exact existing line ranges in known-good files (a refactor *moves* code; re-transcribing 200 lines of window rules verbatim into the plan invites copy errors). Each is bounded by explicit source line numbers and covered by a test — not hand-waving. All NEW logic (harness, machine, monitors, entry, branches, every test) is written in full.
- **Type/name consistency:** `machine` record shape (`type`/`flags`/`monitors`/`fileManager`) is identical across T2 producer and all consumers; `vars` keys consistent T3→T9; test helper names (`calls_of`/`find_call`/`count_calls`) consistent across all `test_*.lua`.
- **Scope:** one coherent behavior-preserving refactor; laptop live cutover fenced to a follow-up (I'm on the desktop and cannot run the laptop).

---

## Execution Handoff

Two options:
1. **Inline execution (recommended here)** — I execute the tasks in THIS session with you steering, checkpointing after each module (matches your collaborative style; and the live cutover in T11 is your desktop, so you'll want eyes on it). Uses superpowers:executing-plans.
2. **Subagent-driven** — a fresh subagent per task with review between. Faster for the mechanical module ports, but the live cutover still needs you.
