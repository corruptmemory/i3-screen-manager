# Hyprland rofi parity + rofi-rbw ydotool fix (2026-08-29)

**Machine:** `nomad-artix` live Hyprland session, same afternoon as the unified-config
laptop cutover (`2026-08-29-hyprland-unified-config-design.md` §10) and the
Quickshell+tensaku parity graduation
(`2026-08-28-quickshell-bar-and-screenshots-laptop-parity.md`).
**Scope:** Fleet-wide (both machines). Audit compared the i3/X11 rofi surface
against the unified Hyprland `bindings.lua` and each script's compositor-safety,
then closed the three gaps found.

## 1. Why now

The laptop cutover was framed as *behavior-preserving* — the bridge kept
waybar/flameshot, then graduated to qs/tensaku the same session. The audit was
next: whatever rofi bindings the laptop's i3 config had, the Hyprland side
needed the same. Muscle memory doesn't care which compositor you booted.

## 2. The parity audit

**Enumeration:** `grep -nE "bindsym.*rofi|bindsym.*i3-.*-(rofi|manager)"` over
each i3 config, cross-referenced against `bindings.lua`. Every referenced
script inspected for compositor-safety (either explicit `$XDG_SESSION_TYPE`
dispatch, or documented as compositor-agnostic).

**Result — every i3 rofi binding across both configs:**

| Function                | i3 keybind                | Script                                    |
|-------------------------|---------------------------|-------------------------------------------|
| Password (rofi-rbw)     | `$mod+Shift+b`            | `rofi-rbw`                                |
| Mouse DPI               | `$mod+Mod1+m`             | `i3-mouse-rofi`                           |
| Screen manager          | `$mod+BackSpace`          | `i3-screen-rofi`                          |
| Keymap toggle           | `$mod+Control+BackSpace`  | `i3-keyboard-rofi`                        |
| Tailscale (laptop-only) | `$mod+Shift+n`            | `i3-tailscale-rofi`                       |
| App launcher            | `$mod+space`              | `rofi -modi drun,run -show drun`          |
| Emoji picker            | `$mod+Control+space`      | `~/.config/rofi/scripts/emoji`            |

**Gaps in the unified Hyprland `bindings.lua`:**

1. `SUPER + ALT + M` → `i3-mouse-rofi` — MISSING (both i3 configs bound it).
2. `SUPER + CONTROL + Space` → emoji picker — MISSING (both i3 configs bound it).

Both were silent losses from the original i3→Hyprland port on each machine.

**Compositor-safety per script:**

| Script                              | Wayland-safe?                                              |
|-------------------------------------|-----------------------------------------------------------|
| `i3-screen-rofi`                    | Delegates to `i3-screen-manager` (already dual-compositor) |
| `i3-screen-manager`                 | `$XDG_SESSION_TYPE` dispatch (documented CLAUDE.md)        |
| `i3-keyboard-rofi`                  | Explicit `is_wayland()` → `hyprctl keyword input:kb_options` |
| `i3-mouse-rofi`                     | HID-level via `solaar` — compositor-agnostic               |
| `i3-tailscale-rofi`                 | Network+tailscale+notify-send — compositor-agnostic        |
| `rofi-rbw` (auto-typer)             | ⚠️ auto-picks `wtype` on Wayland — mangles layout-dep chars |
| `~/.config/rofi/scripts/emoji`      | ⚠️ hardcoded `xclip -selection clipboard` — X11-only        |

Three fixes needed: two restored binds + two Wayland compat patches.

## 3. Fix 1 — restore the two missed rofi binds

`bindings.lua` (unified) gained two lines:

```lua
hl.bind(mod .. " + ALT + M",             hl.dsp.exec_cmd("i3-mouse-rofi"))
hl.bind(mod .. " + CONTROL + Space",     hl.dsp.exec_cmd("~/.config/rofi/scripts/emoji"))
```

Both shared (no machine branch) — both machines have a solaar mouse and both
want the emoji picker. Bind count 90 → 92.
Commit: dotfiles `daa3797`.

## 4. Fix 2 — emoji picker dual-compositor

`~/.config/rofi/scripts/emoji` was pinned to `xclip -selection clipboard` from
the 2026-07-29 rewrite (see companion doc). XWayland's clipboard bridge is
unreliable enough that the correct Wayland answer is `wl-copy`. Same session-
dispatch pattern the other scripts use:

```sh
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    _require rofi wl-copy
    COPY=(wl-copy)
else
    _require rofi xclip
    COPY=(xclip -selection clipboard)
fi
...
printf '%s' "$glyph" | "${COPY[@]}"
```

`_require` still gates on the specific tool selected — silent-failure hygiene
intact on both sides. Commit: dotfiles `57b1a42`.

## 5. Fix 3 — rofi-rbw auto-type via `ydotool`

The CLAUDE.md backlog note had scoped this as a bigger change (session-dispatch
wrapper at `~/.local/bin/rofi-rbw-dispatch`, udev rule setup, uinput group,
repointing four hypr configs + two icewm keys files + two i3 configs). The
actual fix collapsed to two lines because of two discoveries:

### Discovery 1 — elogind already grants a per-user ACL on `/dev/uinput`

```
$ getfacl /dev/uinput
# file: dev/uinput
# owner: root
# group: root
user::rw-
user:jim:rw-        <-- elogind session-manager set this
group::---
mask::rw-
other::---
```

That `+` in `ls -l` output on `/dev/uinput` is the ACL flag. Discovery removed
the whole "install udev rule → `KERNEL=="uinput", GROUP="uinput", MODE=0660` →
add user to uinput group → reload" step from the plan. `ydotoold` can open
`/dev/uinput` as `jim` immediately, no setup. **This is elogind's default seat
behavior; not something I configured — the fleet gets it for free.**

### Discovery 2 — the wrapper script wasn't needed

The backlog plan called for a session-dispatch wrapper so all bind sites could
share one script that reads `$XDG_SESSION_TYPE`. But bindings are per-config:

- Hyprland `bindings.lua` fires only under Wayland (Hyprland IS Wayland).
- i3 `config-*` fires only under X11 (i3 IS X11).
- icewm `keys` fires only under X11 (icewm IS X11).

Each config already knows its compositor. So each config can just pass the
right `--typer` in its bind — no runtime dispatch needed. The wrapper's
raison d'être evaporated.

### The actual fix

`bindings.lua`:
```lua
-- --typer ydotool: wtype (rofi-rbw's Wayland auto-pick) synthesizes keysyms
-- and mangles layout-dependent characters; ydotool goes through /dev/uinput
-- and injects real scancodes, so the kernel input layer does the mapping
-- like a physical keyboard would.
hl.bind(mod .. " + SHIFT + B",       hl.dsp.exec_cmd("rofi-rbw --typer ydotool"))
```

`autostart.lua`:
```lua
-- shared daemons
hl.exec_cmd("udiskie")
hl.exec_cmd("flameshot")
hl.exec_cmd("hypridle")
hl.exec_cmd("ydotoold")
```

i3/icewm bind sites **left alone** — under X11 rofi-rbw auto-picks `xdotool`
and works correctly (per CLAUDE.md's "do NOT fix the X11 path" warning).

Package: `ydotool 1.0.4-2` from `extra` (rung-1). Client `ydotool` uses
`ydotoold`'s Unix socket at `$XDG_RUNTIME_DIR/.ydotool_socket` by default
(no env var needed).

### Why `ydotool` and not `wtype`

`wtype` uses `zwp_virtual_keyboard_v1` to send *keysyms*, which the compositor
then maps through the current keymap. Layout mismatches (dead keys, non-US
symbols in the password) → garbled output. `ydotool` sends *scancodes* via
`/dev/uinput`, so the kernel input layer does the mapping — the same path a
real Bluetooth keyboard takes. This is architectural in wtype, not a bug they
can fix.

Commit: dotfiles `b41015f`.

## 6. Live verification

```
ydotoold:  pid 1330, session leader (SID 1330), /dev/uinput on fd 3
socket:    /run/user/1000/.ydotool_socket (owned by jim, 0600)
device:    /proc/bus/input/devices → "ydotoold virtual device"
bindings:  92 total in hyprctl binds (was 90); B/mod=65, M/mod=72, Space/mod=68 all present
configerrors: none
```

Live end-to-end test (`ydotool type "..."` into a focused text field) deferred
to the user — requires a real GUI focus target this remote session can't
reliably provide.

## 7. What was NOT changed (deliberate)

- **i3 `config-{desktop,laptop}` rofi bindings** — auto-pick xdotool on X11, works.
- **icewm `.icewm/keys` + `.icewm-laptop/keys`** — same, auto-pick xdotool.
- **The wrapper script `~/.local/bin/rofi-rbw-dispatch`** — never created; not needed.
- **Any udev rule for uinput** — elogind's ACL supersedes.
- **The four legacy `hyprland-{desktop,laptop}.{lua,conf}` files** — kept as
  the unified-config revert path; the active `bindings.lua` supersedes them.

## 8. Docs updated in the same pass

- `CLAUDE.md` — the `rofi-rbw` "BACKLOG" bullet flipped to "RESOLVED
  2026-08-29 via ydotool"; the "no udev rule needed" and "no wrapper needed"
  simplifications recorded (`f37e7bf`).
- `README.md:217` — the user-facing statement "types the credential (via
  `wtype` on Wayland)" corrected to `ydotool`.
- `docs/2026-07-29-rofi-emoji-picker-fix.md` — top-of-doc "SUPERSEDED IN
  PART" pointer added: the xclip hardcode described there is now a session
  dispatch (this doc §4).

## 9. Commits

| Repo                 | Hash     | Subject                                                   |
|----------------------|----------|-----------------------------------------------------------|
| dotfiles             | `daa3797` | feat(hypr): restore two i3-era rofi binds missed in the cutover |
| dotfiles             | `57b1a42` | fix(rofi/emoji): use wl-copy under Wayland (xclip on X11) |
| dotfiles             | `b41015f` | feat(hypr): rofi-rbw auto-type via ydotool                |
| i3-screen-manager    | `f37e7bf` | docs(claude.md): mark rofi-rbw ydotool fix as resolved    |
| i3-screen-manager    | (this doc + README + emoji-doc pointer, one commit)       |

## 10. Follow-ups

- **User must confirm `ydotool` types cleanly** with a real Bitwarden entry
  in a real text field. Especially: symbols, dead-key territory, anything
  that historically exposed wtype's mapping issues.
- On next full Hyprland session start, `ydotoold` will be launched by
  `autostart.lua` (this session's copy was started manually with `setsid` so
  it survives the ssh exit). Verify with `pgrep ydotoold` after re-login.
- Rofi-rbw's other actions (`copy`, default `type`) still route through
  ydotool under Wayland now — should also work but not exercised.

## 11. Reference

- Bindings.lua unified config: `~/projects/dotfiles/.config/hypr/bindings.lua`
- Autostart with ydotoold: `~/projects/dotfiles/.config/hypr/autostart.lua`
- Emoji picker with dual-compositor dispatch: `~/.config/rofi/scripts/emoji`
  (dotfiles-tracked at `.config/rofi/scripts/emoji`)
- `getfacl /dev/uinput` on both machines to verify elogind ACL is present
  (if it isn't for some reason, add a udev rule per the earlier plan).
