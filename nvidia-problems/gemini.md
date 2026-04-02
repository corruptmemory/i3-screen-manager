Managing a hybrid Intel/NVIDIA setup (often called Optimus) on Hyprland can be tricky because NVIDIA GPUs are notoriously stubborn about staying awake. When your external ports are hardwired to the dGPU, the card *must* be active to drive those displays.

To ensure the NVIDIA card sleeps when those monitors are disconnected, you need to configure **PCI Express Runtime D3 (RTD3) Power Management**.

---

## 1. Enable NVIDIA Power Management
First, you must tell the NVIDIA driver to allow the kernel to manage its power state. You need to create a modprobe configuration file.

**File:** `/etc/modprobe.d/nvidia-power-management.conf`
```bash
options nvidia "NVreg_DynamicPowerManagement=0x02"
```
> **Note:** The `0x02` value is the "Fine-Grained" power management setting, which allows the GPU to enter its lowest power state (D3) when not in use.

---

## 2. Enable Required Services
NVIDIA provides systemd services specifically for saving and restoring the GPU state. You must enable these for the power management handshake to work correctly:

```bash
sudo systemctl enable nvidia-suspend.service
sudo systemctl enable nvidia-hibernate.service
sudo systemctl enable nvidia-resume.service
```

---

## 3. Verify the "D3" Sleep State
Once you have rebooted with the settings above, you can check if the GPU is actually powered down when the external monitor is unplugged.

1.  **Unplug the monitor.**
2.  **Close any apps** that might be using the dGPU (check `nvidia-smi`).
3.  **Check the power status:**
    ```bash
    cat /sys/bus/pci/devices/0000:<your_gpu_pci_id>/power/runtime_status
    ```
    *(You can find your PCI ID using `lspci | grep -i nvidia`. It usually looks like `01:00.0`)*.

If it says **`suspended`**, the card is in a low-power "sleep" state.

---

## 4. Hyprland Specifics (The "Ghost" Monitor)
Sometimes Hyprland or the dGPU will stay "awake" because it thinks a display is still attached or the port is being polled. 

### Use `udev` Rules
You can automate the power-down process by ensuring the NVIDIA VGA controller is set to `auto` power management via a udev rule. 

**File:** `/etc/udev/rules.d/80-nvidia-pm.rules`
```text
# Enable runtime PM for NVIDIA VGA/3D controller devices
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", ATTR{power/control}="auto"
```

### Hyprland Config
In your `hyprland.conf`, ensure you aren't forcing the NVIDIA card to stay awake by naming it as the primary renderer if you want to save battery. Use the Integrated GPU for the portal:
```bash
env = WLR_DRM_DEVICES,/dev/dri/card0:/dev/dri/card1
```
*(Where `card0` is usually Intel and `card1` is NVIDIA. This tells Hyprland to prioritize Intel for the internal display.)*

---

## Summary Checklist
| Component | Requirement |
| :--- | :--- |
| **Driver** | Proprietary NVIDIA driver (v525+ recommended). |
| **Kernel Param** | `nvidia.NVreg_DynamicPowerManagement=0x02` |
| **Udev** | Set power control to `auto`. |
| **Processes** | No apps (like games or OBS) running on the dGPU. |

If you follow these steps, the moment you pull the HDMI/DisplayPort cable, the NVIDIA driver will notice the 0% utilization and transition the hardware into a D3 state, significantly extending your battery life.
