# Artix Linux Init System Comparison

Research for potential migration from Arch Linux (systemd) to Artix Linux (systemd-free).

## Why Artix?

- Artix has [publicly stated](https://x.com/lundukejournal/status/2034776326901555488) they will **not** implement OS-level age verification
- Artix is Arch-compatible (same packages minus systemd), so migration path exists
- Multiple init system choices: runit, OpenRC, dinit, s6

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

## References

- [Artix Linux](https://artixlinux.org/)
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
