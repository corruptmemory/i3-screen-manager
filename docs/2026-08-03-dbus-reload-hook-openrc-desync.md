# pacman `Invalid operation 'reload'` — dbus-openrc / openrc hook desync

**Date:** 2026-08-03
**Machine:** `godlike-artix` (desktop). **`nomad-artix` (laptop) will hit the
same bug and needs the same fix — see §5.**
**Status:** TEMPORARY local override applied. Re-evaluate on the next
`dbus-openrc` bump (see §6 Watch List).

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

## 5. Laptop (`nomad-artix`) needs the same fix

The laptop is the same Artix/OpenRC stack and will hit the identical error the
first time it updates a package that ships a dbus system policy file. Apply the
exact same override there (the `install -Dm644` block in §4). Before applying,
sanity-check the versions still match §2:

```sh
pacman -Q openrc dbus-openrc
grep Exec /usr/share/libalpm/hooks/dbus-reload.hook   # still `reload dbus`?
```

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

## 7. Bug report (filed upstream)

Filed at Artix Gitea — the OpenRC packages repo: **
https://gitea.artixlinux.org/artixlinux/packages-openrc/issues **

> **Title:** dbus-openrc 20260324-1: dbus-reload.hook calls `openrc-hook reload
> dbus`, unsupported by openrc 0.63.3-2 dispatcher → "Invalid operation 'reload'"
>
> **Body:**
>
> Every post-transaction that touches a D-Bus system policy file fails the
> dbus-reload hook:
>
> ```
> (5/5) Reloading system bus configuration...
>   Invalid operation 'reload'
> error: command failed to execute correctly
> ```
>
> **Cause:** `dbus-reload.hook` (dbus-openrc 20260324-1) runs:
>
> ```
> Exec = /usr/share/libalpm/scripts/openrc-hook reload dbus
> ```
>
> but the `openrc-hook` dispatcher shipped by openrc 0.63.3-2 has no `reload`
> operation. Its `case` implements only `sysctl | dbus_reload | reexec |
> restart | add | del | uadd | udel`, so `reload` hits the `*)` catch-all and
> exits 1.
>
> **Reproduce:**
>
> ```
> $ /usr/share/libalpm/scripts/openrc-hook reload dbus
>   Invalid operation 'reload'   # exit 1
> $ /usr/share/libalpm/scripts/openrc-hook dbus_reload
>   # exit 0 — this is the op the dispatcher actually supports
> ```
>
> Both packages are at the newest repo versions, so updating cannot resolve it —
> the two packages are out of sync. Either dbus-openrc's hook should call
> `dbus_reload` (matching the current dispatcher), or openrc's `openrc-hook`
> needs a generic `reload` verb to match the hook.
>
> **Versions:** openrc 0.63.3-2, dbus-openrc 20260324-1 (Artix, OpenRC).
