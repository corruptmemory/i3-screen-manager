# Brave Browser → Brave Origin migration

Moving the daily browser off **Brave Browser** (`brave-bin`, CLI `brave`) onto
**Brave Origin** (`brave-origin-bin`, CLI `brave-origin`). Both are from Brave
Software and share the same Chromium core; Brave Origin is the **paid, stripped**
build — Leo, Brave Wallet, the crypto/BAT ad system, and the VPN are all removed.
This runbook is the recipe so the second machine can replicate the first.

- **`godlike-artix` (desktop):** DONE 2026-06-23.
- **`nomad-artix` (laptop):** PENDING — follow this document.

Config dir moves with the CLI name:
`~/.config/BraveSoftware/Brave-Browser/` → `~/.config/BraveSoftware/Brave-Origin/`.

---

## 0. The one gotcha that drives everything: the WM_CLASS split

Brave Origin is a *rebuild*, so it presents **two** window identities. This is
the single fact that determined which config lines needed editing:

| Window kind | Old Brave | Brave Origin | Action |
| --- | --- | --- | --- |
| **Main browser window** | `brave-browser` / `Brave-browser` | **`brave-origin` / `Brave-origin`** | rules MUST change |
| Inner-Chromium helper windows (tiny 10×10) | `brave` / `Brave` | `brave` / `Brave` | unchanged |
| Extension popup (e.g. Bitwarden, popped out) | `brave-<extid>` (Wayland) | **`crx_<extid>` / `Brave-origin`** (X11) | match the **ID**, not the prefix |

The inner Chromium binary is *still literally named* `brave`
(`/opt/brave-origin-bin/brave`), which is why helper windows keep the generic
`brave`/`Brave` class while the main window adopts `brave-origin`/`Brave-origin`.

Read the live class yourself (no guessing):

```bash
# X11 (IceWM): main window + any popped-out extension window
for wid in $(xdotool search --class brave); do
  xprop -id "$wid" WM_CLASS
done
# Expect e.g.  "brave-origin", "Brave-origin"   (main)
#              "brave", "Brave"                  (helpers)
#              "crx_nngceck…", "Brave-origin"    (Bitwarden popup)
```

Because that extension-popup instance prefix differs across X11/Wayland and
brave/brave-origin builds, the window rules now match the **stable extension ID**
alone (`^(.*<extid>.*)$`) rather than a brittle prefix.

---

## 1. What the laptop inherits for free — just `git pull`

The config repointing already lives in committed repos. On the laptop, pull them
**before** touching anything else:

```bash
git -C ~/projects/dotfiles    pull   # commit 974c91f
git -C ~/.claude              pull   # claude-stuff: f33e41a → e9e3ec1
git -C ~/projects/home-servers pull  # commit 389e491
```

What those commits already migrated (so the laptop does NOT re-edit them):

- **dotfiles `974c91f`** — launch commands `brave` → `brave-origin` in
  `.icewm/keys` + `.icewm-laptop/keys` (`Super+b`),
  `hyprland-{desktop,laptop}.{lua,conf}` `$browser`, and `dunst/dunstrc`
  `browser =`. Hyprland window rules `^(brave-browser)$` → `^(brave-origin)$`
  (file/open dialogs, idle-inhibit, 2FA). Bitwarden popup rule broadened to the
  extension ID. IceWM `winoptions` focus-steal block
  `brave-browser.Brave-browser` → `brave-origin.Brave-origin`.
  **The laptop's own `hyprland-laptop.*` and `.icewm-laptop/*` are included in
  this commit**, so a `git pull` migrates the laptop's WM config wholesale.
- **claude-stuff** — `CLAUDE.md`: `/usr/bin/brave` → `/usr/bin/brave-origin`
  (platform note, Playwright MCP `--executable-path`, playwright-cli
  `executablePath`) and the WebMCP section repointed + verified (see §8).
- **home-servers** — `.playwright/cli.config.json` → Brave Origin.

---

## 2. What is machine-local — must be redone on the laptop

These touch files **outside** the dotfiles repo (live browser profile data,
`~/.config/mimeapps.list`, the Brave-Origin native-messaging dir). They were done
by hand on the desktop and must be repeated on the laptop.

### 2a. Install Brave Origin + import

```bash
yay -S brave-origin-bin            # AUR *-bin, same family as brave-bin
aur-malware-check                  # the repo's own AUR supply-chain audit; run it
```

> AUR caveat (June 2026 "Atomic" supply-chain infestation): installs from the AUR
> are normally off-limits on these machines. `brave-origin-bin` was installed
> deliberately for this migration — audit with `aur-malware-check` (this repo)
> before trusting it. Official-repo packages remain fine.

Then launch Brave once and use its **import** feature to pull everything from
Brave Browser into Brave Origin.

### 2b. Profile-slot surgery (only if the import misfiles your home profile)

On the desktop, the import dropped a fresh empty **"Personal"** profile into the
`Default` slot and put the real `jim@casapowers.com` profile into `Profile N`.
The fix promotes the home profile into `Default` (which is what the launchers
target with `--profile-directory=Default`).

**Browser MUST be closed** — Chromium rewrites `Local State`/`Preferences` on exit
and will clobber edits. Verify: `pgrep -af brave-origin`.

Identify the right profile from three signals (display name, a `casapowers` hit in
`Preferences`, and directory heft = imported data):

```bash
cd ~/.config/BraveSoftware/Brave-Origin
python3 -c "import json;ic=json.load(open('Local State'))['profile']['info_cache'];[print(d,'->',v.get('name')) for d,v in ic.items()]"
grep -ril casapowers */Preferences          # the home profile is the only hit
du -sh */ | sort -h                           # imported profile is by far the largest
```

Promote it (back up first; the empty Default is moved aside, not hard-deleted):

```bash
cd ~/.config/BraveSoftware/Brave-Origin
cp -p "Local State" /tmp/brave-origin-LocalState.bak
mv "Default" /tmp/brave-origin-Default.personal.removed   # the empty "Personal"
mv "Profile N" "Default"                                   # N = your home profile dir

# Reconcile Local State so the profile picker stays consistent:
python3 - <<'PY'
import json, os
p="Local State"; d=json.load(open(p)); prof=d["profile"]; ic=prof["info_cache"]
home=ic.pop("Profile N")          # <-- the dir you just moved
ic.pop("Default", None)           # drop the old empty Personal entry
ic["Default"]=home                # Default slot now carries the home identity
prof["profiles_order"]=[("Default" if x=="Profile N" else x) for x in prof.get("profiles_order",[]) if x!="Default"]
prof["last_used"]="Default"
tmp=p+".tmp"; json.dump(d,open(tmp,"w"),separators=(",",":")); os.replace(tmp,p)
print("info_cache:", list(ic)); print("order:", prof["profiles_order"])
PY
```

Chromium profile data is path-relative (no self-referential absolute paths in
`Preferences`), so renaming the directory is safe. Verify the new `Default`
mentions `casapowers` and is the heavy one.

### 2c. Strip the "Brave " display-name prefix (optional, cosmetic)

The import prefixed every imported profile name with `"Brave "`. The display name
lives in **two** places that must stay in sync: `Local State`
`profile.info_cache[dir].name` (what the picker shows) and each profile's own
`Preferences` `profile.name`. Browser closed:

```bash
cd ~/.config/BraveSoftware/Brave-Origin
python3 - <<'PY'
import json, os
PREFIX="Brave "
def aw(p,d): t=p+".tmp"; json.dump(d,open(t,"w"),separators=(",",":")); os.replace(t,p)
ls=json.load(open("Local State")); ic=ls["profile"]["info_cache"]; changed=False
for dir,meta in ic.items():
    n=meta.get("name","")
    if n.startswith(PREFIX):
        meta["name"]=n[len(PREFIX):]; changed=True
        pp=os.path.join(dir,"Preferences")
        if os.path.exists(pp):
            pr=json.load(open(pp)); pn=pr.get("profile",{}).get("name","")
            if pn.startswith(PREFIX): pr["profile"]["name"]=pn[len(PREFIX):]; aw(pp,pr)
if changed: aw("Local State",ls)
print("done")
PY
```

### 2d. Dark mode + theme match (optional)

Match each Brave Origin profile's appearance to its old-Brave equivalent **by
name**. Brave stores it in `Preferences`: `browser.theme` (`color_scheme2` →
0/1/2 = System/Light/Dark; `user_color2`/`color_variant2` = accent) and
`extensions.theme.id` (`user_color_theme_id` / `autogenerated_theme_id` / absent).
Copy `browser.theme` + `extensions.theme` from the matching Brave profile and
force `color_scheme2 = 2` (Dark) on every profile. Browser closed.

(On the desktop these were copied programmatically, then hand-tweaked afterward —
so don't expect the laptop's final colors to match the desktop's. The point is
just: dark everywhere, accent ≈ the old profile.)

### 2e. Default browser + mimeapps

The desktop's import already set `brave-origin.desktop` as the default handler for
`http`/`https`/`text/html`; only the stale `webcal` handler needed fixing. On the
laptop, set it explicitly and sweep for any remaining `brave-browser.desktop`:

```bash
xdg-settings set default-web-browser brave-origin.desktop
grep -n brave-browser.desktop ~/.config/mimeapps.list   # repoint any hits → brave-origin.desktop
xdg-settings get default-web-browser                     # verify
```

### 2f. Native-messaging hosts (this is what makes marksnip work)

Chromium reads `NativeMessagingHosts/` **only at browser startup**, and the new
Brave-Origin dir starts empty. Copy the user-level host manifests across:

```bash
SRC=~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts
DST=~/.config/BraveSoftware/Brave-Origin/NativeMessagingHosts
cp -p "$SRC"/*.json "$DST"/        # e.g. com.marksnip.bridge.json, com.anthropic.claude_code_browser_extension.json
```

The manifests' `allowed_origins` reference `chrome-extension://<id>/`; extension
IDs are stable across the import, and the host `path` (`marksnip-native-host`,
etc.) is unchanged — so they copy verbatim. **Restart Brave Origin**, then:

```bash
marksnip status        # expect: chrome: connected on 127.0.0.1:<port> …
```

(`com.anthropic.claude_code_browser_extension` copies too, but Claude-in-Chrome
won't bridge on Brave-family browsers regardless — server-side feature flag — so
its host staying dormant is expected.)

---

## 3. Apply the config (reloads)

The dotfiles changes are inert until each surface reloads:

```bash
killall -HUP icewm          # IceWM (X11): picks up Super+b + winoptions focus-fix
# Hyprland (Wayland): applies on the next session / config reload
# Brave Origin: restart it once so native hosts (§2f) attach
```

---

## 4. Remove Brave Browser

Once Brave Origin is verified working and nothing points at `/usr/bin/brave`:

```bash
pacman -Rsp brave-bin        # DRY RUN first (Artix landmine habit: never -Rs blind)
sudo pacman -R  brave-bin    # then remove (note: -R, not -Rs, unless deps are clearly unique)
```

Package removal does **not** delete `~/.config/BraveSoftware/Brave-Browser/` (user
data); remove that by hand later if you want the disk back.

---

## 5. Verify WebMCP (optional)

Brave Origin **does** ship WebMCP (verified on the desktop at `149.1.91.175`,
Chromium 149): both `chrome://flags#enable-webmcp-testing` and
`chrome://flags#devtools-webmcp-support` exist and were Enabled. With Brave Origin
launched `--remote-debugging-port=9222` and a real page open, probe via direct CDP
(Node 21+, no deps):

```bash
node -e '
(async () => {
  const t = (await (await fetch("http://127.0.0.1:9222/json")).json())
    .find(x => x.type==="page" && x.webSocketDebuggerUrl && !x.url.startsWith("brave://"));
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r, {once:true}));
  ws.send(JSON.stringify({id:1, method:"Runtime.evaluate", params:{
    expression:"JSON.stringify({mc:typeof navigator.modelContext, mct:typeof navigator.modelContextTesting})",
    returnByValue:true}}));
  const m = await new Promise(r => ws.addEventListener("message", e => r(JSON.parse(e.data)), {once:true}));
  console.log(m.result.result.value); ws.close();
})();'
# expect: {"mc":"object","mct":"object"}
```

On the desktop this confirmed `navigator.modelContext` (with
`registerTool`/`getTools`/`executeTool`) and `navigator.modelContextTesting`
(`listTools`/`executeTool`) are live and callable. See the `chrome-devtools-mcp +
WebMCP` section of `~/.claude/CLAUDE.md` for the full plugin wiring; note
`--categoryExperimentalWebmcp` is now unblocked on Origin 149 but not yet
smoke-tested.

---

## 6. Post-migration gotcha: Privacy Badger breaks Gmail link clicks

**Symptom.** Clicking a link *inside a Gmail message* opens a new tab that **hangs
forever** on `about:blank` — title "Loading…", spinner that never resolves, address
bar literally `about:blank`. Brave's **"Copy clean link" → paste into a new tab
works fine.** (Not Brave-Origin-specific — any Brave + Privacy Badger machine; it
just surfaced during the migration shakeout on `godlike-artix`, 2026-06-24.)

**Root cause.** Privacy Badger (`pkehgijcmpdhfbdbbnkijodmdjhbjlgp`) ships a
declarativeNetRequest rule that treats Gmail's `https://www.google.com/url?q=…`
link-shim as a tracker and **307-redirects it to its own bundled forwarder page**:

```
GET https://www.google.com/url?q=<dest>                    (Gmail's safe-redirect)
  └─307→ chrome-extension://<guid>/data/web_accessible_resources/redirect.html?url=<dest>
```

`redirect.html` loads `redirect.js`, which is just
`window.location = new URLSearchParams(location.search).get("url")`. That forwards
fine in a *normal* tab — but Gmail opens external links with
`window.open(saferUrl, '_blank', 'noopener')` (you can see `canAccessOpener:false`
on the new target), and the browser will not complete a redirect **into** an
extension page for that orphaned no-opener navigation. The tab is stranded on its
initial empty `about:blank` document → spinner forever, empty navigation history.
"Copy clean link" works because it's a direct top-level navigation that never
touches `google.com/url`, so the rule never fires.

> The `chrome-extension://` origin in the trace is a randomized **GUID**, not the
> real extension ID, because PB declares `"use_dynamic_url": true` on the resource.
> Map it back to the extension:
> ```bash
> find ~/.config/BraveSoftware/Brave-Origin/Default/Extensions \
>      -path '*web_accessible_resources/redirect.html'
> # → …/Extensions/pkehgijcmpdhfbdbbnkijodmdjhbjlgp/<ver>/…   (Privacy Badger)
> ```

**The fix that works — allowlist the *request* domain:**

> Privacy Badger options → **Disabled Sites** tab → add **`www.google.com`**.
> PB now leaves the `google.com/url` redirect alone; Gmail link clicks work, and PB
> stays active everywhere else.

**The fix that does NOT work** — "Disable Privacy Badger for this site" on
`mail.google.com`. That allowlists the *initiator* site, but the hijack is a
**request-keyed** DNR rule matching `www.google.com` (a different host), evaluated
at the network layer regardless of which tab fired the request. The new tab's
"site" is `google.com`, not `mail.google.com`, so the `mail.google.com` entry is
inert (remove it; it's dead weight). General rule worth remembering:

> When an extension breaks a page via a **network-layer redirect/block**, allowlist
> the domain of the **blocked request**, not the domain of the page you're looking
> at. "Disable for this site" UIs operate on the visible tab's origin and silently
> miss cross-domain request rules.

What you give up with the `www.google.com` allowlist: PB no longer runs on
`www.google.com` (Search + the `/url` redirector). Other Google hosts
(`docs.google.com`, `drive.google.com`, …) are unaffected and stay protected.

**Brave footnote.** Privacy Badger is largely **redundant under Brave Shields**,
which already does tracker/ad blocking, fingerprint protection, query-param
stripping, *and* bounce-tracker debouncing — the very `google.com/url` unwrap PB
botches here. Removing PB entirely is also a clean fix on Brave with ≈zero
protection loss; allowlist-vs-remove is taste.

**Confirm it yourself (CDP).** With Brave Origin on `--remote-debugging-port=9222`,
arm a browser-level CDP `Target.setAutoAttach` listener (`waitForDebuggerOnStart`),
click a Gmail link, and watch the **new tab's** first navigation. The fingerprint
is a `307` from `www.google.com/url?q=…` straight into a
`chrome-extension://…/redirect.html?url=…` — that *is* the smoking gun, no extension
bisecting needed. (A blocked request would instead show
`net::ERR_BLOCKED_BY_CLIENT`; a lost `window.open` handle would show *no* request at
all — the 307-to-extension-page is what distinguishes this redirect-hijack from
those.)

---

## Quick checklist (laptop)

- [ ] `git pull` dotfiles + claude-stuff + home-servers
- [ ] `yay -S brave-origin-bin` → `aur-malware-check`
- [ ] Import from Brave (browser UI)
- [ ] Profile-slot surgery if home profile isn't in `Default` (browser closed)
- [ ] Strip `"Brave "` name prefixes; dark mode (browser closed, optional)
- [ ] `xdg-settings set default-web-browser brave-origin.desktop` + mimeapps sweep
- [ ] Copy `NativeMessagingHosts/*.json` → Brave-Origin; restart browser; `marksnip status`
- [ ] `killall -HUP icewm`; reload Hyprland next session
- [ ] (optional) WebMCP probe
- [ ] `pacman -Rsp brave-bin` (dry-run) → `sudo pacman -R brave-bin`
- [ ] (if Gmail link clicks hang on `about:blank`) Privacy Badger → Disabled Sites → add `www.google.com` — see §6
