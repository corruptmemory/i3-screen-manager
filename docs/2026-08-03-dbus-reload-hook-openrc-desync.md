# pacman `Invalid operation 'reload'` — dbus-openrc / openrc hook desync

**Date:** 2026-08-03
**Machine:** `godlike-artix` (desktop). **`nomad-artix` (laptop) will hit the
same bug and needs the same fix — see §5.**
**Status:** TEMPORARY local override applied. Diagnosis + fix **independently
confirmed on the Artix forum**, where an upstream `dbus-openrc` patch is already
posted and maintainer-liked (§7) — so the resync is expected soon.
Re-evaluate/remove on the next `dbus-openrc` bump (see §6 Watch List).

## 1. Symptom

Running `sudo pacman -Syu` (the `upc` alias) intermittently ends with:

```
:: Running post-transaction hooks...
(1/5) Creating system user accounts...
(2/5) Creating temporary files...
(3/5) Updating udev hardware database...
(4/5) Reloading device manager configuration...
(5/5) Reloading system bus configuration...
  Invalid operation 'reload'
error: command failed to execute correctly
```

It only appears on updates that ship or change a D-Bus **system** policy file —
which is why it shows up "sometimes," not every update.

## 2. Root cause (confirmed + reproduced)

A **package version desync in Artix's current stable repos** — not a
machine-local problem, and not fixable by updating (both packages are already
newest).

- `/usr/share/libalpm/hooks/dbus-reload.hook` — owned by **`dbus-openrc
  20260324-1`**. Its action is:

  ```ini
  [Action]
  Description = Reloading system bus configuration...
  When = PostTransaction
  Exec = /usr/share/libalpm/scripts/openrc-hook reload dbus
  ```

- `/usr/share/libalpm/scripts/openrc-hook` — owned by **`openrc 0.63.3-2`**. It
  is a dispatcher that reads the **first** argument as the operation and
  `case`-matches it. The implemented ops are exactly:

  ```
  sysctl | dbus_reload | reexec | restart | add | del | uadd | udel
  ```

  There is **no `reload`**. So `reload` falls through to the catch-all:

  ```sh
  *) echo >&2 "  Invalid operation '$op'"; exit 1 ;;
  ```

The hook uses the *generic* `<verb> <service>` form (`reload dbus`) — matching
the pattern the `restart` case already uses (`rc-service "$@" restart`) — but
the installed `openrc` dispatcher never gained a generic `reload` verb; it still
only has the legacy single-token `dbus_reload`. **`dbus-openrc` got bumped ahead
of the `openrc` that would understand its hook.**

Reproduced directly:

```console
$ /usr/share/libalpm/scripts/openrc-hook reload dbus
  Invalid operation 'reload'          # exit 1  ← what pacman hits
$ sudo /usr/share/libalpm/scripts/openrc-hook dbus_reload
                                      # exit 0  ← the op that actually works
```

## 3. Why it is essentially harmless

- It is a **PostTransaction** hook — it runs *after* the package DB is
  committed. The update itself fully succeeded; nothing is half-applied. The
  `error: command failed to execute correctly` is pacman reporting the hook's
  non-zero exit, **not** a failed package operation.
- The hook's only job is to poke the *running* dbus daemon
  (`org.freedesktop.DBus.ReloadConfig`) so a just-installed policy goes live
  without a reboot. When it fails, worst case a changed D-Bus **system** policy
  isn't active until the next reboot. For almost every update that is
  irrelevant.

Manual reload any time (needs root):

```sh
sudo dbus-send --system --print-reply --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ReloadConfig
```

## 4. The fix applied (temporary local override)

pacman's `HookDir` precedence lets a same-named file in `/etc/pacman.d/hooks/`
**override** the one in `/usr/share/libalpm/hooks/`. So we shadow the broken
system hook with one that calls the op the installed dispatcher supports.

Installed at **`/etc/pacman.d/hooks/dbus-reload.hook`** (root-owned, `0644`):

```ini
# Local override for the broken system hook shipped by dbus-openrc 20260324-1.
# System hook calls `openrc-hook reload dbus`, but openrc 0.63.3-2's dispatcher
# only implements `dbus_reload`, so `reload` errors out. Same basename → wins by
# HookDir precedence (/etc/pacman.d/hooks over /usr/share/libalpm/hooks).
# REMOVE once Artix resyncs the packages — see the dated doc's Watch List.

[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Operation = Remove
Target = etc/dbus-1/system.d/*.conf
Target = usr/share/dbus-1/system.d/*.conf
Target = usr/share/dbus-1/system-services/*.service

[Action]
Description = Reloading system bus configuration...
When = PostTransaction
Exec = /usr/share/libalpm/scripts/openrc-hook dbus_reload
```

Validated: the fixed op exits 0 as root and performs the reload; the old form
still errors. On the next update that touches a dbus system `.conf`, pacman runs
this override cleanly and silently.

To reproduce the install on a fresh machine:

```sh
sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/dbus-reload.hook <<'EOF'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Operation = Remove
Target = etc/dbus-1/system.d/*.conf
Target = usr/share/dbus-1/system.d/*.conf
Target = usr/share/dbus-1/system-services/*.service

[Action]
Description = Reloading system bus configuration...
When = PostTransaction
Exec = /usr/share/libalpm/scripts/openrc-hook dbus_reload
EOF
```

## 5. Laptop (`nomad-artix`) — upstream fix has already landed here (2026-08-06)

**No override needed on the laptop.** Confirmed 2026-08-06 that the upstream
patch (§7) has shipped in the laptop's `dbus-openrc` package:

```
pacman -Q openrc dbus-openrc
  openrc 0.63.3-2
  dbus-openrc 20260804-2                # ↑ from the broken 20260324-1

grep Exec /usr/share/libalpm/hooks/dbus-reload.hook
  Exec = /usr/share/libalpm/scripts/openrc-hook dbus_reload
                                                ^^^^^^^^^^^ underscore, not `reload`
```

The rewritten hook calls `dbus_reload` (the verb openrc's dispatcher
actually implements), matching what §4's override does — so the local shim
would silently shadow a *correct* system hook. Leave the laptop without
the `/etc/pacman.d/hooks/dbus-reload.hook` override.

This is the "closure" the Watch List (§6) was waiting for: whichever machine
now updates to `dbus-openrc 20260804-2` or later can drop its local override.
When the desktop next runs a full upgrade, the same removal applies there.

*Original prescription (kept for the historical record — was correct at
20260324-1 time):*

> The laptop is the same Artix/OpenRC stack and will hit the identical error
> the first time it updates a package that ships a dbus system policy file.
> Apply the exact same override there (the `install -Dm644` block in §4).

## 6. TEMPORARY — Watch List / re-evaluate

**This override is a shim, pinned to the versions that were current when it was
written:**

| Package       | Version at fix time |
|---------------|---------------------|
| `dbus-openrc` | **20260324-1**      |
| `openrc`      | **0.63.3-2**        |

**Any new `dbus-openrc` (or `openrc`) version means this "fix" must be
re-evaluated** — the desync may be gone, in which case the override now silently
shadows a *correct* system hook and should be removed.

**Heads-up: the upstream fix is already in flight.** The Artix forum patch (§7)
reroutes `dbus-openrc` to source `dbus-reload.hook` from the shared `alpm-hooks`
repo, and it's maintainer-liked — so expect a `dbus-openrc` rebuild (new
`pkgrel`/`pkgver`) that makes the *system* hook call `dbus_reload` on its own.
When that lands, check #2 below flips and the override comes out.

**Re-evaluate on/after 2026-09-03** (≈ one month out) — or immediately whenever
`dbus-openrc` changes version, whichever comes first. Check:

```sh
# 1. Did the packages move?
pacman -Q openrc dbus-openrc

# 2. What does the *system* hook now call?
grep Exec /usr/share/libalpm/hooks/dbus-reload.hook
#    - if it now says `dbus_reload`, the packages resynced → remove the override.

# 3. Does the dispatcher now understand a generic `reload` verb?
grep -E 'reload\)|dbus_reload\)' /usr/share/libalpm/scripts/openrc-hook
```

**When resynced, remove the shim (both machines):**

```sh
sudo rm /etc/pacman.d/hooks/dbus-reload.hook
```

Then run one update to confirm the system hook fires clean on its own.

(Passive doc-based reminder by preference — no cron / scheduled agent.)

## 7. Upstream status — already reported + patched (nothing to file)

Artix's Gitea issue tracker is **closed** (issues disabled), so there is nowhere
to file this — and it doesn't matter, because the bug is **already reported and
patched on the Artix forum**, independently confirming this doc's diagnosis and
fix.

- **Thread:** https://forum.artixlinux.org/index.php/topic,10203.msg61127.html
  — posted 2026-08-03 by `conlogic`, "liked" by `dr-kart` and `Dju`.
- The poster's correction is verbatim ours: *"For the current version of the
  `openrc` package this call should be `dbus_reload`."*
- **Root-cause upstream fix (patch posted):** a `dbus-openrc` PKGBUILD change
  that stops hard-wiring dbus-openrc's own copy of `dbus-reload.hook` and instead
  pulls the shared hook from the `alpm-hooks` repo
  (`git+https://gitea.artixlinux.org/artix/alpm-hooks.git#tag=3.0`) — the same
  way the `openrc` package already sources its hooks. That de-duplication is what
  stops the two packages drifting again. (The patch also notes `alpm-hooks`'
  Makefile `.PHONY` list is missing `install_openrc_dbus`.)

So: **do not file a bug** — the tracker is closed and the issue is already
handled upstream. The only remaining action is to watch for the `dbus-openrc`
rebuild that ships this patch, then remove our override per §6.
