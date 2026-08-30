# Install-paths cheat sheet — where to get software when AUR is sus

**Date:** 2026-08-11 (updated 2026-08-13: added *Reclaiming an AUR-graduate*; updated 2026-08-21: added the herdr rung-2 worked example — first *fresh* install decided by this doc, not a migration; updated 2026-08-28: installed herdr on `godlike-artix` (v0.8.2, sha256-verified), and corrected the original 2026-08-21 install's machine to `nomad-artix` — it was first written as `godlike-artix` in error; also 2026-08-28: added the **tensaku** rung-2 worked example — prebuilt binary, since `cargo install` is blocked by a yanked crates.io dep) · **Applies to:** both machines (Artix, `godlike-artix` desktop + `nomad-artix` laptop) · **Related:** `docs/2026-08-10-aur-supply-chain-assessment.md` (the "why AUR is under scrutiny" primary-source assessment) · `aur-malware-check` (the audit script) · `docs/claude-code-aur-to-native-migration.md`, `docs/codex-aur-to-native-migration.md`, `docs/brave-to-brave-origin-migration.md` (worked examples of AUR → native migrations)

## The problem this doc exists for

Post-June-2026 "Atomic" AUR supply-chain incident (Rust infostealer + optional
eBPF rootkit distributed via ~400–1500 AUR packages), the operating posture is:

> **AUR is hostile-by-default. Every install is a decision, not a default.**

That works fine for the tools you already installed and have `aur-malware-check`'d.
The question this doc answers: **when you want to install something NEW and it's on
the AUR (or you don't know where else to get it), what's the decision procedure?**

## The decision procedure (short form)

Try these in order. Stop at the first one that fits:

1. **Official Artix / Arch repos** (`pacman -Ss <name>`)
2. **Vendor's own native installer with auto-update** (curl-pipe-sh from vendor site)
3. **`pipx install <name>`** if it's a Python tool
4. **`docker run <vendor-image>`** if it's occasional-use and containerises cleanly
5. **Local PKGBUILD fork** (the Odin trick) if you use it daily and want pacman integration
6. **AUR anyway, after `aur-malware-check`** — case-by-case, not blanket rejection

The rest of this doc is the *why* behind each rung, plus the trade-off table.

## The trade-off table

| Rung | Trust story | Update model | Uninstall model | Best fit |
|---|---|---|---|---|
| 1. Repo | Artix packagers curate + sign; pacman verifies. Highest trust surface available. | `pacman -Syu` | `pacman -R` | Anything the distro packages. **First check every time** — and on Artix "the distro" includes the Arch `extra` overlay, which ships *disabled*; enabling it is part of a complete rung-1 check (see *Reclaiming an AUR-graduate*). |
| 2. Vendor native installer | Direct-from-vendor binary, vendor-published checksums (some vendors publish signed manifests). Removes all repackagers from the trust chain. | Self-update from vendor's own channel — no package manager involved. | Vendor-specific (usually `~/.local/…` tree + a symlink; `rm -rf` works). | Big single-vendor tools with active release cadence: Claude Code, Codex, Brave Origin. All three took this path. |
| 3. `pipx` | PyPI + vendor's own PyPI publication. Isolated per-tool venv under `~/.local/pipx/venvs/<name>/`. Trust surface widening = PyPI, but that's already in the trust set (via other Python tools + the fact that pip/pipx are themselves trusted). | `pipx upgrade <name>` per-tool. | `pipx uninstall <name>` — zero collateral, entire venv goes. | Python tools, especially security/lint tools where isolation matters. |
| 4. Docker | Vendor-published image, digest-pinnable, zero host install. Trust surface is Docker Hub / vendor registry + the image's own supply chain. | `docker pull <image>:<tag>` when you want the update. | `docker rmi <image>` — nothing on the host to clean up. | Occasional-use tools; tools with pathological dep chains; tools where you actively don't want the host to know about them (dev-only linters, one-shot audits). |
| 5. Local PKGBUILD fork | AUR entirely out of the trust path — you review the recipe once, host it in your own private git repo, and `makepkg` fetches only from the `source=` line (which points at the vendor's official git or release URL). Full pacman integration retained; the recipe is what you're on the hook for. | `git pull && makepkg -si` on your fork. `-git` packages auto-track upstream master. | `pacman -R` clean. | Daily-driver tools where you genuinely want pacman integration and the vendor doesn't ship a native installer. **Odin is the working example** — see `~/.claude/CLAUDE.md` § "Odin — install from the private odin-git-local fork". |
| 6. AUR direct | Aggregation point for community-maintained recipes; each package is one maintainer's PKGBUILD that pulls from that maintainer's chosen source. Post-2026 incident, **not** an assumed-trustworthy tier — but not blanket-untrusted either. Individual packages remain reviewable. | `yay -Syu` (or refuse it — see below). | `pacman -Rs` (walks the transitive dep chain like any pacman removal). | Fallback when 1-5 don't fit AND the tool is important enough to justify per-package review. **Run `aur-malware-check` before AND after every AUR touch.** Diff the `PKGBUILD` between updates (`yay -G <name>` gets the raw recipe). |

## Worked examples that shaped this doc

| Migration | From | To | Rung | Why that rung |
|---|---|---|---|---|
| Claude Code | AUR `claude-code` | vendor `install.sh` + auto-update in `~/.local/share/claude/` | 2 | Big self-updating vendor tool with a real release cadence — perfect fit for a native installer |
| Codex CLI | AUR `openai-codex-bin` | OpenAI's official installer + `~/.codex/packages/standalone/` | 2 | Identical shape to the Claude Code case |
| Brave browser | AUR `brave-bin` | paid Brave Origin (`brave-origin-bin`) | 2 (was 6, moved for a different reason — paid feature) | Vendor tier with self-update |
| Odin | AUR `odin-git` | private fork at `github.com/corruptmemory/odin-git-local` | 5 | Daily-use, pacman integration wanted, vendor doesn't ship a native installer, AUR recipe went stale against upstream anyway |
| Semgrep (hypothetical re-install) | AUR `semgrep-bin` (uninstalled 2026-08-11 for non-use, not for trust) | **`pipx install semgrep`** would be the right rung | 3 | Vendor publishes to PyPI directly, isolation is real, uninstall is one `pipx uninstall` (vs the 34-package `-Rs` cascade the AUR install left) |
| `git-delta`, `azure-cli`, `rbw` | self-built AUR copies, orphaned when they moved to `extra` | official `extra`, Arch-signed | 1 | Exact name resolves in `extra` once the overlay is on — **reclaim, don't fork**. Worked on `godlike-artix` 2026-08-13; see *Reclaiming an AUR-graduate* |
| `herdr` (new install: `nomad-artix` 2026-08-21, `godlike-artix` 2026-08-28) | not previously installed | vendor `install.sh` → `~/.local/bin/herdr` (v0.8.2), self-update via `herdr update` | 2 | Rung-1 empty (nothing in Artix/Arch repos). Vendor ships a single static-pie Rust binary with a **sha256-verified** install script (`https://herdr.dev/install.sh` — mandatory checksum against `https://herdr.dev/latest.json`; script errors out if the manifest lacks a valid hash). No `sudo`, no `/usr` writes, no init-system unit. AUR has `herdr-bin` + `herdr` but both trail upstream and are single-maintainer recipes of exactly the "freshly-adopted low-eyeballs" shape flagged in the 2026-08-10 assessment. Origin trigger was a DHH endorsement (Omarchy Quatro video, `youtu.be/F7fe9pa8OeE`) — worth logging because trust cascaded through a known operator rather than a package tier. **First fresh-install decision made by this doc rather than a migration in from an existing rung.** Promote to rung 5 (fork `herdr-bin`) only if it earns a permanent spot and pacman integration becomes worth the maintenance. |
| `tensaku` (screenshot annotator, `godlike-artix` 2026-08-28) | not previously installed; the vendor page calls AUR `tensaku` "recommended" | vendor **prebuilt release binary** → `~/.local/bin/tensaku` + `tensaku-edit` (v0.28.0) | 2 | Rung-1 empty. The **rung-3 attempt fails**: `cargo install tensaku` dies on a yanked crates.io transitive dep (`gl_generator` → `xml-rs 0.7.0`/`0.7.1`, both yanked) — resolution can't complete, so cargo is a dead end here. The GitHub release ships a clean `bin/`+`share/` tarball (x86_64, no toolchain; GTK4 + libadwaita runtime already present) that sidesteps **both** the AUR and the crates.io breakage. No `sudo`, no `/usr` writes. Updates are manual (re-download on a new release); no upstream checksum is published, so the trust anchor is pulling from the official `jondkinney/tensaku` GitHub release over HTTPS (sha256 recorded in the session log). A clean "AUR-recommended, but the prebuilt binary is the right non-AUR rung, *and* a reminder that rung-3 language installers can be blocked by upstream dep rot" case. |
| **XLibre X server + drivers** (`nomad-artix` 2026-08-30, `godlike-artix` pending) | Artix `world` + `galaxy` (packaged by `artist@artixlinux.org`) — dropped by Artix 2026-08-27 | **vendor-run signed pacman binary repo**: `[xlibre-stable] Server = https://packages.xlibre.net/arch/stable/$arch` above `[world]`, umbrella package `xlibre-meta` | 2 | Rung-1 was closed by Artix's own decision (see `docs/2026-08-30-xlibre-artix-drop-and-vendor-repo-migration.md`). The vendor spun up `xlibre-arch` GitHub org (successor to archived `X11Libre/pkgbuilds-arch-based` + `binpkg-arch-based`) with a signed binary repo — packages carry external `.sig` files (PGP), verified by pacman against the upstream signing key `0C92313001CFCA27627B9098B97F7C613F359424` (short ID `B97F7C613F359424`) which is `--lsign-key`'d into the local pacman keyring. Three channels: `stable` (25.1.x, chosen), `oldstable` (25.0.x), `beta` (25.2.x). Monthly release cadence, same publisher as the source releases. **AUR `xlibre-meta` exists but the vendor repo obsoletes it** — signed binaries win over PKGBUILDs-that-eval-at-build. A clean "vendor decided to run their own binary repo after their distro packager stepped away, still rung-2 because no local recipe review + pacman signature enforcement" case. Rung-5 (private PKGBUILD fork of ~30 packages) is the documented backup if the vendor infra ever disappears. |

## Trap classes — things that *look* like a rung but aren't

- **"It's on PyPI, so `sudo pip install`"** — NO. System-wide `pip install` mixes vendored Python packages with the distro's site-packages and creates unfixable version conflicts. If it's Python and not in Artix repos, `pipx` (isolated per-tool venv) is the answer. `pip` is fine only inside `venv`s you own.
- **"It's on npm, so `sudo npm install -g`"** — same trap, same fix. `npx` per-invocation (no install) or a project-local `node_modules` (never global) for actual dev.
- **"It's on Docker Hub, so `docker pull <random-user>/<image>`"** — Docker Hub has its own supply-chain surface. Prefer vendor's own repo (`docker.io/<vendor>/…`) or vendor's own registry (`ghcr.io/<vendor>/…`). Digest-pin (`image:tag@sha256:…`) for anything that matters.
- **"It has a `curl … | sh` install command, so it must be trusted"** — that URL still needs to be the *vendor's* URL, not a random blog's mirror. Compare with the vendor's own README / release page. When practical, `curl -o /tmp/install.sh https://vendor/install.sh` first, `less` it, then `sh /tmp/install.sh` — no worse than `curl | sh` in the good case, meaningfully better in the compromised case.
- **"Snap / Flatpak"** — legitimate rungs elsewhere; the trust surfaces (canonical.com, flathub.org) are different and each has its own history. Neither is in active use on these machines, so they're not on the primary decision tree — but if you find yourself repeatedly wanting one, add it as rung 3.5 with its own row above.

## The `aur-malware-check` habit

Regardless of rung choice, whenever you DO touch the AUR (rung 6 or maintenance
of existing AUR packages), run `aur-malware-check` before and after. The script:

- Downloads the latest denylist from the June 2026 "Atomic" campaign (with an
  offline fallback cache).
- Compares against `pacman -Qm` (installed foreign packages) by default; `--all`
  widens to every installed package.
- `--deep` adds a pacman-scriptlet + filesystem IOC scan.
- `--near` flags confusable look-alikes (safe name installed, malicious twin exists).
- Exit 0 = clean, 1 = exposed, 2 = error — drops into a login hook or `&&` chain.

Suggested pattern for any AUR-touch session:

```sh
aur-malware-check && yay -Syu && aur-malware-check
#                    ^^^^^^^^^ your update runs BETWEEN two clean checks
```

## The active AUR install list (per-machine, review quarterly)

`pacman -Qm` on each machine gives the current list. Every entry there is an
implicit "this one's still worth the AUR trust cost." Periodically ask: **has
this graduated to a rung-1-through-5 install path yet?** Two examples that did:

- **`claude-code`** → native installer (rung 2). `claude-code` no longer appears
  in `pacman -Qm`; it lives in `~/.local/share/claude/`.
- **`openai-codex-bin`** → native installer (rung 2). Same migration shape.

## Reclaiming an AUR-graduate — when a foreign package already has a rung-1 home

Sometimes a package you built from the AUR *graduates into the official repos*.
When that happens the AUR entry is deleted, so `pacman -Qm` still shows your
self-built copy but it has no upstream to update from. The tell is unmistakable:

> `yay` reports the package under **"Packages not in AUR"** while it still sits in
> `pacman -Qm` (foreign). That combination means "graduated," not "abandoned."

The fix is **not** a rung-5 fork — it's a **rung-1 reclaim**: re-point the package
at its now-official, distro-signed source. On Artix there's one catch: first-party
Arch packages live in the **Arch `extra` overlay**, which is *not enabled by
default* (base `pacman.conf` ships only `system`/`world`/`galaxy`/`lib32`). So a
complete rung-1 check on Artix is a two-parter — enable the overlay, then look:

```sh
# After the overlay is enabled (procedure below): every foreign package whose
# EXACT name now resolves in a sync repo is a reclaim candidate.
for p in $(pacman -Qmq); do
    pacman -Si "$p" >/dev/null 2>&1 && echo "reclaimable: $p"
done
```

If `pacman -Si <name>` resolves it graduated (reclaim it); if it doesn't it's
either genuinely AUR-only (leave it) or a real rung-5 candidate. That one loop
partitions the whole foreign list.

### Reproducible procedure (Artix) — enable the `extra` overlay + reclaim

Prerequisite (already true on `godlike-artix`; **verify on the laptop**):
`artix-archlinux-support` installed — it provides `archlinux-keyring` and
`/etc/pacman.d/mirrorlist-arch`. Check with `pacman -Q artix-archlinux-support`.

```sh
# 1. Back up, then enable the Arch 'extra' overlay BELOW the Artix repos, so
#    Artix's init-agnostic forks always win a name collision (pacman is
#    first-listed-wins, regardless of version number).
sudo cp -av /etc/pacman.conf /etc/pacman.conf.bak-$(date +%F)
sudo tee -a /etc/pacman.conf >/dev/null <<'CONF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch
CONF

# 2. Trust the Arch signing keys (idempotent).
sudo pacman-key --populate archlinux

# 3. Preview first — refreshes dbs (incl. the new extra.db), commits nothing.
#    On a daily-synced box this should list ONLY the graduates with a newer
#    version in extra. If it wants to replace/remove anything Artix-core, STOP.
sudo pacman -Syu --print

# 4. Commit the upgrade.
sudo pacman -Syu

# 5. Same-version graduates aren't caught by -Syu (nothing to upgrade). Flip
#    their provenance foreign -> extra with an explicit reinstall:
sudo pacman -S extra/<pkg>        # e.g. extra/rbw
```

Verify: `pacman -Qm` no longer lists them; `pacman -Qn <pkg>` now does; the
binary still runs.

**Why this beats forking:** a rung-5 fork exists to get the AUR *out* of the trust
path when nothing better exists. A distro-signed `extra` package is *already* out
of the AUR trust path, *and* signed by Arch developers, *and* auto-updating —
strictly better than a self-attested fork. Forking something the distro already
builds and signs is pure make-work. (Contrast Odin: no official Arch package
exists, so rung 5 is genuinely the only option — that's what earns the fork.)

### Worked example — `godlike-artix`, 2026-08-13

`git-delta`, `azure-cli`, and `rbw` were all self-built AUR packages that had
graduated to `extra` (yay flagged all three under "Packages not in AUR"). Enabling
the overlay and reclaiming took them from foreign/self-built to Arch-signed:

- `git-delta` 0.19.2-1 (foreign) → `extra` 0.19.2-2
- `azure-cli` 2.85.0-1 (foreign) → `extra` 2.87.0-1
- `rbw` 1.15.0-2 (foreign) → `extra` 1.15.0-2 (identical version — needed the
  explicit `-S extra/rbw` from step 5)

The follow-up `pacman -Si` scan over the whole foreign list confirmed these three
were the *only* reclaimable packages; the other 35 are genuinely AUR-only
(`brave-origin-bin`, `discord-latest-bin`, the `-git`/`-bin` builds, `spotify`,
`zoom`, …) and correctly stay on their current rungs. Note `rofi-rbw-git` (the
rofi frontend to rbw) is one of those — AUR-only, not in `extra`, leave it.

**`nomad-artix` still needs this pass.** Run the procedure above on the laptop;
its foreign list may differ, so re-run the `pacman -Si` scan there rather than
assuming the same three. This is machine-local — `/etc/pacman.conf` is not in the
dotfiles repo, so `git pull` will not carry the overlay change across.

## When to just... not install it

The "AUR is sus" period surfaced dead weight on both machines. Some tools sit
in `pacman -Qm` because they were installed for a one-off task and never used
again — the AUR lockdown made "pending upgrade forever" the visible signal.
Before reaching for any of rungs 1-6 for a re-install, ask: **when did you
last actually use this?** If the answer is "I don't remember," the right rung
is "leave it uninstalled." The semgrep case (2026-08-11) is the worked
example: 34 packages removed for something the user never actively used.

## References

- `docs/2026-08-10-aur-supply-chain-assessment.md` — the primary-source assessment of the 2026 waves
- `aur-malware-check` in this repo — the audit script
- `~/.claude/CLAUDE.md` § "Odin — install from the private `odin-git-local` fork" — the rung-5 worked example
- `docs/claude-code-aur-to-native-migration.md` — rung-2 worked example
- `docs/codex-aur-to-native-migration.md` — rung-2 worked example
- `docs/brave-to-brave-origin-migration.md` — rung-2 worked example
