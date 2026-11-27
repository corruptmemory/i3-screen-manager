# Rex

Read this guide before changing Rex: its package and repository, the Rex Rune client, the
always-on login server, the Rex hosts between the machines, its terminfo, or its agent
skill and hooks.
Sources: dotfiles' `etc/pacman.d/rex.conf` and `rex-rune.conf`, `etc/init.d/rex-login-server`,
`etc/rex/accounts.jsonc`, the machine-local `~/.ssh/config`, and `rex --help`.

Rex, a beta from Superlogical, is a terminal multiplexer. Its server holds sessions,
windows, and terminal blocks, and the `rex` CLI drives them on this machine or, with
`-S`, on another. Superlogical's apps are for macOS, iOS, and Windows; on Linux the
unofficial [Rex Rune](#rex-rune) client fills that gap. Agents use `rex run`, `send`,
`capture`, and `wait`. GoRex is a replica with its own server, not a client. Docs:
`superlogical.com/rex/docs/llms.txt`; changelog: the `rex-community` MCP (Discord login).

## Package

Rex comes from Superlogical's pacman repository, set up by hand: its `install.sh` takes
the pacman route only when os-release says `arch`, and Artix says `ID=artix` with no
`ID_LIKE`. Dotfiles stages `etc/pacman.d/rex.conf` and the signing key `rex.asc`
(fingerprint `E28636AC71905C6DDE40C1EDFAA6B80F641307A7`, added and locally signed with
`pacman-key`). The repo is last in `pacman.conf`. Only its snapshot channel has packages,
so any `pacman -Syu` may update Rex, through the scan hook. The package's systemd units do
nothing here; Artix's sysusers hook creates its `rex` account.

## Rex Rune

Rex Rune (`github.com/shuv1337/rex-rune`) is a native Linux client for the Rex server,
written by a third party, not Superlogical. It connects to the local server like the
vendor's apps (`rex client list` shows it as kind `app`) and needs the server's
`api_revision` (`rex whoami --json`) inside the range its release notes state. It opens
a native Wayland window, class `dev.shuv.rex-rune`. Where it is installed, dotfiles'
`bindings.lua` makes Super+Enter focus that window or start it, because a second window
attaches to the same session and mirrors it; the tiled Ghostty moves to Super+Ctrl+Enter.
Both the bind and dotfiles' `dev.shuv.rex-rune.desktop` override start it as
`env FONTCONFIG_FILE=$HOME/.config/rex-rune/fonts.conf rex-rune`; start it the same way
from an agent shell, through `hyprctl-live dispatch 'hl.dsp.exec_cmd("...")'`.
On the desktop (Omarchy), omarchy-tweaks' `config/hypr/bindings.lua` does the same with
Omarchy's focus-or-launch bind, and the terminal moves to Super+Alt+Enter instead.

Rex Rune finds listening ports but does not forward them (0.13.1, tested 2026-11-27).
**Show listening ports…** in Commands lists a session's TCP listeners; for an SSH host,
Ctrl+Enter only copies an `ssh -N -L` command, which Rune never runs, and no setting
forwards. Superlogical's Mac app forwards on ⌘-click of a localhost link (Mac preview 31),
through Rex's own tunnel. Until Rune does, `rex -S HOST forward open -s SESSION --port N N`
listens on this machine's `localhost:N` and forwards through Rex to the host's, so the
pane's own `http://localhost:N` link opens here; `-s` names the session the forward
belongs to (required once the host has more than one), and `rex -S HOST forward close ID`
ends it. `rex cp` needs a server with the file-transfer block: an older running server
refuses it ("block flavor not found"), even when the installed package is newer.

That fontconfig file, a dotfiles link, hides TX-02's Oblique faces. They mark themselves
Regular (OS/2 `fsSelection` `0x00c0`, legacy subfamily "Regular"; only `post.italicAngle`
says otherwise), and Rune can pick one for upright text. Rex Rune then slants italic
from the Regular face; other programs keep the real Oblique faces.

Preferences live in `~/.config/rex-rune/workspace.json`, which the running client
rewrites, so edit it only while Rex Rune is closed. They match Ghostty: `font_family`
`TX-02`, `terminal_theme` `named:dracula-pro` (read from `~/.config/ghostty/themes`),
cursor `bar`, and the Rosé Pine chrome, the nearest of its four palettes to Dracula Pro's
background. Sizes differ in unit: Ghostty's points are 1/72 inch at 96 dpi, and Rex
Rune's are logical pixels, so Ghostty's 13 is Rex Rune's 17.33. Its row height is
`ceil(1.4 × size)` scaled by the line-height setting, not the font's own 1.2 em, so
`terminal.font.line_height` −17 gives Ghostty's rows. The file accepts −17 although
Settings steps by 5. Rex Rune has no sub-pixel (LCD) text setting: Rune has one, and Rex
Rune leaves it at the grayscale default.

The package, `rex-rune-bin`, comes from its author's own pacman repository,
`[rex-linux]` (`https://pkg.shuv.dev/arch/$arch`), the only package there. Dotfiles
stages `etc/pacman.d/rex-rune.conf` and its signing key `rex-rune.asc` (primary
`4BC4B85F4AF37FA0D834B0B52B192F3817340BAB`, the value in the project's
`packaging/keys/README.md`; added and locally signed with `pacman-key`). Its `Include`
follows `rex.conf`, so it is last and cannot shadow another repository's package. A
locally signed key is trusted for any package signature, not only this repository's.
`pacman -Syu` updates it. The package also ships a root helper,
`/usr/lib/rex-rune/rex-rune-update`, behind the polkit action `dev.shuv.rex-rune.update`
(an administrator's password every time) for the client's "Update now"; the helper needs
systemd and refuses on Artix. About 30 seconds after launch, and at most daily, the
client fetches a signed `latest.json` from GitHub to offer updates; Settings → Updates
(`updates.check`) turns that off. A good install has `/usr/bin/rex-rune`, `Validated By :
Signature` in `pacman -Qi rex-rune-bin`, and `channel=pacman` in
`/usr/share/rex-rune/channel`.

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
