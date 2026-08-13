# Windows 11 VM on Artix (QEMU/KVM + libvirt) — for Garmin Express + USB passthrough

**Date:** 2026-08-13 · **Machine:** `godlike-artix` (Artix, OpenRC/elogind,
AMD Threadripper 3970X) · **Goal:** run **Garmin Express** to update device map
data before a trip — it never worked under Wine, so run it in a real Windows 11
guest with the Garmin plugged through via **USB passthrough**. VirtualBox
deliberately avoided; this is the QEMU/KVM + libvirt + virt-manager stack.

## STATUS (as of 2026-08-13)

- **§1 Hardware/BIOS verification — DONE** (below; nothing to change in UEFI).
- **§2 Package plan — DONE** (analysis below).
- **§3 Automation script — WRITTEN, NOT YET RUN.** The install/config in
  `win11-vm-setup.sh` (repo root) has **not** been executed. Nothing is installed
  yet: no `qemu`/`libvirt`, no services, no `libvirt` group, no `/data/vms`.
- **Next action:** run `bash win11-vm-setup.sh`, then log out/in for the group,
  then build the VM in virt-manager (§4). Update this STATUS line when done.

## §1 — Virtualization is enabled (no BIOS change needed)

The definitive test of "is virtualization enabled in firmware" is the `svm` CPU
flag: the kernel strips it from `/proc/cpuinfo` when *SVM Mode* is disabled in
UEFI, so **its presence proves it's on** — no reboot-into-BIOS required.

```sh
lscpu | grep -iE 'model name|Virtualization'   # AMD Ryzen Threadripper 3970X / AMD-V
grep -q svm /proc/cpuinfo && echo enabled       # svm PRESENT (64 threads) -> enabled
ls -l /dev/kvm                                   # crw-rw-rw- root kvm -> KVM live
lsmod | grep kvm                                 # kvm_amd + kvm loaded
ls /sys/kernel/iommu_groups/ | wc -l             # 72 -> AMD-Vi IOMMU active (bonus)
```

Result: AMD-V enabled, `/dev/kvm` present, `kvm_amd` loaded, 72 IOMMU groups.
USB **device** passthrough (what Garmin needs) does not require IOMMU/VFIO — that
is only for full PCI passthrough (e.g. GPUs). So nothing here gates the plan.

## §2 — Package plan (all official repos; no AUR)

| Package | Repo | Why |
|---|---|---|
| `qemu-desktop` | extra | the emulator + GUI display |
| `libvirt` | extra | management daemon/API |
| `libvirt-openrc` | **world (Artix)** | OpenRC init scripts — the Artix glue for the Arch libvirt build |
| `virt-manager` | extra | the "easy button" GUI |
| `virt-viewer` | extra | SPICE console viewer |
| `edk2-ovmf` | extra | **UEFI firmware — Windows 11 requires it** |
| `swtpm` | extra | **software TPM 2.0 — Windows 11 requires it** |
| `dnsmasq` | extra | libvirt default NAT network (VM internet for Garmin downloads) |
| `usbredir` | extra | USB device redirection (Garmin passthrough) |
| `spice-gtk` | extra | SPICE client + USB-redirect UI |

Notes verified during investigation:

- **No systemd on Artix:** `libvirt` pulls `systemd-libs` (the shared *library*
  `libsystemd.so`, used by lots of software) — a 93-package dry-run resolved with
  **no systemd init package and no conflict**. This is the supported Artix pattern
  (Arch `libvirt` + Artix `libvirt-openrc`); the lib coexists with elogind/OpenRC.
- **Firewall already present:** `iptables` + `nftables` are installed, so
  libvirt's NAT backend is covered — only `dnsmasq` was missing.
- **Storage → `/data`:** `/` has only ~65 GB free, but **`/data` is a near-empty
  932 GB NVMe (930 GB free)**. The script puts the libvirt storage pool at
  `/data/vms` so Win11 (~25 GB) + Garmin map data (a region can be 10–30 GB) has
  room. (`/home` = 449 GB free is a fallback.)
- **Groups:** the user was in `jim,docker,wheel` — not `libvirt`/`kvm`. The script
  adds both (`libvirt` = manage VMs without root; `kvm` although `/dev/kvm` is 0666).

## §3 — The automation script (`win11-vm-setup.sh`, repo root)

Idempotent, safe to re-run. Run as your user (it calls `sudo` itself), not as root.
Eight steps:

0. **Preflight** — re-assert `svm` + `/dev/kvm`.
1. **Install** the 10-package stack (`pacman -S --needed --noconfirm`).
2. **Groups** — `usermod -aG libvirt,kvm`.
3. **`/etc/libvirt/libvirtd.conf`** — `unix_sock_group="libvirt"`,
   `unix_sock_rw_perms="0770"`, `auth_unix_rw="none"` → group-based local access,
   no polkit prompt (single-user-desktop convention). Backs up `.orig` once.
4. **Services** — `rc-update add` + start `virtlogd` and `libvirtd` (OpenRC).
5. **Default NAT network** — define (if needed) + autostart + start.
6. **Storage pool `vms` → `/data/vms`** — define/build/autostart/start.
7. **virtio-win ISO** — pulled **direct from Fedora**
   (`fedorapeople.org/.../stable-virtio/virtio-win.iso`), *not* the AUR; non-fatal.
8. **Verify** — `virsh version` / `net-list` / `pool-list`, then print next steps.

Three baked-in choices (edit the vars at the top to change):

- `POOL_DIR=/data/vms` — VM disk location (vs `/home` or default `/var`).
- `auth_unix_rw="none"` — passwordless local libvirt (vs keeping polkit).
- `DL_VIRTIO=1` — download the ~700 MB virtio-win ISO (set `0` to skip and use a
  SATA disk in the guest, which needs no extra drivers).

## §4 — Building the VM (virt-manager, after the script runs)

1. **Log out/in once** so the `libvirt` group takes effect (else virt-manager
   can't reach the system libvirtd).
2. Put the Windows 11 ISO in `/data/vms`.
3. `virt-manager` → New VM → Local install media → the Win11 ISO.
   - OS type **"Windows 11"** — modern virt-manager then auto-adds **TPM 2.0** (needs
     `swtpm`) and selects **UEFI/Secure Boot** (needs `edk2-ovmf`).
   - RAM 8192+ MB, CPUs 4–8 (host has 64 threads).
   - Disk: create in the **`vms`** pool, 64 GB+.
   - Tick **Customize configuration** before Finish and confirm: Firmware = UEFI
     (x64, secboot); a TPM 2.0 (CRB) device is present. For disk perf, add
     `virtio-win.iso` as a second CDROM and load the `viostor` driver at the
     Windows disk-selection step — or leave the disk bus = **SATA** for a
     no-driver install.
4. Install Windows, then install Garmin Express inside the guest.

## §5 — Garmin USB passthrough

With the VM running: **Add Hardware → USB Host Device → select the Garmin** (static
passthrough; the device is grabbed when the VM starts). For hot plug/unplug, use
the console's **"Redirect USB device"** menu instead (that path is why `usbredir`
+ `spice-gtk` are installed). NAT networking already gives the guest the internet
Garmin Express needs to fetch map updates.

## Portability note (laptop)

The stack is generic, but `POOL_DIR=/data/vms` is desktop-specific (that 932 GB
drive is on `godlike-artix`). If `nomad-artix` ever needs the same, re-check its
disks and repoint `POOL_DIR` before running.
