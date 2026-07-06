# XLibre versioning & Artix packaging — why `world` stays on `25.0.0.x`

*2026-07-05. Reference note for both machines (godlike-artix, nomad-artix), which
run XLibre as their X11 server on Artix.*

## The question

Upstream XLibre's current "stable" is **`25.1.8`**, and `xlibre.net`'s homepage
labels `25.1.x` **stable** / `25.2.0` **new beta**. Yet Artix `world` still ships
**`xlibre-xserver 25.0.0.23-1`**. Is something wrong / a broken pin / a held
package?

**No.** Nothing on the machine is wrong (fully synced, no `IgnorePkg`). `25.0.0.x`
and `25.1.x` are **parallel branches**, and Artix deliberately keeps stable `world`
on the conservative `25.0.0.x` line while the *entire* `25.1.x` line is staged in
`world-gremlins` (Artix's `[testing]` equivalent), pending a normal soak-and-promote.

## Version scheme — parallel branches, not a linear progression

- `25` = year-based major (the 2025 fork baseline).
- **`25.0.0.N`** (4-component) — the original **conservative maintenance line**,
  upstream branch `release/25.0`; `N` is a monotonic patch counter. **Still actively
  maintained** (latest `25.0.0.24`, 2026-06-05).
- **`25.1.M`** (3-component semver) — the newer **feature line**, `release/25.1`.
  Began as a **beta** (`25.1.0`, 2025-12-21), **declared stable at `25.1.6`**
  (2026-06-05, XLibre's 1st anniversary). Latest `25.1.8` (2026-06-21).
- **`25.2.0`** (2026-06-21) — the next feature line is already open ("new beta").
- The lines advance **in parallel**; security fixes are cherry-picked into **both**
  (e.g. `25.0.0.24` and `25.1.6` shipped the same hardening set on the same day).
  `25.1.8 > 25.0.0.23` numerically, but it's a *different branch*, not a later
  point release on the same line.
- The specific `25.0.0.23` Artix ships is a **git tag only** (2026-04-28) — not a
  formal GitHub *release* (the releases list jumps `25.0.0.22 → 25.0.0.24`). Artix
  cut its stable package straight from that intermediate tag.

### Verified release dates (GitHub API `published_at` / tags)

| Version | Date | Line / status |
|---|---|---|
| `25.1.0` | 2025-12-21 | 25.1 first **beta** |
| `25.0.0.23` | 2026-04-28 | 25.0 maintenance (tag; Artix's stable) |
| `25.0.0.24` | 2026-06-05 | 25.0 maintenance — **last of the line so far** |
| `25.1.6` | 2026-06-05 | 25.1 **declared stable** |
| `25.1.7` | 2026-06-16 | 25.1 |
| `25.1.8` | 2026-06-21 | 25.1 latest |
| `25.2.0` | 2026-06-21 | next feature line ("new beta") |

## ABI reality (and a cautionary note)

The **shipped Artix packages provide identical driver ABIs across both lines** —
verified from the repo DBs:

```
world           xlibre-xserver-25.0.0.23-1 : X-ABI-VIDEODRV_VERSION=28.0  XINPUT=26.0  EXTENSION=11.0
world-gremlins  xlibre-xserver-25.1.8-1    : X-ABI-VIDEODRV_VERSION=28.0  XINPUT=26.0  EXTENSION=11.0
```

Because the ABI is unchanged, a driver built for one line loads on the other —
which is why `xlibre-video-amdgpu 25.1.1` runs fine against the `25.0.0.23` server.

⚠️ **Cautionary note (verify the artifact, not the recipe):** upstream 25.1 source
carries an *optional* `legacy_nvidia_padding` build flag that **would** bump video
ABI to `28.1`. Reading the PKGBUILD conditional, it's tempting to conclude Artix's
25.1.8 build flips the ABI and forces an atomic driver rebuild. **It doesn't** — the
*built* `world-gremlins` package still provides `28.0`, i.e. the flag isn't enabled
in Artix's build. Always confirm against the compiled package's `%PROVIDES%`, not
the recipe.

## Why `world` stays on `25.0.0.23` (deliberate, not lag)

- `world` = `25.0.0.23-1`, built **2026-05-25**, **not** flagged out-of-date.
- `world-gremlins` = **`25.1.8-1`**, built **2026-06-21 — the same day upstream
  released it.** So it's *packaged and staged*, not lagging in the build sense.
- The Artix packaging git (`gitea.artixlinux.org/packages/xlibre-xserver`) shows the
  policy explicitly: the last stable promotion was
  `[world-gremlins] -> [world] 'xlibre-xserver-25.0.0.23-1' move`, while **every**
  `25.1.x` build lands in gremlins only and is **never** moved to `world`. The whole
  xlibre set (server + all `xlibre-video-*` / `xlibre-input-*`) is currently flagged
  **`Move`** on `checkupdates.artixlinux.org`.
- Upstream only **declared 25.1 stable on 2026-06-05**, and `25.1.7`/`25.1.8`/`25.2.0`
  all landed in a two-week burst (Jun 16–21). Artix is letting it soak. There is real
  precedent for caution: a Dec-2025 amdgpu `undefined symbol: glamor_egl_create_*`
  breakage during the `25.1.0` beta, and this machine's own **`25.0.0.21` vblank
  lockup (2026-02-22)** documented in the project `CLAUDE.md`.
- Maintainer is `artist@artixlinux.org` (also an upstream contributor,
  `artist4artixlinux`), packaging same-day — **not a bandwidth problem.**

**Conclusion:** deliberate stable-branch pin + a normal gremlins→world soak. Not a
build failure, not an out-of-date flag, not project-politics, not abandonment.

## Security caveat (the one actionable gap)

`world`'s `25.0.0.23` (tag 2026-04-28) **predates the 2026-06-05 hardening batch**
(the byte-swap / padding-leak fixes, X.Org CVE-2026-50256…50263 class). Artix **did
not** cut a `25.0.0.24` for `world` — the security-fixed successor exists only in
gremlins as `25.1.6+`. So the current stable `world` X server lacks the June-5 fixes
until Artix promotes `25.1.x`.

## How to check current state

```bash
pacman -Qi xlibre-xserver                                   # installed version + build date
curl -s https://mirror1.artixlinux.org/repos/world/os/x86_64/          | grep -o 'xlibre-xserver-25[^"<]*zst'   # stable
curl -s https://mirror1.artixlinux.org/repos/world-gremlins/os/x86_64/ | grep -o 'xlibre-xserver-25[^"<]*zst'   # testing
# pending promotions (packages flagged "Move"):
curl -s https://checkupdates.artixlinux.org | grep -i xlibre
```

## Watch list

- [ ] Watch for the `world-gremlins → world` promotion of `xlibre-xserver 25.1.x`.
  When it lands, a normal `pacman -Syu` brings the whole xlibre set across together.
- [ ] If the June-5 security fixes matter *before* then: enable `[world-gremlins]`
  and update the **entire** xlibre stack **atomically** (server + all
  `xlibre-video-*` / `xlibre-input-*` in one transaction) — never a partial update.
  Standard testing-repo caveats. Dicier on the NVIDIA-hybrid **nomad-artix** laptop
  than on the pure-AMD **godlike-artix** desktop.
- [ ] Do **not** sideload from the AUR (June-2026 malware), and beware the
  `nettle`-soname-skew black-screen trap that bites when the server and its deps
  arrive on different update cadences.

## Sources

- XLibre releases/tags (dates): <https://github.com/X11Libre/xserver/releases> ·
  wiki "25.1 Changes"; anniversary/stable announcement:
  [org discussion #513](https://github.com/orgs/X11Libre/discussions/513).
- Artix packaging git: <https://gitea.artixlinux.org/packages/xlibre-xserver>
  (per-repo add/move commit trail).
- Artix mirror listings + `checkupdates.artixlinux.org` (repo state, "Move" flags).
- Local: `pacman -Qi xlibre-xserver`; repo-DB `%PROVIDES%` on both machines.

---

*Provenance: cross-verified across multiple research agents; the ABI point above
specifically corrects an over-read (PKGBUILD conditional ≠ shipped `%PROVIDES%`) by
checking the built package. The bake-off methodology itself is recorded in Open Brain,
not here.*
