# Applications

Read this guide for Ghostty/Brave identity and config deployment, chat layout,
GTK dialogs, ArtCraft agent control, or application-specific desktop
integration. Sources are chiefly dotfiles' launchers, `.desktop` overrides, WM
rules, terminal configs, and this repository's `craft-apps` with its table.

## Configuration and Window Identity

Resolve `~/.config/ghostty`, `~/.config/kitty`, and browser launcher paths on the
machine before editing. Shared files in dotfiles and live copies can differ.
Ghostty is the configured default terminal. Validate its parsed settings with
`ghostty +show-config`; keep comments on their own lines. Use a valid dotted
application ID with `--class` for Wayland rules and the configured
`--x11-instance-name` for X11 rules. Inspect user `.desktop` overrides when
single-instance or D-Bus activation changes window placement.

Brave Origin's profile directories are machine-local. `machine.lua` supplies
the alternate-profile directory to Hyprland launchers; do not assume identical
`Profile N` slots across hosts. Browser/PWA flags are determined by the first
process using the profile. If remote-debugging flags are required, launching
a PWA first without them can prevent a later browser command from applying
them. Inspect the running command and local launcher before changing flags.

Native-messaging host manifests and MIME associations are local integration
points. Recheck their paths when changing browser packages or profiles. For
broken Gmail link navigation, inspect the new tab's request chain: a redirect
into an extension resource indicates a different problem from a blocked
request or a window-manager focus rule. Fix a request-matching extension rule
at the affected request domain rather than assuming the originating tab's
domain is the relevant setting.

## Chat Layout

Dotfiles' `i3-chat-launch` selects the session-specific builder. The i3 path
uses `append_layout` and swallow criteria; its rebuild helper can close and
relaunch the chat windows. The Hyprland builder `hypr-chat-layout` launches
missing apps, selects their primary windows, parks targets on a special
workspace, and serially forms Messages/WhatsApp and
Discord/Keybase/Slack/Signal groups on workspace 10. The i3 skeleton's bottom
group is Discord/Slack/Keybase/Signal. Signal's class is `signal` under both
X11 and native Wayland; both builders are verified live with it. Group order and group locking are part of the
algorithm; app startup and largest-window selection handle transient helpers.
Rerunning rebuilds the grouping of existing windows. It can visibly move
windows and must remain a shell workflow because it waits for mapping.

The desktop has the chat builder integration. Shared Hyprland rules place
chat apps on workspace 10 on the laptop, but do not infer an automatic laptop
chat-wall build. Consult the actual autostart entries; a provided helper is
not necessarily enabled at login. Verify repeat invocation, missing apps,
main-window selection, tab order, and focus restoration after builder changes.

## GTK File Dialogs

For slow file dialogs, compare `gio info trash:///` with the same query under
`GIO_USE_VFS=local`. A GVfs trash-backend timeout can delay dialog construction.
The local VFS setting bypasses GVfs backends such as trash and network shares;
place it in the intended session/app environment if that behavior is wanted.
Check package reverse dependencies before removing GVfs. Do not reproduce
package-removal commands from an assumed dependency graph.

## ArtCraft Agent Control

The ArtCraft apps (PhotoCraft, GridCraft and the rest of `craft-apps.toml`)
start a loopback JSON-lines control server only when launched with
`--control <port>`; their `integrations.controlPort` preference is not wired up
upstream. `craft-apps` gives each app a fixed port in 18701-18714, the same on
every machine and below the ephemeral range, plus a token file
`~/.local/state/craft-control/<app>.token`. The token file is mode 0600 and is
created before first use, so a bridge started before its app can read it; the
app reuses it. The table's `[defaults]` grant automation read and write roots
of `~`. Without roots the apps refuse all automated file access.

`craft-apps install` copies each app's system desktop entry to
`~/.local/share/applications/` under the same id, so the copy replaces the
system launcher in menus, rofi, and MIME defaults. In the copy, the main `Exec`
runs `craft-apps launch <app> %F`; Desktop Actions still start the app
uncontrolled. A marker key records the source entry's SHA-256. `check` reports
`stale` after a package changes the system entry (rerun `install`), and
`remove` restores the system launcher.

`launch` starts the app with its row's `control_args`, waits for the port
(`--wait`), and logs to `~/.local/state/craft-control/<app>.log`. When the
shell's display variables are missing or stale, as in agent or herdr shells, it
finds a live Wayland socket or X display itself. A `--control` launch bypasses
the apps' single-instance handoff. So while a controlled copy holds the port,
`launch` with files opens them in a separate uncontrolled window and sends a
notification; without files it reports the running copy. Failures also notify,
since desktop launches have no terminal.

`register` adds each verified app's bridge to Claude Code at user scope as MCP
server `<app>`; rerunning it is a no-op when nothing changed. New servers appear
in new sessions. PhotoCraft's bridge connects on demand: a call made while the
app is down fails with "the request was not sent" and the bridge stays up. For
an agent, the workflow is `craft-apps launch <app>`, then the `mcp__<app>__*`
tools. Each machine is set up per the README's
[ArtCraft section](../../README.md#artcraft-agent-control-per-machine).

Through a bridge the agent drives the live window. `command_list` documents
each command's parameters, `command_batch` runs steps in order (one history
step each, stopping at the first error), and `ui_screenshot` returns the
window. File paths are relative to the automation roots (with `~` as the root,
`Pictures/x.png`) or absolute paths inside them. Paths outside are rejected, and
an output's parent directory must already exist. PhotoCraft's bridge saves with
the app's current export settings: `doc_save` and `doc_export` refuse
`quality` (JPEG/WebP) except in headless mode. Flat formats warn that layers
were flattened; `.pcraft` keeps them.

The apps spell their bridge flags differently. PhotoCraft uses
`mcp --bridge 127.0.0.1:<port>` with a token file; GridCraft and VectorCraft
document `mcp --connect`. A row is used only once `verified` names the version
checked with `<app> --help`, `<app>-cli mcp --help`, and `craft-apps probe <app>`.
Run the probe with the app stopped (expect a clean connection error) and running
(expect `ok`). Rows without `verified` only reserve a port. `list` shows the
installed and verified versions side by side; after an app update, repeat those
checks before changing `verified`. The control channel
is unencrypted loopback with a bearer token: whoever holds the token controls
the UI and runs commands, so keep token files private.

## Application Verification

Check the resolved config, effective settings, actual window identity, and
fresh versus already-running app launches. Exercise both Wayland and X11
paths when the change affects shared launchers. Prefer non-secret fixtures
for browser, clipboard, and password-manager integration checks. For
`craft-apps`, run `probe` with the app stopped and running, `check`, and
`desktop-file-validate` on a written launcher.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
