# Arch Linux Alternatives: Artix & Omarchy

Research for potential migration from Arch Linux to a distro that won't implement OS-level age verification.

## Context

OS-level age verification laws have passed in Brazil and California, with Colorado, Illinois, New York, and Michigan proposing similar. Ubuntu, Fedora, Pop!_OS, and elementary OS are planning to comply. Arch Linux's stance is unknown but concerning — discussion is being censored on their forums and subreddit, and Valve's financial investment (SteamOS is Arch-based) creates compliance pressure. See [age verification tracker](https://github.com/BryanLunduke/DoesItAgeVerify).

Two Arch-based alternatives have publicly stated they will **not** comply:
- **Artix Linux** — Arch without systemd, multiple init system choices
- **Omarchy** — Opinionated Arch + Hyprland/Wayland distribution by DHH (37signals/Basecamp)

---

## Omarchy

- **Website:** [omarchy.org](https://omarchy.org/) | **Repo:** [basecamp/omarchy](https://github.com/basecamp/omarchy) (21k+ stars, 2k+ forks)
- **Creator:** DHH (David Heinemeier Hansson), 37signals/Basecamp
- **Base:** Arch Linux (keeps systemd, keeps pacman, keeps AUR via yay)
- **Age verification:** [Will not implement](https://x.com/lundukejournal/status/2029580164498108846)
- **License:** MIT

### Stack

| Component | Choice |
|---|---|
| **Display protocol** | Wayland |
| **Window manager** | Hyprland (+ hypridle, hyprlock, hyprpicker, hyprsunset) |
| **Status bar** | Waybar |
| **Terminal** | Alacritty (+ Ghostty available) |
| **Shell** | Bash (+ starship prompt) |
| **Editor** | Neovim (custom omarchy-nvim config) |
| **Browser** | Chromium |
| **File manager** | Nautilus |
| **Launcher** | Walker (custom omarchy-walker) |
| **Notifications** | Mako |
| **Screen capture** | grim + slurp + satty, gpu-screen-recorder, OBS |
| **Display manager** | SDDM |
| **Boot** | Limine + Plymouth |
| **Audio** | PipeWire (+ WirePlumber, WireMix) |
| **Containers** | Docker + docker-compose + lazydocker |
| **Password manager** | 1Password |
| **Fonts** | iA Writer, JetBrains Mono Nerd |
| **Git** | gh CLI + lazygit |
| **AI** | Claude Code (ships in base packages!) |

### Pros (for our use case)

- **Still Arch under the hood** — pacman, AUR, same packages, same kernel. Simplest migration path.
- **Keeps systemd** — no init system change, all existing scripts/services work as-is
- **Active development** — DHH and 37signals backing, large community, pushed to daily
- **Strong anti-verification stance** — DHH is vocal about it
- **Good hardware support** — includes NVIDIA, Intel, Surface, T2 MacBook, ASUS, Tuxedo drivers

### Cons (for our use case)

- **Wayland-only** — Hyprland is a Wayland compositor. No X11 support. This is the big one.
  - i3 configs don't carry over (Hyprland has its own config format, though conceptually similar)
  - `xrandr`-based display management (i3-screen-manager) needs complete rewrite for `hyprctl`/wlr-randr
  - X11-specific tools (xdotool, xprop, etc.) don't work
  - Screen sharing requires xdg-desktop-portal-hyprland (included, but the Wayland "technology stack" problem)
- **Very opinionated** — ships 1Password, Obsidian, Spotify, Chromium, Docker, etc. Subtraction needed.
- **SDDM + Plymouth + Limine** — different boot chain than a typical Arch install (GRUB)
- **No gvfs** workaround needed — ships `gvfs-mtp`, `gvfs-nfs`, `gvfs-smb` (but not `gvfs` itself, so the trash D-Bus hang may not apply)

### Migration effort: Medium-High

The init/package layer is trivial (it's just Arch). The real work is the X11→Wayland transition: rewriting display management scripts, learning Hyprland config, replacing X11-specific tooling. The "subtract what you don't want" approach works for applications (remove Obsidian, swap Chromium for Brave, etc.) but the Wayland foundation is non-negotiable.

---

## Artix Linux

- **Website:** [artixlinux.org](https://artixlinux.org/)
- **Base:** Arch Linux without systemd
- **Age verification:** [Will not implement](https://x.com/lundukejournal/status/2034776326901555488)
- **Init systems:** OpenRC, runit, dinit, s6

### Why Artix?

- Arch-compatible (same packages minus systemd), migration path exists
- Multiple init system choices
- Already maintains its own package delta from Arch (systemd removal) — has infrastructure to strip out future compliance packages
- Can run i3/X11 unchanged (no forced Wayland transition)

## Init System Comparison Chart

## Comparison Chart

| Aspect | **Runit** | **OpenRC** | **s6** | **Dinit** |
|---|---|---|---|---|
| **Origin** | Gerrit Pape, 2001 | Gentoo/Roy Marples, 2007 | Laurent Bercot, ~2013 | Davin McCall, ~2016 |
| **Language** | C | C + POSIX shell | C | C++ |
| **Philosophy** | Extreme minimalism | Traditional + deps | Extreme modularity | Best-of-both-worlds |
| **Service deps** | **None** | Full (need/use/after) | Full (compiled DB) | Full (3 dep types) |
| **Supervision** | Always on | **Opt-in only** | Always on | Always on |
| **Parallel boot** | Yes (unordered) | Optional (off by default) | Yes (dep-ordered) | Yes (dep-ordered) |
| **Service format** | Shell script (`run`) | Shell script (`openrc-run`) | Dir + one-file-per-param | **Ini-style config** |
| **Logging** | svlogd (per-service) | None built-in | s6-log (excellent) | logfile directive (basic) |
| **Learning curve** | Low | Low-medium | **High** | Low |
| **Artix status** | Full support | **Flagship/default** | Full support | Full (newest) |
| **Used by** | Void Linux | Gentoo, Alpine | Containers (s6-overlay) | Artix primarily |
| **Bus factor** | Done/unmaintained | Multi-dev, active | 1 (Laurent Bercot) | 1 (Davin McCall) |

## Detailed Notes

### Runit

- Created by Gerrit Pape (2001), reimplementation of DJB's daemontools
- Extreme minimalism: core `runit.c` is ~330 LOC, no dynamic memory allocation
- **No dependency management at all** — services start in parallel with no ordering
- If service B needs A, B crashes and restarts in a loop until A is ready (ugly, wastes resources)
- Services must run in foreground; daemons that fork need wrapper tricks
- Enable/disable by creating/removing symlinks
- Per-service logging via `svlogd` (handles rotation/size limits)
- Essentially "done"/unmaintained — feature-complete by design
- Battle-tested via Void Linux

**Service example:**
```sh
# /etc/runit/sv/sshd/run
#!/bin/sh
exec 2>&1
exec /usr/sbin/sshd -D
```

### OpenRC

- Originated from Gentoo's init scripts, rewritten by Roy Marples ~2005-2007
- Full dependency management: `need` (hard), `use` (soft), `after` (ordering), `before`
- Supervision is **opt-in** via `supervise-daemon` (added v0.21+) — crashed services stay dead by default unless configured
- Parallel boot supported but **off by default** (`rc_parallel="YES"` in `/etc/rc.conf`)
- OpenRC itself is not a daemon — it runs, establishes service states, and exits
- No socket activation or on-demand service starting
- Largest Artix community; Artix originated as Arch-OpenRC
- Default init for Gentoo, Alpine Linux

**Service example:**
```sh
#!/sbin/openrc-run
command="/usr/sbin/sshd"
command_args="-D"
pidfile="/run/sshd.pid"

depend() {
    need net
    use logger
    after firewall
}
```

### s6

- Created by Laurent Bercot (skarnet.org), ~2013
- Multi-package ecosystem: s6 (supervision) + s6-rc (deps) + s6-linux-init (PID 1) + execline (scripting) + skalibs
- Excellent logging via `s6-log` with built-in rotation and per-service log dirs
- Dependencies via s6-rc require a **compile step**: edit source, run `s6-rc-compile`, update live DB
- `execline` scripting language is powerful but unfamiliar; shell works but docs lean on execline
- Popular in containers via `s6-overlay`
- Steepest learning curve of all four
- Bus factor of 1 (Laurent Bercot)

**Service example:**
```
# /etc/s6-rc/source/sshd/type
longrun

# /etc/s6-rc/source/sshd/run
#!/bin/execlineb -P
fdmove -c 2 1
/usr/sbin/sshd -D

# /etc/s6-rc/source/sshd/dependencies
network
```
Then: `s6-rc-compile /etc/s6-rc/compiled /etc/s6-rc/source`

### Dinit

- Created by Davin McCall, ~2016, active development (v0.20.0 Nov 2025)
- Most systemd-like in terms of declarative config
- Three dependency types: `depends-on` (hard), `depends-ms` (milestone), `waits-for` (soft)
- Smart crash handling: stops dependents, restarts failed service, then restarts dependents
- No cgroups integration, no socket activation
- Smallest ecosystem — may need to write service files for less common packages
- Bus factor of 1 (Davin McCall)

**Service example:**
```ini
type = process
command = /usr/sbin/sshd -D
depends-on = network
restart = true
smooth-recovery = true
logfile = /var/log/dinit/sshd.log
```

## Key Considerations for Migration

### What systemd features we actually use

- `systemd-inhibit` in `i3-screen-manager` for clamshell lid-switch blocking — needs replacement
- Service management via `systemctl` — replaced by init-specific tools
- Journal via `journalctl` — replaced by syslog or init-specific logging
- Full audit of systemd dependencies needed before migration

### None of these provide

- Socket activation
- cgroups resource control
- `systemctl`-style unified tooling
- For a desktop i3/X11 setup, these are rarely needed

## Recommendation

**OpenRC > Dinit > Runit > s6** for our desktop i3/X11 use case.

- **OpenRC**: Largest ecosystem, most documentation, most pre-packaged services in Artix, familiar SysV-lineage concepts
- **Dinit**: Easiest transition from systemd (declarative config), but smallest ecosystem
- **Runit**: Simplest but no dependency management is painful on a desktop
- **s6**: Most sophisticated but steep learning curve and administrative overhead

## Side-by-Side: Artix vs Omarchy

| Aspect | **Artix** | **Omarchy** |
|---|---|---|
| **Base** | Arch minus systemd | Arch with systemd |
| **Init** | OpenRC/runit/dinit/s6 | systemd |
| **Display** | Your choice (X11 or Wayland) | Wayland (Hyprland) |
| **Migration effort** | Medium (init system change) | Medium-High (X11→Wayland) |
| **i3 scripts work?** | Yes (with systemd-inhibit replacement) | No (complete rewrite for Hyprland/Wayland) |
| **Package delta from Arch** | Maintained (systemd removal) | Minimal (overlay, not fork) |
| **Age verification resilience** | Strong (already forks packages) | Depends on DHH's commitment |
| **Community size** | Established, multi-year | Large but new (since June 2025) |

## The Wayland Question

Omarchy forces the Wayland transition. The fundamental frustration with Wayland: many things that "just work" in X11 require a technology stack in Wayland (screen sharing, global hotkeys, clipboard management, window positioning). Every other desktop OS handles these out of the box. Wayland's "security-first" design made these intentionally hard, and the ecosystem is still catching up.

That said, Hyprland is arguably the best tiling WM on Wayland — if the transition ever makes sense, it's the one to target. The dream would be a display server that is simultaneously X11 and Wayland compatible without the security-theater restrictions, but that project doesn't exist yet.

**Bottom line:** If staying on X11/i3 is the priority, Artix is the cleaner path. If you're willing to make the Wayland jump (and rewrite display management scripts), Omarchy is simpler at the system level since it keeps systemd.

## Phoenix: The Display Server That Should Exist

**Repo (mirror):** [external-mirrors/phoenix](https://github.com/external-mirrors/phoenix) | **Primary:** [repo.dec05eba.com/phoenix](https://repo.dec05eba.com/phoenix)
**Author:** dec05eba (also the gpu-screen-recorder author)
**Language:** Zig | **License:** GPL-3.0-only | **Status:** Early development (nested mode only, simple GLX/EGL/Vulkan apps)

Phoenix is a **from-scratch X11 server** — not a fork of Xorg, not a Wayland compositor. It reimplements a practical subset of the X11 protocol with modern design choices that address the legitimate criticisms of both X11 and Wayland.

### Design philosophy

| X11 problem | Wayland problem | Phoenix approach |
|---|---|---|
| No app isolation | Apps can't talk to each other at all | Apps isolated by default, but with **permission prompts** (like macOS) and an option to disable isolation entirely |
| Single framebuffer for all monitors | Per-compositor implementation differences | Per-monitor refresh rates, VRR, HDR via DRM/GBM |
| Tearing, no built-in compositor | Compositor is mandatory and complex | Built-in compositor, disables automatically for fullscreen/external compositors |
| Legacy protocol cruft | Broke all existing apps | Only implements the X11 features modern apps actually use (~20 years of software works) |
| xf86 driver interface complexity | Each compositor reimplements display | DRM/GBM kernel interfaces (same as Wayland compositors) |
| No modern features (HDR, VRR) | Has them, but per-compositor | Planned as X11 protocol extensions |
| Global hotkeys: security hole | Global hotkeys: broken/impossible | Global hotkeys work with modifier keys; unmodified hotkeys require explicit permission |
| Clipboard: any app reads anytime | Clipboard: varies by compositor | Only focused app can read clipboard (more secure than both X11 *and* most Wayland compositors) |

### Key features

- **Wayland app compatibility** planned via native support or 12to11 bridge
- **Nested mode** under X11 or Wayland (useful for development and as Xwayland alternative)
- **Zig with ReleaseSafe** — memory-safe without C legacy baggage
- **Per-monitor DPI** as randr properties (new standard, documented)
- **No GrabServer** — the X11 call that lets one app freeze the entire display is a no-op

### Why it matters

From the Phoenix FAQ: *"writing a simple X server that works in practice for a wide range of applications is easier to do than writing a Wayland compositor (+ related software)."*

This is the project that says "keep X11's model where apps can just work, add sensible security with user-controlled permissions instead of architecting functionality out of existence, and use modern kernel display infrastructure." It's the hybrid approach nobody else is attempting.

### Current status (as of 2026-03)

Early. Runs nested only, renders simple GLX/EGL/Vulkan apps. DRM backend (standalone mode) and Wayland nested mode not yet supported. Development is private (contributions not yet accepted publicly). The GitHub repo is a mirror of the primary repo at dec05eba's personal git server — the private development model is a deliberate choice to keep the project insulated from ideological pressure that routinely targets X11-related work.

### What to watch for

- DRM backend landing (standalone mode without a host X/Wayland server)
- Real-world app compatibility (GTK, Qt, Firefox, etc.)
- i3 or other tiling WM running on Phoenix
- 12to11 bridge or native Wayland client support

If Phoenix matures, it could obsolete the Artix-vs-Omarchy question entirely — run i3 on Phoenix on whatever base distro has the right policy stance, with both X11 and Wayland app support.

## References

- [Artix Linux](https://artixlinux.org/)
- [Omarchy](https://omarchy.org/) | [GitHub](https://github.com/basecamp/omarchy)
- [Artix Wiki - OpenRC](https://wiki.artixlinux.org/Main/OpenRC)
- [Artix Wiki - Runit](https://wiki.artixlinux.org/Main/Runit)
- [Artix Wiki - s6](https://wiki.artixlinux.org/Main/S6)
- [Artix Wiki - Dinit](https://wiki.artixlinux.org/Main/Dinit)
- [runit official site](https://smarden.org/runit/)
- [OpenRC on GitHub](https://github.com/OpenRC/openrc)
- [s6 ecosystem (skarnet.org)](https://skarnet.com/projects/s6/)
- [dinit official site](https://davmac.org/projects/dinit/)
- [dinit COMPARISON doc](https://github.com/davmac314/dinit/blob/master/doc/COMPARISON)
- [Gentoo Comparison of init systems](https://wiki.gentoo.org/wiki/Comparison_of_init_systems)
- [Age verification tracker](https://github.com/BryanLunduke/DoesItAgeVerify)
