# Package Installation

Read this guide before installing, updating, replacing, or removing tools,
reviewing an AUR package, or changing pacman repositories. Sources:
`aur-malware-check`, `/etc/pacman.conf`, installed package metadata, and the
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

## Pacman and XLibre

Inspect `/etc/pacman.conf` and sync metadata before assuming a package is AUR
only. An installed foreign package can have a matching official package now;
`pacman -Qm` alone does not establish its source or trust. The Arch `extra`
overlay is configured after Artix repositories on these machines; preserve
Artix package precedence and check init-system dependencies before changing
that arrangement. Do not perform partial upgrades as an installation shortcut.

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
coverage. Use current vendor documentation for native CLI installation and
authentication instead of retaining dated migration recipes here.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
