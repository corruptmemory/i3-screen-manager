# Applications

Read this guide for Ghostty/Brave identity and config deployment, chat layout,
GTK dialogs, or application-specific desktop integration. Sources are chiefly
dotfiles' launchers, `.desktop` overrides, WM rules, and terminal configs.

## Configuration and Window Identity

Resolve `~/.config/ghostty`, `~/.config/kitty`, and browser launcher paths on the
machine before editing. Shared files in dotfiles and live copies can differ.
Ghostty is the configured default terminal. Validate its parsed settings with
`ghostty +show-config`; keep comments on their own lines. Use a valid dotted
application ID with `--class` for Wayland rules and the configured
`--x11-instance-name` for X11 rules. Inspect user `.desktop` overrides when
single-instance or D-Bus activation changes window placement.

Brave Origin's profile directories are machine-local. `machine.lua` supplies
the alternate-profile directory to Hyprland launchers; do not assume identical
`Profile N` slots across hosts. Browser/PWA flags are determined by the first
process using the profile. If remote-debugging flags are required, launching
a PWA first without them can prevent a later browser command from applying
them. Inspect the running command and local launcher before changing flags.

Native-messaging host manifests and MIME associations are local integration
points. Recheck their paths when changing browser packages or profiles. For
broken Gmail link navigation, inspect the new tab's request chain: a redirect
into an extension resource indicates a different problem from a blocked
request or a window-manager focus rule. Fix a request-matching extension rule
at the affected request domain rather than assuming the originating tab's
domain is the relevant setting.

## Chat Layout

Dotfiles' `i3-chat-launch` selects the session-specific builder. The i3 path
uses `append_layout` and swallow criteria; its rebuild helper can close and
relaunch the chat windows. The Hyprland builder `hypr-chat-layout` launches
missing apps, selects their primary windows, parks targets on a special
workspace, and serially forms Messages/WhatsApp and Discord/Keybase/Slack
groups on workspace 10. Group order and group locking are part of the
algorithm; app startup and largest-window selection handle transient helpers.
Rerunning rebuilds the grouping of existing windows. It can visibly move
windows and must remain a shell workflow because it waits for mapping.

The desktop has the chat builder integration. Shared Hyprland rules place
chat apps on workspace 10 on the laptop, but do not infer an automatic laptop
chat-wall build. Consult the actual autostart entries; a provided helper is
not necessarily enabled at login. Verify repeat invocation, missing apps,
main-window selection, tab order, and focus restoration after builder changes.

## GTK File Dialogs

For slow file dialogs, compare `gio info trash:///` with the same query under
`GIO_USE_VFS=local`. A GVfs trash-backend timeout can delay dialog construction.
The local VFS setting bypasses GVfs backends such as trash and network shares;
place it in the intended session/app environment if that behavior is wanted.
Check package reverse dependencies before removing GVfs. Do not reproduce
package-removal commands from an assumed dependency graph.

## Application Verification

Check the resolved config, effective settings, actual window identity, and
fresh versus already-running app launches. Exercise both Wayland and X11
paths when the change affects shared launchers. Prefer non-secret fixtures
for browser, clipboard, and password-manager integration checks.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
