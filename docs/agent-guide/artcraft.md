# ArtCraft Apps

Read this guide to launch, bridge, or drive the ArtCraft apps
(https://getartcraft.com/apps), to check what they run on the GPU, or to record
a demo of them. Sources are this repository's `craft-apps` with its table
`craft-apps.toml`, and each app's `docs/mcp.md` and `docs/control-protocol.md`
at its installed tag. The notes hold for the `verified` versions in the table;
recheck them after an update.

## Control Ports and Bridges

The ArtCraft apps start a loopback JSON-lines control server only when launched
with `--control <port>`; PhotoCraft's `integrations.controlPort` preference is
not wired up upstream. `craft-apps.toml` holds one row per app with a fixed
port in 18701-18714 (the same on every machine, below the ephemeral range) and
that app's own control and bridge argv, taken from its docs at the installed
tag. A row is used only once `verified` names a version whose flags were
checked against that release's source or docs and whose bridge passed
`craft-apps probe <app>` with the app stopped and running. Do not check flags
by running the GUI binary: DesignCraft has no `--help` and opens the word as a
file behind an error dialog, and the GridCraft and LightCraft CLIs reject
`mcp --help`. Twelve apps are verified. PdfCraft has no row: its MCP
server is headless only, with no way to attach to the running app. ArtCraft's
row only reserves a port (it was not installed). The AUR recipes build the
tagged `github.com/storytold/<app>` tarball, pinned by SHA-256, with
`cargo fetch --locked` and an offline `--frozen` build; on an update, review
the recipe diff and any new `git+` sources in the release's `Cargo.lock` as
the [package guide](packages.md#aur-audit-contract) describes.

The apps differ in two ways that matter:

- File access. PhotoCraft, FigCraft and VectorCraft take automation roots at
  launch; the table's `[defaults]` grant read and write under `~`. The other
  running apps have no such flags and are not confined, and their bridges
  refuse roots, so the agent reaches any file the user can.
- Authentication. PhotoCraft reads a token from
  `~/.local/state/craft-control/<app>.token` (0600, created before first use
  so a bridge started first can read it). WordCraft writes a new key to
  `~/.config/wordcraft/control-key.local-<port>` each start, and its bridge
  reads it. The rest accept any local client on their port.

`craft-apps install` copies each app's system desktop entry to
`~/.local/share/applications/` under the same id, so the copy replaces the
system launcher in menus, rofi, and MIME defaults. In the copy, the main `Exec`
runs `craft-apps launch <app> %F`; Desktop Actions still start the app
uncontrolled. A marker key records the source entry's SHA-256. `check` reports
`stale` after a package changes the system entry (rerun `install`), and
`remove` restores the system launcher.

`launch` starts the app with its row's `control_args`, waits for the port
(`--wait`), and prints how long the app took from spawn to an answering port
(about 0.25 s for each app on `godlike-artix`). It logs to
`~/.local/state/craft-control/<app>.log`. When the shell's display variables
are missing or stale, as in agent or herdr shells, it finds a live Wayland
socket or X display itself. A `--control` launch bypasses the apps'
single-instance handoff. So while a controlled copy holds the port, `launch`
with files opens them in a separate uncontrolled window and sends a
notification; without files it reports the running copy. Failures also notify,
since desktop launches have no terminal. `stop` closes controlled apps by
sending SIGTERM to the process that holds each port; it warns when an app stays
open, for example while asking about unsaved work.

`register` adds each verified app to Claude Code at user scope as MCP server
`<app>`; rerunning it is a no-op when nothing changed. New servers appear in
new sessions. Six bridges connect on demand (PhotoCraft, FilmCraft, LightCraft,
EffectCraft, SoundCraft, and CADCraft with `--lazy`). The other six (DeckCraft,
DesignCraft, FigCraft, GridCraft, VectorCraft, WordCraft) exit when their app
is down, which would leave the server failed for the whole session. Their rows
set `needs_app_at_start`, and `register` installs `craft-apps bridge <app>`
instead: a lazy proxy that answers the handshake and tool list from
`~/.local/state/craft-control/<app>.mcp.json`. `register` first fills that cache
from the CLI's headless mode, whose tool list matched the connected one for all
six, and no window opens. The proxy starts the real bridge at the first tool
call, refreshes the cache (sending `tools/list_changed` if it changed), and
forwards traffic unchanged. Until that first connection, it rewrites a
headless cache's "Backend: headless" sentence to name the app and port. A call
while the app is down returns a tool error naming `craft-apps launch`. For an
agent, the workflow is `craft-apps launch <app>`, then the `mcp__<app>__*`
tools. Each machine is set up per the README's
[ArtCraft section](../../README.md#artcraft-agent-control-per-machine).

Through a bridge the agent drives the live window: command lists document their
parameters, and screenshot and inspect tools read the window back. Where roots
apply, paths are relative to them (with `~` as the root, `Pictures/x.png`) or
absolute paths inside them. Paths outside are rejected, and an output's parent
directory must already exist. `list` shows installed and verified versions side
by side; after an app update, recheck its flags and probe it before changing
`verified`. The control channel is unencrypted loopback: protect token files,
and remember that most of these ports take commands from any local process
while the app runs. To verify a `craft-apps` change, run `probe` with the app
stopped and running, `check`, and `desktop-file-validate` on a written
launcher.

## Driving the Apps

Every action is a command id with JSON parameters, and most apps have a batch
tool. Discovery calls cost time, so use the ids below when they fit. Look at
the result (a render, screenshot, or read-back) before moving on: several apps
report success while the output is wrong. Rough edges found by driving all
twelve to finished files:

- PhotoCraft: `doc_save` and `doc_export` refuse `quality` except in headless
  mode, and flat formats warn that layers were flattened. Hiding layers marks
  the document dirty, and unsaved work blocks a SIGTERM quit: save first.
  `filter.render.tree` with `newLayer: true` draws procedural trees.
- VectorCraft: start with `file.new {name, width, height, units, backgroundContents}`.
  `draw_shape` and `draw_path` give new art a 1 pt black stroke unless
  `stroke: "none"`. `apply_effect blur.gaussian {radius}` softens glow
  shapes. A PNG export of a transparent document keeps its alpha.
- LightCraft: `import` adds to the user's real library; `photo.delete` moves a
  photo to Recently Deleted and leaves the file. `list_controls` sections:
  `light`, `color`, `effects` (texture, clarity, dehaze only), `vignette`,
  `grading` (shadow/midtone/highlight/global hue, saturation, luminance),
  `grain`. `export {longEdge: 0}` writes the full cropped size. The 0.11.0
  bridge lists 595 tools once connected (28 while the app is down).
- GridCraft: `insert_chart` takes the range's first column as categories and
  needs a contiguous range. Column autofit is
  `home.autofitColumnWidth {cols}`; `sheet.rename {name}`. `screenshot` only
  writes a file.
- CADCraft: `command_line` treats spaces as Enter, so write labels with
  `execute text {at, text, height, justify}`. `script` sends several lines.
  `layer.set` edits a layer's properties without switching to it; use
  `layer.current {name}`, and `laymch {handles, layer}` to move entities.
- WordCraft: `text.insert` is a command, so a whole section fits one `batch`
  with `para.style`, `insert.picture {path, width}` (points), `insert.table`
  and `text.tab`. Alignment set before typing in a Title paragraph is lost:
  align after with `select_text` and `para.align`. `select_text {text,
  occurrence}` is a tool, not a command, so formatting each span costs a
  select call and a command call; keep the target text unique.
- DesignCraft: text that does not fit its frame goes overset with no error
  (a 78 pt headline showed one word); size it to fit or check overset in
  `inspect_document`. `text.select {story, anchor, focus}` takes byte offsets.
  `swatch.create` takes a colour or a gradient of swatch stops, and
  `object.fill {swatch, ids}` applies it.
- FigCraft: start with `file.new`; it may also restore an earlier tab.
  `batch` is one undo step and rolls back entirely on any error.
  `{"$step": n}` stands for step n's id anywhere in later params, `ids`
  included, so a follow-up `node.set` fits in the same batch.
  `image.place {path, parent, x, y, width, height, mode}`; `node.set` takes
  gradient `fills` with `#RRGGBBAA` stops; `view.zoomFit` frames the work.
- DeckCraft: themes include Ember and Nocturne. `design.background {color, index}`
  sets one slide; `format.color` and `format.bold` act on shapes selected with
  `edit.select {ids}`. `insert_chart` takes no position and lands over the
  title; move it with `shape.sizePosition {ids, x, y, w, h}`.
- SoundCraft: `list_commands` appends about 60 `window.*` commands to every
  filter result. MIDI runs at 960 ticks per quarter note (`length_ticks`
  defaults to 480, an eighth). Notes built for 480 per quarter play at double
  speed. `midi.note_add` adds one note per call; for a real part, write a
  Standard MIDI File and run `file.import_midi {path}`, which creates
  instrument tracks (`drum_synth` for channel 10) with the file's tempo.
  `bounce_mix` reports LUFS and peak; `transport.play {from}` plays aloud.
- EffectCraft: `file.import {paths}` returns item ids for
  `layer.addItem {item, time, position, duration}`. A key at the comp's end
  warns that it is outside the layer but still interpolates. Render with
  `renderQueue.add`, then `renderQueue.render {wait: true}`. The H.264 output
  has one keyframe; check frames with `ffmpeg -i f -ss t`. Its bridge keeps
  its connection to an app that has exited: the first call after a relaunch
  fails with "connection closed by the app" (outcome unknown; nothing ran in
  the new app) and a retry reconnects. The other lazy bridges reconnect
  silently.
- FilmCraft: `render_frame` in bridge mode returns the Program monitor, UI
  included, and two concurrent calls collide (one fails "No such file").
  There is no play command; press Space with `ui_key`. Stills keep their
  pixel size until `clip.scaleToFrameSize` runs on the selection
  (`timeline.select {clips}`). `graphics.newText` sets text by its left
  baseline until `graphics.set` gives `align: center`. One second is
  254016000000 ticks.

## GPU Use

Checked on `godlike-artix` (RX 7900 GRE, Mesa RADV) against each app's source
at the version given; recheck after an update. LightCraft, PhotoCraft and
FilmCraft draw their windows with eframe on wgpu and load RADV's Vulkan
driver. `craft-apps launch` passes the environment through, so the variables
below work as `VAR=1 craft-apps launch <app>`, and stderr lands in the app's
log. What else runs on the GPU:

- LightCraft 0.11.0: the develop pipeline runs as WGSL compute for loupe
  renders and 8-bit exports; AI denoise and face detection have GPU paths of
  their own. Raw decode and demosaic, thumbnails, LUT profiles, refined and AI
  (sky, subject) masks, inpaint, and 16-bit, float and HDR output use the CPU.
  A render that fails on the GPU or passes the 2047 MiB buffer limit falls
  back to the CPU; a lost device moves the rest of the session there.
  `LIGHTCRAFT_PROFILE=1` logs `gpu <stage>: N ms` for each GPU render (seen
  for a 4096 px render); `app.gpu` reports the adapter and the last fallback;
  `LIGHTCRAFT_GPU=0` forces the CPU.
- PhotoCraft 0.12.0: the GPU composites only the live canvas (layers, blend
  modes, masks, adjustment and fill layers, layer styles). Filters,
  destructive adjustments, brushes, the gradient tool, and every save, export
  and flatten run on the CPU. `help.systemInfo` shows "Image compositor:
  GPU/CPU"; `ui.inspect` gives `perf.timings.lastRefresh` (`gpu-*` means the
  GPU composited) and `gpuFallback`. `--safe-gpu`, `WGPU_BACKEND` and
  `PHOTOCRAFT_CPU_COMPOSE` change the path.
- FilmCraft 0.10.0: the Program monitor composites on the GPU (YUV to RGB,
  scaling, blend modes, about 33 effects, dissolves); the Source monitor,
  masks, adjustment layers and titles render on the CPU. H.264 and HEVC decode
  through VA-API (the log says "hardware decoding through VA-API"); the other
  codecs are FilmCraft's own software decoders. Encoding is always software
  here: hardware encoding is VideoToolbox or NVENC only, though this card's
  VA-API encodes H.264, HEVC and AV1. Export renders on the CPU unless
  `file.exportMedia` gets `gpuRendering: "auto"` (the Export dialog's
  checkbox), and even then frames the GPU cannot take render on the CPU. The
  default log filter hides the wgpu adapter line;
  `RUST_LOG=warn,filmcraft*=info,egui_wgpu=debug` shows it. `perf.stats`
  reports `gpu` (null when compositing on the CPU) and hardware versus
  software decoded frames; `FILMCRAFT_CPU_COMPOSITE` forces CPU compositing.
- EffectCraft 0.13.0 and 0.14.0 chose wgpu's GL backend and turned its GPU
  compositor off ("needs DirectX 12, Vulkan, Metal or WebGPU") although Vulkan
  works for the apps above; the cause has not been investigated.

## Recording a Demo

Claude Code (2.1.306, auto mode) shows short assistant messages written
between tool calls verbatim, replaces long ones with a one-line paraphrase,
and folds shell output into "Ran N shell commands". Banners or timings meant
for a viewer therefore need their own window, or an overlay added afterwards.
The recorded reel used a Ghostty window with its own X11 instance name
(`--x11-instance-name`; an undotted `--class` is ignored), floated by i3 over
the top of the terminal column so the tiled terminal and app keep their
halves. It redraws a figlet banner whenever a small JSON state file changes.
One shell call per app stops the previous app, logs the chapter, updates the
banner and runs `craft-apps launch`, whose timing line the banner shows.

Rehearse first and keep every successful call. Given the same calls, a
freshly launched app wrote byte-identical files, and most ids (layers,
clips, shapes) came out the same, so the recording replays the log with no
discovery calls; discovery was most of the dead air in an earlier take.
Audio plays in real time and `craft-apps stop` cuts it off, so wait out a
playback before the next app. Check a frame early in the recording, and audio
levels only afterwards. When `ffmpeg` runs under `setsid -f`, the background
PID is the wrapper: take the recorder's PID from `pgrep -n -x ffmpeg` to stop
it with SIGINT. A short keyframe interval (`-g 60`) lets the finished
recording be cut by stream copy within two seconds of the wanted start.
YouTube ignores a description's chapter list when any chapter is shorter than
10 s or the first does not start at 0:00.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
