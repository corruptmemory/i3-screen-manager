# Agent Usage

Read this guide for the Python collectors, their caches, JSON output, or the
agent widgets. Sources: `agent-usage`, `agent-usage-claude`, `agent-usage-codex`,
`lib/agent-usage/collectors.py`, `agent-usage-polybar`, `agent-usage-rofi`,
dotfiles' `Widgets/Agents.qml` and
`AgentsPanel.qml` under `.config/quickshell/`, and the `agent-usage` polybar
module in dotfiles' `.config/polybar/config-i3.ini` and `config-i3-laptop.ini`.

## Collection and Storage

The collectors are vendored from `basecamp/omarchy` (MIT); retain attribution
and `lib/agent-usage/LICENSE`. They use Python's standard library and print one
JSON record each. The Bash
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
from its OAuth usage endpoint using the existing login; the weekly row is the
`seven_day` bucket, and the plan comes from `~/.claude.json`. The collector does
not refresh that login. Transport failures can set `retryAdvised`.

Codex scans `CODEX_HOME` (default `~/.codex`) session and archived-session
files, `.jsonl` and compressed `.jsonl.zst`, plus supported pi/omp/opencode
sources. Limits are read via a temporary `codex app-server` subprocess:
`initialize`, then `account/rateLimits/read`, with `account/read` only as a
fallback for the plan name. It reads every bucket in `rateLimitsByLimitId`, and
reports free reset credits as `resetCredits`. The subprocess is terminated after
the query. Scanner support is limited to the formats the code parses; a new CLI
storage format needs verification.

Both collectors keep the last good limits per signed-in identity. When a probe
fails, the record carries those limits with `limitsStale` true and
`limitsFetchedAt` naming when they were measured. Codex reports a window that
has already reset at zero.

Normal local-scan reuse is 20 seconds; `--limits-only` permits reuse for 900
seconds. Both collectors reuse a limits answer younger than 15 seconds.
`--force` bypasses all reuse.
Preserve date-sensitive caches, file locking, and token accounting when
changing these paths. In native Codex usage, cached input is already included
in input totals and reasoning is included in output; do not count either twice.

## Upstream Sync

`agent-usage-claude`, `agent-usage-codex`, and `lib/agent-usage/collectors.py`
are upstream's `bin/omarchy-agent-usage-claude`, `bin/omarchy-agent-usage-codex`,
and `shell/plugins/agents/collectors.py`; each file's header names the upstream
commit. These are the only local edits:

1. Both entry scripts load `collectors.py` from `lib/agent-usage/` beside their
   resolved path instead of `$OMARCHY_PATH`.
2. `cache_root()` drops upstream's `omarchy/` path segment.
3. `program()` names diagnostics after the `agent-usage-` commands.
4. The attribution header in each file.

Left as upstream and inert here: the account registry and local Codex provider
files under `~/.local/state/omarchy/agents/`, read only when present; the
`OMARCHY_AGENT_USAGE_REFRESH_AT` hint; and the app-server client name.

To re-sync, copy the three files from the new upstream commit, reapply the
edits, and compare each collector's record against the current one with
isolated `XDG_CACHE_HOME` and `XDG_STATE_HOME` before deploying. Clear
`~/.cache/agent-usage/` when the cache format may have changed.

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
| `hasPromptStats` | Boolean; always true from these two collectors |
| `limitsStale`, `limitsFetchedAt` | Limits kept from an earlier probe; when measured, in epoch milliseconds (0 if never) |
| `resetCredits` | Codex only, optional: `{available, nextExpiresAt}` |

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
shows agent limits, reset countdowns, today counters, and today's top four
models. The model bars rank on `todayTokensByModel`, so they agree with the
today line above them; lifetime `modelUsage` would bury the current workhorse
model behind historical heavyweights.

The i3/Polybar path presents the same JSON without Quickshell.
`agent-usage-polybar` is a `custom/script` module formatter: it runs
`agent-usage --limits-only`, prints the robot glyph (wrapped in `%{T2}` for the
bar's nerd font) plus the highest ready-agent limit percent, colored at the same
0.75/0.9 thresholds, and prints nothing when nothing is ready so the module
self-collapses. Its `click-left` opens `agent-usage-rofi`, a read-only rofi list
that renders each agent as header, text-meter limit rows with reset countdowns,
a today line, and today's top-model bars, reading the cached state files (kept fresh by
the module) with a live `agent-usage` fallback. The module is on the desktop's
landscape bar only and on the laptop's single bar. Presentation lives in these
scripts, not in `agent-usage`.

Claude is ready with prompts, model usage, or limits; Codex with sessions,
limits, or registered accounts. The current QML has no manual refresh control,
no fast retry for `retryAdvised`, and no marking of `limitsStale`; do not
document any of them as available. Antigravity has no
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
