# Garmin Express on Linux: Wine Attempt and the Path Forward

Status: **Wine route abandoned 2026-05-26.** This doc captures the attempt so we don't repeat it, and lays out the Windows-VM path for when we're ready.

## The actual problem

The desktop got converted away from Windows during the home-server experiment. The single thing the user actually used Windows for was **Garmin Express** — specifically, **map updates** for:

- **GPSMAP 67i** — handheld GPS, USB mass-storage class
- **Edge 840** — cycling computer, mixed protocol
- **Forerunner 970** — running watch, proprietary protocol

(The Varia RTL515 and Index Sleep Monitor update via Bluetooth/ANT+ from the Edge/phone — they're not Garmin-Express clients. They're red herrings.)

Firmware updates already happen over WiFi/Bluetooth on all three GPS devices. **Maps are the only remaining Windows dependency** — Garmin's regional map packs (TopoActive North America, Cycle Map, etc.) are entitlement-gated behind Garmin Express's licensing layer and don't come down over WiFi.

## What we tried: Wine + winetricks

System at the time of the attempt:
- Arch Linux on `godlike-artix` (the desktop)
- Hyprland 0.55.2 (Wayland) with XWayland for X11 apps
- Wine 11.9 (multilib repo)
- winetricks 20260125
- Garmin Express installer `GarminExpress.exe` v7.28.1.0

The standard advice circa 2024 (multiple WineHQ + GitHub Gist guides) recommends a 32-bit prefix with .NET 4.6 and Visual C++ 2010. That recipe is now wrong on two counts — see below.

### Failure 1: `WINEARCH=win32` no longer works

Wine 10+ dropped pure 32-bit prefix support. Modern Wine runs 32-bit binaries via WoW64 inside a 64-bit prefix. Error: `wine: WINEARCH is set to 'win32' but this is not supported in wow64 mode.`

**Fix:** drop `WINEARCH=win32`. Create the prefix with just `WINEPREFIX=$HOME/.garmin_express wineboot`. The 32-bit `express.exe` runs fine via the WoW64 layer.

### Failure 2: `dotnet46` is too old for Garmin Express 7.28

Older guides recommend `.NET Framework 4.6` (release 393297). Garmin Express 7.28.1.0's WiX bootstrapper hard-requires .NET 4.7.2 (release 461808+) and tries to install `NetFx472Redist` from Microsoft. Wine's incomplete Authenticode certificate chain implementation fails to verify the redistributable's signature with HRESULT `0x80070490`, the bundler retries 3× then aborts with the unhelpful "Garmin Express could not be installed on this computer" dialog.

**Fix:** install `.NET 4.7.2` via winetricks BEFORE running the Garmin installer. Then the bundler's pre-flight check sees `NETFRAMEWORK_RELEASE >= 461808`, skips the `NetFx472Redist` payload entirely, and the cert-chain bug never gets hit.

```bash
# Sequence that actually got the bundler to "Successfully installed":
WINEPREFIX=~/.garmin_express winetricks -q win7 corefonts vcrun2010
WINEPREFIX=~/.garmin_express winetricks -q vcrun2019 dotnet472
# Then run the installer:
WINEPREFIX=~/.garmin_express wine ~/Downloads/GarminExpress.exe
```

(Note: `dotnet472` takes 15-25 minutes because winetricks runs Microsoft's actual `NDP472-KB4054530-AllOS-ENU.exe` installer inside Wine, and it has to NGEN-compile ~2000 .NET assemblies to native code. The installer visually appears hung at ~65%. It isn't — it's NGEN'ing `mscorlib.dll`. Wait it out.)

### Failure 3: CEF renderer subprocess never paints

Garmin Express's UI is built on **CefSharp** — the .NET wrapper around the Chromium Embedded Framework. The main `express.exe` process spawns specialized Chromium subprocesses on demand: a network service, a GPU process, and one or more renderer subprocesses. CEF was bundled inside the install directory (`libcef.dll`, `cef.pak`, `chrome_elf.dll`, etc.), so no external WebView2 dependency.

The main window's chrome (title bar, menu, system-tray-quit dialog) rendered fine. The content area (which is where the entire app UI lives) was **completely black**. Right-clicking the tray icon → "Quit" produced a modal that *did* render, which forced a single Win32 paint event in the content area too — but as soon as the modal closed, content area went black again.

Confirmed via `ps`: the network subprocess was alive, but **no `--type=renderer` subprocess existed**. The renderer was either failing to spawn or dying immediately.

**Hypotheses tried (none fixed it):**
- CEF `--disable-gpu --disable-gpu-compositing` flags → no effect, renderer still missing
- CEF `--single-process` mode → main process stayed alive but content still black
- Hyprland windowrule with `opaque + no_blur + no_dim + no_anim + no_shadow` for `express.exe` → no effect
- Disable Hyprland VRR (`misc:vrr = 0`) → no effect
- Replace the Rofi `.desktop` `Exec` to bypass the .lnk shortcut and set CWD via `sh -c 'cd ... && exec wine ...'` → no effect

### Failure 4: `WinDeviceWatcher` triggers an unhandled exception that the CLR can't unwind

Wine's exception trace showed two interleaved problems:

1. **`exception code=6ba (RPC_S_SERVER_UNAVAILABLE)`** thrown in Garmin's device-enumeration codepath. Garmin Express's `WinDeviceWatcher` class calls into Win32 / WMI APIs to enumerate connected USB devices. Wine's WMI implementation is incomplete; some RPC endpoints simply don't exist. Garmin's exception handler catches this, **but then…**

2. **The .NET CLR enters an infinite `RtlUnwindEx code=80000026` loop.** `STATUS_LONGJUMP` is the .NET CLR's internal mechanism for stack unwinding during exception propagation. Wine's `RtlUnwindEx` implementation under WoW64 doesn't clear a flag correctly, so the CLR unwinds the same frame forever. The process either hangs or eventually drops.

This is the wall. It's a runtime-level interaction between Wine 11.9's WoW64 and the .NET 4.7.2 CLR's exception machinery — not something we can fix by installing more winetricks verbs or tweaking flags.

### Other curiosities encountered

- **WinRT (Windows.Foundation.*) gaps**: `err:combase:RoGetActivationFactory Failed to find library for L"Windows.Foundation.Diagnostics.AsyncCausalityTracer"`. Wine has limited WinRT support; modern .NET apps using `async`/`await` infrastructure may touch WinRT pieces that don't exist.
- **ANT drivers skipped silently**: the bundler tried to install `AntDriversX64` (the kernel driver for the ANT+ USB stick). Wine can't load Windows kernel drivers, but the bundler doesn't hard-fail — it just records the failure and proceeds. Harmless for the GPSMAP 67i (mass-storage) but means we'd never be able to talk to ANT-only accessories via Wine.

## What we left in place vs. cleaned up

Removed:
- `~/.garmin_express/` (2.4 GB Wine prefix)
- `~/.local/share/applications/wine/Programs/Garmin/Garmin Express.desktop` (Rofi entry)
- `~/.local/share/applications/wine-protocol-garminexpress.desktop`
- `~/.local/share/applications/wine-protocol-connectagent.desktop`
- `~/.local/share/applications/wine-extension-*.desktop` (10 file-type handlers)
- `~/.config/menus/applications-merged/wine-Programs-Garmin-Garmin Express.menu`
- The temporary `windowrule { match:class = ^(express\.exe)$ … }` block from `hyprland-desktop.conf` (reverted)
- The temporary `hyprctl keyword misc:vrr 0` override (`hyprctl reload` restored it from config)

Left in place (these have no Garmin-specific footprint and may be useful for future Wine work):
- `wine` and `winetricks` packages
- `lib32-openal` and `lib32-mpg123` packages (installed during the attempt; harmless)
- `~/.cache/wine/` (cached wine-mono/wine-gecko MSI installers, ~100 MB)
- The `GarminExpress.exe` installer at `~/Downloads/` (in case we want to feed it to a Windows VM later — see below)

## Path forward: Windows VM via QEMU/KVM + virt-manager

This is the route to take when there's time to set it up. Total estimated time: 60-90 minutes one-time setup. Then boot 2-4× per year for map updates.

### Step 1 — install the virt stack

```bash
# Note: qemu-base is the headless QEMU; virt-manager is the GUI; iptables-nft is
# needed for libvirt's NAT networking; edk2-ovmf provides UEFI firmware images.
yay -S --needed qemu-base virt-manager iptables-nft dnsmasq edk2-ovmf swtpm
```

### Step 2 — enable libvirt

```bash
# Artix uses runit/openrc/dinit/s6 depending on which init was picked at install.
# Confirm which one and start libvirtd accordingly. On this machine (runit):
sudo ln -s /etc/runit/sv/libvirtd /run/runit/service/
sudo sv up libvirtd
sudo sv status libvirtd     # expect: run

# Add jim to the libvirt group so virt-manager doesn't need sudo each time
sudo usermod -aG libvirt $USER
# Log out and back in (or newgrp libvirt) so the new group takes effect
```

### Step 3 — grab a Windows 11 ISO

Microsoft offers it directly with no license/activation needed for unlimited time (you get a watermark and disabled personalization, neither of which matters for running Garmin Express twice a year):

  https://www.microsoft.com/software-download/windows11

Save the ISO somewhere like `~/Downloads/Win11.iso`.

### Step 4 — create the VM in virt-manager

GUI walkthrough:
1. Launch `virt-manager`.
2. **File → New Virtual Machine → Local install media**, point at the Win11 ISO.
3. Memory: **4096 MB** is plenty. CPUs: **2**.
4. Storage: **30 GB** qcow2 (sparse — only grows as Windows writes to it).
5. Network: default NAT (allows internet for Garmin's auth + map downloads).
6. On the final screen, **check "Customize configuration before install"**.

In the customize panel:
- **Overview → Firmware**: switch from BIOS to **UEFI** (Windows 11 requires it). Pick the `OVMF_CODE_4M.fd` variant.
- **Add Hardware → TPM**: emulated TPM 2.0 (Win11 requires it). Backend: `Emulated`, version `2.0`, model `CRB`.
- **CPU**: under "Configuration", check "Copy host CPU configuration" — needed for some Windows-11 CPU compatibility checks.
- **Display Spice → Video**: model `Virtio` (fast).
- Click **Begin Installation**.

Click through Windows setup. When it asks "Sign in with a Microsoft account", you can bypass it by hitting Shift+F10 to open cmd and running `oobe\BypassNRO` (which reboots the installer into the "I don't have internet" path → "Continue with limited setup" → local account). Set up local user "jim" (or whatever).

### Step 5 — USB passthrough for the Garmin devices

Inside virt-manager, with the VM running:
1. **View → Details → Add Hardware → USB Host Device**.
2. Pick the connected Garmin device from the list.
3. Click Finish. Windows inside the VM will pop up a "new device detected" toast and mount the GPS as a USB drive.

Alternative — set up a USB filter so the Garmin auto-attaches whenever you plug it in:
- **VM → Details → USB → Add USB redirector** for the appropriate vendor:product ID
- Find the ID with `lsusb | grep Garmin` on the host

### Step 6 — install Garmin Express inside the VM

Easiest: download `GarminExpress.exe` fresh inside the VM's browser (Edge ships with Windows). Run it. Native Windows. It Just Works.

(Optional: share the host `~/Downloads/GarminExpress.exe` with the VM via virt-manager's filesystem share or by adding a `9pfs` mount. Not worth the trouble for one installer download.)

### Step 7 — daily-driver workflow

When you have maps to update:
1. `virt-manager` → start the VM
2. Plug in the GPSMAP 67i (or Edge 840 / Forerunner 970)
3. Switch the USB device into the VM (auto if filter set up)
4. Open Garmin Express inside Windows, do whatever
5. Eject the device from inside Windows
6. Shut down Windows (or just close the VM window — virt-manager will ACPI-soft-shutdown)

The VM consumes nothing when not running.

## Fallback option: manual OSM-derived map drops (GPSMAP 67i only)

If the VM is overkill for occasional updates and you can live without Garmin's paid TopoActive packs, the 67i mounts as a regular USB mass-storage device on Linux. Drop `.img` files into its `Garmin/` folder. Free sources:

- **talkytoaster.me.uk** — excellent UK/Europe topo (OSM-derived)
- **openmtbmap.org** — worldwide MTB/hiking-focused
- **garmin.openstreetmap.nl** — global OSM coverage, region-by-region downloads

Zero Wine, zero VM. But this doesn't cover the Edge 840 or Forerunner 970 (different filesystem layouts and entitlement-gated maps), and it doesn't refresh the Garmin-licensed `.gma` map files that came bundled with the 67i.

## Lessons

- **The perplexity research's recipe was 2 years stale**: `WINEARCH=win32`, `dotnet46`, `vcrun2010` — none of those are right for Garmin Express 7.x on Wine 11.x. When the research dates from a different era of Wine's WoW64 transition AND the target app has shipped multiple major versions, treat the recipe as a starting hypothesis, not a working solution.
- **CefSharp/Electron-style apps are uniquely hostile to Wine** because they rely on Chromium's multi-process model + Win32 RPC + .NET CLR exception machinery — three places where Wine has known coverage gaps that compound.
- **"Modern Garmin app" + Wine is not a tractable problem** in 2026 without a Wine fork that specifically targets these workloads. None exists. The next time someone asks if Wine can run a CefSharp .NET app, the answer is "probably not for very long."
- **Be more bearish, earlier**, when the user says they're bearish. They were right.
