# Claude Code: AUR → native ("blessed upstream") migration runbook

**Status:** `godlike-artix` (desktop) — **DONE 2026-06-15**. `nomad-artix` (laptop) — **PENDING**.
**Author:** the desktop's Claude Code, after doing this surgery on itself.
**Audience:** the next Claude Code instance that runs this on the laptop. Read this
first — it will save you the 3–4 wasted rounds the desktop run took to discover the
gotchas below.

> **Why this migration exists.** The June 2026 "Atomic" AUR supply-chain compromise
> (see `aur-malware-check` in this repo) means Jim is avoiding AUR package updates for
> a while. Claude Code was installed from the AUR (`claude-code` package). This switches
> it to Anthropic's official native installer (`curl -fsSL https://claude.ai/install.sh | bash`),
> which **self-updates from Anthropic's own channel** — so Claude stays current without
> ever touching the AUR again.

---

## TL;DR — the correct order (this is the "do it right the first time" sequence)

The desktop run discovered the right order *by getting it wrong first*. On the laptop,
do exactly this and it works on the first attempt:

```text
1. Pre-flight (read-only): confirm the AUR package shape + config locations + the
   deep-link handler path (they may differ slightly from the desktop).
2. Remove the AUR package FIRST:        sudo pacman -R --noconfirm claude-code
3. From a CLEAN terminal — NOT inside a Claude Code session — install native:
                                        curl -fsSL https://claude.ai/install.sh | bash
4. Verify in that same clean terminal:  claude doctor   (expect: native + auto-updates enabled)
5. Fix the deep-link .desktop handler to point at ~/.local/bin/claude
6. Restart Claude Code; verify the session is on the native build.
```

The two non-obvious ordering constraints — **remove the AUR package before installing**,
and **run the installer from a terminal that is not itself a Claude session** — are the
whole reason this doc exists. Details under "Key findings."

---

## Key findings / gotchas (the expensive lessons)

### 1. Your configs are independent of the install method — the migration is config-safe
`~/.claude/` (skills, plugins, settings, keybindings, memory) and `~/.claude.json`
(all MCP servers — open-brain, perplexity, the plugin servers — plus project history)
live in `$HOME` and are **not owned by the AUR package**. On the desktop the package
owned only 11 files, none under `/home`. Therefore:
- `sudo pacman -R claude-code` removes **nothing** in your home dir.
- Installing the native build touches **nothing** in your existing config.
- After the swap, the native binary reads the same `~/.claude*` and everything
  (MCP, plugins, skills) just works. Verify with `claude mcp list`.

### 2. A pre-existing *system* install disables the user auto-updater
The AUR package installs to `/opt/claude-code/bin/claude` with a root-owned symlink at
`/usr/bin/claude`. Claude Code treats a root-owned/global install as
**administrator-managed** and disables per-user auto-update — `claude install` then prints
*"Updates are disabled by your administrator. Contact your IT team…"* and **no-ops** (it
creates no launcher). **Fix: remove the AUR package before the native install**, so there
is no system install for the native one to defer to.

### 3. Running the installer *nested inside a Claude session* also disables it
Even with the AUR package gone, if you run `curl … | bash` / `claude install` from a shell
that is a child of a running Claude Code session, the launcher/auto-updater setup detects
the nested context and **still** no-ops with the same "administrator" message. This is
**process-tree based, not env-var based** — scrubbing `CLAUDE*` env vars does **not** help.
**Fix: run step 3 from a plain terminal that is not under Claude Code.** (This is why the
laptop's Claude cannot fully self-migrate from inside a session — it must hand the final
install command to Jim to run in a clean terminal, exactly as happened on the desktop.)

### 4. Removing the running binary mid-session is safe
`sudo pacman -R claude-code` unlinks `/opt/claude-code/bin/claude` while the current Claude
session is executing it. On Linux the inode stays alive for the running process — the
session keeps working off the now-unlinked file until it exits. The new build only takes
effect on a **fresh launch**. So removal does not crash your live session; just don't
expect the live session to "become" the native build — restart for that.

### 5. The deep-link `.desktop` handler hardcodes the old binary path
`~/.local/share/applications/claude-code-url-handler.desktop` handles `claude-cli://`
deep links (OAuth login callbacks, "open in Claude Code" links). On the desktop its
`Exec=` hardcoded the AUR path `/opt/claude-code/bin/claude`, which **silently breaks**
the next time a browser login hands back to the CLI once the AUR package is gone. It is
**not** package-owned (Claude itself wrote it), so removal leaves it stale. **Fix it to
point at `~/.local/bin/claude`** — the stable launcher symlink, *not* the versioned path
(see finding 6). On the laptop, read the file first; its hardcoded path may differ.

### 6. Point things at the launcher symlink, never the versioned path
The native install lays out as: `~/.local/bin/claude` → **symlink** →
`~/.local/share/claude/versions/<version>` (the actual ~250 MB binary). Auto-update drops a
new `versions/<next>` and **repoints the symlink**. So anything that references Claude (the
`.desktop` handler, scripts, etc.) must use the stable `~/.local/bin/claude`, because the
versioned path changes on every update.

### 7. PATH precedence
`~/.local/bin` must come before any system bin dir. On the desktop it was already first
(Jim's fish config also prepends `~/.claude/local`, a legacy local-install dir that is
currently empty — harmless). Confirm on the laptop with `echo $PATH`; if `~/.local/bin`
isn't ahead of `/usr/bin`, add it via `fish_add_path` (fish) before relying on `claude`
resolving to the native build.

---

## Step-by-step (laptop)

### 0. Pre-flight (read-only — confirms the laptop matches the desktop's shape)
```bash
which -a claude                                   # where does it resolve now?
pacman -Qi claude-code | grep -E 'Version|Install'
pacman -Ql claude-code                            # confirm it owns nothing under /home
pacman -Ql claude-code | grep -i '/home/' || echo "(none -> configs safe)"
ls -ld ~/.claude ~/.claude.json                   # configs present
grep -H '^Exec=' ~/.local/share/applications/claude-code-url-handler.desktop  # note the hardcoded path
echo "$PATH" | tr ':' '\n' | grep -n local        # ~/.local/bin ahead of /usr/bin?
```

### 1. Remove the AUR package
```bash
sudo pacman -R --noconfirm claude-code
ls /usr/bin/claude /opt/claude-code 2>&1          # expect: both gone
```
(Safe even though it's the running binary — see finding 4. Jim has passwordless sudo on
his machines, so `--noconfirm` is non-interactive.)

### 2. Install native — FROM A CLEAN TERMINAL (not inside Claude Code)
This is the step the laptop's Claude must hand off to Jim, because of finding 3.
```bash
curl -fsSL https://claude.ai/install.sh | bash
```
The installer downloads a **checksum-verified** binary from
`downloads.claude.ai/claude-code-releases`, then runs `claude install` to create
`~/.local/bin/claude` → `~/.local/share/claude/versions/<version>` with auto-update enabled.

### 3. Verify in that clean terminal
```bash
claude doctor
```
Expect: `Currently running: native`, `Config install method: native`,
`Updates → Auto-updates: enabled`, `Auto-update channel: latest`, no "administrator" line.

### 4. Fix the deep-link handler
Repoint `Exec=` to the launcher symlink (adjust the old path to whatever step 0 showed):
```bash
sed -i 's#^Exec=.*#Exec="'"$HOME"'/.local/bin/claude" --handle-uri %u#' \
  ~/.local/share/applications/claude-code-url-handler.desktop
grep '^Exec=' ~/.local/share/applications/claude-code-url-handler.desktop   # confirm
```

### 5. Restart Claude Code and confirm the session is native
```bash
echo "$CLAUDE_CODE_EXECPATH"      # expect ~/.local/share/claude/versions/<version>, NOT /opt/claude-code/...
which -a claude                   # expect ~/.local/bin/claude (a symlink)
readlink -f ~/.local/bin/claude   # -> ~/.local/share/claude/versions/<version>
claude mcp list                   # open-brain + others should connect
```

---

## What "correct" looks like — verification checklist (the desktop end-state)

| Check | Expected |
|---|---|
| `CLAUDE_CODE_EXECPATH` | `~/.local/share/claude/versions/<version>` (native), not `/opt/claude-code/...` |
| `~/.local/bin/claude` | symlink → `~/.local/share/claude/versions/<version>` |
| `pacman -Qq claude-code` | `error: package 'claude-code' was not found` |
| `/usr/bin/claude`, `/opt/claude-code` | both absent |
| `claude doctor` | native install method; auto-updates **enabled**; channel `latest` |
| `.desktop` Exec | `"$HOME/.local/bin/claude" --handle-uri %u` |
| `claude mcp list` | open-brain ✔, perplexity ✔, serena ✔, context7 ✔, playwright ✔, chrome-devtools ✔ |

OAuth connectors (Gmail / Drive / Calendar / Microsoft 365 / GitLab) showing
`! Needs authentication` is **normal and pre-existing** — they need an interactive
re-login and have nothing to do with this migration.

---

## Fallback: manual verified-binary placement (stopgap only)

If you can't conveniently get a clean terminal and need a *working* (but not yet
self-updating) native `claude` immediately, place the verified binary by hand. This is
what the desktop run did as a bridge before the clean-terminal finalize:

```bash
BASE=https://downloads.claude.ai/claude-code-releases
ver=$(curl -fsSL "$BASE/latest")
plat=linux-x64                                  # use linux-x64-musl on a musl system (Artix is glibc)
sum=$(curl -fsSL "$BASE/$ver/manifest.json" | jq -r ".platforms[\"$plat\"].checksum")
curl -fsSL "$BASE/$ver/$plat/claude" -o /tmp/claude-native
[ "$(sha256sum /tmp/claude-native | cut -d' ' -f1)" = "$sum" ] && echo "CHECKSUM OK" || echo "ABORT: mismatch"
install -Dm755 /tmp/claude-native ~/.local/bin/claude && rm -f /tmp/claude-native
```
This yields a working `claude` but **without** the auto-update launcher — you still must
run `claude install` (or `curl … | bash`) from a clean terminal afterward to get
auto-updates and the proper symlink layout. The proper installer overwrites the stopgap.

---

## What did NOT need touching (so don't)

- `~/.claude/` and `~/.claude.json` — all MCP servers, plugins, skills, settings,
  keybindings, memory. Install-method-independent; left completely alone.
- MCP registrations (open-brain key, perplexity, the plugin servers) — read identically
  by the native binary.

---

## Reference: `godlike-artix` end-state (2026-06-15)

- AUR package removed: `claude-code 2.1.177-1` (had owned `/opt/claude-code/{,bin/claude}`,
  `/usr/bin/claude`, `/usr/share/licenses/claude-code/LICENSE` — 11 files, none in `/home`).
- Native: `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.177` (250480336 bytes).
- `claude doctor`: native; auto-updates **enabled**; channel `latest`; stable 2.1.153 /
  latest 2.1.177.
- Deep-link handler `~/.local/share/applications/claude-code-url-handler.desktop`:
  `Exec="/opt/claude-code/bin/claude"` → fixed to `Exec="/home/jim/.local/bin/claude"`.
- All MCP servers verified connecting under the native binary.
