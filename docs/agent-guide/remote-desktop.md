# Remote Desktop

Read this guide to reach a Windows or TSPlus server over RDP from Linux, let an agent
drive a session, or work out a clipboard problem. Sources: `tools/rdp/`, FreeRDP, and
the browser's debug port. Client comparison, measurements, and sources are in the
[research note](../research/2026-11-02-rdp-clients-and-tsplus.md).

## Choosing a Route

| Need                                 | Use                                                   |
|--------------------------------------|-------------------------------------------------------|
| A person working on the server       | `xfreerdp3`                                           |
| A GUI with saved profiles            | Remmina (needs `freerdp` too)                         |
| Nothing can be installed locally     | The TSPlus HTML5 portal                               |
| An agent, for a quick supervised job | The portal over CDP; the person signs in and watches  |
| An agent, for sustained work         | `xfreerdp3` on a private display (`rdp-lab`)          |
| An app on the server by itself       | `xfreerdp3 /app:program:...`; untested against TSPlus |

No client in the Arch repositories has a command port or MCP interface, so an agent
always works from screenshots, coordinates, and keystrokes. Prefer SSH or a program's
own API over either route whenever the server offers one. The portal's RemoteApp option
needs a Windows plugin and cannot work from Linux.

## Setup

Both machines have this, from the official repositories:

```bash
yay -S --needed --noconfirm --repo --ask 4 freerdp xlibre-xserver-xvfb \
  xlibre-xserver-xephyr xorg-xdpyinfo xdotool imagemagick xclip
```

`--ask 4` lets pacman replace a conflicting `xorg-server-xephyr` or `xorg-server-xvfb`.
These machines run XLibre, so use its packages. The CDP tools need Node 21 or newer.

## Credentials and Sign-In

A person signs in; an agent never types a password into a login prompt or form.

- `rdp-lab connect` takes no password, so FreeRDP prompts on the terminal. Run it in a
  real terminal: there is no prompt through Claude Code's `!`.
- A script can use `rbw get ... | xfreerdp3 ... /from-stdin`, or `/args-from:stdin` for the
  whole command line. Neither puts the password in `argv`, where any local user can read
  it. See [network profiles](network-profiles.md#credentials) for the Bitwarden rules.
- Never use the portal's `?user=&pwd=` URL parameters, which put the password in the
  address and browser history. Do not read the page's `remoteapp2_psw` variable.
- TSPlus publishes the login for its demo in its own documentation. It is not recorded
  here, and test sessions on that shared demo use harmless sample text only.

## FreeRDP Bench

`tools/rdp/rdp-lab` runs a session on a private X display. xdotool drives input, `import`
takes screenshots, and xclip reaches that display's clipboard, which stays separate from
the desktop's. A clipboard manager on the desktop never sees it. Files go under
`$XDG_RUNTIME_DIR/rdp-lab` unless `--dir` says otherwise; the display is `:77` unless
`--display` says otherwise.

```bash
tools/rdp/rdp-lab display-start          # Xephyr window under a desktop, else Xvfb
tools/rdp/rdp-lab connect demo.tsplus.net demo   # in a real terminal; Enter at Domain:
tools/rdp/rdp-lab shot start             # find a text window, then use a point inside it
tools/rdp/rdp-lab case-check 820 527     # releases modifiers, fixes inverted Caps Lock
tools/rdp/rdp-lab copy-test 820 527      # both directions, non-ASCII, newlines
tools/rdp/rdp-lab paste-test 820 527     # strict paste; stops and screenshots on two misses
tools/rdp/rdp-lab sizes 820 527          # 600 KB and 1.1 MB
tools/rdp/rdp-lab display-stop
```

For rich content, open a blank document, then use `paste-html`, `paste-rtf`, `paste-image`,
`targets`, and `pull TARGET FILE`, one step at a time. Those tests overwrite text in the
window at that point, so never aim them at a document that matters.

`connect` adds `KRB5_CONFIG=/dev/null` to skip a failed Kerberos try, `/cert:tofu` to trust
the first certificate and refuse a later change, and a debug filter that logs clipboard
messages to `xfreerdp.log`. The log arrives through a pipe and lags, so never use it as a
live counter. Extra arguments pass through, for example:

```bash
tools/rdp/rdp-lab connect HOST USER /drive:share,/path/to/dir
```

The server appears as `\\tsclient\share`. Keep that off unless the job needs it, since it
exposes the folder to the session. TSPlus also serves RDP on its HTTP and HTTPS ports
unless an administrator disabled that, so try `HOST:443` when 3389 is closed.

## Driving Rules for Agents

These all came from real failures:

1. **Run `case-check` first.** Remote Caps Lock was on after connecting in both sessions
   checked, which inverts typed case.
2. **Release modifiers first, and after anyone switches desktops.** A window manager
   shortcut can press Alt in the session without ever releasing it. Ctrl+C then types `©`
   in Word, replacing any selection.
3. **Screenshot before anything that can overwrite data.** A popup silently takes the
   keyboard; keystrokes go to it, or nowhere.
4. **Wait for the screen to settle.** Portal frames lagged typing by up to a second, and
   dropped nothing.
5. **Wait at least 600 ms between a click and a key.** A key sent straight after a click
   can be applied first.
6. **Aim clicks below the text.** A click on the last line lands mid-line once the line
   is longer than the click's position.
7. **Check what you read.** Use a sentinel on the clipboard and let it settle for 0.8 s
   before a remote copy, or its late announcement can overwrite the copy.
8. **Keep the agent away from secrets.** Anything on screen goes into a screenshot, so
   stay out of admin pages and files holding credentials.

## HTML5 Portal over CDP

The client draws everything on one canvas and sends input over a WebSocket, so the DOM
has no text to read. `tools/rdp/cdp-tab.mjs` attaches to the single tab under a URL prefix
and never touches other tabs. It needs Brave's debug port, 9222. Coordinates are CSS
pixels: divide screenshot pixels by `devicePixelRatio`.

```bash
tools/rdp/portal-test.sh inspect       # facts and a screenshot; sends no input
tools/rdp/portal-test.sh --x 727 --y 364 type
tools/rdp/portal-test.sh copy-timing   # quick Ctrl+C taps against the local clipboard
tools/rdp/portal-test.sh paste
tools/rdp/portal-test.sh menu          # To clip, To IME, ToEnv
tools/rdp/portal-test.sh stale-probe   # the open paste question below
```

These overwrite the local clipboard, then restore any text it held. The contents are
never printed. Client 8.36 exposes:

| Item            | Purpose                                                             |
|-----------------|---------------------------------------------------------------------|
| `JWTS_myCanvas` | The canvas holding the whole session                                |
| `W.clipbuffer`  | Last text received from the session: the agent's way to read        |
| `JWTS_clippy`   | Clipboard menu's text area; exists once the menu has opened         |
| `JWTS_cb2`      | To clip: sends the text area to the session, then Ctrl+V            |
| `JWTS_cb4`      | To IME: types the text area as keystrokes, for paste-resistant apps |
| `JWTS_cb10`     | ToEnv: copies the text area to the local clipboard                  |
| `JWTS_cb11`     | GetEnv: reads the local clipboard; may prompt for permission        |
| `JWTS_cb3`      | Close                                                               |
| Shift+F11       | Opens the clipboard menu                                            |

Synthetic input differs from real keys in two ways. A CDP Ctrl+V pastes only with
`commands:["paste"]` (the `key` step's `commands` field). Clipboard writes need focus, so
use the `focus` step, which lasts for that one attach. The MCP `click` tools need an
element reference and cannot aim at a canvas position; use raw CDP or Playwright's
`page.mouse`.

Local clipboard text from the session uses `navigator.clipboard.writeText`, which needs
HTTPS. On a plain-HTTP portal that API is absent, and the timing trap in TSPlus's docs (hold
Ctrl+C until the text arrives) may return. Check `isSecureContext` with `inspect`.

## What the Clipboard Carries

| Content        | `xfreerdp3`                     | HTML5 portal                                          |
|----------------|---------------------------------|-------------------------------------------------------|
| Plain text     | Yes, both ways                  | Yes, with the quirk below                             |
| Non-ASCII text | Yes                             | Yes                                                   |
| Large text     | 1.1 MB tested                   | Refuses over 500 KB, per its own message              |
| Images         | Yes, both ways                  | Untested; docs describe extra steps                   |
| Rich text      | No, arrives as plain or nothing | Untested; docs say text and images only               |
| Files          | Untested; needs FUSE            | Not by clipboard; drag in, `\\tsclient\WebServer` out |

**Open portal quirk.** With real keys, Ctrl+V did nothing while the session had a selection,
until the selection was cleared and the local text copied again. Synthetic pastes after a
remote copy inserted the old remote text instead of the new local text. The exact trigger
is unknown; `stale-probe` is written to find it, and has not yet run against a live client.

## Troubleshooting

| Symptom                                         | Cause and fix                                                            |
|-------------------------------------------------|--------------------------------------------------------------------------|
| Ctrl+C types `©`                                | Stuck Alt. `release-modifiers`, then undo with Ctrl+Z                    |
| Typed case is inverted                          | Remote Caps Lock. `case-check` fixes it                                  |
| Keys and paste stop working at about 5 minutes  | On the demo, its "Logon timer expired" dialog took focus. Screenshot     |
| Session ends at about 7 minutes                 | Demo limit: `ERRINFO_RPC_INITIATED_DISCONNECT`. Sign in again            |
| `X connection to :77 broken`                    | The private display exited. Read `display.log`, then `display-start`     |
| Kerberos errors naming `ATHENA.MIT.EDU`         | Arch's stock `/etc/krb5.conf`. `connect` avoids them; they are not fatal |
| `Domain:` prompt                                | Press Enter unless the account has a domain                              |
| `load_map_from_xkbfile` warnings                | Harmless; they return whenever xdotool remaps a key                      |
| Paste fails, session otherwise fine             | Check policy, then restart `rdpclip.exe` in the session (untested here)  |
| Browser asks to open `xdg-open`                 | The portal's RemoteApp option. Cancel; never tick "Always allow"         |
| Headless Chromium stalls on every page over SSH | It waits on a locked keyring. Add `--password-store=basic`               |
| CDP screenshot hangs on a new tab               | The tab is in the background. Use the `front` step first                 |
| `pkill -f PATTERN` kills your own shell         | The pattern is in your command line. Stop by PID, as `rdp-lab` does      |
| `pgrep -x` finds nothing for a long name        | It only matches 15 characters. `freerdp-shadow-cli3` is too long         |

Server policy can block the clipboard whatever the client does: see "Do not allow Clipboard
redirection" and the direction limits in the research note, and `W.clipboard` in the portal's
publicly readable `software/html5/settings.js`.

## Verification

```bash
bash -n tools/rdp/rdp-lab tools/rdp/portal-test.sh tools/rdp/canvas-test.sh
node --check tools/rdp/cdp-tab.mjs
tools/rdp/canvas-test.sh            # no server needed; throwaway headless Brave
tools/rdp/rdp-lab local-test        # no server needed; loopback FreeRDP
```

`canvas-test.sh` proves a coordinate click and typed keys reach a canvas as trusted events
and that screenshots work. `local-test` proves the display, FreeRDP, input window, and
capture. Its loopback server has no clipboard channel, so clipboard behavior needs a live
session. Both passed on both machines, including over plain SSH and in the desktop's i3
session, and `xfreerdp3` also ran as a normal window on that real i3 display.

The clipboard subcommands of `rdp-lab` and `portal-test.sh` began as scripts that ran against
TSPlus's demo. The versions in this repository have run against the loopback server, and with
stubs for `node` and `xclip`, but not against a live clipboard. The next live session should
rerun them and correct this paragraph.
