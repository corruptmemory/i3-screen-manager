# IceWM-on-XLibre Trial — Implementation Plan + Execution Log

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, this session — live X + Xephyr testing and user-in-the-loop tweaks make subagent-per-task a poor fit). Steps use checkbox (`- [ ]`) syntax for tracking. Append gotchas/decisions under each task as it executes (mirrors the PekWM `-plan.md`).

**Goal:** Stand up IceWM 4.0 as a third toggleable WM on `godlike-artix`, reproducing the current PekWM daily-driver setup (click-to-focus+raise, GNOME-style maximize, send-to-workspace with focus survival, rofi, titlebarless + cyan border, native taskbar), evaluated against the success criteria in `2026-06-16-icewm-x11-setup.md`.

**Architecture:** `start-icewm` = X11 sibling of `start-pekwm` → `exec startx ~/.xinitrc-icewm` → `icewm-session`. Config in dotfiles `.icewm/{preferences,keys,winoptions}`, symlinked to `~/.icewm/`. Native IceWM taskbar (no Polybar). Additive/reversible — Hyprland and PekWM untouched.

**Tech Stack:** IceWM 4.0.0 (Artix `world` repo), XLibre X server, rofi, flameshot (x11 config), xdotool/wmctrl/xprop for verification, Xephyr for isolated smoke-testing.

**Spec:** `docs/2026-06-16-icewm-x11-setup.md`. **Config syntax note:** IceWM's `preferences`/`keys`/`winoptions` formats are stable and well-documented, but a few exact option names (titlebar-off lever, native tiling keys, mouse-modifier) are confirmed in Task 1 before later tasks rely on them. Draft config blocks below are the expected syntax; Task 1 validates/corrects.

---

### Task 1: Install IceWM + recon (resolve the spec's open items)

**Files:** none yet (capture findings into this doc under "Task 1 — findings").

- [x] **Step 1: Install from the official repo (not AUR)**

Run: `yay -S --noconfirm icewm` (or `sudo pacman -S icewm`)
Expected: installs `icewm 4.0.0-1` from `world`. Verify: `icewm --version`.

- [x] **Step 2: Locate defaults + docs**

Run:
```bash
ls /usr/share/icewm/
for m in icewm icewm-preferences icewm-keys icewm-winoptions icewm-theme icewm-session; do man -w "$m" 2>/dev/null && echo "  ^ $m"; done
```
Expected: a `preferences` defaults file under `/usr/share/icewm/`, and man pages present.

- [x] **Step 3: Confirm the exact option/key names this plan depends on**

Capture the real names (grep the installed defaults — authoritative over memory):
```bash
D=/usr/share/icewm/preferences
grep -E '^#? *(ClickToFocus|RaiseOnClickClient|ShowTaskBar|TaskBarShow|WorkspaceNames|DesktopBackgroundImage|ColorActiveBorder|ColorNormalBorder|QuickSwitch)=' "$D"
grep -E '^#? *KeyWin(Maximize|Restore|Close|Fullscreen)=' "$D"
grep -E '^#? *KeySysWorkspace(TakeWindow)?[0-9]+=' "$D"
grep -iE 'tile' "$D" || echo "no native tiling keys -> Task 5 uses the xdotool helper"
man icewm-winoptions | grep -iE 'title|border|decor|frame' | head    # confirm the titlebar-off option name
```
Record into "Task 1 — findings" below: exact names for each, whether native tiling keys exist, and the winoptions key that removes the title bar (candidates: a per-class decoration/`noTitleBar`-style flag, else fall back to a titleH=0 theme).

- [x] **Step 4: Commit the findings note**

```bash
cd /home/jim/projects/i3-screen-manager
git add docs/2026-06-16-icewm-x11-setup-plan.md
git commit -m "icewm: Task 1 recon — confirmed IceWM 4.0 option/key names"
```

**Task 1 — findings (2026-06-16):**

- `icewm 4.0.0` installed from `world`. Defaults at `/usr/share/icewm/{preferences,keys,winoptions,toolbar}`; all man pages present. Native control CLI: **`icesh`** (`icesh keys` / `icesh winoptions` reload those files; `icesh restart`; EWMH-based, ships with IceWM).
- **Corrections to the draft config below (applied when writing the real files in Tasks 2–3/5):**
  1. **Tray option** is `TaskBarEnableSystemTray=1` (there is no `TaskBarShowSystemTray`); `TaskBarShowTray=1` shows app icons in the tray panel.
  2. **Border-color format uses slashes:** `ColorActiveBorder="rgb:33/CC/FF"`, `ColorNormalBorder="rgb:33/33/33"`.
  3. **Titlebarless is a winoptions DECOR option and can be GLOBAL:** `.dTitleBar: 0` (leading-dot form ⇒ all windows); keep borders with `.dBorder: 1`. → `winoptions` becomes one global rule, no per-class list (per-class override still possible, e.g. `KittyFloating.dTitleBar: 1`).
  4. **Half-tiling is NATIVE:** `KeyWinTileLeft/Right/Top/Bottom` (+ corners/center) exist → Task 5 uses **path A** (native keys); the wmctrl `icewm-snap` helper is **dropped**.
  5. **No absolute send-to-workspace key** (only relative `KeySysWorkspace{Next,Prev,Last}TakeWin`). → bind `Super+Shift+N` to **`icesh -f setWorkspace <idx>`** directly in `keys` (verify 0- vs 1-indexing + focus-survival in Task 4; wrap in a helper only if focus is lost).
  6. **`wmctrl` unavailable** (confirmed); use `xdotool`/`icesh`. IceWM `keys` runs `program + args` (no shell) ⇒ no `~` expansion, no inline compound commands ⇒ absolute paths / helper scripts.
- Confirmed as drafted: `ClickToFocus=1`, `RaiseOnClickClient=1`, `QuickSwitch=1`, `WorkspaceNames`, `DesktopBackgroundImage/Scaled`, `KeyWin{Maximize,Restore,Close,Fullscreen}`, `KeySysWorkspace1..10`.
- ⚠️ Self-inflicted nit: an `icesh -f setWorkspace 1` parse-check was run against the **live `:0`** session; if a window was focused it may have hopped a workspace. Lesson: mutating `icesh`/`xdotool` tests go in Xephyr (Task 4), never `:0`.

---

### Task 2: Core `preferences` (focus, taskbar, workspaces, colors, wallpaper, window/workspace keys)

**Files:**
- Create: `/home/jim/projects/dotfiles/.icewm/preferences`
- Symlink: `~/.icewm -> /home/jim/projects/dotfiles/.icewm` (dir symlink, matching `~/.pekwm`)

- [ ] **Step 1: Create the dotfiles dir and symlink**

```bash
mkdir -p /home/jim/projects/dotfiles/.icewm
ln -sfn /home/jim/projects/dotfiles/.icewm /home/jim/.icewm
```

- [ ] **Step 2: Write `preferences`** (correct any names per Task 1 findings)

```ini
# ~/.icewm/preferences — godlike-artix IceWM trial. See i3-screen-manager
# docs/2026-06-16-icewm-x11-setup{,-plan}.md.

# --- Focus: click-to-focus + raise (focused window is topmost) ---
ClickToFocus=1
RaiseOnClickClient=1
FocusOnAppRaise=1
PointerColormap=1

# --- Decoration colors (titlebars off via winoptions; border = focus cue) ---
ColorActiveBorder="rgb:33CCFF"
ColorNormalBorder="rgb:333333"

# --- Workspaces (10, named) ---
WorkspaceNames=" 1 ", " 2 ", " 3 ", " 4 ", " 5 ", " 6 ", " 7 ", " 8 ", " 9 ", " 10 "

# --- Native taskbar: pager + window list + tray + clock + cpu/net ---
ShowTaskBar=1
TaskBarShowWorkspaces=1
TaskBarShowWindows=1
TaskBarShowSystemTray=1
TaskBarShowClock=1
TaskBarShowCPUStatus=1
TaskBarShowNetStatus=1
TaskBarShowMEMStatus=0
TaskBarShowMailboxStatus=0
TaskBarShowStartMenu=0
TaskBarShowShowDesktopButton=0
TimeFormat="%a %b %d  %H:%M"

# --- Wallpaper owned by IceWM (icewmbg); feh dropped from this session ---
DesktopBackgroundImage="/home/jim/.config/wallpaper/earth.jpg"
DesktopBackgroundScaled=1

# --- Alt+Tab native quick-switch kept ---
QuickSwitch=1

# --- Window action keys (KeyWin*) ---
KeyWinMaximize="Super+Up"
KeyWinRestore="Super+Down"
KeyWinMaximizeVert="Super+f"
KeyWinClose="Super+q"
KeyWinFullscreen="Super+Shift+f"

# --- Workspace keys (KeySys*): goto + take-window, 1..10 ---
KeySysWorkspace1="Super+1"
KeySysWorkspace2="Super+2"
KeySysWorkspace3="Super+3"
KeySysWorkspace4="Super+4"
KeySysWorkspace5="Super+5"
KeySysWorkspace6="Super+6"
KeySysWorkspace7="Super+7"
KeySysWorkspace8="Super+8"
KeySysWorkspace9="Super+9"
KeySysWorkspace10="Super+0"
KeySysWorkspaceTakeWindow1="Super+Shift+1"
KeySysWorkspaceTakeWindow2="Super+Shift+2"
KeySysWorkspaceTakeWindow3="Super+Shift+3"
KeySysWorkspaceTakeWindow4="Super+Shift+4"
KeySysWorkspaceTakeWindow5="Super+Shift+5"
KeySysWorkspaceTakeWindow6="Super+Shift+6"
KeySysWorkspaceTakeWindow7="Super+Shift+7"
KeySysWorkspaceTakeWindow8="Super+Shift+8"
KeySysWorkspaceTakeWindow9="Super+Shift+9"
KeySysWorkspaceTakeWindow10="Super+Shift+0"
```

- [ ] **Step 3: Confirm the wallpaper path exists** (fix the path to the real file)

Run: `ls -l /home/jim/.config/wallpaper/earth.jpg` (or `grep -r feh /home/jim/projects/dotfiles/.xinitrc-desktop` to find the path PekWM/feh uses). Update `DesktopBackgroundImage` to the actual file.

- [ ] **Step 4: Commit**

```bash
cd /home/jim/projects/dotfiles && git add .icewm/preferences && git commit -m "icewm: core preferences (focus, taskbar, workspaces, maximize/workspace keys)"
```

---

### Task 3: `keys` (launchers/media) + `winoptions` (titlebarless)

**Files:**
- Create: `/home/jim/projects/dotfiles/.icewm/keys`
- Create: `/home/jim/projects/dotfiles/.icewm/winoptions`

- [ ] **Step 1: Write `keys`** (shell commands; absolute paths for local scripts — the PekWM `~`-not-expanding lesson, applied defensively)

```text
# ~/.icewm/keys — godlike-artix. Launchers/media; window+workspace actions live
# in preferences (KeyWin*/KeySys*).
key "Super+Return"         kitty
key "Super+Shift+Return"   kitty --class KittyFloating
key "Super+space"          rofi -modi drun,run -show drun
key "Super+Tab"            rofi -show window
key "Super+d"              rofi -show run
key "Super+b"              brave --remote-debugging-port=9222 --profile-directory=Default --new-window
key "Super+e"              emacs
key "Super+Shift+b"        rofi-rbw
key "Super+Shift+l"        i3lock -c 000000
key "Print"                flameshot gui
key "Super+Ctrl+BackSpace" /home/jim/.local/bin/i3-keyboard-rofi
key "Super+F1"             xdotool search --class slack windowactivate
key "Super+F2"             xdotool search --class keybase windowactivate
key "Super+F3"             xdotool search --class discord windowactivate
key "XF86AudioRaiseVolume" wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
key "XF86AudioLowerVolume" wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
key "XF86AudioMute"        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
key "XF86AudioPlay"        playerctl play-pause
key "XF86AudioNext"        playerctl next
key "XF86AudioPrev"        playerctl previous
```

- [ ] **Step 2: Write `winoptions`** for titlebarless on the apps in daily use (use the exact option key confirmed in Task 1; example assumes `noTitleBar`)

```text
# ~/.icewm/winoptions — remove the title bar per WM_CLASS (IceWM matches by class).
# If Task 1 finds a global lever (theme titleH=0), prefer that and shrink this list.
kitty.noTitleBar: 1
Brave-browser.noTitleBar: 1
Emacs.noTitleBar: 1
Slack.noTitleBar: 1
discord.noTitleBar: 1
```

- [ ] **Step 3: Commit**

```bash
cd /home/jim/projects/dotfiles && git add .icewm/keys .icewm/winoptions && git commit -m "icewm: keys (launchers/media) + winoptions (titlebarless)"
```

---

### Task 4: Xephyr smoke test + behavioral verification

**Files:** none (verification only). Uses the harness proven this session.

- [ ] **Step 1: Launch a nested IceWM**

```bash
Xephyr -br -ac -resizeable -screen 1600x1000 :3 >/dev/null 2>&1 &
sleep 1; DISPLAY=:3 icewm-session >/tmp/icewm-xephyr.log 2>&1 &
sleep 2; echo "icewm in Xephyr:"; DISPLAY=:3 wmctrl -m 2>/dev/null | head -2
```
Expected: `wmctrl -m` reports `Name: IceWM`. Check `/tmp/icewm-xephyr.log` for config parse errors.

- [ ] **Step 2: Verify focus model = click-to-focus (hover must NOT steal focus)**

```bash
export DISPLAY=:3
kitty --class FX_A sh -c 'sleep 90' & kitty --class FX_B sh -c 'sleep 90' &
sleep 1.5
WA=$(xdotool search --class FX_A|head -1); WB=$(xdotool search --class FX_B|head -1)
xdotool windowmove "$WA" 80 80; xdotool windowmove "$WB" 850 80; sleep 0.3
xdotool windowactivate "$WA"; sleep 0.4
echo "before hover: $(xdotool getactivewindow) (A=$WA)"
xdotool mousemove 1000 200; sleep 0.6
echo "after hover B: $(xdotool getactivewindow) (A=$WA means click-to-focus OK; B=$WB means sloppy)"
xdotool search --class FX_A windowkill; xdotool search --class FX_B windowkill
```
Expected: after-hover active == A (click-to-focus).

- [ ] **Step 3: Verify maximize honors the taskbar strut + send-to-workspace keeps focus**

```bash
export DISPLAY=:3
kitty --class MX sh -c 'sleep 60' &; sleep 1.2; WM=$(xdotool search --class MX|head -1)
xdotool windowsize "$WM" 500 350; xdotool windowactivate "$WM"; sleep 0.4
echo "before: $(xdotool getwindowgeometry "$WM"|awk '/Geometry/{print $2}')"
xdotool key --clearmodifiers super+Up; sleep 0.6
echo "maximized: $(xdotool getwindowgeometry "$WM"|awk '/Geometry/{print $2}') (height < screen => strut honored)"
xdotool key --clearmodifiers super+Down; sleep 0.5
echo "restored: $(xdotool getwindowgeometry "$WM"|awk '/Geometry/{print $2}')"
xdotool search --class MX windowkill
# send-to-workspace + focus survival
kitty --class SW_A sh -c 'sleep 60' & kitty --class SW_B sh -c 'sleep 60' &; sleep 1.4
WA=$(xdotool search --class SW_A|head -1); WB=$(xdotool search --class SW_B|head -1)
xdotool windowactivate "$WA"; sleep 0.4
xdotool key --clearmodifiers super+shift+2; sleep 0.7
echo "after send A->ws2: active=$(xdotool getactivewindow) (want B=$WB; empty => bug present, add helper)"
xdotool search --class SW_A windowkill; xdotool search --class SW_B windowkill
```
Expected: maximized height < full screen; restore returns ~500x350; after send, active == B (focus survives — the §5 prediction). If active is empty, note it and port `pekwm-send-to-ws` as `icewm-send-to-ws` (KeySysWorkspaceTakeWindow has no winid arg → helper uses `wmctrl -r :ACTIVE: -t <N-1>` then activates the survivor).

- [ ] **Step 4: Tear down Xephyr; record results under "Task 4 — findings"; commit the doc**

```bash
DISPLAY=:3 pkill -f 'icewm-session'; pkill -f 'Xephyr.*:3'
cd /home/jim/projects/i3-screen-manager && git add docs/2026-06-16-icewm-x11-setup-plan.md && git commit -m "icewm: Task 4 — Xephyr behavioral verification results"
```

**Task 4 — findings:** _(fill during execution; especially the focus-survival result, which decides whether Task 5b is needed)_

---

### Task 5: Half-screen snapping (native if present, else xdotool helper)

**Files (path B only):**
- Create: `/home/jim/projects/dotfiles/.local/bin/icewm-snap`
- Symlink: `~/.local/bin/icewm-snap`

- [ ] **Step 1 (path A): If Task 1 found native tiling keys**, add to `preferences` and commit:

```ini
KeyWinTileLeft="Super+Shift+Left"
KeyWinTileRight="Super+Shift+Right"
KeyWinTileTop="Super+Shift+Up"
KeyWinTileBottom="Super+Shift+Down"
```
Then skip to Step 4.

- [ ] **Step 2 (path B): Else write `icewm-snap`** (half-screen via wmctrl against the active monitor work area)

```bash
#!/usr/bin/env bash
# icewm-snap left|right|top|bottom — half-screen the active window using the
# work area (EWMH _NET_WORKAREA, so the taskbar strut is respected).
set -u
side="${1:?usage: icewm-snap left|right|top|bottom}"
read -r wx wy ww wh < <(xprop -root _NET_WORKAREA | awk -F'[ ,]+' '{print $3, $4, $5, $6}')
case "$side" in
  left)   x=$wx;            y=$wy; w=$((ww/2)); h=$wh ;;
  right)  x=$((wx+ww/2));   y=$wy; w=$((ww/2)); h=$wh ;;
  top)    x=$wx; y=$wy;            w=$ww; h=$((wh/2)) ;;
  bottom) x=$wx; y=$((wy+wh/2));   w=$ww; h=$((wh/2)) ;;
  *) exit 2 ;;
esac
wid=$(xdotool getactivewindow)
wmctrl -ir "$wid" -b remove,maximized_vert,maximized_horz
xdotool windowsize "$wid" "$w" "$h"; xdotool windowmove "$wid" "$x" "$y"
```

- [ ] **Step 3 (path B): Deploy + bind** in `keys`

```bash
chmod +x /home/jim/projects/dotfiles/.local/bin/icewm-snap
ln -sf /home/jim/projects/dotfiles/.local/bin/icewm-snap /home/jim/.local/bin/icewm-snap
```
Append to `~/.icewm/keys`:
```text
key "Super+Shift+Left"   /home/jim/.local/bin/icewm-snap left
key "Super+Shift+Right"  /home/jim/.local/bin/icewm-snap right
key "Super+Shift+Up"     /home/jim/.local/bin/icewm-snap top
key "Super+Shift+Down"   /home/jim/.local/bin/icewm-snap bottom
```

- [ ] **Step 4: Verify in Xephyr** (relaunch as Task 4 Step 1), snap a window left, assert width ≈ half work-area and x==workarea-left; commit.

```bash
cd /home/jim/projects/dotfiles && git add .icewm/ .local/bin/icewm-snap 2>/dev/null; git commit -m "icewm: half-screen snapping (Super+Shift+arrows)"
```

---

### Task 6: Session integration — `start-icewm` + `.xinitrc-icewm`

**Files:**
- Create: `/home/jim/projects/dotfiles/.local/bin/start-icewm` (clone of `start-pekwm`)
- Symlink: `~/.local/bin/start-icewm`
- Create: `/home/jim/projects/dotfiles/.xinitrc-icewm` (clone of `.xinitrc-desktop`)
- Symlink: `~/.xinitrc-icewm`

- [ ] **Step 1: Create `start-icewm`** by copying `start-pekwm` and changing only the deltas

```bash
cp /home/jim/projects/dotfiles/.local/bin/start-pekwm /home/jim/projects/dotfiles/.local/bin/start-icewm
```
Edits in the copy: header comment → IceWM; `XDG_CURRENT_DESKTOP=icewm`, `XDG_SESSION_DESKTOP=icewm` (keep `XDG_SESSION_TYPE=x11`); keep the dbus/keyring/ssh-agent/reaper/VA-API/flameshot-x11 blocks **verbatim** (flameshot path is identical — X11 legacy); final line → `exec startx ~/.xinitrc-icewm`.

- [ ] **Step 2: Create `.xinitrc-icewm`** by copying `.xinitrc-desktop` and changing the WM exec

```bash
cp /home/jim/projects/dotfiles/.xinitrc-desktop /home/jim/projects/dotfiles/.xinitrc-icewm
```
Edits: keep `dbus-update-activation-environment …` and the autostart block; **remove the `feh` wallpaper line** (IceWM owns it via `DesktopBackgroundImage`); change the final `exec pekwm` → `exec icewm-session`.

- [ ] **Step 3: Symlink + exec bits**

```bash
chmod +x /home/jim/projects/dotfiles/.local/bin/start-icewm /home/jim/projects/dotfiles/.xinitrc-icewm
ln -sf /home/jim/projects/dotfiles/.local/bin/start-icewm /home/jim/.local/bin/start-icewm
ln -sf /home/jim/projects/dotfiles/.xinitrc-icewm /home/jim/.xinitrc-icewm
```

- [ ] **Step 4: Static checks** (don't launch — that drops the live session)

```bash
bash -n /home/jim/.local/bin/start-icewm && echo "start-icewm: syntax OK"
bash -n /home/jim/.xinitrc-icewm && echo ".xinitrc-icewm: syntax OK"
grep -nE 'icewm|pekwm|feh|XDG_CURRENT_DESKTOP|exec ' /home/jim/.local/bin/start-icewm /home/jim/.xinitrc-icewm
```
Expected: no `pekwm`/`feh` leftovers; `exec startx ~/.xinitrc-icewm` and `exec icewm-session` present.

- [ ] **Step 5: Commit**

```bash
cd /home/jim/projects/dotfiles && git add .local/bin/start-icewm .xinitrc-icewm && git commit -m "icewm: session launcher (start-icewm) + .xinitrc-icewm"
```

---

### Task 7: Live TTY validation + docs + push

**Files:** `docs/2026-06-16-icewm-x11-setup-plan.md` (this doc), `CLAUDE.md` (pointer).

- [ ] **Step 1: Live boot** — user logs out of the current session, at the TTY runs `start-icewm`. Walk the spec success criteria 1–7 by hand (focus, maximize/restore, goto/send workspace + focus survival, rofi, titlebarless + cyan border, taskbar, keyring/wallpaper/flameshot). Note anything off under "Task 7 — findings".

- [ ] **Step 2: Iterate** any tweaks the live session surfaces (the user flagged "likely tweaks once we can test it"); re-commit affected dotfiles.

- [ ] **Step 3: Update `CLAUDE.md`** — add IceWM to the migration/experiment doc list and a one-line architecture note alongside the PekWM entry; commit.

- [ ] **Step 4: Finalize execution log** in this doc (gotchas, decisions, what diverged from the spec), commit, and push both repos **when the user asks**.

**Task 7 — findings / live-tweak backlog (Xephyr pass, 2026-06-16):**

Verified in nested Xephyr; full *keyboard* testing is blocked by the outer PekWM's
`Super` grabs, so the OPEN items below finish in a real `start-icewm` boot.

- ✅ click-to-focus; titlebarless (global `.dTitleBar: 0`, 4px border = cyan focus
  cue); non-toggle maximize/restore via `icesh -f maximize`/`restore` honoring the
  strut; send-to-workspace `icesh -f setWorkspace` (0-indexed) with **focus
  surviving** (no helper needed); native half-tiling (`KeyWinTile*`); rofi launch;
  close via `icesh -f close` (the `KeyWinClose="Super+q"` preference did NOT fire —
  keys-file + icesh does).
- ✅ Bar: moved to **TOP**, `Look="flat"`, near-black palette, **no boxes**
  (text-colour state: cyan active workspace / white active window), window icons
  off, CPU/net graph monitors off.
- ✅ Quick-launch toolbar emptied (`~/.icewm/toolbar`) — kills the default xterm +
  "Web browser" buttons.
- ✅ `start-icewm` + `.xinitrc-icewm` (clones of the PekWM siblings): keyring
  bootstrap + `dbus-update-activation-environment` carried over so the unlock
  prompt draws; native taskbar (no Polybar), IceWM owns the wallpaper (no feh).
- ✅ RESOLVED: the bare-**Super tap** opened the start menu — trigger was
  `Win95Keys=1` (IceWM's Win95 "tap Win → menu"). `Win95Keys=0` kills it without
  touching explicit `Super+<key>` binds. (It was NOT a desktop/bar menu —
  `DesktopMenuButton=0`/`DesktopWinListButton=0`/`TaskBarShowStartMenu=0` were red
  herrings; the empty `~/.icewm/toolbar` did remove the xterm/web quick-launchers.)
- ✅ RESOLVED: bar **system stats** — CPU/RAM/Net monitors on (IceWM's are little
  time-series graphs, not Polybar-style text); temp omitted (ample cooling, no
  native widget).
- ✅ RESOLVED: **Super+drag** — `MouseWinMove="Super+Pointer_Button1"` /
  `MouseWinSize="Super+Pointer_Button3"` (replaces default Alt+drag, frees Alt+click
  for apps). And direct **Alt+Tab** — `KeySysWinNext` (NOT QuickSwitch, which
  `QuickSwitch=0` disables *entirely*) + `RaiseOnFocus=1` raises each window so you
  see it; no popup list.

**Control CLI:** `icesh` (EWMH-aware, ships with IceWM) — drives the keybinds and
was the live-debugging tool for everything above. `icewmhint` for per-window hints.

### Round-2 — live-session results, gotchas, verdict (2026-06-16)

Tuned entirely *inside* a real `start-icewm` session via `icesh` (PekWM's `Super`
grabs blocked keyboard testing in Xephyr). Key gotchas:

- **`icesh restart` applies preference changes in place** — the WM re-execs, all
  client windows survive (re-parented), and config is re-read. This is the live-
  tweak loop; no logout needed. (Mouse/`Win95Keys`/`Look`/border changes all need
  a restart, not just `icesh winoptions`/`keys`.)
- **The bar's 3D look AND the window-frame bevel both came from the default
  `pixmap` theme**, which silently overrode preference `Look="flat"` for frames.
  A minimal custom theme (`themes/godlike/default.theme`, `Look=flat`) displaced
  it — that's what flattened the bar *and* enabled a thin border.
- **IceWM window borders are color-computed with a Win95 raised bevel on every
  `Look`** — top/left = highlight (`ColorActiveBorder`), bottom/right = shadow.
  There is **no flat/uniform-border option and no image-based border** (pixmap
  themes only image titlebar buttons, not the frame). At `BorderSizeX/Y=1` only
  the highlight shows (top-left "⌐"); at `2` all sides show but stay beveled.
  Settled on **2px** cyan(focus)/slate(unfocus) — the balanced ceiling.
- **`QuickSwitch=0` disables Alt+Tab outright** (the popup *is* the switch);
  direct cycling is a different action, `KeySysWinNext`.
- **Bare `Super` tap → menu** is `Win95Keys=1` (default), not a desktop/bar menu.

**Verdict (user, daily use):** IceWM is **noticeably more responsive and more
stable** than the PekWM trial — several PekWM "oddities" that read as bugs (the
focus-fallback-after-SendToWorkspace miss, the dead `Titlebar`/`KeyWinClose`
autoprops, `~`-not-expanding in `Exec`) simply don't occur here; the two-decade
maturity shows. **IceWM adopted as the active X11 daily driver** in the toggle
rotation (`start-icewm` / `start-pekwm` / `start-hyprland`). PekWM and Hyprland
remain installed and toggleable; nothing was removed.

---

## Self-review (against the spec)

- Success criteria 1–7 → Tasks 2/3 (config) + 4/7 (verify). ✓
- Native taskbar (§2) → Task 2 Step 2. ✓
- Keymap parity (§3) → Tasks 2 (KeyWin*/KeySys*) + 3 (keys). ✓
- Look/behavior (§4): titlebarless → Task 3; cyan border + click-to-focus+raise + wallpaper + QuickSwitch → Task 2. ✓
- Focus-fallback bug (§5) → Task 4 Step 3 verifies; helper port noted if it recurs. ✓
- Half-snapping (§6) → Task 5 (native-or-helper, branched on Task 1 recon). ✓
- Super+drag gap → deferred (Alt+drag default is the fallback; revisit live in Task 7 if missed). Not a blocker.
- Session integration → Task 6. Docs → Tasks 1/4/7.
