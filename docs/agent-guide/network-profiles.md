# Network Profiles

Read this guide for the firewall, VPNs, client network profiles, or their
credentials. Sources: `i3-net-profile`, `i3-net-profile-rofi`, and dotfiles'
`etc/net-profile/`, `etc/init.d/zerotier-one`, `etc/sudoers.d/90-net-profile`.

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

`i3-net-profile status|list|polybar|set NAME` calls the root-owned
`/etc/net-profile/net-profile` through a narrow sudoers rule, so a bar can run it even
where `sudo` prompts. `i3-net-profile-rofi` is the menu, and choosing the
active profile re-applies it. The Polybar `net-profile` module shows a shield and the
profile, and a click opens the menu. Red means UFW is off or credentials were left in
RAM. Yellow names another problem, or shows `?` when the helper is missing. The
Quickshell bar has no widget, so under Hyprland run the menu directly.

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
one, keeping the key off disk:

```sh
d=$(mktemp -d /dev/shm/zt.XXXXXX)
zerotier-idtool generate $d/identity.secret $d/identity.public >/dev/null
cut -d: -f1 $d/identity.secret    # the address for the network admin to approve
cat $d/identity.secret            # paste this as the first line in rbw's editor
rbw add ITEM_NAME NETWORK_ID
rm -rf $d
```

Docker publishes ports through its own firewall rules, which reportedly bypass UFW; this
was not tested, and the service is not enabled at boot. A real ZeroTier network and the
real `rbw` path were not tested when this was written: the checks used a stand-in `rbw`
and a network ID that does not exist. To inspect a running daemon, use
`sudo zerotier-cli -D/run/net-profile/zerotier-one/home info`.

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

[Shared instructions and task index](../../CLAUDE.md#task-guides).
