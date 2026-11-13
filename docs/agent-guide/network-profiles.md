# Network Profiles

Read this guide for the firewall, VPNs, client network profiles, their credentials,
or captive-portal sign-in. Sources: `i3-net-profile`, `i3-net-profile-rofi`,
`captive-portal`, and dotfiles' `etc/net-profile/`, `etc/init.d/zerotier-one`,
`etc/sudoers.d/90-net-profile`, `etc/NetworkManager/conf.d/`,
`.config/quickshell/Connectivity.qml`, `.config/quickshell/Widgets/Network.qml`.

## Behavior

A profile sets the firewall rules and which VPNs run. Each is one root-owned file,
`/etc/net-profile/profiles/NAME.conf`, of `key = value` lines, parsed as data and
never executed:

- `description` is the menu text.
- `allow` holds `ufw` rule arguments, and may repeat.
- `service` names an OpenRC service, typically a VPN, and may repeat.
- `secret` names a Bitwarden item, never a value; `%h` expands to the hostname. A
  profile with a secret has exactly one service.

Adding a profile is adding a file; it appears in the menu with no code change. The
staged copies live in dotfiles, which is private, so client names stay out of this
public repository. That privacy is about names only: credentials never go in any
repository, private or public.

Every profile keeps UFW enabled and denying incoming traffic, including on VPN
interfaces, which carry another network to the machine wherever it is. Switching
stops and wipes each service named by any other profile, replaces the rules tagged
`net-profile` while leaving rules added by hand, then starts the target's services.
The helper has no off command. `home` allows SSH from `192.168.1.0/24`, the subnet
both machines share, so any network numbered that way gets the exception; choose
`away` when traveling.

Tailscale is the exception to the deny, under every profile: `tailscaled`'s own
`ts-input` chain comes first in `INPUT` (`sudo iptables -S INPUT`) and accepts
everything arriving on `tailscale0` before UFW sees it. Tailnet peers, all of them Jim's
own devices, therefore reach every port listening beyond loopback, which on both
machines is SSH alone. The tailnet's access policy, not UFW, is what limits them.

`i3-net-profile status|list|polybar|set NAME` calls the root-owned
`/etc/net-profile/net-profile` through a narrow sudoers rule, so a bar can run it even
where `sudo` prompts. `i3-net-profile-rofi` is the menu, and choosing the
active profile re-applies it. The Polybar `net-profile` module shows a shield and the
profile, and a click opens the menu. Red means UFW is off or credentials were left in
RAM. Yellow names another problem, or shows `?` when the helper is missing. Dotfiles'
Quickshell `NetProfile` widget shows the same states from `status`, with white on red
for the two red ones. Its `NetProfileState` reads `status` at startup, every five
minutes, and on `qs ipc call netprofile refresh`, which `i3-net-profile set` sends
after a switch and the widget sends when the menu closes.

## Credentials

Credentials live in Bitwarden, and the master password gates them:

1. `i3-net-profile` runs `rbw get --raw ITEM` as the user, which prompts through
   pinentry if the vault is locked. A failed fetch leaves the current profile running.
2. It pipes the output to the helper on stdin, never in arguments or a variable.
3. The helper puts it in a ramfs at `/run/net-profile/SERVICE`. A ramfs cannot swap,
   which matters because neither machine encrypts its swap or disks, and it vanishes
   on reboot.
4. The service's runner in `/etc/net-profile/vpn/` builds the daemon's config from it
   and deletes the input. The daemon must hold the key in memory while it runs.
5. The runner wipes everything when the daemon exits for any reason. If the runner
   itself is killed, the service's `stop_post` and every profile switch wipe too, and
   the wipe kills the daemon by its recorded PID. The bar flags anything left behind.

VPN services stay out of the runlevels and do not respawn, because a restart would have
no credentials. After a crash or reboot the bar reports the VPN down until the profile
is chosen again. These protections depend on `rbw` locking: while the vault is unlocked,
every process running as the user can read it. Each machine sets `lock_timeout` to 900
seconds (15 minutes).

A new VPN needs a profile, an OpenRC service, and a runner that turns the Bitwarden item
into that VPN's config; `zerotier-run` is the template. `rbw get --raw` emits JSON with
`.data.username`, `.data.password`, `.fields`, and `.notes`.

ZeroTier has no user credentials. Its credential is a per-machine private key whose
address the network admin approves, and two machines sharing one identity conflict, so
each machine has its own login item, named by the profile with `%h`: the password is the
contents of `identity.secret`, and the username is the 16-digit network ID. To create
one, keeping the key off disk and off the screen:

```sh
d=$(mktemp -d /dev/shm/zt.XXXXXX)
zerotier-idtool generate $d/identity.secret $d/identity.public >/dev/null
cut -d: -f1 $d/identity.secret    # the node ID for the network admin to approve
rbw add ITEM_NAME NETWORK_ID <$d/identity.secret
i3-net-profile set PROFILE
sudo zerotier-cli -D/run/net-profile/zerotier-one/home info    # must show that node ID
rm -rf $d
```

When stdin is not a terminal, `rbw` reads the password from it and never opens its
editor, so `rbw add` run that way without the redirect, as by an agent, saves an empty
password. `rbw edit ITEM_NAME <FILE` replaces a password the same way. Delete `$d` only
once `info` shows the node ID, because the key exists nowhere else. Starting the profile
before approval is harmless and lists the node as a join request: `listnetworks` shows
`ACCESS_DENIED` until the admin approves, then `OK` and an address. For any VPN the bar's
`ok` means only that its service is running, not that the network admitted the machine.

Docker publishes ports through its own firewall rules, which reportedly bypass UFW; this
was not tested, and the service is not enabled at boot. The real `rbw` path and a real
network were tested end to end: a join request, the admin's approval, then traffic.

## Setting up a machine

From dotfiles' `etc/` directory:

```sh
sudo pacman -S --needed ufw ufw-openrc zerotier-one
sudo install -D -m755 -o root -g root net-profile/net-profile /etc/net-profile/net-profile
sudo install -D -m755 -o root -g root net-profile/vpn/zerotier-run /etc/net-profile/vpn/zerotier-run
sudo install -d -m755 -o root -g root /etc/net-profile/profiles
sudo install -m644 -o root -g root net-profile/profiles/*.conf /etc/net-profile/profiles/
sudo install -m755 -o root -g root init.d/zerotier-one /etc/init.d/
visudo -cf sudoers.d/90-net-profile && sudo install -m440 -o root -g root sudoers.d/90-net-profile /etc/sudoers.d/
for s in i3-net-profile i3-net-profile-rofi; do ln -sfn ~/projects/i3-screen-manager/$s ~/.local/bin/$s; done
rbw config set lock_timeout 900
i3-net-profile set home
sudo rc-update add ufw default && sudo rc-service ufw start
```

Install a changed or new profile file with the `install -m644` line. Over SSH, first arm
a timer that runs `ufw --force disable`, and cancel it once a new connection works. Detach
it with stdin, stdout, and stderr redirected, or `ssh` waits for it to finish.

A libvirt host also needs these, or its guests lose DHCP, DNS, and outbound TCP. Ping keeps
working because UFW passes ICMP echo, so it proves nothing. Libvirt's nftables table does
not help: a packet must pass every table's chains, so UFW's drop wins. Added by hand, the
rules stay in every profile:

```sh
sudo ufw allow in on virbr0 to any port 53 comment 'libvirt guests'
sudo ufw allow in on virbr0 to any port 67 proto udp comment 'libvirt guests'
sudo ufw route allow in on virbr0 comment 'libvirt guests'
```

## Verification

Probe port 22 from the other machine in each profile: open in `home`, blocked in every
other. Testing from the same machine proves nothing, because loopback traffic is always
allowed. To check guest networking without booting a guest, attach a network namespace to
`virbr0` through a veth pair, give it an address, and test DNS to the bridge address and TCP
out. A DHCP probe needs a raw socket, and a new bridge port takes about 8 seconds to settle,
so an earlier miss means nothing. This was checked that way; a real guest has not been
booted behind UFW. A VPN must run only in its own profile. With a VPN profile active, kill the
daemon, kill the runner, and stop the service in turn: each must leave no daemon and no
`/run/net-profile/SERVICE`, or a red bar until a profile is chosen. Search disk, logs,
and process arguments for the key afterward, reading the search term from a file so the
search does not match itself.

After a reboot, `i3-net-profile status` must report the chosen profile as `ok`, or as
`vpn-down` for a VPN profile until it is chosen again. `sudo ufw status` must show its rules,
`rc-status` must show `ufw` and `clamd` started, and port 22 must follow the profile when
probed from the other machine. No VPN daemon and no `/run/net-profile` may remain.

## Captive Portals

Only the laptop runs NetworkManager; the desktop runs netifrc, so this section applies to
`nomad-artix` alone.

Its Wi-Fi backend is wpa_supplicant, NetworkManager's default, set by dotfiles'
`90-wifi-backend.conf`; NetworkManager.conf(5) calls iwd experimental, and Omarchy left it too.
D-Bus starts wpa_supplicant on demand, so it needs no OpenRC service, and iwd is not installed.
Saved networks are keyfiles in `/etc/NetworkManager/system-connections`, and the home one is
bound to `wlan0`. That is the kernel's own name: Artix's udev ships no `.link` file, so
nothing renames interfaces, and at boot the kernel creates `wlan0` for NetworkManager to
connect.

NetworkManager detects a portal by fetching its check URL: a reply other than the expected
one means Portal. Dotfiles' `etc/NetworkManager/conf.d/90-connectivity.conf` points the check
at Omarchy's `http://ping.omacom.io/nm-check.txt`, which answers 204 with
`X-NetworkManager-Status: online`, in place of Arch's `ping.archlinux.org` from
`/usr/lib/NetworkManager/conf.d/20-connectivity.conf`. The URL must stay plain HTTP on a host
that is not HSTS-preloaded, or a browser upgrades it to HTTPS and the portal cannot intercept
it; archlinux.org is preloaded. On a working network the endpoint redirects a browser to
omarchy.org. `90-wifi-powersave.conf` turns Wi-Fi power save off whenever a Wi-Fi connection
activates, even after something has turned it on.

Dotfiles' `.config/quickshell/Connectivity.qml` reads NetworkManager's state through
Quickshell's `Networking`. It is a singleton, so every bar shares one re-check and one
notification. It looks for `/run/NetworkManager` once at bar start and touches `Networking`
only when that exists, because the first use without NetworkManager logs an ERROR ("Could not
find an available backend"). Without it, as on the desktop, the `Network` widget shows only the
link. On the laptop `Widgets/Network.qml` turns white on red with
`sign in` for Portal, where a click runs `captive-portal`, and yellow for Limited. While either
holds, the singleton asks NetworkManager to re-check every 10 seconds instead of its own 300.
Entering Portal sends one notification whose default action, a click in mako, runs
`captive-portal`; it expires after mako's 5 seconds like any other. Nothing opens without a
click, and only the fixed check URL is opened, never a `Location` the portal supplies.

`captive-portal [URL]` opens the check URL, which the portal intercepts to show its sign-in
page; the URL argument, `http` or `https` only, is for testing. A flock at
`$XDG_RUNTIME_DIR/captive-portal.lock` keeps one run waiting, and a second run focuses that
run's window by the PID in `captive-portal.pid`, then exits. The script starts Brave Origin as
its own process with the profile `~/.local/state/captive-portal/brave`, so Jim's extensions,
Secure DNS, and cookies never meet a portal page, and the portal's cookies persist for the next
sign-in. Like Jim's other Brave it has WebMCP and a CDP port, `127.0.0.1:9223` because the main
Brave holds 9222, open only while the window is. Behind a real portal no agent can be reached,
so each run also leaves `last-run.log` beside the profile, recording the connectivity results as
they change, each page the window visits (read from that CDP port), and how the run ended, and
`brave.log` with the browser's output; the next run replaces both. A new Origin profile ignores
`--app` and shows Origin's free-tier splash, so before each launch the script sets
`brave.origin.free_tier_accepted` to `true` in the profile's `Local State`, the choice Jim's
main profile records. It sets only that key and copies nothing from the main profile: the portal
profile never signs in or uses one of the Origin purchase's device activations.

Brave names an `--app` window after its URL; for the check URL the class is
`brave-ping.omacom.io__nm-check.txt-Default`, which dotfiles' `captive-portal` window rule floats
centered at 900x760. The script waits for `nmcli networking connectivity check`, read in the C
locale, to print `full`: every 2 seconds for 5 minutes, then every 15. polkit allows that
re-check only from an active local session; elsewhere, as over SSH, the script reads
NetworkManager's last result instead. Once online it closes the window
through Hyprland's `pid:` selector, falls back to SIGTERM and then SIGKILL, and notifies
`Online`. Closing the window first ends the wait silently; a browser that exits before Hyprland
lists its window raises a critical notification. Outside Hyprland the close is a SIGTERM.
Omarchy's pause of a Tailscale exit node is not ported, because tailscaled doesn't run on the
laptop. The script and both config files are adapted from Omarchy 4.5 and carry its MIT
license in full.

To set up the laptop, from dotfiles' `etc/` directory:

```sh
sudo install -m644 -o root -g root NetworkManager/conf.d/90-*.conf /etc/NetworkManager/conf.d/
sudo sed -i '/^wifi\.backend=/d' /etc/NetworkManager/NetworkManager.conf   # conf.d sets it
sudo rc-service NetworkManager restart
busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager \
    org.freedesktop.NetworkManager ConnectivityCheckUri    # the omacom URL
ln -sfn ~/projects/i3-screen-manager/captive-portal ~/.local/bin/captive-portal
```

On a machine still running iwd, first stop it and take it out of the runlevel
(`rc-service iwd stop`, `rc-update del iwd default`). iwd replaces the kernel's interface with
its own and deletes it when it stops, so unless the machine reboots next, recreate it with
`iw phy phy0 interface add wlan0 type managed` before restarting NetworkManager. Then remove it
with `pacman -R iwd iwd-openrc`, which leaves `/var/lib/iwd` and its copies of network secrets
to delete by hand. Change the backend with a wired link up, since Wi-Fi drops until
NetworkManager reconnects.

`NetworkManager --print-config` must show `wifi.backend=wpa_supplicant`, and `nmcli device`
must show `wlan0` connected, with wpa_supplicant's `p2p-dev-wlan0` as its p2p device. After a
reboot, `iw dev` must list the kernel's `wlan0` and NetworkManager must have connected Wi-Fi
with no cable. A change to `90-connectivity.conf` alone needs only
`sudo nmcli general reload conf`.

To rehearse a portal, set `uri=http://neverssl.com/` and `response=NetworkManager is online`
in the installed `90-connectivity.conf` and reload: a plain-HTTP page whose body doesn't match
reads as Portal. `nmcli networking connectivity check` must print `portal`, the bar must turn
red and send one notification, and its window must float at 900x760. Reinstall the staged file
and reload: the check must print `full` again, and a waiting `captive-portal` must close its
window and notify. A real portal, including whether Brave's automatic HTTPS upgrade still falls
back to the plain-HTTP URL there, can only be checked in the field.

[Shared instructions and task index](../../CLAUDE.md#task-guides).
