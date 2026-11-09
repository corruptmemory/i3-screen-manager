# X11 and Input

Read this guide for i3/IceWM, X11 window identity, keyboard/mouse settings,
rofi dependencies, or clipboard typing. Sources here: `i3-keyboard-rofi`,
`i3-mouse-setup`, `i3-mouse-rofi`, `keybase-popup-anchor-x11`, and `lib/require.sh`.
Desktop configs and X11 launchers live in dotfiles.

## X11 Configuration

Dotfiles has `start-i3`, `start-i3-laptop`, `start-icewm`, and
`start-icewm-laptop` under `.local/bin`, with corresponding `.xinitrc-*` files.
For i3, `.config/i3/config` selects `config-desktop` or `config-laptop`;
Polybar has matching configs and launchers. IceWM uses `.icewm/` on desktop
and `ICEWM_PRIVCFG` for `.icewm-laptop/`. Resolve live symlinks before edits.

i3's desktop config pins workspaces 1-6 to `DP-2` and 7-10 to `HDMI-1`.
The laptop does not use fixed external-output pins. X11 screen layout belongs
in the session setup or display CLI. IceWM's desktops are global; its native
taskbar does not implement independent per-monitor workspaces.

In the configured i3 setup, `exec` runs at session startup and `exec_always`
also runs on an i3 restart; a config reload does not rerun them. Use startup
for long-running daemons and retain single-instance guards on restart hooks.
Validate config with `i3 -C -c PATH`. Live behavior requires the real session;
a single-screen nested X server cannot verify physical multi-monitor layout.

## Keyboard, Mouse, and Clipboard

`i3-keyboard-rofi` toggles `ctrl:nocaps,shift:both_capslock_cancel` versus no
keyboard options. X11 clears options through `setxkbmap -option` before
applying the chosen set. Its Wayland branch reads the live value with `hyprctl
getoption` and applies a choice with `hyprctl eval 'hl.config(...)'`, because
`hyprctl keyword` is gone under the Lua config. A failure raises a critical
notification. A config reload restores the configured options, so the choice lasts
only until then.

Mouse DPI uses solaar at the HID level on either backend. The i3 and Hyprland
autostarts and the IceWM xinitrc files run `i3-mouse-setup` at login. It finds
the paired mouse, caches its name, and applies the saved DPI, 1200 if none is
saved. It exits silently without solaar or a solaar mouse. A mouse that refuses
the setting, as one asleep at login does, gets retries for two minutes and then
a notification. Mouse identity and DPI are stored under
`~/.config/i3-mouse-manager/`. The menu offers 800-2000 and reports a missing
solaar installation or an undetected mouse. When the cached name no longer
answers, as after the mouse is replaced, it looks the mouse up again. Inspect
whether `usbhid` is built into the running kernel before using modprobe
configuration for poll rate; built-in driver parameters belong in the kernel
command line.

All four `i3-*-rofi` menus source `~/.local/lib/sh/require.sh`. Keep its symlink
to this repo's `lib/require.sh` installed. `_require` checks commands and
reports failures on stderr and through `notify-send` when available. Put
dependency checks before pipelines whose failure could make a menu disappear.

The dotfiles emoji picker uses wl-copy on Wayland and xclip on X11; rofi's
selection and the clipboard tool both need to be present. `Super+Ctrl+Space` is
the emoji binding in i3 and Hyprland. Check keysyms case-insensitively when
looking for duplicate Hyprland binds.

Bitwarden lookup is provided by external `rbw`/`rofi-rbw`. Hyprland launches
`rofi-rbw --typer ydotool`; `ydotoold` must be running with `/dev/uinput`
access and a matching runtime socket. Check the actual user ACL before adding
device rules. X11 uses xdotool with a plain rofi-rbw binding. `Super+Alt+V` types
the clipboard, with `wl-paste` and `ydotool` under Hyprland and the desktop's
machine-local `xdtpaste.sh` under i3. Keep typing tests to non-secret sample text.

rofi offers whatever `rbw`'s local copy of the vault holds. rofi-rbw's "Sync
logins" (`Alt+s`) runs `rbw sync` and discards its exit status and message, and
`rbw-agent`'s hourly sync reports nothing either. When the server rejected the
saved login, both machines stayed on months-old copies, missing new entries and
typing old passwords. `rbw-sync-check --watch`, started by every session
(Hyprland autostart, both i3 configs, both IceWM xinitrc files), runs `rbw sync`
two minutes after login and hourly after that. One watcher runs per user. It
raises a critical notification on any failure, repeated at most every six
hours. A network error notifies only once the copy is three days old. A
rejected login (`missing field access_token`) comes with the fix: `rbw purge`,
`rbw login`, `rbw sync`. `rbw login` alone does nothing while the rejected
login is still saved. A sync needs only that saved login, never an unlocked
vault. With no login at all the check does nothing, so it never prompts for the
master password. Without secrets, the copy's age is the mtime of
`~/.cache/rbw/*.json`. Never use `rbw get` in checks; it prints the password.

An unavailable clipboard owner can block X11 paste; inspect the configured clipboard
manager and the owning app before blaming the consumer. i3 runs `copyq`. Hyprland
autostart runs `wl-clip-persist --clipboard regular` from the Artix repos, because
Wayland drops a selection when its source app exits. To check it, copy with `wl-copy
--foreground`, kill that, and run `wl-paste`; without the daemon it reports nothing
copied. Emacs is a GTK build, so under Hyprland it reaches the clipboard through
XWayland.

## Keybase Popup and Application Identity

`keybase-popup-anchor-x11` subscribes to i3 window events. It matches a small
floating Keybase window by class, size, and floating state, then positions it
below the bar on the output containing it. The main window can share the
popup's title during startup; a title-only rule is not sufficient.
`BAR` defaults to 28 and `POPUP_MAX_W` to 1000; the laptop launcher supplies
its bar height. Preserve the `flock` guard and test main-window startup as
well as popup opening.

Hyprland handles the Keybase popup in dotfiles' `autostart.lua`: its
`window.open` callback moves the cursor to the popup's center. Moving the
Wayland popup itself can dismiss it. Keep this backend-specific behavior.

Brave Origin's X11 main class is `Brave-origin`; helper windows can use other
classes. Its X11 PWAs share that class and use `crx_<app-id>` instances.
Wayland PWA classes include the app ID and profile. Electron main and helper
windows can differ in capitalization. Inspect `xprop` or `hyprctl-live clients
-j` and match the intended window, including its size/role when needed.

## X11 and Input Verification

Check the relevant WM config, missing-tool notification, picker cancellation,
both keyboard modes, saved DPI restoration, and clipboard contents. For the
Keybase watcher, test each monitor's tray, opening the main app, i3 restart,
and duplicate-process prevention. Claims about X11 limitations must be checked
against the installed XLibre implementation and application backend; avoid
generalizing from another server version or an app's missing integration.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
