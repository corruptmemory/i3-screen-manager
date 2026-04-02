Yes, but with an important caveat:

On these hybrid laptops, if an external monitor is physically wired through the NVIDIA dGPU, the dGPU generally **cannot fully power down while that monitor is active**. NVIDIA’s own RTD3 docs say the GPU remains active if it is driving a display, and NVIDIA’s Wayland docs say there is no public API for Wayland compositors to power off video memory via RTD3. ([NVIDIA Download][1])

So the practical goal is:

1. run Hyprland primarily on the **Intel iGPU**,
2. include the NVIDIA card only so external outputs work when needed, and
3. enable NVIDIA **runtime power management** so when no external monitor is connected, the dGPU can fall to a low-power or suspended state. ([wiki.hypr.land][2])

## What to do

### 1) Make Intel the primary GPU for Hyprland

Hyprland recommends laptops use the integrated GPU as primary for battery life, and says external monitors attached to another GPU still require that GPU to be listed in `AQ_DRM_DEVICES`. ([wiki.hypr.land][2])

Set `AQ_DRM_DEVICES` so the Intel DRM device is first, and NVIDIA second.

Example:

```ini
env = AQ_DRM_DEVICES,/dev/dri/intel-igpu:/dev/dri/nvidia-dgpu
```

Hyprland specifically recommends using stable symlinks rather than raw `/dev/dri/cardN`, because card numbers can change between boots. ([wiki.hypr.land][2])

So create udev symlinks for both GPUs and use those paths in `AQ_DRM_DEVICES`.

### 2) Enable NVIDIA runtime PM

NVIDIA documents RTD3 support via the kernel runtime PM framework. For maximum savings, runtime PM must be enabled for all NVIDIA PCI functions, and the driver option `NVreg_DynamicPowerManagement` must be enabled. `0x02` is the fine-grained mode. ([NVIDIA Download][1])

Set the module options:

```conf
# /etc/modprobe.d/nvidia-rtd3.conf
options nvidia NVreg_DynamicPowerManagement=0x02
```

Then make sure the PCI functions are set to `auto`:

```bash
echo auto | sudo tee /sys/bus/pci/devices/0000:01:00.0/power/control
echo auto | sudo tee /sys/bus/pci/devices/0000:01:00.1/power/control
echo auto | sudo tee /sys/bus/pci/devices/0000:01:00.2/power/control
echo auto | sudo tee /sys/bus/pci/devices/0000:01:00.3/power/control
```

Replace `0000:01:00.x` with your NVIDIA device functions.

NVIDIA notes that all PCI functions matter, not just `.0`, because audio/USB/UCSI functions can keep the GPU from reaching the lowest power state. ([NVIDIA Download][1])

### 3) Persist the `power/control=auto` settings

Use a udev rule so this happens automatically whenever the NVIDIA device appears:

```udev
# /etc/udev/rules.d/80-nvidia-runtime-pm.rules
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="power/control", ATTR{power/control}="auto"
```

Reload rules:

```bash
sudo udevadm control --reload
sudo udevadm trigger
```

### 4) Rebuild initramfs if your distro needs it

If your distro loads NVIDIA modules in initramfs, rebuild it after changing modprobe options.

Examples:

```bash
# Arch
sudo mkinitcpio -P

# dracut
sudo dracut --regenerate-all --force
```

## How to verify it is actually sleeping

Check runtime PM state:

```bash
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
cat /proc/driver/nvidia/gpus/0000:01:00.0/power
```

NVIDIA exposes RTD3 details in `/proc/driver/nvidia/gpus/.../power`, including runtime D3 status and video-memory status. ([NVIDIA Download][1])

What you want to see with **no external monitor connected** is something like:

* `runtime_status`: `suspended`
* `/proc/.../power`: RTD3 enabled / video memory in self-refresh or off

## Important Hyprland/NVIDIA behavior to expect

Hyprland says that on hybrid setups, if an external monitor is attached to NVIDIA, that NVIDIA card must be included in `AQ_DRM_DEVICES` for the monitor to work. It also notes NVIDIA hybrid multi-GPU support can be flaky, with `AQ_FORCE_LINEAR_BLIT=0` as a possible workaround. ([wiki.hypr.land][2])

So a sensible baseline is:

```ini
env = AQ_DRM_DEVICES,/dev/dri/intel-igpu:/dev/dri/nvidia-dgpu
env = AQ_FORCE_LINEAR_BLIT,0
```

Only keep the second line if you actually see external-monitor issues.

## The hard limit

You asked for “at least power-save or sleep when an external monitor is not plugged in.”

That is the right target. When **no external display is connected**, RTD3 can often suspend the NVIDIA GPU. But when the NVIDIA GPU is the one **driving a display**, NVIDIA says it stays active unless the display path itself is turned off, and Wayland currently lacks the API needed for fuller RTD3 video-memory power-off control. ([NVIDIA Download][1])

## Minimal recommended setup

Use this as the simplest practical recipe:

`~/.config/hypr/hyprland.conf`

```ini
env = AQ_DRM_DEVICES,/dev/dri/intel-igpu:/dev/dri/nvidia-dgpu
```

`/etc/modprobe.d/nvidia-rtd3.conf`

```conf
options nvidia NVreg_DynamicPowerManagement=0x02
```

`/etc/udev/rules.d/80-nvidia-runtime-pm.rules`

```udev
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="power/control", ATTR{power/control}="auto"
```

Then reboot and verify with:

```bash
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
cat /proc/driver/nvidia/gpus/0000:01:00.0/power
```

If you want, I can turn this into an Arch-specific setup with exact commands to discover the Intel/NVIDIA DRM paths and generate the udev symlinks automatically.

[1]: https://download.nvidia.com/XFree86/Linux-x86_64/450.57/README/dynamicpowermanagement.html "Chapter 22. PCI-Express Runtime D3 (RTD3) Power
Management"
[2]: https://wiki.hypr.land/Configuring/Multi-GPU/ "Multi-GPU – Hyprland Wiki"
