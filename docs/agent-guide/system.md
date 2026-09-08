# System Maintenance

Read this guide for hardware, OpenRC services, the Tailscale helper, CMOS
monitoring, or VM setup. Sources: `start-hyprland`, `i3-tailscale-rofi`,
`i3-cmos-battery`, `volumecontrol.sh`, and `win11-vm-setup.sh`. Check active
machine state before applying configuration outside this repository.

## Service and GPU Boundaries

Use OpenRC service tools on these machines and elogind's `loginctl` for session
operations. The user D-Bus socket is `/run/user/<uid>/bus`; launchers export
its address. Gnome-keyring owns secrets/PKCS#11; a separate OpenSSH agent uses
`$XDG_RUNTIME_DIR/ssh-agent.sock`. Check whether that agent is live and whether
keys are loaded separately. Keep desktop-session and laptop-user-service
ownership of PipeWire distinct.

The laptop launcher uses stable DRM PCI paths for Intel `0000:00:02.0` and
NVIDIA `0000:01:00.0`. Hybrid mode lists Intel first in `AQ_DRM_DEVICES`, then
NVIDIA for the external ports; discrete mode selects NVIDIA alone. Only the
discrete branch forces `GBM_BACKEND=nvidia-drm` and NVIDIA GLX. Hybrid uses
Intel VA-API (`iHD`). Do not apply these laptop-specific paths or driver
overrides to the AMD desktop launcher in dotfiles.

The laptop firmware supports Hybrid and Discrete graphics modes. Changing
that mode requires a reboot and changes GPU availability and power use.
For poor external rendering, inspect actual GPU routing, DRM modeset state,
and frame behavior before adjusting compositor settings. A historical symptom
does not establish the current driver stack's performance.

`volumecontrol.sh` forces the Intel Vulkan ICD for pavucontrol. Treat this as
a hardware-specific wrapper rather than a universal audio requirement.

A USB DAC with a gain-only hardware volume (the desktop's Kanto ORA4 exposes
0 to +16 dB, no attenuation) leaves a silent range below its unity base under
the default ACP path, because the sink volume rides the hardware route. Force
software volume with a machine-local WirePlumber drop-in in
`~/.config/wireplumber/wireplumber.conf.d/` that sets `api.alsa.use-acp=false`
on the card and `api.alsa.soft-mixer=true` on the node; a node-only soft-mixer
does not override ACP. Confirm by watching the hardware mixer stay fixed while
the graph volume changes. This drop-in is desktop-local, not carried by dotfiles.

## CMOS Monitoring

`i3-cmos-battery` reads an it87-family `Vbat` hwmon input in millivolts.
Thresholds are OK at >=2800, LOW at 2500-2799, and DEAD below 2500. No sensor
produces no output. `polybar` is the default output and emits markup;
`quickshell` emits `<volts> <status>`; `cli`/`--cli` emits a report. Polling is
owned by the bar. Keep thresholds and output shapes shared between consumers.

## Tailscale and Open Brain

`i3-tailscale-rofi` controls the local daemon and rewrites only the Open Brain
URL in `~/.claude.json`. It does not update Codex's MCP configuration. Its LAN
URL, tailnet endpoint, and `tailscale up --hostname=nomad-artix
--accept-dns=false` arguments are machine-specific. Read them before adapting
the script. Open Brain must be reachable on its configured interface/port.
The menu also supports login and a manual URL toggle. Preserve other JSON
fields and avoid logging authentication headers while investigating failures.

## VM Setup

`win11-vm-setup.sh` is a privileged host-setup program for QEMU/KVM and libvirt,
run as the normal user with sudo available. It checks AMD `svm` and `/dev/kvm`,
installs packages, configures libvirt group access, enables OpenRC services,
starts NAT networking, creates the `vms` pool at `/data/vms`, and optionally
downloads virtio drivers. On btrfs it applies nodatacow to the image directory.
Group changes require a fresh login. It may restart services on a rerun.

Its AMD preflight, storage path, and libvirt `auth_unix_rw=none` choice must be
reviewed before use on another host. It does not create or install the Windows
guest. Do not run it as a documentation or syntax check.

For a guest, use the system libvirt connection, select UEFI/Secure Boot and a
TPM 2.0 device, allocate suitable memory/CPU and disk in the intended pool,
and supply the Windows installation ISO. A virtio disk needs its matching
Windows driver; SATA avoids that installation-time dependency. Install Garmin
Express in Windows and attach the device via USB Host Device or the console's
USB-redirection control. USB-device passthrough is distinct from PCI/VFIO
passthrough. Check `virsh list --all`, `net-list --all`, and `pool-list --all`
for actual host/guest state instead of relying on an old completion checklist.

## System Verification

Use read-only configuration, package, service, device, and connection queries
first. Verify both the intended state and user-visible behavior after a system
change. Check absent-sensor output, Tailscale failure/auth paths, and the
actual VM storage and service state when their respective tools change.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
