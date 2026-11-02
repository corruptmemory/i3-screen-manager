# RDP clients on Artix, the TSPlus HTML5 client, and agent control

Research note, 2026-11-02. A client offered access to a Windows server running TSPlus, by
its HTML5 web portal or a standard Linux RDP client. This note records which client to use,
how an agent can drive each route, and how the clipboard behaves, which has been a recurring
pain point. Tests ran from `nomad-artix` against TSPlus's public demo, `demo.tsplus.net`. The
client's own server has not been touched. This note is not loaded as agent instructions. The
operating guide, and the tools to reproduce all of this, are in
[`docs/agent-guide/remote-desktop.md`](../agent-guide/remote-desktop.md) and `tools/rdp/`.

## Conclusions

- For a person, use `xfreerdp3`. Its text clipboard was exact in every valid test, and the
  portal's paste quirk never appeared in it. Rich text does not survive in either direction.
- No client in the repositories offers a command port or MCP interface. An agent works from
  screenshots, coordinates, and keystrokes, on either route.
- The portal works for a quick supervised job, with nothing to install. For sustained agent
  work, `xfreerdp3` on a private X display is better, because its clipboard stays separate.
- SSH or a program's own API beats both whenever the server allows it.
- Most apparent failures in these tests came from the bench, the demo's timer, or a stuck
  key, not the clipboard. See [What looked wrong](#what-looked-wrong-and-was-not).

## Clients in the repositories

From `pacman -Si`, 2026-11-02:

| Package             | Version    | Upstream activity                                        | Verdict                   |
|---------------------|------------|----------------------------------------------------------|---------------------------|
| `freerdp`           | 2:3.32.2-1 | 13,930 stars; 3.33.0 released 2026-11-02                 | **First choice**          |
| `remmina`           | 1:1.4.43-4 | Last commit 2026-10-29                                   | **Second**: GUI, profiles |
| `krdc`              | 26.08.2-1  | KDE release; recent clipboard work on master only        | **Third**: text clipboard |
| `gnome-connections` | 51.0-1     | Last commit 2026-10-19 was a translation                 | Basic viewer              |
| `rdesktop`          | 1.9.0-4    | v1.9.0 from 2019-10-11; README says no longer maintained | Avoid                     |

`xrdp` and `krdp` are servers, so they do not apply. TSPlus's docs still suggest `rdesktop`
for Linux, but its README warns of unreviewed security reports. AUR candidates such as
`electerm`, `rustconn-appimage`, `tempest-desktop-bin`, `nyaterm-bin`, `motty-bin`, and
`taomni-bin` were not evaluated: official packages meet the need, and the AUR is
hostile-by-default under [the package policy](../agent-guide/packages.md).

### FreeRDP as packaged

Arch ships `xfreerdp3`, `sdl-freerdp3`, `wlfreerdp3`, `sfreerdp3`, `sfreerdp-server3`,
`freerdp-shadow-cli3`, `freerdp-proxy3`, `winpr-hash3`, and `winpr-makecert3`. The recipe sets
`WITH_X11`, `WITH_WAYLAND`, `WITH_CLIENT_SDL3` (not SDL2), `WITH_FUSE`, `WITH_PULSE`,
`WITH_VAAPI`, `WITH_SERVER`, and binary versioning. The proxy's bundled modules are
`bitmap-filter`, `demo`, and `dyn-channel-dump`, so there is no capture module. Options that
matter here, from `client/common/cmdline.h`:

| Option                 | Use                                                                         |
|------------------------|-----------------------------------------------------------------------------|
| `/clipboard[:...]`     | `use-selection:<atom>`, `direction-to:all,local,remote,off`, `files-to:...` |
| `/from-stdin[:force]`  | Read credentials from stdin                                                 |
| `/args-from:...`       | `file:`, `stdin`, `fd:`, or `env:`; one argument per line                   |
| `/drive:<name>,<path>` | Share a folder as `\\tsclient\<name>`                                       |
| `/app:program:...`     | RemoteApp: `<path>` or `\|\|alias`, plus `cmd:`, `file:`, `workdir:`        |
| `/grab-keyboard`       | On by default; `-grab-keyboard` if window manager shortcuts are swallowed   |
| `/action-script`       | Local script for client actions; not a control port                         |
| `/cert:tofu`           | Trust the first certificate, refuse a later change                          |
| `/log-filters:...`     | Per-channel logging, such as `com.freerdp.channels.cliprdr.client:DEBUG`    |

`com.freerdp.*` in the logs is only a label (`#define FREERDP_TAG(tag) "com.freerdp." tag` in
`log.h`). FreeRDP is C and C++, not Java. TSPlus's own web server does need OpenJDK 17 or newer,
on the server.

### Remmina and KRDC

Arch builds Remmina with `-DWITH_FREERDP3=ON`, and `freerdp` is an optional dependency that
must be installed for RDP. Scripting stops at launching: `-c` connects to a profile, and
`--update-profile` with `--set-option` edits one. Its D-Bus use in `src/` and `plugins/` is theme
and system information plus an old Telepathy plugin, not a control interface. It has a "Send
clipboard content as keystrokes" menu item in current source.

KRDC links FreeRDP directly. Its only D-Bus use in C++ is in `rdp/rdphostpreferences.cpp`. Its
RDP source has no RemoteApp support.

## Letting an agent drive

Repository figures are from the GitHub API on 2026-11-02.

| Project                         | Runs on         | Approach                               | Stars | Last push  | Assessment                         |
|---------------------------------|-----------------|----------------------------------------|-------|------------|------------------------------------|
| `xfreerdp3`, Xvfb, xdotool      | Local           | Private X display, input, screenshots  | n/a   | n/a        | **Recommended**; see `rdp-lab`     |
| `stubbedev/win-rdp-mcp`         | Local + server  | MCP around that same approach          | 2     | 2026-11-02 | Useful reference; do not run as is |
| `advenimus/conduit-desktop`     | Local           | Electron manager with 60+ MCP tools    | 19    | 2026-10-28 | Not in repos; README read only     |
| `WangYihang/remote-desktop-mcp` | Local           | Python MCP; credentials in environment | 3     | 2026-03-13 | Stale, and exposes credentials     |
| `apache/guacamole-server`       | Local or Docker | `guacd` text protocol                  | 4,033 | 2026-10-31 | Closest to a command port; heavy   |
| `lighttransport/RDPFlux`        | Both            | Agent on the server over `rdp2tcp`     | 0     | 2026-10-03 | Needs software on the server       |
| `dddabtc/winremote-mcp`         | Server          | MCP server on Windows, port 8090       | 216   | 2026-09-30 | Needs software on the server       |
| `GhouI/winreach-mcp`            | Server          | MCP server on Windows over HTTP        | 7     | 2026-07-18 | Needs software on the server       |
| `emog33k/winrdp-mcp`            | Local + server  | Enables WinRM, opens the firewall      | 5     | 2026-10-14 | Changes the server's configuration |

**`win-rdp-mcp`, from its source.** It holds an `xfreerdp3` session inside Xvfb and passes the
arguments on stdin with `/args-from:stdin`, so the password stays out of `argv`. It sets
`KRB5_CONFIG=/dev/null`, which is where this bench's fix came from. Problems for this use:

- `clientArgs` hard-codes `/cert:ignore` (no server check) and `/sec:nla` (fails if NLA is off).
- By default it pushes a Windows agent over drive redirection. `--no-agent` stops that but still
  shares a local folder with `/drive:mcp,...`.
- It reconnects on its own, and a second login as the same user takes over the session.
- The password comes from an environment variable or `--pass-file`.

**Guacamole.** `guacd` connects to RDP through FreeRDP and exposes a text protocol: `select`,
`args`, `size`, `audio`, `video`, `image`, `connect`, then `ready`; `mouse` and `key` go in; `img`
and `blob` come out. Version 1.6.0 added FreeRDP 3 support (GUACAMOLE-1026). It is not in the
repositories, the AUR's `guacamole-client-bin` is the web part only, there is no MCP bridge, and a
client would have to be written. Talking to `guacd` from a non-web client was not tested.

**Libraries.** `Devolutions/IronRDP` (3,272 stars, Rust, active), `skelsec/aardwolf` (243 stars,
Python, 0.2.16 on 2026-10-04), and `GoSecure/pyrdp` (1,788 stars, a proxy and recorder, last
release 2024-01-23) would mean building a client. None was tried.

## The TSPlus portal

### Server behavior, from TSPlus's documentation

- RDP listens on a configurable port (default 3389) and also on the HTTP and HTTPS ports, unless
  AdminTool > Advanced > Security > "Disable RDP Forwarding" is set. The demo answered on 3389,
  443, and 80.
- An administrator can reject standard RDP clients, require the web portal, or allow Microsoft
  RDP clients for administrators only.
- Network Level Authentication is something an administrator activates.
- The HTML5 client accepts `user`, `pwd`, `program`, `startupdir`, and `params` URL parameters. The
  password ones are unsafe. "Application Command Line" in AdminTool can disable the program ones.
- `software/html5/settings.js` holds client settings, and the demo serves it to anyone. Clipboard
  ones: `W.clipboard`, `W.openonclipblur`, `W.clipansiconvert`, `W.clippasteimage`, and
  `W.clippasteimagewhiletext`.

### The HTML5 client, from its code and live tests

Client 8.36 loads `html5/settings.js`, `language.js`, `flashcanvas.js`, `jwweb.org.js`,
`socket.io.js`, `jwweb.core.js`, and `jws.js`. The page is one canvas, `JWTS_myCanvas`, plus a few
controls; `document.body.innerText` showed only `en_us more..`. `W` is a global. In the test
browser the page measured 1862x1036 CSS pixels at `devicePixelRatio` 1.375, so screenshots were
2560x1425.

- `W.setClipOnData` writes received text to the local clipboard. It calls `syncClip`, a wrapper for
  `navigator.clipboard.writeText`, then falls back to `execCommand("copy")`. `syncImg` does the same
  for images with `navigator.clipboard.write`.
- That explains why the docs' timing trap did not appear: the async call does not need Ctrl+C to
  be held. It needs a secure context, so a plain-HTTP portal could behave as documented.
- The clipboard menu's `GetEnv` button appears when `navigator.clipboard.readText` exists. TSPlus's
  clipboard page does not list it.
- `language.js` contains "ClipBoard text is over 500kb Upload it per file!". The limit was not tested.

Per TSPlus's support article, only text and images pass through the HTML5 clipboard. Copying an
image out takes an extra right-click on a preview, and files use drag and drop inward and
`\\tsclient\WebServer` outward.

### The RemoteApp option

Choosing RemoteApp at login leads to an "Open xdg-open?" prompt when an app is clicked. Clicking
Notepad on the demo did this:

1. `launch(3)` posted connection settings to `/cgi-bin/hb.exe?action=remoteapppost`, with an ID made
   by `hex_sha1` over the settings, a random number, and the time.
2. The page ran `location.replace('remoteapps://demo.tsplus.net/<40-character ID>')`, or
   `remoteapp://` on plain HTTP.
3. On Windows, per TSPlus's docs, `RemoteAppClient.exe` fetches those settings from the server by ID
   (`RemoteAppClient/Setup-RemoteAppClient.exe` is the download). That step could not be observed here.

No handler exists on Linux (`xdg-mime query default x-scheme-handler/remoteapps` is empty), so
opening the link achieves nothing. The link itself holds only the ID. A Linux handler would mean
reverse-engineering the server's calls; `xfreerdp3 /app:` is the direct route. The portal names
Notepad `[App9]`, so a server may accept only its own aliases. That has not been tested.

## Clipboard results

All against the demo's Notepad, from the laptop. `xfreerdp3` ran on a nested Xephyr display, with
xdotool and xclip.

| Test                          | `xfreerdp3`                            | HTML5 portal                           |
|-------------------------------|----------------------------------------|----------------------------------------|
| Coordinate click and typing   | Works                                  | Works, as trusted events               |
| Remote to local, plain text   | 3 of 3 exact, 191 to 220 ms            | 8 of 8 exact, arriving in about 107 ms |
| Remote to local, real keys    | Not tested                             | Works, with a quick tap                |
| Local to remote, strict check | 56 of 56 exact while Notepad had focus | Works with `commands:["paste"]`        |
| Local to remote, real keys    | Not tested                             | Worked after the quirk below           |
| Non-ASCII                     | Exact; LF kept                         | Exact through `To clip` and `To IME`   |
| Paste inside the session      | 10 of 10                               | Not tested                             |
| 600 KB and 1.1 MB             | Both intact                            | Not tested                             |
| Local clipboard from the menu | n/a                                    | `ToEnv` exact                          |

The non-ASCII text was `café ñ € ✓ 日本語`. Portal text read from the session used CRLF.

**The portal quirk.** With real keys, Ctrl+V did nothing while the session had a selection. Clearing
the selection and copying the local text again made it work. In synthetic tests the first paste over
a selection worked, then later pastes inserted the old remote text instead of the new local text,
with and without a selection. Each of those pastes followed a remote copy made to read the result
back, so a recent remote copy may be the real trigger. `portal-test.sh stale-probe` was written to
settle this, and has not run yet.

### Rich content, against Word

| Direction     | Content | Result                                                                                   |
|---------------|---------|------------------------------------------------------------------------------------------|
| Linux to Word | PNG     | Pasted correctly                                                                         |
| Word to Linux | Image   | Offered as BMP, WebP, PNG, JPEG, and TIFF; the PNG was 320x120 and essentially identical |
| Linux to Word | HTML    | Word requested `HTML Format` repeatedly and got answers, but nothing appeared            |
| Linux to Word | RTF     | `text/rtf` was never announced to the server, so nothing to paste                        |
| Word to Linux | Text    | Plain text only: targets were `STRING` and `UTF8_STRING`                                 |

For the Word text copy the server offered `Rich Text Format`, `CF_TEXT`, `CF_UNICODETEXT`,
`CF_METAFILEPICT`, `Native`, `Hyperlink`, `CF_LOCALE`, and `CF_OEMTEXT`. HTML was not among them, and
`xfreerdp3` does not expose RTF as an X target. The HTML test source offered `text/html` alone. A real
browser copy also offers plain text, so it may fall back to that; this was not tested.

### What each client's clipboard supports

From reading source; none of this ran except `xfreerdp3`. Versions are what Arch packages.

| Client         | Text | Images | HTML | Files        | Notes                                            |
|----------------|------|--------|------|--------------|--------------------------------------------------|
| `xfreerdp3`    | Yes  | Yes    | Yes  | Yes, by FUSE | Direction limits; choice of CLIPBOARD or PRIMARY |
| Remmina 1.4.43 | Yes  | Yes    | Yes  | No           | On/off setting; CLIPBOARD only; files on master  |
| KRDC 26.08.2   | Yes  | No     | No   | No           | Images, HTML, files, Unicode fix on master, 2026 |

`xfreerdp3` uses CLIPBOARD by default, so a terminal selection (PRIMARY) will not cross.
`use-selection:PRIMARY` switches to it rather than adding it. `/clipboard:direction-to:remote` is a
reported workaround for the SDL bug below.

### Known FreeRDP and Remmina issues

| Issue                     | State       | Summary                                                                   |
|---------------------------|-------------|---------------------------------------------------------------------------|
| FreeRDP #13519            | Open, stale | SDL on Wayland re-announces after server copies; fix #13560 is in 3.32.2  |
| FreeRDP #13938            | Open        | Large `xclip` selection fails; not reproduced here at 1.1 MB on Xephyr    |
| FreeRDP #12355            | Open        | File transfer aborts when the clipboard changes during the copy           |
| FreeRDP #13891            | Open        | The shadow server has no clipboard channel                                |
| FreeRDP #13486, #13554    | Closed      | 3.32.0: remote copy dropped the session; closed before 3.32.1             |
| FreeRDP #13525            | Closed      | 3.32.0: copying a file hung the client; #13527 is in 3.32.1               |
| FreeRDP #12209            | Closed      | Repeated image pastes stopped keyboard input                              |
| FreeRDP discussion #12023 | Discussion  | Reports of fragile sync; stale `/tmp/com.freerdp.client.cliprdr.*` mounts |
| Remmina #3587             | Open        | File copy through the clipboard on FreeRDP 3                              |
| Remmina #3623             | Open        | Images offered only as `image/png` will not paste on Windows              |
| Remmina #3609             | Open        | Diacritics break when pasted into Chrome                                  |
| Remmina #2084             | Closed      | On Wayland, clipboard sync only happens on window focus                   |

FreeRDP releases often and has regressed the clipboard: if it breaks after an update, suspect the new
version first.

### Server policy

From Microsoft's documentation:

- "Do not allow Clipboard redirection" (`fDisableClip`) blocks the clipboard entirely.
- `LimitServerToClientClipboardRedirection` and `LimitClientToServerClipboardRedirection` limit it by
  direction and format: none, plain text, plus images, plus RTF, plus HTML. They exist on Windows Server
  2022 from build 10.0.20348.2523.
- Disabling drive redirection also blocks file copy through the clipboard, but not text or images.
- `rdpclip.exe` handles the clipboard in a session. A comment on FreeRDP #12209 reports it sometimes
  crashes; restarting it is the common advice. It was never needed or tested here.

## What looked wrong and was not

| Appearance                                        | Real cause                                                                       |
|---------------------------------------------------|----------------------------------------------------------------------------------|
| Paste "stalled" about 5 minutes in                | The demo's "Logon timer expired" dialog took the keyboard focus                  |
| Local-to-remote failed 2 of 3 in the first run    | Probably a sentinel set right before Ctrl+C; never reproduced with a settle time |
| Copies "never" arrived, first run                 | Remote Caps Lock was on, so the expected lowercase token never matched           |
| Ctrl+C typed `©` over a Word paragraph            | Stuck Alt: Word maps Ctrl+Alt+C to a copyright sign. Undone, never saved         |
| Clipboard held odd text during the "stall"        | Ctrl+C in a Windows message box copies the dialog's text                         |
| Tokens looked jumbled in Notepad                  | A click on the last line placed the cursor mid-line                              |
| Typed text seemed truncated                       | Frames lagged; all 45 characters had arrived                                     |
| `X connection to :77 broken` after password entry | Xephyr had exited cleanly (the window may have been closed); cause not logged    |
| Logged server requests read 0 per trial           | The log reaches the file through a pipe and lags                                 |
| CDP canvas test failed over SSH on the desktop    | Chromium waited on the keyring until given `--password-store=basic`              |

The demo's limits: a dialog at 5:00 after logon ("It will be disconnected in 2 minutes"), then
`ERRINFO_RPC_INITIATED_DISCONNECT` at about 7:00. The first FreeRDP session's paste failures started
6:39 after logon, 23 seconds before its cutoff, with no dialog visible, and the log showed no error.
That is probably the same shutdown, but it was not proven.

Stuck Alt probably came from switching desktops while the window had focus, since i3's modifier reaches
the focused window first. That is an inference. The cause of the Caps Lock state is unknown.

## Open questions

- What triggers the portal's blocked and stale pastes (`stale-probe`).
- `xfreerdp3` with real keys on a real desktop, including whether it swallows i3 shortcuts.
- A clipboard manager's effect. The suspicion is that CopyQ taking ownership after each copy could echo
  back to the server, as in FreeRDP #13519. The test proved nothing: `copyq --session=NAME` on the nested
  display reported `monitoring: true` and `check_clipboard: true`, yet stored nothing, even from a plain
  `xclip`. Its files land in `~/.config/copyq-NAME` and `~/.local/share/copyq-NAME`. Test with the real
  CopyQ on the desktop's i3 session instead.
- File copy, `/drive:` on TSPlus, and `/app:` against TSPlus's aliases.
- Whether a browser copy of rich text falls back to plain text in Word.
- Portal images, and the 500 KB limit.

## Sources

- FreeRDP: `client/common/cmdline.h`, `client/X11/xf_cliprdr.c`, `client/SDL/SDL3/sdl_clip.cpp`,
  `client/Wayland/wlf_cliprdr.c`, `client/common/client_cliprdr_file.c`, `include/freerdp/log.h`, releases
  and issues at <https://github.com/FreeRDP/FreeRDP>.
- Arch recipes: `gitlab.archlinux.org/archlinux/packaging/packages/{freerdp,remmina,krdc,gnome-connections}`.
- Remmina `v1.4.43` and master: <https://gitlab.com/Remmina/Remmina>. KRDC `v26.08.2` and master:
  <https://invent.kde.org/network/krdc>. GNOME Connections master. rdesktop README.
- TSPlus: <https://docs.tsplus.net/tsplus/html5-client-using-clipboard/>,
  <https://docs.tsplus.net/tsplus/html5-client-parameters-in-url-address/>,
  <https://docs.tsplus.net/tsplus/securing-a-terminal-service-plus-server/>,
  <https://docs.tsplus.net/tsplus/quickstart-guide/>, and support articles on HTML5 clipboard use, pen tests,
  and RemoteApp error codes at <https://support.tsplus.net/>. Client code: public files on `demo.tsplus.net`.
- Guacamole: <https://guacamole.apache.org/doc/gug/guacamole-protocol.html>,
  <https://guacamole.apache.org/doc/gug/protocol-reference.html>, <https://guacamole.apache.org/releases/1.6.0/>.
- Microsoft: <https://learn.microsoft.com/azure/virtual-desktop/redirection-configure-clipboard>,
  <https://learn.microsoft.com/azure/virtual-desktop/clipboard-transfer-direction-data-types>,
  <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-remotedesktopservices>,
  <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-terminalserver>.
