# Applications

Read this guide for Ghostty/Brave identity and config deployment, chat layout,
GTK dialogs, the herdr terminal server, Zoom, the ScreenConnect client, or
application-specific desktop integration.
Sources are chiefly dotfiles' launchers, `.desktop` overrides, WM rules, and terminal
configs. The ArtCraft apps and `craft-apps` have their own
[guide](artcraft.md), and so does [Rex](rex.md).

## Configuration and Window Identity

Resolve `~/.config/ghostty`, `~/.config/kitty`, and browser launcher paths on the
machine before editing. Shared files in dotfiles and live copies can differ.
Ghostty is the configured default terminal. Validate its parsed settings with
`ghostty +show-config`; keep comments on their own lines. Use a valid dotted
application ID with `--class` for Wayland rules and the configured
`--x11-instance-name` for X11 rules. Inspect user `.desktop` overrides when
single-instance or D-Bus activation changes window placement.

Fish's config sets no `TERM`, so each terminal's own `TERM` reaches its shell. Ghostty's
`ssh-env` shell-integration feature makes `ssh` from a Ghostty shell send `xterm-256color`,
because most remote hosts, node-0 among them, lack `xterm-ghostty`. `ssh-terminfo`, which
would install the entry on each remote host, stays off. kitty has no such wrapper set up,
so its `ssh` sends `xterm-kitty`.

Brave Origin's profile directories are machine-local. `machine.lua` supplies
the alternate-profile directory to Hyprland launchers; do not assume identical
`Profile N` slots across hosts. Every profile runs in one browser process, and
its flags come from whichever launch started it. Dotfiles'
`.config/brave-origin-flags.conf`, linked at `~/.config/brave-origin-flags.conf`
on both machines, gives every launch `--remote-debugging-port=9222` and
`--enable-features=WebMCP`: `/usr/bin/brave-origin` reads it and passes its
lines ahead of the launcher's own arguments. That covers a link opened while
Brave is closed, as an agent's `xdg-open` does, which starts it from the
package's `.desktop` file. Each Brave key (`Super+B`, `Super+y`, Hyprland and
i3) passes both flags as well. Chromium keeps only the last `--enable-features`,
so a launcher with its own list must include WebMCP. The chat wall's PWAs keep
the process running after its last browser window closes, so applying new flags
takes a full quit (`Ctrl+Shift+Q`). Inspect the running command (`ps -C brave`)
and local launcher before changing flags.

Each profile pairs with its counterpart on the other machine through its own Brave
Sync chain. The standard set is Bookmarks, Extensions, Settings, Themes, and History;
Passwords stay off, because Bitwarden holds them. Each device keeps its own selection,
and a new chain starts with Passwords on, so set both devices after joining. Treat the
chain's code like a password. Sync cannot install Brave's Manifest V2 uBlock Origin:
turn it on per profile under Settings, Extensions, Manifest V2 extensions. A theme
syncs only when it changes, so re-pick a color chosen before the chain existed.
History syncs new visits only.

Native-messaging host manifests and MIME associations are local integration
points. Recheck their paths when changing browser packages or profiles. For
broken Gmail link navigation, inspect the new tab's request chain: a redirect into
an extension resource means an extension rule, to fix at the request's domain, not
the originating tab's.

## Chat Layout

Dotfiles' `i3-chat-launch` selects the session-specific builder. The i3 path
uses `append_layout` and swallow criteria; its rebuild helper can close and
relaunch the chat windows. The Hyprland builder `hypr-chat-layout` launches
missing apps, selects their primary windows, parks targets on a special
workspace, and serially forms Messages/WhatsApp and
Discord/Keybase/Slack/Signal groups on the chat workspace. That is dotfiles'
`machine.lua` `chat_workspace`, read through `lua5.4`, or `--workspace N`: 10
(the panel's slot 10) on the laptop, 20 (the portrait's slot 10) on the
desktop ([Displays](displays.md#workspace-contract)). The i3 skeleton
stays on workspace 10, and its bottom group is Discord/Slack/Keybase/Signal.
Signal's class is `signal` under both
X11 and native Wayland; both builders are verified live with it. Group order and group locking are part of the
algorithm; app startup and largest-window selection handle transient helpers.
Rerunning rebuilds the grouping of existing windows. It can visibly move
windows and must remain a shell workflow because it waits for mapping. It
never focuses the workspace already focused, because the desktop's
`workspace_back_and_forth` would bounce away mid-build, and it ends on the
window that had focus when it started.

The desktop has the chat builder integration. Shared Hyprland rules place
chat apps on the same chat workspace on both machines, but do not infer an automatic laptop
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

## herdr

herdr, a terminal workspace manager for coding agents, keeps its panes in a `herdr server`
that the first `herdr` client starts and that outlives detached clients. To use the
desktop's panes from the laptop, attach from a laptop terminal with
`herdr --remote jim@100.64.248.76`, not by running `herdr` inside an `ssh` session. The
`--remote` client runs on the laptop and reaches the server through a `herdr
remote-client-bridge` over SSH, so only it can paste images. Its Ctrl+V
(`remote_image_paste` under `[keys]`) reads the laptop's clipboard image, the server
saves it under `/tmp/herdr-clipboard-images-1000/` and pastes that path, and Claude Code
attaches the file as an image. Inside plain `ssh`, Ctrl+V reads the desktop's clipboard.
Verified laptop to desktop over the tailnet.

`herdr integration install NAME` hooks an agent CLI into herdr, so its pane reports the
agent's session. Both machines have the claude, codex, opencode, cursor, antigravity-cli,
and grok integrations (`herdr integration status`). Cursor's adds a
`sessionStart` hook to `~/.cursor/hooks.json`, which the Cursor app's agent reads too; the
hook does nothing outside a herdr pane. `herdr agent list` shows each detected agent.

## Hype and Omacalc

Omarchy's MIT-licensed Qt Quick apps, Hype (Markdown presentations) and Omacalc
(calculator), are built from source as the user. They are not pacman packages:
the AUR has an unrelated `hype`, which `yay -Syu` would offer as an upgrade to a
locally built one. Their Qt dependencies, including `qt6-multimedia` and
`qt6-imageformats`, come from the official repositories.

Each is cloned to `~/projects/<app>` from `github.com/omacom/hype` or
`github.com/omacom-io/omacalc` and checked out at a release tag. Its own
`bin/build` runs `qmake6` and `make` into `build/`. `~/.local/bin/<app>` links to
`build/<app>`, and the repository's `pkgbuild/<app>.desktop` and `<app>.svg` are
copied to `~/.local/share/applications` and `~/.local/share/icons/hicolor/scalable/apps`.
To update, check out the newer tag and run `bin/build` again; copy the two files
again if they changed.

Hype opens from the app launcher, whose entry runs `hype open`; a bare `hype`
prints usage. Omacalc opens with `Super+Shift+Q` or the calculator key, and
floats under both Hyprland and i3. Both apps read colors from Omarchy's
`~/.local/state/omarchy/current/theme/colors.toml` when it exists and otherwise
use their own defaults; nothing writes that file here.

## Zoom

`zoom-web [URL]` opens Zoom's web client in Brave's `Default` profile as one `--app`
window, not the native client's many. It rewrites a `zoommtg://` or `zoomus://` link, or
`https://…zoom.us/j/ID`, to `app.zoom.us/wc/join/ID`, keeping only a digit ID and a
URL-safe passcode. Dotfiles' `Zoom.desktop` shadows the package's entry and handles both
schemes. `/usr/bin/zoom` remains for what the web client lacks.

## ScreenConnect

Both machines have a ScreenConnect technician client, installed per user from the
instance's own installer ([Package installation](packages.md#aur-audit-contract)). It
lives in `~/.local/share/applications/connectwisecontrol-<instance>/`, beside a
`.desktop` file that handles the `sc-<instance>` URL scheme. Its launch parameters say
`y=Host`, the technician side, and nothing starts it at boot. The client needs the
system Java runtime.

A Join link reaches the client through `xdg-desktop-portal`, which starts the handler
with the D-Bus session's activation environment, not the browser's. The client is Java
drawing through XWayland, so that environment needs `DISPLAY`. Dotfiles' `autostart.lua`
passes `DISPLAY` with `WAYLAND_DISPLAY` to `dbus-update-activation-environment` when
Hyprland starts, which reaches only programs D-Bus starts after that; restart a portal
that is already running without it. The launcher runs Java in the background and appends
all its output to `~/.local/share/applications/connectwisecontrol-<instance>-logs`, so
a failed start shows nothing in the browser. Read that log first, and check a Join after
a fresh Hyprland login when the session's startup environment changes.

## Steam

Steam's client starts inside its pressure-vessel container, and `pressure-vessel-wrap`
inspects every top-level directory. A FUSE mount under `/` whose daemon has stopped
answering therefore hangs the start, and any process that touches that mount, with
`~/.local/share/Steam/logs/console-linux.txt` ending at "re-launching steam in SteamRT
runtime". Keybase's root redirector (`keybase-redirector /keybase`) has done this by
deadlocking on its own mount. Diagnose without touching mounts:
`/sys/fs/fuse/connections/<N>/waiting` counts unanswered requests (root-only for root
mounts), where `<N>` is the mount's minor device number in `/proc/self/mountinfo`.
Quitting Keybase ends the redirector, and the waiting start continues. Run
`sudo fusermount -uz /keybase` before restarting Keybase: its redirector will not mount
over the stale mount (`~/.cache/keybase/keybase.redirector.log`).

## Application Verification

Check the resolved config, effective settings, actual window identity, and
fresh versus already-running app launches. Exercise both Wayland and X11
paths when the change affects shared launchers. Prefer non-secret fixtures
for browser, clipboard, and password-manager integration checks.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
