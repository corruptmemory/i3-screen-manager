# rofi emoji picker — root-cause + fix (2026-07-29)

`Super+Control+space` showed a rofi window whose only row was **"Do not launch rofi
from inside rofi."** instead of an emoji menu. Diagnosed on `godlike-artix`
(i3/X11); the fix is in the shared dotfiles, so **the laptop (`nomad-artix`) needs
the redeploy steps in §5.**

---

## 1. Symptom

Keybind `bindsym $mod+Control+space exec "rofi -modi emoji -show emoji
-kb-secondary-copy '' -kb-custom-1 Ctrl+c"` → a rofi window titled `emoji`
containing one row: `Do not launch rofi from inside rofi.`

## 2. Root-cause analysis (the method, for next time)

That message is **rofi's own nested-launch guard**: when rofi spawns a child
process it exports `ROFI_OUTSIDE=<pid>`; if that child runs `rofi` again, the
second instance sees the variable and refuses. So the question was *why the emoji
rofi was already "inside rofi."* Steps:

1. **Confirmed the guard var and message live in the binary** (not some wrapper):
   `strings "$(command -v rofi)" | grep -iE 'inside rofi|ROFI_OUTSIDE'` → both present.
2. **Ruled out an environment leak** — if `ROFI_OUTSIDE` had leaked into i3's env,
   *every* rofi bind would break, not just emoji:
   `tr '\0' '\n' < /proc/$(pgrep -x i3)/environ | grep ROFI` → nothing. Clean.
3. **Read the binding**, then checked every way `-modi emoji` could resolve:
   - no `emoji` rofi plugin (`.so`) installed (`/usr/lib/rofi*` doesn't exist),
   - no custom `emoji` modi in the rofi config tree,
   - no `emoji` executable in `PATH`.
   Yet the window opened with rows — so `emoji` *was* resolving to something.
4. **Traced the actual exec chain** — the decisive step:
   ```
   strace -f -e trace=execve -qq timeout 3 rofi -normal-window \
       -modi emoji -show emoji  2>&1 | grep execve
   ```
   Showed:
   ```
   rofi -modi emoji -show emoji …
     └─ execve("/home/jim/.config/rofi/scripts/emoji", …)          # rofi ran the script AS the modi
          └─ execve("/usr/bin/rofi", ["rofi","-show","emoji","-modi","emoji", …])  # script re-ran rofi
   ```
   The child rofi inherited `ROFI_OUTSIDE` → guard fired → its stderr became the
   one row shown.

**Root cause.** `~/.config/rofi/scripts/emoji` was a *launcher* written for the
**rofi-emoji plugin** (`rofi -modi emoji`; the `-kb-secondary-copy ''`/`-kb-custom-1`
flags are copied from that plugin's docs). The plugin isn't installed — and rofi
2.0 **auto-discovers script modes by bare name from `~/.config/rofi/scripts/`**, so
`-modi emoji` resolved to *that very script*, which re-invoked `rofi -modi emoji`.
Self-referential; it could never work. (Secondary breakage: the script's `-theme`
pointed at `Themes/emojis.rasi` — wrong dir *and* filename; the real theme is
`global/emoji.rasi`.)

**Constraint that shaped the fix:** the `rofi-emoji` plugin and `rofimoji` are both
**AUR-only** → off-limits under the machine's AUR-malware policy. So the fix must be
self-contained (no plugin, no new package).

## 3. The fix (self-contained `rofi -dmenu` picker)

All in the shared dotfiles (`~/projects/dotfiles/.config/`):

| File | Role |
|---|---|
| `rofi/scripts/emoji` | rewritten → `rofi -dmenu` over a static list; copies the chosen glyph to the CLIPBOARD selection (`xclip`), toast via `notify-send`. Runs standalone — **no `-modi`**. |
| `rofi/emoji.txt` *(new)* | 1419 emoji, one `"<glyph> <name>"` per line, name-searchable (`shrug` → 🤷). |
| `rofi/gen-emoji.py` *(new)* | offline generator for `emoji.txt` (see §4). |
| `rofi/global/emoji.rasi` | grid theme → searchable **list** theme (a grid can't show searchable names). Base font is sans, so names read cleanly and emoji render via Pango fallback to the colour-emoji font. |
| `i3/config-desktop` `:121`, `i3/config-laptop` `:112` | binding → `exec --no-startup-id "$HOME/.config/rofi/scripts/emoji"` (run the script directly, not `rofi -modi emoji`). |

The picker (glyph extraction is `${sel%% *}` — the first space-delimited field, safe
because emoji clusters contain no spaces):

```bash
sel="$(rofi -dmenu -i -p emoji -theme "$THEME" < "$DATA")" || exit 0
[ -n "${sel:-}" ] || exit 0
printf '%s' "${sel%% *}" | xclip -selection clipboard
```

## 4. Regenerating `emoji.txt`

Offline, from the system Unicode data (no network, no AUR). Source:
`/usr/share/texmf-dist/tex/generic/unicode-data/emoji-data.txt` (UTS #51 v17,
shipped by texlive) for the emoji property set + Python `unicodedata` (UCD 16) for
names. It takes `Emoji_Presentation` codepoints as-is, plus text-default
pictographs (`Emoji ∧ Extended_Pictographic`, e.g. ❤ ✌ ☺) forced to emoji
presentation with `U+FE0F`, and skips digit/`#`/`*` keycap bases + components.

```bash
python3 ~/.config/rofi/gen-emoji.py ~/.config/rofi/emoji.txt   # → "wrote 1419 emoji"
```

Only needed to *regenerate* (e.g. a Unicode bump); the committed `emoji.txt` is
enough to just use. Regeneration needs the texlive `unicode-data` file present.

## 5. Laptop (`nomad-artix`) redeploy — REQUIRED

The i3 config is symlinked (binding updates on `git pull`), but **`~/.config/rofi`
is copy-deployed on both machines**, so the rofi files must be copied over:

```bash
cd ~/projects/dotfiles && git pull

# sanity: confirm rofi is a copy, not already a symlink
[ -L ~/.config/rofi ] && echo "symlinked — skip copies" || echo "copy-deployed — do the copies below"

cp .config/rofi/scripts/emoji     ~/.config/rofi/scripts/emoji
cp .config/rofi/global/emoji.rasi ~/.config/rofi/global/emoji.rasi
cp .config/rofi/emoji.txt         ~/.config/rofi/emoji.txt
cp .config/rofi/gen-emoji.py      ~/.config/rofi/gen-emoji.py
chmod +x ~/.config/rofi/scripts/emoji

i3-msg reload      # binding half is already live via the symlinked config
```

Then test: `Super+Control+space` → searchable list → pick → glyph on the clipboard
(`Ctrl+V` to paste). The picker is WM-agnostic — any WM can bind
`~/.config/rofi/scripts/emoji`; only i3 carried the broken binding here.

## 6. Reusable gotchas

- **rofi 2.0 auto-runs `~/.config/rofi/scripts/<name>` for `-modi <name>`** when
  `<name>` isn't a builtin/plugin. A launcher script sitting there that calls rofi
  will be run *as a modi* and nest.
- **"Do not launch rofi from inside rofi." = `ROFI_OUTSIDE` is set.** Either you're
  genuinely nested (a rofi-spawned child ran rofi), or the var leaked into the WM's
  environment. Check `/proc/<wm-pid>/environ` first to tell the two apart.
- **`strace -f -e trace=execve`** is the fastest way to see what a launcher *really*
  runs — it turned "why is this nested?" into a two-line answer.
- **rofi config drift:** `~/.config/rofi` is copy-deployed (not symlinked) on both
  machines — the same trap noted three times in `docs/2026-07-20-i3-x11-setup.md`.
  Symlinking the dir would end it; until then, changes need a manual copy per machine.

## 7. Verification used (desktop)

`i3 -C -c ~/.config/i3/config` (config valid) · `i3-msg reload` · clipboard
round-trip (`${sel%% *}` → `xclip` → `xclip -o`) · `timeout 2 rofi -dmenu -theme …`
opened with empty stderr (theme parses) · live `Super+Control+space` confirmed by
the user (✌️).

## 8. Follow-on: sibling rofi scripts all silent-fail the same way (2026-08-06)

The **laptop** first-boot of the picker exposed the same class of silent
failure differently: `xclip` was not installed on `nomad-artix`, so the
`printf '%s' "$glyph" | xclip -selection clipboard` line failed under
`set -euo pipefail` — the whole script exited zero-visible-output, the
picker just "vanished" after selection. No stderr, no notification, no clue.

**The fix scaled beyond this one script.** Every other rofi menu script in
the fleet has the same failure mode by construction — `set -euo pipefail` +
a shelled-out external tool = silent vanish on missing dep. Every script
below now guards its required tools at the top so a missing runtime dep
produces a visible `notify-send` + a stderr line instead of nothing:

| Script | Repo | Guards |
|---|---|---|
| `.config/rofi/scripts/emoji`                | dotfiles          | `rofi`, `xclip` |
| `.config/rofi/scripts/powermenu.sh`         | dotfiles          | `rofi`, `loginctl` |
| `.local/bin/icewm-window-switcher`          | dotfiles          | `rofi`, `icesh`, `xdotool` |
| `i3-keyboard-rofi`                           | i3-screen-manager | `rofi`; `hyprctl` / `setxkbmap` per compositor branch |
| `i3-mouse-rofi`                              | i3-screen-manager | `rofi` (existing `rofi -e` guard on `solaar` retained for its richer per-mouse message) |
| `i3-screen-rofi`                             | i3-screen-manager | `rofi` |
| `i3-tailscale-rofi`                          | i3-screen-manager | `rofi`, `jq`, `tailscale` |

### The shared helper (added 2026-08-09)

The 12-line `_require` function was originally inlined verbatim into each of
the 7 scripts. Refactored to a shared library sourced by all consumers:

- **Source of truth:** `i3-screen-manager/lib/require.sh` — 12 lines, one
  function definition, well-commented.
- **Machine-local install:** `~/.local/lib/sh/require.sh` → the repo file.
  One-time symlink per machine; recorded in each setup doc's "one-time
  machine setup (symlinks)" section.
- **Consumer pattern** (verbatim in every consumer script):
  ```bash
  . "$HOME/.local/lib/sh/require.sh"
  _require rofi …
  ```
- **Bootstrap failure mode:** if the symlink is missing (or broken), a
  script that sources the file will crash with
  `bash: /home/…/require.sh: No such file or directory` and (under
  `set -euo pipefail`) exit non-zero. Scripts without pipefail
  (`powermenu.sh`) surface the same bash error and then hit
  `_require: command not found` on the next line. Either way, no silent
  vanish — the bootstrap failure is at least as visible as the
  missing-tool-arg failure it exists to prevent.

**Why not relative-source from the script's own location?** The scripts
live in two different repos and are invoked via symlinks in
`~/.local/bin/` / `~/.config/rofi/scripts/`. `$0` at run time points at
the symlink, not the source file, so a relative-source lookup would need
`readlink -f "$0"` + a `$(dirname …)/../lib/require.sh` chain — brittle
and different in each repo's directory structure. A stable machine-local
absolute path is the simplest thing that could possibly work.

**Why not source into dotfiles?** i3-screen-manager owns 4 of the 7
consumers and is more of a "toolkit" than dotfiles, which is more of a
general bin/config store. i3-screen-manager was the natural home. Either
would have worked; the pattern is that ONE of the two repos owns it and
the other sources through the stable machine-local path.

**Reusable takeaway:** any shell script that runs under `set -euo pipefail`
and shells out to non-universal tools should guard those tools at the top.
The `set -eu` discipline gives you crash-on-bug for logic errors but silently
converts missing-tool errors into empty output. `command -v` guards + a visible
side channel (notify-send / rofi -e) turn "menu vanishes" back into a
diagnosable event.
