# Hyprland dwindle switch + i3 split/move bind port (2026-08-29)

**Machine:** `godlike-artix` live Hyprland session (0.56.1), same day as the
unified-config landing (`2026-08-29-hyprland-unified-config-design.md`) and the
rofi-parity pass (`2026-08-29-hyprland-rofi-parity-and-ydotool.md`).
**Scope:** Fleet-wide (both machines — layout is a global preference, not
per-machine). **Verdict: dwindle KEPT** after a live A/B against master.

## 1. Why now

Two i3 reflexes had no home under the prior Hyprland setup:

1. *"Open the next window as a vertical vs horizontal split"* (i3 `split v` /
   `split h`).
2. *"Move a whole group left/right/up/down as a block"* (i3 `move` on a tabbed
   container).

Both are i3 muscle memory. Neither worked — and the root cause was a layout
mismatch nobody had noticed: the config declared `general:layout = "master"`.

## 2. The reframe — master has no splits

The single most important fact, verified against the wiki source
(`hyprwm/hyprland-wiki`, `content/configuring/layouts/{master,dwindle}-layout.md`,
pulled via `gh` because the live site bot-blocks WebFetch with 403):

- **`master`** is a master-area + slave-stack layout. It has **no per-window
  split concept at all.** Its only spatial knob is whole-workspace
  `orientation{left,right,top,bottom,center}` / `orientationnext` / `orientationcycle`
  — far coarser than "this next window goes below vs beside."
- **`dwindle`** is a BSPWM-like binary tree. It has the exact i3 primitive:

  | dwindle `layoutmsg` | behavior |
  |---|---|
  | `preselect <dir>` | *one-time* override for the NEXT window's split side (l/r/u/t/d/b) — this **is** i3 `split h`/`split v` |
  | `togglesplit` | flip an existing window's split axis (requires `preserve_split`) |
  | `swapsplit` / `rotatesplit` | swap / rotate the split |
  | `movetoroot` | promote a window to the root of its workspace subtree |

  Quirk worth remembering: *dwindle splits are NOT permanent* by default — the
  split axis is re-derived from the parent node's W/H ratio on every change (W>H
  side-by-side, H>W top-and-bottom). `preserve_split = true` makes them stick,
  and it is **required** for `togglesplit` to do anything. We set it.

So point 1 was never a keybind gap — it was a **layout** gap. Fixing it meant
switching the active layout to dwindle.

## 3. The A/B mechanism (one switch, complete swap)

`vars.lua` gained a single selector:

```lua
layout = "dwindle",   -- A/B: flip to "master" to revert
```

- `looknfeel.lua` reads `general.layout = v.layout`, and **both** layout config
  blocks (`hl.config({ dwindle = { preserve_split = true } })` and
  `hl.config({ master = {} })`) are defined unconditionally, so flipping the one
  value is a genuine full swap with nothing left dangling.
- `bindings.lua` gates the layout-specific binds on `v.layout`: dwindle gets the
  split binds; master keeps `swapwithmaster` (which has no dwindle analog).

Revert is: flip that one string, `hyprctl reload`. That is the whole A/B.

## 4. The i3 -> dwindle translation (all on the exact i3 chords)

Read straight off `dotfiles/.config/i3/config-desktop` — the Hyprland chords were
all free, so zero relearning:

| i3 (`config-desktop`) | Hyprland dwindle | Chord |
|---|---|---|
| `$mod+h` -> `split h` (next window beside) | `hl.dsp.layout("preselect r")` | `Super+h` |
| `$mod+v` -> `split v` (next window below) | `hl.dsp.layout("preselect d")` | `Super+v` |
| `$mod+Shift+e` -> `layout toggle split` | `hl.dsp.layout("togglesplit")` | `Super+Shift+e` |
| `$mod+g` -> `layout tabbed` | `hl.dsp.group.toggle()` (already bound) | `Super+g` |
| `$mod+Shift+arrows` -> `move` | plain `window.move({direction})` | `Super+Shift+arrows` |
| `$mod+a` / `$mod+Shift+a` -> `focus parent/child` | **no equivalent** | — |

## 5. The move family — three distinct verbs

Point 2 exposed that Hyprland splits into three separate operations what i3 folds
into fewer. The key fact (dispatchers page): **"A group is like i3wm's *tabbed*
container. It takes the space of one window."** A group is a single tile node, so
moving that node moves the whole group. Final binds:

| Chord | Operation | Dispatcher |
|---|---|---|
| `Super+Shift+←↑↓→` | move window / whole group as a **block** | `window.move({ direction })` (no `group_aware`) |
| `Super+Ctrl+Shift+←↑↓→` | move window **into / out of** the adjacent group | `window.move({ direction, group_aware = true })` |
| `Super+Alt+Ctrl+←/→` | reorder within a group's **tab order** | `group.move_window({ forward })` |

The original port had `Super+Shift+arrows` bound with `group_aware = true`, which
is a Hyprland-ism (pull windows in/out of adjacent groups) that does **not** match
i3's plain `move`. Switching it to plain move restored i3 parity **and** delivered
the "move the whole group as a block" ask in one change. The in/out behavior
wasn't lost — it moved to its own chord (`Super+Ctrl+Shift+arrows`), which is
layout-agnostic (works under master too).

## 6. The one i3 thing that does NOT port

`$mod+a` / `$mod+Shift+a` (`focus parent` / `focus child`). Hyprland has **no**
arbitrary-subtree selection — you cannot grab an interior tree node (a 2x2
quadrant, say) and address it the way i3 lets you climb the container tree. Only
**tabbed groups** are addressable as a unit; `movetoroot` is the only interior-tree
primitive. If a workflow depended on i3's `focus parent`, that specific muscle
memory has no home here. (Named honestly rather than papered over — verify, not
folklore.)

## 7. Verification

- Offline harness (`dotfiles/.config/hypr/tests/`) extended: `test_looknfeel.lua`
  asserts `layout == "dwindle"` + `preserve_split` on both machine branches and
  that the `master` block is still defined (revert path); `test_bindings.lua`
  gained a `dsp_of()` dispatcher extractor and asserts `preselect r`/`preselect d`/
  `togglesplit`, plain move with NO `group_aware`, the group-aware in/out chord,
  and the absence of `swapwithmaster` under dwindle. All 10 tests green from both
  machine branches.
- Live: `hyprctl reload` clean (empty `configerrors`), `general:layout` reports
  `dwindle`, every new bind present via `hyprctl binds` (shown as `__lua <n>` —
  Lua mode wraps binds in callbacks, so live introspection cannot show the
  dispatcher string; the offline harness pins the exact dispatcher+args instead).
- Functional A/B driven by hand on ws10: grouped Messages/WhatsApp + Discord/Keybase
  into a two-group comms wall using only `Super+g` + the new move binds — the exact
  structure the prior (master) Hyprland setup structurally could not build, and i3
  did trivially.

## 8. Next

The hand-built comms wall proves the primitives for a scripted **"Launch Chats"**
now exist under Hyprland (the deferred item — an i3 `append_layout`-style
auto-builder ported to a Wayland-native window-system branch). Brainstorm before
building. See the project's Launch Chats memory.

## 9. Follow-up (2026-09-02): `Super+left/right` boundary escape

The original `focus_or_group` was binary: in a multi-window group it ALWAYS
cycled tabs (wrapping), else directional focus. That trapped focus inside a group
whenever a non-group window shared the row (e.g. a terminal beside the ws10
Messages/WhatsApp group): you could focus INTO the group but never back OUT —
**the real issue was simply that there was no keyboard escape to the terminal
once a group was focused.** i3's `focus left/right` escapes a tabbed container at
its edge; ours didn't.

The result is **i3-inspired, and — verified live against a real i3 under the
SAME setup (Jim A/B-tested 2026-09-02) — identical to i3 for practical
purposes.** "Good enough" undersold it; it's on par with i3.

(A first draft of this doc listed two "deviations from i3" — an isolated group
wrapping its tabs at the edge, and a plain window at the row's end wrapping via
raw `movefocus`. Those were asserted from *memory* of i3's `focus_wrapping`
semantics and were never checked against a live i3. The A/B test contradicted
them: same behavior where it counts. Kept here only as a note — a ground-truth
test beats a remembered spec. The escape was the point, and it matches i3.)

Fixed by adding boundary detection with a **geometric neighbor test** (see
`bindings.lua` `has_neighbor` / `focus_or_group`, and the CLAUDE.md Architecture
+ Common Issues entries):

- In a group, interior -> cycle tab (`group.next/prev`).
- At the edge in `dir` **with** a real adjacent tile on that side -> `focus({direction})`
  escapes the group to it.
- At the edge **without** a neighbor -> cycle (wrap) — preserves the isolated
  comms-wall feel (a lone group still wraps its tabs).

`current_index` is 1-based; `next`=idx+1/wrap, `prev`=idx-1/wrap; `members[]` is
left->right tab order (v0.56.1 `LuaGroup.cpp` + `ConfigActions.cpp::changeGroupActive`
-> `CGroup::moveCurrent`).

**Key gotcha that shaped the implementation** (now also in CLAUDE.md Common
Issues): Hyprland's `movefocus` does NOT reliably no-op when nothing is in the
requested direction — probed live, `focus({direction="left"})` from a group with
no left-neighbor grabbed the group *below* (off-axis), and whether it moved
depended on focus history. So "dispatch focus, did the active window change?" is
NOT a sound neighbor test; `has_neighbor` computes adjacency itself from
`hl.get_workspace_windows(ws)` + `.at`/`.size` (vertical-overlap band for
left/right). Escape is gated on that; `movefocus` is reliable once a real
in-direction candidate exists.

Verified live 2026-09-02 with synthesized `Super+arrow` keystrokes (ydotool)
against the deployed bind, across a 9-scenario matrix (both ws10 groups + the
terminal): escape, cycle, wrap, and enter-from-plain-window all correct. The
bottom Discord/Keybase/Slack group (no vertically-overlapping neighbor) correctly
keeps wrapping. Desktop live; **laptop inherits via `git pull` + reload** — the
logic is geometry-driven and machine-agnostic, so no laptop-specific tuning is
expected.
