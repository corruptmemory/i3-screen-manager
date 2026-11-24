# Power

Read this guide for the laptop's power settings: TLP, the power key and its menu,
hibernation, the resume hook, low-battery notices, and the known power defects. Sources:
`i3-power-rofi`, `hypr-dpms-all`, and dotfiles' `etc/tlp.d/`, `etc/elogind/`,
`etc/default/grub.d/`, `etc/UPower/`, `etc/pacman.d/hooks/95-nvidia-rtd3-check.hook`,
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

## Hibernation

The image goes to the swap partition, `/dev/nvme0n1p3`: 64 GiB against 62 GiB of RAM.
Dotfiles' `etc/default/grub.d/60-nomad-artix.cfg` adds `resume=UUID=83bc52c1-…` to the
kernel command line. `/etc/mkinitcpio.conf`, in no repository, puts the `resume` hook
after `block` and before `filesystems`, so the image is read before root is mounted.
`loginctl hibernate` writes the image and powers off through ACPI S4. Only that command
and UPower's critical action (see [Low Battery](#low-battery)) hibernate; the lid and
hypridle suspend. The NVIDIA driver saves video memory through its kernel suspend
notifiers (`NVreg_UseKernelSuspendNotifiers=1`, files in `/var/tmp`), so it needs no
sleep hook.

nvidia must stay out of the initramfs: `MODULES=(i915)`. udev loads it from the root
filesystem about 7 s into boot, with its `/etc/modprobe.d` options. When the boot kernel
had loaded nvidia before the restore, its freeze callback refused (`nv_pmops_freeze …
returns -5` after "System Power Management attempted without driver procfs suspend
interface"). nvidia 620's notifier handles `PM_HIBERNATION_PREPARE` but not the boot
kernel's `PM_RESTORE_PREPARE`. The kernel then abandoned the image ("Failed to load
image, recovering") and booted fresh. `/etc/conf.d/bootmisc` sets `previous_dmesg=yes`:
OpenRC rewrites `/var/log/dmesg` at every boot, and a failed boot's log now survives one
reboot as `/var/log/dmesg.old`.

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
an action at 2%. Dotfiles' `etc/UPower/UPower.conf.d/70-nomad-artix.conf` makes that
action `Hibernate`. UPower 1.91 turns the stock `Auto` into logind's `Sleep`, which
elogind reports unavailable (`CanSleep` answers `na`), so `Auto` falls through to
`Ignore` and the battery runs flat. UPower is started by D-Bus, not OpenRC: after a
config change, `sudo pkill -x upowerd`, and the next query starts it again.

## Known Defects

- **The dGPU's runtime suspend depends on a local driver patch.** Linux 7.3 starts kernel
  threads in an empty root, so stock nvidia-open's `nv-probe-*` thread cannot open
  `/sys/bus/pci/devices/…/config` and turns dynamic power off at probe, logging nothing
  visible: `/proc/driver/nvidia/gpus/*/power` reads `Runtime D3 status: Not supported`
  (NVIDIA/open-gpu-kernel-modules#1507). The fix, PR #1512, is applied by hand to
  `/usr/src/nvidia-620.73.04` and built with DKMS; with it the file reads `Enabled
  (fine-grained)` and the GPU and its root port reach D3cold. A new `nvidia-open-dkms`
  ships unpatched source unless it contains `scoped_with_init_fs`: reapply as
  `~/.local/share/nvidia-rtd3/README` says, then reboot. Dotfiles'
  `95-nvidia-rtd3-check.hook` warns after each `nvidia-open-dkms` install or upgrade
  whose source lacks the fix; it never patches. Until then an unbind and bind from user
  context, with nothing holding the card, restores it until reboot. Read
  `power/runtime_status` in sysfs: `nvidia-smi` and `lspci` wake the card.
- **A failed restore leaves the panel dark.** After the kernel abandons an image, the
  fresh boot runs normally (network, Rex and the lid switch work), but fbcon never logs
  `Taking over console`, so the internal panel stays black. Seen only while nvidia was
  in the initramfs; the cause is not established. Reach the laptop over SSH or Rex, or
  force a power-off and boot again.

## Verification

After a TLP change run `sudo tlp start`. On AC every CPU's
`energy_performance_preference` must read `performance`,
`/sys/firmware/acpi/platform_profile` `performance`, and
`/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost` 1; `sudo tlp-stat -c` names the
file each value came from. After the power-key drop-in, `busctl get-property
org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager
HandlePowerKey` must read `ignore`, and a press must open the menu.

After a hibernation change, `/sys/power/resume` must read `259:3`, and a fresh boot's
`dmesg` must show `PM: Image not found (code -22)`, proof that the `resume` hook looked.
`loginctl hibernate` must come back with the same `/proc/sys/kernel/random/boot_id` and
`ACPI: PM: Waking up from system sleep state S4`; a new `boot_id` means the image was
abandoned, and `/var/log/dmesg.old` says why. `test_resume` in `/sys/power/disk` writes
and restores the image in one boot, so it never exercises the boot kernel. Its log looks
cut short because the log buffer is restored with the image. `busctl call
org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower GetCriticalAction`
must answer `Hibernate`, and `sudo /etc/pacman.d/scripts/nvidia-rtd3-check` must report
the RTD3 fix in the current driver source.

Run the resume hook by hand while the monitors are blanked: `post suspend` must light
every monitor, and `pre suspend` must exit at once. Check the low-battery decision offline
by running `checkLow()` from `BatteryState.qml` against a fake `root` with `notify()`
recorded; on a real discharge past 10% with two bars, exactly one notice must appear.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
