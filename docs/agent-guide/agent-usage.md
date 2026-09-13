# Agent Usage

Read this guide for the Python collectors, their caches, JSON output, or the
agent widgets. Sources: `agent-usage`, `agent-usage-claude`, `agent-usage-codex`,
`agent-usage-polybar`, `agent-usage-rofi`, dotfiles' `Widgets/Agents.qml` and
`AgentsPanel.qml` under `.config/quickshell/`, and the `agent-usage` polybar
module in dotfiles' `.config/polybar/config-i3.ini`.

## Collection and Storage

The collectors are vendored from `basecamp/omarchy` (MIT); retain attribution.
They use Python's standard library and print one JSON record each. The Bash
orchestrator resolves sibling collectors with `readlink -f`, runs them in
parallel, checks successful stdout with jq, and prints an array in
Claude/Codex order. A failed collector is omitted; both failing produces `[]`.
Success here means parseable JSON, not schema validation.

Successful records are atomically cached to
`${XDG_STATE_HOME:-$HOME/.local/state}/agent-usage/{claude,codex}.json`.
Failures do not remove previous records. Collector caches live beneath
`${XDG_CACHE_HOME:-$HOME/.cache}/agent-usage/`. A retained file is not proof
of a fresh measurement. Agent credentials/transcripts are inputs; cache/state
files are outputs. Do not expose credentials in JSON, logs, or tests.

Claude reads `CLAUDE_CONFIG_DIR` (default `~/.claude`), project transcripts,
aggregate/history fallbacks, and supported pi/omp/opencode usage. Limits come
from its OAuth usage endpoint using the existing login. The collector does
not refresh that login. It can reuse cached limits on failure, excluding
windows whose reset time has passed; transport failures can set `retryAdvised`.

Codex scans `CODEX_HOME` (default `~/.codex`) session and archived-session
JSONL plus supported pi/omp/opencode sources. Limits are read via a temporary
`codex app-server` subprocess using `initialize`, `account/read`, and
`account/rateLimits/read`. The collector reads primary and secondary limit
windows; do not assume it implements every shape a newer server might expose.
The subprocess is terminated after the query. Scanner support is limited to
the formats the code parses; a new CLI storage format needs verification.

Normal local-scan reuse is 20 seconds; `--limits-only` permits reuse for 900
seconds. `--force` bypasses that reuse. Claude also throttles successful limit
probes over a 15-second interval unless forced; Codex probes limits each run.
Preserve date-sensitive caches, file locking, and token accounting when
changing these paths. In native Codex usage, cached input is already included
in input totals and reasoning is included in output; do not count either twice.

## JSON Contract

| Field | Meaning |
|-------|---------|
| `schemaVersion` | Integer `1` |
| `id`, `name`, `updatedAt` | Agent identifier, display name, UTC timestamp |
| `ready`, `hasLocalStats` | Booleans used by consumers; readiness is not an authentication guarantee |
| `tierLabel`, `usageStatusText`, `authHelpText` | Plan/status/help strings |
| `limits` | Array with `label`, `percent`, `resetsAt`, and optional `title` |
| `todayPrompts`, `todaySessions`, `todayTotalTokens` | Today's integer counters |
| `todayTokensByModel` | Object mapping model names to token totals |
| `modelUsage` | Object keyed by model, with `inputTokens`, `outputTokens`, `cacheCreationInputTokens`, `cacheReadInputTokens` |
| `recentDays` | Array of `{date, messageCount}`; `messageCount` contains token totals |
| `totalPrompts`, `totalSessions`, `activeDays` | Aggregate counters |
| `retryAdvised` | Optional retry hint; not acted on by the current widget |

`limits[].percent` is a fraction, not an integer percentage. Consumers multiply
by 100 for labels and clamp meter fill. `resetsAt` is a timestamp or an empty
string. `modelUsage` is an object, not an array; per-model totals sum its four
token fields. Do not hardcode plan names, model names, or a fixed number of
limit windows.

## UI and Known Limitations

`Agents.qml` starts a collection at bar startup and every 600000 ms. It reads
stdout, not the saved record files. If `agent-usage` is not on PATH when the
bar starts, that first poll fails (`Process failed to start` in `qs log`) and
the item stays hidden until the next interval; restart the bar after
installing the symlinks. A malformed result leaves its prior UI
state; an array replaces it. The widget filters on `ready`, displays the
highest limit, and uses warning/critical thresholds of 0.75/0.9. Its panel
shows agent limits, reset countdowns, today counters, and the top four models.

The i3/Polybar path presents the same JSON without Quickshell.
`agent-usage-polybar` is a `custom/script` module formatter: it runs
`agent-usage --limits-only`, prints the robot glyph (wrapped in `%{T2}` for the
bar's nerd font) plus the highest ready-agent limit percent, colored at the same
0.75/0.9 thresholds, and prints nothing when nothing is ready so the module
self-collapses. Its `click-left` opens `agent-usage-rofi`, a read-only rofi list
that renders each agent as header, text-meter limit rows with reset countdowns,
a today line, and top-model bars, reading the cached state files (kept fresh by
the module) with a live `agent-usage` fallback. The module is on the landscape
bar only. Presentation lives in these scripts, not in `agent-usage`.

Readiness differs between collectors: Claude requires prompts or limits;
Codex currently sets `ready=true` even when its limit probe fails. An
unauthenticated Codex record may therefore keep the bar item visible.
The current QML has no manual refresh control and no fast retry for
`retryAdvised`; do not document either as available. Antigravity has no
collector in this repo. Account limits describe account usage; local token
statistics only cover the sources available on this machine.

## Agent-Usage Verification

Check each record and the merged array with jq; verify schema types, empty
data, absent tools/auth, expired reset windows, failures retaining old cache
files, and simultaneous invocations. Use isolated cache/state directories and
fixtures for automated checks. Verify fractional meters and model totals
against the records in the actual widget when changing its contract. Syntax
checks alone do not verify remote account limits or UI rendering.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
