# i3-screen-manager

Bash scripts for managing external displays, mouse settings, lid/clamshell behavior,
keyboard layout, and Hyprland session bring-up. Project originated as an i3/X11
toolkit; both machines migrated to Hyprland/Wayland in 2026-Q2. Script names
retain the `i3-` prefix deliberately — they're invoked everywhere by muscle
memory and from rofi menus, so changing the names would cost more than the
labels are worth.

## Environment

- **Distro:** Artix Linux (OpenRC, both machines). Both were originally Arch.
- **Compositor:** Hyprland on Wayland. Originally i3 on X11.
- **Package manager:** `yay` (AUR wrapper around pacman). Both Arch and Artix packages work.
- **Privileges:** `sudo` is available from the user account.
- **Machines:** `nomad-artix` (ThinkPad X1 Extreme Gen 5 laptop), `godlike-artix` (desktop).

## Migration history

The big migration runbooks live under `docs/`. Read them when working on
anything compositor- or tooling-adjacent:

- `docs/hyprland-migration.md` — initial i3/X11 → Hyprland/Wayland migration
  (laptop, on Artix). Phase-by-phase. Captures startup, env, NVIDIA hybrid,
  Waybar replacement of Polybar, the i3-screen-manager rewrite from xrandr to
  hyprctl/wlr-randr.
- `docs/desktop-artix-hyprland-migration.md` — desktop equivalent (pure AMD,
  no NVIDIA, no laptop-specific concerns).
- `docs/hyprland-lua-migration.md` — Hyprland 0.55+ hyprlang → Lua config
  migration. Both machines on Lua now. Includes Hyprland-side gotchas and the
  open waybar #5008 regression.
- `docs/artix-laptop-setup.md` — first-boot install/setup notes for the laptop.
- `docs/hyprland-first-boot.md` — Hyprland-specific first-boot checklist.
- `docs/claude-code-aur-to-native-migration.md` — switching Claude Code itself
  off the AUR `claude-code` package onto Anthropic's native installer
  (auto-updates, no more AUR exposure). **Done on both machines** —
  `godlike-artix` 2026-06-15, `nomad-artix` 2026-06-18. Key gotcha: the native
  install must be finalized from a clean terminal, *not* from inside a Claude
  Code session. The laptop run uncovered one positive finding: recent Claude
  versions (≥ 2.1.181) self-correct the `.desktop` deep-link handler during
  `claude install`, so the manual step 4 is now a no-op verification.
- `docs/codex-aur-to-native-migration.md` — the same AUR→native swap for the
  Codex CLI: off `openai-codex-bin` onto OpenAI's official installer
  (`curl -fsSL https://chatgpt.com/codex/install.sh | sh`, self-updating
  standalone layout under `~/.codex/packages/standalone/`). **Done on both
  machines** — `godlike-artix` 2026-06-19, `nomad-artix` 2026-06-27. Unlike
  the Claude Code swap, this one needs **no** clean-terminal hand-off — the Codex
  installer has no nested-session detection, so it can be run from inside a Claude
  Code session.
- `docs/brave-to-brave-origin-migration.md` — switching the daily browser off
  `brave-bin` (CLI `brave`) onto the paid, stripped **Brave Origin**
  (`brave-origin-bin`, CLI `brave-origin`). Done on `godlike-artix` 2026-06-23;
  **`nomad-artix` (laptop) still pending** — runbook is written for it. Key
  gotcha: Brave Origin's main window WM_CLASS is `brave-origin`/`Brave-origin`
  (was `brave-browser`/`Brave-browser`), while its inner-Chromium helper windows
  still report `brave`/`Brave` — so the WM window-rules and IceWM `winoptions`
  focus-fix had to be repointed. Most config is inherited via `git pull`
  (dotfiles `974c91f`); the profile-slot surgery, default-browser/mimeapps, and
  native-messaging-host copy (marksnip) are machine-local. WebMCP confirmed
  present in Origin 149.
- `docs/kitty-to-ghostty-terminal-swap.md` — making **Ghostty** the terminal on
  `Super+Return` fleet-wide, plus aligning its palette to Kitty's. Desktop DONE
  2026-07-19; **laptop config committed but NOT deployed** (Ghostty is
  copy-deployed, so `git pull` alone does nothing — see the runbook §4). Kitty
  stays installed; the swap is a one-line revert. Two gotchas worth knowing
  before touching either terminal: Ghostty's `class` must be a valid GTK
  application ID (**must contain a dot**) or it's silently ignored and the
  floating terminal stops matching its float rule — so Hyprland uses `--class=`
  while IceWM must use `--x11-instance-name=` (dots are `winoptions`' own field
  separator); and Ghostty **drops malformed config lines silently**, including
  any line with a *trailing* comment, so `ghostty +show-config` is the only
  ground truth.

**IceWM is now the only active X11 WM on both machines.** PekWM was tried on
the desktop and **declared over** (verdict: PekWM oddities read as bugs; IceWM
noticeably more responsive and stable). On **2026-06-18** PekWM was
**uninstalled and all its config artifacts removed** — the `pekwm` package,
`start-pekwm`, `pekwm-send-to-ws`, `.pekwm-desktop/`,
`polybar/config-pekwm.ini`, and `.xinitrc-desktop` are all gone. It was never
replicated to the laptop. The full WM rotation:

- **`godlike-artix` (desktop):** Hyprland (Wayland) · **i3 (X11, provisional complete success 2026-07-20)** · IceWM (X11) · ~~FVWM3~~ (X11, **rejected 2026-07-20 — provisional failure**)
- **`nomad-artix` (laptop):** Hyprland (Wayland) · IceWM (X11, live) · **i3 (X11, scaffolded 2026-07-21 — pending first TTY-boot validation)**

**FVWM3 was tried and rejected on 2026-07-20**, the same day it was built. It
was chosen as the only stacking X11 WM with genuinely independent per-monitor
workspaces, and that part *worked* — the trial died on **window placement
quirks** arriving faster than they could be fixed (Discord restoring itself to a
remembered monitor; maximise-then-unmaximise teleporting a window back to the
previous monitor; `xdg-open` silently stealing focus so the next window command
hit the wrong window). Same failure mode that ended PekWM: not a missing
feature, an accumulation of behaviours you have to hold in your head.

Marked **provisional** because the diagnosis is incomplete — at least one of the
three looks like a bug in the config rather than in fvwm. Config is left in
place and is entirely additive; nothing needs undoing. See
`docs/2026-07-20-fvwm3-x11-setup.md` §8.

**Direction after this: back to i3** — accepting a tiling paradigm to get the
per-monitor workspace model that the stacking world could not deliver reliably.

**i3 was rebuilt and adopted the same day, 2026-07-20 — "provisional complete
success."** Verdict: *"most things just work."* The tiling paradigm that was
feared turned out to be the cure, not the compromise — deterministic window
placement is exactly what the stacking WMs lacked. Standout: an auto-building
comms stack on workspace 10 (Messages+WhatsApp / Discord+Slack+Keybase) via i3's
`append_layout` + swallow criteria, reachable by `Super+F1..F5`, with a "Launch
Chats" from-scratch rebuild. See `docs/2026-07-20-i3-x11-setup.md`. Only
"provisional" pending daily-use time; nothing is broken.

Docs:

- `docs/2026-06-15-x11-wm-research.md` — the survey of living X11 WMs that led
  to trying PekWM, then settling on IceWM.
- `docs/2026-06-15-pekwm-x11-setup.md` (+ `…-plan.md`) — PekWM-on-XLibre on
  `godlike-artix`. **Trial concluded; PekWM uninstalled and all config removed
  2026-06-18.** Docs retained as the historical record only — the config they
  reference (`.pekwm-desktop/`, `polybar/config-pekwm.ini`, `.xinitrc-desktop`,
  `.local/bin/start-pekwm`) no longer exists in the repo.
- `docs/2026-06-16-icewm-x11-setup.md` (+ `…-plan.md`) — **IceWM 4.0-on-XLibre
  on the desktop** (`start-icewm`). Native taskbar (no Polybar), `icesh` control
  CLI. Border quirk: IceWM color-computes a Win95 bevel on every `Look`, so
  a uniform border isn't achievable — settled on 2px beveled cyan/slate.
  Config: `dotfiles/.icewm/`, `dotfiles/.xinitrc-icewm`,
  `dotfiles/.local/bin/start-icewm`.
- `docs/2026-06-17-icewm-laptop-setup.md` — **IceWM on the laptop**
  (`start-icewm-laptop`). Mirrors the desktop setup with hardware deltas:
  NVIDIA PRIME via `xorg.conf.d/10-nvidia-prime.conf` (Intel modesetting
  primary, NVIDIA secondary, externals bound via
  `xrandr --setprovideroutputsource`), touchpad config, brightness keys,
  battery widget. Config: `dotfiles/.icewm-laptop/`,
  `dotfiles/.xinitrc-icewm-laptop`, `dotfiles/.local/bin/start-icewm-laptop`.
  IceWM picks up the laptop config via `ICEWM_PRIVCFG` (no `~/.icewm`
  symlink needed).
- `docs/2026-07-20-i3-x11-setup.md` (+ `…-i3-desktop-setup-plan.md` design,
  `…-i3-implementation-steps.md` build) — **i3 4.25.1 on the desktop: rebuilt and
  adopted 2026-07-20, "provisional complete success."** The return to i3 after
  FVWM3 was rejected; tiling turned out to be the cure ("most things just work"),
  not the compromise it was feared to be. Read the outcome doc for: the measured
  `exec` vs `exec_always` truth (`exec_always` re-runs on *restart*, NOT reload —
  the common belief is wrong); the Electron window-identity gotchas (Discord and
  Slack present a lowercase `res_class` main window with capital-cased tray
  helpers, so match case-insensitively; Brave PWAs share class `Brave-origin` and
  must be matched by `instance`); the workspace-10 comms stack built from
  `append_layout` + swallow criteria (`i3-chat-layout`, `i3-chat-rebuild` / "Launch
  Chats", `Super+F1..F5`); and that `~/.config` copy-deployment drift was found
  THREE times in one build (i3, rofi, polybar) — symlinking is the structural fix.
  Unlike FVWM3, i3 ships `i3 -C` to validate a config without launching it.
- `docs/2026-07-21-i3-laptop-setup.md` — **i3 on the laptop, scaffolded
  2026-07-21** (pending first TTY-boot validation). Sibling of the desktop's
  i3 setup with the SKIP list applied for a dynamic-external-monitor life:
  no `workspace N output` fixed pins, single-bar polybar with a battery
  module (drops `cmos-battery` which is desktop-it87-only), brightness binds
  added, no audio-stack launches in xinitrc (OpenRC user services own that
  on the laptop), no `xdtpaste` bind (desktop-local script), and no
  workspace-10 chat-wall auto-build (deferred while the user cooks on an
  alternate design). Reuses the IceWM-laptop infrastructure verbatim:
  `/etc/X11/xorg.conf.d/{10-nvidia-prime,40-touchpad}.conf`, HiDPI recipe,
  `i3-screen-manager` X11 backend, `flameshot-laptop-{wayland,x11}.ini`
  symlinks. Also lands the Ghostty user-level `.desktop` shadow that
  prevents `--gtk-single-instance=true` re-entering via D-Bus activation.
  Config: `dotfiles/.config/i3/config-laptop`,
  `dotfiles/.local/bin/start-i3-laptop`, `dotfiles/.xinitrc-i3-laptop`,
  `dotfiles/.config/polybar/config-i3-laptop.ini`.
- `docs/2026-07-20-fvwm3-x11-setup.md` (+ `…-desktop-setup-plan.md` design,
  `…-fvwm3-implementation-steps.md` build) — **FVWM3 on the desktop: built and
  REJECTED the same day, 2026-07-20 (provisional failure — see §8).** Chosen as
  the only stacking X11 WM with independent per-monitor workspaces
  (`DesktopConfiguration per-monitor`), which did work; it died on window
  placement quirks. Docs retained because the diagnosis is reusable and the
  config is still on disk. Read the outcome
  doc before touching it: the single biggest trap is that **fvwm3's user
  directory is `~/.fvwm`, not `~/.fvwm3`**, and the `Read` failures that causes
  are *silent*, so the first boot came up as stock 1992 FVWM with no error
  anywhere. Also records: `CurrentScreen` is NOT monitor-scoped (it is a synonym
  for `CurrentPageAnyDesk`; `Screen <name>` is the real one); `StartFunction`
  runs on every restart so daemons belong in `InitFunction`; polybar's
  EWMH-correct screen-absolute strut is applied by fvwm as monitor-relative,
  which broke maximise on the y-offset monitor; and **Xephyr cannot validate any
  of this** — it exposes a single RandR output, so per-monitor behaviour is
  untestable in a nested server.
- `docs/2026-07-20-desktop-dual-monitor-portrait.md` — **desktop went dual-head
  2026-07-19**: ASUS PA248QV (1920x1200) pivoted to **portrait** on the right of
  the PB328 (2560x1440), both native, vertical centers aligned (the *shorter*
  panel carries the y-offset — X11 has no negative screen coordinates). Live and
  verified under IceWM/X11; the Hyprland `transform` **direction** is written but
  untested (if the panel comes up upside-down on the next Wayland boot, it's `3`,
  not `1`). Also covers the `HDMI-1`(X11)/`HDMI-A-1`(DRM/Wayland) name split, a
  defused Hyprland catch-all that used to force 2560x1440 onto *every* output,
  and — separately from the layout — the research result that **IceWM cannot give
  a monitor its own workspaces or its own bar**: `_NET_CURRENT_DESKTOP` is a
  single global scalar, so it's architectural, and swapping in polybar fixes the
  bar but provably cannot fix the workspaces.
- `docs/2026-07-05-xlibre-versioning-artix-packaging.md` — **XLibre version
  scheme + Artix packaging.** Why `world` ships `xlibre-xserver 25.0.0.x` while
  upstream "stable" is `25.1.x`: they're *parallel branches*, and Artix stages the
  whole `25.1.x` line in `world-gremlins` pending a normal soak+promote (not lag,
  not a broken pin). Includes the verified ABI reality (both shipped pkgs provide
  `VIDEODRV 28.0`), the security gap (`world`'s `25.0.0.23` predates the 2026-06-05
  hardening — Artix skipped `25.0.0.24`), and a Watch List for the
  `world-gremlins → world` promotion. Ties into the `25.0.0.21` vblank regression
  under Common Issues → "X11 historical".
- `docs/2026-07-29-starling-desktop-investigation.md` — **code-level teardown of
  Starling** (`starling.build`, the AI-written desktop) + a broader X11/Wayland
  "structural vs folklore" audit. Not a WM-setup doc — a reference for revisiting
  Starling and for the architecture arguments it surfaced. Headlines: Starling's
  X11 is a **bespoke ~5.2K-line in-process C++ X server, NOT Xwayland** (compiled
  into the same binary as its Wayland compositor; both feed Flutter's texture
  registry; real Xwayland kept as the escape hatch for WeChat) — **reconstructed
  from AI training exposure, not lifted** (zero X.Org tokens; NOTICE attributes it
  to no-one; grown gap-by-gap per client). It runs **Flutter's *macOS* embedder on
  Linux** across five languages, so Swift is inherited toll, not merit. Also a
  **verified XLibre finding** (slots beside the XLibre doc above): XLibre ships
  **TearFree by default + optional atomic modesetting + VariableRefresh**
  (`README` + `modesetting.man`), and X has had every-frame-perfect presentation
  since ~2013 via **Present + DRI3** — so "X structurally can't do tear-free/atomic
  presentation" is folklore. The one real architectural Wayland win that survives
  the audit is **client isolation** (X's ambient authority; portals re-grant it).
  Closes with the **"where you put the seam" thesis** (draw-ops vs buffers vs
  semantics) and why remote-dev tooling makes the X-vs-Wayland fight orthogonal.
- `docs/2026-07-29-rofi-emoji-picker-fix.md` — **`Super+Control+space` emoji picker
  root-cause + fix.** It showed *"Do not launch rofi from inside rofi."* instead of
  an emoji menu: the `emoji` "modi" was a launcher script written for the (AUR-only,
  off-limits) **rofi-emoji plugin**, and rofi 2.0 **auto-discovers
  `~/.config/rofi/scripts/<name>` as a script modi**, so `-modi emoji` ran that
  script, which re-ran rofi → the `ROFI_OUTSIDE` nested-launch guard fired. Diagnosed
  by `strace -f -e trace=execve` on the exec chain. Replaced with a self-contained
  `rofi -dmenu` picker (`scripts/emoji` → `xclip`) over an offline-generated
  1419-entry `emoji.txt` (`gen-emoji.py`, from texlive's UCD `emoji-data.txt`) with a
  searchable list theme. **The laptop needs the redeploy in §5** — `~/.config/rofi`
  is copy-deployed on both machines, so `git pull` alone won't move the rofi files.
- `docs/2026-08-03-dbus-reload-hook-openrc-desync.md` — **pacman `Invalid
  operation 'reload'` post-transaction error** = an Artix packaging desync, not a
  machine problem: `dbus-openrc 20260324-1`'s `dbus-reload.hook` calls
  `openrc-hook reload dbus`, but `openrc 0.63.3-2`'s dispatcher only implements
  `dbus_reload` (no generic `reload` verb), so it exits 1. Harmless
  (PostTransaction; only skips a live dbus policy reload). Fixed with a
  **TEMPORARY** `/etc/pacman.d/hooks/dbus-reload.hook` override that calls
  `dbus_reload`. **Laptop (`nomad-artix`) needs the same override** (§5).
  Diagnosis + fix confirmed on the Artix forum, where an upstream `dbus-openrc`
  patch is already posted + maintainer-liked (§7) — so no bug to file (Gitea
  issues closed), just watch for the rebuild. Pinned to `dbus-openrc
  20260324-1`; **re-evaluate/remove on any `dbus-openrc` bump, or by 2026-09-03**
  — the doc's §6 Watch List has the check-and-remove steps.
- `docs/2026-08-10-aur-supply-chain-assessment.md` — **decision-grade
  assessment of AUR supply-chain risk (Feb–Aug 2026)**, the security-research
  companion to the `aur-malware-check` script. Primary-source-first (official
  Arch news, `aur-general`/`aur-requests`, the `aurweb` GitLab MRs/issues) plus
  trusted vendors (Truesec, Sonatype, BleepingComputer, Phoronix). Timeline of
  the 2026 waves (May `@onionmail` crypto-wallet precursor → the June
  `atomic-lockfile`/`js-digest` "Atomic Arch" campaign, ~400–1500 pkgs, Rust
  infostealer + optional root-only eBPF rootkit → the late-July `openconnect-sso`
  relapse), the **shipped-vs-proposed mitigation ledger** (aurweb `!914`
  PM-reviewed adoption merged 2026-07-31; adoption+pushes frozen 2026-07-30/08-01;
  2FA `#514` still open since 2024), and the verdict: **keep Arch, treat the AUR
  as hostile-by-default — build in a clean chroot, read every `PKGBUILD` diff,
  distrust freshly-adopted orphans.** Built via a multi-lane research pass
  (Codex hit the GitLab API for the ledger; Perplexity + `marksnip` for primary
  timeline/quotes); the doc records that the `agy` (Google-grounded) lane
  fabricated specifics, so nothing from it is load-bearing. Published Artifact:
  <https://claude.ai/code/artifact/1e67b264-50b4-4755-8bd2-2830ac2f614e>.
- `docs/install-paths-cheatsheet.md` — **decision tree for "AUR is sus, where
  should I install X from instead?"** Six-rung table (Artix repos → vendor
  native installer → pipx → docker → local PKGBUILD fork → AUR-with-audit)
  with the trust story, update model, uninstall model, and best-fit case for
  each; the trap classes that look like a rung but aren't (`sudo pip install`,
  `sudo npm install -g`, random Docker Hub images); worked examples that
  shaped the doc (Claude Code + Codex + Brave Origin at rung 2, Odin at
  rung 5, hypothetical Semgrep re-install at rung 3). Written after the
  semgrep-bin uninstall pass on `nomad-artix` 2026-08-11 which surfaced that
  the AUR lockdown wasn't just about Semgrep — every new install now needs a
  decision, and the decision was worth capturing.

Hyprland and IceWM are both installed and toggleable from a TTY on each
machine. PekWM was the lone exception to the "additive and reversible" rule —
it was a trial and has now been fully removed from the desktop (2026-06-18); it
never reached the laptop.

## Architecture

Scripts, no build step. All committed in this repo and symlinked from
`~/.local/bin/`:

**Display & input management (compositor-aware — Wayland AND X11):**
- `i3-screen-manager` — CLI for display layout (extend/clamshell/mirror/disconnect/scale/status). Dispatches internally on `$XDG_SESSION_TYPE`: Wayland uses `hyprctl dispatch 'hl.monitor({...})'` (Lua-mode-safe); X11 uses `xrandr`. Single source of truth; same UX both ways. (Until 2026-06-17 this was Hyprland-only and silently broken under Hyprland 0.55+ Lua mode.)
- `i3-screen-rofi` — Rofi menu frontend that calls `i3-screen-manager` (compositor-agnostic)
- `i3-keyboard-rofi` — Rofi toggle for laptop (Caps→Ctrl) vs external keyboard. Dispatches on `$XDG_SESSION_TYPE`: Wayland → `hyprctl keyword input:kb_options`; X11 → `setxkbmap -option`. Same UX both ways.
- `i3-mouse-setup` — Login-time script that applies saved mouse DPI via `solaar`. Compositor-agnostic (HID-level).
- `i3-mouse-rofi` — Rofi menu for mouse DPI adjustment (saves choice for persistence). Compositor-agnostic.
- `i3-cmos-battery` — CMOS battery voltage monitor (CLI + waybar output, formerly polybar)

**Hyprland session bring-up & maintenance:**
- `start-hyprland` — Hyprland session launcher: env, gnome-keyring, ssh-agent at predictable socket, NVIDIA hybrid `AQ_DRM_DEVICES`, `exec /usr/bin/start-hyprland`
- `laptop-monitor.sh` — Hyprland lid-switch handler; checks the clamshell inhibitor PID before re-enabling eDP-1
- `laptop-monitor-x11.sh` — X11/IceWM sibling of `laptop-monitor.sh`. **Not auto-wired** (no acpid hook by default); see `docs/2026-06-17-icewm-laptop-setup.md` for the manual-trigger pattern and the acpid wiring recipe.
- `hyprland-clamshell-restore` — Re-applies clamshell eDP-1 disable after every Hyprland config reload (wired via `hl.on("config.reloaded")` under Lua, or `exec=` under hyprlang)
- `screenshot.sh` — hyprshot + satty screenshot workflow (alternative path; main flow is flameshot via `Print`)
- `flameshot.sh` — flameshot wrapper with `QT_SCREEN_SCALE_FACTORS="1;1"` for correct DPI
- `volumecontrol.sh` — pavucontrol wrapper that forces Intel Vulkan ICD to avoid NVIDIA VA-API conflicts

**System maintenance & security:**
- `aur-malware-check` — Read-only audit of installed packages against the June 2026 "Atomic" AUR supply-chain denylist. Name intersection by default; `--deep` adds a pacman-scriptlet + filesystem IOC scan, `--near` flags confusable look-alikes (you have the safe name, a malicious twin exists), `--all` widens to every installed package, `--list`/`--url` override the source. Downloads + caches the denylist (offline fallback); exit `0`/`1`/`2` = clean/exposed/error, so it drops into a login hook or `&&` chain.

## Key Design Decisions

- **Internal display is hardcoded as `eDP-1`** — standard for modern Intel laptop panels.
- **External display is auto-detected** — `wlr-randr` (not `hyprctl monitors -j`) because hyprctl drops disabled outputs while wlr-randr sees all physically connected ones.
- **Lid state path is discovered dynamically** — ACPI names vary (`LID`, `LID0`, etc.) across boots.
- **Safe defaults** — if lid state can't be detected, assume closed (refuse disconnect rather than risk black screen).
- **Clamshell uses `elogind-inhibit`** — `elogind` is Artix's logind. Holds a `handle-lid-switch` block lock via a background `sleep infinity` process, PID tracked in `/tmp/i3-screen-manager-inhibit.pid`. (Pre-Artix this used `systemd-inhibit` with identical flags.)
- **`hyprctl keyword monitor X,disable` is unreliable** — known Hyprland issue where disable can leave a phantom monitor. Always follow with `wlr-randr --output X --off` to cut the physical DRM output.
- **`moveworkspacetomonitor` silently no-ops on disabled monitors** — when entering clamshell, enable the external first (at `auto` position) before moving workspaces, then disable eDP-1.
- **Disconnect enables internal BEFORE disabling external** — no window where zero displays are active. Internal goes up at `auto` first to avoid overlap warnings, then external goes down, then internal repositions to `0x0`.
- **Scale instead of `Xft.dpi`** — Wayland uses output scaling. `i3-screen-manager scale` calls `hyprctl keyword monitor "$target,preferred,auto,$scale"` with a rofi picker of 0.75/1.00/1.25/1.50/1.75/2.00. The old `Xft.dpi` knob is gone — there is no X resource database.
- **Mouse DPI via solaar** — `i3-mouse-setup` auto-detects Logitech mice at login and applies saved DPI from `~/.config/i3-mouse-manager/dpi`. `i3-mouse-rofi` provides on-the-fly adjustment that persists across reboots.
- **CMOS battery monitoring** — `i3-cmos-battery` reads Vbat from the it87 Super I/O chip. Requires `it87` kernel module (auto-loaded via `/etc/modules-load.d/it87.conf`). Refreshes every 6 hours. Exits silently on machines without the sensor (laptops).
- **Clamshell survives Hyprland config reload** — the `hyprland-clamshell-restore` script is wired into Hyprland (via `exec=` under hyprlang or `hl.on("config.reloaded")` under Lua) so saving the config file doesn't wake eDP-1 back up.
- **`aur-malware-check` is a standalone tenant** — it has nothing to do with displays. It lives here because this repo is the home for the machine's hand-rolled bash scripts and it follows the same "commit here, symlink from `~/.local/bin/`" convention. It has no dependency on the rest of the toolkit and can be lifted out at any time.

## Testing

No automated tests. Test manually with an external monitor:

1. `i3-screen-manager extend-right` — external should light up to the right of internal.
2. `i3-screen-manager mirror` — both screens same content.
3. `i3-screen-manager clamshell` — internal off, external only. Close lid safely.
4. `i3-screen-manager disconnect` (lid closed) — should refuse with an explanatory message.
5. Open lid, `i3-screen-manager disconnect` — should restore internal display.
6. `i3-screen-manager scale` — rofi picker should appear, selecting a value changes the output scale.
7. `i3-screen-manager scale 1.5 eDP-1` — direct scale set, bypasses the picker.
8. `i3-screen-manager status` — should show internal/external, active monitors with pos/scale, and inhibitor state.

## Common Issues

### Hyprland / Wayland

- **`hyprctl keyword monitor` is dead under Lua mode (Hyprland 0.55+)** — returns "keyword can't work with non-legacy parsers. Use eval." The dual-compositor refactor of `i3-screen-manager` (2026-06-17) replaced it with `hyprctl dispatch 'hl.monitor({...})'`. The dispatch wrapper itself errors ("hl.dispatch: expected a dispatcher") but the `hl.monitor()` side effect runs first — verified during the 75Hz experiment 2026-06-13 and the `i3-screen-manager disconnect` smoke test 2026-06-17. The `hl_apply` helper quiets the wrapper error and accepts the side effect.
- **Black screen on disconnect**: lid was closed and eDP-1 couldn't activate. The lid guard prevents this.
- **External not detected**: `wlr-randr` should see it. NVIDIA outputs follow `*-N-N` naming (e.g. `HDMI-1-0`, `DP-1-0`).
- **A monitor rule silently matches nothing (X11 vs Wayland output names)**: xrandr and the kernel DRM layer name the *same physical port* differently — the desktop's second monitor is `HDMI-1` under xrandr but `HDMI-A-1` to wlroots/Hyprland. Copying a working xrandr layout into a Hyprland config verbatim therefore matches no output and falls through to the catch-all, with no error. `DP-2` is spelled the same in both, which makes the mismatch easy to miss. Ground truth for the Wayland-side name, readable from an X11 session: `for c in /sys/class/drm/card*-*; do [ "$(cat $c/status)" = connected ] && basename $c; done`.
- **Phantom monitor after clamshell**: `hl.monitor disabled=true` is unreliable like the hyprlang `keyword monitor X,disable` it replaced. Always paired with `wlr-randr --output X --off` in the scripts. If it ever recurs, rerun `i3-screen-manager clamshell`.
- **Waybar workspace clicks do nothing under Lua mode**: known regression — waybar #5008. Hyprland 0.55+ tries to evaluate the IPC dispatch string as Lua, and waybar's old-style `dispatch workspace N` is not valid Lua. Workaround: `Super+N` keyboard shortcut (works), or mouse-wheel on the bar (works via configured `on-scroll-*`). See `docs/hyprland-lua-migration.md` § "Waybar workspace click regression".
- **GTK file dialog hangs 25 seconds**: `gvfsd-trash` D-Bus backend times out. Root fix: remove `gvfs` entirely (`sudo pacman -R gvfs evince`) and use `xreader` instead of evince. Keep `export GIO_USE_VFS=local` in `start-hyprland` as a safety net. Diagnose with `time gio info trash:///` (slow) vs `time GIO_USE_VFS=local gio info trash:///` (instant).
- **BACKLOG — `rofi-rbw` auto-type types nonsense under Wayland**: bound to `Super+Shift+b` in every WM. Under X11 it auto-selects the `xdotool` typer and works fine (confirmed 2026-07-20 — do NOT "fix" the X11 path). Under Wayland the only installed typer is `wtype`, which synthesizes keysyms and mangles anything layout-dependent, so credentials come out garbled and you fall back to copy/paste. **Not yet fixed** — deferred until actually running Hyprland. Intended fix, when the time comes: a session-dispatch wrapper (same `$XDG_SESSION_TYPE` branch as `i3-screen-manager` / `i3-keyboard-rofi`) that all the `rofi-rbw` binds call — `--typer xdotool --clipboarder xclip` under X11; under Wayland either install `ydotool`/`dotool` (real scancodes via uinput; `wtype` is the broken one) or default to `--action copy`. rofi-rbw reads `~/.config/rofi-rbw.rc`, but a static rc can't branch on session type, hence the wrapper. Bind sites to repoint: `.config/i3/config-desktop`, `.icewm/keys`, `.icewm-laptop/keys`, and the four `.config/hypr/hyprland-{desktop,laptop}.{lua,conf}`.

### X11 / IceWM (laptop-specific)

- **NVIDIA PRIME provider not yet bound**: external monitors don't appear in `xrandr --query` until `xrandr --setprovideroutputsource modesetting NVIDIA-G0` runs. The xinitrc-icewm-laptop fires it at session start; `i3-screen-manager`'s X11 path fires it again before any external operation (`ensure_nvidia_provider_x11`) as belt-and-suspenders. Sources disagree on the argument order (`provider source` vs `modesetting NVIDIA-*`), so the helper tries four orderings silently.
- **Scale under X11**: no Wayland-style per-output fractional scaling. `i3-screen-manager scale` under X11 applies a server-wide `Xft.dpi` via `xrdb -merge`, which only affects newly-launched apps (existing apps don't redraw). Different model from Hyprland's hot-applied scale.
- **Lid handling is manual under IceWM**: no native lid binding; auto-handling would require `acpid` + a script that crosses the root-to-user boundary. The current plan: enter clamshell explicitly via `i3-screen-rofi → Clamshell`. The `elogind-inhibit` inhibitor works under both compositors and prevents suspend on lid close. See `docs/2026-06-17-icewm-laptop-setup.md` § "Lid handling, deferred".

### Scripts / shell

- **Silent-failure trap on missing runtime deps**: any script running `set -euo pipefail` that pipes to a shelled-out tool will exit zero-visible-output when the tool isn't installed — `set -e` propagates the failed pipe, script dies, no stderr surfaces because the tool was never given a chance to write one. First hit on `nomad-artix` 2026-08-06 when `xclip` was missing from the emoji picker's `printf … | xclip` line: menu "vanished" after selection with no diagnostic. All rofi menu scripts in the fleet now guard their required tools at the top by sourcing `lib/require.sh` (via `~/.local/lib/sh/require.sh` — one-time machine-local symlink) and calling `_require rofi tool1 tool2 …`; missing tools produce a `notify-send -u critical` + a stderr line. Pattern + shared-library design documented in `docs/2026-07-29-rofi-emoji-picker-fix.md` § 8. Apply the same guard to any new shell script that shells out to non-universal tools.

### Hardware / kernel

- **Mouse poll rate config ignored**: on the stock kernel, `usbhid` is built-in (not a module), so `/etc/modprobe.d/` has no effect. Use `usbhid.mousepoll=1` in GRUB's `GRUB_CMDLINE_LINUX_DEFAULT` and `grub-mkconfig -o /boot/grub/grub.cfg`.

### Package management (pacman / Artix)

- **`Invalid operation 'reload'` on the dbus-reload post-transaction hook** (`upc`/`pacman -Syu`): an Artix packaging desync — `dbus-openrc 20260324-1`'s hook calls `openrc-hook reload dbus`, unsupported by `openrc 0.63.3-2`'s dispatcher (which only has `dbus_reload`). **Harmless** (PostTransaction; packages install fine; only a live dbus policy reload is skipped). Not fixable by updating — both packages are newest. **TEMPORARY** fix: `/etc/pacman.d/hooks/dbus-reload.hook` override calling `dbus_reload`. Full write-up + Watch List + laptop note in `docs/2026-08-03-dbus-reload-hook-openrc-desync.md`. **Already reported + patched upstream on the Artix forum** (Gitea issues are closed) — a `dbus-openrc` rebuild is expected, so **re-evaluate/remove the override on any `dbus-openrc` bump, or by 2026-09-03.**

### X11 historical (now mostly moot)

These bit us under i3/X11 and are kept here only because they document past pain
that could resurface if X11 is ever re-introduced (e.g. via an X11 app under
XWayland, or rollback).

- **`xorg.conf.d TargetRefresh` ignored**: the `TargetRefresh` monitor option doesn't work reliably (e.g. amdgpu). Use explicit `xrandr --rate` in `~/.xinitrc` instead.
- **xlibre-xserver 25.0.0.21 vblank regression (2026-02-22)**: 20→21 caused X lockup (`modeset(0): failed to queue next vblank event`). Userspace X server bug, NOT the desktop's PCIe/GPU hardware issue. Downgrade cached at `/var/cache/pacman/pkg/xlibre-xserver-25.0.0.20-1-x86_64.pkg.tar.zst`. No longer relevant under Hyprland but listed in case of X11 fallback.
- **Workspace move errors via `i3-msg`**: `"No output matched"` was usually harmless — workspace was already on the target output. (`i3-msg` no longer used; Hyprland uses `hyprctl dispatch moveworkspacetomonitor`.)
