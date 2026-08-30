# Quickshell Bar Implementation Plan

> **STATUS: EXECUTED 2026-08-28.** All 13 tasks completed inline in one Hyprland
> session; the MVP shipped and Waybar was retired (dotfiles `39cddc7`..`44b9733`).
> Deviations that arose during the build, worth knowing before extending it:
> `Rectangle` delegates in a `RowLayout` need `Layout.preferredWidth/Height`;
> `font.families` is unsupported (use `font.family`); `transform` is a FINAL
> property (the PollText stdout hook is `format`); TX-02 has no nerd glyphs so
> icons render in an explicit `Symbols Nerd Font` and network uses `f0200`
> (Waybar's `f796` is Font-Awesome-only); cpu folds `iowait` into idle. Kept as
> the build record.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Waybar on the `godlike-artix` desktop with a hand-written, lightly-modular Quickshell shell that reaches feature parity, fixes the #5008 workspace-click regression, and leaves room for rich popouts later.

**Architecture:** A `shell.qml` entry (`ShellRoot`) spawns one opaque top `PanelWindow` per monitor via `Variants` over `Quickshell.screens`, composing left/center/right widget components. A `Theme` singleton holds no-frills style tokens; reusable `BarText`/`PollText` primitives keep each widget terse. Native Quickshell services drive Hyprland/clock/tray; `Process` polls drive the `/proc`+`/sys`+`wpctl` widgets.

**Tech Stack:** Quickshell 0.3.1 (QtQuick/QML), Hyprland 0.56.1 (Lua config mode), Wayland/wlroots (aquamarine), bash `Process` polls.

**Spec:** `docs/2026-08-28-hyprland-fresh-start-rebuild.md` (§ Phase A decision + this build's design). Throwaway PoC that proved feasibility: `~/quickshell-bar-poc/shell.qml`.

## Global Constraints

- **Aesthetic (hard):** no animations, square corners (`radius: 0`), fully opaque (no transparency/blur), no-frills. (memory `feedback_no_frills_aesthetic`.)
- **Deployment:** config lives in `~/projects/dotfiles/.config/quickshell/`, symlinked to `~/.config/quickshell` (same pattern as `~/.config/hypr`). Never edit the deployed symlink target through the link; edit the dotfiles source.
- **Waybar is unhooked, not deleted.** Cutover comments out the Waybar launch so revert is one line. `mako` stays as the notification daemon.
- **Per-monitor workspace pools:** DP-2 → workspaces 1-6, HDMI-A-1 → 7-10 (mirrors the `hl.workspace_rule` bindings already in `hyprland-desktop.lua`).
- **Workspace clicks MUST use the Lua-mode dispatch form:** `hyprctl dispatch 'hl.dsp.focus({ workspace = "N" })'` via `Quickshell.execDetached` — never the legacy `dispatch workspace N` string (that's the #5008 bug).
- **Live-reload:** `qs` watches its config dir and reloads on save, so the dev loop is edit → save → read the qs task log for errors → eyeball. No manual restart per change.
- **Commits:** private repo, normal style; end every commit message with the two trailers:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01123dqZCk5QF17sk2hYUqh3`.

## Testing model (domain-adapted)

There is no unit-test harness for a QML shell. Each task's "test" is:
1. **Clean-load check:** after saving, the running `qs` auto-reloads; read its task-output log and confirm `Configuration Loaded` with **no** `WARN`/`ERR`/QML errors referencing the changed file.
2. **Data cross-check:** run the widget's authoritative source command yourself and confirm the on-screen value matches (Jim eyeballs the pixel; you compute the source-of-truth).
3. **Interaction check:** where a widget has a click/scroll, Jim performs it and you confirm the effect via `hyprctl`/process state.

Launch for the whole session (leave running; it auto-reloads):
```bash
SIG=$(for d in "$XDG_RUNTIME_DIR"/hypr/*/; do s=$(basename "$d"); HYPRLAND_INSTANCE_SIGNATURE="$s" hyprctl version >/dev/null 2>&1 && { echo "$s"; break; }; done)
env HYPRLAND_INSTANCE_SIGNATURE="$SIG" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" qs -p ~/.config/quickshell &
```
Log to watch: the background task's output file (grep for `Configuration Loaded|error|warn`).

## File Structure

```
~/projects/dotfiles/.config/quickshell/     (symlinked to ~/.config/quickshell)
  shell.qml            ShellRoot: per-monitor PanelWindow assembly + workspace-pool map
  Theme.qml            singleton: color/font/size tokens
  BarText.qml          styled Text (Theme-driven) — base for text widgets
  PollText.qml         BarText that reruns a command every N ms and shows a transform of stdout
  Widgets/
    Workspaces.qml     per-monitor workspace pool, click-to-focus (#5008-correct)
    WindowTitle.qml    active window title, elided to 80 chars
    Clock.qml          SystemClock -> "4:37 PM 2026-08-28"
    Cpu.qml            /proc/stat delta -> "  NN%"
    Memory.qml         free -> "  used/total G"
    Temperature.qml    k10temp hwmon -> "NN°C "
    Network.qml        eth* operstate -> "  ethN" / "⚠ disconnected"
    Pulseaudio.qml     wpctl poll -> "NN% <icon>" + mic; click -> pavucontrol
    IdleInhibitor.qml  toggle: elogind-inhibit --what=idle holder
    Tray.qml           Quickshell.Services.SystemTray
```

Each `Widgets/*.qml` has one responsibility and is independently reloadable. `shell.qml` is the only file that knows the bar layout and the per-monitor pool map.

---

### Task 1: Scaffold — Theme, primitives, per-monitor bar skeleton, deploy

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Theme.qml`
- Create: `~/projects/dotfiles/.config/quickshell/BarText.qml`
- Create: `~/projects/dotfiles/.config/quickshell/PollText.qml`
- Create: `~/projects/dotfiles/.config/quickshell/shell.qml`
- Symlink: `~/.config/quickshell` → `~/projects/dotfiles/.config/quickshell`

**Interfaces:**
- Produces: `Theme` singleton (`bg`, `bgAlt`, `fg`, `fgDim`, `accent`, `font`, `fontSize`, `barHeight`, `gap`); `BarText` (a `Text` with `property string value`); `PollText` (`command:[]`, `interval:int`, `transform:fn`, exposes `text`); `shell.qml` exposes per-bar `required property var modelData` (the screen) and a `poolFor(name)` helper returning the workspace-id list.

- [ ] **Step 1: Create the config dir and symlink it**

```bash
mkdir -p ~/projects/dotfiles/.config/quickshell/Widgets
ln -sfn ~/projects/dotfiles/.config/quickshell ~/.config/quickshell
ls -la ~/.config/quickshell   # confirm the symlink resolves into dotfiles
```

- [ ] **Step 2: Write `Theme.qml` (singleton tokens)**

```qml
pragma Singleton
import Quickshell
import QtQuick

Singleton {
    readonly property color bg:      "#161616"
    readonly property color bgAlt:   "#232323"
    readonly property color fg:      "#e6e6e6"
    readonly property color fgDim:   "#888888"
    readonly property color accent:  "#3b6ea5"
    readonly property string fontFamily: "monospace"
    readonly property int fontSize:  13
    readonly property int barHeight: 28
    readonly property int gap:       8
}
```

- [ ] **Step 3: Write `BarText.qml`**

```qml
import QtQuick
import qs

Text {
    property string value: ""
    text: value
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
}
```

- [ ] **Step 4: Write `PollText.qml`**

```qml
import QtQuick
import Quickshell.Io
import qs

BarText {
    id: root
    property var command: []
    property int interval: 2000
    property var transform: (s) => s.trim()

    Process {
        id: proc
        command: root.command
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.value = root.transform(this.text)
        }
    }
    Timer {
        interval: root.interval
        running: true
        repeat: true
        onTriggered: proc.running = true
    }
}
```

- [ ] **Step 5: Write `shell.qml` (per-monitor empty bars)**

```qml
//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs

ShellRoot {
    // Per-monitor workspace pools (mirrors hl.workspace_rule bindings).
    readonly property var pools: ({ "DP-2": [1,2,3,4,5,6], "HDMI-A-1": [7,8,9,10] })
    function poolFor(name) { return pools[name] || [1,2,3,4,5] }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            readonly property var pool: poolFor(modelData.name)

            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.barHeight
            exclusionMode: ExclusionMode.Auto
            WlrLayershell.namespace: "qs-bar"
            WlrLayershell.layer: WlrLayer.Top
            color: Theme.bg

            // Left / center / right anchors — widgets land here in later tasks.
            RowLayout {
                id: left
                anchors { left: parent.left; leftMargin: Theme.gap; verticalCenter: parent.verticalCenter }
                spacing: Theme.gap
            }
            RowLayout {
                id: center
                anchors.centerIn: parent
                spacing: Theme.gap
            }
            RowLayout {
                id: right
                anchors { right: parent.right; rightMargin: Theme.gap; verticalCenter: parent.verticalCenter }
                spacing: Theme.gap
            }
        }
    }
}
```

- [ ] **Step 6: Launch qs and verify clean load + empty bars on both monitors**

Run the launch block from the "Testing model" section, then:
```bash
sleep 0 # (do not use foreground sleep; just read the log on the next tool call)
grep -iE 'Configuration Loaded|error|warn' <qs-task-output>
hyprctl layers -j | jq -r '[.. | objects | select(.namespace?=="qs-bar")] | length'  # expect 2
```
Expected: `Configuration Loaded`, no errors, **2** `qs-bar` surfaces. If `Theme`/`qs` import fails, fix the import mechanics here (this is the one task where singleton/module wiring is shaken out) before proceeding.

- [ ] **Step 7: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Theme.qml .config/quickshell/BarText.qml .config/quickshell/PollText.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): scaffold — theme, primitives, per-monitor bar skeleton"
```

---

### Task 2: Clock widget (center)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Clock.qml`
- Modify: `shell.qml` (add `Clock {}` to the `center` RowLayout, `import qs.Widgets`)

**Interfaces:**
- Consumes: `BarText`, `Theme`. Produces: `Clock` (self-contained, no properties needed).

- [ ] **Step 1: Write `Widgets/Clock.qml`**

```qml
import Quickshell
import qs

BarText {
    value: Qt.formatDateTime(clock.date, "h:mm AP yyyy-MM-dd")
    SystemClock { id: clock; precision: SystemClock.Minutes }
}
```

- [ ] **Step 2: Wire into `shell.qml`**

Add `import qs.Widgets` near the top imports, and inside the `center` RowLayout:
```qml
            RowLayout {
                id: center
                anchors.centerIn: parent
                spacing: Theme.gap
                Clock {}
            }
```

- [ ] **Step 3: Verify clean load + format matches Waybar**

```bash
grep -iE 'Configuration Loaded|error|warn' <qs-task-output>
date +'%-I:%M %p %F'   # Waybar's exact format, e.g. "4:37 PM 2026-08-28"
```
Expected: the center of both bars shows the same time/date shape as `date` output. (`h:mm AP` gives `4:37 PM`; `yyyy-MM-dd` gives the date.) Jim confirms visually.

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Clock.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): center clock widget"
```

---

### Task 3: Tray widget (right)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Tray.qml`
- Modify: `shell.qml` (add `Tray {}` to `right`)

**Interfaces:**
- Consumes: `Theme`. Produces: `Tray` (self-contained). API verified in the PoC/Omarchy: `SystemTray.items`, `modelData.icon`, `modelData.activate()`, `modelData.secondaryActivate()`.

- [ ] **Step 1: Write `Widgets/Tray.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs

RowLayout {
    spacing: Theme.gap
    Repeater {
        model: SystemTray.items
        Item {
            required property var modelData
            implicitWidth: 18
            implicitHeight: 18
            Image {
                anchors.fill: parent
                source: modelData.icon
                sourceSize.width: 18
                sourceSize.height: 18
                fillMode: Image.PreserveAspectFit
                smooth: false
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => m.button === Qt.LeftButton
                    ? modelData.activate() : modelData.secondaryActivate()
            }
        }
    }
}
```

- [ ] **Step 2: Wire into `shell.qml`** — add `Tray {}` as the last item of the `right` RowLayout.

- [ ] **Step 3: Verify** — clean load; tray icons appear on the right of the bar. Cross-check count:
```bash
grep -iE 'Configuration Loaded|error|warn' <qs-task-output>
```
Jim confirms the same tray apps as Waybar show, and a left-click opens one.

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Tray.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): system tray widget"
```

> **Update (2026-08-28): tray context menus (Discord "Quit").** The first cut
> mapped right-click to `secondaryActivate()` — but in the SNI spec that's the
> *middle*-click action, so an app whose only full-exit is a tray **context-menu**
> item (Discord) had an unreachable menu and the icon looked dead on every button.
> Fix: right-click -> `modelData.display(window, x, y)` (the item's own native
> menu), middle -> `secondaryActivate()`, and menu-only items (`onlyMenu`) open on
> left too. `display()` renders a *platform* menu, which Quickshell **refuses
> unless the shell root declares `//@ pragma UseQApplication`** — ours does (Task
> 1), so no extra work was needed. Verified live (probe logged `hasMenu=true`,
> `display at 2508,23`): right-click Discord -> Open/Quit. The `display()` signature
> was confirmed against the installed qmltypes before use
> (`SystemTrayItem.display(parentWindow, relativeX, relativeY)`).

---

### Task 4: Workspaces widget with per-monitor pools (left) — the #5008 fix

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Workspaces.qml`
- Modify: `shell.qml` (add `Workspaces { pool: bar.pool }` to `left`)

**Interfaces:**
- Consumes: `Theme`; `pool` (array of workspace ids from `shell.qml`). Produces: `Workspaces` (`property var pool`). API: `Hyprland.workspaces.values` (each `.id`, `.toplevels.values`), `Hyprland.focusedWorkspace.id`.

- [ ] **Step 1: Write `Widgets/Workspaces.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs

RowLayout {
    id: root
    property var pool: [1,2,3,4,5]
    spacing: 4

    function wsById(id) {
        var v = Hyprland.workspaces.values
        for (var i = 0; i < v.length; i++) if (v[i].id === id) return v[i]
        return null
    }

    Repeater {
        model: root.pool
        Rectangle {
            id: btn
            required property var modelData
            readonly property int wsId: modelData
            readonly property var ws: root.wsById(wsId)
            readonly property bool focused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId
            readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0

            implicitWidth: 26
            implicitHeight: 20
            radius: 0
            color: focused ? Theme.accent : Theme.bgAlt

            Text {
                anchors.centerIn: parent
                text: String(btn.wsId)
                color: btn.focused ? "#ffffff" : (btn.occupied ? Theme.fg : Theme.fgDim)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.execDetached(
                    ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + btn.wsId + "\" })"])
            }
        }
    }
}
```

- [ ] **Step 2: Wire into `shell.qml`** — first item of `left`: `Workspaces { pool: bar.pool }`.

- [ ] **Step 3: Verify per-monitor pools + click dispatch (#5008)**

```bash
grep -iE 'Configuration Loaded|error|warn' <qs-task-output>
# baseline:
hyprctl monitors -j | jq -r '.[] | "\(.name): pool-shown-should-be \(if .name=="DP-2" then "1-6" else "7-10" end)"'
```
Expected: DP-2 bar shows `1 2 3 4 5 6`, HDMI-A-1 bar shows `7 8 9 10`. Jim clicks a number on each bar; confirm focus moves:
```bash
hyprctl monitors -j | jq -r '.[] | "\(.name): activeWs=\(.activeWorkspace.id)"'
```
This is the capability Waybar lacks under Lua mode — clicks MUST switch.

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Workspaces.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): per-monitor workspace pools with working Lua-mode clicks"
```

---

### Task 5: WindowTitle widget (left)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/WindowTitle.qml`
- Modify: `shell.qml` (add after `Workspaces` in `left`)

**Interfaces:**
- Consumes: `Theme`, `BarText`. Produces: `WindowTitle`. API: `Hyprland.activeToplevel` (nullable), `.title`. (If `activeToplevel` is unavailable on 0.3.1, fall back to `Hyprland.focusedMonitor.activeWorkspace` last-window; confirm on load and adjust.)

- [ ] **Step 1: Write `Widgets/WindowTitle.qml`**

```qml
import QtQuick
import Quickshell.Hyprland
import qs

BarText {
    color: Theme.fgDim
    elide: Text.ElideRight
    maximumLineCount: 1
    Layout.maximumWidth: 600
    value: Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : ""
}
```
(Note: `Layout.maximumWidth` requires the widget to sit in a `RowLayout`, which it does. Waybar caps at 80 chars; a pixel cap with elide is the QML-idiomatic equivalent.)

- [ ] **Step 2: Wire into `shell.qml`** — second item of `left`: `WindowTitle {}`.

- [ ] **Step 3: Verify** — clean load; focusing different windows updates the title. Cross-check:
```bash
hyprctl activewindow -j | jq -r '.title'
```
Expected: bar text matches the focused window's title (elided if long).

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/WindowTitle.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): active window-title widget"
```

---

### Task 6: CPU widget (right)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Cpu.qml`
- Modify: `shell.qml` (add to `right`, first)

**Interfaces:**
- Consumes: `PollText`, `Theme`. Produces: `Cpu`. Source: two `/proc/stat` reads 1s apart → busy %.

- [ ] **Step 1: Write `Widgets/Cpu.qml`**

```qml
import qs

PollText {
    interval: 2000
    command: ["sh", "-c",
        "S=$(grep '^cpu ' /proc/stat); sleep 1; E=$(grep '^cpu ' /proc/stat); " +
        "echo \"$S $E\" | awk '{a=$2+$3+$4+$5+$6+$7+$8; ai=$5; " +
        "b=$11+$12+$13+$14+$15+$16+$17; bi=$14; " +
        "printf \"%d\", (1-(bi-ai)/(b-a))*100}'"]
    transform: (s) => "  " + s.trim() + "%"   // nerd-font cpu glyph; adjust to taste
}
```

- [ ] **Step 2: Wire into `shell.qml`** — in `right` (order per Waybar: idle, pulseaudio, network, cpu, memory, temperature, tray — cpu goes 4th; final ordering happens in Task 12, add here for now).

- [ ] **Step 3: Verify against source**

```bash
grep -iE 'Configuration Loaded|error|warn' <qs-task-output>
S=$(grep '^cpu ' /proc/stat); sleep 1; E=$(grep '^cpu ' /proc/stat); echo "$S $E" | awk '{a=$2+$3+$4+$5+$6+$7+$8; ai=$5; b=$11+$12+$13+$14+$15+$16+$17; bi=$14; printf "%d\n", (1-(bi-ai)/(b-a))*100}'
```
Expected: bar value tracks this number (±a few %, it's sampled).

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Cpu.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): cpu widget"
```

---

### Task 7: Memory widget (right)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Memory.qml`
- Modify: `shell.qml`

**Interfaces:**
- Consumes: `PollText`. Produces: `Memory`. Source: `free -b` → used/total in GiB, matching Waybar's `{used:0.1f}G/{total:0.1f}G`.

- [ ] **Step 1: Write `Widgets/Memory.qml`**

```qml
import qs

PollText {
    interval: 10000
    command: ["sh", "-c",
        "free -b | awk '/^Mem:/{printf \"%.1fG/%.1fG\", $3/1073741824, $2/1073741824}'"]
    transform: (s) => "  " + s.trim()   // nerd-font memory glyph; adjust to taste
}
```

- [ ] **Step 2: Wire into `shell.qml`** (in `right`).

- [ ] **Step 3: Verify**

```bash
free -b | awk '/^Mem:/{printf "%.1fG/%.1fG\n", $3/1073741824, $2/1073741824}'
```
Expected: bar matches (e.g. `6.7G/125.7G`).

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Memory.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): memory widget"
```

---

### Task 8: Temperature widget (right)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Temperature.qml`
- Modify: `shell.qml`

**Interfaces:**
- Consumes: `PollText`. Produces: `Temperature`. Source: `k10temp` hwmon `temp1_input` (millidegrees).

- [ ] **Step 1: Confirm the CPU hwmon on this box**

```bash
for h in /sys/class/hwmon/*; do echo "$(cat "$h/name")  $h"; done
# expect a line: k10temp  /sys/class/hwmon/hwmonN
```
If the CPU sensor is not `k10temp`, substitute its `name` in the command below.

- [ ] **Step 2: Write `Widgets/Temperature.qml`**

```qml
import qs

PollText {
    interval: 5000
    command: ["sh", "-c",
        "for h in /sys/class/hwmon/*; do " +
        "[ \"$(cat \"$h/name\" 2>/dev/null)\" = k10temp ] && " +
        "awk '{printf \"%d\", $1/1000}' \"$h/temp1_input\" && break; done"]
    transform: (s) => s.trim() + "°C "
}
```

- [ ] **Step 3: Verify**

```bash
for h in /sys/class/hwmon/*; do [ "$(cat "$h/name" 2>/dev/null)" = k10temp ] && awk '{printf "%d\n", $1/1000}' "$h/temp1_input" && break; done
```
Expected: bar shows the same `NN°C`.

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Temperature.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): temperature widget"
```

---

### Task 9: Network widget (right)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Network.qml`
- Modify: `shell.qml`

**Interfaces:**
- Consumes: `PollText`. Produces: `Network`. Source: first `eth*` iface `operstate`. Matches Waybar `format-ethernet " {ifname}"` / `format-disconnected "⚠ disconnected"`.

- [ ] **Step 1: Write `Widgets/Network.qml`**

```qml
import qs

PollText {
    interval: 5000
    command: ["sh", "-c",
        "for i in /sys/class/net/eth* /sys/class/net/en*; do " +
        "[ -e \"$i/operstate\" ] || continue; " +
        "if [ \"$(cat \"$i/operstate\")\" = up ]; then echo \"up $(basename \"$i\")\"; exit 0; fi; done; " +
        "echo down"]
    transform: (s) => {
        var p = s.trim().split(" ")
        return p[0] === "up" ? "  " + p[1] : "⚠ disconnected"
    }
}
```

- [ ] **Step 2: Wire into `shell.qml`.**

- [ ] **Step 3: Verify**

```bash
for i in /sys/class/net/eth* /sys/class/net/en*; do [ -e "$i/operstate" ] && echo "$(basename "$i") $(cat "$i/operstate")"; done
```
Expected: bar shows the up ethernet iface name, or `⚠ disconnected`.

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Network.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): network widget"
```

---

### Task 10: Pulseaudio widget (right)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/Pulseaudio.qml`
- Modify: `shell.qml`

**Interfaces:**
- Consumes: `PollText`, `Theme`. Produces: `Pulseaudio`. Source: `wpctl get-volume` for sink + source; click → `pavucontrol`. (Chosen over native Pipewire QML for write-without-test robustness; a native `Quickshell.Services.Pipewire` upgrade is a later refinement.)

- [ ] **Step 1: Write `Widgets/Pulseaudio.qml`**

```qml
import QtQuick
import Quickshell
import qs

PollText {
    id: pa
    interval: 2000
    command: ["sh", "-c",
        "sink=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null); " +
        "src=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null); " +
        "echo \"$sink | $src\""]
    transform: (s) => {
        // "Volume: 0.55 [MUTED] | Volume: 0.40"
        function pct(part) {
            var m = part.match(/Volume: ([0-9.]+)/)
            var v = m ? Math.round(parseFloat(m[1]) * 100) : 0
            var muted = /MUTED/.test(part)
            return { v: v, muted: muted }
        }
        var parts = s.split("|")
        var out = pct(parts[0] || "")
        var mic = pct(parts[1] || "")
        var sinkIcon = out.muted ? "" : ""   // muted / speaker
        var micIcon  = mic.muted ? "" : ""   // mic-off / mic
        return (out.muted ? "muted " : out.v + "% ") + sinkIcon + "  " + micIcon + " " + mic.v + "%"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["pavucontrol"])
    }
}
```
(Glyphs are nerd-font placeholders; Jim retunes. The regex tolerates `wpctl`'s `[MUTED]` suffix.)

- [ ] **Step 2: Wire into `shell.qml`.**

- [ ] **Step 3: Verify**

```bash
wpctl get-volume @DEFAULT_AUDIO_SINK@; wpctl get-volume @DEFAULT_AUDIO_SOURCE@
```
Expected: bar percentage matches (0.55 → 55%); Jim clicks it → `pavucontrol` opens; muting toggles the icon within one interval.

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/Pulseaudio.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): pulseaudio widget"
```

---

### Task 11: IdleInhibitor widget (right)

**Files:**
- Create: `~/projects/dotfiles/.config/quickshell/Widgets/IdleInhibitor.qml`
- Modify: `shell.qml`

**Interfaces:**
- Consumes: `Theme`, `BarText`. Produces: `IdleInhibitor`. Mechanism: a toggle that holds an `elogind-inhibit --what=idle` process (consistent with the repo's existing `elogind-inhibit` clamshell pattern) while active.

- [ ] **Step 1: Write `Widgets/IdleInhibitor.qml`**

```qml
import QtQuick
import Quickshell.Io
import qs

BarText {
    id: inh
    property bool active: false
    value: active ? "" : ""   // eye / eye-slash
    color: active ? Theme.accent : Theme.fgDim

    Process {
        id: holder
        command: ["elogind-inhibit", "--what=idle", "--who=quickshell-bar",
                  "--why=manual", "sleep", "infinity"]
        running: inh.active
    }
    MouseArea {
        anchors.fill: parent
        onClicked: inh.active = !inh.active
    }
}
```

- [ ] **Step 2: Wire into `shell.qml`** (first item of `right`, matching Waybar order).

- [ ] **Step 3: Verify**

Jim clicks it → icon flips to the active state. Cross-check the holder process:
```bash
pgrep -af 'elogind-inhibit .*quickshell-bar'   # present when active, gone when toggled off
```
Expected: process appears/disappears with the toggle. (If idle isn't actually inhibited, note it — hypridle may need the Wayland idle-inhibit protocol instead; a `Quickshell.Wayland` inhibitor is the fallback. Flag, don't block.)

- [ ] **Step 4: Commit**

```bash
git -C ~/projects/dotfiles add .config/quickshell/Widgets/IdleInhibitor.qml .config/quickshell/shell.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): idle-inhibitor toggle"
```

---

### Task 12: Layout / parity / no-frills styling pass

**Files:**
- Modify: `shell.qml` (finalize right-side order + spacing), `Theme.qml` (retune tokens if needed)

**Interfaces:** none new.

- [ ] **Step 1: Finalize the `right` RowLayout order** to match Waybar exactly:

```qml
            RowLayout {
                id: right
                anchors { right: parent.right; rightMargin: Theme.gap; verticalCenter: parent.verticalCenter }
                spacing: Theme.gap
                IdleInhibitor {}
                Pulseaudio {}
                Network {}
                Cpu {}
                Memory {}
                Temperature {}
                Tray {}
            }
```
And `left`: `Workspaces { pool: bar.pool }` then `WindowTitle {}`; `center`: `Clock {}`.

- [ ] **Step 2: Side-by-side compare against Waybar**

Waybar is still running (not yet retired). Jim eyeballs both bars stacked and confirms: same modules, same order, readable at a glance, square/opaque/static (no-frills), no clipping on the narrow portrait bar (1200px logical width — confirm the right cluster fits or elides gracefully).

- [ ] **Step 3: Verify clean load and commit**

```bash
grep -iE 'Configuration Loaded|error|warn' <qs-task-output>
git -C ~/projects/dotfiles add .config/quickshell/shell.qml .config/quickshell/Theme.qml
git -C ~/projects/dotfiles commit -m "feat(quickshell): finalize module order and no-frills styling"
```

---

### Task 13: Cutover — retire Waybar, launch Quickshell from the session

**Files:**
- Modify: `~/projects/dotfiles/.config/hypr/hyprland-desktop.lua` (line ~134 autostart; the `Super+Shift+W` restart bind ~line 544)

**Interfaces:** none.

- [ ] **Step 1: Swap the autostart launch**

Find:
```lua
    hl.exec_cmd("sleep 1 && waybar & mako")
```
Replace with (keeps mako; launches qs against the deployed config):
```lua
    -- Quickshell bar (replaces Waybar; see docs/2026-08-28-quickshell-bar-plan.md).
    -- Waybar retained in-repo for one-line revert.
    hl.exec_cmd("sleep 1 && qs -p ~/.config/quickshell & mako")
```

- [ ] **Step 2: Swap the restart bind**

Find:
```lua
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("pkill waybar; waybar"))
```
Replace with:
```lua
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("pkill -f 'qs -p'; qs -p ~/.config/quickshell"))
```

- [ ] **Step 3: Kill the dev qs + Waybar, reload, and let the session own the bar**

```bash
pkill -f 'qs -p' 2>/dev/null; pkill waybar 2>/dev/null
hyprctl reload            # re-reads config; autostart exec runs on login, so start qs manually now:
qs -p ~/.config/quickshell & disown
hyprctl layers -j | jq -r '[.. | objects | select(.namespace?=="qs-bar")] | length'   # expect 2
```
Expected: only the Quickshell bar present (no `waybar` process), 2 `qs-bar` surfaces.

- [ ] **Step 4: Full parity confirmation**

Jim runs a normal workflow for a few minutes: workspace switching via bar clicks and `Super+N`, tray interaction, audio change, window focus changes. Confirm every Waybar module's info is present and live, on both monitors, portrait included.

- [ ] **Step 5: Commit the cutover**

```bash
git -C ~/projects/dotfiles add .config/hypr/hyprland-desktop.lua
git -C ~/projects/dotfiles commit -m "feat(hypr): retire Waybar, launch Quickshell bar from the session"
```

- [ ] **Step 6: Update the design doc** — mark the Phase-A bar decision as executed and link this plan; commit in `i3-screen-manager`.

---

## Self-Review

**Spec coverage:** every Waybar module in the parity inventory (workspaces, window, clock, idle_inhibitor, pulseaudio, network, cpu, memory, temperature, tray) maps to a task (4, 5, 2, 11, 10, 9, 6, 7, 8, 3). Structure (lightly modular), per-monitor pools, no-frills aesthetic, dotfiles+symlink deploy, launch/bind swap with Waybar retained, mako kept — all present (Tasks 1, 4, 12, 13). Popouts are explicitly out of MVP scope (design doc "then, incrementally").

**Placeholder scan:** no TBD/TODO; every widget ships real QML and a concrete cross-check command. The two flagged uncertainties (`Hyprland.activeToplevel` availability in Task 5; whether `elogind-inhibit` actually pauses hypridle in Task 11) carry an explicit fallback and are non-blocking — they are verification branches, not missing content.

**Type consistency:** `Theme` token names are used identically across all widgets; `PollText` contract (`command`/`interval`/`transform`, writes `value`) is consistent in Tasks 6-10; `BarText.value` used consistently; `Workspaces.pool` produced by `shell.qml poolFor()` and consumed in Task 4; glyph placeholders are labeled as retunable, not load-bearing.

**Known live-shakeout point:** Task 1 Step 6 is where Quickshell singleton/module import mechanics (`pragma Singleton` + `import qs` / `import qs.Widgets`) are proven against the running compositor; if the import spelling differs on 0.3.1, fix it there before building widgets on top.

---

## Update (2026-08-29): per-monitor compact bar

The narrow portrait panel (HDMI-A-1, 1200px wide after `transform=3`) ran the full
right-side system cluster into the centered clock. Fix: `shell.qml` gives each
`PanelWindow` a `readonly property bool compact: modelData.height > modelData.width`,
and the right slot wraps the system widgets (Weather / IdleInhibitor / Pulseaudio /
Network / Cpu / Memory / Temperature) in a `RowLayout { visible: !bar.compact }`,
leaving **Tray** always shown. So a portrait panel keeps only workspaces + window
title (left), clock (center), tray (right); landscape panels keep the full set.
Orientation-based, not name-based, so it auto-applies to any portrait monitor
(incl. laptop externals). Verified via `hyprctl layers`: HDMI-A-1's `qs-bar` reports
w=1200 (rotated/logical), so `compact` resolves true there and false on DP-2 (w=2560).

## Update (2026-08-29): qs-kill restart + a rare SNI tray crash

Two things surfaced reviewing the bar on the desktop:

**Restart must use `qs kill`, not `pkill -f '^qs '`.** The bar-restart bind
(`Super+Shift+W`) and any manual relaunch previously did `pkill -f '^qs '; qs -p …`.
That pattern does NOT kill a running bar: once launched, `qs` re-execs and its command
line becomes `/usr/bin/quickshell`, so `pkill -f '^qs '` matches nothing and the
relaunch spawns a SECOND bar (visible as two stacked bars per monitor). Fixed by
switching the bind to **`qs kill; qs -p ~/.config/quickshell`** — `qs kill` is
Quickshell's native "kill every instance"; `qs list` shows what's running. (And
`pkill -f quickshell` is NOT a safe substitute in a *tool/agent* shell — it
self-matches any command line containing "quickshell", including the shell running the
pkill, so it kills itself mid-command.)

**Rare SNI tray crash (upstream Quickshell 0.3.1).** Quickshell segfaulted once with
the stacktrace in Qt6Core I/O (`QIOVectoredWriteOperation`) and the last log line
`quickshell.service.sni.watcher: Unregistered StatusNotifierItem … from watcher` — it
died tearing down a tray item as **Keybase's flaky Electron tray icon** churned. QML is
memory-safe (can't segfault), so this is a Quickshell/Qt bug, not the config. Rare (one
crash observed). If it recurs: file upstream with the report under
`~/.cache/quickshell/crashes/<id>/`, and/or wrap the autostart in a restart loop so the
bar self-heals.

## Update (2026-08-29): Network + Temperature widgets go cross-machine

Both widgets were originally desktop-hardcoded — the laptop bar showed `down`
in Network and just `°C` (no number) in Temperature after graduation. Root
cause was single-source assumptions:

- `Network.qml`: probed only `/sys/class/net/eth*` + `/en*` (wired). Laptop
  has no wired link when undocked, so all probes failed → `down`.
- `Temperature.qml`: matched only the hwmon `name == k10temp` (AMD Ryzen —
  the desktop's CPU sensor). Laptop is Intel and exposes CPU package temp
  via `coretemp` (hwmon8 on this X1E Gen 5), so the loop found nothing and
  emitted an empty string → just `°C`.

Fix is runtime auto-detection, kept in a single QML source per widget:

- `Network.qml` now scans `eth* → en* → wl*` in preference order. Wired
  wins when both are up (docked laptop future), wireless is the fallback.
  Both machines display the same "first up interface" semantic; the
  interface *name* naturally differs (`eth0` / `wlp5s0` / `wlan0` / …).
- `Temperature.qml` accepts either `k10temp` or `coretemp` as the hwmon
  name; a machine has one or the other (never both), so first hit wins.
  Both machines display the same "CPU package temp" semantic; the
  underlying sensor is whichever this box exposes.

No `machine.lua` branching, no per-machine widget variant. The alternative
(one widget file per machine, or a QML singleton reading machine identity)
was rejected as premature: both machines want the same *semantic* metric,
and the sysfs abstraction already differentiates by what the kernel exposes.
Reach for the structural per-machine path if a future need is something
stronger — e.g., laptop wants **battery** temp instead of CPU temp, or
desktop wants a specific mobo sensor over the CPU package.

Live-verified on the laptop 2026-08-29 (`wlan0` in Network, `51°C` in
Temperature). The desktop keeps its `eth0` / `k10temp` readings unchanged
after pull because those pattern-match first in the same scans.

## Update (2026-08-29): CMOS coin-cell (CR2032) widget

Ported the desktop's polybar `cmos-battery` indicator to the bar — Jim's
sanity gauge, because "when that battery goes low all hell breaks loose"
(it87 Vbat drop → BIOS corruption / boot failures / PCIe instability).

- **`Widgets/CmosBattery.qml`** (new) follows the **`Battery.qml` shape**, not
  `PollText`, because it needs the two things PollText can't do: **self-hide**
  when the sensor is absent (no it87 → laptop), and **status-driven color**
  (OK → `fg`, LOW → `warn`, DEAD → `crit`). It *runs* the shared
  `i3-cmos-battery quickshell` (new output mode: `<volts> <status>`) rather than
  re-reading hwmon in QML — the script stays the single source of truth for the
  CR2032 thresholds. Glyph mirrors Battery's alarm treatment: full-battery when
  OK, **battery_alert** when LOW/DEAD, so a dying cell reads as a *warning*.
- **`Theme.qml`** gained `warn` (`#F0C674`) + `crit` (`#A54242`) — the alarm
  palette, matching i3-cmos-battery's own colors, reusable by future widgets.
- **`shell.qml`** places `CmosBattery {}` in the `!compact` system cluster, so
  it shows on the **main (landscape) monitor only** — the portrait panel stays
  compact, and the laptop self-hides for lack of the sensor. 6h poll interval
  (matches the old polybar module; the cell drifts glacially).

Live-verified on the desktop (`CMOS 3.29V`, OK/fg). Aside caught during the
screenshot check: the adjacent `0%`/`1%` is the **Cpu** widget at idle (a cpu
Nerd glyph that reads battery-ish at 28px), not a phantom `Battery{}` —
`/sys/class/power_supply/` is empty on the desktop, so `Battery{}` correctly
self-hides.

## Update (2026-08-30): Battery glyph — plug on AC, level bucket on battery

The prior `Battery.qml` showed `battery_charging` (single glyph, no level)
while `state == Charging`, and level-bucket glyphs otherwise. That was a lie
on AC: `state == Full` (charged to 100% and plugged in) fell through to the
level-bucket branch and showed a **full-battery** glyph, indistinguishable
from `state == Discharging` at 100%. Same on `Not charging` (some laptops
throttle charging when a threshold is met). So the icon claimed "on battery"
even while plugged in.

Now the glyph is a **semantic switch**:
- On AC → **`nf-md-power_plug`** (0xf06a5, filled — matches the filled-battery
  aesthetic already there).
- On battery → level bucket (0..9 → `nf-md-battery_10..nf-md-battery`), as before.
- On battery + capacity < 15 → `battery_alert` (unchanged: warning glyph, not level).

"On AC" is an explicit whitelist — `Charging || Full || Not charging` — rather
than `!= Discharging`, so a transient `Unknown` state (firmware quirks at boot)
falls through to the level-bucket branch instead of lying with a plug. The `low`
warning still gates on `!plugged` (plugged in with 5% is charging, not
concerning). The `%` text is untouched, so level info stays readable next to
the plug on AC.

Nerd Font codepoints verified via `fontTools.ttLib` against
`~/.local/share/fonts/NFM.ttf` on the laptop before shipping (a check worth
doing whenever a new codepoint enters the bar — MDI ↔ Symbols Nerd Font
mapping is stable but not universal across font revisions). Live-tested on the
laptop plugged/unplugged.
