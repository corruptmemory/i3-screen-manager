# XFCE on X11: toolkit, window management, workspaces, panel widgets

Research note, 2026-10-07. Answers five questions about running XFCE as an X11
desktop on these machines, grounded in the project's current source rather
than recollection. Nothing was installed; the repositories were shallow-cloned
and read. This note is not loaded as agent instructions (see
`CLAUDE.md` "Documentation Boundaries").

## Sources

| Source                                              | State read                                                |
| --------------------------------------------------- | --------------------------------------------------------- |
| `gitlab.xfce.org/xfce/xfwm4`                        | master `d30886f` (2026-08-28); latest stable tag 4.20.0   |
| `gitlab.xfce.org/xfce/xfce4-panel`                  | master `96e7a16` (2026-10-07); stable 4.20.8, dev 4.21.2  |
| `gitlab.xfce.org/panel-plugins/xfce4-genmon-plugin` | master `100218d` (2026-09-25); latest tag 4.3.0           |
| xfce.org blog, wiki `xfwl4_faq`, 4.20 tour          | release context, cross-checked by web search the same day |

Release context: Xfce 4.20 (December 2024) is the current stable series. 4.22
is expected around the end of 2026 and will ship `xfwl4`, a from-scratch
Rust/Smithay Wayland compositor whose preview releases appeared in June and
August 2026. xfwm4 stays the X11 window manager; the project states there are
no plans to drop X11 support.

## 1. Toolkit

GTK 3. Both development branches declare `gtk+-3.0` (`xfwm4/meson.build:45`,
`xfce4-panel/meson.build:46`), so 4.22 remains a GTK 3 desktop. Neither repo
contains GTK 4 work. The porting effort went into `libxfce4windowing`, an
abstraction that lets the panel and applications run on X11 or Wayland; the
panel builds `gdk-x11`/`gtk+-x11` and `gdk-wayland` backends side by side.

## 2. Snapping, tiling, grouping (xfwm4, X11)

xfwm4 is a stacking window manager with Windows-style snap. It has no dynamic
layout engine and no window grouping or tabbing.

| Feature              | Mechanism                                                                                      |
| -------------------- | ---------------------------------------------------------------------------------------------- |
| Magnetic edges       | `snap_to_border` (default on), `snap_to_windows` (off), `snap_width` 10 px, `snap_resist`      |
| Snap by dragging     | `tile_on_move` (default on): left/right edge = half, corner = quarter, top edge = maximize     |
| Snap by keyboard     | `tile_{left,right,up,down,up_left,up_right,down_left,down_right}_key`, `maximize_{horiz,vert}` |
| Move across monitors | `move_window_to_monitor_{left,right,up,down}_key`                                              |
| Grouping / tabbing   | None. The only "group" in the source is the X11 `WM_HINTS` window group used for transients    |

Evidence: tile modes `src/client.h:257-265`; edge/corner thresholds
`src/moveresize.c:790-860`; action vocabulary `src/settings.c` (`parseShortcut`
list); defaults `defaults/defaults`.

Gotcha: `clientMoveTile` returns early when `wrap_windows` is set
(`src/moveresize.c:790`), and the shipped defaults set `wrap_windows=true`.
That option is "wrap workspaces when dragging a window off the screen". With
it on, dragging to an edge switches workspace and never tiles. Turn it off for
edge snapping to engage.

Keyboard defaults are not in xfwm4 itself; `parseShortcut` reads the xfconf
shortcuts channel, which xfce4-settings populates. Bind the tile actions to
Super+arrows in Settings > Window Manager > Keyboard.

## 3. Chrome-free windows, Super+mouse move/resize

Both are supported natively.

Decorations. xfwm4 honours Motif decoration hints at map time
(`src/client.c:1023-1037`) and re-applies them on `PropertyNotify`
(`src/events.c:1673`, `clientGetMWMHints` + `clientApplyMWMHints`). With the
border flag cleared, `frameLeft`/`frameTop` return 0 (`src/frame.c:1216`), so
the window has no frame at all. Per window, live:

```sh
xprop -id WIN -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "2,0,0,0,0"
```

A rule daemon (devilspie2, or a watcher like `keybase-popup-anchor-x11`) can
apply that automatically. Globally, frame geometry is derived from the theme's
image sizes (`frameDecorationTop` returns the title image height,
`src/frame.c:1174`), so a theme with 1 px parts gives near-zero chrome; a 0 px
theme was not tested. `borderless_maximize` is on by default and
`titleless_maximize` exists (off by default).

Mouse. The `easy_click` modifier (default `Alt`) is chosen in Window Manager
Tweaks, Accessibility, "Key used to grab and move windows"; the list is None,
Alt, Control, Hyper, Meta, Shift, Super, Mod1.. (`settings-dialogs/
tweaks-settings.c:49`). The button dispatch (`src/events.c:910-940`):

| Button with modifier | Action                                                          |
| -------------------- | --------------------------------------------------------------- |
| 1 (left)             | raise, then move                                                |
| 2 (middle)           | lower                                                           |
| 3 (right)            | resize; edge or corner chosen from where the window was grabbed |
| 4 / 5 (wheel)        | compositor zoom in/out when `zoom_desktop` is set               |
| 8 / 9 (side)         | previous / next workspace                                       |

So Super+left = move and Super+right = resize is one setting:

```sh
xfconf-query -c xfwm4 -p /general/easy_click -s Super
```

## 4. Workspaces across monitors

Shared. xfwm4 publishes one EWMH desktop list on the root window
(`src/workspaces.c:440`, `_NET_NUMBER_OF_DESKTOPS`); a workspace spans every
monitor and monitors are positions inside it, hence the "Move to Another
Monitor" menu item (`src/menu.c:67`) and the move-to-monitor keys. There is
no per-monitor independent workspace model on X11, unlike i3, Hyprland, or
FVWM3's per-monitor `DesktopConfiguration`.

The panel is written against libxfce4windowing "workspace groups" with
per-monitor membership (`xfce4-panel/common/panel-utils.c`,
`panel_utils_list_workspace_groups_for_monitor`). That abstraction serves
Wayland compositors that expose per-output groups; on X11 there is one group,
so every monitor's pager shows the same set. Panels themselves can be pinned to
a monitor (`output-name`), and the tasklist can be limited to windows on its
own monitor (`monitors-to-include`, formerly `include-all-monitors`).

Implication here: the desktop's split of workspaces 1-6 and 7-10 across the
landscape and portrait monitors has no xfwm4 equivalent; it would become one
shared set with per-monitor tasklists.

## 5. Adding widgets to the panel

Panel widgets are plugins. Discovery is a `.desktop` file in
`<datadir>/xfce4/panel/plugins/` naming a module in
`<libdir>/xfce4/panel/plugins/`; both directories are derived from the
`XDG_DATA_DIRS` prefixes (`panel/panel-module-factory.c:195-240`).

```ini
[Xfce Panel]
Type=X-XFCE-PanelPlugin
Name=Clock
Comment=What time is it?
Icon=org.xfce.panel.clock
X-XFCE-Module=clock
X-XFCE-Internal=TRUE
X-XFCE-API=2.0
```

- `X-XFCE-Internal=TRUE` loads the module in-process; `false` runs it in the
  `xfce4-panel-wrapper` helper, embedded over XEmbed (`GtkSocket` in
  `panel/panel-plugin-external-wrapper-x11.c:95`, `GtkPlug` in
  `wrapper/wrapper-plug-x11.c:55`). The panel rejects any `X-XFCE-API` other
  than `2.0` (`panel/panel-module.c:322`). `X-XFCE-Unique=TRUE` allows one
  instance.
- A compiled plugin subclasses `XfcePanelPlugin` via
  `XFCE_PANEL_DEFINE_PLUGIN(TypeName, type_name)`
  (`libxfce4panel/xfce-panel-macros.h:123`), overrides `construct` and
  `size_changed`, and adds any GTK widget; `plugins/separator/separator.c` is
  the minimal template. GObject Introspection is available for Vala or Python.
- `xfce4-panel --add=NAME` adds a plugin without the preferences dialog
  (`panel/main.c:69`).

Zero-code route: the Generic Monitor plugin (`xfce4-genmon-plugin`, an
external plugin) runs a command on a timer, 30 s by default
(`panel-plugin/main.c:493`), and renders tagged output: `<txt>`, `<img>`,
`<bar>`, `<tool>` (tooltip), `<click>` and `<txtclick>` (actions), `<css>`
(`panel-plugin/main.c:175-350`). It is the Polybar `custom/script` equivalent,
so `agent-usage-polybar` would port by swapping Polybar's `%{T2}`/`%{F}` tags
for genmon markup rather than by a rewrite. Whether `<txt>` accepts Pango
markup was not checked.

## Not verified

- A theme with 0 px frame images (only the mechanism was read).
- Pango markup inside genmon `<txt>`.
- Behaviour of `easy_click=Super` alongside a Super-only key binding such as
  an application menu; the grab is on modifier+button, so no conflict is
  expected, but it was not run.
