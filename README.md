# i3-screen-manager

Desktop automation for Artix Linux/OpenRC, with Hyprland/Wayland and X11
(i3/IceWM) support. The toolkit manages laptop displays, input settings,
screenshots, session helpers, hardware reporting, and coding-agent usage.
The `i3-` command names are used by existing menus and keybindings.

There is no build step. Scripts live here; desktop configuration and Quickshell
UI live in the companion `~/projects/dotfiles` repository. Scripts are normally
symlinked into `~/.local/bin`. Installing them does not install a desktop config.

## Tools

| Area | Commands |
|------|----------|
| Display CLI and menu | `i3-screen-manager`, `i3-screen-rofi` |
| Keyboard and mouse | `i3-keyboard-rofi`, `i3-mouse-setup`, `i3-mouse-rofi` |
| Hyprland session and sleep | `start-hyprland`, `hyprctl-live`, `hypr-dpms-all` |
| Lid handling | `laptop-monitor.sh`, `laptop-monitor-x11.sh`, `hyprland-clamshell-restore` |
| Screenshots | `screenshot` (grim/slurp/tensaku), `screenshot.sh` (hyprshot/satty), `flameshot.sh` |
| Desktop helpers | `i3-cmos-battery`, `keybase-popup-anchor-x11`, `volumecontrol.sh` |
| Network menu | `i3-tailscale-rofi` |
| Usage records | `agent-usage`, `agent-usage-claude`, `agent-usage-codex` |
| System utilities | `aur-malware-check`, `win11-vm-setup.sh` |
| Shared dependency guard | `lib/require.sh` |

## Requirements

The shell tools assume Linux, Bash, GNU core utilities, grep, sed, and gawk.
Install additional dependencies for the features being used:

| Feature | Dependencies |
|---------|--------------|
| Hyprland displays | Lua-configured Hyprland, `hyprctl`, `wlr-randr`, `jq`, installed `hyprctl-live` |
| X11 displays / DPI | `xrandr`, `xrdb` |
| Rofi menus | `rofi`, the installed shared helper, `notify-send` for notifications |
| Clamshell | `elogind-inhibit`, readable ACPI lid state |
| Keyboard / mouse | `hyprctl` or `setxkbmap`; `solaar` for Logitech DPI |
| Session launcher | gnome-keyring, OpenSSH agent tools, `/usr/bin/start-hyprland`, configured user D-Bus |
| `screenshot` | `grim`, `slurp`, `wl-clipboard`, `hyprctl`, `jq`; optional `hyprpicker`, `tensaku-edit` |
| Other capture / audio wrappers | `hyprshot`, `satty`, `flameshot`, or `pavucontrol`, as applicable |
| Agent usage | Python 3.10+, `jq`; agent login and `codex` for live Codex limits |
| Tailscale menu | `tailscale`, Python 3, `jq`, `curl`, `xdg-open`, configured `~/.claude.json` |
| Keybase popup | i3, `jq`, `flock` |
| CMOS monitoring | it87-family Vbat sensor |
| AUR audit | `pacman`, `curl` or a local denylist |

Quickshell and Polybar are output consumers, not requirements for the display
CLI. See [package installation guidance](CLAUDE.md#package-installation)
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
same method; install all three siblings for the agent-usage orchestrator:

```bash
for script in agent-usage agent-usage-claude agent-usage-codex; do
    ln -sfn "$(pwd)/$script" "$HOME/.local/bin/$script"
done
```

The dotfiles repo supplies keybindings, autostart hooks, and bar widgets.
`start-hyprland` is a TTY session launcher, not an in-session autostart command;
resolve its installed path because dotfiles also supplies a desktop launcher.
The Tailscale and VM tools contain machine-specific settings; read their
[system guide](CLAUDE.md#system-maintenance) before using them elsewhere.

## Display Commands

`i3-screen-manager` chooses Wayland when `XDG_SESSION_TYPE=wayland` or
`WAYLAND_DISPLAY` is nonempty, and otherwise uses X11. Laptop layout commands
assume **`eDP-1` and one detected external**. The desktop's fixed dual-monitor
layout is owned by dotfiles, while focused-output scaling is available there.

| Command | Behavior |
|---------|----------|
| `extend-left/right/above/below` | Place the external relative to the internal panel |
| `clamshell` | External only; inhibit lid-triggered suspend |
| `mirror` | Hyprland mirror or X11 `--same-as`, using preferred modes |
| `disconnect` | Restore internal only; refuse if the lid is closed or unreadable |
| `scale [VALUE] [OUTPUT]` | Wayland output scaling or session-wide X11 font DPI |
| `dpi [VALUE] [OUTPUT]` | Alias for `scale` |
| `status` | Detected outputs, monitor geometry, Wayland scale, inhibitor state |
| `apply-ws-split` | Wayland only: move workspaces 7-10 to the detected external |

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
See [display constraints and verification](CLAUDE.md#displays).

The keyboard and lid helpers still contain legacy Hyprland keyword calls;
their Lua-mode support is incomplete. Use `hyprctl-live` for queries from
shells that outlived a compositor restart. See the [Hyprland guide](CLAUDE.md#hyprland-and-quickshell)
and [input guide](CLAUDE.md#x11-and-input).

## Common Bindings

The configured Hyprland bindings include:

| Binding | Action |
|---------|--------|
| `Super+Backspace` | Display menu |
| `Super+Ctrl+Backspace` | Keyboard menu |
| `Super+Alt+Backspace` | Scale picker (`dpi` alias on desktop) |
| `Super+Alt+M` | Mouse DPI, where installed |
| `Super+Shift+B` | Bitwarden via `rofi-rbw --typer ydotool` |
| `Super+Shift+N` | Tailscale menu on the laptop |
| `Print` | Flameshot |
| `Super+Print` | Region capture and annotation, with tensaku enabled |
| `Super+Shift+W` | Quickshell restart |

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
See [the JSON contract and failure behavior](CLAUDE.md#agent-usage).

`i3-cmos-battery` emits no output without an appropriate sensor. Its default
format is Polybar markup; `quickshell` emits volts and status for the widget.

`i3-tailscale-rofi` updates the Open Brain URL in Claude Code's `~/.claude.json`
only. `aur-malware-check` reports incident-denylist matches without removing
packages. `win11-vm-setup.sh` performs privileged host setup and does not
install the Windows guest. Their interfaces and verification are in the
[system guide](CLAUDE.md#system-maintenance) and
[package guide](CLAUDE.md#package-installation).

## Maintenance

[CLAUDE.md](CLAUDE.md), also available through the `AGENTS.md` symlink, contains
shared working instructions and current technical guidance. It describes the
system as implemented; update facts in place when changing behavior. Git
contains previous documentation and decisions.

There is no build or automated runtime test suite. Run syntax checks for
changed scripts and the relevant [behavioral checks](CLAUDE.md#verification)
for changed functionality. Desktop checks require the actual compositor and
hardware; a documentation update does not require rearranging live displays.

## License

MIT. Retain the attribution and license notices in vendored collectors.
