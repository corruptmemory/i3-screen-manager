# Rex

Read this guide before changing Rex: its package and repository, the always-on login
server, the Rex hosts between the machines, its terminfo, or its agent skill and hooks.
Sources: dotfiles' `etc/pacman.d/rex.conf`, `etc/init.d/rex-login-server` and
`etc/rex/accounts.jsonc`, the machine-local `~/.ssh/config`, and `rex --help`.

Rex, a beta from Superlogical, is a terminal multiplexer. Its server holds sessions,
windows, and terminal blocks, and the `rex` CLI drives them on this machine or, with
`-S`, on another. Its apps are for macOS, iOS, and Windows, not Linux, so here agents use
`rex run`, `send`, `capture`, and `wait`. GoRex is a replica with its own server, not a
client. Docs:
`superlogical.com/rex/docs/llms.txt`; changelog: the `rex-community` MCP (Discord login).

## Package

Rex comes from Superlogical's pacman repository, set up by hand: its `install.sh` takes
the pacman route only when os-release says `arch`, and Artix says `ID=artix` with no
`ID_LIKE`. Dotfiles stages `etc/pacman.d/rex.conf` and the signing key `rex.asc`
(fingerprint `E28636AC71905C6DDE40C1EDFAA6B80F641307A7`, added and locally signed with
`pacman-key`). The repo is last in `pacman.conf`. Only its snapshot channel has packages,
so any `pacman -Syu` may update Rex, through the scan hook. The package's systemd units do
nothing here; Artix's sysusers hook creates its `rex` account.

## Always-On Server

Dotfiles' `etc/init.d/rex-login-server`, adapted from the vendor's Alpine script, runs
`rex login-server` as root in the default runlevel. Its socket,
`/run/rex/login-server.sock`, is root-only, and `etc/rex/accounts.jsonc` lets root
(`peer:0`) open `jim`. A connection through it opens a PAM login session (the Arch policy
reaches `pam_elogind` through `system-remote-login`) and starts `rex server run
--exit-empty` as `jim` inside it. elogind counts that session, so a tty logout keeps
`/run/user/1000` and the server's socket, and plain `rex` reaches the server at the usual
path. The server stops about 10 seconds after its last session ends, so the script's `start_post`
keeps it always on: unless one exists, it opens an idle `home` session (a fish shell)
through the login server. Restarting the service leaves the server and `home` running.
At boot the service starts before any login. The server restores `home` from its saved
state with a fresh shell, so `start_post` finds it and opens nothing. The log's "PAM
credentials not established" warning is expected: the policy's auth section is `pam_deny`.

A server started any other way, such as by a plain `rex` command after `home` was closed,
has no login session of its own: a logout deletes its socket and leaves it running,
unreachable, with its saved sessions locked against the next server. Restart the service
to bring `home` back.

Always on has costs. The `rex` login session holds `/run/user/1000`, so a logout no longer
clears it: the keyring stays unlocked, keys loaded in the SSH agent stay loaded, and the
same keyring daemon carries on into the next login. At boot the tty login's PAM still
starts the keyring daemon and unlocks it. On the laptop, the session's `pam_openrc` starts
the PipeWire user services at boot, before anyone logs in, and audio works as before.
The server has no display variables, so give commands that need the screen
`DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority` under X11, or `WAYLAND_DISPLAY=wayland-1
XDG_SESSION_TYPE=wayland DISPLAY=:0` under Hyprland. That includes `rbw` with a locked
vault: it hands its environment to pinentry, which otherwise waits where nobody sees it.
Its session is not the seat's active one, so
polkit refuses it the seat's locks, such as the lid-switch lock, and a process a Rex command
leaves in the background ends with that command. Start either kind under Hyprland with
`hyprctl-live dispatch 'hl.dsp.exec_cmd("...")'`.

## Hosts and Access

Each machine reaches the other as a Rex host over SSH, LAN first: `laptop` is
`ssh://nomad-artix` then `ssh://jim@100.90.248.89`, `desktop` is
`ssh://jim@godlike-omarchy` then `ssh://jim@100.64.248.76`, each plus
`/run/user/1000/rex/server.sock`. Each command runs `ssh` anew, so a sleeping laptop
breaks nothing. Without the socket path, Rex would start a server outside the login
session, as `ssh HOST rex ...` does; use `rex -S LABEL`. Its 10-second connect timeout
spans all endpoints, so each `~/.ssh/config` sets `ConnectTimeout 4` for these
addresses, above `Host *`; a dead first address then costs 4 seconds.

Rex has no logins; it admits callers by connection: its socket's owner, or whoever SSH
logs in as `jim`. Its Tailscale node (`rex server tailscale`, off on both) admits its
owner. Never add `--allow-anonymous`: every caller gets a shell as the account.

## Terminfo and Agent Hooks

`rex terminfo setup` installs `xterm-rex` in `~/.terminfo` and puts an `Include` of Rex's
guard at the top of the machine-local `~/.ssh/config`. Outside a Rex terminal the guard
changes nothing.
`ssh` runs the guard's `Match exec` through `$SHELL -c`, so a shell startup file that sets
`TERM` defeats it (one reason fish's config sets none), and a server whose `SHELL` is that
shell gives its terminals `xterm-256color`. `rex terminfo status` run with the server's
`SHELL` shows the decision.
`rex skill setup` adds the `rex` skill, tracked in `~/.claude`, and a SessionStart hook in
the untracked `~/.claude/settings.json` and in `~/.codex/hooks.json`. Outside Rex the hook
prints nothing and starts no server. Codex runs its hook only after `/hooks` approves it.

## Other Machines

The laptop has all of this. On Omarchy (the desktop) the package's user `rex.socket`,
held from boot by lingering, starts `rex.service` on first use; `rex server stop` saves
the sessions, and the next connection starts an upgraded server.
To set up another Artix machine: pull dotfiles, check that `rex.asc`
matches the key the vendor serves at `https://pkgs.superlogical.com/rex/keys/rex.asc`, and
install the key, repo, package, login server, and accounts file from dotfiles `etc/` as
their headers say. Delete any tarball Rex in `/usr/local/bin`, which shadows `/usr/bin/rex`,
then start the service and run `rex terminfo setup` and `rex skill setup`. Add the hosts
as above.

## Verification

To test a host, create a throwaway session with `rex -S LABEL new`, check that
`rex -S LABEL run --wait` returns the command's exit status, then `kill` the session.
