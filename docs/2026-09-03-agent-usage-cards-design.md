# Agent-usage cards (Quickshell) — design (2026-09-03)

**Goal:** A Quickshell bar widget + popout on `godlike-artix` that shows live
AI-coding-agent usage — plan tier, rate-limit meters with reset countdowns, and
token stats — for **Claude Code** and **Codex**, mined from Omarchy's
`agents` panel but rebuilt on Jim's own Quickshell (`dotfiles/.config/quickshell/`)
and his own script repo (`i3-screen-manager/bin/`).

**Status:** design approved in chat 2026-09-03 (pipeline option A). Spec →
implementation plan → build.

**Machine:** **fleet-wide by construction** — developed on `godlike-artix` but
not specific to it. The QML rides the whole-dir `~/.config/quickshell` symlink,
so it appears on `nomad-artix` the moment `shell.qml` mounts it; the collectors
honor `CLAUDE_CONFIG_DIR`/`CODEX_HOME` with no hardcoded paths; and the bar
item **self-hides** wherever an agent has no `ready` record, so a machine
missing an agent's auth simply shows fewer cards. The only machine-local step is
the `~/.local/bin/` symlinks for the three scripts — the standard convention for
every script in this repo, not a per-machine special case. See §2.1.

## 1. Why / provenance

Omarchy (`basecamp/omarchy`, MIT) ships an `agents` bar plugin: standalone
Python **collectors** each print one display-ready JSON **record**, and a
QuickShell **panel** watches those records and draws cards. The
collector↔panel seam is a plain JSON file on disk — the panel never touches an
endpoint or a disk format. That seam is what makes the data layer portable to
Jim's Quickshell even though Omarchy's QML panel is bound to Omarchy's plugin
host.

Ground truth established while scoping (both run clean on `godlike-artix`):

- `omarchy-agent-usage-claude` → Claude **Max 20x**, live limits from Anthropic's
  OAuth usage endpoint (`https://api.anthropic.com/api/oauth/usage`): Session
  (5-hour), Weekly (7-day), plus a Fable Weekly bucket.
- `omarchy-agent-usage-codex` → Codex **pro**, Weekly (7-day) limit via the
  Codex app-server RPC.

**agy (Antigravity) is deferred** — see Out of scope.

Both collectors have **no `$OMARCHY_PATH` dependency**; the only Omarchy-isms are
(a) a cache dir segment `~/.cache/omarchy/agent-usage/` and (b) `omarchy:...`
comment-metadata lines. So vendoring is a rename + light touch, not a rewrite —
we keep the proven OAuth/limits logic (the whole point) rather than
re-deriving it.

## 2. Architecture — two layers, JSON-file seam

```
 i3-screen-manager/bin/                     dotfiles/.config/quickshell/
 ┌───────────────────────┐   JSON array    ┌──────────────────────────┐
 │ agent-usage           │ ─── stdout ───▶ │ Widgets/Agents.qml       │ bar item
 │  ├─ agent-usage-claude │  (+ writes      │  └─ Popout ──────────────┐
 │  └─ agent-usage-codex  │   per-agent     │       AgentsPanel.qml    │ cards
 └───────────────────────┘   files to      └──────────────────────────┘
        (Python, RO)          state dir)
```

- **Data layer** (`i3-screen-manager/bin/`, committed + symlinked from
  `~/.local/bin/` per repo convention):
  - `agent-usage-claude`, `agent-usage-codex` — vendored from Omarchy, adapted
    (rename; repoint cache dir; keep/replace `omarchy:` metadata comments with a
    provenance header). Read-only; each prints one record to stdout.
  - `agent-usage` — new tiny orchestrator (bash). Runs both collectors in
    parallel, validates each is JSON (`jq -e .`), prints a merged **JSON array**
    of records to stdout, and also writes each record to
    `~/.local/state/agent-usage/<id>.json` (near-free; enables a future
    CLI/rofi reader and cross-machine sync without changing the QML).
    Passes through `--force` / `--limits-only`.
- **UI layer** (`dotfiles/.config/quickshell/`, whole-dir symlinked live):
  - `Widgets/Agents.qml` — bar `MouseArea` item: nerd-icon + compact indicator
    (the single highest limit `percent` across agents, e.g. `󰚩 10%`). A
    `Process` on a `Timer` runs `agent-usage`; stdout parsed as JSON in QML (no
    jq). `onClicked: pop.toggle()`. **Self-hides** (zero width, no icon) until at
    least one record is `ready` — matches Omarchy; keeps the bar quiet on a
    machine with no agent usage.
  - `Widgets/AgentsPanel.qml` — popout card content via the existing
    `Popout.qml`, styled with `Theme.qml` tokens (square, opaque, no animation —
    the house no-frills aesthetic).

### 2.1 Fleet-wide behavior

Nothing here is `godlike-artix`-specific:

- **QML** — `Agents`/`AgentsPanel` land on both machines via the
  `~/.config/quickshell` whole-dir symlink. `shell.qml` mounts the widget in a
  **shared, non-machine-gated** part of the bar row (not behind a `machine.lua`
  trait branch), so both boxes render it.
- **Collectors** — Claude Code and Codex are installed on both machines
  (migration history); paths come from `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/XDG, so
  the same script works on either. On a machine where an agent isn't signed in,
  its collector returns a not-`ready` record (or limits-less local stats) and
  the card self-hides — no gating, no error.
- **Machine-local step (standard):** create the `~/.local/bin/` symlinks for the
  three scripts on each machine, exactly as every other script in this repo is
  deployed. That is the whole laptop rollout — no laptop-specific tuning.

### Refresh (pipeline A — approved)

QML-driven, exactly like `Weather.qml` runs `curl`: `Agents.qml` owns a `Timer`
(~10 min) that re-runs `agent-usage`; `r`/Enter or a click re-triggers it. No
external daemon. Safe because the collectors self-throttle: the Claude collector
caches limits under `~/.cache/…/agent-usage` with a 15 s probe floor and reads
transcripts on a cache age, so frequent invocation does not hammer the endpoint.
(Rejected B: an OpenRC user timer writing files the bar watches — cleaner
separation but an extra moving part; the disk writes in `agent-usage` already
leave the door open to it later with no QML change.)

## 3. Record contract (schemaVersion 1) — consumed by the cards

Top-level keys the panel reads (verified live):

| Key | Type | Card use |
|---|---|---|
| `id`, `name` | str | which mark/label to draw |
| `tierLabel` | str | plan chip (`Max 20x`, `pro`) |
| `ready` | bool | gates the whole agent (and the bar self-hide) |
| `usageStatusText` / `authHelpText` | str | replaces the plan line on auth/endpoint trouble |
| `limits` | `[{label, percent, resetsAt, title?}]` | one meter row each: label, bar, percent text, countdown to `resetsAt` |
| `todayPrompts`, `todaySessions` | int | "Today N prompts · M sessions" |
| `todayTotalTokens` | int | today token total |
| `todayTokensByModel` | `{model: tokens}` | today per-model |
| `recentDays` | `[{date, messageCount}]` | tokens-by-day bars — **`messageCount` is the day's token total** (legacy name), scaled to the busiest day |
| `modelUsage` | `[{key: model, value: {inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens}}]` | tokens-by-model bars, scaled to heaviest; input/output/cache split on hover |
| `totalPrompts`, `totalSessions`, `activeDays` | int | footer / lifetime |

**`percent` is a 0..1 fraction** (confirmed against Omarchy `Panel.qml`):
display text `= Math.round(percent * 100) + "%"`; meter fill width
`= trackWidth * clamp(percent, 0, 1)`; a limit is drawn in the **urgent** color
when `percent >= 0.9`. Live sample: Session `0.01` → 1 %, Weekly `0.1` → 10 %,
Fable Weekly `0.17` → 17 %.

## 4. Card layout (two agents stacked, no switcher)

With exactly two agents, stack both in one popout (see both at once) rather than
Omarchy's one-at-a-time switch:

```
 󰚩  Claude Code                         Max 20x
     Session (5h)   ░░░░░░░░░░   1%   resets 3h
     Weekly (7d)    ▓░░░░░░░░░  10%   resets 4d
     Fable Weekly   ▓▓░░░░░░░░  17%   resets 4d
     Today  90 prompts · 2 sessions · 30M tok
     By model  ▓▓▓▓▓ fable-5   ▓▓ opus-4-8
 ───────────────────────────────────────────────
 󱚝  Codex                                    pro
     Weekly (7d)    ░░░░░░░░░░   0%   resets 7d
     Today  …
```

- Meters + reset countdown are the hero (fill = `percent`; urgent color at
  `≥ 0.9`). Tokens-by-day/by-model bars are secondary rows, drawn with plain
  `Rectangle`s scaled to the max (no chart lib).
- Auth/endpoint failure for an agent: its plan line is replaced by
  `usageStatusText`/`authHelpText` and meters are omitted, but local token stats
  still render (Omarchy behavior).
- Marks: reuse Omarchy's `assets/claude.svg` / `codex.svg` (MIT) or fall back to
  a nerd glyph. Icon choice finalized in the plan.

## 5. Interactions

- Bar icon: left = toggle popout; (right = launch default agent — optional,
  deferred).
- Popout: click-outside / trigger-again to dismiss (inherited from `Popout.qml`
  focus-grab); `r`/Enter to refresh.

## 6. Testing (manual — repo has no automated tests)

1. `agent-usage-claude` / `agent-usage-codex` each emit valid JSON
   (`… | jq -e .`) on `godlike-artix`.
2. `agent-usage` prints a 2-element array and writes
   `~/.local/state/agent-usage/{claude,codex}.json`.
3. Bar item hidden when the state dir is empty / nothing `ready`; appears once
   records exist.
4. Popout renders both agents, meters match the raw `percent`, countdown text is
   sane, token bars scale to the busiest day/model.
5. `--limits-only` and `--force` behave (fast path vs cache-bypass).
6. `qs kill; qs -p ~/.config/quickshell` reloads cleanly, no duplicate bars
   (per CLAUDE.md Quickshell restart rule).

## 7. Out of scope (now)

- **agy / Antigravity** — no upstream collector; local token data is
  unschema'd protobuf-in-SQLite (`gen_metadata`/`step_payload` blobs), no `usage`
  subcommand, no personal-account limits endpoint. Deferred as a separate
  reverse-engineering effort; the `agent-usage` orchestrator globs collectors so
  adding `agent-usage-agy` later needs no UI change.
- **fireworks** — Omarchy's third collector; not an agent Jim uses.
- **Cross-machine usage sync** (Omarchy's synced-folder merge) — the disk writes
  leave room for it; not built now.
- **Right-click launch-agent** on the bar icon.

## 8. Provenance / attribution

Vendored collectors and any lifted SVG marks carry a header crediting
`basecamp/omarchy` (MIT) with the upstream path. No AI-tells in any committed
prose (per standing convention). The QML is original (mirrors Jim's own
`Weather.qml`), with a one-line note that the panel design was mined from
Omarchy's `shell/plugins/agents/`.

## 9. File inventory

Create:
- `i3-screen-manager/bin/agent-usage` (bash orchestrator)
- `i3-screen-manager/bin/agent-usage-claude` (vendored Python)
- `i3-screen-manager/bin/agent-usage-codex` (vendored Python)
- `dotfiles/.config/quickshell/Widgets/Agents.qml`
- `dotfiles/.config/quickshell/Widgets/AgentsPanel.qml`
- (optional) `dotfiles/.config/quickshell/assets/{claude,codex}.svg`

Modify:
- `dotfiles/.config/quickshell/shell.qml` — mount `Agents` in the bar's widget
  row (placement TBD in plan, near the system cluster).
- `~/.local/bin/` symlinks for the three scripts (machine-local, per convention).
- `i3-screen-manager/CLAUDE.md` — Architecture + doc-index entries (post-build).
