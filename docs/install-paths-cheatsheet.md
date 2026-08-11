# Install-paths cheat sheet — where to get software when AUR is sus

**Date:** 2026-08-11 · **Applies to:** both machines (Artix, `godlike-artix` desktop + `nomad-artix` laptop) · **Related:** `docs/2026-08-10-aur-supply-chain-assessment.md` (the "why AUR is under scrutiny" primary-source assessment) · `aur-malware-check` (the audit script) · `docs/claude-code-aur-to-native-migration.md`, `docs/codex-aur-to-native-migration.md`, `docs/brave-to-brave-origin-migration.md` (worked examples of AUR → native migrations)

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
| 1. Repo | Artix packagers curate + sign; pacman verifies. Highest trust surface available. | `pacman -Syu` | `pacman -R` | Anything the distro packages. **First check every time.** |
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
