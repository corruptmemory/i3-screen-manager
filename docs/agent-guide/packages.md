# Package Installation

Read this guide before installing, updating, replacing, or removing tools,
reviewing an AUR package, or changing pacman repositories or mirrors. Sources:
`aur-malware-check`, `artix-rank-mirrors`, `/etc/pacman.conf`,
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

Rung-5 forks in use on both machines: `odin-git-local`, `cursor-bin-local`, and
`git-wd40` (Git with the WD-40 patchset; it provides and conflicts with `git`).
The first two rename the package, so the AUR never offers an update. `git-wd40`
keeps the AUR `pkgname`, so `yay -Syu` offers to rebuild it from the AUR, which
would drop the fork's Artix deltas; exclude it (`--ignore git-wd40`) and sync
the fork at `~/projects/git-wd40` instead, per that repo's README.

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

The configured XLibre vendor source is `[xlibre-stable]`, with
`https://packages.xlibre.net/arch/stable/$arch` before `[world]` and an
`IgnorePkg` entry for `xorg-server xorg-server-common`. Preserve signature
checking and verify publisher keys through current authoritative instructions
before bootstrapping trust on another machine. Query package versions, owners,
and repositories instead of recording a version inventory as enduring fact.

For a dbus reload-hook error, compare the system hook, any local override,
and `/usr/share/libalpm/scripts/openrc-hook`. A local override can shadow a
correct packaged hook. The relevant dispatcher verb is `dbus_reload`; check
the installed implementation before prescribing an override. Do not carry
completed workaround deadlines forward as active tasks.

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

Options: `--all` includes every installed package, `--deep` scans indicators,
`--near` checks similar names, `--list FILE` supplies a local list, and
`--url URL` changes the source. The tool downloads/caches the list with an
offline fallback and reports without removing packages or payload files.
Exit codes are 0 for no exposure found, 1 for exposure found, and 2 for errors.

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

[Shared instructions and task index](../../CLAUDE.md#task-guides).
