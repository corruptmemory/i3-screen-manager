# i3-screen-manager

Desktop automation for Artix Linux/OpenRC, with Hyprland/Wayland and X11
(i3/IceWM) support. The toolkit manages laptop displays, input settings,
screenshots, session helpers, hardware reporting, and coding-agent usage.
The `i3-` command names are used by existing menus and keybindings.

There is no build step. Scripts live here; desktop configuration and Quickshell
UI live in the companion `~/projects/dotfiles` repository. Scripts are normally
symlinked into `~/.local/bin`. Installing them does not install a desktop config.

## Tools

| Area                       | Commands                                                                                                                             |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| Display CLI and menu       | `i3-screen-manager`, `i3-screen-rofi`                                                                                                |
| Keyboard and mouse         | `i3-keyboard-rofi`, `i3-mouse-setup`, `i3-mouse-rofi`                                                                                |
| Hyprland session and sleep | `start-hyprland`, `hyprctl-live`, `hypr-dpms-all`                                                                                    |
| Lid handling               | `laptop-monitor.sh`, `laptop-monitor-x11.sh`, `hyprland-clamshell-restore`                                                           |
| Screenshots                | `screenshot` (grim/slurp/tensaku), `screenshot.sh` (hyprshot/satty), `flameshot.sh`                                                  |
| Desktop helpers            | `i3-cmos-battery`, `keybase-popup-anchor-x11`, `volumecontrol.sh`                                                                    |
| Network menu               | `i3-tailscale-rofi`                                                                                                                  |
| Usage records              | `agent-usage`, `agent-usage-claude`, `agent-usage-codex`; `agent-usage-polybar`, `agent-usage-rofi` (i3/Polybar bar item and popout) |
| System utilities           | `aur-malware-check`, `artix-rank-mirrors`, `win11-vm-setup.sh`                                                                       |
| ArtCraft agent control     | `craft-apps` (with `craft-apps.toml`)                                                                                                |
| Shared dependency guard    | `lib/require.sh`                                                                                                                     |

## Requirements

The shell tools assume Linux, Bash, GNU core utilities, grep, sed, and gawk.
Install additional dependencies for the features being used:

| Feature                        | Dependencies                                                                                                           |
|--------------------------------|------------------------------------------------------------------------------------------------------------------------|
| Hyprland displays              | Lua-configured Hyprland, `hyprctl`, `wlr-randr`, `jq`, installed `hyprctl-live`                                        |
| X11 displays / DPI             | `xrandr`, `xrdb`                                                                                                       |
| Rofi menus                     | `rofi`, the installed shared helper, `notify-send` for notifications                                                   |
| Clamshell                      | `elogind-inhibit`, readable ACPI lid state                                                                             |
| Keyboard / mouse               | `hyprctl` or `setxkbmap`; `solaar` for Logitech DPI                                                                    |
| Session launcher               | gnome-keyring, OpenSSH agent tools, `/usr/bin/start-hyprland`, configured user D-Bus                                   |
| `screenshot`                   | `grim`, `slurp`, `wl-clipboard`, `hyprctl`, `jq`; optional `hyprpicker`, `tensaku-edit`                                |
| Other capture / audio wrappers | `hyprshot`, `satty`, `flameshot`, or `pavucontrol`, as applicable                                                      |
| Agent usage                    | Python 3.10+, `jq`; agent login and `codex` for live Codex limits; `rofi` and the bar's Nerd Font for the Polybar item |
| Tailscale menu                 | `tailscale`, Python 3, `jq`, `curl`, `xdg-open`, configured `~/.claude.json`                                           |
| Keybase popup                  | i3, `jq`, `flock`                                                                                                      |
| CMOS monitoring                | it87-family Vbat sensor                                                                                                |
| AUR audit                      | `pacman`, `curl` or a local denylist                                                                                   |
| Mirror ranking                 | Python 3.10+, `vercmp` (pacman), `bsdtar` (libarchive), network access                                                 |
| ArtCraft control               | Python 3.11+, the ArtCraft app packages, `claude` for `register`, `notify-send`                                        |

Quickshell and Polybar are output consumers, not requirements for the display
CLI. See [package installation guidance](docs/agent-guide/packages.md)
when choosing how to install a dependency.

## Installation

From the repository root:

```bash
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/sh"
ln -sfn "$(pwd)/lib/require.sh" "$HOME/.local/lib/sh/require.sh"

for script in i3-screen-manager i3-screen-rofi hyprctl-live \
    i3-keyboard-rofi i3-mouse-setup i3-mouse-rofi i3-cmos-battery; do
    ln -sfn "$(pwd)/$script" "$HOME/.local/bin/$script"
done
```

Keep `~/.local/bin` on the desktop session's PATH. Link optional tools by the
same method; install all three siblings for the agent-usage orchestrator, and
the Polybar pair on an i3 session:

```bash
for script in agent-usage agent-usage-claude agent-usage-codex \
    agent-usage-polybar agent-usage-rofi; do
    ln -sfn "$(pwd)/$script" "$HOME/.local/bin/$script"
done
```

The dotfiles repo supplies keybindings, autostart hooks, and bar widgets.
`start-hyprland` is a TTY session launcher, not an in-session autostart command;
resolve its installed path because dotfiles also supplies a desktop launcher.
The Tailscale and VM tools contain machine-specific settings; read their
[system guide](docs/agent-guide/system.md) before using them elsewhere.

### ArtCraft agent control (per machine)

`craft-apps` wires twelve ArtCraft apps to MCP: PhotoCraft, VectorCraft,
FilmCraft, LightCraft, EffectCraft, DesignCraft, FigCraft, WordCraft,
SoundCraft, DeckCraft, CADCraft and GridCraft. PdfCraft's MCP server is
headless only and ArtCraft has no row yet, so neither is wired. Each machine
needs its own launchers, token files, tool caches and MCP registration;
nothing in `~/.local/state/craft-control/` is shared or committed.

Install the apps first. The AUR packages build from tagged source releases
and the Rust builds take a long time. Follow the
[package guide](docs/agent-guide/packages.md): run `aur-malware-check` before
and after, and finish with a full `yay -Syu`, not `-Sy`.

```bash
yay -S photocraft vectorcraft filmcraft lightcraft effectcraft designcraft \
       figcraft wordcraft soundcraft deckcraft cadcraft gridcraft
```

Then, from the repository root:

```bash
ln -sfn "$(pwd)/craft-apps" "$HOME/.local/bin/craft-apps"
ss -ltn | grep -E ':187(0[1-9]|1[0-4])\b'  # expect nothing: reserved ports free
craft-apps list        # installed must equal verified on every wired row
craft-apps install     # 12 controlled launchers in ~/.local/share/applications
craft-apps register    # caches six proxied tool lists (headless, no window),
                       # then adds 12 user-scope MCP servers to Claude Code
claude mcp list | grep craft   # all twelve ✔ Connected with no app running
craft-apps check       # all ok; rerun install after package updates
```

Check every app twice, once with it stopped and once with it running:

```bash
for app in $(craft-apps list | awk 'NR > 1 && $3 != "-" {print $1}'); do
    craft-apps probe "$app" | tail -1   # stopped: a clean error (see below)
    craft-apps launch "$app" && craft-apps probe "$app" | tail -1   # running: ok
    craft-apps stop "$app"
done
```

A stopped direct bridge reports a refused connection ("the request was not
sent" or similar). A stopped proxied bridge (DeckCraft, DesignCraft, FigCraft,
GridCraft, VectorCraft, WordCraft) reports "<app> is not running with agent
control". Every running app must print `ok`. If `list` shows an installed
version that differs from `verified`, recheck that app per the
[ArtCraft guide](docs/agent-guide/artcraft.md#control-ports-and-bridges)
before updating its row.

Start a new Claude Code session to get the `mcp__<app>__*` tools; the agent
runs `craft-apps launch <app>` before using an app and `craft-apps stop <app>`
afterwards. Launching from an agent shell under Hyprland (where `launch` finds
the Wayland socket itself) was verified only on X11/i3 so far. Under Hyprland,
run the loop above from an agent or herdr shell and confirm each window
opens. PhotoCraft writes only into existing folders, so create an output
folder such as `~/Pictures/craft-samples` before saving there.

## Display Commands

`i3-screen-manager` chooses Wayland when `XDG_SESSION_TYPE=wayland` or
`WAYLAND_DISPLAY` is nonempty, and otherwise uses X11. Laptop layout commands
assume **`eDP-1` and one detected external**. The desktop's fixed dual-monitor
layout is owned by dotfiles, while focused-output scaling is available there.

| Command                         | Behavior                                                           |
|---------------------------------|--------------------------------------------------------------------|
| `extend-left/right/above/below` | Place the external relative to the internal panel                  |
| `clamshell`                     | External only; inhibit lid-triggered suspend                       |
| `mirror`                        | Hyprland mirror or X11 `--same-as`, using preferred modes          |
| `disconnect`                    | Restore internal only; refuse if the lid is closed or unreadable   |
| `scale [VALUE] [OUTPUT]`        | Wayland output scaling or session-wide X11 font DPI                |
| `dpi [VALUE] [OUTPUT]`          | Alias for `scale`                                                  |
| `status`                        | Detected outputs, monitor geometry, Wayland scale, inhibitor state |
| `apply-ws-split`                | Wayland only: move workspaces 7-10 to the detected external        |

```bash
i3-screen-manager status
i3-screen-manager extend-right
i3-screen-manager scale              # rofi picker
i3-screen-manager scale 1.5 eDP-1     # explicit Wayland output
i3-screen-manager dpi 1.25           # alias; 120 font DPI on X11
```

Wayland scale targets the focused output by default, with `eDP-1` as fallback;
it also reapplies preferred mode and automatic position. X11 sets `Xft.dpi`
through xrdb and needs newly launched apps. Neither persists monitor defaults.

The configured laptop workspace split is 1-6 internal / 7-10 external when
extended, all on external in clamshell, and all internal when undocked.
Hyprland hooks and persistent workspace rules in dotfiles complete this behavior.
See [display constraints and verification](docs/agent-guide/displays.md).

The keyboard and lid helpers still contain legacy Hyprland keyword calls;
their Lua-mode support is incomplete. Use `hyprctl-live` for queries from
shells that outlived a compositor restart. See the [Hyprland guide](docs/agent-guide/hyprland.md)
and [input guide](docs/agent-guide/x11-input.md).

## Common Bindings

The configured Hyprland bindings include:

| Binding                | Action                                              |
|------------------------|-----------------------------------------------------|
| `Super+Backspace`      | Display menu                                        |
| `Super+Ctrl+Backspace` | Keyboard menu                                       |
| `Super+Alt+Backspace`  | Scale picker (`dpi` alias on desktop)               |
| `Super+Alt+M`          | Mouse DPI, where installed                          |
| `Super+Shift+B`        | Bitwarden via `rofi-rbw --typer ydotool`            |
| `Super+Shift+N`        | Tailscale menu on the laptop                        |
| `Print`                | Flameshot                                           |
| `Super+Print`          | Region capture and annotation, with tensaku enabled |
| `Super+Shift+W`        | Quickshell restart                                  |

The authoritative bindings and machine gates are in
`dotfiles/.config/hypr/bindings.lua`. X11 bindings belong to their WM configs.

## Other Workflows

```bash
screenshot region
screenshot full --annotate
screenshot clipboard
agent-usage
agent-usage --limits-only
agent-usage --force
i3-cmos-battery cli
i3-cmos-battery quickshell
```

`screenshot` saves under `${XDG_PICTURES_DIR:-$HOME/Pictures}` and copies
captures to the clipboard. Clipboard annotation requires `tensaku-edit`.

`agent-usage` prints a merged JSON array and caches successful per-agent records
under `${XDG_STATE_HOME:-$HOME/.local/state}/agent-usage/`. Collectors use
their existing logins and local usage sources; cached files can outlive a
failed collection. The Quickshell widget polls stdout every ten minutes.
See [the JSON contract and failure behavior](docs/agent-guide/agent-usage.md).

`i3-cmos-battery` emits no output without an appropriate sensor. Its default
format is Polybar markup; `quickshell` emits volts and status for the widget.

`i3-tailscale-rofi` updates the Open Brain URL in Claude Code's `~/.claude.json`
only. `aur-malware-check` reports incident-denylist matches without removing
packages. `artix-rank-mirrors` prints a mirrorlist ranked by content freshness
and speed (`--arch` for the `[extra]` overlay) without editing `/etc/pacman.d`.
`craft-apps` writes desktop launchers that start the ArtCraft apps with their
control port and registers their MCP bridges with Claude Code.
`win11-vm-setup.sh` performs privileged host setup and does not
install the Windows guest. Their interfaces and verification are in the
[system guide](docs/agent-guide/system.md) and
[package guide](docs/agent-guide/packages.md).

## Maintenance

[CLAUDE.md](CLAUDE.md), also available through the `AGENTS.md` symlink, contains
shared working instructions and a [task-to-guide index](CLAUDE.md#task-guides).
Read the relevant guides under `docs/agent-guide/` as needed; they cover current
contracts, constraints, and verification without preloading every topic.
Update facts in place when changing behavior. Git contains previous
documentation and decisions. Dated evaluations of alternatives (for example
other window managers) live under `docs/research/`; they inform decisions but
are not loaded as agent instructions.

The shared root has an 8 KiB budget, with 16 KiB per topic guide. No increased
Codex document-loading limit is required for this repository's root file.
Validate documentation and its checker with:

```bash
python3 tools/check_docs.py
python3 -m unittest discover -s tools -p 'test_*.py'
```

There is no build or automated runtime test suite. Run syntax checks for
changed scripts and the relevant [behavioral checks](CLAUDE.md#verification)
for changed functionality. Desktop checks require the actual compositor and
hardware; a documentation update does not require rearranging live displays.

## License

MIT. Retain the attribution and license notices in vendored collectors.
