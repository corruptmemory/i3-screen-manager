# System Maintenance

Read this guide for hardware, OpenRC services, the Tailscale helper, CMOS
monitoring, the local dictionary server, disk reclaim, or VM setup. Sources:
`start-hyprland`, `i3-tailscale-rofi`, `i3-cmos-battery`, `volumecontrol.sh`,
`ora4-hw-pin`, `win11-vm-setup.sh`, and dotfiles' `etc/init.d/dictd`.
Check active machine state before applying configuration outside this repository.

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

The desktop's Kanto ORA4 (USB) reports a misleading hardware-volume dB scale,
so under the default ACP path PulseAudio parks a false "base" near 54% and the
range below it collapses to silence. A machine-local WirePlumber drop-in in
`~/.config/wireplumber/wireplumber.conf.d/` takes the card off ACP
(`api.alsa.use-acp=false`) and does volume in software (`api.alsa.soft-mixer=true`),
restoring a smooth full range; `api.alsa.ignore-dB` does not linearize it under
ACP. Software volume orphans the hardware PCM, which then powers up at 0 (silent)
after a reboot, so `ora4-hw-pin` pins that control open by name each login. It
runs from the desktop session startup under both compositors: Hyprland's
`autostart.lua` audio block and i3's `.xinitrc-i3` after the PipeWire trio. The
WirePlumber drop-in is PipeWire config, so it applies under either session
unchanged. The drop-in is desktop-local, not carried by dotfiles; the pin script
and its startup lines are.

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

## Local Dictionary Server

`dictd` serves offline dictionaries to Emacs's `dictionary` package (`M-#` in
emacs-again). It is an OpenRC system service from dotfiles'
`etc/init.d/dictd` and `etc/conf.d/dictd`, run under `supervise-daemon` as
`nobody`, bound to `127.0.0.1:2628`, logging to `/var/log/dictd.log`. Keep the
loopback bind: the packaged `/etc/dict/dictd.conf` says `allow *`, and dictd
otherwise listens on every interface. No syslog daemon runs on these machines,
so `--syslog` would discard dictd's messages. Copy both files into `/etc` with
`install`, not symlinks, so the root-run script is not writable by the user.

The databases are AUR packages; each one's install scriptlet appends a
`database` block to `/etc/dict/dictd.conf`, but only when `dictd` is already
installed, and then calls `systemctl`, which prints "command not found" on
Artix. They total about 365 MiB, most of it Wiktionary.

### Setting up a machine

Run the steps in order, in bash: the audit loop uses bash parameter expansion,
which fish lacks. `sudo` and `yay` prompt for a password, so a person runs
those.

1. **Prerequisites.** Pull `~/projects/dotfiles`, `~/projects/i3-screen-manager`,
   and emacs-again (`~/.config/emacs`). `locale -a | grep -x en_US.utf8` must
   print `en_US.utf8`: dictd refuses UTF-8 databases such as Wiktionary under
   any other locale. If it prints nothing, uncomment `en_US.UTF-8 UTF-8` in
   `/etc/locale.gen` and run `sudo locale-gen`.

2. **Audit gate** (the [packages.md](packages.md) AUR contract). Run
   `aur-malware-check --near`, then confirm each recipe is still the commit
   that was reviewed:

   ```bash
   for pw in wordnet=f3c5f33856a2 dict-gcide=9b4795542288 \
             dict-foldoc=bde87cbc6ecb dict-jargon=87e46c39562b \
             dict-devils=4f9db17a6e67 dict-freedict-fra-eng-bin=0411896bcc00 \
             dict-freedict-eng-fra-bin=03bec6d0e0e1 \
             dict-moby-thesaurus=ddc946b2e46b dict-wikt-en-all=9dca22cb68f8; do
     p=${pw%=*} want=${pw#*=}
     got=$(git ls-remote "https://aur.archlinux.org/$p.git" refs/heads/master | cut -c1-12)
     [ "$got" = "$want" ] && echo "same     $p" || echo "CHANGED  $p ($want -> $got)"
   done
   ```

   `same` means the review below still applies. For `CHANGED`, clone the
   recipe and read `git diff <want>..HEAD` (PKGBUILD, `.install`, helper
   scripts, sources, checksums) before installing, then update the commit here.
   The review found: every source checksum-pinned except `dict-foldoc`'s
   rolling data file (`SKIP`); `dict-foldoc` also runs `curl` against
   foldoc.org whenever its PKGBUILD is sourced; `dict-moby-thesaurus` fetches
   from a third-party GitHub branch with pinned checksums; `wordnet` and
   `dict-jargon` download over plain `http` with pinned checksums; the
   `dict-gcide` and `dict-foldoc` build-time `sed` scripts contain no `e`, `w`,
   or `r` commands; `wordnet-dictd` inherits the WordNet suite's runtime
   dependencies, adding `tcl` and `tk`. The `-bin` FreeDict packages avoid the
   AUR-only `freedict-tools`.

3. **Server package first**, so the database scriptlets register:
   `sudo pacman -S dictd`.

4. **`dict-gcide` signing key**, imported from GNU's maintainer keyring rather
   than a keyserver (it is Sergey Poznyakoff's):

   ```bash
   cd "$(mktemp -d)"
   curl -fsSLO https://ftp.gnu.org/gnu/gnu-keyring.gpg
   gpg --no-default-keyring --keyring "$PWD/gnu-keyring.gpg" \
       --export 4BE4E62655488EB92ABB468F79FFD94BFCE230B1 | gpg --import
   ```

5. **Databases.** Each install prints `Adding configuration for … to
   /etc/dict/dictd.conf`; the `systemctl: command not found` lines are
   expected. Afterwards run `aur-malware-check --near --deep`.

   ```bash
   yay -S wordnet-dictd dict-gcide dict-foldoc dict-jargon dict-devils \
          dict-freedict-fra-eng-bin dict-freedict-eng-fra-bin \
          dict-moby-thesaurus dict-wikt-en-all
   ```

6. **Service.**

   ```bash
   sudo install -m 0755 ~/projects/dotfiles/etc/init.d/dictd /etc/init.d/dictd
   sudo install -m 0644 ~/projects/dotfiles/etc/conf.d/dictd /etc/conf.d/dictd
   sudo rc-update add dictd default
   sudo rc-service dictd start
   ```

7. **Verify.** `rc-service dictd status` reports `started`;
   `ps -o user= -C dictd` prints `nobody`; `ss -ltn 'sport = :2628'` shows only
   `127.0.0.1:2628`; `grep -c '^database' /etc/dict/dictd.conf` prints `9`;
   `dict -h 127.0.0.1 -D` lists `fra-eng foldoc wn jargon eng-fra wikt-en-all
   devils moby-thesaurus gcide`. `/var/log/dictd.log` holds startup and lookup
   lines.

8. **Emacs.** emacs-again needs no extra packages (`dictionary.el` is
   built in). Restart Emacs; `M-#` on a word opens `*Dictionary*` as a Popper
   popup at half the frame.

### Upkeep

The init files are copies, so a dotfiles pull does not redeploy them: after
changing either, re-run the two `install` lines and `sudo rc-service dictd
restart`. After installing another database package, restart the service so
dictd reads the new block. Removing a package deletes its block unless the
block was edited.

## Storage and Disk Reclaim

The desktop root filesystem is a separate, modestly sized btrfs; `/home` and
`/data` are separate, larger disks, so user builds and downloads under `/home`
do not pressure the root. When the root nears capacity, inspect live state
before deleting anything: `df -hT`, `du -xh --max-depth=1 /` (the `-x` keeps
`du` on the root filesystem rather than descending into other mounts), and on
btrfs `btrfs filesystem usage /` with `btrfs subvolume list /` to distinguish a
genuine data fill from unreclaimed allocation or snapshots. Resolve the actual
mount layout with `findmnt`; do not assume `/var` is its own partition.

The first and safest reclaim is the pacman package cache under
`/var/cache/pacman/pkg`: `paccache -rk1` keeps one version of each package and
`paccache -ruk0` drops the cache for uninstalled packages. These remove only
re-downloadable files and never touch installed packages; preview with the `-d`
dry-run flag before removing.

Two larger consumers commonly sit on the root. The libvirt `default` storage
pool is `/var/lib/libvirt/images`; a guest qcow2 there is sparse (its apparent
size is the maximum the guest can grow into, not the space used) and consumes
the small root even while a pool on `/data` has room, so prefer the `/data`
pool for guests (see VM Setup). Docker uses the containerd image store here, so
its images live under the `moby` namespace in `/var/lib/containerd`, not
`/var/lib/docker`, and the `docker`/`containerd` services are started on demand
rather than from a runlevel. Prune only dangling images (`docker image prune`):
tagged images are not garbage, and `prune -a` would drop images merely because
nothing is running. To read image identities offline, start the daemon briefly
(`rc-service docker start` pulls up containerd), inspect with `docker system df`
and `docker images`, then stop both (`rc-service docker stop` does not stop
containerd; stop it explicitly to restore the prior state).

## System Verification

Use read-only configuration, package, service, device, and connection queries
first. Verify both the intended state and user-visible behavior after a system
change. Check absent-sensor output, Tailscale failure/auth paths, and the
actual VM storage and service state when their respective tools change.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
