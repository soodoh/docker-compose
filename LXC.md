# Setting up LXC Container (in Proxmox) for Docker host

1. Create container from Ubuntu server CT template. Make sure network is set up correctly (I used DHCP, rather than a static IP).

1. (???) Make sure $LANG (/etc/locale) is set up correctly.

1. Configure ssh keys for Github access.

```
ssh-keygen -t ed25519 -C "your_email@example.com"
```

1. Add bind mount point for ZFS pool dataset.

```
pct set <CTID> --mp0 /mnt/media,mp=/mnt/media
pct apply <CTID>
```

1. Manually add to `/etc/pve/lxc/<CTID>.conf`:

```
lxc.mount.entry: /dev/zigbee dev/zigbee none bind,optional,create=file
lxc.mount.entry: /dev/zwave dev/zwave none bind,optional,create=file
```
This might be necessary too? `lxc.cgroup2.devices.allow: c 188:* rwm`

1. Set `udev` rules for Zigbee/Zwave USB controllers

File location: `/etc/udev/rules.d/<YOUR_FILE>.rules`
File contents:
```
SUBSYSTEM=="tty", ATTRS{idVendor}=="VENDOR_ID", ATTRS{idProduct}=="PRODUCT_ID", ATTRS{serial}=="SERIAL", MODE="0766", SYMLINK+="zigbee"
SUBSYSTEM=="tty", ATTRS{idVendor}=="VENDOR_ID", ATTRS{idProduct}=="PRODUCT_ID", ATTRS{serial}=="SERIAL", MODE="0766", SYMLINK+="zwave"
```

1. Reload `udev rules`

Run `udevadm control --reload-rules && udevadm trigger`, then verify that `/dev/zigbee` has correct permissions and is symlinked to `/dev/ttyUSB0` (or `ttyUSB*`).

## TODO

[] Set up Proxmox + Docker hosts to automatically run ssh-agent for git access
[] Configure SSH access for Proxmox + Docker hosts so that authentication is host-based (or otherwise happens automatically, but securely)
