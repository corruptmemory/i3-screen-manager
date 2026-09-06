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
applying the chosen set. Its Wayland branch still uses legacy `hyprctl
getoption`/`keyword` and needs Lua-mode work; do not describe that branch as
fully compatible with the current config.

Mouse DPI uses solaar at the HID level on either backend. `i3-mouse-setup`
defaults to 1200 and restores the saved value; the menu offers 800-2000.
Mouse identity and DPI are stored under `~/.config/i3-mouse-manager/`.
The login helper quietly skips unavailable hardware; the menu reports a
missing solaar installation or an undetected mouse. Inspect whether `usbhid`
is built into the running kernel before using modprobe configuration for poll
rate; built-in driver parameters belong in the kernel command line.

All four `i3-*-rofi` menus source `~/.local/lib/sh/require.sh`. Keep its symlink
to this repo's `lib/require.sh` installed. `_require` checks commands and
reports failures on stderr and through `notify-send` when available. Put
dependency checks before pipelines whose failure could make a menu disappear.

The dotfiles emoji picker uses wl-copy on Wayland and xclip on X11; rofi's
selection and the clipboard tool both need to be present. `Super+period` is
the Hyprland emoji binding; its float toggle occupies `Super+Ctrl+Space`.
Check keysyms case-insensitively when looking for duplicate Hyprland binds.

Bitwarden lookup is provided by external `rbw`/`rofi-rbw`. Hyprland launches
`rofi-rbw --typer ydotool`; `ydotoold` must be running with `/dev/uinput`
access and a matching runtime socket. Check the actual user ACL before adding
device rules. X11 uses xdotool with a plain rofi-rbw binding. Keep typing tests
to non-secret sample text. An unavailable clipboard owner can block X11 paste;
inspect the configured clipboard manager and the owning app before blaming
the consumer.

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
