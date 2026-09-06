# i3-screen-manager

Shared instructions for Codex and Claude Code. `AGENTS.md` is a relative symlink
to this file; edit `CLAUDE.md` to update both.

## Scope and Ownership

This is an Artix Linux/OpenRC desktop toolkit: shell scripts, two Python usage
collectors, and their operating documentation. There is no application build.
The `i3-` command names are public interfaces used by keybindings and menus.
Display and keyboard scripts have both Hyprland/Wayland and X11 branches.

The companion `~/projects/dotfiles` repository owns desktop configuration and
Quickshell UI. Paths written as `dotfiles/...` in these guides refer to that
sibling repository, not to a directory in this one. Read its instructions
before editing it. A shared contract may need changes in both repositories.

| Machine | Configured role |
|---------|-----------------|
| `nomad-artix` | ThinkPad X1 Extreme Gen 5, Intel/NVIDIA graphics, dynamic docking, battery/backlight, OpenRC-managed user audio |
| `godlike-artix` | AMD desktop, fixed landscape plus portrait monitors, audio launched by the desktop session |

Both Hyprland profiles select Quickshell and enable the tensaku screenshot
bindings. X11 i3/IceWM configurations also exist. Inspect the active session,
installed tools, and resolved config paths before making machine-specific
claims; repository configuration alone does not establish runtime state.

## Working Rules

- Read the affected scripts and their consumers before changing behavior.
  Preserve command names, arguments, output formats, and machine distinctions
  unless the task calls for changing those interfaces.
- Scripts are installed through `~/.local/bin` symlinks. Rofi scripts source
  `lib/require.sh` through `~/.local/lib/sh/require.sh`; use `_require` for
  non-universal commands so missing tools produce visible diagnostics.
- Resolve symlinks before editing deployed files. Preserve machine-local
  settings and understand whether a program rewrites its own config.
- Use `hyprctl-live` for compositor queries from agent or other long-lived
  shells. Preserve a usable display when changing docking or lid behavior.
- Treat Bash pipelines and expected command failures deliberately under
  `set -euo pipefail`. Keep diagnostics on stderr where stdout is an interface.
- Retain third-party copyright and license notices in vendored code.
- Documentation describes implemented behavior, constraints, and verification.
  Update the relevant fact in place when behavior changes. Use Git for history;
  do not append migration narratives, session logs, or completed task lists.
- Give each detailed fact one primary documentation home. Keep known defects
  separate from intended behavior, and verify discrepancies against code or
  the active machine rather than preserving contradictory claims.

## Task Guides

Read the matching guide **before changing that area**. Load only the guide(s)
needed for the task; links are not instructions to preload the whole directory.
For work crossing boundaries, read each affected guide. Within a guide, follow
further references only when relevant. Read source files to confirm behavior.

| Task or trigger | Guide | Main sources |
|-----------------|-------|--------------|
| Displays, docking, scale/DPI, lid transitions, workspace placement | [Displays](docs/agent-guide/displays.md) | `i3-screen-manager`, lid helpers; dotfiles monitor rules and workspace pools |
| Hyprland Lua, session startup, focus/groups, Quickshell bars/popouts/tray, screenshots, DPMS | [Hyprland and Quickshell](docs/agent-guide/hyprland.md) | Session/capture helpers; dotfiles `hypr/` and `quickshell/` |
| i3/IceWM, keyboard/mouse, rofi dependencies, clipboard/typing, Keybase popup | [X11 and input](docs/agent-guide/x11-input.md) | Input/rofi helpers, `lib/require.sh`; dotfiles WM configs |
| Agent collection, auth/limits, caches, JSON schema, usage widget | [Agent usage](docs/agent-guide/agent-usage.md) | `agent-usage*`; dotfiles `Agents.qml` and `AgentsPanel.qml` |
| OpenRC/audio ownership, GPU routing, CMOS, Tailscale/Open Brain, VM host setup | [System maintenance](docs/agent-guide/system.md) | `start-hyprland`, system utilities, machine-local services |
| Ghostty/Brave config and identity, chat layout, GTK dialogs, desktop app integration | [Applications](docs/agent-guide/applications.md) | Dotfiles launchers, terminal config, WM rules |
| Install/update/remove packages, choose distributions, review AUR, pacman/XLibre/hooks | [Package installation](docs/agent-guide/packages.md) | `aur-malware-check`, local pacman config, current vendor instructions |

For installation, command usage, and dependencies, see [README.md](README.md).
Names such as `hypr/` and `quickshell/` in the table are under
`dotfiles/.config/`. Each guide lists more specific source entry points.

## Verification

Run `bash -n` on changed Bash scripts and `sh -n` on POSIX shell scripts.
Parse changed Python collectors without executing account probes merely for
syntax validation. This repository has no automated runtime test suite.
Use focused behavioral checks described in the relevant guide; report
which live checks were actually performed.

Display commands, compositor reloads, bar restarts, package installs, and the
VM setup script affect the running machine. A documentation-only change needs
documentation checks, not a live desktop reconfiguration. The separate
`dotfiles/.config/hypr/tests/run.sh` exercises Lua configuration with a stub;
it does not establish real multi-monitor behavior.

After documentation changes, run `python3 tools/check_docs.py` for byte budgets,
local links/anchors, guide routing, and the shared symlink. Check the validator
itself with `python3 -m unittest discover -s tools -p 'test_*.py'`.

## Documentation Boundaries

Keep this root at or below 8 KiB, leaving headroom under Codex's default 32 KiB
combined project-instruction budget. Each topic guide has a 16 KiB budget.
Move growing detail to its owning guide; do not raise the loading limit to
compensate for growth. Split a guide further only when its task boundaries
justify separate loading, and make the routing trigger explicit.

The root owns universal rules and routing. Guides own technical contracts,
constraints, known limitations, and focused verification. The README owns
user-facing setup and usage. Do not add nested `AGENTS.md` files merely to
store reference detail, or eager includes that load every guide. Historical
investigations and superseded plans remain in Git, not in an archive to preload.
