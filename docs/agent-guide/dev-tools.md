# Developer Tools (mise)

Read this guide before installing, updating, or removing a developer tool or coding-agent
CLI, or changing how shells find them. Sources: dotfiles' `.config/mise/` and
`.local/share/applications/storageexplorer.desktop`, `update-mise`, `tool-audit`, the
machine-local `~/.config/fish/config.fish`, `~/.bashrc` and `~/.bash_profile`, and
`mise tool NAME`. Packages that system software depends on stay on pacman; see
[Package Installation](packages.md).

## What mise Owns

On the laptop, mise installs the language toolchains and their language servers (Node,
Zig and zls, Odin and ols, Ruby), CLIs built by Go, npm, cargo and pipx (gopls, templ,
gosec, stringer, gdlv and Delve's dlv, playwright-cli, rbw, rofi-rbw, basedpyright),
release binaries (pandoc, slang, emacs-lsp-booster, Azure Storage Explorer, herdr), and
the coding-agent CLIs (claude, codex, agy as `antigravity-cli`, grok, cursor-agent,
opencode).
`mise ls --global` lists the set. go, rustup, python, uv, clang, nodejs, and the
`typescript-language-server` package stay on pacman, because other packages need them.

The config is dotfiles' `.config/mise/config.toml`, shared by both machines, plus
`conf.d/<hostname>.toml` for tools one machine alone gets (the laptop's coding-agent
CLIs). Each file is linked into `~/.config/mise/`. Edit a file and run `mise install`,
or run `mise use -g`, which writes through the link and keeps the comments.

## Updates and Trust

`update-mise` lists outdated tools, then runs `mise upgrade --global`. It reads the global
and system configs only, so a project's `mise.toml` in the current directory is never
upgraded by it. `--dry-run` only lists outdated tools; `--audit` runs `tool-audit`
afterwards. Exit status is 0 when everything is current or upgraded, 1 when mise or the
audit fails, and 2 on a usage error. mise skips releases younger than its minimum release
age, which was 24 hours on 2026-11-25. Grok's `http:` install has no release date, so it
bypasses the delay. For an urgent fix, run `MISE_MINIMUM_RELEASE_AGE=0s update-mise`. The
replaced version is pruned after `upgrade.prune_after` (24 h).

`mise tool NAME` shows how mise verified a tool: a checksum (claude, codex, opencode, node,
zig, emacs-lsp-booster), a minisign or GPG signature (zls, zig, node), or nothing (agy,
grok, cursor-agent, herdr, and the GitHub-release tools without a digest). `tool-audit`
treats every real `installs/<tool>/<version>` folder as immutable, so a file that changes
inside one is a red flag. New version folders and the moved `latest` alias links are
normal. It checks Claude Code and herdr against their vendors' published checksums, using
the binary `mise which` names.

The agents' own updaters are set off where a setting exists, in machine-local files:
Claude Code's `autoUpdates` in `~/.claude.json` (it also records `installMethod: native`;
the Omarchy desktop has the same settings and its mise-run claude has never been
self-updated), grok's `[cli] auto_update` in `~/.grok/config.toml`, and opencode's
`autoupdate` in `~/.config/opencode/cli.json`, whose effect is unverified. codex, agy,
cursor-agent and herdr have no such setting. `tool-audit` shows an updater's work either
way: a binary rewritten in place is a red flag, and one written to the vendor's own
folder or `~/.local/bin` appears as New.
`agent` (Cursor's name for its CLI) is a fish alias for `cursor-agent`.

## Shells and Launchers

Fish login and non-interactive shells put `~/.local/share/mise/shims` on PATH. A session
started from a TTY login (`start-hyprland`, the X11 launchers) therefore hands the shims to rofi,
Emacs, and other GUI launches. The shims stay valid across upgrades. Interactive fish and
bash then run `mise activate`, which also applies per-directory `mise.toml` versions. The
fish block ends `config.fish`, after the PATH block that would otherwise put `~/.local/bin`
first. `~/.bash_profile` adds `~/.local/bin` before it sources `~/.bashrc`, for the same
reason.

Node's global packages are listed in `~/.default-npm-packages` (`typescript-language-server`,
`typescript`), and mise installs them into each Node version it adds. Cursor's CLI runs
`npx -y typescript-language-server` in every folder it opens; with the package already
global, `npx --offline` runs it without the npm registry.

Storage Explorer's launcher runs the `StorageExplorer` shim. Its icon is the tarball's
`StorageExplorerColor.svg`, reached through the `latest` alias, because the tarball's
`icon.png` is corrupt. Sign-in runs on .NET, so `dotnet-runtime` stays installed from
pacman and is marked explicit. The window class is `storageexplorer`.

## Known Gaps

- mise's pipx tools (rofi-rbw, basedpyright) run on uv's managed Python under
  `~/.local/share/uv/python/`. Removing that Python breaks them until
  `mise install --force` reinstalls them.
- The desktop (Omarchy) gets Node and its coding-agent CLIs from Omarchy's
  `/etc/mise/conf.d/omarchy-tools.toml`, and does not link the shared config or
  `update-mise` yet. Open decisions there:
  - which of the 17 Go tools in `~/go/bin` move to `go:` entries (golangci-lint has an
    aqua entry);
  - whether cargo's `tree-sitter` moves;
  - whether pacman's rbw and rofi-rbw, zig, pandoc-cli, odin-git-local, herdr and
    gemini-cli move or are removed;
  - lean4 in a `conf.d/godlike-omarchy.toml`.

## Verification

After a config change, run `mise install` and check that `fish -c 'command -v TOOL'`
resolves under `~/.local/share/mise`. After changing `update-mise`, run `bash -n` and
`update-mise --dry-run`. After changing `tool-audit`, run
`python3 -m unittest discover -s tools -p 'test_*.py'`; its tests cover the
version-folder rule and an upgrade. For a launcher, `desktop-file-validate`, then start
it from rofi.
