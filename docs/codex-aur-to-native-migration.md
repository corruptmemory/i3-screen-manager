# Codex CLI: AUR → native ("official upstream") migration runbook

**Status:** `godlike-artix` (desktop) — **DONE 2026-06-19**. `nomad-artix` (laptop) — **PENDING** (assume it still has `openai-codex-bin`).
**Author:** the desktop's Claude Code, after performing the swap.
**Audience:** the next instance that runs this on the laptop. Read this first.

> **Why this migration exists.** Same rationale as the Claude Code one
> (`claude-code-aur-to-native-migration.md`): the June 2026 "Atomic" AUR
> supply-chain compromise (see `aur-malware-check`) means Jim is avoiding AUR
> package updates. Codex was installed from the AUR (`openai-codex-bin`). This
> switches it to OpenAI's official installer
> (`curl -fsSL https://chatgpt.com/codex/install.sh | sh`), whose standalone
> layout **self-updates from OpenAI's own channel** — so Codex stays current
> without ever touching the AUR again.

---

## TL;DR — the correct order

```text
1. Pre-flight (read-only): confirm package shape + config locations + PATH.
2. (Optional but habitual on Artix) dry-run the removal:  pacman -Rsp openai-codex-bin
3. Remove the AUR package:                                sudo pacman -R --noconfirm openai-codex-bin
4. Install native (can be run right here — see "Key difference" below):
                                                          curl -fsSL https://chatgpt.com/codex/install.sh | sh
5. Verify:                                                codex --version ; readlink -f (command -v codex) ; codex login status
6. Restore shell completions (native installer ships none): codex completion fish > ~/.config/fish/completions/codex.fish
```

---

## Key difference from the Claude Code migration: NO clean-terminal hand-off

The Claude Code runbook's two hardest constraints were both **claude-code-specific**
and **do not apply to Codex**:

- **No nested-session problem.** The Claude installer detects when it's run from
  inside a running Claude Code session (process-tree based) and no-ops the
  auto-updater. The Codex installer has **no such detection** — it just downloads,
  symlinks, and exits. So you can run it directly from inside a Claude Code
  session (which is how the desktop migration was done). Codex is not the tool
  running the session, so there is nothing to self-modify.
- **No "administrator-managed" deferral.** Claude disables its user auto-updater
  if a root-owned global install is present. The Codex installer has no such
  logic. Removing the AUR package first is therefore about **cleanliness / PATH
  unambiguity**, not a hard precondition.

The one habit that carries over: **remove the AUR package before installing**, so
there is exactly one `codex` on the system and PATH order is unambiguous.

---

## Key findings / gotchas

### 1. Configs are install-method-independent — the migration is config-safe
`openai-codex-bin` owns **only files under `/usr/`** (the binary at
`/usr/bin/codex` plus shell completions under `/usr/share/...`) — **nothing under
`$HOME`**. Your entire `~/.codex/` (`config.toml`, `auth.json`, `sessions/`,
`skills/`, `memories/`, the sqlite state/log DBs, `history.jsonl`) is untouched by
both the removal and the install. After the swap the native binary reads the same
`~/.codex/` and everything just works — verified on the desktop with
`codex login status` → **"Logged in using ChatGPT"** (the pre-existing `auth.json`
was read unchanged).

### 2. The installer's own conflict detector will NOT remove the AUR package for you
The script's `classify_existing_codex` only recognizes **npm**, **bun**, or
**Homebrew** installs (it greps for a `#!/usr/bin/env node` shim, or matches
`/opt/homebrew` / `/usr/local` on macOS). The AUR `/usr/bin/codex` is a **native
ELF binary**, so it is classified as "not managed" → the installer leaves it in
place and installs `~/.local/bin/codex` alongside it. Because `~/.local/bin` is
first on PATH, the new one *would* win regardless — but to avoid two codices,
**remove the AUR package yourself with `pacman -R` first.**

### 3. Native layout — point things at the stable launcher, never the versioned dir
```text
~/.local/bin/codex                                  → symlink →
  ~/.codex/packages/standalone/current              → symlink →
    ~/.codex/packages/standalone/releases/<ver>-x86_64-unknown-linux-musl/bin/codex
```
Self-update drops a new `releases/<next>` and repoints `current`, so the visible
`~/.local/bin/codex` symlink stays stable. Anything that references codex should
use `~/.local/bin/codex`, not the versioned release path.

### 4. It's the musl static build — fine on glibc Artix
Linux x64 resolves to the `x86_64-unknown-linux-musl` asset. A statically-linked
musl binary runs fine on a glibc system; no compatibility concern on Artix.

### 5. The installer won't touch your fish config (and didn't need to)
`add_to_path` early-returns when `$BIN_DIR` (`~/.local/bin`) is already on `$PATH`
— which it is on both machines (it's first). Even if it hadn't been, the
installer's profile-writer only knows `~/.bashrc` / `~/.zshrc` / `~/.profile`
(it has no fish branch), so it would have written `~/.profile`, not fish config.
On the desktop run it wrote nothing — `path_action=already`.

### 6. Strong download verification (a reason to trust the `curl | sh`)
The script downloads `codex-package_SHA256SUMS`, verifies **that file's** digest
against the GitHub API release metadata (`/repos/openai/codex/releases/...`), then
verifies the package tarball against the checksum inside it. It aborts on any
mismatch. If you want to be extra careful, fetch the script to a file, read it,
and run the local copy (`sh /tmp/codex-install.sh`) so you execute exactly the
bytes you reviewed rather than a fresh fetch.

### 7. Completions are lost and must be regenerated
The AUR package shipped completions for bash/elvish/fish/powershell/zsh under
`/usr/share/...`; removing it deletes them, and the native installer ships none.
Regenerate per-shell with the built-in generator:
```bash
codex completion fish > ~/.config/fish/completions/codex.fish   # fish (Jim's shell)
# bash:  codex completion bash > ~/.local/share/bash-completion/completions/codex
# zsh:   codex completion zsh  > "${fpath[1]}/_codex"
```

---

## Step-by-step (laptop)

### 0. Pre-flight (read-only)
```bash
which -a codex                                    # where does it resolve now?
pacman -Qi openai-codex-bin | grep -E 'Version|Install Reason'
pacman -Ql openai-codex-bin | grep -i '/home/' || echo "(none -> configs safe)"
ls -ld ~/.codex                                   # config present
echo "$PATH" | tr ':' '\n' | grep -n local        # ~/.local/bin ahead of /usr/bin?
```

### 1. Dry-run + remove the AUR package
```bash
pacman -Rsp openai-codex-bin                      # EXPECT: only openai-codex-bin (no cascade)
sudo pacman -R --noconfirm openai-codex-bin
command -v codex || echo "(gone — expected)"
```
On Artix, always dry-run trial-package removals first — `-Rs` can cascade into
`archlinux-keyring` & friends for some packages. Codex has `Depends On: None` and
no reverse deps, so it removes cleanly, but the habit is cheap.

### 2. Install native (run it right here — no clean-terminal needed)
```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
# or, to run exactly what you reviewed:
#   curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/codex-install.sh
#   less /tmp/codex-install.sh && CODEX_NON_INTERACTIVE=1 sh /tmp/codex-install.sh
```
`CODEX_NON_INTERACTIVE=1` suppresses the two end-of-run prompts ("uninstall the
existing npm/bun codex?" — won't fire for us; and "Start Codex now?").

### 3. Verify
```bash
command -v codex                                  # -> ~/.local/bin/codex
readlink -f "$(command -v codex)"                 # -> .../releases/<ver>-x86_64-unknown-linux-musl/bin/codex
codex --version
codex login status                                # -> "Logged in using ChatGPT"
```

### 4. Restore fish completions
```bash
mkdir -p ~/.config/fish/completions
codex completion fish > ~/.config/fish/completions/codex.fish
```

---

## Verification checklist (the desktop end-state)

| Check | Expected |
|---|---|
| `command -v codex` | `~/.local/bin/codex` (a symlink) |
| `readlink -f ~/.local/bin/codex` | `~/.codex/packages/standalone/releases/<ver>-x86_64-unknown-linux-musl/bin/codex` |
| `~/.codex/packages/standalone/current` | symlink → the release dir |
| `pacman -Qq openai-codex-bin` | `error: package 'openai-codex-bin' was not found` |
| `/usr/bin/codex` | absent |
| `codex --version` | `codex-cli <ver>` |
| `codex login status` | `Logged in using ChatGPT` |
| `~/.codex/config.toml`, `~/.codex/auth.json` | present, unmodified (same mtimes as before) |
| `~/.config/fish/completions/codex.fish` | present (regenerated) |

---

## What did NOT need touching (so don't)

- `~/.codex/` — config, auth, sessions, skills, memories, state/log DBs. Read
  identically by the native binary.
- Fish `$PATH` / shell config — `~/.local/bin` already leads PATH on both machines.

---

## Reference: `godlike-artix` end-state (2026-06-19)

- AUR package removed: `openai-codex-bin 0.141.0-1` (had owned `/usr/bin/codex`
  plus bash/elvish/fish/powershell/zsh completions under `/usr/share/...` —
  264.65 MiB, nothing in `/home`).
- Native: `~/.local/bin/codex` → `~/.codex/packages/standalone/current/bin/codex`
  → `releases/0.141.0-x86_64-unknown-linux-musl/bin/codex`.
- `codex login status`: **Logged in using ChatGPT** (existing `auth.json` read
  unchanged).
- Fish completions regenerated to `~/.config/fish/completions/codex.fish`.
- Installer wrote no profile (`path_action=already`; `~/.local/bin` already on PATH).
