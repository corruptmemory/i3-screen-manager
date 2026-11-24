# Power

Read this guide for the laptop's power settings: TLP, the power key and its menu, the
resume hook, low-battery notices, and the known power defects. Sources: `i3-power-rofi`,
`hypr-dpms-all`, and dotfiles' `etc/tlp.d/`, `etc/elogind/`,
`.config/quickshell/BatteryState.qml`, `.config/hypr/hypridle.conf`.

## TLP

TLP runs from the default runlevel with `/etc/tlp.d/01-nomad-artix.conf`, staged in
dotfiles. On AC it sets EPP `performance`, the ACPI platform profile `performance`, and
HWP dynamic boost: the desktop's responsiveness, at the cost of fan noise. On battery it
sets EPP `power` and the platform profile `low-power`. `intel_pstate` runs in active mode,
so `scaling_governor` reads `powersave` on AC too; EPP and the platform profile carry the
choice. Wi-Fi power save is on only on battery; PCIe ASPM and runtime PM are set in both
states. power-profiles-daemon conflicts with TLP and is not installed.

## Power Key and Menu

elogind's drop-in `/etc/elogind/logind.conf.d/20-power-key.conf`, staged in dotfiles, sets
`HandlePowerKey=ignore`, so the key reaches the session instead of powering off at once.
Hyprland, i3 and IceWM on the laptop bind `XF86PowerOff` to `i3-power-rofi`: Lock,
Suspend, Log out, Reboot, Power off. Holding the button about 4 s still forces a firmware
power-off. Lock starts `hyprlock` on Wayland unless one is running, and `i3lock` on X11.
Log out exits Hyprland through `hyprctl-live`, i3 through `i3-msg`, and IceWM through
`icesh logout`; the other entries call `loginctl`. elogind rereads a changed drop-in on
`sudo loginctl daemon-reload` (elogind's `loginctl` has no `reload`) without touching
sessions.

## Sleep Hook

Hypridle blanks the monitors and, on battery, suspends; see
[Capture and Sleep](hyprland.md#capture-and-sleep). The firmware offers only `s2idle`.

`/etc/elogind/sleep.d/50-display-resume`, staged in dotfiles, runs after every resume. It
waits 1 s for the USB-C hub's DisplayPort to re-enumerate, then, for each user with a
Hyprland runtime directory, finds the live instance with `hyprctl instances` and runs that
user's `hypr-dpms-all on`. A stale directory from an earlier session is never used. elogind
runs every executable in `sleep.d`, so keep backups of the hook elsewhere.

## Low Battery

Dotfiles' `BatteryState.qml` singleton reads `/sys/class/power_supply/BAT*` at bar start
and every 30 s for every bar's `Battery` widget, and sends each notice once however many
bars run: normal at 10%, critical at 5%, each once per discharge. `Charging`, `Full` and
`Not charging` count as plugged in, which re-arms both. A bar started below a threshold
sends that notice alone. The widget turns red below 15% on battery. Without a battery the
singleton sends nothing.

UPower keeps its own thresholds in `/etc/UPower/UPower.conf`: low 20%, critical 5%, and
`CriticalPowerAction=Auto` at 2%.

## Known Defects

- **The dGPU never runtime-suspends.** `/proc/driver/nvidia/gpus/*/power` reports
  `Runtime D3 status: Not supported`, and `01:00.0` stays `active` with no suspended time,
  although `NVreg_DynamicPowerManagement=0x02` (`/etc/modprobe.d/nvidia.conf`) is live and
  `/etc/udev/rules.d/80-nvidia-pm.rules` sets `power/control=auto`. The audio function
  `01:00.1` does suspend. Not investigated yet. Read `power/runtime_status` in sysfs:
  `nvidia-smi` and `lspci` wake the card.
- **The critical battery action cannot save the session.** `Auto` hibernates, but the
  kernel command line has no `resume=` and the initramfs no `resume` hook, so the image is
  never restored and the session is lost as with a power-off.

## Verification

After a TLP change run `sudo tlp start`. On AC every CPU's
`energy_performance_preference` must read `performance`,
`/sys/firmware/acpi/platform_profile` `performance`, and
`/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost` 1; `sudo tlp-stat -c` names the
file each value came from. After the power-key drop-in, `busctl get-property
org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager
HandlePowerKey` must read `ignore`, and a press must open the menu.

Run the resume hook by hand while the monitors are blanked: `post suspend` must light
every monitor, and `pre suspend` must exit at once. Check the low-battery decision offline
by running `checkLow()` from `BatteryState.qml` against a fake `root` with `notify()`
recorded; on a real discharge past 10% with two bars, exactly one notice must appear.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
