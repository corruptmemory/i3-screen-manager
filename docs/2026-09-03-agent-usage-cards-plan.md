# Agent-usage cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A self-hiding Quickshell bar widget + popout showing live Claude Code and Codex usage (plan tier, rate-limit meters with reset countdowns, token stats), fed by two vendored read-only Python collectors and a bash orchestrator.

**Architecture:** Two layers joined by a JSON-file/stdout seam. Data layer: `agent-usage-claude` / `agent-usage-codex` (vendored from Omarchy, MIT) each print one JSON record; `agent-usage` (bash) runs both, prints a merged array, and caches per-agent files. UI layer: `Agents.qml` (bar item, polls `agent-usage` like Weather polls curl) + `AgentsPanel.qml` (popout cards), mounted in `shell.qml`'s shared right-slot cluster.

**Tech Stack:** Python 3 stdlib (collectors), Bash + jq (orchestrator), QML / Quickshell 0.3.x (widget), Hyprland.

**Spec:** `docs/2026-09-03-agent-usage-cards-design.md`

## Global Constraints

- **Repo has NO automated test harness; QML is not unit-testable.** "Verification" per task = concrete runnable checks (`jq -e` assertions for scripts) and explicit reload + `qs log` + visual checks for QML. Each task still ends in an independently checkable deliverable and a commit. This is the honest TDD adaptation for a bash/QML dotfiles context — do not fabricate a test framework.
- **Two repos.** Scripts live in `~/projects/i3-screen-manager/bin/` (commit here, `chmod +x`, symlink from `~/.local/bin/`). QML lives in `~/projects/dotfiles/.config/quickshell/` (whole-dir symlinked live to `~/.config/quickshell`). Commit each repo separately.
- **Commit trailers** (every commit, both repos):
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3
  ```
- **Trunk-based:** commit directly to `master`. Do not push until Jim asks ("the update-the-remote dance").
- **No AI-tells** in any committed prose/comments (no em-dashes/arrows; fence code; backtick symbols/dates/SHAs).
- **Vendored code carries a provenance header** crediting `basecamp/omarchy` (MIT) + the upstream filename.
- **Quickshell restart:** `qs kill; qs -p ~/.config/quickshell` (NEVER `pkill -f '^qs '` — it re-execs to `/usr/bin/quickshell` and a relaunch spawns a duplicate bar). `qs list` shows instances; `qs log` shows QML errors.
- **Theme tokens (exact):** `Theme.bg #000`, `bgAlt #232323`, `fg #e6e6e6`, `fgDim #888`, `accent #3b6ea5`, `warn #F0C674`, `crit #A54242`; `fontFamily "TX-02"`, `iconFont "Symbols Nerd Font"`, `fontSize 16`, `gap 8`, `barHeight 28`. TX-02 has NO nerd glyphs; icons MUST use `font.family: Theme.iconFont`.
- **QML gotchas (from CLAUDE.md):** use `Layout.preferredWidth/Height` in layouts (not `width`); `font.family` (not `font.families`); do NOT name a property `transform` (FINAL Item prop) or `format` shadowing issues; parse JSON in QML with `JSON.parse` (no jq shell-out); `Timer.interval` is milliseconds. Toggle visibility with `visible`/`hidden`, not `Layout` removal.
- **`percent` is a 0..1 fraction.** Meter fill = `clamp(percent,0,1)`; text = `Math.round(percent*100)+"%"`.

---

### Task 1: Vendor the two collectors

**Files:**
- Create: `i3-screen-manager/bin/agent-usage-claude` (from `~/projects/omarchy/bin/omarchy-agent-usage-claude`)
- Create: `i3-screen-manager/bin/agent-usage-codex` (from `~/projects/omarchy/bin/omarchy-agent-usage-codex`)
- Symlink: `~/.local/bin/agent-usage-claude`, `~/.local/bin/agent-usage-codex`

**Interfaces:**
- Produces: two executables that each print ONE JSON record to stdout (contract: `id,name,tierLabel,ready,limits[],todayPrompts,todaySessions,todayTotalTokens,todayTokensByModel,recentDays[],modelUsage[],…`), accepting `--force` / `--limits-only`.

- [ ] **Step 1: Copy the two collectors verbatim**

```bash
cd ~/projects/i3-screen-manager
cp ~/projects/omarchy/bin/omarchy-agent-usage-claude bin/agent-usage-claude
cp ~/projects/omarchy/bin/omarchy-agent-usage-codex  bin/agent-usage-codex
chmod +x bin/agent-usage-claude bin/agent-usage-codex
```

- [ ] **Step 2: Replace the `omarchy:` metadata comments with a provenance header**

In EACH file, replace the leading `# omarchy:summary=…` / `# omarchy:args=…` / `# omarchy:hidden=…` comment lines (just below the shebang) with:

```python
# Vendored from basecamp/omarchy (MIT): bin/omarchy-agent-usage-<agent>.
# Read-only: prints one display-ready JSON usage record to stdout. Adapted only
# to drop the Omarchy cache-dir segment; the OAuth/limits + local-stats logic is
# upstream's. See i3-screen-manager/docs/2026-09-03-agent-usage-cards-design.md.
```
(Use `agent-usage-claude` / `agent-usage-codex` for `<agent>`.) Leave the module docstring and all code intact.

- [ ] **Step 3: De-Omarchy the cache directory**

Find every cache-dir literal and drop the `omarchy/` segment (keeps the vendored collector from sharing Omarchy's cache):

```bash
cd ~/projects/i3-screen-manager
grep -n '"omarchy"' bin/agent-usage-claude bin/agent-usage-codex
# Expect one hit per file, of the form: ... / "omarchy" / "agent-usage"
sed -i 's# / "omarchy" / "agent-usage"# / "agent-usage"#g' bin/agent-usage-claude bin/agent-usage-codex
grep -n '"omarchy"' bin/agent-usage-claude bin/agent-usage-codex   # expect: no output
```
Expected: the second grep prints nothing.

- [ ] **Step 4: Symlink into `~/.local/bin`**

```bash
ln -sf ~/projects/i3-screen-manager/bin/agent-usage-claude ~/.local/bin/agent-usage-claude
ln -sf ~/projects/i3-screen-manager/bin/agent-usage-codex  ~/.local/bin/agent-usage-codex
```

- [ ] **Step 5: Verify each emits a valid record (the "test")**

```bash
agent-usage-claude | jq -e '.id=="claude" and (.limits|type=="array") and (.ready|type=="boolean")' && echo CLAUDE_OK
agent-usage-codex  | jq -e '.id=="codex"  and (.limits|type=="array")' && echo CODEX_OK
```
Expected: `true` + `CLAUDE_OK`, `true` + `CODEX_OK`. (Both were confirmed working on `godlike-artix` during scoping.) If a collector prints a Python traceback, read it — most likely a missing `~/.claude`/`~/.codex` on this machine, in which case the record should still be valid JSON with `ready:false`; only a hard crash is a failure here.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/i3-screen-manager
git add bin/agent-usage-claude bin/agent-usage-codex
git commit -F - <<'EOF'
feat(agent-usage): vendor Claude + Codex usage collectors from omarchy

Read-only Python collectors (MIT, basecamp/omarchy) that each print one
JSON usage record: live rate limits (Anthropic OAuth usage endpoint /
Codex app-server RPC) plus local token/prompt stats. Adapted only to
drop the omarchy cache-dir segment. Data layer for the Quickshell agents
widget.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3
EOF
```

---

### Task 2: The `agent-usage` orchestrator

**Files:**
- Create: `i3-screen-manager/bin/agent-usage`
- Symlink: `~/.local/bin/agent-usage`

**Interfaces:**
- Consumes: `agent-usage-claude` / `agent-usage-codex` (siblings in the same bin dir).
- Produces: a JSON **array** of the successful records on stdout; writes each record to `~/.local/state/agent-usage/<id>.json` (atomic). Passes `--force`/`--limits-only` through.

- [ ] **Step 1: Write the orchestrator**

Create `bin/agent-usage`:

```bash
#!/usr/bin/env bash
# agent-usage - run the per-agent usage collectors, print a merged JSON array,
# and cache each record to ~/.local/state/agent-usage/<id>.json. Data layer for
# the Quickshell agents widget (Widgets/Agents.qml). Collectors are vendored
# from basecamp/omarchy (MIT). See
# docs/2026-09-03-agent-usage-cards-design.md.
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-usage"
mkdir -p "$STATE_DIR"
BIN_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

agents=(claude codex)
pass_args=("$@")   # e.g. --force / --limits-only

run_one() {
  local agent="$1" out="$2" rec dest tmp
  if rec=$("$BIN_DIR/agent-usage-$agent" "${pass_args[@]}" 2>/dev/null) \
       && [[ -n $rec ]] && jq -e . >/dev/null 2>&1 <<<"$rec"; then
    printf '%s\n' "$rec" >"$out"
    dest="$STATE_DIR/$agent.json"
    tmp=$(mktemp "$STATE_DIR/.$agent.XXXXXX")
    printf '%s\n' "$rec" >"$tmp" && mv "$tmp" "$dest"
  else
    : >"$out"   # empty file marks a failed/absent collector
  fi
}

tmps=() pids=()
for agent in "${agents[@]}"; do
  tmp=$(mktemp); tmps+=("$tmp")
  run_one "$agent" "$tmp" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done

# Merge non-empty records into a JSON array (agents[] order); [] if none.
nonempty=()
for t in "${tmps[@]}"; do [[ -s $t ]] && nonempty+=("$t"); done
if ((${#nonempty[@]})); then jq -s '.' "${nonempty[@]}"; else echo '[]'; fi
rm -f "${tmps[@]}"
```

- [ ] **Step 2: Make executable + symlink**

```bash
cd ~/projects/i3-screen-manager
chmod +x bin/agent-usage
ln -sf ~/projects/i3-screen-manager/bin/agent-usage ~/.local/bin/agent-usage
```

- [ ] **Step 3: Verify it prints an array and writes cache files (the "test")**

```bash
agent-usage | jq -e 'type=="array" and length>=1 and (.[0]|has("id"))' && echo ARRAY_OK
ls -1 ~/.local/state/agent-usage/     # expect: claude.json (and codex.json if authed)
jq -e '.id' ~/.local/state/agent-usage/claude.json && echo CACHE_OK
# --limits-only is the fast path used by the widget's frequent refresh:
time agent-usage --limits-only | jq -e 'type=="array"' >/dev/null && echo LIMITS_ONLY_OK
```
Expected: `true`+`ARRAY_OK`, the cache file(s), `CACHE_OK`, `LIMITS_ONLY_OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/i3-screen-manager
git add bin/agent-usage
git commit -F - <<'EOF'
feat(agent-usage): orchestrator - merged JSON array + per-agent cache

Runs the claude + codex collectors in parallel, prints a JSON array of
the successful records, and atomically caches each to
~/.local/state/agent-usage/<id>.json. Resolves siblings via readlink so
it works through the ~/.local/bin symlink. Passes --force/--limits-only
through. Consumed by Widgets/Agents.qml.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3
EOF
```

---

### Task 3: `Agents.qml` bar item + mount + self-hide

**Files:**
- Create: `dotfiles/.config/quickshell/Widgets/Agents.qml`
- Modify: `dotfiles/.config/quickshell/shell.qml` (mount in the right-slot cluster)

**Interfaces:**
- Consumes: `agent-usage` on PATH (array of records).
- Produces: `records` (var array) shared to the popout; a bar item that self-hides until an agent is `ready`.

- [ ] **Step 1: Write `Agents.qml` with a placeholder popout**

Create `Widgets/Agents.qml`. (The real popout content, `AgentsPanel`, arrives in Task 4; here it is an empty `Popout` so the bar item is independently verifiable.)

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.Widgets

// Agent-usage bar item: robot glyph + the highest limit % across all ready
// agents (the "closest to a cap" glance value). Click toggles a popout of
// per-agent cards. Polls `agent-usage` (Claude + Codex) every 10 min, parsing
// the merged JSON array in QML (no jq), the same way Weather runs curl.
// Self-hides until at least one record is `ready`, so a machine with no
// signed-in agent draws nothing. Panel design mined from omarchy's
// shell/plugins/agents; the QML is original (mirrors Weather.qml).
MouseArea {
    id: root
    property var records: []
    readonly property var readyRecords: (records || []).filter(function (r) { return r && r.ready })
    readonly property bool haveData: readyRecords.length > 0

    // Highest limit percent (0..1) across ready agents, or -1 if none.
    readonly property real maxPercent: {
        var m = -1
        for (var i = 0; i < readyRecords.length; i++) {
            var ls = readyRecords[i].limits || []
            for (var j = 0; j < ls.length; j++) {
                var p = ls[j].percent
                if (typeof p === "number" && p > m) m = p
            }
        }
        return m
    }
    function pctColor(p) { return p >= 0.9 ? Theme.crit : (p >= 0.75 ? Theme.warn : Theme.fg) }

    visible: haveData
    implicitWidth: haveData ? pill.implicitWidth : 0
    implicitHeight: pill.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: pill.implicitHeight
    onClicked: pop.toggle()

    RowLayout {
        id: pill
        anchors.centerIn: parent
        spacing: 4
        Text {
            text: String.fromCodePoint(0xF06A9)   // nf-md-robot (above U+FFFF, like Weather glyphs); if tofu, try 0xF167B (robot-outline)
            color: root.pctColor(root.maxPercent)
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            visible: root.maxPercent >= 0
            text: root.maxPercent >= 0 ? Math.round(root.maxPercent * 100) + "%" : ""
            color: root.pctColor(root.maxPercent)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            verticalAlignment: Text.AlignVCenter
        }
    }

    Process {
        id: proc
        command: ["agent-usage", "--limits-only"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(this.text)
                    if (Array.isArray(arr)) root.records = arr
                } catch (e) { /* transient failure: keep last good data */ }
            }
        }
    }
    // 10 min - collectors self-throttle (claude caches limits, 15s probe floor).
    Timer { interval: 600000; running: true; repeat: true; onTriggered: proc.running = true }

    Popout { id: pop; anchorItem: root }   // content added in Task 4
}
```

- [ ] **Step 2: Mount it in `shell.qml`'s right-slot cluster**

In `shell.qml`, inside the `RowLayout { visible: !bar.compact … }` in the `right` slot, add `Agents {}` as the FIRST child (before `Weather {}`):

```qml
                RowLayout {
                    visible: !bar.compact
                    spacing: Theme.gap
                    Agents {}
                    Weather {}
                    IdleInhibitor {}
```
(Shared cluster, not behind a `machine.lua` trait -> appears on both machines. It is hidden on the portrait/compact panel like the rest of the cluster, and self-hides when no agent is ready.)

- [ ] **Step 3: Confirm `agent-usage` resolves on the Quickshell PATH**

```bash
qs kill; qs -p ~/.config/quickshell >/dev/null 2>&1 &
sleep 3
qs log 2>/dev/null | grep -iE "agent-usage|No such file|Process.*error" | tail
```
Expected: NO "No such file" for `agent-usage`. If it appears, change the `Process.command` in `Agents.qml` to the PATH-independent form and reload:
```qml
        command: ["sh", "-c", "exec \"$HOME/.local/bin/agent-usage\" --limits-only"]
```

- [ ] **Step 4: Verify the bar item (visual "test")**

Reload (`qs kill; qs -p ~/.config/quickshell`). On the landscape monitor confirm: a robot glyph + a percent (e.g. `17%`) appears in the right cluster; the number matches the highest limit from `agent-usage --limits-only | jq '[.[].limits[].percent]|max'`; clicking it toggles an empty bordered popout; `qs log` shows no QML errors referencing `Agents.qml`. Temporarily confirm self-hide by checking the widget is absent when `readyRecords` is empty (e.g. it does not render on the portrait panel / with no data).

- [ ] **Step 5: Commit (dotfiles)**

```bash
cd ~/projects/dotfiles
git add .config/quickshell/Widgets/Agents.qml .config/quickshell/shell.qml
git commit -F - <<'EOF'
feat(quickshell): agents bar item - highest limit %, self-hiding

Robot glyph + the highest rate-limit percent across ready agents (glance
value for "closest to a cap"), colored warn/crit at 0.75/0.9. Polls
`agent-usage --limits-only` every 10 min, parses the JSON array in QML.
Mounted first in the shared right-slot cluster (fleet-wide, not
machine-gated); self-hides until an agent is ready. Empty popout for now
(cards land next).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3
EOF
```

---

### Task 4: `AgentsPanel.qml` - the cards

**Files:**
- Create: `dotfiles/.config/quickshell/Widgets/AgentsPanel.qml`
- Modify: `dotfiles/.config/quickshell/Widgets/Agents.qml` (put `AgentsPanel` inside the `Popout`; switch its poll to full `agent-usage` so token stats are present)

**Interfaces:**
- Consumes: `records` (array of the full record contract).
- Produces: the stacked per-agent cards.

- [ ] **Step 1: Write `AgentsPanel.qml`**

Create `Widgets/AgentsPanel.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import qs

// Popout content for the agents widget: one card per ready agent, stacked
// (no switcher - only two agents). Each card: name + tier chip, a meter row
// per limit (label, bar, percent, reset countdown), a "today" line, and
// tokens-by-model bars. Pure Rectangles scaled to the max - no chart lib, no
// animation (house no-frills aesthetic). Design mined from omarchy's
// shell/plugins/agents/Panel.qml; percent is a 0..1 fraction.
ColumnLayout {
    id: root
    property var records: []
    readonly property var readyRecords: (records || []).filter(function (r) { return r && r.ready })
    implicitWidth: 340
    spacing: Theme.gap

    function fmtTokens(n) {
        n = Number(n) || 0
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k"
        return "" + n
    }
    function fmtReset(iso) {
        if (!iso) return ""
        var t = Date.parse(("" + iso).replace(/\.\d+/, ""))   // strip micros for V4 parse
        if (isNaN(t)) return ""
        var d = t - Date.now()
        if (d <= 0) return "now"
        var mins = Math.floor(d / 60000)
        if (mins < 60) return "resets " + mins + "m"
        var hrs = Math.floor(mins / 60)
        if (hrs < 24) return "resets " + hrs + "h"
        return "resets " + Math.floor(hrs / 24) + "d"
    }
    function pctColor(p) { return p >= 0.9 ? Theme.crit : (p >= 0.75 ? Theme.warn : Theme.fg) }
    function modelTotal(v) {
        if (!v) return 0
        return (Number(v.inputTokens) || 0) + (Number(v.outputTokens) || 0)
             + (Number(v.cacheCreationInputTokens) || 0) + (Number(v.cacheReadInputTokens) || 0)
    }
    // Top-N models by total tokens, scaled to the heaviest. Returns
    // [{name, total, frac}] sorted desc.
    function topModels(mu, n) {
        var rows = []
        for (var i = 0; i < (mu || []).length; i++)
            rows.push({ name: mu[i].key, total: modelTotal(mu[i].value) })
        rows.sort(function (a, b) { return b.total - a.total })
        rows = rows.slice(0, n)
        var max = rows.length ? rows[0].total : 0
        for (var j = 0; j < rows.length; j++) rows[j].frac = max > 0 ? rows[j].total / max : 0
        return rows
    }

    Text {
        visible: root.readyRecords.length === 0
        text: "No agent usage yet"
        color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
    }

    Repeater {
        model: root.readyRecords
        delegate: ColumnLayout {
            id: card
            required property var modelData
            readonly property var rec: modelData
            Layout.fillWidth: true
            spacing: 4

            // Header: name + tier chip
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: card.rec.name || card.rec.id
                    color: Theme.fg; font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize; font.bold: true
                    Layout.fillWidth: true
                }
                Text {
                    visible: !!card.rec.tierLabel
                    text: card.rec.tierLabel || ""
                    color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                }
            }

            // Auth/endpoint status (replaces meters when limits unavailable)
            Text {
                visible: !!card.rec.usageStatusText || (!!card.rec.authHelpText && (card.rec.limits || []).length === 0)
                text: card.rec.usageStatusText || card.rec.authHelpText || ""
                color: Theme.fgDim; font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2; wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // Limit rows
            Repeater {
                model: card.rec.limits || []
                delegate: ColumnLayout {
                    required property var modelData
                    readonly property var lim: modelData
                    readonly property real pct: (typeof lim.percent === "number") ? lim.percent : 0
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: lim.title || lim.label || ""
                            color: Theme.fgDim; font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2; Layout.fillWidth: true
                        }
                        Text {
                            text: Math.round(pct * 100) + "%"
                            color: root.pctColor(pct); font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            text: root.fmtReset(lim.resetsAt)
                            color: Theme.fgDim; font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    Rectangle {   // meter track
                        Layout.fillWidth: true
                        implicitHeight: 4; radius: 0; color: Theme.bgAlt
                        Rectangle {   // fill
                            height: parent.height; radius: 0
                            width: parent.width * Math.max(0, Math.min(1, pct))
                            color: root.pctColor(pct)
                        }
                    }
                }
            }

            // Today line
            Text {
                readonly property int tp: Number(card.rec.todayPrompts) || 0
                readonly property int ts: Number(card.rec.todaySessions) || 0
                readonly property int tt: Number(card.rec.todayTotalTokens) || 0
                visible: tp > 0 || tt > 0
                text: "Today  " + tp + " prompts · " + ts + " sessions"
                      + (tt > 0 ? "  · " + root.fmtTokens(tt) + " tok" : "")
                color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                Layout.topMargin: 2
            }

            // Tokens by model (top 4, scaled to heaviest)
            Repeater {
                model: root.topModels(card.rec.modelUsage, 4)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text {
                        text: modelData.name
                        color: Theme.fgDim; font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        Layout.preferredWidth: 120; elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4; radius: 0; color: Theme.bgAlt
                        Rectangle {
                            height: parent.height; radius: 0
                            width: parent.width * modelData.frac; color: Theme.accent
                        }
                    }
                    Text {
                        text: root.fmtTokens(modelData.total)
                        color: Theme.fgDim; font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight
                    }
                }
            }

            // Separator between cards (not after the last)
            Rectangle {
                visible: index < root.readyRecords.length - 1
                Layout.fillWidth: true; implicitHeight: 1; color: Theme.bgAlt
                Layout.topMargin: 4
            }
        }
    }
}
```

- [ ] **Step 2: Wire it into the popout + switch the bar poll to full records**

In `Widgets/Agents.qml`: (a) change `Process.command` from `["agent-usage", "--limits-only"]` to `["agent-usage"]` (the popout needs token stats; still 10 min, still self-throttled); (b) replace the placeholder `Popout { id: pop; anchorItem: root }` with:

```qml
    Popout {
        id: pop
        anchorItem: root
        AgentsPanel { records: root.records }
    }
```

- [ ] **Step 3: Verify the cards (visual "test")**

`qs kill; qs -p ~/.config/quickshell`. Click the bar item and confirm: one card for Claude (name + `Max 20x` chip), one for Codex (`pro`); each limit shows label + meter + `N%` + `resets Xd/Xh/Xm`; the `N%` matches `agent-usage | jq '.[0].limits'`; meter fill visually tracks the percent; warn/crit color at 0.75/0.9; the "Today" line and up to 4 model bars render with sane `k`/`M`/`B` totals; a separator sits between the two cards but not after the last. `qs log` shows no errors referencing `AgentsPanel.qml`.

- [ ] **Step 4: Commit (dotfiles)**

```bash
cd ~/projects/dotfiles
git add .config/quickshell/Widgets/AgentsPanel.qml .config/quickshell/Widgets/Agents.qml
git commit -F - <<'EOF'
feat(quickshell): agents popout cards - limits, today, tokens by model

Stacked per-agent cards (Claude, Codex): name + tier chip, a meter row
per limit (label, bar, percent, reset countdown; warn/crit at .75/.9), a
today line, and top-4 tokens-by-model bars scaled to the heaviest. Pure
Rectangles, no chart lib, no animation. Bar widget now polls full
`agent-usage` so the popout has token stats. Design mined from omarchy's
Panel.qml; QML original.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3
EOF
```

---

### Task 5: Docs + laptop rollout note

**Files:**
- Modify: `i3-screen-manager/CLAUDE.md` (Architecture entry + doc index)

- [ ] **Step 1: Add an Architecture entry** under the Scripts list describing the three scripts (`agent-usage`, `agent-usage-claude`, `agent-usage-codex`): read-only collectors vendored from omarchy (MIT), the JSON-array + per-agent cache contract, consumed by the Quickshell `Agents`/`AgentsPanel` widget; note the design/plan docs. Note the QML is fleet-wide via the quickshell symlink and the scripts need the standard `~/.local/bin` symlink on each machine.

- [ ] **Step 2: Add a doc-index bullet** in the migration/docs list pointing at `docs/2026-09-03-agent-usage-cards-design.md` (and this plan), one-line summary: the omarchy-mined agent-usage cards for Claude + Codex.

- [ ] **Step 3: Commit (i3-screen-manager)**

```bash
cd ~/projects/i3-screen-manager
git add CLAUDE.md
git commit -F - <<'EOF'
docs: record the agent-usage cards (Claude + Codex) in CLAUDE.md

Architecture entry for the agent-usage collectors + orchestrator and the
Quickshell Agents/AgentsPanel widget; doc-index pointer to the design +
plan. Fleet-wide via the quickshell symlink; scripts need the standard
~/.local/bin symlink per machine.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3
EOF
```

- [x] **Step 4: Laptop rollout (machine-local — DONE on `nomad-artix` 2026-09-03)**

Not part of the desktop build; recorded here so it is not lost. On the laptop (directly or over SSH), after `git pull` in both repos:
```bash
for s in agent-usage agent-usage-claude agent-usage-codex; do
  ln -sf ~/projects/i3-screen-manager/$s ~/.local/bin/$s   # repo ROOT — there is no bin/ (see Post-build corrections)
done
agent-usage | jq -e 'type=="array"'          # collectors work on the laptop
qs kill; qs -p ~/.config/quickshell          # QML already inherited via the symlink
```
The widget self-hides for any agent not signed in there; no laptop-specific tuning.
Laptop result (2026-09-03): both collectors `ready` through the symlinks on the first
run (~4.5 s cold, Python 3.14 stdlib only). One gotcha worth knowing: if Quickshell
was (re)started *before* the symlinks exist, its first poll logs
`WARN: Process failed to start ... Command: QList("agent-usage")` and the item stays
hidden until the 10-min timer re-polls — restart the bar (or wait) after symlinking.

---

## Self-Review

- **Spec coverage:** data layer (Tasks 1-2), bar item + self-hide + fleet-wide mount (Task 3), all cards - limits/today/by-model (Task 4), docs + fleet rollout (Task 5). Tokens-by-day from `recentDays` was in the spec as secondary; omitted from v1 for compactness (by-model is the richer glance) - note if you want it added, it is a sibling Repeater over `recentDays` using `messageCount`.
- **Placeholder scan:** none - all steps carry real code. The one conditional is the PATH fallback in Task 3 Step 3 (bare `agent-usage` vs `$HOME/.local/bin/agent-usage`), resolved by an explicit check.
- **Type consistency:** `records` is an array of the contract everywhere; `percent` treated as 0..1 in both `Agents.qml` (`maxPercent`) and `AgentsPanel.qml` (meters); `modelUsage` is `[{key,value:{…Tokens}}]` consumed by `topModels`/`modelTotal`; `recentDays[].messageCount` noted as tokens.
- **Icon risk:** the robot glyph `9` is verified visually in Task 3 Step 4 (fallback noted inline).

---

## Post-build corrections (2026-09-03, EXECUTED)

Built and shipped the same day. Three deviations from the plan-as-written, all
caught during live verification (this is what the checkpoints are for):

1. **Scripts live at the repo ROOT, not `bin/`.** This repo keeps its ~15
   scripts at top level, symlinked from `~/.local/bin/`; there is no `bin/`
   subdir. Every `i3-screen-manager/bin/X` above means repo-root `X`
   (`~/projects/i3-screen-manager/agent-usage`, `.../agent-usage-claude`,
   `.../agent-usage-codex`). The `~/.local/bin/` and `~/projects/omarchy/bin/`
   paths were already correct and unchanged.
2. **`modelUsage` is a dict `{model: {...Tokens}}`, not `[{key,value}]`.** The
   spec/plan mis-stated the shape (an earlier probe's `jq to_entries` had
   converted the dict, so it only looked like an array). `topModels` was fixed to
   iterate object keys (and still handles the array shape defensively). This was
   the one real bug the Task 4 visual check surfaced: model bars rendered empty
   until the fix.
3. **Model labels strip the `claude-` vendor tag** (`claude-opus-4-8` ->
   `opus-4-8`) via a `shortModel()` helper; Codex's `gpt-5.6-sol` is left as-is.
   A post-verification polish Jim chose.

Vendored collectors verified live (Claude Max 20x, Codex pro); `agent-usage`
resolved on the Quickshell session PATH with no fallback needed. Commits:
i3-screen-manager `cdc43f3` (collectors), `9feba37` (orchestrator); dotfiles
`7a176fe` (bar item), `6cca7fc` (cards).
