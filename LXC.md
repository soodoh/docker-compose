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
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,optional,create=file
```

This might be necessary too? `lxc.cgroup2.devices.allow: c 188:* rwm`
I don't think I needed it.

1. Set `udev` rules for Zigbee/Zwave USB controllers

File location: `/etc/udev/rules.d/<YOUR_FILE>.rules`
File contents:

```
SUBSYSTEM=="tty", ATTRS{idVendor}=="VENDOR_ID", ATTRS{idProduct}=="PRODUCT_ID", ATTRS{serial}=="SERIAL", MODE="0766", SYMLINK+="zigbee"
SUBSYSTEM=="tty", ATTRS{idVendor}=="VENDOR_ID", ATTRS{idProduct}=="PRODUCT_ID", ATTRS{serial}=="SERIAL", MODE="0766", SYMLINK+="zwave"
```

1. Reload `udev rules`

Run `udevadm control --reload-rules && udevadm trigger`, then verify that `/dev/zigbee` has correct permissions and is symlinked to `/dev/ttyUSB0` (or `ttyUSB*`).

1. Install Google Coral TPU drivers

[Official instructions](https://coral.ai/docs/m2/get-started/#2a-on-linux)
[Extra steps I needed](https://forum.proxmox.com/threads/update-error-with-coral-tpu-drivers.136888/#post-608975)

Extra steps:

```
apt install git devscripts dh-dkms
cd ~
git clone https://github.com/google/gasket-driver.git
cd gasket-driver/
debuild -us -uc -tc -b
cd ..
dpkg -i gasket-dkms_1.0-18_all.deb
apt update && apt upgrade
```

Modified official steps:

```
echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | sudo tee /etc/apt/sources.list.d/coral-edgetpu.list
apt-get update
apt-get install libedgetpu1-std

sh -c "echo 'SUBSYSTEM==\"apex\", MODE=\"0660\", GROUP=\"apex\"' >> /etc/udev/rules.d/65-apex.rules"
groupadd apex
adduser $USER apex
```

Reboot & verify:

```
lspci -nn | grep 089a
ls /dev/apex_0
```
