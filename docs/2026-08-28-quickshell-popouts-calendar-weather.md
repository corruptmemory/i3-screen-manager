# Quickshell popouts: calendar + weather

**Desktop (`godlike-artix`), 2026-08-28.** The hand-written Quickshell bar
(`2026-08-28-quickshell-bar-plan.md`) grew its first two popouts: a month-grid
**calendar** hung off the clock, and a **weather** pill (Open-Meteo) with a
4-day forecast popout. Both ride one small reusable `Popout.qml`. No-frills
throughout: square, opaque, accent-bordered, **no open/close animation**.

Files (all under `dotfiles/.config/quickshell/`, SHARED via the
`~/.config/quickshell` symlink):

| File | Role |
|---|---|
| `Popout.qml` | Reusable popout: `PopupWindow` anchored below a bar item + `HyprlandFocusGrab` click-outside dismiss. ~55 lines. |
| `Widgets/Calendar.qml` | Month grid, Sunday-start, ISO week numbers. Pure local date math, no network. |
| `Widgets/Clock.qml` | Rewritten from a bare `BarText` to a `MouseArea` that toggles the calendar popout. |
| `Widgets/Weather.qml` | Weather pill (icon + °F) + owner of the Open-Meteo fetch + `wxIcon`/`wxText` helpers + the forecast popout. |
| `Widgets/WeatherForecast.qml` | Popout content: current-conditions hero over a 4-day forecast. |
| `shell.qml` | Added `Weather {}` to the head of the right cluster. |

## The reusable core — `Popout.qml`

The whole popout mechanism is two native Quickshell primitives:

- **`PopupWindow`** anchored via `anchor.window` (the bar's `QsWindow.window`,
  NOT `anchor.item`). Position is computed in `onAnchoring:` with
  `window.contentItem.mapFromItem(target, localX, localY)`, centred under the
  trigger and clamped to the screen. The bar is always top, so the popup always
  drops downward.
- **`HyprlandFocusGrab { windows: [popup, barWindow]; onCleared: close() }`** for
  click-outside dismissal. **Listing the bar window in the grab is load-bearing**:
  it lets a second click on the trigger toggle-close instead of the grab eating
  the click and reopening it.

The API was cribbed verbatim from Omarchy's `shell/Ui/PopupCard.qml` (the one
piece of Omarchy worth lifting) — but stripped of its plugin machinery
(per-widget IPC handlers, popout coordinators, `injectPanel`/`switchPanelFrom`,
opacity animations). Our version is a padded opaque `Rectangle` with a 1px
accent border and a default-property content slot; loose children land in the
padded card, explicit children (card/anchor/grab) stay on the window.

Contract: `Popout { anchorItem: <the bar Item>; <content> }`, driven by an
`open` bool and a `toggle()` method.

## Calendar

- **Sunday-start** (US convention). Week-number column is the **ISO week of each
  row's Thursday** — Thursday is the canonical ISO-week determinant, so the
  numbers stay coherent under a Sunday-start layout (a naive "first cell's ISO
  week" would be wrong, because a Sunday-start row's leading Sunday belongs to
  the previous ISO week).
- A **read-out, not a picker**: today is the only marked day (accent block);
  chevrons and the scroll wheel step the month; clicking the "Month YYYY" label
  snaps back to today.
- `today` is refreshed by a `SystemClock { precision: Hours }` so the highlight
  rolls over at midnight without reopening.
- Zero network, zero external data — a clock-click can never fail or hang.

### Future: events from life-dashboard (the seam)

Jim's `~/projects/life-dashboard/` is already a Go app that merges Google +
Microsoft calendars (one polling actor per source, recurring-event dedup done,
OAuth done) and *also* pulls Open-Meteo weather. The **eventual** "sane Google
calendar cache" is not a second cache to build for the bar — life-dashboard
already is that cache. The clean integration:

1. life-dashboard grows a tiny local JSON endpoint, e.g. `GET
   /api/events/upcoming`.
2. `Calendar.qml` gains an `Upcoming` region fed by
   `curl -s --max-time 1 http://127.0.0.1:8080/api/events/upcoming` — the same
   "shell out to a command" pattern every widget already uses.
3. When life-dashboard is down, the curl fails fast and the popout just shows
   the month grid (graceful degradation, which life-dashboard itself preaches).

Nothing for this is built yet; the calendar was written to leave room for it.

## Weather

- **Open-Meteo, no API key.** One request per poll returns current conditions +
  the daily forecast together; fetched every 20 min and **parsed as JSON in QML**
  (no `jq`). One `Process` feeds both the pill and the popout. A `try/catch`
  keeps the last-good reading if a poll times out.
- Request: `current=temperature_2m,weather_code,is_day` +
  `daily=weather_code,temperature_2m_max,temperature_2m_min`,
  `temperature_unit=fahrenheit`, `timezone=auto`, `forecast_days=4`.
- **WMO `weather_code` -> Material-Design nerd glyph** (`wxIcon`), day/night
  split only for clear skies. All 11 glyphs verified present in
  `SymbolsNerdFont-Regular.ttf` via a `fontTools` cmap check before use — they
  live above U+FFFF, so they're built with `String.fromCodePoint(0xF05xx)`, NOT
  a `"\uXXXX"` escape (which only encodes 4 hex digits). Same lesson as the bar's
  `f0200` network glyph: prefer the Material-Design (`f0xxx`) set, which is fully
  present, over Font-Awesome codepoints that Symbols Nerd Font may lack.
- Forecast rows parse the ISO date with **local date parts**
  (`new Date(y, m-1, d)`), never `new Date(iso)`, so the weekday label never
  shifts across the UTC boundary. Row 0 is labelled "Today".

### Location is a desktop hardcode

`lat/lon` are Ridgewood, NJ, baked into `Weather.qml`. That is correct for a
desktop that never moves. **The laptop will need this to become dynamic**
(geolocation, or per-network) — flagged in the code comment and in the
laptop-parity guide. Do not copy the hardcode to the laptop unchanged.

## Verification

Live under Hyprland (Wayland), Quickshell 0.3.1. `qs` auto-reloads on file save;
its stderr log (`qs log`, or the running instance's log file) shows
`Configuration Loaded` with no QML errors across every step of this build. Both
popouts confirmed visually: calendar drops under the clock with today
highlighted and month-stepping working; weather pill shows `<icon> 73°F` and the
click-popout shows current + 4-day forecast. Click-outside and second-click-to-
close both dismiss.

## Laptop notes (for the future laptop session)

- The `quickshell/` config is SHARED, so `Popout.qml` / `Calendar.qml` /
  `Weather.qml` / `WeatherForecast.qml` arrive with a `git pull`. The wiring in
  `shell.qml` (the `Weather {}` slot) and `Clock.qml` is shared too.
- **Weather location must become dynamic** on the laptop — the Ridgewood
  hardcode is desktop-only. Simplest first step: read a machine-local
  `~/.config/quickshell/weather-location` file, or geolocate.
- Calendar needs nothing laptop-specific; it's pure local date math.
- Same `curl`/`jq`-free JSON path; `curl` is already present fleet-wide.
