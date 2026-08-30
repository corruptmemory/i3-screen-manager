# Wayland "Launch Chats" — the comms-wall auto-builder under Hyprland (2026-08-29)

**Machine:** `godlike-artix`, live Hyprland session (0.56.1), same day as the
dwindle switch (`2026-08-29-hyprland-dwindle-switch-and-i3-move-binds.md`) — which
is what made this possible: dwindle's group primitives are what a scripted build
needs.
**Scope:** Desktop (the comms wall is ws10, desktop-only; the laptop defers a
comms design). Fleet-safe: the dispatcher and the self-hiding rules are harmless
on the laptop.
**Status:** BUILT + verified live (idempotent-regroup path, build-from-scratch
path, and launch-missing path all exercised).

Resolves the deferred "port i3's Launch Chats to Hyprland" item. The primitives
only existed once the box moved to dwindle — under the old master layout you
could not build the two-group wall at all.

## 1. Why the i3 approach does not port

i3's `i3-chat-layout` lays down a `chat-layout.json` skeleton via `append_layout`:
five empty placeholder containers (a `splitv` of two tabbed groups) each carrying
a `swallow` criterion. It then launches the apps and i3 SWALLOWS each new window
into its slot. This is **declarative and async-safe** — order of arrival does not
matter, and the shuffle is invisible because the slots pre-exist.

**Hyprland has no `append_layout` and no swallow-into-placeholder.** So the
Wayland build is necessarily **imperative**: launch what is missing, wait for the
windows to map, then dispatch group operations to assemble the structure. The
visible consequence is the "self-assembling puzzle having a seizure" — windows
splat onto the monitor wherever dwindle tiles them, then get sucked into place.
Declarative-atomic (i3) vs imperative-after-the-fact (Hyprland); the jank is
architectural, not a bug.

## 2. The finding that made it tractable — unique Wayland classes

The single hardest part of the i3 version is telling the two Brave PWAs apart:
under X11 both share `res_class` "Brave-origin", so `i3-chat-layout` matches them
by the `crx_<app-id>` **instance**. Under Wayland that problem **evaporates** —
Brave bakes the app-id straight into the class:

| App | Wayland class (verified via `hyprctl clients -j`) |
|---|---|
| Messages | `brave-hpfldicfbfomlpcikngkocigghgafkph-Default` |
| WhatsApp | `brave-hnpfjngllnobngcgfapefoaidbinmjnm-Default` |
| Slack | `slack` |
| Keybase | `Keybase` |
| Discord | `discord` |

Every app has a unique, stable class, so every window is deterministically
selectable by class alone (`focus -> class:...`). No instance juggling, no title
matching. This is what turns "async + ambiguous identity" into "poll until
present, then group by class."

## 3. Design (approved) — grouped, arrangement flexible

Target: two tabbed groups on ws10 — `Messages | WhatsApp` and
`Discord | Slack | Keybase` — but the exact top/bottom placement and split ratio
are **whatever dwindle yields**. Dropping the exact-split requirement removes all
the brittle directional sequencing; the two groups are what matter.

## 4. The pieces

- **`hypr-chat-layout`** (dotfiles `.local/bin/`) — the Wayland builder:
  1. **Launch only what is missing** (per-class `hyprctl clients` check).
  2. **Wait** until all five are mapped (bounded 25s; Electron/PWA cold start).
  3. **Move stragglers to ws10** (silent), belt-and-suspenders over the rules.
  4. **Group by class** — for each group, merge members into an anchor via
     `window.move({ into_or_create_group = <dir> })`, where `<dir>` is computed
     from live window coordinates and **retried** (in a multi-window tree the
     first directional step can land on a between-neighbor; re-reading position
     and re-dispatching converges), guarded by an `in_same_group` check.
  5. Return to the workspace that was active at start.
- **`i3-chat-launch`** (dotfiles `.local/bin/`) — session dispatcher: X11 ->
  `i3-chat-rebuild` (unchanged), Wayland -> `hypr-chat-layout`. `launch-chats.desktop`
  points here. Named with the `i3-` prefix for rofi/muscle-memory consistency
  (same as `i3-screen-manager` being the Wayland-capable tool).
- **`rules.lua`** — two ws-pin rules (`msg-pwa-messages`, `msg-pwa-whatsapp`) for
  the PWAs, using their unique Wayland classes (the X11 config could not pin them
  — shared class). Same ws as `msg-apps` (desktop 10 / laptop 1).

## 5. Idempotent by REGROUPING, not by killing

The i3 rebuild (`i3-chat-rebuild`) must KILL the apps first, because
`append_layout` only swallows windows created AFTER the skeleton drops — a
re-run on already-open windows just focuses them. **Hyprland has no such
limitation**: it regroups live windows. So `hypr-chat-layout` never kills — it
launches only what is missing and regroups whatever is present. The
`in_same_group` short-circuit makes a re-run on an already-correct wall a
complete no-op. Hitting "Launch Chats" repeatedly is safe and non-destructive —
no Electron kill dance, no lost chat state.

## 6. Verification (live)

- **Idempotent path:** ran against the already-built wall -> both groups
  unchanged, no window moved (every `merge_into` short-circuited). Exit 0.
- **Build path:** dissolved all groups (`out_of_group` on each), then ran ->
  the two groups reconstructed exactly (`Messages+WhatsApp`, `Discord+Slack+Keybase`).
- **Launch-missing path:** full teardown + run rebuilt the wall from nothing.

## 7. The one i3 capability with no Hyprland home

Same as the dwindle doc's §6: Hyprland has no `focus parent` / arbitrary-subtree
selection. Only tabbed groups are addressable as a unit. That is fine here — the
comms wall is exactly two tabbed groups.

## 8. Notes

- All hyprctl dispatches use the Lua-call form (`hl.dsp.*(...)`) — the bareword
  form is dead under Lua mode (see CLAUDE.md Common Issues).
- Tool-guarded inline (`command -v`); poll timeout -> `notify-send -u critical`
  (the fleet silent-failure guard). No shared `require.sh` symlink on the desktop.
- Laptop deferral stands (its comms design is still cooking); the dispatcher and
  the self-hiding rules are harmless there.
