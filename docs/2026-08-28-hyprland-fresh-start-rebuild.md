# Hyprland fresh-start rebuild (desktop) — design + runbook

**Machine:** `godlike-artix` (desktop). **Date:** 2026-08-28.
**Status:** DESIGN + PREP complete (authored from an X11/i3 session). Phase A
(Quickshell bar spike) and Phase B (core rebuild) are **pending a Hyprland
session** — nothing in the live Hyprland config has been touched yet.

## Why this doc exists

The desktop is returning to Hyprland as a deliberate "fresh start." This work was
scoped and prepped **from within the current i3/X11 session**, but everything that
*runs* (the bar, window rules, the portal, output scaling) can only be validated
under a live Hyprland/Wayland session. This doc is the hand-off: it captures every
decision and every copy-paste-ready snippet so a fresh Claude Code session started
**under Hyprland** can execute Phase A then Phase B without re-deriving anything.

Companion inputs shopped for ideas: `~/projects/omarchy` (`basecamp/omarchy`
v4.0.0.alpha). We lifted *content and ideas*, never Omarchy's machinery.

## Session split (important)

- **Author-anywhere (done under X11):** package installs, writing the PoC QML,
  writing this doc, editing config files. All just files.
- **Validate-in-Hyprland-only:** launching the qs bar, seeing window rules fire,
  testing portal screen-share, checking output scale. These need a live Hyprland
  session, and a Claude session running under X11 cannot observe them.

## Decisions locked (2026-08-28 brainstorm)

| Question | Decision |
|---|---|
| Fresh-start meaning | **Blank slate, port selectively** — new file, carry nothing unless chosen on purpose |
| Config structure | **Stay monolithic** (`hyprland-desktop.lua`, single file) until it demonstrably hurts — NOT Omarchy's modular split |
| Menu system | **Keep Rofi.** Omarchy's menu is a Quickshell QML plugin inside `omarchy-shell`; inseparable from the machinery |
| Bar | **Quickshell bar = spike first** (Phase A), decide vs Waybar before committing |
| Theming | **Per-app to taste, NOT a unified palette.** Look at Omarchy's theme *mechanism* only out of curiosity |
| Window rules | **Lift the useful subset**, translated to `hl.window_rule`, opacity/animation stripped |
| Capture tools | Lift OCR + QR (clean); **from-scratch** minimal screen-recorder |
| Packages | Install the diff'd shortlist, rung-1/2 only |

## Aesthetic constraints (HARD — see memory `feedback_no_frills_aesthetic`)

1. **No animations, at all** — instant updates over eye-candy.
2. **Square** — `rounding = 0` everywhere (already true in current config).
3. **No transparency** — no blur, no opacity rules; windows fully opaque.
4. **Default to no-frills** — when a UI choice arises, pick the plain/static/legible one.

Consequence for the rebuild: when lifting Omarchy config, **strip** their opacity
system (`+default-opacity` tags, `opacity = "0.985 0.96"`, browser translucency)
and their animation curve set. Keep only structural/functional rules.

---

## Phase A — Quickshell bar spike (DO FIRST)

**Question:** Is a hand-written minimal Quickshell bar a good-enough Waybar
replacement — do workspace clicks dispatch under Hyprland 0.55+ **Lua mode** (the
#5008 pain that breaks Waybar's clicks), does the tray work, is authoring QML an
acceptable cost — to justify switching?

**Already done in prep (X11 session):**
- `quickshell 0.3.1-1` installed (rung-1, official `extra`/`galaxy`).
- Throwaway PoC written to **`~/quickshell-bar-poc/shell.qml`** (durable, non-repo).
  API idioms verified against Omarchy's `shell/` (known-good vs quickshell 0.3.1):
  `PanelWindow` + `WlrLayershell.layer` + `ExclusionMode.Auto`,
  `Hyprland.workspaces.values` / `Hyprland.focusedWorkspace`,
  `SystemTray.items` + `modelData.activate()`, `SystemClock`.
- **The #5008 fix baked in:** the workspace click handler shells out via
  `Quickshell.execDetached(["hyprctl","dispatch","hl.dsp.focus({ workspace = \"N\" })"])`
  — the **Lua-expression** dispatch form (Omarchy's proven approach), NOT the legacy
  `"workspace N"` string that Lua mode rejects. This is the exact capability under test.
- **X11 pre-validation:** `qs -p ~/quickshell-bar-poc` under i3 → **"Configuration
  Loaded"**, QML parsed clean, all imports resolved, zero syntax/property/type errors.
  The only warnings are expected Wayland-only gaps: `Cannot connect to hyprland`
  (no Hyprland under i3), `Could not create WlrLayershell` (layer-shell is
  Wayland-only), and `Unable to assign [undefined] to QuickshellScreenInfo` at
  `screen: modelData` (line 36 — a construction-timing artifact under xcb; **watch it**
  on first real launch, trivial guard if it recurs).

**Run it (in Hyprland, alongside Waybar — does NOT touch Waybar):**
```bash
qs -p ~/quickshell-bar-poc     # launch
qs list                        # confirm it's running
qs kill                        # stop it (or Ctrl-C, or: qs kill -p ~/quickshell-bar-poc)
```

**Test checklist:**
1. Bar renders on **both** monitors, top edge, square + fully opaque.
2. **Workspace clicks switch workspace** — THE #5008 proof. If yes, Quickshell does
   what Waybar can't under Lua mode.
3. System tray populates and left-click **activates** an item.
4. The `screen: modelData` warning is gone under real Wayland (check `qs log`).
5. Subjective: is authoring QML an acceptable cost vs Waybar's declarative JSON?

**Decision gate:**
- **Keep** → Phase B targets a Quickshell bar. Promote the PoC into `dotfiles`
  (`~/projects/dotfiles/.config/quickshell/…`), build out the modules you actually
  want (square/static/no-frills), retire Waybar.
- **Drop** → stay on Waybar; `rm -rf ~/quickshell-bar-poc`. Phase B keeps Waybar.

---

## Phase B — core rebuild (AFTER the bar decision)

### B0. Config skeleton

- Fresh monolithic `hyprland-desktop.lua`. Backup of the current one:
  **`~/hypr-config-backup-2026-08-28-desktop/`** (symlinks dereferenced).
- **Port VERBATIM (hard-won, already correct — do NOT reconstruct from scratch):**
  - The **MONITORS block** — dual-head DP-2 (2560x1440 landscape, left) + HDMI-A-1
    (1920x1200 **portrait**, `transform = 1`, right, y-offset 240 to vertically
    center). ⚠️ The portrait transform is **still unverified under Wayland** (set up
    from X11). If the panel comes up **upside-down** on first Wayland boot, the value
    is **`3`, not `1`** (those are the only two options).
  - The **`hl.env` block** — it already sets `XDG_CURRENT_DESKTOP=Hyprland`,
    `XDG_SESSION_TYPE=wayland`, `MOZ_ENABLE_WAYLAND`, `ELECTRON_OZONE_PLATFORM_HINT`,
    `GDK_BACKEND`, `GIO_USE_VFS=local`, etc. The screen-share env fix is **already done**.
    Optional Omarchy-inspired tweak: `QT_QPA_PLATFORM = "wayland;xcb"` (xcb fallback)
    vs current `"wayland"`.
- **Looknfeel — enforce no-frills:** `decoration.rounding = 0` (already), blur off,
  shadow off, and **`animations { enabled = false }`** (verify/flip line ~224 of the
  current file — the current block exists; make sure it's OFF).

### B1. Window rules — translate Omarchy → `hl.window_rule`

Your idiom (confirmed): `hl.window_rule({ name=…, match={ class=…, title=… }, <props> })`.
Omarchy's `o.window(match, props)` maps directly. **Strip every opacity/tag.**
You already ship `suppress-maximize`. Add:

```lua
-- Password managers: exclude from screen captures (security).
hl.window_rule({
    name            = "1password-no-screenshare",
    match           = { class = "^(1[pP]assword)$" },
    no_screen_share = true,
    float           = true,
})
hl.window_rule({
    name            = "bitwarden-no-screenshare",  -- Bitwarden is already in float-apps
    match           = { class = "^(Bitwarden)$" },
    no_screen_share = true,
})

-- Picture-in-Picture: float, pin, corner-anchor, aspect-lock (any app).
hl.window_rule({
    name              = "pip",
    match             = { title = "([Pp]icture.?in.?[Pp]icture)" },
    float             = true,
    pin               = true,
    size              = { 600, 338 },
    keep_aspect_ratio = true,
    border_size       = 0,
    move              = { "(monitor_w-window_w-40)", "(monitor_h*0.04)" },
})

-- Hide the "you are sharing your screen" banner (Chrome/Discord).
hl.window_rule({
    name      = "screenshare-banner-hide",
    match     = { title = ".*is sharing.*" },
    workspace = "special:silent",   -- verify the "silent" (don't-switch) nuance in hl
})

-- XWayland empty-class floating drag fix.
hl.window_rule({
    name     = "xwayland-empty-nofocus",
    match    = { class = "^$", title = "^$", xwayland = true, floating = true },
    no_focus = true,
})

-- Per-app niceties.
hl.window_rule({ name="localsend",  match={ class="(Share|localsend)" }, float=true, center=true, size={1100,700} })
hl.window_rule({ name="jetbrains-nofollowmouse", match={ class="^(jetbrains-.*)$" }, no_follow_mouse=true })
```

(DaVinci Resolve opacity rules from Omarchy are moot — you keep everything opaque anyway.)

### B2. Portal — "screen-share just works"

Core recipe (all **rung-1 / already present**, NO AUR needed):
- `XDG_CURRENT_DESKTOP=Hyprland` env — **already set** (ports over with B0).
- `~/.config/hypr/xdph.conf` — **already** has `allow_token_by_default = 1`
  (auto-approves remembered re-requests).
- The `no_screen_share` rules from B1.

Optional polish (the thumbnail GUI picker) — **AUR, rung-6, skip unless wanted:**
```
# xdph.conf, inside screencopy { }  — OPTIONAL
custom_picker_binary = hyprland-preview-share-picker
```
`hyprland-preview-share-picker` is **AUR-only** (not in official repos). If adopted:
run `aur-malware-check` + read the PKGBUILD (rung-6), install its config from
`~/projects/omarchy/config/hyprland-preview-share-picker/config.yaml` but **replace**
the `stylesheets:` line (it points at Omarchy's theme state dir) with your own CSS
or drop it. Not required for screen-share to work — only prettier first-pick UX.

### B3. Packages (install rungs verified 2026-08-28)

**Capture deps (rung-1, official — install first):**
`hyprpicker` (world), `tesseract` + `tesseract-data-eng` (world), `zbar` (world),
`gpu-screen-recorder` (galaxy).

**Other useful candidates (all rung-1 official):**
`ddcutil` (world — software brightness/input for the dual externals), `hyprsunset`
(world), `satty` (galaxy), `sushi` (world — Nautilus quick-look), `dua-cli` (extra),
`lazygit` (galaxy), `lazydocker` (extra), `moonlight-qt` (extra), `qrencode` (world),
`imv` (galaxy). Already installed: `quickshell`, `grim`, `slurp`, `wl-clipboard`,
`wtype`, `mpv`, `udiskie`, `flameshot`, `waybar`, `rofi`.

**AUR (rung decision — optional, defer):** `localsend` (has AppImage/Flatpak as
rung-alt), `mise-bin` (mise has an official installer = rung-2). `hyprland-preview-share-picker` (B2).

Install rung-1 set with: `sudo pacman -S --needed <pkgs>`.

### B4. Capture scripts (new, in `i3-screen-manager`, symlinked from `~/.local/bin`)

Follow the repo convention (commit here, symlink out) and guard deps via
`lib/require.sh` (the fleet silent-failure pattern).

- **OCR → clipboard** (`omarchy-capture-text`, 26 ln — **clean lift**): swap the one
  Omarchy tentacle `omarchy-notification-send` → `notify-send`. Flow:
  `hyprpicker -r -z` freeze → `slurp` → `grim -g` → `tesseract stdin stdout --oem 1
  --psm 6 -l eng` → `wl-copy`. Deps: hyprpicker, slurp, grim, tesseract(+eng), wl-clipboard.
- **QR decode → clipboard** (`omarchy-capture-qr`, 36 ln — **clean lift**): same
  `notify-send` swap. Flow: freeze → slurp → `grim -g` → `zbarimg -q --raw
  -Sdisable -Sqrcode.enable` → `wl-copy --sensitive` (keeps otpauth secrets out of
  clipboard history — preserve this). Deps: hyprpicker, slurp, grim, zbar, wl-clipboard.
- **Screen record** — do NOT lift Omarchy's 288-line version (it drags in the
  370-line `capture-region` picker + webcam helpers + `omarchy-shell` indicator).
  Write a **~40-line** minimal `gpu-screen-recorder` wrapper: focused-monitor or
  `slurp` region, start/stop toggle (`pgrep`/`pkill -SIGINT ^gpu-screen-recorder`),
  `notify-send`. Deps: gpu-screen-recorder, slurp.
- Bind the three in the new config.

---

## Already done in the X11 prep session (2026-08-28)

- `quickshell 0.3.1-1` installed (rung-1 official).
- PoC `~/quickshell-bar-poc/shell.qml` written + X11-validated (loads clean).
- Config backup `~/hypr-config-backup-2026-08-28-desktop/`.
- Memory saved: `feedback_no_frills_aesthetic`.
- Package install rungs verified (B3).
- This doc.

## Landed live in the first Hyprland session (2026-08-28)

herdr kept the terminal alive across the X11->Hyprland boot, so validation began
in-session sooner than planned (the shell was XWayland with X11 env; bridged to
Hyprland by discovering `HYPRLAND_INSTANCE_SIGNATURE` + `WAYLAND_DISPLAY` from
`$XDG_RUNTIME_DIR`, then a full herdr restart gave clean Wayland env):

- **Portrait transform RESOLVED:** `transform=3` (not 1) is upright — the X11
  `--rotate right` maps to wlroots 270, confirmed on-screen. Baked into
  `hyprland-desktop.lua` (B0 watch-item closed).
- **Per-monitor workspace confinement DONE** (ahead of Phase B, on request):
  DP-2 owns 1-6, HDMI-A-1 owns 7-10, via a `hl.workspace_rule({ monitor = ... })`
  loop (defaults 1 and 7). Mirrors the i3 desktop split. Verified live.
- **Dispatch bug found + fixed:** the legacy `hyprctl dispatch
  moveworkspacetomonitor <ws> <mon>` is DEAD under Lua mode (args parsed as Lua).
  Correct form is **`hl.dsp.workspace.move({ workspace = "N", monitor = "M" })`**
  (found via `/usr/share/hypr/stubs/hl.meta.lua` + live probing — the API error
  message self-documents it). Fixed the 3 silently-failing call sites in
  `i3-screen-manager` (clamshell/disconnect workspace migration was a no-op).

## Open items / watch list

- [x] **Phase A gate:** DONE 2026-08-28 — chose Quickshell (working Lua-mode
  workspace clicks Waybar lacks under #5008); MVP built inline and Waybar
  retired. Full build: `2026-08-28-quickshell-bar-plan.md`.
- [x] **Portrait transform** — RESOLVED: `transform=3` (see above).
- [ ] `screen: modelData` warning — confirm it's gone under real Wayland (A).
- [ ] `workspace = "special:silent"` — confirm the "silent" (don't-switch) hl form (B1).
- [ ] Decide on the AUR trio (share-picker / localsend / mise) — all optional.
