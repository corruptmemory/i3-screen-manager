# Hyprland laptop workspace split, clamshell disconnect fix, and adjacent hardening

**Date:** 2026-08-31
**Scope:** `nomad-artix` (laptop) primarily, with fleet-wide changes flagged.
**Origin:** Session that started with "when a second monitor is attached and NOT in clamshell mode, the workspace split should be 1-6 on the laptop screen and 7-10 on the attached monitor" and grew to cover a cascade of related Hyprland gotchas.

## What landed

Ten commits across two repos, in chronological order:

| Commit | Repo | Subject |
|---|---|---|
| `27fc26c` | i3-screen-manager | fix(i3-screen-manager): PRIME hookup must swallow xrandr stdout too |
| `2c7cd02` | dotfiles | feat(hyprland-laptop): dynamic workspace split — 1-6 internal, 7-10 external |
| `af94b23` | i3-screen-manager | feat(i3-screen-manager): apply Hyprland workspace split on extend |
| `9832156` | dotfiles | fix(quickshell): WindowTitle is per-monitor, not globally-focused window |
| `ece3762` | i3-screen-manager | fix(i3-screen-manager): clamshell→disconnect no longer blanks screens |
| `daee2a0` | i3-screen-manager | feat(i3-screen-manager): auto-apply ws split + harden Hyprland dispatchers |
| `de9618d` | dotfiles | feat(hyprland-laptop): auto-apply ws split on monitor.added + qs toplevel refresh |
| `90e316c` | dotfiles | fix(quickshell): periodic refreshToplevels — one-shot wasn't enough |
| `cffc29c` | dotfiles | feat(hyprland): confine Super+arrow focus to current monitor |
| `83a5caa` | i3-screen-manager | fix(scale): default target = focused monitor, not always internal |

## The workspace split (feature)

**Goal:** on the laptop, when both monitors are up, confine workspaces 1-6 to `eDP-1` and 7-10 to the external. In clamshell (or with the internal disabled), all 10 land on the external. Laptop-only keeps all 10 on `eDP-1`.

**Implementation surfaces:**

1. **`dotfiles/.config/hypr/machine.lua`** — the laptop entry declares intent as data:
   ```lua
   monitors = {
     internal = { output = "eDP-1", ... },
     internal_workspaces = { 1, 2, 3, 4, 5, 6 },
     external_workspaces = { 7, 8, 9, 10 },
     default_ws = 1,
   },
   ```
   SSOT for the split values. The same numbers are duplicated in `shell.qml`'s `poolFor` and in `i3-screen-manager`'s `EXTERNAL_WORKSPACES` bash constant.

2. **`dotfiles/.config/hypr/monitors.lua`** dynamic branch bakes persistent `hl.workspace_rule` entries for ws 1-10 rooted on `eDP-1`. `persistent = true` guarantees the workspaces exist as soon as `eDP-1` is available, so downstream `hl.dsp.workspace.move({...})` dispatchers never hit "Workspace not found".

3. **`i3-screen-manager` `EXTERNAL_WORKSPACES=(7 8 9 10)`** + a helper `apply_ws_split_wayland` that iterates and dispatches `hl.dsp.workspace.move({ workspace = "N", monitor = "$ext" })`. Called at the end of `cmd_extend_wayland`.

4. **`i3-screen-manager apply-ws-split`** — a new Wayland-only, idempotent subcommand that finds the external and applies the split. Silent no-op when there's no external. This is the entry point for the automated path (below).

5. **Auto-apply on boot AND hot-plug via `autostart.lua`:**
   ```lua
   if m.traits.clamshell then
     hl.on("monitor.added", function() hl.exec_cmd("i3-screen-manager apply-ws-split") end)
   end
   -- Belt-and-suspenders fallback inside hyprland.start:
   if m.traits.clamshell then
     hl.exec_cmd("sleep 3 && i3-screen-manager apply-ws-split")
   end
   ```
   `monitor.added` fires per-monitor at boot AND when a monitor is hot-plugged during a session. The sleep-3 fallback covers the race where the first `monitor.added` fires before the persistent workspaces have instantiated.

6. **Quickshell `shell.qml`** — the bar's per-monitor workspace pool became dynamic:
   ```qml
   function poolFor(name) {
       if (pools[name]) return pools[name]           // desktop's static DP-2 / HDMI-A-1
       var screens = Quickshell.screens              // reactive read
       var hasEDP = /* check for eDP-1 */
       if (name === "eDP-1")
           return (screens.length > 1) ? [1..6] : [1..10]
       return hasEDP ? [7..10] : [1..10]             // unknown external
   }
   ```
   The desktop's static `DP-2 → [1-6] / HDMI-A-1 → [7-10]` entries stay. The laptop's `eDP-1` and dynamically-named externals fall through to the reactive logic.

## The clamshell→disconnect blank-screen bug

**Symptom:** exiting clamshell mode via `disconnect` blanked BOTH screens. Hyprland required a full restart to recover. Reported live, reproduced twice.

**Root causes (two, stacked):**

1. **`hl.monitor` does NOT auto-enable a disabled monitor.** Passing `mode`/`position`/`scale` alone leaves a previously-disabled monitor OFF. You must pass `disabled = false` explicitly. Without it, the disconnect sequence left `eDP-1` disabled (from clamshell entry) AND then disabled the external — Hyprland's `FALLBACK` placeholder monitor activated → both screens black.

2. **Two monitors cannot share position `0x0`.** Hyprland quietly refuses one of them. The old disconnect sequence enabled internal at `position=auto`, moved workspaces, disabled external, then **repositioned internal to `0x0`** — but external's Hyprland-side position was still `0x0` (disabled ≠ removed from state), so the reposition collided.

**Fix:** rewrote `cmd_disconnect_wayland` to:
1. Stash the external at `10000x0` FIRST (frees its `0x0` slot).
2. Put internal at `0x0` in one shot, with explicit `disabled = false`.
3. Move workspaces from external to internal.
4. Disable external (`disabled = true` + `wlr-randr --off`).

Every re-enabling `hl_apply` in the script now carries `disabled = false`:
```
extend_wayland     — internal, external (all four directions)
clamshell_wayland  — external (auto position and 0x0 position)
mirror_wayland     — internal, external
disconnect_wayland — external (stash), internal, no-ext branch
```

**Verified live:** full extend → clamshell → disconnect cycle now returns cleanly to `eDP-1` at `0x0`, `HDMI-A-2` disabled at `10000x0`, no FALLBACK, no restart needed.

## The hyprctl-live wrapper

`i3-screen-manager` had ~15 bare `hyprctl` callsites. When invoked from a shell that outlived a Hyprland restart (agent sessions, herdr-hosted terminals, tmux panes older than the compositor), `HYPRLAND_INSTANCE_SIGNATURE` points at the dead socket and every bare `hyprctl` silently no-ops. The script would "run" without doing anything.

**Fix:** a one-line shell function at the top of `i3-screen-manager`:
```bash
hyprctl() { command hyprctl-live "$@"; }
```
Routes every call through `hyprctl-live`, which rediscovers the live signature on each invocation via `hyprctl instances -j` (which doesn't need a valid sig — it enumerates `$XDG_RUNTIME_DIR/hypr` directly). In-session callers pay a cheap `ls`; stale-env callers get a working command instead of silence.

## WindowTitle per-monitor + Quickshell toplevel refresh

**Bug:** WindowTitle showed the SAME globally-focused window's title on every monitor's bar, regardless of what workspace that monitor was actually displaying.

**Fix (dotfiles `9832156`):** WindowTitle now takes a `screenName` property, matches it against `Hyprland.monitors.values` to find the monitor's `activeWorkspace`, and filters `Hyprland.toplevels.values` to those with `t.workspace.id === activeWorkspace.id`. Prefers the activated toplevel, else the last matching one.

**Follow-up bug (dotfiles `90e316c`):** `Hyprland.toplevels` starts EMPTY on qs startup — Quickshell only sees toplevels that opened via `socket2` events since it connected. Pre-existing windows have `ws=-1`, `monitor=null`. Additionally the associations can go stale after `hl.dsp.workspace.move` dispatchers. Fix: a periodic `Hyprland.refreshToplevels()` every 3s in `shell.qml` keeps the state fresh.

## Fleet-wide binds change

`binds.window_direction_monitor_fallback` defaults to `true` — `hl.dsp.focus({direction=...})` crosses monitor boundaries when there's no window in that direction on the current monitor. Same surprising behavior we fixed under i3 as `f8e30d5`.

Set to `false` in `bindings.lua`:
```lua
hl.config({ ["binds.window_direction_monitor_fallback"] = false })
```
Fleet-wide (both machines pass through this config). Cross-monitor moves stay available via explicit dispatchers (Super+N for workspace, Super+Shift+arrow for move-window, etc).

## Scale picker targets focused monitor

`cmd_scale` was hard-coded to `$INTERNAL` when no target was given, so Super+Alt+BackSpace always adjusted the laptop's scale even when invoked from the external monitor. Now defaults to the focused Wayland monitor (via `hyprctl monitors -j '.[] | select(.focused) | .name'`), falling back to `$INTERNAL` if none focused or under X11.

## Hyprland Lua-mode facts learned along the way

Full list captured in `~/.claude/projects/-home-jim-projects-i3-screen-manager/memory/project_laptop_display_chain.md` for future sessions. Highlights:

- **All `hl.on` events**: `hyprland.start`, `hyprland.shutdown`, `config.reloaded`, `config.props_refreshed`, `monitor.added`, `monitor.removed`, `monitor.focused`, `monitor.layout_changed`, `workspace.created`, `workspace.removed`, `workspace.active`, `workspace.special_active`, `workspace.move_to_monitor`, `window.open`, `window.open_early`, `window.close`, `window.destroy`, `window.move_to_workspace`, `window.update_rules`, `window.class`, `window.title`, `window.fullscreen`, `window.pin`, `window.active`, `window.urgent`, `window.kill`, `layer.opened`, `layer.closed`, `input.keyboard.key`, `screenshare.state`, `keybinds.submap`.
- **Runtime config setting**: `hl.config({ ["dotted.path.to.option"] = value })` — see the wiki's [Dynamically changing a config option](https://wiki.hypr.land/) section. Works both at load time and inside a bind function.
- **`hl.bind` accepts Lua functions** (not just dispatcher objects) — enables compound actions.
- **Dispatcher table forms**: `hl.dsp.focus({workspace|monitor|direction|window|last|urgent_or_last|urgent})`, `hl.dsp.workspace.move({workspace, monitor})`, `hl.dsp.cursor.move({x, y})`. The bare-string classical form `hyprctl dispatch <verb> <args>` is dead under Lua mode.
- **`hl.dsp.focus({monitor = X})` ALSO warps the cursor** to the newly focused monitor. That's why Super+N cross-monitor works cleanly (via `hl.dsp.focus({workspace = N})`, which under the hood focuses the workspace's monitor).
- **`hl.dsp.workspace.move` silently fails** on disabled target monitors and on nonexistent workspaces — hence the persistent workspace_rules that pre-create ws 1-10.

## Known cosmetic issue (not fixed)

When `HDMI-A-2` comes up (extend or hot-plug), Hyprland auto-creates a fresh workspace (typically `wsN+1` beyond the persistent set, e.g. ws 11) as external's active workspace BEFORE `apply-ws-split` moves 7-10 over. The orphan is empty non-persistent; disappears when you first focus one of ws 7-10. Fixing it would require a briefly-focus-then-restore step in `apply-ws-split`, which would flicker keyboard focus. Left as-is — trivial to clean by pressing `Super+7`.

## Untested: physical unplug + replug

Simulated via `hl.monitor({disabled = true/false})` and the `monitor.added` hook fires as expected. Actual physical hot-plug not exercised in this session.

## Deployment

All ten commits are on `master` of their respective repos and pushed. Symlinks (`~/.config/hypr` → dotfiles, `~/.config/quickshell` → dotfiles, `~/.local/bin/i3-screen-manager` → i3-screen-manager) mean changes are live on the source machine as soon as they land. Other machines pick up via `git pull` + Hyprland reload.

**Fleet applicability:**

| Change | nomad-artix (laptop) | godlike-artix (desktop) |
|---|---|---|
| Workspace split feature | yes (main target) | no-op (static workspaces already declared) |
| Clamshell/disconnect fixes | yes | no-op (no clamshell trait, path not exercised) |
| hyprctl-live wrapper in i3-screen-manager | yes | yes (harmless — pays cheap ls per call) |
| WindowTitle per-monitor | yes | yes (was showing wrong title on both monitors before) |
| shell.qml periodic refreshToplevels | yes | yes |
| Super+arrow monitor confinement | yes | yes |
| Scale picker → focused monitor | yes | yes |
| xrandr stdout-leak fix | yes | n/a (no PRIME provider under X11) |
