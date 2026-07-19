# Kitty → Ghostty terminal swap (+ palette alignment)

Making **Ghostty** the terminal behind `Super+Return` on every machine and every
WM, and making its colors indistinguishable from Kitty's so the switch is
invisible. Kitty stays installed — nothing was uninstalled and every change is a
one-line revert.

- **`godlike-artix` (desktop):** DONE 2026-07-19.
- **`nomad-artix` (laptop):** config committed, **not yet deployed** — needs the
  §4 steps (`git pull` alone is not enough; Ghostty's config is copy-deployed,
  not symlinked).

Two independent problems were solved here. They're documented separately because
they fail in completely different ways:

1. **Colors** — Ghostty was showing a *different scheme entirely*, for a reason
   that had nothing to do with the palette values (§1).
2. **Identity** — Ghostty refuses the `--class` idiom Kitty used, and does it
   *silently* (§2).

---

## 0. Status of verification (what is proven vs. assumed)

Everything below was changed from an **IceWM/X11 session**, so the X11 path is
directly verified and the Wayland path is verified only at the config layer.
Be honest about which is which before trusting this doc:

| Claim | How verified | Confidence |
| --- | --- | --- |
| All 16 ANSI colors + fg/bg/selection/cursor match Kitty | mechanical diff of `ghostty +show-config` vs `kitty.conf` | **proven** |
| `--class=` is accepted and applied | `xprop` on a live window | **proven** |
| `--x11-instance-name=` sets the WM_CLASS instance | `xprop` on a live window | **proven** |
| Hyprland float rule matches the floating terminal | app_id == the verified `--class` value; rule not exercised live | *inferred* |
| IceWM `winoptions` keeps the title bar on the floater | token == the verified instance name; needs `icewm --restart` | *inferred* |

The two *inferred* rows are the ones to eyeball on next Hyprland boot / IceWM
restart.

---

## 1. Colors: why they didn't match (it wasn't the palette)

### 1a. Kitty is Dracula **Pro**, not Dracula

`~/.config/kitty/kitty.conf` runs the paid **Dracula Pro** palette — `#ff9580`
red, `#8aff80` green, `#9580ff` blue, `#ff80bf` magenta, `#80ffea` cyan — on a
background darkened further from Dracula Pro's stock `#22212c` to **`#12111c`**.

Ghostty's config said `theme = Dracula`, which is the **free** Dracula that
Ghostty ships as a built-in: `#282a36` background, `#ff5555` red. Different
scheme. These were never going to converge by tweaking.

### 1b. The repo had a fix that was never deployed

`dotfiles/.config/ghostty/themes/Dracula` existed in git — but
`~/.config/ghostty/` had **no `themes/` directory at all**. Ghostty found no user
theme by that name and fell through to its built-in `Dracula (resources)`.

This is the failure mode of **copy-deployment**: `hypr` and `.icewm` are
symlinked into the repo, so they cannot drift, but `kitty` and `ghostty` are
plain copies. A file committed to the repo is *not* a file that is live. See §5.

### 1c. GOTCHA: Ghostty has no trailing comments

The first draft of the theme wrote:

```
palette = 0=#32313c               # black
```

Ghostty parses everything after `=` as the value, so the comment became part of
it, the value failed to parse, and **the line was dropped silently — no warning,
no error, just a fallback to the built-in default.** Entries 8–15 had no trailing
comment and applied correctly, which is what made the bug visible: a half-applied
palette.

**Only whole-line `#` comments are safe in Ghostty config.**

The lesson generalises past comments: Ghostty's config parser drops bad lines
quietly. Never trust the file — `ghostty +show-config` prints what actually
resolved, and is the only ground truth:

```bash
ghostty +show-config | grep -E '^(theme|background|foreground|selection|cursor-)'
```

### 1d. The theme

Palette lives at `dotfiles/.config/ghostty/themes/dracula-pro`, mirrored 1:1 from
`kitty.conf`. Nothing generates it — **if you retune Kitty, retune this file in
the same commit.**

One non-obvious entry: Kitty leaves `cursor` commented out, so it falls through
to Kitty's own built-in default `#cccccc`. That value is hardcoded into the theme
because Ghostty's default differs; matching required copying Kitty's *default*,
not Kitty's *config*.

Verify a claimed match mechanically rather than by eye:

```bash
grep -oE '^color[0-9]+[[:space:]]+#[0-9a-fA-F]{6}' ~/.config/kitty/kitty.conf \
  | sed -E 's/^color([0-9]+)[[:space:]]+#(.*)/\1 \L\2/' | sort -n > /tmp/k.txt
ghostty +show-config | grep -oE '^palette = ([0-9]|1[0-5])=#[0-9a-fA-F]{6}' \
  | sed -E 's/^palette = ([0-9]+)=#(.*)/\1 \L\2/' | sort -n > /tmp/g.txt
diff /tmp/k.txt /tmp/g.txt && echo "IDENTICAL"
```

---

## 2. The one gotcha that drives every config edit: Ghostty's `class`

Kitty tagged its floating scratch terminal with `--class KittyFloating`. **That
idiom does not port.** Ghostty requires `class` to be a valid **GTK application
ID** — which must contain at least one dot. Given a dotless name it logs:

```
warning(gtk_ghostty_application): invalid 'class' in config, ignoring
```

…and proceeds with the **default** app_id. The window still opens, so it looks
like it worked — but it no longer matches the float rule, so the floating
terminal silently starts tiling. Classic quiet failure.

Worse, the obvious fix (`--class=com.mitchellh.ghostty.Floating`) is **unusable
under IceWM**, because dots are `winoptions`' own field separator
(`NAME.CLASS.OPTION`). A dotted class is literally unmatchable there.

So the two WMs use two different identity knobs. This is inherent to X11 vs
Wayland, not sloppiness:

| Launch | WM_CLASS instance | WM_CLASS class / Wayland app_id | Used by |
| --- | --- | --- | --- |
| `ghostty` | `ghostty` | `com.mitchellh.ghostty` | `Super+Return`, swallow regex |
| `ghostty --class=com.mitchellh.ghostty.Floating` | `ghostty` | **`com.mitchellh.ghostty.Floating`** | Hyprland float rule |
| `ghostty --x11-instance-name=ghostty-floating` | **`ghostty-floating`** | `com.mitchellh.ghostty` | IceWM `winoptions` |

Read the live identity yourself (no guessing):

```bash
ghostty --x11-instance-name=ghostty-floating -e sleep 25 &
sleep 5
for wid in $(xdotool search --classname ghostty-floating); do
  xprop -id "$wid" WM_CLASS
done
# Expect: "ghostty-floating", "com.mitchellh.ghostty"
```

Both regexes are `$`-anchored, so `com.mitchellh.ghostty` and
`com.mitchellh.ghostty.Floating` cannot cross-match — main windows tile, the
floater floats.

**Single-instance is not a problem.** A `ghostty --gtk-single-instance=true`
daemon may already be running (D-Bus activation from the `.desktop` file). A
launch with a *different* `--class` registers its own GTK application ID rather
than handing off, so per-window identity still applies — verified by `xprop`
with such a daemon live.

---

## 3. What changed

Six files in `~/projects/dotfiles`, all symlinked live except the Ghostty pair:

| File | Change |
| --- | --- |
| `.config/ghostty/themes/dracula-pro` | **new** — palette mirrored from `kitty.conf` |
| `.config/ghostty/config` | `theme = Dracula` → `theme = dracula-pro` |
| `.config/hypr/hyprland-{desktop,laptop}.lua` | `terminal` → `"ghostty"`; new `termFloat` local; swallow regex; float `window_rule`; `special:terminal` workspace rule; `SHIFT+return` bind |
| `.config/hypr/hyprland-{desktop,laptop}.conf` | same five, via `$terminal` / new `$termFloat` |
| `.icewm{,-laptop}/keys` | `Super+Return` → `ghostty`; `Super+Shift+Return` → `ghostty --x11-instance-name=ghostty-floating` |
| `.icewm{,-laptop}/winoptions` | `KittyFloating.dTitleBar` → `ghostty-floating.dTitleBar` |

The floating-terminal command is factored into one variable (`termFloat` /
`$termFloat`) per config because it must stay in lockstep with the float
`window_rule` regex — they are two halves of one fact.

Both Lua configs pass `luac -p`. Run it after any edit; Hyprland's Lua mode will
otherwise fail at load with a much less obvious message:

```bash
luac -p ~/projects/dotfiles/.config/hypr/hyprland-{desktop,laptop}.lua
```

---

## 4. Deploying to the laptop (`nomad-artix`)

`git pull` is **necessary but not sufficient** — Ghostty is copy-deployed.

```bash
# 0. Prerequisite: is Ghostty even installed? (official repo, not AUR)
command -v ghostty || sudo pacman -S ghostty

# 1. Symlinked configs (hypr, .icewm-laptop) go live for free:
cd ~/projects/dotfiles && git pull

# 2. Ghostty is NOT symlinked — copy it, including the themes dir:
mkdir -p ~/.config/ghostty/themes
cp ~/projects/dotfiles/.config/ghostty/config          ~/.config/ghostty/config
cp ~/projects/dotfiles/.config/ghostty/themes/dracula-pro ~/.config/ghostty/themes/dracula-pro

# 3. Confirm the theme actually resolved (see §1c — silent drops):
ghostty +show-config | grep -E '^(theme|background|foreground)'
# expect: theme = dracula-pro / background = #12111c / foreground = #f8f8f2

# 4. Reload whichever WM is live:
icewm --restart      # IceWM: `icesh` has NO restart verb — this is the command
# Hyprland: picks up the symlinked config at next session start
```

---

## 5. Open items / watch list

- **Font sizes still differ** — Kitty `font_size 14.0`, Ghostty `font-size 15`.
  Deliberately left alone (the ask was colors), but Ghostty renders noticeably
  larger side by side. Align whichever direction you prefer.
- **`themes/Dracula` is now dead weight** in the repo. It never applied (§1b) and
  it shadows a Ghostty built-in name, so it is actively confusing. Retained only
  because it predates this change; delete when convenient.
- **Copy-deployment is the root cause of §1b and will bite again.** Symlinking
  `~/.config/ghostty` → the repo (as `hypr` and `.icewm` already are) would make
  the whole class of "committed but not live" bugs structurally impossible. Same
  argument applies to `~/.config/kitty`.
- **Kitty is still installed and fully configured.** Reverting is a one-line
  change to `terminal` / `$terminal` plus the float class in each config.
