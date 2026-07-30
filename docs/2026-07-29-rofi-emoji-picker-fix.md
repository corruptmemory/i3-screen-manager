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
