# Hyprland: Nvidia dGPU Power Saving (Intel + Nvidia Hybrid)

The core strategy is to run Hyprland on the Intel iGPU and let the Nvidia driver's dynamic power management shut the dGPU off when nothing is using it.

---

## 1. Point Hyprland at the iGPU First

Find your device paths:

```bash
ls -la /dev/dri/by-path/
```

Then set the device order in your Hyprland environment (e.g. `~/.config/hypr/hyprland.conf` or via `uwsm`):

```
env = AQ_DRM_DEVICES,/dev/dri/card1:/dev/dri/card0  # intel first, nvidia second
```

Adjust `card0`/`card1` to match your actual iGPU/dGPU paths.

---

## 2. Enable Nvidia Dynamic Power Management

Create `/etc/modprobe.d/nvidia-power-management.conf`:

```
options nvidia NVreg_DynamicPowerManagement=0x02
```

`0x02` = "fine-grained" power control — the driver will cut power to the dGPU when no clients are using it.

---

## 3. Required Kernel Parameters

In your bootloader config, ensure these are set:

```
nvidia_drm.modeset=1 nvidia_drm.fbdev=1
```

---

## 4. Don't Force Nvidia Globally in Hyprland

Avoid setting these globally in `hyprland.conf`, as they force Nvidia rendering and break iGPU setups:

```
# DON'T set these globally:
# env = NVD_BACKEND,direct
# env = LIBVA_DRIVER_NAME,nvidia
# env = __GLX_VENDOR_LIBRARY_NAME,nvidia
```

---

## 5. Optionally Use envycontrol

If you want a clean toggle between iGPU-only and hybrid mode:

```bash
sudo envycontrol -s integrated   # dGPU fully off
sudo envycontrol -s hybrid        # dGPU on-demand
```

---

## Verify It's Working

```bash
# Check power state and wattage (look for P8 and ~0W when idle)
nvidia-smi

# Should show "suspended" when dGPU is idle
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
```

The dGPU should suspend within a few seconds of nothing using it. When an external monitor is plugged in (routed through Nvidia), Hyprland/aquamarine will wake it automatically.
