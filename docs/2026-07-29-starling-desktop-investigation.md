# Starling desktop — investigation + X11/Wayland architecture lessons (2026-07-29)

A code-level teardown of **Starling** (`starling.build`, `github.com/starling-build/starling`),
the AI-written Linux desktop, prompted by its headline claim of **native, baked-in
X11 *and* Wayland support "at once."** The investigation answered "how is the X
support actually baked?" from the source (both repos cloned locally), then widened
into a broader, evidence-checked audit of the X11-vs-Wayland "structural vs
folklore" question — including a **verified finding about XLibre** that belongs
next to `docs/2026-07-05-xlibre-versioning-artix-packaging.md`.

Method throughout: **the code tells the truth.** Every claim below is anchored to a
`file:line` you can re-check. Repos cloned to `~/projects/starling` and
`~/projects/starling-engine` (shallow; HEAD `1401708` = `release: 0.2.1`,
2026-07-29). XLibre cloned to scratchpad for the tear-free check.

---

## TL;DR

1. **Starling's X11 is a bespoke, in-process C++ X server — NOT Xwayland.** My first
   prediction ("cute Xwayland repackaging") was wrong; the code refuted it. It's a
   ~5,200-line hand-written X server compiled into the *same binary* as the Wayland
   compositor, sharing one GPU device and one epoll loop. Both protocol servers feed
   window buffers into **Flutter's texture registry**, which composites everything —
   that is *why* they ported Flutter.
2. **It's a curated, GPU-first *subset*, with real Xwayland as the escape hatch.**
   First-class for the modern DRI3/Present path (Chrome/Zoom/GLX); a best-effort
   shadow path for raster (Qt/GTK); and genuinely awkward clients (WeChat) still get
   **rootful Xwayland**. "Native both" for the 90%, shim for the tail.
3. **Provenance: reconstructed, not lifted.** The "grabbed an existing X server"
   hypothesis is falsified (zero X.Org tokens, fastidious NOTICE attributes it to
   no-one = first-party, and the repo grows it *gap-by-gap* per client). What it
   "came from" is the model's training exposure to Xorg/Xwayland: **derived
   knowledge, not derived code.**
4. **Five languages, a lattice of bridges — and it runs the *macOS* Flutter embedder
   on Linux.** Swift is *inherited toll* from reusing Flutter's mac embedder, not a
   merit choice. For a single-language, own-the-stack sensibility, Swift **does not
   pay its freight** here.
5. **It is a *born* complexity-soup**, not accreted scar tissue — maximal debt with
   zero equity, mostly *accidental* (Brooks) not essential. The "scaffold, then
   rewrite native" defense is already contradicted by the repo's own "do not touch"
   quarantine directives.
6. **The broader X11/Wayland audit:** several marquee "X *structurally* can't,
   therefore Wayland" claims are **folklore**. Verified against code:
   - **Tear-free / atomic / VRR** → XLibre ships **TearFree by default** + optional
     atomic modesetting + VariableRefresh. Folklore, busted.
   - **Every-frame-perfect client presentation** → X has had it since **~2013 via
     Present + DRI3** (the same swap-chain Starling reimplements). Folklore, busted.
   - **Ambient-authority isolation** → the *one* genuinely architectural Wayland
     difference that survives. X's "any client can snoop/inject any other" is the
     design; not retrofittable. The portal tax buys a real thing.
   - **Network transparency** → not a corpse; **bifurcated by rendering model**, and
     latency-bound (thrives on LAN). Wayland made CSR mandatory (the one
     non-transparent model) and offers `waypipe` as a strictly-less-elegant swap.
7. **The through-line: quality is mostly *where you put the seam.*** X = draw-ops;
   Wayland/`waypipe` = buffers/pixels; modern remote-dev (Tramp / VS Code Remote /
   JetBrains Gateway) = **semantics** — a higher, better, display-server-*agnostic*
   seam that makes the whole X-vs-Wayland fight orthogonal to real dev work.

---

## Part 1 — Starling

### 1.1 What it is

One person + an LLM, six months, ~335K LOC (Apache-2.0). Of that, **~273K is a
Flutter framework port from Dart to Swift** (the `engine`/`sdk`), and **~62K is the
desktop itself + its Wayland and X11 servers + bundled apps**. Marketing thesis:
*"the constraint on Linux desktop dev was never taste, it was labour — and labour
got cheap."* The site describes the X path as *"hosts an X server,"* which reads
like Xwayland — the phrasing that seeded my wrong first guess.

### 1.2 The X server is bespoke and in-process (not Xwayland)

`shell/Sources/X11Server/x11_server.cc` (~5,158 lines) + `include/x11_server.h`
(171) implement the X11 wire protocol directly:

- **Owns the display socket itself** — `mkdir /tmp/.X11-unix`, `bind`, `listen` on
  `X<n>` (`x11_server.cc:861-901`), both abstract- and filesystem-namespace. **No
  `fork`/`exec`/`posix_spawn` of any X binary** anywhere.
- **Does not link `libX11`/`libxcb`** (those are *client* libs). It links only the
  server/GPU helpers: `xshmfence`, `drm_fourcc`, `gbm`, and opens
  `/dev/dri/renderD128` (`:638`). Bespoke opcode table (`X11_CREATE_WINDOW = 1 …`),
  modern STL (`std::vector/map`).
- **Compiled into the same binary as the Wayland compositor.** `shell/Package.swift`:
  `DesktopShellApp` depends on both `"X11Server"` and `WaylandServer`
  (which links `wayland-server`). One process, one `renderD128`, one epoll (the X
  server registers its listen socket + vblank timer + a wakeup eventfd into the
  compositor's DRM epoll via `x11_server_set_epoll_fd` / `get_all_fds`).

### 1.3 How X windows reach the screen — everything becomes a Flutter texture

The C ABI (`x11_server.h`) is callback-based. `X11Integration.swift` (447 lines,
`import X11Server`, `x11_server_create` at `:119`) maps it into the compositor:

- `on_present_buffer` — a **DRI3 DMA-BUF** (fd + fourcc + stride) for GPU clients →
  imported straight into a **Flutter external texture** (`textureRegistry` →
  `MarkExternalTexture`, `X11Integration.swift:91`).
- `on_present_image` — raster upload (RGBA8888) for Qt/GTK/xclock that paint with
  core-X/MIT-SHM instead of DRI3.
- `on_window_{mapped,unmapped,destroyed,configured}`, `on_title_changed`,
  `capture_screen` (GetImage/screenshot).
- Input flows back over the same ABI: `x11_server_pointer_motion/button`,
  `x11_server_key_event` (evdev keycodes), `set_focus`, enter/leave; WM ops
  `configure_window`, `release_buffer` (PresentIdleNotify); its own ~60Hz vblank
  timer + resize-debounce timer.

**So both the X server and the Wayland server dump buffers into Flutter's texture
registry, and Flutter composites the lot.** X window, Wayland surface, and the dock
are all just textures. That is the payoff of the 273K-line Flutter port — it's the
shared scene graph.

### 1.4 Curated subset + the Xwayland escape hatch

Advertised extensions (`x11_server.cc:845-855`): **Present, GLX, RENDER, Composite,
XFIXES, XInput2, SYNC, MIT-SHM, BIG-REQUESTS.** Conspicuously **absent: RANDR,
DAMAGE, XKEYBOARD, XTEST, Xinerama.** GPU-first; Mesa-only (`renderD128`+`gbm`, no
NVIDIA path).

When a client is too awkward for the in-tree server, Starling falls back to the
real thing: `build/wechat-run.sh` runs WeChat *"through **rootful Xwayland**"* ("the
desktop's Wayland compositor has no X window manager"), and
`build/package-desktop.sh:258` lists `xwayland` in the Debian `Recommends:`. **True
shape: bespoke native X for the modern mainstream; actual Xwayland for the long
tail.**

### 1.5 Provenance — reconstructed, not lifted

The "they grabbed a working X server and baked it in" hypothesis is **falsified**:

1. **Zero X.Org DNA.** Canonical protocol tokens (`CARD32`/`xReq`/`REQUEST()`/
   `dixLookup`) = **0**. Lifted X.Org/kdrive code would `#include <X11/Xproto.h>`
   and speak `CARD32`; this speaks `uint32_t`.
2. **The NOTICE would have ratted them out.** It attributes *everything* — 15
   individual Wayland copyright holders, PDFium's sub-licenses, even
   dynamically-linked system libs "for completeness." The X server is attributed to
   **no-one** → claimed first-party. A silent lift, in a repo this fastidious, would
   be a glaring Apache-NOTICE violation.
3. **It's grown gap-by-gap — the fingerprint of hand-written code.** `CLAUDE.md:206`:
   *"Java/Swing needs two X server gaps closed… XI1 `ListInputDevices` must reply —
   AWT blocks on it holding the toolkit lock… RENDER `QueryPictFormats` must list the
   depth-32 root visual."* You only get *per-client missing pieces* like that in a
   server you wrote and extend one app at a time. The repo calls it the **"in-tree
   X server"** (`CLAUDE.md:23`).
4. **The only "Xorg" strings are oracle, not source.** The vendor handshake reports
   `"The X.Org Foundation"` (`:1419`) because clients sniff it; a comment says
   *"matching real Xorg, which sends these at vblank… Chrome's ANGLE frame pacing
   depends on it"* (`:3138`). Reverse-engineering observable behavior, not copying.

**Verdict:** what it "came from" is the model's *training exposure* to Xorg/Xwayland
(the banner literally says *"C++ rewrite"*; every hard case is written against real
Xorg as the spec-to-reproduce) — **derived knowledge, not derived code.** Legally
clean; no attribution owed for learned patterns. Public history is squashed to one
release commit, so git archaeology is unavailable.

### 1.6 Five languages, a bridge lattice, and macOS-on-Linux

The C++/Swift split isn't a provenance tell — it's necessity (you can't sanely do
DMA-BUF fd-passing / epoll / `gbm` from Swift-on-Linux; the `extern "C"` ABI is
where any Swift systems project drops to C/C++). But the *whole* language picture
is worse than two:

- **Desktop repo:** 684 Swift · 51 C + 54 .h + 1 .cc · **32 Objective-C** (all in
  `sdk/macos-compat/probe`).
- **Engine repo:** **6,158 Dart** (the framework is *still Dart*; the "Swift port" is
  a binding veneer) · 1,659 .cc + 81 .cpp + 8 C · **219 .mm + 119 .m** (ObjC/ObjC++)
  · 103 Swift.
- **Bridges named in `Package.swift`:** `FlutterMacOSBridge`, `FlutterEmbedderBridge`,
  `FlutterDRMBridge`, `WaylandServerBridge`, `ImeBridge`, `FlutterSwiftBridge`,
  `SwiftRuntime`, plus a raw `cxxBridgeInclude` into
  `.../flutter/lib/ui/swift/include`.
- **The kicker:** it links `-framework FlutterMacOS` and carries a 32-file ObjC
  `macos-compat` shim — **Starling runs Flutter's *macOS embedder* on Linux.**

**So Swift is inherited toll, not merit.** Flutter's macOS platform layer is
Swift/ObjC; reusing that mac embedder (rather than writing a Linux one) was the
fast path, and it dragged Swift + ObjC + a macOS-compat shim in with it. Swift buys
**nothing** for the systems layer (that's all C++). Where it "pays" is narrow: it's
the least-friction host for a *Dart* framework port, and its type-checker turns AI
mistakes into compile errors instead of C++ UB. On a *single-language, no-runtime,
own-the-stack* value function (mine), it does not pay its freight.

### 1.7 Born-soup vs accreted scar tissue

*"Most working software is incoherent accretion"* is true but **does not license
this** — because there is a categorical difference:

- **Accreted complexity** (X11's, the Linux desktop's) is **scar tissue**: earned
  over decades, each ugly layer a healed wound encoding a real solved problem.
  Information-rich; debt *with equity* (you took it on because the system was worth
  keeping alive). It is the **exhaust** of solving real problems.
- **Born complexity** (Starling's) is complexity as a **precondition** — poured in on
  day one as the fuel to boot at all, before meeting a single real constraint that
  would justify it. Maximal debt with **zero equity**, and mostly **accidental**
  (Brooks) not essential: Wayland+X11 in one session is essential-ish; running the
  *macOS embedder* five languages deep to get there is pure accidental — a
  fingerprint of the *builder's* constraint (one person / six months / reuse-or-die),
  not the *problem's* nature.

The "it's scaffold — bootstrap ugly, then rewrite native" defense is empirically
almost never redeemed, and **this repo already shows the freeze**: `CLAUDE.md`
carries `X11Server/ … do not touch unless asked` and a standing *"Wayland only. Do
not read, modify, or reference `X11Server/` or X11 launch paths unless explicitly
asked."* That's **quarantine tape**, at v0.2.1. What AI actually did here is keep
alive a project that complexity-at-birth *should* have killed — long enough to
screenshot. Whether that's a triumph or a way to manufacture zombies (systems only
the model that secreted them can maintain) is the open question.

---

## Part 2 — The broader X11/Wayland audit

### 2.1 "Structural" vs folklore (verified against code)

Three times this session the received "Wayland progress" narrative was repeated and
then **refuted by evidence**. Kept here because the pattern is the point.

| Claim ("X can't, therefore Wayland") | Reality | Evidence |
|---|---|---|
| X can't do tear-free / atomic presentation | **Folklore.** XLibre ships it. | see §2.2 |
| X can't do every-frame-perfect client present | **Folklore.** X has it since ~2013. | Present + DRI3 (`Xext/present`, `Xext/dri3`) — the same swap-chain Starling reimplements |
| X network transparency was already dead | **Folklore.** Bifurcated + LAN-alive. | see §2.4 |
| X has no client isolation | **True — the one real one.** | X's ambient authority is the design; not retrofittable. Portals are Wayland re-granting it through mediated slots. |

The recurring bias: reaching for *"structural / architectural / can't"* when the
truth is *"nobody defaulted it"* or *"it's folklore repeated until it sounds like
physics."* Verify against **XLibre source** and **Present/DRI3** before repeating
the received wisdom.

### 2.2 VERIFIED FINDING — XLibre has tear-free + atomic + VRR

Checked in the XLibre `xserver` tree directly. `README.md` "Selected Features",
bullet 2: **"TearFree modesetting *by default* and optionally atomic modesetting"**
(with commit links). The `modesetting` man page carries the knobs:

- `Option "TearFree"` (`modesetting.man:123`)
- `Option "Atomic"` — *"Enable atomic modesetting when supported"* (`:134`)
- `Option "VariableRefresh"` — VRR/adaptive-sync per-CRTC (`:85`)
- `Option "AsyncFlipSecondaries"` — async flips on secondary outputs (`:92`)

Code: `hw/xfree86/drivers/video/modesetting/{driver,present,pageflip,drmmode_display}.c`.
README also claims *"all the good things from X.Org Server, including its unreleased
features,"* plus NVIDIA 340/390/470/570 support, the `Xnamespace` client-isolation
extension, and `seatd` support.

**Implication:** the "atomic, tear-free, every-frame-perfect presentation" I once
called something "X structurally can't retrofit" is (a) shipping as the *default* in
a fork on a rounding-error of the manpower, and (b) was never structural anyway —
Present/DRI3 gave the client-side swap-chain a decade ago. This is a crisp instance
of the proportionality thesis: capability that existed all along, an "impossibility"
that was a story, parity handed back to X by volunteers *after* the schism's bill was
paid. **Ties directly into `docs/2026-07-05-xlibre-versioning-artix-packaging.md`.**

*One honest residue:* **mixed / independent per-monitor DPI** is the axis I did
*not* find XLibre addressing (no headline claim in `README`/`NEWS`/`HISTORY`); X's
single global coordinate space still looks genuinely structural there — but held
with much less confidence than before, given how "structural" evaporated on
presentation.

### 2.3 Wayland's 17 years, read through this

Wayland (2008) is the *same* "the hard 20% is a tweak away" delusion as Starling,
run in the opposite direction: Starling was born a soup; Wayland was born a pristine
core and spent ~17 years re-growing the soup it deleted. The Brooks-shaped heart:
**it mistook X11's *essential* complexity for *accidental* complexity, cut it out,
and spent two decades rediscovering it was load-bearing.** The "countless man-hours
of argument" *were* the re-derivation of knowledge X11 already had encoded in its
"bloat." The **portal fleet** is the monument — a subsystem whose only job is to
hand back, through a mediated slot, functionality that used to be ambient.

Jim's reductive equation (kept for the record):
> today's Wayland ≈ X11 − network-transparency + independent-per-monitor-DPI +
> (partial) HDR + draconian-security-needing-a-fleet-of-portals-to-regain-function.

Honest ledger: a *few* deletions were genuine upgrades X can't cleanly retrofit
(mixed-DPI; the isolation model). But most of the "wins" were parity-recovery, and
the crime is the **disproportion** — ~17 years and an ecosystem-wide schism to buy a
modest set of gains an evolve-X11 path might have delivered faster and without the
blood.

### 2.4 Network transparency — not a corpse, bifurcated

X network transparency **bifurcates by rendering model**:

- **Command-stream apps** (xterm, X-emacs, dev tooling, monitoring, gnuplot-style
  plotting, most internal GUIs) ship *drawing ops* — a few bytes each — and forward
  beautifully.
- **Client-side-rendering apps** (modern GTK3+/Qt5, browsers, image/gradient-heavy
  UIs) ship *pixels* and choke.

The killer is **round-trip latency, not bandwidth** (X is chatty; requests block on
replies). On a WAN that's death; on a **low-latency LAN** the penalty vanishes and
even chattier apps stay crisp.

Field evidence (Jim, direct): **2Sigma** (hedge fund) — almost everyone on **Windows
desktops** working **continuously** on Linux, running X apps via **SSH X-forwarding**
to their VMs (Windows X servers: MobaXterm / Exceed / X-Win32). *Remarkably useful*,
at scale, **to at least ~2018** — and this pattern likely survives in pockets of
finance/EDA in 2026. So "corpse" was wrong; it was *thriving in the workloads that
matched its model.*

Wayland made **CSR mandatory** — the one model that *structurally* can't be
network-transparent — then offers `waypipe`: "ship the pixels, but efficiently." The
CSR-slideshow case, optimized, as a replacement for the command-stream case it
can't do at all. Euthanizing the healthy quadrant to standardize the sick one.

### 2.5 The seam thesis (the unifying lesson)

**Quality is mostly a question of where you put the seam.** Different problems have
different optimal seam-locations; picking the wrong one generates the soup / the
disproportion / the "17 years to get back."

| System | Seam location | Consequence |
|---|---|---|
| X11 forwarding | **draw-ops** | transparent for command-stream, chatty/latency-bound, useless for CSR |
| Wayland / `waypipe` | **buffers / pixels** | atomic + secure, but CSR-only, transparency-hostile |
| Remote-dev (Tramp / VS Code Remote / JetBrains Gateway) | **semantics** (files, completions, diagnostics, terminal bytes; UI rendered locally & natively) | latency-tolerant, tiny, **display-server-agnostic** |
| Starling | **a C ABI**, forced down at the Swift↔C++ boundary | a lattice of bridges |

For **remote development** — Jim's actual need — the winning seam is *higher than
either display server*. VS Code Remote doesn't care whether the *local* box runs X,
Wayland, macOS, or Windows, because nothing crossing the wire touches a display
protocol. **That's why the entire X-vs-Wayland fight is orthogonal to how real dev
work gets done** — the workload was lifted clean off that battlefield.

Caveat in-idiom: the semantic seam has a **clean** embodiment (Tramp/SSH — *nothing*
installed remote; editor fully local, only file ops proxied) and a **fat** one (VS
Code Remote / Gateway — a heavyweight agent pushed onto every host, telemetry and
all). Same seam-location, opposite weight.

---

## Appendix — reproduce it

```bash
# Starling (already cloned):
cd ~/projects/starling
sed -n '1,8p' shell/Sources/X11Server/x11_server.cc          # "C++ rewrite" banner
grep -nE 'add_ext' shell/Sources/X11Server/x11_server.cc      # advertised extensions (:845-855)
grep -cE 'CARD32|xReq|REQUEST\(|dixLookup' \
     shell/Sources/X11Server/x11_server.cc                    # → 0 (no X.Org DNA)
grep -n 'X11Server\|WaylandServer\|FlutterMacOS' shell/Package.swift
sed -n '203,210p' CLAUDE.md                                   # the gap-by-gap Swing note
cat NOTICE                                                    # attributes everything but the X server

# XLibre tear-free/atomic (re-clone if scratchpad is gone):
git clone --depth 1 https://github.com/X11Libre/xserver.git
grep -n 'TearFree\|atomic' xserver/README.md
grep -inE 'tearfree|atomic|variablerefresh' \
     xserver/hw/xfree86/drivers/video/modesetting/modesetting.man
```

**Local artifacts:** `~/projects/starling`, `~/projects/starling-engine` (shallow
clones). XLibre was cloned to the session scratchpad — re-clone as above if needed.

**Related docs:** `docs/2026-07-05-xlibre-versioning-artix-packaging.md` (the XLibre
finding in §2.2 slots in beside it); `docs/2026-06-15-x11-wm-research.md`.
