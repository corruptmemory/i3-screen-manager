# The AUR Supply-Chain Situation: A Decision-Grade Assessment

**Prepared:** 2026-08-10 · **Window:** Feb–Aug 2026 (with 2018/2025 context)
**Purpose:** Inform the decision of whether to keep running Arch-based distros given AUR risk.

**Method — multi-lane, triangulated, primary-source-first.** Findings were gathered
across independent lanes (live web search + fetch; a browser lane via `marksnip`
pulling mailing-list threads verbatim; Perplexity; an OpenAI Codex lane querying
the `gitlab.archlinux.org` API directly; and a Google-grounded `agy`/Antigravity
lane). Every load-bearing claim below is backed by a **primary source** (official
Arch news, the Arch mailing lists, or the `aurweb` GitLab repo) or a **reputable
security vendor** (Truesec, Sonatype, BleepingComputer, The Hacker News, Phoronix).
The `agy` lane produced confident but partly **fabricated** specifics (invented tool
names, a wrong "2FA in-dev" claim); nothing from it is used unless a primary source
confirmed it. Where sources disagree (e.g. package counts), the disagreement is
shown, not averaged.

---

## Bottom line up front

- **This is real, large, and recent — not FUD.** In a ~10-week span the AUR was hit
  by three escalating waves of automated supply-chain attacks. The largest (June
  2026, "Atomic Arch") poisoned **~400 to ~1,500 packages** with a Rust infostealer
  and an optional root-only eBPF rootkit. Arch's own DevOps team took the drastic
  step of **disabling package adoption (2026-07-30), then all git pushes
  (2026-08-01)**. As of this writing the AUR is effectively in an **emergency-freeze
  posture**, not normal operation, with no official all-clear posted.
- **But the blast radius is bounded and well-understood.** The official Arch repos
  (`[core]`/`[extra]`/`[multilib]`) and Arch's signing keys were **never touched**.
  Every incident lived entirely inside the AUR's *user-contributed, run-arbitrary-
  `PKGBUILD`* model. The victims are people who build **orphaned/recently-adopted AUR
  packages without reading the diff and without a build sandbox**.
- **Trend: increasing and adaptive** through July, now met with the **first real
  structural fix in years** (PM-reviewed adoption, merged 2026-07-31). Whether the
  trend bends depends on whether that fix plus disposable-email blocking actually
  raise attacker cost. Too early to call it contained.
- **The core risk is STRUCTURAL, mitigations are OPERATIONAL.** Arbitrary build-time
  code execution and low-friction orphan adoption are design properties, not bugs.
  They can be *fenced* (sandboxing, adoption gates, quarantine) but not *removed*
  without changing what the AUR is.
- **Recommendation (detailed at the end):** Keeping an Arch-based distro is
  **defensible** — *if* you treat the AUR as hostile-by-default: prefer `[extra]`,
  build AUR packages in a **clean chroot** (`devtools`/`aurutils`), **read every
  `PKGBUILD` and `.install` diff**, never blindly `yay -Syu`, and be especially wary
  of **recently-adopted orphans**. Your own `aur-malware-check` is a reasonable
  backstop, not a substitute for the above. If you cannot commit to that hygiene on a
  machine that holds real credentials, disable the AUR on that machine.

---

## 1. History — a dated timeline

### Context: this attack pattern is old
- **2018-07** — Malware found in the AUR: an attacker (`xeactor`) adopted the
  orphaned `acroread` (and touched `balz`, `minergate`), inserting a `curl`-style
  downloader that exfiltrated host info via a Pastebin-like service. Arch reverted and
  suspended the account. Three packages, not a repo-wide event — but the **exact**
  "inherit trust by adopting an orphan" pattern the 2026 waves industrialized.
  [BleepingComputer, 2018](https://www.bleepingcomputer.com/news/security/malware-found-in-arch-linux-aur-package-repository/) ·
  [The Hacker News, 2018](https://thehackernews.com/2018/07/arch-linux-aur-malware.html)

### July 2025 — CHAOS RAT (browser-utility spoofing)
- **2025-07-16 → 07-18** — Three malicious packages uploaded by one user
  (`danikpapas`): **`librewolf-fix-bin`, `firefox-patch-bin`, `zen-browser-patched-bin`**.
  Their `PKGBUILD` pulled a script from a GitHub repo identified as a **CHAOS RAT**
  (Go remote-access trojan). Caught by community inspection; packages deleted within
  ~2 days.
- **Primary (verbatim), aur-general SECURITY thread:**
  > "On the 16th of July, at around 8pm UTC+2, a malicious AUR package was uploaded…
  > These packages were installing a script coming from the same GitHub repository
  > that was identified as a Remote Access Trojan (RAT)… As of today, 18th of July…
  > the offending packages have been deleted from the AUR."
  [aur-general thread](https://lists.archlinux.org/archives/list/aur-general@lists.archlinux.org/thread/7EZTJXLIAQLARQNTMEW2HBWZYE626IFJ/) ·
  [BleepingComputer, 2025-07](https://www.bleepingcomputer.com/news/security/arch-linux-pulls-aur-packages-that-installed-chaos-rat-malware/)

### May 16–24 2026 — the "Shai-Hulud"-linked precursor (crypto-wallet targeting)
- **May 16–17:** three orphaned packages **adopted by single-package burner accounts
  using `@onionmail.org`** addresses; the first commit on each ran `npm install
  python-utils`, whose "JavaScript preinstall" file was actually a **UPX-packed x86-64
  ELF**. **May 24:** Arch PM **Hyacinthe Cartiaux** found a related `crypto-javascript`
  variant in `gnome-vfs`, `expressvpn`, `atomicwallet-bin`, `exodus-bin`. Staff banned
  the accounts and reverted ~7 current + 3 older wallet packages. It **targeted
  crypto-wallet packages** specifically.
- **Primary (verbatim), Hyacinthe Cartiaux (Arch Package Maintainer), May 24:**
  > "This is a not so kind remember to not trust blindly AUR packages and to verify
  > before building/installing updates…"
- **Primary (verbatim), aur-requests, reply by maintainer "Muflone":**
  > "The following packages have been reverted… and the owner accounts have been
  > banned: mod_python (deleted), gnome-vfs, multibootusb, nss-hg, expressvpn,
  > atomicwallet-bin…, exodus-bin…. Additionally the following packages were removed
  > as they appeared compromised in the past months: tonkeeper-wallet-bin,
  > phantom-wallet-bin, solflare-wallet-bin."
  [aur-requests thread](https://lists.archlinux.org/archives/list/aur-requests@lists.archlinux.org/message/K6IBSXLNYFMIAROGWJQUTJVQSJ6RAF3H/)
- *Significance:* this was the **dress rehearsal** — same adoption vector, same burner-
  account tradecraft, small scale — a month before the mass campaign.

### June 11–12 2026 — "Atomic Arch," the mass campaign
- Attackers **automated adoption of orphaned packages at scale** and pushed poisoned
  `PKGBUILD`/`.install` files that ran malicious **npm/Bun dependencies**:
  **`atomic-lockfile`** (`@1.4.2`, ~134 weekly downloads before removal), then
  **`js-digest`** and **`lockfile-js`** in a second wave. The install line paired the
  malware with legit-looking decoys (`npm install atomic-lockfile minimist chalk`).
  Entry-point examples: **`alvr`**, **`premake-git`**.
- **Payload:** a **Rust infostealer** harvesting SSH private keys, shell history,
  browser cookies/sessions, and tokens for GitHub, npm, cloud providers, **HashiCorp
  Vault**, OpenAI, and Slack/Discord/Teams/Telegram; plus an **optional eBPF rootkit**
  (only with root) hooking `getdents64()` and using pinned BPF maps
  (`hidden_pids`/`hidden_names`/`hidden_inodes`) to hide processes and block debuggers.
- **Detection/attribution:** flagged by security vendors and community trackers; the
  `deps` payload was reverse-engineered by independent researcher **"Whanos."**
  Sonatype tracks it as **`Sonatype-2026-003775` (CVSS 8.7)** and the second wave as
  **`Sonatype-2026-003808`**. **No CVE** was assigned.
- **Official response — Arch news, 2026-06-12 (verbatim):**
  > "We are actively working to track down existing malicious commits and attempting
  > to prevent additional malicious commits from being pushed… We continue to
  > encourage all users of AUR packages to review *all* PKGBUILD and install script
  > changes when updating, especially during this time."
  Arch temporarily restricted **new account creation, package pushes, and package
  adoption/creation** during response.
  [Arch news, 2026-06-12](https://archlinux.org/news/active-aur-malicious-packages-incident/) ·
  [Truesec, 2026-06-16](https://www.truesec.com/hub/blog/supply-chain-attack-compromising-arch-linux-aur-packages-infostealer-rootkit) ·
  [Sonatype](https://www.sonatype.com/blog/atomic-arch-npm-campaign-adds-malicious-dependency) ·
  [The Hacker News, 2026-06](https://thehackernews.com/2026/06/over-400-arch-linux-aur-packages.html) ·
  [BleepingComputer, 2026-06](https://www.bleepingcomputer.com/news/security/over-400-arch-linux-packages-compromised-to-push-rootkit-infostealer/)
- **Contradiction, preserved:** package counts differ by source. The Hacker News
  cites **~408** on the initial catalogued master list; **Sonatype/Truesec estimate
  "up to ~1,500 across multiple waves,"** explicitly hedged as still-changing. Read
  **~400 confirmed, up to ~1,500 plausible** — do not treat 1,500 as hard.

### June 12 – July 25 — cleanup, hardening, and an early relapse
- **June 12–13:** responders reverted/force-pushed affected repos and banned accounts.
  **Jonathan Steel (Arch):** *"I believe that at the moment we deleted all the
  malicious commits we know of"* — immediately caveating that the published list held
  *"many (but not all)"* affected packages. Cleanup was substantial but **reactive and
  admittedly incomplete**.
- **June 15:** new AUR account registration disabled during cleanup.
- **July 13:** registration reopened **with hardening** — disposable-email rejection,
  mandatory email verification (24-hour token), email-change lock during cooldown
  (`aurweb` `!903`/`!906`).
- **July 25:** a mailing-list "new spam wave" flagged **≥12** freshly-adopted packages
  with malicious commits — proof the June cleanup was **not** a durable fix.

### July 29 – Aug 1 2026 — the relapse and the freeze
- A fresh wave began **2026-07-29** via **`openconnect-sso`**. Reported spread is
  **contested:** a **primary-sourced floor of ~89–116 named packages** across
  July 29–Aug 1 aur-general reports (e.g. `boringssl-git`, `icloudpd`,
  `windscribe-cli-v2-bin`, `stirling-pdf-desktop-bin`, `pgadmin4-server`), while the
  widely-quoted **"200+" figure is Reddit-tracker-derived and was *not* independently
  verified** (BleepingComputer said as much on July 31). Some rode **hijacked
  maintainer accounts**, not only orphan adoption. This wave injected **native ELF
  binaries** (e.g. `hasher`, `linter`, `parser`) directly, did VM/sandbox/debugger
  checks, established **systemd-user persistence**, and used **Tor-disguised** staging.
  Whether it is literally "Atomic Arch wave 2/3" is **not established** — better read
  as a *related but operationally distinct* continuation.
- **Primary (verbatim), former `openconnect-sso` maintainer, 2026-07-29:**
  > "The openconnect-sso AUR package has been compromised with a malware binary." …
  > "I disowned the package after I stopped using it completely, so I no longer have
  > access to the repo." — the stewardship gap, in one quote.
- **Official response — aur-general, Robin Candau (Antiz):**
  > "Due to the current influx of malicious package adoptions and follow-up commits
  > made via the AUR, package adoption is currently disabled…" **(2026-07-30)**
  Then, **2026-08-01:** *"We have now disabled pushes altogether as well for the
  moment, while we handle the situation."*
  [aur-general "adoption disabled"](https://lists.archlinux.org/archives/list/aur-general@lists.archlinux.org/message/DRDEU3JUSC72CB265XHXPFA3DFSLXPBP/) ·
  [aur-general follow-up](https://lists.archlinux.org/archives/list/aur-general@lists.archlinux.org/message/YPJ3FQYJTJXXY3RUXCYLMHUKHLIUNVFF/) ·
  [BleepingComputer, 2026-07-31](https://www.bleepingcomputer.com/news/security/arch-linux-disables-aur-package-adoption-to-stop-malware-flood/) ·
  [Phoronix](https://www.phoronix.com/news/Arch-Linux-AUR-Adoptions-Halted)

---

## 2. Current state (as of 2026-08-10)

- **Trend: increasing then forcibly interrupted.** Three escalating waves in ~10
  weeks (May precursor → June mass campaign → late-July relapse that specifically
  defeated the June defenses) is an *escalating, adaptive* pattern. The July freeze
  stopped the bleeding by turning the vector off, not by out-defending it.
- **Posture: emergency freeze, not steady-state.** Adoption and pushes were disabled
  July 30; the merged fixes (below) are how Arch is trying to reopen safely. Treat any
  "it's over" claim as premature.
- **Actual risk vs. hype:**
  - **Overstated:** "all Arch systems are compromised," "the distro is backdoored,"
    "reinstall immediately no matter what," "1,500 packages installed rootkits." The
    official repos and signing infrastructure were untouched; risk is confined to AUR
    builds you actually ran; and "~1,500 packages" means **~1,500 altered recipes
    calling a handful of shared malicious npm packages**, not 1,500 distinct payloads
    or 1,500 infected machines. The eBPF rootkit is "capable," not universally
    deployed — it needed **root** and successful second-stage execution.
  - **The balanced insider read — Jguer (yay maintainer), 2026-06-17 (verbatim):**
    > "It is not the AURpocalypse. The AUR is working within its established trust
    > model." *(True — and the flip side is that that model deliberately puts review
    > on you.)*
  - **Real and high:** if you built/updated an affected AUR package during a malicious
    window **without a sandbox**, assume **user-scope credential theft** (SSH keys,
    tokens, browser sessions) and — only if you built as root or the payload escalated
    — possible kernel-level hiding. Truesec's guidance: treat anything AUR-built or
    -updated **since 2026-06-11 as suspect**, rotate credentials, and consider reinstall.
- **Quantified reality:** **~117,161** packages exist in the AUR (live count). The
  campaigns touched **hundreds** confirmed (≈400 in June; ~116 named in July, ~200
  alleged/unverified) — well under **~1.3%** of the repo even at the high estimate,
  and package-name fractions are **not** infection rates — but heavily weighted toward
  **orphans**, and
  time-to-detection ranged from **hours** (popular packages, caught by build errors/
  forum reports) to **days** (obscure orphans, caught by vendor scans). The danger is
  not breadth; it is that **one poisoned package you build unsandboxed is enough.**

---

## 3. Mitigations — a shipped-vs-proposed ledger

This is where secondary AI summaries are least reliable, so every row below is checked
against the **`aurweb` GitLab repo** directly (merge state + date).

### A. Arch / `aurweb` server-side — what actually SHIPPED
| Change | State | Date | Efficacy |
|---|---|---|---|
| **Require Package-Maintainer review for adoption** ([`!914`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/914)) | **merged** | 2026-07-31 | **High / structural.** Unprivileged orphan adoption now files a *pending request* (web+SSH), one per package base, auto-rejected when idle. Directly closes the mass-adoption vector. The single most important fix. |
| **Block disposable-email registration** ([`!906`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/906)) | **merged** | 2026-06-18 | **Moderate.** Kills the `@onionmail.org`-style burner path used in May/June. Attackers can migrate to costlier email sources. |
| **Email verification, blocks non-readonly SSH until verified** ([`!903`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/903)) | **merged** | 2026-07-13 | **Moderate.** Raises account-creation cost; doesn't stop a determined actor with real inboxes. |
| **Canonicalize `+tag`/dot email aliases** ([`!912`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/912), [`!913`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/913)) | **merged** | 2026-07-26 / 08-01 | **Low-moderate.** Stops one-inbox→many-accounts; incremental. |
| **Disable adoption, then all pushes (incident switch)** | **live op** | 2026-07-30 | **High short-term / poor long-term.** Stops everything, including legitimate maintenance. This is a tourniquet, and `!914` is the intended replacement. |

### B. Arch / `aurweb` — PROPOSED, not (yet) shipped
| Idea | State | Efficacy if done |
|---|---|---|
| **2FA / TOTP for aurweb accounts** ([`#514`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/514)) | **open since 2024-08-22** | Low against *this* threat — attackers used **fresh** accounts, not account takeover. 2FA protects existing maintainers, not the adoption vector. (Note: `accounts.archlinux.org` staff SSO has 2FA; **aurweb itself does not**.) |
| **"Report as malicious" button** ([`#558`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/558)) | open | Moderate. Speeds reporting vs. flooding the mailing list. |
| **Quarantine package** (moderator button, deny `git clone`, signal helpers) ([`#560`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/560)) | open | Moderate-high for response speed; lets more staff act on reports. |
| **Lock adoption on high-value/formerly-official orphans** ([`#556`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/556)) | open | High for the exact packages attackers prize. |
| **Reject spoofed commit emails** ([`#555`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/555) / [`!902`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/902)) | open | Moderate; audit-trail hygiene. |
| **Surface young/suspended accounts ("beginner shield", strike-through)** ([`!901`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/901)) | open | Moderate; helps humans spot a 3-day-old adopter. |
| **Expose adoption timestamp so helpers can warn** ([`!904`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/904)) | **closed unmerged** | Would have let `paru` flag recent adoptions on first install. Currently not landed. |
| Server-side static analysis / signed commits / mandatory package signing | discussed, **no implementation** | Signing gives identity, not safety (attacker signs their own malware); static analysis is an arms race. |

### C. Client-side (AUR helpers) — the user's real defenses
| Control | Status | Efficacy |
|---|---|---|
| **Clean-chroot builds** (`devtools` `makechrootpkg`, `aurutils`) | available now | **Very high.** Builds in a container with **no access to `$HOME`** — `~/.ssh`, `~/.aws`, browser profiles are simply absent. The most effective single control. |
| **`bwrap`/sandboxed build** (`rua`, or `paru`/`makepkg` under bubblewrap) | available now | **High.** Restricts FS/network during `build()`. |
| **Mandatory `PKGBUILD`/`.install` diff review** (`paru --review`, `yay` diff prompt) | available now | **Moderate.** Essential and it *works when done* — but subject to **alert fatigue** on mass updates. The June/July payloads were visible in the diff. |
| **Pin to well-maintained packages, avoid fresh orphans** | behavioral | **Moderate-high.** ~all victims were orphaned/recently-adopted. |
| **`yay` v13.0.1 risk signals** (last-modified age in search/upgrade; Lua policy hooks) — shipped 2026-06-19 | available now | **Low-moderate.** Surfaces "recently changed = re-review" and gives automation hooks; a timestamp is a signal, not a trust proof. |

### D. Community detection
| Tool | Efficacy |
|---|---|
| **Consolidated denylists** (e.g. the [`md.archlinux.org` note](https://md.archlinux.org/s/SxbqukK6IA)) + local scanners like your **`aur-malware-check`** (fork of [`lenucksi/aur-malware-check`](https://github.com/lenucksi/aur-malware-check)) | **Moderate, reactive.** Great for "am I already exposed?" after the fact; cannot prevent a novel payload. A backstop, not a gate. |

---

## 4. Prospectus — structural vs. fixable

### Structural (cannot be removed without changing what the AUR is)
1. **Arbitrary build-time code execution.** `PKGBUILD` *is* a bash script; `makepkg`
   runs it. Any unvetted, unsandboxed build is intrinsically dangerous. This is the
   AUR's defining property, not a defect.
2. **Uncurated crowdsourcing.** Anyone can publish; there is no pre-publication review
   by design. The AUR will never carry `[core]`-grade assurance.
3. **The orphan problem.** Software loses maintainers constantly. *Any* low-friction
   adoption model for abandoned-but-installed packages is a standing target — this is
   the exact seam all three 2026 waves used.

### Fixable (operational, and Arch has started)
1. **Adoption governance — largely fixed as of `!914`** (PM-review-gated, rate-limited,
   expiring). This is the decisive change; if it holds, the mass-adoption vector is
   materially harder.
2. **Account-creation cost** — improved (`!903`/`!906`/`!912`); ongoing arms race.
3. **Response tooling** — quarantine (`#560`) and report button (`#558`) would cut
   time-to-takedown; still open.
4. **Client default posture** — the highest-leverage *unfixed* item: mainstream
   helpers (`yay`, `paru`) still build **unsandboxed by default**. If `yay`/`paru`
   shipped chroot/`bwrap` sandboxing **on by default**, the *impact* of a poisoned
   build would collapse even when a malicious package slips through. That is the change
   that would most reduce real-world harm, and it is not on Arch's server-side roadmap
   — it's on the helpers.

**Net:** the AUR will **remain structurally exploitable** (you can always be tricked
into building malware), but the **mass-scale, automated** version that defined summer
2026 is being fenced off. Expect **fewer 1,500-package events** and a shift back toward
**targeted, lower-volume** poisonings — which sandboxing defeats regardless.

---

## Recommendation for your decision

**Keeping Arch-based distros is defensible.** The events were serious but confined to a
part of the system you control how you use. The deciding question is not "is the AUR
safe" (it structurally is not) but "will I use it with discipline."

**Keep Arch, and treat the AUR as hostile-by-default:**
1. **Prefer `[extra]`/official repos**; reach for the AUR only when there's no
   alternative.
2. **Build in a clean chroot** (`aurutils` + `devtools`, or `makechrootpkg`) — this
   single step neutralizes the credential-theft payloads by denying `$HOME`.
3. **Read every `PKGBUILD` and `.install` diff. Never blindly `yay -Syu`.** The 2026
   payloads were visible in the diff.
4. **Be paranoid about recently-adopted orphans** — check the maintainer and adoption
   recency before building.
5. **Keep `aur-malware-check` as a backstop**, and rotate credentials if you ever find
   exposure.

**Disable the AUR** on any machine that (a) holds production/enterprise credentials or
(b) where you won't reliably do steps 2–4. On a credentialed workstation without that
hygiene, the expected loss from one bad build outweighs the convenience.

If you *don't* want to run that discipline at all, the honest alternative isn't "a
safer Arch" — it's a distro whose extra-package model is curated/sandboxed (e.g.
Fedora + Flatpak, or openSUSE), accepting the loss of the AUR's breadth. That loss is
real; so is the risk you'd be trading away.

---

## Confidence and gaps
- **High confidence:** the timeline, the official freeze actions, the shipped `aurweb`
  fixes, payload behavior, and that official repos were untouched — all primary- or
  vendor-sourced.
- **Medium confidence:** exact package counts — the June 400-vs-1,500 span and the
  July ~116-named-vs-~200-alleged span, both preserved rather than averaged. (The
  freeze sequence is now **high** confidence: adoption disabled **July 30**, all pushes
  **Aug 1**, per two primary messages.)
- **Open gaps:** whether the AUR has *fully reopened* pushes/adoption by 2026-08-10
  (still freeze-adjacent at last primary post); whether `yay`/`paru` will adopt
  default sandboxing; and any post-freeze all-clear from Arch, which had not been
  posted at time of writing.

## Source ledger
**Primary (Arch):** [Arch news 06-12](https://archlinux.org/news/active-aur-malicious-packages-incident/) ·
[aur-general adoption-disabled 07-30](https://lists.archlinux.org/archives/list/aur-general@lists.archlinux.org/message/DRDEU3JUSC72CB265XHXPFA3DFSLXPBP/) ·
[pushes-disabled follow-up](https://lists.archlinux.org/archives/list/aur-general@lists.archlinux.org/message/YPJ3FQYJTJXXY3RUXCYLMHUKHLIUNVFF/) ·
[CHAOS RAT SECURITY thread 2025](https://lists.archlinux.org/archives/list/aur-general@lists.archlinux.org/thread/7EZTJXLIAQLARQNTMEW2HBWZYE626IFJ/) ·
[May precursor / aur-requests](https://lists.archlinux.org/archives/list/aur-requests@lists.archlinux.org/message/K6IBSXLNYFMIAROGWJQUTJVQSJ6RAF3H/) ·
aurweb GitLab: [`!914`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/914) [`!903`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/903) [`!906`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/906) [`!912`](https://gitlab.archlinux.org/archlinux/aurweb/-/merge_requests/912) [`#514`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/514) [`#558`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/558) [`#560`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/560) [`#556`](https://gitlab.archlinux.org/archlinux/aurweb/-/work_items/556)
**Trusted third-party:** [Truesec](https://www.truesec.com/hub/blog/supply-chain-attack-compromising-arch-linux-aur-packages-infostealer-rootkit) ·
[Sonatype](https://www.sonatype.com/blog/atomic-arch-npm-campaign-adds-malicious-dependency) ·
[The Hacker News](https://thehackernews.com/2026/06/over-400-arch-linux-aur-packages.html) ·
[BleepingComputer 06](https://www.bleepingcomputer.com/news/security/over-400-arch-linux-packages-compromised-to-push-rootkit-infostealer/) ·
[BleepingComputer 07](https://www.bleepingcomputer.com/news/security/arch-linux-disables-aur-package-adoption-to-stop-malware-flood/) ·
[BleepingComputer 2025 CHAOS RAT](https://www.bleepingcomputer.com/news/security/arch-linux-pulls-aur-packages-that-installed-chaos-rat-malware/) ·
[Phoronix](https://www.phoronix.com/news/Arch-Linux-AUR-Adoptions-Halted) ·
[StepSecurity](https://www.stepsecurity.io/blog/400-aur-packages-hijacked-atomic-arch-campaign)
