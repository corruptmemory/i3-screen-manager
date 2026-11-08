# Applications

Read this guide for Ghostty/Brave identity and config deployment, chat layout,
GTK dialogs, the Rex terminal server, or application-specific desktop integration.
Sources are chiefly dotfiles' launchers, `.desktop` overrides, WM rules, terminal
configs, and `rex-link`. The ArtCraft apps and `craft-apps` have their own
[guide](artcraft.md).

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

## Rex

Rex, a beta from Superlogical, is a terminal multiplexer. Its server holds sessions,
windows, and terminal blocks, and the `rex` CLI drives them on this machine or, with
`-S`, on another. Linux has only the server and CLI; the app that shows sessions is
macOS-only, so here agents use `rex run`, `send`, `capture`, and `wait`.

Rex comes from Superlogical's pacman repository, set up by hand: its `install.sh` takes
the pacman route only when os-release says `arch`, and Artix says `ID=artix` with no
`ID_LIKE`. Dotfiles stages `etc/pacman.d/rex.conf` and the signing key `rex.asc`
(fingerprint `E28636AC71905C6DDE40C1EDFAA6B80F641307A7`, added and locally signed with
`pacman-key`). The repo is last in `pacman.conf`. Only its snapshot channel has packages,
so any `pacman -Syu` may update Rex, through the scan hook. The package's systemd units do
nothing here; Artix's sysusers hook creates its `rex` account.

Dotfiles' `etc/init.d/rex-login-server`, adapted from the vendor's Alpine script, runs
`rex login-server` as root in the default runlevel. Its socket,
`/run/rex/login-server.sock`, is root-only, and `etc/rex/accounts.jsonc` lets root
(`peer:0`) open `jim`. A connection through it opens a PAM login session (the Arch policy
reaches `pam_elogind` through `system-remote-login`) and starts `rex server run
--exit-empty` as `jim` inside it. elogind counts that session, so a tty logout keeps
`/run/user/1000` and the server's socket, and plain `rex` reaches the server at the usual
path. A session started this way ran through a full logout and login with no gap. The
server stops about 10 seconds after its last session ends.

A server started any other way, by a plain `rex` command or `rex server start`, has no
login session of its own. A logout deletes its socket and leaves it running, unreachable,
with its saved sessions locked against the next server. Start work that must outlive a
logout through the login server: `sudo rex -S unix:///run/rex/login-server.sock new LABEL
-- COMMAND`. Known gap: dotfiles' i3 and Hyprland autostarts still run `rex server start`,
which makes such an unprotected server when none is running.

`rex-link LABEL SSH_DESTINATION` forwards another machine's server socket over SSH,
registers LABEL as a host, and checks that `rex -S LABEL` answers; `--stop LABEL` and
`--status` manage forwards. It opens no port and never starts the remote server. Never
add an `--allow-anonymous` listener: Rex has no logins yet, so anyone who reaches one gets
a shell as the account. Admit callers only through SSH or Tailscale identity.

`rex terminfo setup` installs `xterm-rex` in `~/.terminfo` and puts an `Include` of Rex's
guard at the top of the machine-local `~/.ssh/config`. Outside a Rex terminal the guard
changes nothing; `ssh -G` resolved the usual hosts identically before and after.
`rex skill setup` adds the `rex` skill, tracked in `~/.claude`, and a SessionStart hook in
the untracked `~/.claude/settings.json` and in `~/.codex/hooks.json`. Outside Rex the hook
prints nothing and starts no server. Codex runs its hook only after `/hooks` approves it.

The laptop has all of this. The desktop has an older tarball Rex in `/usr/local/bin` and
none of the setup: install the key, repo, package, login server, and accounts file from
dotfiles `etc/` as their headers say, delete `/usr/local/bin/rex` (it shadows
`/usr/bin/rex`), run `rex terminfo setup` and `rex skill setup`, and pull dotfiles. Then,
from the laptop, run `rex-link desktop jim@192.168.1.19` and `rex -S desktop ls`.

`rex-link self jim@localhost` tests the forward without a second machine: create a
session through `-S self`, check that `rex run --wait` returns the command's status, then
`--stop self` and `rex hosts remove self`.

## Application Verification

Check the resolved config, effective settings, actual window identity, and
fresh versus already-running app launches. Exercise both Wayland and X11
paths when the change affects shared launchers. Prefer non-secret fixtures
for browser, clipboard, and password-manager integration checks.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
