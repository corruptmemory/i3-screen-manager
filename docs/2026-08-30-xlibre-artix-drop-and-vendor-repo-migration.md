# XLibre → vendor-repo migration (Artix drops XLibre support)

**Date:** 2026-08-30 · **Machines:** `nomad-artix` DONE · `godlike-artix` DONE

## The event

On **2026-08-27** Artix posted "XLibre support discontinued":

> With the 2026.08 ISO release, Artix switched back to Xorg. The switch had been
> decided soon after the 2026.04 release, due to the unusually high amount of
> XLibre-related bug reports on our forum and started with our weekly ISO images.
> This resulted in backlash from XLibre and a veteran Artix developer, Artist,
> was targeted and harassed, which led to his resignation.
>
> Artist is the developer who made XLibre possible on Artix and we regret to
> inform our users that XLibre will no longer be packaged. Existing XLibre
> users will have it replaced by the corresponding Xorg packages soon. Should
> any choose to remain on XLibre, its 3rd-party repositories must be placed
> above [world] in /etc/pacman.conf, in full knowledge it is unsupported.

The Artix-side packages that matter here (`xlibre-xserver`, `xlibre-xserver-common`)
were already **removed from repos before this doc was written** — as of 2026-08-30
`pacman -Ss ^xlibre` on the laptop only shows the driver packages still lingering
in `galaxy/`; the two server packages are gone. What's installed on-box is the
"last version pulled" (25.1.9-1 for both, from 2026-08-19).

The decision was to **stay on XLibre**. Xorg has no meaningfully-maintained
non-XLibre fork; the XLibre project itself is active and shipping monthly.

## The maintained path: XLibre's own signed binary repo

XLibre operates a signed pacman binary repo at **`packages.xlibre.net/arch/`**,
managed by the `xlibre-arch` GitHub org (successor to the archived
`X11Libre/pkgbuilds-arch-based` and `X11Libre/binpkg-arch-based`). This is the
"3rd-party repositories" Artix's announcement pointed at — no other candidate
exists. Three channels, matching upstream release trains:

| Channel             | Series  | Purpose                           |
| ------------------- | ------- | --------------------------------- |
| `xlibre-stable`     | 25.1.x  | current stable (chosen)           |
| `xlibre-oldstable`  | 25.0.x  | backport-only                     |
| `xlibre-beta`       | 25.2.x  | next stable, in-flight            |

**This slots as rung 2 in `docs/install-paths-cheatsheet.md`** (vendor's own
maintained distribution), not rung 6 (AUR direct):

- Signed by upstream key `0C92313001CFCA27627B9098B97F7C613F359424`
  (short ID `B97F7C613F359424`).
- Packages carry external `.sig` files (detached PGP) fetched alongside `.pkg.tar.zst`.
- Verified by pacman on every install/upgrade — same enforcement model as Artix's own repos.
- Repo host: nginx over HTTPS+HSTS at `packages.xlibre.net`.
- Same publisher as the source releases (`X11Libre/xserver` on GitHub), on the
  same monthly cadence.
- Clean uninstall: remove repo section, `pacman -Rns xlibre-meta`, done.

## Trust bootstrap (the load-bearing security step)

The signing key is served from `xlibre-arch.github.io/xlibre-archlinux.asc` over
HTTPS+HSTS from GitHub Pages. **The fingerprint MUST be independently verified
before `pacman-key --lsign-key`** — that command marks the upstream key trusted
for signature verification of every future package install. If the GitHub Pages
site were ever compromised or DNS-hijacked, a bad key could ride the wrong
fingerprint through this step; verifying the fingerprint against a
second-channel value is the mitigation.

Verified on `nomad-artix` 2026-08-30:
```
pub   ed25519 2026-06-20 [C] [expires: 2028-07-01]
      0C92313001CFCA27627B9098B97F7C613F359424
uid   [full] XLibre for Arch Linux Maintainers <archlinux-maintainers@xlibre.net>
sub   ed25519 2026-06-20 [S] [expires: 2028-07-01]        <- signing subkey 02BA97000400DEDD7911E10C6A87EB02CFBFDB4F
sub   cv25519 2026-06-20 [E] [expires: 2028-07-01]
```

Independent verification path when doing the desktop (or re-verifying):
1. Compare the fingerprint against the value printed at
   <https://xlibre-arch.github.io/> (main page — it appears in the key
   installation block).
2. If wildly paranoid, cross-check by fetching the same key file from a different
   network (mobile hotspot, another site) and diffing.

## Recipe (per machine)

### 1. Import + verify + local-sign the upstream key

```bash
cd /tmp
curl -sSfL -O https://xlibre-arch.github.io/xlibre-archlinux.asc
gpg --show-keys xlibre-archlinux.asc                       # HUMAN-VERIFY fingerprint
sudo pacman-key --add xlibre-archlinux.asc
sudo pacman-key --finger B97F7C613F359424                  # cross-check what's in the keyring
sudo pacman-key --lsign-key B97F7C613F359424               # mark trusted
```

### 2. Add `[xlibre-stable]` ABOVE `[world]` in `/etc/pacman.conf`

Backup first:

```bash
sudo cp /etc/pacman.conf /etc/pacman.conf.bak.pre-xlibre-vendor-repo-$(date +%Y%m%d-%H%M%S)
```

Insert this stanza immediately before the `[world]` section. Order matters —
pacman evaluates repos top-to-bottom and the first-match wins, so `[xlibre-stable]`
above `[world]` guarantees XLibre packages win over any Xorg replacement Artix
pushes to `[world]`:

```ini
[xlibre-stable]
Server = https://packages.xlibre.net/arch/stable/$arch
```

### 3. Safety belt — pin Xorg OUT of any transaction

Add to the `[options]` section right under `HoldPkg`:

```ini
IgnorePkg    = xorg-server xorg-server-common     # safety belt post XLibre vendor-repo migration 2026-08-30
```

This is defense-in-depth against a hypothetical Artix `Replaces=` push that might
otherwise slip past repo priority. Both `xlibre-xserver` and `xlibre-xserver-common`
already declare `Conflicts With: xorg-server` / `xorg-server-common`, so pacman
would refuse the swap on its own — but the belt makes it categorically impossible.

### 4. Sync + upgrade

```bash
sudo pacman -Syu                    # picks up any pkgrel bumps from the new repo
sudo pacman -S xlibre-meta          # umbrella marker — 3.20 KiB, 0 installed size
```

### 5. Verify

```bash
pacman -Qi xlibre-meta xlibre-xserver | grep -E '^(Name|Version|Packager|Install Date)'
pacman -Si xlibre-xserver | grep -E '^(Repository|Version)'    # should say xlibre-stable
```

## Laptop execution log (`nomad-artix`, 2026-08-30 13:09-13:15 EDT)

Pre-migration state:
```
local/xlibre-input-evdev 25.0.0-9 (xlibre-drivers)         <- Artix-packaged
local/xlibre-input-libinput 25.0.1-3 (xlibre-drivers)      <- Artix-packaged
local/xlibre-xserver 25.1.9-1 (xlibre)                     <- Artix-packaged (artist@artixlinux.org)
local/xlibre-xserver-common 25.1.9-1 (xlibre)              <- Artix-packaged
```

Ran the recipe above. `-Syu` transaction was 3 packages: `mise` (unrelated,
already in queue from `extra`) + `xlibre-input-libinput 25.0.1-3 → 25.0.1-4` +
`xlibre-input-evdev 25.0.0-9 → 25.0.0-11`. Both driver bumps were pkgrel-only
(same upstream version, vendor's own pkgrel counter). Total transaction:
23.93 MiB download, 1.54 MiB net upgrade.

Post-migration state:
```
xlibre-input-libinput  25.0.1-4    Packager: XLibre for Arch Linux Maintainers  <- vendor now
xlibre-input-evdev     25.0.0-11   Packager: XLibre for Arch Linux Maintainers  <- vendor now
xlibre-xserver         25.1.9-1    Packager: artist@artixlinux.org              <- still Artix (same version, -Syu no-op)
xlibre-xserver-common  25.1.9-1    Packager: artist@artixlinux.org              <- same
xlibre-meta            25.1-1      Packager: XLibre for Arch Linux Maintainers  <- new umbrella
```

**Mixed-ownership note:** xserver + xserver-common still show Artix's `artist@…`
as packager because `-Syu` doesn't touch same-version packages regardless of repo
change. That will resolve itself on the next real version bump (25.1.10, etc.) —
`pacman -Si xlibre-xserver` already resolves to `xlibre-stable`, so the next
update will land from the vendor repo.

If you want to force the source-swap immediately:
```bash
sudo pacman -S xlibre-xserver xlibre-xserver-common     # forces reinstall of same version from higher-priority repo
```
Not done here — no functional gain, the bits are identical.

## Desktop execution log (`godlike-artix`, 2026-08-30 13:26-13:27 EDT)

Driven remotely from the laptop over SSH (`ssh jim@192.168.1.19`, pure TTY on
the desktop — no display manager, no X server, safe transaction window).

Pre-migration state (surprise vs. the 2026-07-05 doc's snapshot):
```
xlibre-input-libinput 25.0.1-3    Packager: artist@artixlinux.org  <- Artix-packaged
xlibre-xserver 25.1.9-1           Packager: artist@artixlinux.org  <- ALREADY on 25.1.x, not 25.0.0.x
xlibre-xserver-common 25.1.9-1    Packager: artist@artixlinux.org
```

The **desktop was already on `25.1.9`** — the July doc's snapshot of `25.0.0.23`
had been superseded by an Artix promotion at some point. Both machines therefore
started this migration on the same version, so `[xlibre-stable]` was the right
pick with no version jump on either box.

`xlibre-input-evdev` isn't installed on the desktop (pure AMD, only needs libinput
for mouse/keyboard). `xlibre-video-amdgpu` also isn't installed — the amdgpu path
runs via the kernel modesetting driver + the generic `modesetting` X DDX, not the
`xf86-video-amdgpu` DDX. Both are correct absences.

`-Syu` transaction was 22 packages (bigger backlog than the laptop; the desktop
hadn't been synced recently). Only one XLibre-touching item:
`xlibre-input-libinput 25.0.1-3 → 25.0.1-4` (pkgrel bump from vendor). Other
notable items: `binutils 2.47-4`, `tailscale 1.102.3-1`, `dhcpcd 10.5.2-1`,
`tpm2-tss 4.2.0-2`. Two side-notes surfaced by pacman that need follow-up but are
NOT part of this migration:

- `tar 1.35-5` advisory: `/usr/bin/backup` and `/usr/bin/restore` moved to a
  separate `tar-scripts` package. If either is used, `pacman -S tar-scripts`.
- `tpm2-tss` shipped two `.pacnew` files:
  `/etc/tpm2-tss/fapi-profiles/{P_ECCP384SHA384,P_RSA3072SHA384}.json.pacnew` —
  merge or diff, then remove `.pacnew`.

Post-migration state:
```
xlibre-input-libinput  25.0.1-4    Packager: XLibre for Arch Linux Maintainers  <- vendor
xlibre-xserver         25.1.9-1    Packager: artist@artixlinux.org              <- still Artix (same-version -Syu no-op)
xlibre-xserver-common  25.1.9-1    Packager: artist@artixlinux.org              <- same
xlibre-meta            25.1-1      Packager: XLibre for Arch Linux Maintainers  <- new umbrella
```

Same mixed-ownership state as the laptop; same auto-migration on the next real
version bump. Belt in place: `IgnorePkg = xorg-server xorg-server-common`.
Backup at `/etc/pacman.conf.bak.pre-xlibre-vendor-repo-20260830-132620`.

### Notes on driving from bash-in-Fish

The desktop's login shell is fish, which doesn't understand `set -e` or `<<HEREDOC`
inside the SSH command string. The workaround used was `ssh ... bash -s <<'REMOTE'`
— feed the whole recipe into bash on stdin, and it evaluates as expected (nested
`<<'PYEOF'` heredocs work fine inside the outer `bash -s`).

## Post-cutover watch-list (from the video-transcript bug-map)

None of the video's named bugs applied to daily-driver use on this hardware
(Hyprland primary; the two X11-only issues are low-priority under
Wayland-primary use; the CVE-lag concern was Artix's rebuild pipeline, gone
post-migration; the Intel-driver class doesn't apply since neither machine uses
`xlibre-video-intel`). But the video was ~80% drama recap; the ceiling on its
bug enumeration is thin. Smoke-test these after the desktop cutover:

1. **MPV video artifact:** `mpv --vo=gpu-next <known-good-file>` — no
   black/white bar or post-decode tearing.
2. **X11-fallback SIGSEGV:** the day you boot into IceWM/i3, run
   `journalctl _COMM=Xorg -f` in a scratch pane; a mid-session Xorg segfault is
   the "server crash after few hours of inactivity" bug landing.
3. **Touchpad tap + natural-scroll** (laptop) after `xlibre-input-libinput`
   bumps — the two knobs that classically break in libinput jumps.
4. **Portrait panel** (desktop) after `xlibre-video-amdgpu` bumps — verify
   HDMI-A-1 comes back at `transform=3`, VRR-off, no aquamarine flicker.
5. **Version-diff on every `-Syu`** — grep `xlibre-` in
   `/var/log/pacman.log` after upgrading to log the version transition,
   so a rollback to `[xlibre-oldstable]` is one command away if a regression
   lands.

## Rollback recipes

**To another XLibre channel** (25.1 → 25.0 backport-only):

```bash
# swap the stanza in /etc/pacman.conf:
[xlibre-oldstable]
Server = https://packages.xlibre.net/arch/oldstable/$arch
# then:
sudo pacman -Syyuu       # allow downgrades
```

**Off XLibre entirely** (rejoin the Artix Xorg mainline):

```bash
# remove the belt:
sudo sed -i '/IgnorePkg.*xorg-server/d' /etc/pacman.conf
# remove the vendor repo stanza (undo the pacman.conf edit)
# then:
sudo pacman -Rns xlibre-meta                              # drop the umbrella marker
sudo pacman -S xorg-server xorg-server-common             # pacman resolves the Conflicts=, replaces XLibre
```

Neither expected. Documented so the exit path is a single grep-and-run away.
