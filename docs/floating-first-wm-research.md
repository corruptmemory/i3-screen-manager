# Floating-First WM Research Notes

Research date: 2026-06-07
Status: Decision pending — captured for cogitation, not committed.

Companion docs (background, do not duplicate):
- `docs/wayland-compositor-comparison.md` (2026-03-31) — field survey
- `docs/niri-evaluation.md` (2026-03-31) — why Niri was eliminated as Plan B
- `docs/hyprland-migration.md` — current Hyprland setup

This document captures a *philosophical* re-evaluation, not a fresh survey. The March 2026 comparison treated the question as "which tiling WM should I use." This document treats the question as: **was tiling the right choice at all?**

---

## Why this conversation happened

Hyprland's tiling-first model has been generating friction in workflows that aren't terminal+editor-shaped. Concrete examples that motivated the re-think:

- **Games with "preferred" window sizes** (e.g. `~/projects/game-bootstrap`) get force-fit into tile slots by the WM rather than the size the application wants. Per-window rules in `hyprland.conf` are a band-aid, not a solution — and the band-aid has to be re-applied for every project.
- **KiCad and similar X11 multi-window apps** assume floating tool palettes that the WM positions globally. Wayland forbids global positioning; tiling compositors make this worse by force-tiling.
- **Application-shape mismatch in general:** a tiled layout *should be* an ad-hoc choice per workspace, not a universal default.

Core observation: **stacking window managers are a strict superset of tiling functionality.** Tiling is a layout strategy you can opt into; floating is the more general primitive you can opt out of.

## Original ask

A floating-first WM that supports:

1. **Per-workspace tile/float toggle**, defaulting to float (AwesomeWM model).
2. **Snap zones** for floating windows (Windows-style edge tiling, but better).
3. **Window grouping** for floating windows.

## Corrections made during the conversation

These reframings need to be remembered when re-reading this document later:

### Special workspaces (Zoom, Morgan) are correct UX, not a misuse

Initial assistant framing was that the Zoom-overlay-misbehavior and Morgan-can't-cut-and-paste problems were caused by the "overlay" workspace pattern, and that putting these apps on regular workspaces would fix them.

**That framing is wrong.** Morgan-as-overlay solves "check schedule without leaving current context" — a dedicated workspace forces a context switch and defeats the purpose (99% read, 1% write). Zoom-as-overlay is a *containment strategy* against Zoom's notorious habit of decorating every workspace with floating "YOU'RE IN A MEETING" widgets — boxing it in is correct, not wrong. Zoom is a guest in the user's home; the user gets to dictate how it behaves.

The overlay-vs-tiled friction (clicking through to underlying windows while overlay is up, link-handling spawning invisible Zoom in special workspace) is **a real cost of containment**, not evidence the containment is wrong.

### X11's per-monitor DPI is fundamentally broken — this is the real dealbreaker

The earlier "X11 loses HDR, animations, fractional scaling" framing understated the actual cost. On Jim's laptop (multi-monitor with mixed DPIs), X11 enforces **one DPI for all screens, period**. Wayland fixes this natively. This is not a polish issue, it's a workflow-blocking issue.

XLibre is the watch item but doesn't yet help on this specific axis — see XLibre status below.

### River is no longer a tiler

The March 2026 comparison treats river as a "dynamic tiling Wayland compositor." That's out of date. River has evolved into something closer to "WM-construction toolkit" — it provides APIs/protocols for building arbitrary window managers under Wayland, analogous to X11's old WM libraries. It's no longer a turn-key tiler.

(This means a future "build my own floating WM on river" path *exists in principle*, but it's a much larger commitment than configuring an existing WM.)

### Niri's xwayland-satellite is a disaster for multi-floating X11 apps

`docs/niri-evaluation.md` covers Zoom specifically. The broader point: any X11 client that spawns multiple floating windows confuses xwayland-satellite badly. Niri is eliminated.

### COSMIC is a whole desktop, not just a WM

The earlier "COSMIC as dark horse" framing didn't grapple with the fact that COSMIC isn't just `cosmic-comp` — it's a full desktop replacement, with everything that implies about giving up granular control. Jim toyed with it previously and came away underwhelmed. Eliminated for control-loss reasons.

## Field as of mid-2026

| Option | Status | Why eliminated / kept |
|--------|--------|------------------------|
| Niri | OUT | xwayland-satellite breaks X11 multi-float apps (Zoom unusable) |
| River | OUT | Evolved into WM-construction kit; not a turnkey WM anymore |
| COSMIC | OUT | Whole-desktop scope; control-loss tradeoff is too high |
| labwc | OUT | Stacking-only, no tiling mode at all, no snap zones, no grouping |
| AwesomeWM on Wayland | DOESN'T EXIST | No v5, no wayland branch, no active fork. way-cooler is dead. |
| Sway, dwl, vivarium, niri variants | OUT | All tiling-first |
| **Wayfire** | KEPT | Closest floating-first match on Wayland |
| **AwesomeWM on X11** | KEPT (philosophically) | Only mature floating-first per-tag-layout WM, but blocked by X11 single-DPI |
| **Hyprland + Lua** | KEPT | Current platform; can be bent toward floating-first via scripting |

## Hard facts (verified June 2026)

### Hyprland's Lua config is shipped and is the default

- **Lua is the canonical config format since Hyprland 0.55+** (default since 2.13.0). Hyprlang is deprecated. Single Lua file that can `require` other modules. (Sources: [Hyprland wiki](https://wiki.hypr.land/Configuring/Basics/Variables/), [ArchWiki](https://wiki.archlinux.org/title/Hyprland))
- This is **not on a roadmap** — it has shipped. The earlier "Watch List" item is now closed.

### Hyprland has no native floating-default workspace rule

- Workspace rules' `mode = t|f|g|v|p` field is about **gap/border window counting**, not "all new windows on this workspace spawn floating."
- Window rules can float-by-class, but no rule pattern exists for "spawn on workspace X → float."
- Achievable only via Lua + event-socket listener: subscribe to `openwindow`, check workspace ID, dispatch `togglefloating`. ~50 lines of Lua estimated.

### Hyprland snap zones are third-party

- No native edge-snap or window-magnetism in core Hyprland.
- [`hyprfloat`](https://github.com/yz778/hyprfloat) provides snap-zone behavior and tile/float-toggle on top of dispatchers.
- Not first-party, not in `hyprland-plugins/`.

### Hyprland groups are tiling-only

- Documentation: groups "take the space of one window" — a tabbed slot in the tiling tree.
- Floating-group is not a coherent concept; toggling float on a grouped member produces undefined behavior.
- **The "grouped floating windows" requirement (item 3 in the original ask) is unrealizable in Hyprland.** If grouping is load-bearing, Hyprland is wrong.

### AwesomeWM Wayland: nothing exists

- No `v5`, no `wayland` branch, no active fork with momentum (as of mid-2026).
- way-cooler abandoned.
- No Lua-scripted Wayland compositor faithfully implements the rc.lua per-tag layout model.
- AwesomeWM is still X11-only and will remain so for the foreseeable future.

### Wayfire's plugin model fits the requirements

- `simple-tile` plugin can be enabled per-workspace/per-output → per-workspace tile/float toggle works.
- Grid/snap plugins provide drag-to-edge tiling (halves, quarters).
- No first-class tabbed window grouping in stock plugin set.
- Mature, daily-driver capable, wlroots-based, standard XWayland.

### Wayfire's real-world gaps (from prior usage, not survey)

- **Overview** is a Gnome-overview knockoff — forces a grid (no fast Ctrl+Alt+Left/Right), or flat-scaled views that are hard to read at a glance.
- **Gaming via Steam+Proton** breaks on cases that Just Work on Hyprland. Less compositor testing surface, fewer eyes on wlroots gaming edge cases.
- Net: switching to Wayfire would degrade currently-working gaming workflows to fix the WM-philosophy mismatch.

### XLibre status (verified June 2026)

XLibre (https://x11libre.net/, https://github.com/X11Libre) forked from X.Org on 2025-06-05. ~50 contributors, real momentum.

**Shipped:**
- **TearFree by default** — the X11 tearing problem is solved in XLibre.
- **Atomic modesetting** support enabled.
- Restored support for older NVIDIA drivers (340, 390, 470).
- Code cleanups, security backports.
- `Xnamespace` extension for separating X clients.
- `Xfbdev` (framebuffer) support restored.
- `seatd` integration alongside `systemd-logind`.

**In active design ("Soon To Be Addressed" category):**
- **Color Management & HDR** (discussion #251, 80 comments) — actively designed. Closing this Wayland-parity gap is on the near roadmap.
- Nvidia proprietary ABI tracing tool.
- RPC refactoring.

**In "Good Ideas for Later" (no active work):**
- **"Real Multi-Monitor Implementation"** (#288, Aug 2025) — the architectural rework that would underpin per-monitor DPI. Not in the near queue.
- **"Scaling on a multi-monitor setup"** (#499, Apr 2026, 1 comment) — community recognition of the problem, but minimal engagement.

**Not addressed in publicly visible discussions:**
- Per-monitor DPI as an active work item with a maintainer behind it.

**Interpretation:**
- The X11 "loses tearing fixes" framing is now wrong — XLibre has TearFree by default.
- HDR is roadmap, not hand-wave. Likely closes in the next 12–24 months given the engagement level.
- **Per-monitor DPI is still the open dealbreaker for Path 2.** It's recognized but not on the active roadmap. Until #288 moves to "Soon To Be Addressed" with a maintainer signed up, AwesomeWM-on-XLibre remains blocked for mixed-DPI laptops.
- Cultural note: discussion #115 ("Add Wayland compatibility" — make X11 a Wayland server) was correctly rejected as out-of-scope. XLibre is not trying to become Wayland, it's trying to be a healthier X11. The inverse-of-XWayland framing is funny but not actually a feature anyone is building.

**Wayland-app escape hatch on X11: 12to11**

The maintainer-recommended answer to "what about Wayland-only apps on X11?" is [12to11](https://aur.archlinux.org/packages/12to11-git), a tool that runs *inside* X11, presents a Wayland socket, and converts Wayland windows into X11 windows. Per maintainer reports on discussion #115, performance is good (reportedly better fps than running Wayland-native in some cases). Install via AUR, run `RENDERER=egl 12to11`, done.

- **Canonical upstream:** `https://git.linuxping.win/12to11/12to11` (committer "cat" = Po Lu, X.Org / Emacs developer).
- **`github.com/probonopd/12to11`** is a mirror, NOT the upstream. probonopd historically maintains X11-preservation mirrors of useful tools.
- **Last upstream commit: 2025-06-17.** Quiet for ~12 months as of this writing. Author may have reached "good enough for my purposes" — or may have moved on.
- Known limitations (per upstream README): touchscreens not supported, dmabuf feedback device switching incomplete.
- Known issues per maintainer report on discussion #115: cursor square-shadow with EGL renderer, SDL apps say Wayland not available.

**Decay function — direction confident, magnitude uncertain**

12to11 froze ~mid-2025. Wayland protocols continue to evolve (color management, fractional-scale refinements, `xdg-toplevel-icon`, etc.). A frozen bridge will cover progressively less of the Wayland-app landscape over time.

Compound this with the GNOME-and-KDE-going-Wayland-only direction:
- GNOME 47+ ships without an X11 session option (Wayland-only sessions).
- KDE Plasma 6.x defaults to Wayland; X11 session deprecated.
- BUT: GTK4 and Qt6 still ship X11 backends. "Wayland-only app" really means "app whose authors explicitly dropped X11 in their build/runtime."

**Two different curves — don't conflate:**
- **User session share** (which session people log into).
- **App build decisions** (does upstream ship `--disable-x11`). Driven by toolkit/app maintainer choices, not user vote. Can run ahead of user share but not unboundedly.

**The user-share data is more interesting than initially treated.** Per [Linux-Hardware.org](https://linux-hardware.org/?view=os_display_server&scale=last_three_years) (voluntary survey, ~6,000 machines).

Two caveats worth dispatching:
- **"Technical-user selection bias"** — doesn't apply. There is no large non-technical Linux desktop population to be skewed against. Outside Steam Deck (SteamOS, sidesteps the X11/Wayland choice entirely) and Android (not desktop), the Linux desktop population *is* technical users. The sample reflects the actual base.
- **"Sample too small"** — also doesn't apply. Steam Hardware Survey puts Linux at ~4% of Steam (~5M people including Steam Deck; strip the Deck and traditional desktop Linux is on the order of 1-3M Steam users). Total worldwide Linux desktop is a small multiple of that — 5-10M generously. 6,000 machines is 0.06-0.12% of the universe; for a population in the low millions, that's solid statistical footing. Health studies that drive medical practice routinely work with smaller fractions.

The trend it shows:

- X11 and Wayland in dead heat, within ~1pp of each other.
- **No noteworthy Wayland gains since June 2024** — ~2 years of stagnation.
- Wayland down from a 49.2% peak to 47.3% (near-noise on the absolute number, but the lack of growth is the load-bearing observation).

Firefox telemetry (Feb 2022, now stale but the dateline matters): 90%+ pure X11, 92-94% including XWayland — *14 years after Wayland's first release*. The transition has been slow throughout.

**The "no pop" observation:** Ubuntu, Fedora, Debian have been defaulting to Wayland for years. GNOME removed the X11 session option entirely. KDE deprecated X11. The desktop ecosystem has invested enormously. And the adoption curve stayed flat. Successful platform transitions usually have a hockey-stick from social proof — someone tries it, it's better, they tell friends, share climbs nonlinearly. Wayland's curve looks more like a forced migration users tolerate rather than advocate for. Pattern-matches the Microsoft Windows-8/Metro/Recall dynamic: vendor decides users want X, invests heavily, users keep using Y, vendor concludes users are wrong rather than reconsidering X.

**Why this matters more than equivalent data from Windows/macOS:**

Linux desktop is a self-selecting population. Every user is there *despite* the easier path of accepting Windows or macOS defaults. They've already paid the cost of leaving and the cost of ongoing maintenance. That selection means they're closer to "informed evaluators" than "default acceptors." Share data from this population is much closer to *revealed preference* than equivalent data from Windows users, most of whom never actively chose anything.

So 47.3% Wayland, flat for two years, in a population of evaluators is a fundamentally different signal than "X% browser-share-growing" in a population of accepters. The first is the market telling us that informed users, given a free choice, aren't picking Wayland. That's a much stronger claim than "adoption is slow."

**The "always backed up" property of the resistance:**

The objections to Wayland aren't vibes. They're specific testable claims, catalogued at length across forums, distro bug trackers, and project-specific docs:

- NVIDIA driver pain
- Screen sharing breakage (per-app, per-toolkit)
- Mouse capture in games (e.g., XWayland hardware cursor workaround)
- Fractional scaling edge cases (toolkit-dependent)
- Multi-window X11 app behavior (KiCad, GIMP single-window-disabled, virt-manager)
- Global hotkeys (limited by protocol)
- Color picking across apps
- Accessibility tool gaps
- Application-specific failures (Zoom catalog in `docs/niri-evaluation.md`)
- The xwayland-satellite gap for non-native-XWayland compositors

Each is concrete, reproducible, and persistent. That's a different epistemological category than "users dislike change."

**Revised reading:** in the population qualified to judge, with a free choice, Wayland is currently losing on the merits. The press narrative that it's the obvious upgrade hasn't survived contact with that user base. Whether it eventually wins depends on whether the resistance points get *fixed* — and the rate of fixing has been slow because each point requires negotiating with a different stakeholder (compositor authors, toolkit maintainers, app authors, hardware vendors).

**The cost-benefit framing — not anti-modernization, anti-this-path-to-modernization:**

The Wayland resistance isn't "we don't want what Wayland is selling." Most of the goals (per-monitor DPI, tearing fixes, HDR, better security model, fractional scaling) are *shared desires*. The objection is to the path: Wayland's chosen route to deliver those goals doesn't justify what it costs in regressions, fragmentation, and time-to-parity.

This is a Brooks "Second System Effect" critique. From *The Mythical Man-Month*: the first system gets built under the discipline of inexperience; the second system gets built by the same designer who now knows what they "should have done" the first time, and they put in *everything* they had to leave out. The result is architecturally ambitious but operationally worse, and takes much longer to mature than predicted.

Wayland fits the pattern uncomfortably well:

- **Complexity moved, not removed.** Wayland-the-protocol is small, but every Wayland compositor reinvents what X.Org used to do once: input handling, damage tracking, output management, atomic modesetting, surface presentation. Net complexity went up, fragmented across implementations.
- **"Small core + extensions" became "small core + 30 extensions, each compositor implementing a different subset."** Per-compositor protocol divergence is the direct second-system manifestation: optimized for theoretical cleanliness, delivered practical fragmentation that X.Org didn't have.
- **Still not at protocol-level parity 15+ years in.** Color management, HDR, global window positioning, accessibility hooks, session management — landing piecemeal, years behind promise. X11 had most of these (ugly, but had them).

**What this implies for XLibre as a path forward:**

There's no third-system display server being built. The cleanest fix to a Brooks pattern is usually a third try by a humbler designer, but nobody is doing that and the Wayland investment is too deep to abandon. The remaining live option is **continued evolution of the first system** — which is what XLibre is. By Brooks's strict framing that's not the predicted winning move, but a lot of "second systems" have actually lost to "first systems evolved harder" — Unix vs Multics being the textbook case.

This is the deeper argument for why Path 2 (XLibre + AwesomeWM) has more strategic legs than the press narrative suggests: it's the only path that doesn't require Wayland's second-system bet to pay off.

**Revised implications:**

- **Decay function magnitude is probably much smaller than initially stated.** If user share is flat across the *actual* user base, toolkit maintainers face real consequences for dropping X11 — bug reports, distro forks, user migrations to less-aggressive alternatives. GNOME may absorb the pain on principle; others won't.
- **"Wayland actually loses" upgrades from non-zero to non-trivial.** Coexistence is still more likely than X11 outright winning, but the probability mass is meaningful enough to factor into planning. If XLibre keeps shipping and the Wayland push runs out of social capital, the long-run equilibrium could be X11-dominant or true coexistence rather than Wayland-dominant.
- **DPI dealbreaker is unchanged.** None of this fixes today's mixed-DPI laptop on X11. The argument shifts *time pressure* on Path 2, not the *current blocker*.

**Net effect on Path 2:** still tilts toward Path 3 as the path-of-least-regret *today*, because Path 3's maintenance burden is bounded and the per-monitor DPI block on Path 2 is real. But Path 2's re-evaluation timeline is shorter than the initial framing suggested — not "watch for years" but "if XLibre #288 picks up a maintainer, Path 2 could be the right answer within 18-24 months."

## The three remaining paths

### Path 1: Wayfire as primary

- ✅ Closest architectural fit to the original ask
- ✅ Per-workspace tile/float via plugin activation
- ✅ Snap zones via grid plugin
- ✅ Prior experience with the system
- ❌ Overview UX is poor (grid-or-flat, no fast cycling)
- ❌ Gaming/Proton regressions vs Hyprland (real, not theoretical)
- ❌ Smaller contributor base → wlroots edge cases stay broken longer
- ❌ No first-class tabbed window grouping

**Cost:** voluntary downgrade of currently-working gaming and overview workflows to fix the WM philosophy.

### Path 2: AwesomeWM on X11 (XLibre)

- ✅ Exactly the per-tag layout model originally described, mature
- ✅ KiCad-class apps work natively without XWayland positioning compromises
- ✅ Steam+Proton on X11 still excellent
- ✅ **Tearing is solved on XLibre** (TearFree by default) — earlier framing was wrong on this point
- ⏳ HDR is on XLibre's near roadmap (#251, "Soon To Be Addressed", 80 comments)
- ❌ **Per-monitor DPI not on XLibre's active roadmap** — sits in "Good Ideas for Later" (#288), minimal engagement
- ❌ Animations/fractional scaling story remains weaker than Wayland
- ❌ Backward step from accumulated Wayland investment

**Cost:** the per-monitor DPI dealbreaker is unrecoverable until XLibre #288 (Real Multi-Monitor Implementation) moves to active development. Status: monitor the issue tracker, not a near-term option.

### Path 3: Hyprland + Lua, bent toward floating

- ✅ Stay on the compositor with most attention and best gaming
- ✅ Keep Wayland's modern stack including per-monitor DPI
- ✅ Lua config gives clean expression of the float-default behavior
- ✅ Gaming workspace can stay standard tiling — best of both within one session
- ✅ Special workspaces (Zoom, Morgan) keep working as today
- ❌ "Floating-default workspace" must be built (Lua module + event socket subscription)
- ❌ Snap zones require `hyprfloat` (or hand-rolled equivalent)
- ❌ Grouped-floating is unrealizable — must be abandoned as a requirement
- ❌ Maintenance burden: Lua API will churn, event-socket semantics aren't a committed contract

**Cost:** ~1 weekend of Lua, ongoing maintenance, and dropping the grouping requirement.

## Recommendation (assistant's view, for Jim's consideration)

**Path 3 (Hyprland + Lua), with the grouping requirement dropped.**

Reasoning:
1. The grouping requirement was the weakest of the three originally — couldn't be defended when pressed on it. "Two windows side-by-side" is handled by snap zones; "tabs across windows" is handled by application-internal tabs (browser, terminal multiplexer).
2. Per-workspace floating default (item 1) and snap zones (item 2) are the load-bearing requirements. Both are achievable on Hyprland with bounded effort.
3. The per-monitor DPI dealbreaker eliminates Path 2.
4. Wayfire's gaming regressions eliminate Path 1 from "drop-in upgrade" territory; it would only be the answer if Hyprland-with-Lua proves intolerable.

Path 1 (Wayfire) becomes the fallback if Path 3 turns into a maintenance nightmare. Path 2 (AwesomeWM-X11) is held as a "watch XLibre and reassess" entry.

## Open questions for cogitation

1. **Is the per-workspace floating-default behavior actually load-bearing?** Or would a global "everything floats unless I explicitly tile this window" suffice? The latter is even simpler — just make Hyprland default to floating globally (window rule: `float, class:.*` minus exceptions) and have a `togglefloating` keybind. No workspaces involved.

2. **What problem does "grouping floating windows" actually solve** that snap-zones + application-internal tabs don't? If the answer is "move two windows together as a unit," is that worth building? Or is it nice-to-have?

3. **How fragile is the Hyprland Lua API going to be over the next 12 months?** The migration just shipped; APIs will churn. Acceptable churn budget?

4. **Should Wayfire be tried again** specifically to verify the gaming regressions and overview UX are still as bad as remembered? Memory is from previous use; situation may have improved.

5. **XLibre watch:** the trigger for reopening Path 2 is specifically discussion **#288 ("Real Multi-Monitor Implementation")** moving from "Good Ideas for Later" to "Soon To Be Addressed" with a maintainer attached. Tearing and HDR progress on XLibre are nice but not the gating items.

## If Path 3 is chosen — sketch of the work

1. **Float-default Lua module:**
   - Subscribe to Hyprland event socket (`/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`).
   - Listen for `openwindow` events.
   - Check window's workspace ID against configured float-default set.
   - Dispatch `togglefloating` via hyprctl if in set.
   - ~50 lines, plus error handling and reconnect logic.

2. **Snap zones:**
   - Try `hyprfloat` first.
   - If unsuitable, hand-roll snap logic using `movewindowpixel` / `resizewindowpixel` and edge detection in the same Lua module.

3. **Gaming workspace exception:**
   - Designate workspace 9 (or similar) as tiling-default; keep it out of the float-default set.
   - Game windows tile/fullscreen normally.

4. **Special workspaces:**
   - No changes. Zoom and Morgan stay as-is — confirmed correct UX during this conversation.

5. **Documentation:**
   - Add a section to `docs/hyprland-migration.md` describing the float-default layer.
   - Update the Watch List section with "Hyprland Lua API stability" as an item.

## Next steps

Not committed. Document captured for review. No code changes made.
