# Home lab

## Coral Edge TPU driver on Linux 7.1+

Frigate uses a PCIe Coral Edge TPU passed through from Proxmox to this Arch Linux VM. The Proxmox host only needs to bind the device to `vfio-pci`; the `gasket` and `apex` drivers are installed in this VM.

Linux 7.1 removed the exported `zap_vma_ptes()` API used by Google's archived Gasket driver. When the VM first booted Linux 7.1, DKMS failed with:

```text
gasket_core.c:923:9: error: implicit declaration of function ‘zap_vma_ptes’
```

The fix is to patch the driver to use the exported `zap_special_vma_range()` replacement on Linux 7.1 and newer.

### Build the patched Arch package

Install the build dependencies for the running kernel:

```sh
sudo pacman -S --needed base-devel git dkms linux-headers
```

Clone the AUR package as a regular user:

```sh
git clone https://aur.archlinux.org/gasket-dkms-git.git
cd gasket-dkms-git
```

Download the Linux 7.1 compatibility patch:

```sh
curl -fsSL \
  https://gist.githubusercontent.com/flocke/0757c03608e386809c86e2d564b90916/raw/linux-7.1-compat.patch \
  -o linux-7.1-compat.patch
```

Update `PKGBUILD`:

1. Increment `pkgrel` so the patched package supersedes the unpatched package:

   ```sh
   pkgrel=3
   ```

2. Add the compatibility patch to the `source` and `sha256sums` arrays:

   ```sh
   source+=("linux-7.1-compat.patch")
   sha256sums+=("SKIP")
   ```

3. Replace `prepare()` with the following. Using `$srcdir` avoids path-resolution problems seen with some `makepkg` versions:

   ```sh
   prepare() {
     cd gasket-driver
     patch -Np1 -i "$srcdir/4b2a1464f3b619daaf0f6c664c954a42c4b7ce00.patch" # Linux 6.12+
     patch -Np1 -i "$srcdir/6fbf8f8f8bcbc0ac9c9bef7a56f495a2c9872652.patch" # Linux 6.13+
     patch -Np1 -i "$srcdir/linux-7.1-compat.patch" # Linux 7.1+
   }
   ```

Build the package as a regular user, then install it as root:

```sh
makepkg --cleanbuild --force --noconfirm
package=$(find . -maxdepth 1 -name 'gasket-dkms-git-*.pkg.tar.zst' -print -quit)
sudo pacman -U "$package"
```

### Load and verify the driver

```sh
sudo modprobe gasket
sudo modprobe apex

dkms status
lsmod | grep -E '^(gasket|apex)'
ls -l /dev/apex_0
lspci -nnk -d 1ac1:089a
```

Expected results:

- DKMS reports `gasket` as `installed` for the running kernel.
- `/dev/apex_0` exists.
- The Coral PCI device reports `Kernel driver in use: apex`.

Recreate Frigate so the restored device is attached to the container:

```sh
docker compose up -d --force-recreate frigate
docker compose logs -f frigate
```

Frigate should log `TPU found`, become healthy, and remain at zero restarts.

The patched DKMS source remains installed under `/usr/src`, so DKMS will rebuild it during future kernel upgrades. Reapply this local package patch if `gasket-dkms-git` is reinstalled before the AUR package includes Linux 7.1 support.

References:

- [AUR `gasket-dkms-git`](https://aur.archlinux.org/packages/gasket-dkms-git)
- [Linux 7.1 compatibility patch](https://gist.github.com/flocke/0757c03608e386809c86e2d564b90916)
- [Linux 7.1 Gasket build issue](https://github.com/NixOS/nixpkgs/issues/535359)

## Wolf game streaming

Wolf runs Steam and other graphical apps in on-demand containers and streams them to Moonlight clients. The Radeon RX 7900 XTX is exposed as `/dev/dri/renderD128`; Wolf, Jellyfin, and Frigate share that render node.

The dedicated game disk is mounted through `/etc/fstab`:

```fstab
UUID=31602ce7-0054-498a-9f24-f51ca491e7b3 /mnt/games ext4 defaults,noatime 0 2
```

Wolf keeps its generated configuration, client pairings, profiles, and Steam home directories under `/mnt/games/wolf`. Set `GAMES_PATH` to override the default `/mnt/games` base path.

The ES-DE app mounts `${GAMES_PATH}/roms` read-only at `/ROMs`, `${GAMES_PATH}/bioses` read-only at `/bioses`, and `${GAMES_PATH}/es-de-media` read-write at `/media`. Emulator applications come from the upstream Games on Whales ES-DE image, while RetroArch cores downloaded through its Online Updater persist in `${GAMES_PATH}/wolf/profile-data/paul/WolfES-DE/.config/retroarch/cores`. The complete `${GAMES_PATH}/wolf/profile-data/paul/WolfES-DE` profile is included in encrypted backups at the matching `/backup/wolf/profile-data/paul/WolfES-DE` path, excluding caches, logs, downloadable RetroArch assets, and thumbnails. Steam game data, ROMs, BIOS files, and regenerable scraped media are intentionally excluded.

Steam and ES-DE run under Sway. Their Wolf app mounts replace Waybar with the `${GAMES_PATH}/wolf/cfg/waybar-disabled` no-op and load `sway-borderless-frontends.conf`, which removes frontend borders and main-workspace gaps while leaving game launchers and dialogs under normal Sway window management.

Install the tracked Wolf host configuration:

```sh
sudo install -m 0644 services/data/wolf/wolf-input.conf /etc/modules-load.d/wolf-input.conf
sudo install -m 0644 services/data/wolf/85-wolf-virtual-inputs.rules /etc/udev/rules.d/85-wolf-virtual-inputs.rules
sudo install -D -m 0755 services/data/wolf/waybar-disabled "${GAMES_PATH:-/mnt/games}/wolf/cfg/waybar-disabled"
sudo install -D -m 0644 services/data/wolf/sway-borderless-frontends.conf "${GAMES_PATH:-/mnt/games}/wolf/cfg/sway-borderless-frontends.conf"
sudo install -D -m 0644 services/data/wolf/es-de/es_systems.xml "${GAMES_PATH:-/mnt/games}/wolf/cfg/es-de/es_systems.xml"
sudo install -D -m 0644 services/data/wolf/es-de/wolf-xbox-one.cfg "${GAMES_PATH:-/mnt/games}/wolf/cfg/es-de/wolf-xbox-one.cfg"
sudo install -D -m 0755 services/data/wolf/es-de/dolphin-config.sh "${GAMES_PATH:-/mnt/games}/roms/dolphin-config/Configure Dolphin.sh"
sudo modprobe uinput uhid
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=misc --subsystem-match=hidraw --subsystem-match=input
```

Pull the upstream ES-DE image, then start and verify Wolf:

```sh
docker pull ghcr.io/games-on-whales/es-de:edge
docker compose up -d wolf
docker compose logs -f wolf
```

ES-DE uses its bundled GBA, Nintendo DS, and Nintendo 64 definitions. The tracked GameCube override launches the image's standalone Dolphin AppImage, the Dolphin Configuration system opens its full settings interface, and the tracked RetroArch autoconfiguration supports Wolf's virtual Xbox One controller. Install and update mGBA, melonDS DS, and Mupen64Plus-Next through **RetroArch → Online Updater**; the persistent core directory takes precedence over system cores.

The startup log should report VA-API H.264, H.265, and AV1 encoders and an AMD zero-copy pipeline on `/dev/dri/renderD128`. In Moonlight, add the server's internal IP, select Wolf, then open the pairing URL printed in `docker compose logs wolf` and enter Moonlight's PIN.

Wolf has read-write access to the Docker socket so it can create application containers. Keep its ports restricted to the trusted LAN.

## Cronjobs

```sh
sudo pacman -Syu cronie
sudo systemctl enable --now cronie.service
sudo crontab -e
```

Then, add this to the root's crontab (it will clean up old docker images, running every Sunday at 4AM machine local time).

```cron
0 4 * * 0 { date; /usr/bin/docker system df; /usr/bin/docker system prune --all --force --filter "until=168h"; /usr/bin/docker system df; } >> /var/log/docker-prune.log 2>&1
```
