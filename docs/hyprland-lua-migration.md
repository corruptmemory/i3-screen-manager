# Hyprland hyprlang → Lua config migration

**Status:** Desktop (`godlike-artix`) migrated, validated, and **live-verified
against the old config** 2026-06-09 — running under the lua manager with full
parity (see [verification](#runtime-verification-only-a-live-session-can-confirm)).
Laptop (`nomad-artix`) pending — follow the [in-situ laptop runbook](#in-situ-laptop-runbook).

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

## In-situ laptop runbook

The laptop config (`hyprland-laptop.conf`) **differs** from desktop — do not
copy the desktop `.lua`. Re-run the process *on the laptop* so device-specific
bits (monitor, brightness keys, touchpad, lid) are handled live:

1. `ssh`/sit at `nomad-artix`. `hyprctl version` (expect ≥0.55), `hyprctl configerrors` clean.
2. `pipx install hyprconf2lua`.
3. `hyprconf2lua --report ~/projects/dotfiles/.config/hypr/hyprland-laptop.conf -o /tmp/lap.lua`
   — if it dies on a comma-in-value, sentinel it (defect #1) and re-run.
4. Hand-correct against the [defect list](#converter-defects-hyprconf2lua-v130--what-to-hand-fix).
   Laptop-specific watch items the desktop didn't have:
   - **Brightness keys** (`XF86MonBrightnessUp/Down`) → `{ locked = true, repeating = true }`.
   - **Lid switch** binds → `hl.bind("switch:on:[name]", …, { locked = true })`.
   - **Touchpad** block under `input = { touchpad = { … } }`.
   - **Monitor** likely `eDP-1` + scale; preserve the laptop's value.
5. Validate: `lua5.4 -e 'assert(loadfile("…/hyprland-laptop.lua"))'` then
   `Hyprland --verify-config -c …/hyprland-laptop.lua` → must print `config ok`.
6. Arm: `ln -sf /home/jim/projects/dotfiles/.config/hypr/hyprland-laptop.lua ~/.config/hypr/hyprland.lua`
   (absolute target; keep `.conf`).
7. **Logout/login** (not `hyprctl reload` — manager change), then walk the
   [runtime verification](#runtime-verification-only-a-live-session-can-confirm)
   — Pass 1 (introspection) confirms the bulk, Pass 2 (keypresses) the rest.
8. Once both machines are solid for a while, retire the `.conf` files.

---

## Artifacts

- Final: `dotfiles/.config/hypr/hyprland-desktop.lua` (armed via
  `~/.config/hypr/hyprland.lua` symlink; `.conf` kept for rollback).
- Scratch (ephemeral): `/tmp/hypr-lua-migration/` — raw converter `out.lua`,
  official `example/hyprland.lua`, wiki markdown sources, `report.txt`, and the
  verification helpers `dump_binds.py` / `check_options.py` (rebuild on the
  laptop from the Pass-1 recipe above; `/tmp` doesn't survive a reboot).
