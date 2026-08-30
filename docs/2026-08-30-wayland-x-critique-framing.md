# Wayland vs X — a reusable framing

**Date:** 2026-08-30 · **Purpose:** capture the arguments the user has developed
across multiple sessions on multiple machines so future Claude Code sessions can
reconstruct the framing without re-derivation. This is thesis-form documentation,
not conversation transcript. Grep the section headers.

Companion to:
- [`docs/2026-07-29-starling-desktop-investigation.md`](2026-07-29-starling-desktop-investigation.md) — broader "structural vs folklore" X11/Wayland audit
- [`docs/2026-08-30-xlibre-artix-drop-and-vendor-repo-migration.md`](2026-08-30-xlibre-artix-drop-and-vendor-repo-migration.md) — the migration this framing informed
- Auto-memory `feedback_xlibre_technical_envelope.md` — the specific "check XLibre before asserting X can't do X" rule
- Open-brain thought #346 — cross-machine version of the XLibre-envelope rule; and the bite-sized captures published alongside this doc

## 1. XLibre-of-2026 has closed most of the "structural X limitations"

My training data is calibrated to Xorg-of-2020 and systematically underestimates
what XLibre-of-2026 ships. Corrected twice in 24 hours (2026-08-29 on the desktop,
2026-08-30 here on the laptop) on the same claim: "client isolation is structural
to X." Wrong.

- **`Xnamespace` extension v1.0** — server-side client isolation via named
  namespaces; per-capability grants (`allow mouse-motion` / `allow shape` /
  `allow xinput`); token-based (MIT-MAGIC-COOKIE-1) namespace assignment; `root`
  namespace stays unrestricted so legacy apps keep working in ambient-authority
  mode. Doc: <https://github.com/X11Libre/xserver/blob/master/doc/Xnamespace.md>.
- **Present + DRI3** — tear-free presentation since ~2013.
- **Atomic modesetting** — optional but shipped (XLibre `modesetting.man`).
- **VariableRefresh (VRR)** — shipped.
- **`TearFree` default** — enabled by default in XLibre.
- **HDR** — in the pipeline per user (2026-08-30).

**Standing rule:** before asserting a technical limitation of X, check
`github.com/X11Libre/xserver/tree/master/doc` and recent releases, or ASK. The
one thing that IS still true is that adoption of these features by
distros/desktops/toolkits/apps LAGS the codebase — that's a coordination gap,
not a technical limitation of X. Distinguishing coordination from architecture
is the whole point of this framing.

## 2. The self-fulfilling narrative loop

The "X is legacy" narrative isn't a conspiracy but it's also not just neutral
observation. Once it reached coordination-point status, individual developers
used it to decide where to spend their finite time. Every talented person who
moved to Wayland was another data point confirming the narrative for the next
person weighing the choice. That's why "just fund X" as a counterfactual is
weaker than it sounds — the money wouldn't have summoned back the people who
left, because they left partly because they thought Wayland was technically
better *and* partly because that's where the interesting work was going to be.
Ideology and technical judgment reinforced each other in a loop that neither
alone could sustain. Red Hat's institutional weight didn't cause the drain so
much as ratify a direction that was already collecting the momentum.

**The FLOSS coalition asymmetry:** in volunteer-driven ecosystems, the coalition
that gets to say "we're starting fresh" only has to defend what they're
building. The coalition preserving and incrementally improving has to justify
every hour of unglamorous work against "why aren't you working on the shiny new
thing?" pressure. "Rewrite" coalitions structurally outrun "preserve and
improve" coalitions, regardless of technical merit. GNOME 3 vs GNOME 2 is the
same shape. Systemd vs sysvinit. Emacs vs the modern-editor churn (from the
other direction — preservation somehow won there).

XLibre is now doing the unglamorous "improve incrementally" work that X's
normal cadence would have delivered years ago if the coalition hadn't
fragmented. It gets no press because "we shipped feature parity for the thing
you already have" doesn't fit a marketing narrative. That's why the framing is
maddening rather than merely wrong: **incremental thoughtful improvement is the
engineering discipline that respects user investment, and it's the discipline
FLOSS has the worst institutional support for.**

## 3. Coordination gap, not technical limitation

The distinction matters because it flips who's responsible for what.

**Verified 2026-08-30 case:** Chromium/Brave 152.1.94.117 under `--ozone-platform=x11`
has NO kinetic scrolling and NO pinch-to-zoom. Both features are implemented
ONLY in the Wayland Ozone backend (which reads raw libinput events); the X11
Ozone backend routes through the legacy GNOME/GTK scroll stack that lacks the
fling and pinch code. `chrome://flags` returns zero results in BOTH Available
AND Unavailable tabs for `pinch`, `swipe`, `smooth`. No flag flip fixes this.
Code-search for `EnablePinchZoom`/`kEnablePinchToZoom` in `ui/events/x/` and
`ui/base/x/` returned zero. Structural direction is Wayland-only forever:
GNOME 50 (March 2026) shipped with ZERO X11 code (Mutter's X11 backend removed
2025-11-05); Chromium's X11 backend gets bug fixes but no feature work;
2026 gesture-adjacent CVEs (`CVE-2026-13855`, `-15764`, `-15765`) all landed
on Wayland UI-gesture code paths.

**But** — this is NOT a technical limitation of X. Xnamespace exists.
`libinput` on X11 delivers XInput 2.1/2.4 gesture events; a compositor
consuming those and synthesizing fling could ship. It's a coordination
decision by Chromium's team, informed by where the funding and feature work
go, which is Wayland. **The X server can do this. The Chromium binary chose
not to.**

Rule for the write-ups: when a feature "doesn't work under X in <app>," check
whether it's the SERVER that can't or the APP that doesn't. Usually the app.
Usually the coordination gap is the true story. Naming this distinction
prevents the sloppy "X can't do X" claim that keeps getting corrected.

The full write-up: [`docs/2026-08-30-chromium-brave-x11-gestures.md`](../docs/2026-08-30-xlibre-artix-drop-and-vendor-repo-migration.md)
carries the migration + this gesture finding as a post-cutover watch-list item;
CLAUDE.md's Common Issues → X11 apps section carries the shipped-in-repo bullet.

## 4. Security-by-default: threat model + POLA operational cost

The "security by default" narrative usually skips the threat-model step.
Wayland's mediated-everything design fits a threat model where many
mutually-suspicious apps share a device — mobile, or a multi-user server. On a
solo desktop where one user runs mostly-known software, that threat model is a
poor fit; the friction is per-interaction and the payoff is per-catastrophe.
The base rate of catastrophic compromise on a hygiene-competent solo desktop
really is low, and the daily cost of paranoid defaults is not zero. It's a
legitimate calibration to say "the expected-utility math on my personal box
doesn't clear the bar."

**The specific asymmetry that IS real:** once a compromise HAS landed, ambient
X authority lets a foothold amplify into keystroke capture, clipboard scraping,
credential harvesting. **But that's not materially worse than what your file
system already permits to anything running as you.** `~/.ssh`, `~/.mozilla`,
`gnome-keyring`, browser cookie stores, session tokens — all wide open. Once
compromised at the user-account level, you're compromised at the user-account
level. The marginal isolation that eliminating ambient-authority provides is a
smaller delta than the security narrative implies, because your other
user-scope secrets weren't isolated anyway. The Wayland pitch isolates ONE bit
of the attack surface (display) while leaving the rest untouched, and then
markets that one bit as if it were the whole game.

**Where per-app isolation genuinely earns its friction cost:** browsers
(constant untrusted content is their whole job), containers, sandboxed CI
runs, anything running attacker-controlled JavaScript. For those, capability-based
grants matter — and XLibre's opt-in `Xnamespace` gets the shape exactly right.
Browser gets launched into a namespace with minimal grants; containers get
namespaces; everyday emacs + terminal stay in `root` and pay no tax. **That IS
the pragmatic desktop-security policy: pay the friction where the threat model
actually requires it, don't tax everything for the sake of consistency.**

**The POLA operational-cost argument:** POLA (principle of least authority) as
a default is intellectually strong but operationally expensive to build and
maintain. iOS makes it work because Apple pays for the entire tooling stack,
permission UI, app-review layer, and developer education. Desktop Linux with
volunteer labor cannot afford POLA-by-default with the same polish, which is
why the actual experience under Wayland is often "the safety features I didn't
ask for are breaking the tools I did." XLibre's opt-in path respects user
agency without giving up the mechanism.

## 5. The Wayland protocol is not simple — empirically refuted

The "underneath libwayland is a simple protocol" claim was empirically tested
by the user's `~/projects/jai-wayland` project. The finding: not simple.
Concept count required to parse and dispatch one Wayland message:

1. Framed message with header
2. Per-interface opcode-to-signature dictionary
3. FD-argument parsing that couples the SCM_RIGHTS ancillary channel to the
   data channel via the signature (you can't just "read N bytes then dispatch
   on opcode" — you have to pre-consult the signature table to know how many
   FDs to pop from the ancillary buffer)
4. Versioning per interface
5. A meta-protocol (XML) for *defining* interfaces
6. Codegen tooling (`wayland-scanner`) to make any of it tractable

**Six concepts minimum**, with the last two being meta-level — they exist
because the first four turned out to be too complex to write against directly.

Contrast — **X core wire protocol: 2 concepts.** Fixed-header framed message
(32-byte requests), opcode-to-handler dispatch, arguments typed and positional
at known offsets. FDs in extensions (DRI3) come via ancillary but the count is
opcode-derived, not "parse to find out."

Contrast — **Win32 message pump: 2 concepts.** `MSG` struct, `WndProc`
`switch(msg)` with per-case hand-decoding of `wParam`/`lParam`. The
ugliness (variant-typed values packed into machine words) is
*concentrated in each handler* rather than distributed across a framework
that mediates the whole thing. **Ugliness-concentrated is actually a feature**
— you can look at one case and understand it entirely; you don't have to hold
the whole system in your head. Wayland smears the complexity uniformly across
the surface, which is what makes it feel simple-per-message and be
complex-in-aggregate.

**Simplicity tests both protocols pass:**
- Can you write a client with just a text editor and a hex dump? X: yes. Win32:
  yes. Wayland: no.
- Can you `telnet` to it and type it? (HTTP/1.1 passes.) N/A here but
  Wayland's wire is opaque without `wayland-scanner` output next to you.

**The design-by-XML anti-pattern:** when a protocol requires a code generator
to be usable, the protocol has failed the simplicity test. The XML files ARE
the spec, not a rendering of it. That's the design equivalent of admitting
the protocol can't stand on its own. Same failure mode as Protobuf, Thrift,
DBus — reach for tooling to paper over a design that got too big to write
against directly. And once you're in tooling-required territory, you're
stuck: nobody can validate your implementation against the "protocol" because
the "protocol" only exists in a form the tool understands. XML-defined
protocols are the CMake of network design.

**The final indictment:** if the wire protocol were actually simple,
"unwrapping libwayland into a normal event loop" would have delivered X-like
or Win32-like elegance as the natural shape. `jai-wayland` did that
unwrapping. What fell out was still baroque, still opaque, still required
carrying context to parse each message. libwayland isn't hiding elegance
behind convenience — it's hiding *ambient complexity* behind a framework that
mediates it enough that most consumers never look.

## 6. IoC / libwayland-owns-main is a framework, not a library

`libwayland` ships `wl_event_loop` — **its own event loop** that you're
supposed to integrate everything else into. That's the moment a library
says the quiet part out loud: "no, YOU adapt to ME." **A library that ships
its own main loop and expects you to plumb your input devices, DRM/KMS
events, GPU fences, timers, audio, and IPC through IT isn't a library. It's a
framework, and frameworks poison composition.**

The single-callback-API case is fine. The pathology shows up when you compose
N callback APIs — which is exactly what building a real compositor is. Then
you're managing:
- Which framework owns the *outermost* main loop
- Cross-framework object-lifetime rules that don't align
- Threading assumptions that don't match
- Latency stacking (event forwarded across three framework main loops before
  reaching your code)

The Unix syscall interface has been doing the right thing since forever:
`poll()` / `epoll_wait()` / `read()` — return me an event, I'll decide what
to do next. Add my own timers, my own IPC, my own scheduling. The client
owns the flow. Wire-level Wayland could have been that shape: "here's a fd,
`recv()` gives you framed messages, here's a table of message signatures,
go." Instead we got "here's a framework, register your listeners, please
don't touch main."

**Casey Muratori's version of this argument** (handmade-hero tradition,
roughly): bad API design comes from people who've only written outermost-application
code, because that's the only place IoC doesn't cost you anything. In systems
programming *everything is compose-multiple-things code*, so nothing is ever
the leaf, so callback-owns-main is always wrong.

The taste for callback-driven APIs — the "of course the runtime owns your
control flow" aesthetic — is the *default taste* of anyone who came up in a
callback-normalized ecosystem (browser JS, Node, modern async frameworks).
That taste is fine when you ARE the leaf of the dependency tree. Systems
programming is never the leaf.

## 7. The 1968 generational-reinvention thesis

Casey Muratori's "The Standup" appearance 2026-08-29
(<https://www.youtube.com/watch?v=gbzLuAzhJ0c>) leafs through the first six
months of *Datamation* magazine 1968 and finds every "modern" tech problem
already being discussed:

- **AI-as-existential-threat op-eds** ("computers possess an intelligence
  that dwarfs man's")
- **Federal data-bank privacy hearings** (Senator Long's subcommittee:
  3 billion citizen-name records, 2 billion age records; "whatever privacy
  remains for the American citizen remains because the federal government
  is presently too inefficient to pull all its personal information files
  together")
- **Software-as-a-Service** business model ("lease your software with no
  capital investment")
- **Software patents defeated-then-permitted** (a 1968 bill to ban them was
  defeated; that decision still shapes 2026)
- **Conway's Law's original April-1968 publication**
- **Automatic license-plate readers** (a New York State pilot that reads
  exactly like Flock cameras circa 2026)
- **Computer-assisted X-ray diagnosis beating physicians**
- **IBM System/360 Model 40 hypervisors** ("the user is not aware of anyone
  else in the system" — literal VM/container marketing pitch)
- **Political-campaign computing** (DNC upgrading their 1401 to a five-tape
  360-30 for the '68 race)
- **Computer-predicted judicial outcomes**
- **China-as-computing-threat forecasts**
- **Ray tracing already being sold as a commercial service** in February
  1968 Datamation ads — predating Wikipedia's cited "first ray-traced image"
  from April

Casey's summary: *"We have done nothing, basically. Hardware got a lot
better, and we just are exactly the same as what was in a Datamation magazine
from 1968."*

**The mechanism:** computing has an unusually strong cultural bias toward
youth vs peer disciplines. Music-theory freshmen analyze Bach; architects
read Vitruvius; physicists learn Newton before Einstein. Computing HAS the
equivalent canon — Knuth, Dijkstra, Hoare, Lamport, Wirth, Iverson,
Sutherland, Engelbart — but industry culture treats reading them as quaint
rather than required. The material rate-of-change of computing makes the
old work *feel* obsolete because the artifacts age (punch cards, PDP-11
assembly, tape drives), even though the *ideas* are timeless. A 1968 article
about "software as a service" is 100% conceptually applicable today — but
because it uses the word "leased" and shows a mainframe, it reads as
historical curiosity to a mid-career engineer skimming, who then invents
SaaS from first principles because they didn't recognize what they were
seeing.

**The pre-Internet path was actually the lucky one** (though it wouldn't
have felt lucky at the time). The user started in an era with no Internet,
forced to read books and magazines by older practitioners, which calibrated
them on what ground was already taken. The Internet-generation path mostly
exposes practitioners to the current wave's take on old ideas rather than
the original sources, and the current wave has strong incentive to omit the
"someone already did this in 1968" citation because it reduces novelty claims.

**Wayland vs X is the same shape at smaller scale.** The Wayland proponents
did not lead with "here is the version of X-with-Xnamespace-and-Present-and-DRI3-and-VRR
we're choosing not to build, and here's why," because that framing would
have required admitting the alternative was real. The rewrite got the
marketing budget; the incremental improvement got done anyway, on volunteer
time, unwatched, until XLibre made it undeniable. Same 1968 pattern,
58 years later.

## 8. Recurring mistakes to not make

Compressed for future me:

- **Do not** repeat "X structurally can't do <feature>" without checking XLibre
  first. `Xnamespace`, Present+DRI3, VRR, HDR are all in.
- **Do not** claim "Wayland has a simpler protocol" — `jai-wayland` refutes
  this empirically; concept-count is 6 vs 2.
- **Do not** collapse "simpler for a compositor author using libwayland" into
  "simpler protocol." Different claims. libwayland's API is a framework
  taste, not a protocol property.
- **Do not** frame "security" as a Wayland win without naming the threat
  model. Solo desktop with hygiene doesn't need the mobile-multi-app model.
- **Do not** treat "Chromium under X11 lacks kinetic/pinch" as evidence
  against X. It's a Chromium coordination decision. X can do the underlying
  work (XInput 2.1/2.4 events are there).
- **Do not** invoke "security by default" as an axiom. It's a design
  position with real friction costs; capability-with-opt-in is a defensible
  alternative and it's what XLibre chose.
- **Do** ask the user before making architectural claims about X.
- **Do** cite XLibre docs and release notes for anything technical about X.
- **Do** distinguish coordination gaps (Chromium, GNOME, distro choices) from
  architecture gaps (very few of these actually exist).

## 9. When this framing applies (topic triggers)

Grep for these terms in future conversation; this doc should surface:

- "X11" / "Xorg" / "XLibre" / "Wayland"
- "kinetic scroll" / "pinch zoom" / "touchpad gesture"
- "libwayland" / "wl_event_loop" / "wayland-scanner"
- "callback API" / "inversion of control" / "framework"
- "security by default" / "principle of least authority" / "POLA"
- "1968" / "Casey Muratori" / "Datamation" / "generational reinvention"
- "Xnamespace" / "Present" / "DRI3"
- "protocol simplicity" / "code generation" / "XML-defined protocol"

## 10. Provenance

Assembled 2026-08-30 from a rolling conversation the user has had "variants
of on multiple machines," now explicitly captured so it doesn't have to be
re-derived. Companion bite-sized captures published to open-brain the same
day for cross-machine retrieval.
