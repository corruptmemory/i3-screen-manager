# Package Installation

Read this guide before installing, updating, replacing, or removing tools,
reviewing an AUR package, malware scanning, or changing pacman repositories or
mirrors. Sources: `aur-malware-check`, `tool-audit`, `artix-rank-mirrors`, `/etc/pacman.conf`,
`/etc/pacman.d/mirrorlist*`, installed package metadata, and the
vendor's current distribution instructions.

## Selection Policy

Prefer these paths in order, checking suitability for the specific tool:

1. Official packages from the machine's configured Artix/Arch repositories.
2. The vendor's own native distribution, installer, or signed binary repository.
3. An isolated language-tool installation, such as pipx for a Python CLI.
4. A vendor container image for tools suited to occasional containerized use.
5. A locally maintained PKGBUILD when pacman integration warrants its upkeep.
6. An individually reviewed AUR recipe when the other paths do not fit.

Inspect the vendor/source identity, update path, and removal path. Keep Python
tools out of system site-packages; use an owned virtual environment or pipx.
Avoid sudo-driven global npm installs for project tooling. A vendor URL or
container namespace must actually belong to the publisher; retain available
signature/checksum verification. Read installer behavior before executing it.

Rung-5 forks in use on both machines: `odin-git-local`, `cursor-bin-local`,
`claude-desktop-local`, and `git-wd40` (Git with the WD-40 patchset; it provides and
conflicts with `git`). The first three rename the package, so the AUR never offers an
update. `claude-desktop-local`'s `update.sh` pins each `.deb` from Anthropic's signed apt
index; `cursor-bin-local`'s takes its hash from Cursor's download API. `git-wd40`
keeps the AUR `pkgname`, so `yay -Syu` offers to rebuild it from the AUR, which
would drop the fork's Artix deltas; exclude it (`--ignore git-wd40`) and sync
the fork at `~/projects/git-wd40` instead, per that repo's README.

Gemini CLI and opencode come from `extra`. Cursor's CLI and Grok's both install as
`~/.local/bin/agent`; here `agent` is Cursor's and Grok runs as `grok`. Cursor's updater
relinks `agent` on every update. Grok's fish block reads `fish_add_path --path --append
$HOME/.grok/bin`, so `~/.grok/bin/agent` stays behind `~/.local/bin`. Grok's installer, not
its updater, relinks `agent` and rewrites that block; after running it, run
`ln -sfn "$(readlink ~/.local/bin/cursor-agent)" ~/.local/bin/agent` and edit the block back.

A tool that runs `npx -y NAME` downloads `NAME` from npm unless npm's global folder,
`/usr/lib/node_modules`, where Arch's node packages install, already has it. Cursor's CLI runs
`npx -y typescript-language-server` in every folder it opens, so both machines install
`typescript-language-server` from `extra`; with npm's registry unreachable, `npx` still ran it.

## Pacman and XLibre

Inspect `/etc/pacman.conf` and sync metadata before assuming a package is AUR
only. An installed foreign package can have a matching official package now;
`pacman -Qm` alone does not establish its source or trust. The Arch `extra`
overlay is configured after Artix repositories on these machines; preserve
Artix package precedence and check init-system dependencies before changing
that arrangement. Do not perform partial upgrades as an installation shortcut.
Unattended `pacman -U`/`-S` with `--noconfirm` declines package-conflict
removals, so a package that deliberately replaces another (as `git-wd40` does
for `git`) fails with "unresolvable package conflicts"; add `--ask 4` to answer
that question class yes without affecting any other prompt.

The configured XLibre vendor source is `[xlibre-stable]` from XLibre for
Artix, `https://github.com/xlibre-artix/stable/releases/download/$arch`, after
`[system]` and before `[world]`, with an `IgnorePkg` entry for
`xorg-server xorg-server-common`. Its packages are signed by "XLibre for Artix
Linux Maintainers", key `AEF4CED426F70F7942FCB3D52AFFCD7B42ADD2E7`, locally
signed in the pacman keyring; the repository database is unsigned. Do not use
`packages.xlibre.net/arch` on Artix. Both repositories are built from the same
PKGBUILDs (`github.com/xlibre-arch/xlibre-arch`): the Arch build sets
`USE_SYSTEMD=1`, so its servers link libsystemd for the optional `sd_notify`
and `sd_listen_fds` hooks and depend on `libsystemd.so`, which nothing on Artix
provides (`artix-archlinux-support` provides only the names `systemd-libs` and
`libsystemd`, not the library). The Artix build sets `USE_SYSTEMD=0`, needs
only `libudev.so`, and lists `elogind` as optional. Preserve signature checking
and verify publisher keys through current authoritative instructions before
bootstrapping trust on another machine. Query package versions, owners, and
repositories instead of recording a version inventory as enduring fact.

For a dbus reload-hook error, compare the system hook, any local override,
and `/usr/share/libalpm/scripts/openrc-hook`. A local override can shadow a
correct packaged hook. The relevant dispatcher verb is `dbus_reload`; check
the installed implementation before prescribing an override. Do not carry
completed workaround deadlines forward as active tasks.

Arch can rebuild an `[extra]` package against a library soname Artix has not
shipped yet (OpenSSL 4, `libssl.so.4`, reached Arch `[core]` on 2026-10-24).
An unversioned dependency such as `openssl` lets the upgrade through, and the
program then fails with `error while loading shared libraries`. Compare
`readelf -d` `NEEDED` entries with the installed library, reinstall the
previous `pkgrel` from the cache with `pacman -U` (check its `NEEDED` first),
and hold the package with `IgnorePkg` until Artix `[system]` ships the
library; do not pull the library from an Artix testing repository. pacman.conf
has no end-of-line comments: words after a `#` on an `IgnorePkg` line become
package names (`pacman-conf IgnorePkg` lists them), so put notes on their own
line.

## Mirror Freshness

pacman fetches each repository's sync database from the first mirror in its
list that answers. A partly synced first mirror can therefore serve a current
`[world]` alongside a stale `[system]`, so `-Syu` installs packages built
against libraries that have not been delivered. An unversioned dependency lets
the transaction succeed; the failure appears at run time as `symbol lookup
error: ... undefined symbol`, first in post-transaction hook output and then
when programs start. `ldd` still reports every library found because symbols
bind lazily; `ldd -r <binary>` exposes the missing one. A low-level library
such as gdk-pixbuf or GLib can take down terminals, launchers, and compositors
at once.

To diagnose, find which library exports the missing symbol in a newer version,
then compare `pacman -Si <pkg>` across `[system]`/`[world]` and `[core]`/`[extra]`
with what is installed. Fix the mirror order and complete the upgrade with
`pacman -Syu`; do not leave a mix behind. Installing the matching `[extra]`
package can bridge a gap, but switch back to the Artix build
(`pacman -S world/<pkg>`) once Artix carries it. When the versions match, the
cached `[extra]` file has the same name, so the Artix signature check fails.
Answer yes to deleting the cached file, or remove it first, then reinstall.
Rerun the failed hooks' commands (for example `gtk-update-icon-cache` and
`gtk-query-immodules-3.0 --update-cache`) after the repair.

`artix-rank-mirrors` ranks mirrors and never edits `/etc/pacman.d` itself. It
judges freshness by database content, because some mirrors misreport
`Last-Modified`. For each repository it counts packages older than on any
other probed mirror, checking `system` then `world` in stages so that only
mirrors current on the small database download the large one. It ranks by
stages passed, then lag, then speed, and prints the top `--count` (default 8)
as a mirrorlist. Candidates come from `mirrorlist.pacnew`, else the cached
`artix-mirrorlist` package, else `--source FILE`. `--arch` ranks the `[extra]`
overlay from archlinux.org's status data (`--country`, default `US,CA`;
`--max-candidates`, default 20). Install the output with a backup:

```sh
artix-rank-mirrors -o /tmp/mirrorlist &&
  sudo cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak &&
  sudo install -m644 /tmp/mirrorlist /etc/pacman.d/mirrorlist
```

Then delete the consumed `.pacnew`. Use `--arch` and `mirrorlist-arch` for the
overlay. Exit codes: 0 when the first entry is current, 1 when even it lags,
and 2 on errors or when no mirror answers. Just after an Artix push only a few
mirrors are current; the ranking still leads with them. Exit 1 means wait and
rerun before a large upgrade.

## AUR Audit Contract

Run `aur-malware-check` before and after AUR operations as the repository's
package-maintenance convention. It defaults to installed foreign packages,
checks the Atomic-incident denylist, and can scan related filesystem and
scriptlet indicators. It is an incident-specific check, not a general guarantee
that a package is trustworthy. Review the recipe and changes independently.
When a recipe or a `Cargo.lock` pins a GitHub commit, confirm the commit is on
a branch of that repository: `gh api repos/O/R/compare/SHA...BRANCH` reports
`ahead` or `identical`, or `gh api repos/O/R/commits/SHA/branches-where-head`
names one. GitHub serves commits that exist only in a fork through the parent
repository's URLs, so a pinned hash alone does not prove where it came from.

Options: `--all` includes every installed package, `--deep` scans indicators,
`--near` checks similar names, `--list FILE` supplies a local list, and
`--url URL` changes the source. The tool downloads/caches the list with an
offline fallback and reports without removing packages or payload files.
Exit codes are 0 for no exposure found, 1 for exposure found, and 2 for errors.

Reviewed and rejected: AUR `screenconnect-bin`. It contains no software and needs the
installer from a ScreenConnect instance, hardcodes one instance's ID, and ships a systemd
unit that runs the client as root at boot. Take the client from the instance instead. Read
and scan the installer before running it, and confirm it is a technician client, not an
unattended agent that lets the instance's operators in. Both machines run a technician
client installed that way ([Applications](applications.md#screenconnect)).

## Malware Scanning

Dotfiles' `etc/pacman.d/hooks/90-pkg-scan.hook` runs
`etc/pacman.d/scripts/pkg-scan` on every install and upgrade. Both are copied
into `/etc` with the `install` commands in their headers, not symlinked, because
the script runs as root. It is a PreTransaction hook: it runs after download and
signature checks, before extraction and scriptlets. `AbortOnFail` works only
there; a PostTransaction hook runs after scriptlets and cannot block.

The hook receives package names, not paths. Repo files are found with
`pacman -Sp --print-format '%f'` in the cache; `pacman -U` files, which is how
yay installs AUR builds, come from the parent's command line, with relative paths
resolved against ancestor processes because pacman changes directory.

- **ClamAV** scans each package after extraction, as the `clamav` user, since
  ClamAV 1.5 does not unpack zstd: an EICAR file in a `.pkg.tar.zst` scans clean.
  Default limits also skip large files while reporting clean, so the limits are
  raised, and anything still too large is reported as not scanned.
- **Scriptlet lint** applies to `-U` packages: `.INSTALL` is checked for
  fetch-and-run commands, the form of the June 2026 AUR attack.
- **Blocking** happens only on a positive finding. A scanner failure warns and
  continues, and the summary says `INCOMPLETE`, so a broken scanner cannot block
  updates. `sudo touch /run/pkg-scan-skip-once` skips one transaction, for a false
  positive. Results are logged to `/var/log/pkg-scan.log`.
- **Not covered:** recipes run as the user during `makepkg`, before pacman starts,
  so build-time behavior needs the recipe review above.

Each scan process takes about 1 GiB and 5 seconds to load signatures, so one
package costs about 8 seconds. A 15-package update, 875 MiB unpacked, took 88
seconds with 4 processes. On hybrid Intel CPUs scans pin to the efficiency cores,
because 4 unpinned idle-priority processes reached the i7-12800H's 100 C limit.
The `clamd` service keeps signatures current with `START_CLAMD=no` in
`/etc/conf.d/clamd`, which leaves only the `freshclam` daemon running.

`tool-audit` covers what pacman never sees: vendor installers, self-updaters, and
language tools. It hashes the tool folders and startup files, diffs them against a
baseline, checks vendor checksums for Claude Code and herdr, and scans only changed
files. A changed file in a version folder, a checksum mismatch, or a detection is a
red flag and exits 1. Review the report, then run `tool-audit --accept`; it never
updates the baseline itself. `--full` scans all tool folders, which took about 20
minutes on the desktop and over 15 on the laptop. Add tools to `TOOL_ROOTS`; missing
folders are skipped. Keep a copy of `~/.local/state/tool-audit/baseline.tsv.gz` on
another machine, because anything running as the user can rewrite the local one. Each
machine holds the other's beside its own as `peer-HOSTNAME.tsv.gz`; refresh it after
an `--accept`.

Project `node_modules` folders are outside the tool folders. Scan one with `clamscan -r`
and the limits above, but ClamAV is a weak check on npm code, so also read
`hasInstallScript` and any non-registry `resolved` URL in its `package-lock.json`.

To set up a machine, run these from dotfiles' `etc/` directory:

```sh
sudo pacman -S --needed clamav clamav-openrc
sudo sed -i 's/^START_CLAMD=yes/START_CLAMD=no/' /etc/conf.d/clamd
sudo sed -i 's/^NotifyClamd /#NotifyClamd /' /etc/clamav/freshclam.conf
sudo freshclam
sudo rc-update add clamd default && sudo rc-service clamd start
sudo install -d /etc/pacman.d/hooks /etc/pacman.d/scripts
sudo install -m755 -o root -g root pacman.d/scripts/pkg-scan /etc/pacman.d/scripts/
sudo install -m644 -o root -g root pacman.d/hooks/90-pkg-scan.hook /etc/pacman.d/hooks/
```

To verify, build a dummy package containing the EICAR string and `pacman -U` it:
the transaction must abort with nothing installed. A clean package and a repo
reinstall must pass with `result: clean`. For `tool-audit`, two runs in a row must
report 0 changed, and a test file in `~/.config/autostart` must be listed.

## Package Verification

Check origin, signature policy, transaction contents, and dependency effects
before a package change, then verify installed ownership, the executable
resolved on PATH, and relevant service or desktop behavior. Validate the audit
tool with a local denylist and controlled package/indicator fixtures when
changing its matching logic; a live incident-list check is not broad test
coverage. After changing `artix-rank-mirrors`, run both modes and check the
exit status and the stderr ranking. Confirm that the first entry's databases
match an official mirror (`mirror2.artixlinux.org`) and that `--source` with a
missing file exits 2. Use current vendor documentation for native CLI
installation and authentication instead of retaining dated migration recipes
here.

## Watch List: Package Holds

Last reviewed: 2026-11-10. Both machines hold `mise` at 2026.11.5-1, the build
linked against OpenSSL 3; Arch's 2026.11.5-2 needs `libssl.so.4`. Trigger:
`pacman -Si system/openssl` reports version 4, or `-Syu` warns that it is
ignoring a `mise` upgrade while Artix ships OpenSSL 4. Then remove the
`IgnorePkg = mise` line and its note from `/etc/pacman.conf`, run `pacman -Syu`,
and confirm `mise --version` runs. Artix's `system-gremlins` testing repository
carried `openssl` 4.1.0 with an `openssl-3` compatibility package on 2026-11-10.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
