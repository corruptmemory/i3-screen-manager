# Hyprland hyprlang → Lua config migration

**Status:** Desktop (`godlike-artix`) migrated, validated, and **live-verified
against the old config** 2026-06-09 — running under the lua manager with full
parity (see [verification](#runtime-verification-only-a-live-session-can-confirm)).
Laptop (`nomad-artix`) authored 2026-06-13, validated (`config ok`), armed via
`~/.config/hypr/hyprland.lua` symlink; pending logout/login to switch managers.
Both machines' waybar configs are now patched and live-verified for the workspace-click regression (2026-06-13) — see [waybar regression](#waybar-workspace-click-regression-waybar-5008).

This is the worked record of migrating `hyprland-desktop.conf` (hyprlang) to
`hyprland-desktop.lua` for Hyprland 0.55+. It exists so the laptop migration can
be done the same way without re-discovering the converter's sharp edges.

---

## Why

Confirmed against official sources (June 2026):

- **Installed:** Hyprland **0.55.3** (`hyprctl version`).
- **Deprecation:** *"Since Hyprland 0.55, hyprlang is deprecated in favor of
  lua."* — [wiki Start page](https://wiki.hypr.land/Configuring/Start/) and the
  [Lua-ification announcement](https://hypr.land/news/26_lua/).
- **Clock:** hyprlang supported *"for 1 - 2 releases starting from 0.55. After
  that, hyprlang will be dropped"*, and *"new config features will not be added
  to hyprlang anymore."* Finite runway, no upside to waiting.

### Scope: only ONE file per machine migrates

`~/.config/hypr/` holds five configs. Only the **compositor** one moves:

| File | Migrates? |
|---|---|
| `hyprland.conf` → `hyprland-desktop.conf` | **Yes** → `.lua` |
| `hypridle.conf`, `hyprlock.conf`, `hyprpaper.conf`, `xdph.conf` | **No — stay hyprlang.** Separate hypr\* tools; the announcement keeps them on hyprlang. |

---

## The new Lua API (ground truth)

Source of truth, in priority order:

1. **`example/hyprland.lua` in the Hyprland repo** — `gh api
   repos/hyprwm/Hyprland/contents/example/hyprland.lua --jq .content | base64 -d`
2. **Wiki markdown source** (the rendered HTML pages do NOT survive WebFetch —
   they're JS-rendered; fetch the source instead):
   `gh api repos/hyprwm/hyprland-wiki/contents/content/Configuring/Basics/<Page>.md --jq .content | base64 -d`
   — pages: `Binds.md`, `Dispatchers.md`, `Window-Rules.md`, `Workspace-Rules.md`.

The compositor exposes a global **`hl`**:

| hyprlang | Lua |
|---|---|
| `monitor=...` | `hl.monitor({ output=, mode=, position=, scale= })` |
| `env = K,V` | `hl.env("K", "V")` — **value is a string** |
| `general { ... }` etc. | `hl.config({ general = { ... } })` |
| `col.active_border = a b 45deg` | `col = { active_border = { colors = {"a","b"}, angle = 45 } }` |
| `windowrule { name= match:class= float=true }` | `hl.window_rule({ name=, match={ class= }, float=true })` |
| two `suppress_event =` lines | one space-joined string: `suppress_event = "activate fullscreen"` |
| `workspace = special:x, on-created-empty: cmd` | `hl.workspace_rule({ workspace="special:x", on_created_empty="cmd" })` |
| `exec-once = cmd` | inside `hl.on("hyprland.start", function() hl.exec_cmd("cmd") end)` |
| `bind = MOD, key, dispatcher, arg` | `hl.bind("MOD + key", hl.dsp.<dispatcher>(...))` |
| `bindd` (description) | flags table: `hl.bind(..., ..., { description = "..." })` |
| `binde` (repeat) | `{ repeating = true }` |
| `bindl` (locked) | `{ locked = true }` |
| `bindm` (mouse) | `hl.bind(..., hl.dsp.window.drag(), { mouse = true })` |
| `submap=name` / `submap=reset` | `hl.define_submap("name", function() ... end)` + `hl.dsp.submap("name")` / `hl.dsp.submap("reset")` |

Dispatcher namespaces (from `Dispatchers.md`): top-level `hl.dsp.focus/layout/exec_cmd/exit`;
`hl.dsp.window.*` (close, float, fullscreen, pseudo, move, resize, cycle_next,
toggle_swallow, pin); `hl.dsp.workspace.*` (toggle_special, move);
`hl.dsp.group.*` (toggle, next, prev, active, move_window, lock, lock_active).

---

## Process used (desktop)

```bash
# 0. Confirm version + clean baseline
hyprctl version
hyprctl configerrors                       # baseline must be clean

# 1. Install the first-pass converter (isolated)
pipx install hyprconf2lua                   # v1.3.0, June 2026

# 2. First pass into SCRATCH (never straight into the live config)
SCRATCH=/tmp/hypr-lua-migration; mkdir -p "$SCRATCH"
CONF=~/projects/dotfiles/.config/hypr/hyprland-desktop.conf
hyprconf2lua --report "$CONF" -o "$SCRATCH/out.lua"   # see "Converter defects" — it WILL need help

# 3. Hand-correct against the official API (see defect list). Author the final
#    file in the dotfiles dir but DO NOT symlink it yet.

# 4. Validate WITHOUT touching the live session:
lua5.4 -e 'assert(loadfile("…/hyprland-desktop.lua"))'        # syntax
Hyprland --verify-config -c …/hyprland-desktop.lua           # semantics → "config ok"

# 5. Arm (non-disruptive — running session already loaded .conf; this only
#    takes effect on the NEXT Hyprland start). Use an ABSOLUTE target to match
#    the .conf symlink convention — a relative target resolves inside
#    ~/.config/hypr/ where the real file does NOT live, giving a broken link.
ln -sf /home/jim/projects/dotfiles/.config/hypr/hyprland-desktop.lua ~/.config/hypr/hyprland.lua

# 6. Live switch = LOGOUT/LOGIN, not `hyprctl reload`. Hyprland picks its config
#    MANAGER (hyprlang vs lua) at startup via discovery; a reload re-reads the
#    .conf the session started under and won't pick up a newly-appeared .lua.
#    Rollback before re-login: rm ~/.config/hypr/hyprland.lua
```

**Validation is the whole game.** `Hyprland --verify-config -c FILE` is a true
dry-run ("Do not run Hyprland, only print if the config has any errors"); it
auto-detects Lua by extension and never launches the compositor. This is what
makes the migration safe — you can prove a staged file loads before arming it.

---

## Converter defects (hyprconf2lua v1.3.0) — what to hand-fix

The converter is a **scaffold, not a drop-in**. It nailed the declarative bulk
(monitor, all 11 `hl.config` sections except one, all 28 window rules, env
values modulo quoting, autostart wrapping, mouse binds, simple binds) but
mangled a large slice of the keybinds. Its advertised "~95% coverage" counts
*lines emitted*, not *lines correct*. Real story below.

**Hard failures (config won't load):**

1. **Comma inside a `$variable` value → total parse failure, zero output.**
   `$menu = ... rofi -modi drun,run ...` died at the comma (`L5:38: Unexpected
   token ','`). Fix: neutralize value-internal commas before running
   (`sed 's/drun,run/drun__C__run/'`), then restore `__C__`→`,` in the output.
2. **`groupbar.col.active = ...` (flat dotted key) → invalid Lua.** A dotted key
   is illegal in a table constructor; must be `col = { active=, inactive= }`.
   (Inconsistent: it nested `general.col` and `group.col` correctly.)
3. **`on-created-empty = ...` → invalid Lua** (hyphens parse as subtraction).
   Correct key is `on_created_empty`.

**Semantic corruptions (loads, but wrong behavior):**

4. **Compound `$mainMod+SHIFT` (plus-form) left as the literal string
   `"$mainMod+SHIFT"`** — no interpolation inside a Lua string. ~25 binds.
   (Exact boundary: space-form `$mainMod SHIFT` *did* resolve; only the
   `+`-joined form failed.) Fix: `mainMod .. " + SHIFT + ..."`.
5. **10 real dispatchers emitted as commented-out dead code** with guessed
   names: `toggleswallow`→`hl.dsp.window.toggle_swallow()`;
   `lockactivegroup`→`hl.dsp.group.lock_active({action="toggle"})`;
   `movewindoworgroup`→`hl.dsp.window.move({direction=…, group_aware=true})`;
   `resizeactive`→`hl.dsp.window.resize({x=, y=, relative=true})`.
6. **`changegroupactive` → `group.next({forward=false})`** using an undocumented
   `forward` param. Correct: `group.prev()` / `group.next()`.
7. **`fullscreen,1` and `fullscreen,0` → identical bare `window.fullscreen()`**,
   losing the mode. Correct: `{ mode = "maximized" }` vs `{ mode = "fullscreen" }`.
8. **`movetoworkspace,N` → `window.move(N)`** (bare int). Correct:
   `window.move({ workspace = N })`.
9. **`togglefloating` → bare `window.float()`** — make the action explicit:
   `{ action = "toggle" }`.
10. **`togglespecialworkspace, terminal` → `toggle_special(terminal)`** — it
    variable-resolved the workspace *name* "terminal" into the `terminal` local
    (`"kitty"`), pointing at the wrong workspace. Correct: `toggle_special("terminal")`.
11. **`binde` / `bindl` flags dropped** — volume & resize lost `{ repeating = true }`.
12. **two `suppress_event` lines collapsed to the last one** (dropped `activate`).
    Correct: one space-joined string.
13. **`bindd` descriptions dropped** (cosmetic; restore with `{ description = }`).
14. Cosmetic: env numbers unquoted; `--profile-directory="Default"` quotes
    stripped; `-j | jq` whitespace munged; unused locals; doubled blank lines.

**Net:** the 28 window rules + section blocks saved real time; the ~83-bind
block was faster to re-author by hand against the wiki than to repair line by
line. Budget for "convert in 1 minute, hand-fix the binds for an hour."

---

## Runtime verification (only a live session can confirm)

`--verify-config` proves the file *loads*; it can't prove behavior. After the
live switch, verify in two passes: **machine introspection** (proves the bulk
without lifting a finger) then a short **human spot-check** (the part Hyprland
won't let a machine read back).

### Pass 1 — machine-verifiable via `hyprctl`/`pgrep`/`/proc` (desktop: all ✓)

```bash
# Confirm you're actually under the lua manager (not just "no errors"):
hyprctl systeminfo | grep -i configProvider          # → configProvider: lua

# Binds: live count MUST equal the source .conf bind count. Triggers, modmask,
# repeat/mouse flags and submaps are all introspectable...
hyprctl binds -j | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'
#   ...BUT each dispatcher reports as "__lua" with a numeric callback ref — the
#   ACTION behind a key is NOT introspectable under a lua config. Verify the
#   bind count + triggers here; verify the actions by source-read + Pass 2.

# Declarative options: spot-check live values against the .conf:
hyprctl getoption general:gaps_in -j
hyprctl getoption group:groupbar:col.active -j        # the defect-#2 one
#   Gotchas: colors come back AARRGGBB (rgba(1e3a5fff) → "ff1e3a5f"); and
#   group:groupbar:font_weight_active returns "invalid type (internal error)" —
#   a hyprctl read limitation, NOT an unset value. Confirm bold visually instead.

# Autostart: every exec-once process should be up (incl. the audio stack in order):
for p in pipewire wireplumber pipewire-pulse waybar mako nm-applet udiskie \
         flameshot hypridle swaybg xdg-desktop-portal-hyprland xdg-desktop-portal; do
  pgrep -f "$p" >/dev/null && echo "ok  $p" || echo "MISSING $p"; done

# env block: confirm it reached launched apps (sample any child of the session):
tr '\0' '\n' < /proc/$(pgrep -x waybar)/environ | grep -E '^(XCURSOR_SIZE|MOZ_ENABLE_WAYLAND|QT_QPA_PLATFORM|GDK_BACKEND|XDG_CURRENT_DESKTOP|GIO_USE_VFS)='
```

Reusable scratch scripts from the desktop pass (decode modmask → dump every
bind; batch-compare ~40 options): `/tmp/hypr-lua-migration/{dump_binds.py,check_options.py}`.

Desktop result: 83/83 binds, 40/40 options (incl. both hand-fixed converter
defects), 13/13 autostart, 12/12 env vars, 4/4 special-workspace rules, monitor
— all matched the `.conf`.

### Pass 2 — human spot-check (Lua bind actions are opaque, so press the keys)

- [ ] **Dual-bind:** `mainMod+left/right` are intentionally bound to BOTH
      `focus` and group `prev/next` (faithful to the original). Both appear
      twice in `hyprctl binds`; confirm both behaviors still fire.
- [ ] **Fullscreen modes:** `mainMod+F` = maximize (keeps bar/gaps),
      `mainMod+SHIFT+F` = true fullscreen. Confirm they differ.
- [ ] **Resize submap:** `mainMod+ALT+R`, then arrows resize *and repeat on
      hold*, `escape` exits.
- [ ] **Direction strings:** focus/move use `"left"`/`"right"`/`"up"`/`"down"`
      (per the official example). If a move misbehaves, try `"l"/"r"/"u"/"d"`.
- [ ] **Special workspaces:** `S`/`SHIFT+V`/`m`/`z` toggle terminal/volume/morgen/zoom;
      each `on_created_empty` launches its app.
- [ ] **Swallow:** `mainMod+SHIFT+T` toggle; `enable_swallow=false` so kitty
      shouldn't swallow by default.
- [ ] **cyclenext exec hack** (`mainMod+ALT+space`): shells out to `hyprctl
      dispatch cyclenext` — confirm that runtime dispatcher name still exists in
      0.55, else rewrite with `hl.dsp.window.cycle_next({ tiled=true })`.
- [ ] **Autostart on reload:** `hl.on("hyprland.start")` should fire only at
      start, not on `hyprctl reload` (exec-once semantics) — confirm a reload
      does NOT relaunch waybar/pipewire.

### Non-issue worth not re-chasing

`movefocus, l, visible, nowarp` in the old config (the `mainMod+CONTROL+arrow`
binds) → migrated to plain `hl.dsp.focus({ direction = "left" })`. The trailing
`visible`/`nowarp` were **never** valid `movefocus` parameters (it only consumes
the direction); hyprlang silently ignored them too. Dropping them is faithful,
not a regression — don't try to "restore" them.

Rollback: `rm ~/.config/hypr/hyprland.lua`, then logout/login to drop back to the
hyprlang manager and `hyprland.conf`. (Once you're already running under lua,
`hyprctl reload` re-reads the live `.lua` fine — the manager only gets chosen at
startup.)

---

## Post-migration gotchas (Hyprland 0.55+)

Three things bit during the laptop migration that the desktop didn't surface.
Apply all three when redoing this on another machine — and to the desktop too,
if applicable.

### Removed: `gestures.workspace_swipe` and `gestures.workspace_swipe_fingers`

The hyprlang `gestures { workspace_swipe = true; workspace_swipe_fingers = 3 }`
block became invalid in 0.55+. Setting either key produces:

```
unknown config key 'gestures.workspace_swipe'
unknown config key 'gestures.workspace_swipe_fingers'
```

The replacement is a new **top-level** `hl.gesture({...})` call (NOT inside
`hl.config`). From the wiki `Variables.md` footnote:

```lua
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})
```

The desktop's `gestures {}` block was commented out, so it never surfaced. The
laptop conf had `gesture = 3, horizontal, workspace` as a live top-level keyword
(unrelated to the section), which I translated to the call above.

The OTHER `gestures:*` keys (`workspace_swipe_distance`, `workspace_swipe_invert`,
etc.) still live inside `hl.config({ gestures = { ... } })`. It's specifically
the master toggle + finger count that moved.

### `Hyprland --verify-config` runs registered hooks

The dry-run is not as dry as the runbook above implied. During `--verify-config`,
Hyprland executes registered `hl.on(...)` callbacks — including `config.reloaded`.
Concrete observation from the laptop migration:

```
$ Hyprland --verify-config -c hyprland-laptop.lua
DEBUG: [executor] Executing hyprland-clamshell-restore
DEBUG: [executor] Process created with pid 13504
...
======== Config parsing result:
config ok
```

The `hyprland-clamshell-restore` script is wired via `hl.on("config.reloaded", ...)`
in the laptop config — and it ran during verification. For that specific
command it's harmless (no-ops fast when the clamshell inhibitor PIDFILE is
absent) but it's a real footgun: **never** wire destructive commands into
`config.reloaded`, `hyprland.start`, or similar hooks without considering that
they fire during `--verify-config` too.

For testing-only hooks during development: gate them behind an env var the live
session sets but `--verify-config` doesn't, e.g.:

```lua
hl.on("config.reloaded", function()
    if os.getenv("HYPRLAND_RUNNING") == "1" then
        hl.exec_cmd("hyprland-clamshell-restore")
    end
end)
```

…and have `start-hyprland` export `HYPRLAND_RUNNING=1` before `exec`'ing Hyprland.

### `config.reloaded` is the correct hook for "every reload" behavior

Under hyprlang we wired `hyprland-clamshell-restore` via `exec = …` (which fires
on every reload, vs `exec-once = …` which fires once at startup). The Lua
equivalent is **NOT** `hl.on("hyprland.start", …)` — that's exec-once semantics
and skips reloads. The correct event is `config.reloaded`, exposed by
`src/event/EventBus.hpp` and routed by `src/config/lua/LuaEventHandler.cpp`:

```lua
hl.on("config.reloaded", function() hl.exec_cmd("…") end)
```

`hyprland.start` and `config.reloaded` are the two compositor-lifecycle hooks
documented in `LuaEventHandler.cpp` so far. Other categories (window/workspace/
monitor/input/render/screenshare/keybinds/config:preReload) exist in the
EventBus but I haven't traced whether they're exposed to Lua yet — check
`LuaEventHandler.cpp`'s `dispatch("…", …)` calls before assuming an event name.

### Waybar workspace click regression (waybar #5008)

**Symptom:** After switching to the Lua config manager, clicking the workspace
buttons in waybar's `hyprland/workspaces` module no longer focuses that
workspace. The button highlights visually but the active workspace doesn't
change.

**Root cause: Hyprland-side, not waybar-side.** In `src/debug/HyprCtl.cpp::dispatchRequest`,
under Lua mode the IPC dispatch handler turns every incoming `dispatch X`
into the Lua expression `return hl.dispatch(X)` and evaluates it through the
Lua manager. Waybar's `Workspace::handleClicked` sends `dispatch workspace 2`,
which Hyprland turns into `return hl.dispatch(workspace 2)` — that's not valid
Lua (no comma between tokens). The Lua evaluation fails. **But the fallback
`.value_or("ok")` returns the literal string `"ok"`**, so Hyprland reports
success while doing nothing. This is also why
`hyprctl dispatch 'hl.dsp.exec_raw("workspace 2")'` reports ok but doesn't
focus: the Lua evaluation succeeds, but `exec_raw` doesn't actually run a
workspace dispatcher.

**The only IPC form that focuses under Lua mode:**

```sh
hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })'
```

**Why this can't be cleanly fixed at the waybar config level:** waybar's
`Workspace::handleClicked` is hardcoded to call `IPC::dispatch("workspace", id)`
— no config knob switches it to Lua syntax. `on-click` in waybar is a static
shell command **per module**, not per button, with no `{id}` substitution.
There's no way to inject the workspace ID into a click handler that wraps it
in `hl.dsp.focus({...})`.

**Tracking:** [waybar #5008](https://github.com/Alexays/Waybar/issues/5008)
(open as of 2026-06). A patched waybar (gulafaran's diff in the comments)
fixes it; expect upstream fix to ship in waybar 0.16+.

**Partial workaround — one shared block, applied and live-verified on BOTH machines
(2026-06-13).** `config-desktop.jsonc` and `config-laptop.jsonc` now carry the
**identical** `hyprland/workspaces` block. The functional fix is the two
`on-scroll-*` handlers — they use the only IPC form that focuses under Lua mode
(`hl.dsp.focus({...})`):

```jsonc
// waybar #5008: under Hyprland Lua config mode the built-in per-button click
// ("activate" -> `dispatch workspace N`) is wrapped as invalid Lua and silently
// no-ops, so workspace buttons don't switch. on-click is kept so clicks resume
// automatically when the upstream fix ships (>= waybar 0.16). Scroll-to-cycle
// below uses hl.dsp.focus({...}), the only IPC form that focuses under Lua mode.
// Direct jumps meanwhile: Super+1..0. See docs/hyprland-lua-migration.md.
"hyprland/workspaces": {
    "format": "{name}",
    "on-click": "activate",
    "sort-by-number": true,
    "all-outputs": true,
    "on-scroll-up":   "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e+1\" })'",
    "on-scroll-down": "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e-1\" })'",
}
```

`on-scroll-*` is per-module with shell substitution-free strings — a perfect fit
for static `hl.dsp.focus({...})` IPC calls. Result: **mouse-wheel cycling on the
bar works**; **per-button clicks remain broken** until waybar #5008 lands. We keep
`on-click: "activate"` (a no-op today) so per-button clicks resume automatically
the moment the upstream fix ships — no second config edit. `{name}` renders the
same as `{id}` for numbered workspaces.

**History note (corrected 2026-06-13):** an earlier draft of this runbook
described the workaround as already present in `config-laptop.jsonc`, but at the
time that file only listed the module in `modules-left` and inherited waybar
defaults (no scroll handlers); `config-desktop.jsonc` carried `on-click: "activate"`
with no handlers. The block first landed in each file in slightly different forms
(laptop `{id}`/no `on-click` in `43314bc`; desktop `{name}`/`on-click` alongside),
then was **unified to the single shared block above**. Live-verified on both
machines: desktop reloaded in place (`killall -SIGUSR2 waybar`, validated first),
laptop reloaded and tested. Mouse-wheel scroll-to-cycle confirmed working on
`godlike-artix` and `nomad-artix`.

**Workspace-switch UX under this regression:**

| Need | Working method |
|---|---|
| Jump to specific workspace | `Super + <N>` keyboard (Lua bind, unaffected) |
| Cycle next/prev | Mouse wheel on bar (partial workaround) or `Super+Ctrl+Alt+arrow` keyboard |
| Move window to workspace | `Super+Shift+<N>` (unaffected) |
| Switch via bar click | **Broken — waiting on upstream waybar #5008** |

If you're heavily reliant on bar clicks for navigation, the practical near-term
options are: (1) keyboard primary + scroll-on-bar as fallback (cheap, no
package burden), (2) build waybar from source with the patch (one package to
maintain across upgrades).

---

## In-situ laptop runbook (DONE 2026-06-13)

The laptop config (`hyprland-laptop.conf`) **differs** from desktop — do not
copy the desktop `.lua`. Re-run the process *on the laptop* so device-specific
bits (monitor, brightness keys, touchpad, lid) are handled live:

1. `ssh`/sit at `nomad-artix`. `hyprctl version` (expect ≥0.55), `hyprctl configerrors` clean.
2. **(actually used)** Skip the converter — start from `hyprland-desktop.lua`
   structure and patch in laptop-specific bits by hand. The converter's
   hand-correction tax has already been paid on the desktop; re-running it
   buys no new information and ships the same defects. Use `hyprconf2lua` only
   as a defense-in-depth check (bind count diff).
3. Hand-port from the desktop `.lua` with these laptop-specific watch items:
   - **Monitor** `eDP-1` + scale `1.25` (vs desktop's external + scale `1`).
   - **Touchpad** block under `input = { touchpad = { natural_scroll = true, drag_lock = 0 } }`.
   - **Gesture** — top-level `hl.gesture({ fingers, direction, action })`, NOT inside
     `hl.config`. See [post-migration gotchas](#removed-gesturesworkspace_swipe-and-gesturesworkspace_swipe_fingers).
   - **Brightness keys** (`XF86MonBrightnessUp/Down`) → `{ repeating = true }`
     (faithful translation of the original `bind=` not `bindl=`; add
     `locked = true` if you want dimming on lock screen).
   - **Lid switch** binds → `hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("…"), { locked = true })`.
   - **`config.reloaded` hook** for `hyprland-clamshell-restore` (replaces the
     hyprlang `exec = …` pattern, which has no Lua equivalent).
   - **Extra env vars** the desktop didn't have: `HYPRCURSOR_SIZE`,
     `QT_STYLE_OVERRIDE=Fusion`, `OZONE_PLATFORM`, `CHROMIUM_FLAGS`,
     `XCOMPOSEFILE`, `_JAVA_AWT_WM_NONREPARENTING=1` (desktop uses `=0`).
   - **No audio stack autostart** — laptop has pipewire/wireplumber/pipewire-pulse
     as OpenRC user services. Don't copy the desktop's autostart audio block.
   - **Volume keys**: upgraded `pactl` → `wpctl` to match the desktop pattern.
   - **Tailscale rofi bind** `Super+Shift+N` → `i3-tailscale-rofi`.
   - **Brave windowrules** incorporated from desktop (file/open/extension/idle).
4. Validate: `lua5.4 -e 'assert(loadfile("…/hyprland-laptop.lua"))'` then
   `Hyprland --verify-config -c …/hyprland-laptop.lua` → must print `config ok`.
   (Note: this fires `config.reloaded` hooks — see gotcha above.)
5. Bind count sanity check: source `bind*=` lines should equal Lua runtime binds
   (top-level `hl.bind(` count + submap binds + for-loop expansion).
6. Arm: `ln -sf /home/jim/projects/dotfiles/.config/hypr/hyprland-laptop.lua ~/.config/hypr/hyprland.lua`
   (absolute target; keep `.conf`).
7. **Patch the waybar config** for the workspace-click regression — see
   [waybar regression](#waybar-workspace-click-regression-waybar-5008).
8. **Logout/login** (not `hyprctl reload` — manager change), then walk the
   [runtime verification](#runtime-verification-only-a-live-session-can-confirm)
   — Pass 1 (introspection) confirms the bulk, Pass 2 (keypresses) the rest.
9. Once both machines are solid for a while, retire the `.conf` files.

---

## Artifacts

- Final desktop: `dotfiles/.config/hypr/hyprland-desktop.lua` (armed via
  `~/.config/hypr/hyprland.lua` symlink on `godlike-artix`; `.conf` kept for rollback).
- Final laptop: `dotfiles/.config/hypr/hyprland-laptop.lua` (armed via
  `~/.config/hypr/hyprland.lua` symlink on `nomad-artix`; pending logout/login
  to switch managers).
- Waybar workaround for the click regression: applied to BOTH
  `dotfiles/.config/waybar/config-desktop.jsonc` and `config-laptop.jsonc`
  (2026-06-13) — a `hyprland/workspaces` block with scroll-to-cycle Lua-form
  dispatchers. Live-verified on both machines: scroll-to-cycle confirmed working
  on desktop and laptop.
- Scratch (ephemeral): `/tmp/hypr-lua-migration/` — raw converter `out.lua`,
  official `example/hyprland.lua`, wiki markdown sources, `report.txt`, and the
  verification helpers `dump_binds.py` / `check_options.py` (rebuild on the
  laptop from the Pass-1 recipe above; `/tmp` doesn't survive a reboot).
