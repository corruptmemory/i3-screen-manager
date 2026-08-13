#!/usr/bin/env bash
# win11-vm-setup.sh
# One-shot, idempotent setup of QEMU/KVM + libvirt on Artix (OpenRC/elogind)
# for a Windows 11 guest with USB passthrough (Garmin Express map updates).
#
# Run as your normal user WITH sudo available (NOT as root directly):
#     bash win11-vm-setup.sh
# Safe to re-run — every step checks state first.

set -euo pipefail

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '   \033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

USER_NAME="${SUDO_USER:-$(id -un)}"
[ "$USER_NAME" != root ] || die "Run as your user (script will call sudo itself)."

POOL_NAME=vms
POOL_DIR=/data/vms          # 932G NVMe, 930G free — roomy home for VM disks
DL_VIRTIO=1                 # set 0 to skip the virtio-win driver ISO download

# ---------------------------------------------------------------------------
log "0. Preflight — virtualization must be live"
grep -q svm /proc/cpuinfo || die "AMD-V (svm) not exposed — enable 'SVM Mode' in UEFI."
[ -e /dev/kvm ] || die "/dev/kvm missing — kvm_amd not loaded?"
ok "AMD-V present and /dev/kvm exists"

# ---------------------------------------------------------------------------
log "1. Packages (official repos only; --needed skips already-installed)"
sudo pacman -S --needed --noconfirm \
    qemu-desktop libvirt libvirt-openrc virt-manager virt-viewer \
    edk2-ovmf swtpm dnsmasq usbredir spice-gtk
ok "packages present"

# ---------------------------------------------------------------------------
log "2. Group membership (libvirt = manage VMs w/o root; kvm = /dev/kvm)"
if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx libvirt; then
    ok "$USER_NAME already in libvirt group"
else
    sudo usermod -aG libvirt,kvm "$USER_NAME"
    warn "added $USER_NAME to libvirt,kvm — LOG OUT/IN (or reboot) for it to take effect"
fi

# ---------------------------------------------------------------------------
log "3. libvirtd.conf — group-based access, no polkit prompt (easy local use)"
CONF=/etc/libvirt/libvirtd.conf
sudo test -f "$CONF.orig" || sudo cp -a "$CONF" "$CONF.orig"   # one-time backup
set_kv() {  # key  quoted-value
    if sudo grep -qE "^#?[[:space:]]*$1[[:space:]]*=" "$CONF"; then
        sudo sed -i -E "s|^#?[[:space:]]*$1[[:space:]]*=.*|$1 = $2|" "$CONF"
    else
        printf '%s = %s\n' "$1" "$2" | sudo tee -a "$CONF" >/dev/null
    fi
}
set_kv unix_sock_group   '"libvirt"'
set_kv unix_sock_rw_perms '"0770"'
set_kv auth_unix_rw      '"none"'
ok "libvirtd.conf set (backup at $CONF.orig)"

# ---------------------------------------------------------------------------
log "4. OpenRC services — enable at boot + start now"
for svc in virtlogd libvirtd; do
    sudo rc-update add "$svc" default 2>/dev/null || true
    sudo rc-service "$svc" restart
done
sudo virsh version >/dev/null 2>&1 || die "libvirtd not responding after start"
ok "virtlogd + libvirtd running and enabled"

# ---------------------------------------------------------------------------
log "5. Default NAT network (gives the VM internet for Garmin downloads)"
if ! sudo virsh net-info default >/dev/null 2>&1; then
    NETXML=/usr/share/libvirt/networks/default.xml
    [ -f "$NETXML" ] && sudo virsh net-define "$NETXML" || warn "default.xml not found; define a NAT net in virt-manager"
fi
sudo virsh net-autostart default 2>/dev/null || true
sudo virsh net-start     default 2>/dev/null || ok "default net already active"
ok "NAT network ready"

# ---------------------------------------------------------------------------
log "6. Storage pool '$POOL_NAME' on $POOL_DIR (avoids the tight 65G /)"
sudo mkdir -p "$POOL_DIR"
# btrfs: disable copy-on-write on the image dir so qcow2 files don't fragment.
# New files created under a +C dir inherit nodatacow; existing files don't.
if [ "$(stat -f -c %T "$POOL_DIR" 2>/dev/null)" = btrfs ]; then
    sudo chattr +C "$POOL_DIR" 2>/dev/null && ok "nodatacow (+C) set on $POOL_DIR (btrfs)"
fi
if ! sudo virsh pool-info "$POOL_NAME" >/dev/null 2>&1; then
    sudo virsh pool-define-as "$POOL_NAME" dir --target "$POOL_DIR"
    sudo virsh pool-build "$POOL_NAME"
fi
sudo virsh pool-autostart "$POOL_NAME" 2>/dev/null || true
sudo virsh pool-start     "$POOL_NAME" 2>/dev/null || ok "pool already active"
ok "pool '$POOL_NAME' -> $POOL_DIR"

# ---------------------------------------------------------------------------
log "7. virtio-win driver ISO (direct from Fedora — NOT the AUR)"
if [ "$DL_VIRTIO" = 1 ]; then
    ISO="$POOL_DIR/virtio-win.iso"
    if [ -f "$ISO" ]; then
        ok "virtio-win.iso already present"
    elif sudo curl -fL --retry 3 -o "$ISO" \
        https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
    then
        ok "downloaded $ISO"
    else
        warn "virtio-win download failed — fine, use a SATA disk in virt-manager instead"
    fi
fi

# ---------------------------------------------------------------------------
log "8. Verify"
sudo virsh version
echo; sudo virsh net-list  --all
echo; sudo virsh pool-list --all
echo
cat <<EOF
------------------------------------------------------------------------------
DONE. Next steps (do these yourself):

  1. LOG OUT and back in  (activates your new 'libvirt' group membership).
  2. Drop your Windows 11 ISO into:  $POOL_DIR
  3. Launch:  virt-manager
  4. New VM -> Local install media -> pick the Win11 ISO.
       - OS: "Windows 11" (auto-enables TPM 2.0 + UEFI/Secure Boot).
       - Memory 8192+ MB, CPUs 4-8 (you have 64 threads).
       - Storage: create a disk in the '$POOL_NAME' pool, 64 GB+.
       - Before "Finish", tick "Customize configuration":
           * Firmware = UEFI (x64, secboot) if not already.
           * Add Hardware -> TPM -> CRB / 2.0 if the wizard didn't.
           * (perf) add virtio-win.iso as a 2nd CDROM; load its viostor
             driver at the Windows disk-selection step. Or just leave the
             disk bus = SATA for a no-driver install.
  5. Install Windows, then Garmin Express inside the guest.
  6. Garmin device passthrough: VM running -> Add Hardware -> USB Host
     Device -> select the Garmin. (Or use the console's "Redirect USB
     device" menu for hot plug/unplug.)
------------------------------------------------------------------------------
EOF
