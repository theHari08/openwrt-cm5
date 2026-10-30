# OpenWrt router image for the Waveshare CM5-DUAL-ETH-BOX-B

Custom [OpenWrt](https://openwrt.org/) image for the [Waveshare CM5-DUAL-ETH-BOX-B](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B), a Raspberry Pi CM5 with eMMC in a dual-Ethernet box. It targets [bcm27xx/bcm2712](https://openwrt.org/docs/techref/targets/bcm27xx) as a squashfs image and is built with the official [OpenWrt Image Builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder). [`build.sh`](build.sh) downloads, verifies and extracts the Image Builder, then builds the image.

## Defaults (first boot and after every factory reset)

| Setting | Default |
| --- | --- |
| lan | eth1 (2.5GbE, RTL8156 on internal USB), br-lan 192.168.50.1/24, DHCP .100-.249 |
| wan | eth0 (1GbE, RP1), DHCP client, [mwan3](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3) primary |
| wanusb | usb0 (Android USB tethering), DHCP client, mwan3 backup |
| IPv6 | Off: wan6 exists with `auto=0`, no RA/DHCPv6 on lan |
| Firewall | Normal router: wan, wan6 and wanusb NATed, inbound rejected; manage from lan only |
| Login | No root password and no SSH key until set in LuCI |
| Boot config | Wi-Fi and Bluetooth disabled ([`dtoverlay`](https://www.raspberrypi.com/documentation/computers/config_txt.html)), M.2 slot at PCIe Gen3 as in the [Waveshare NVMe guide](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B-Tutorials-NVMe) |
| Storage | [`75_grow_rootfs_part`](files/lib/preinit/75_grow_rootfs_part) grows partition 2 to the end of the eMMC before the overlay is created, so the f2fs overlay spans the whole disk (about 29 GB) |

The router defaults are set by [`90-router-defaults`](files/etc/uci-defaults/90-router-defaults), a [uci-defaults](https://openwrt.org/docs/guide-developer/uci-defaults) script. The failover policy is in [`files/etc/config/mwan3`](files/etc/config/mwan3).

## Layout

| Path | Contents | In git |
| --- | --- | --- |
| [`build.sh`](build.sh) | Image Builder download/verify/extract, package list, build | yes |
| [`files/`](files) | Files copied into the image (grow hook, router defaults, mwan3 config) | yes |
| `imagebuilder-dl/<version>/` | Downloaded Image Builder archive and the release's `sha256sums` | no |
| `imagebuilder-<version>/` | Extracted Image Builder | no |
| `out/` | Output of the last build, emptied at the start of each run | no |
| `releases/YYYY-MM-DD-HHMM/` | Builds saved with `--release`: images, manifest, checksums, `build-inputs/` | no, back it up separately |

## Prerequisites (Fedora x86_64)

    sudo dnf install make gcc perl python3 rsync wget unzip zstd tar gzip file curl mtools util-linux
    sudo dnf install perl-FindBin perl-Time-Piece perl-IO-Compress perl-File-Compare perl-Thread-Queue perl-IPC-Cmd

You also need about 2 GB of free disk space and access to [downloads.openwrt.org](https://downloads.openwrt.org/releases/).

## Build

    ./build.sh                    # OpenWrt 25.12.6 (default)
    ./build.sh 25.12.7            # another OpenWrt release
    OPENWRT_VERSION=25.12.7 ./build.sh
    ./build.sh --release          # build, then save to releases/YYYY-MM-DD-HHMM/
    ./build.sh -r 25.12.7         # same for another OpenWrt release
    ./build.sh --help

Each run does the following:

1. Fetches the release's `sha256sums` once, into `imagebuilder-dl/<version>/`. The source is the [target download folder](https://downloads.openwrt.org/releases/25.12.6/targets/bcm27xx/bcm2712/) of that release.
2. Verifies the archive against `sha256sums`. It downloads the archive only if it is missing or corrupt. If a fresh download does not match, the run stops.
3. Extracts the archive to `imagebuilder-<version>/` if that folder does not exist yet.
4. Appends the Wi-Fi/BT-off and PCIe Gen3 lines to the boot `config.txt` once, and builds squashfs images only.
5. Empties `out/` and runs `make image` with the package list, `files/`, `ROOTFS_PARTSIZE=512` and `EXTRA_IMAGE_NAME=cm5router`. The output goes to `out/`.
6. With `--release`, saves the build to `releases/YYYY-MM-DD-HHMM/` and verifies the checksums there (see [Save a release](#save-a-release)).

**Package list:** add packages to the existing `PACKAGES` list in [`build.sh`](build.sh); never replace the list. A leading `-` excludes a package; Wi-Fi and Attended Sysupgrade are excluded this way. Keep `mwan3`, `luci-app-mwan3` and the `kmod-usb-net-*` drivers, because the USB-tether failover depends on them.

**Check a build:**

    grep -iE "error|cannot|unable|unsatisf" build.log
    command diff <(sort releases/<last>/*.manifest) <(sort out/*.manifest)

## Install

**Upgrade (keeps settings).** In LuCI, go to System -> Backup / Flash Firmware and flash `out/*-squashfs-sysupgrade.img.gz`. Or use the [sysupgrade command line](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli) from the PC:

    scp -O out/*-sysupgrade.img.gz root@192.168.50.1:/tmp/up.img.gz
    ssh root@192.168.50.1 'sha256sum /tmp/up.img.gz; sysupgrade -T /tmp/up.img.gz && sysupgrade /tmp/up.img.gz'

Compare the checksum with `out/sha256sums`. `sysupgrade -n` discards settings. The message "Partition layout has changed. Full image will be written." is expected: the grow hook runs again before your settings are restored.

**Fresh flash (erases the eMMC):**

1. Set the BOOT switch to ON and connect the box's USB-C to the PC (see [Waveshare's flashing notes](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B)). From a build of [raspberrypi/usbboot](https://github.com/raspberrypi/usbboot), run `sudo ./rpiboot -d mass-storage-gadget64`.
2. Find the eMMC: it is the ~29.1G USB disk, model `mmcblk0`. The ~119G disk is the NVMe.
3. Decompress the image: `gzip -dc out/*-squashfs-factory.img.gz > /tmp/f.img` (the "trailing garbage" warning is the image metadata and is harmless).
4. Write it: `sudo dd if=/tmp/f.img of=/dev/sdX bs=4M conv=fsync status=progress`.
5. Verify it: `sudo cmp -n $(stat -c %s /tmp/f.img) /tmp/f.img /dev/sdX`.
6. Set BOOT to OFF. Cable the PC to eth1 and the upstream to eth0, then power on.

**After installing:**

1. Run `ssh-keygen -R 192.168.50.1` if the host key changed. It changes after a fresh flash, `-n` or a factory reset.
2. On the box, check that `dmesg | grep grow_rootfs` shows the grow, `df -h /overlay` shows about 29G, and `mwan3 interfaces` shows wan online.
3. Set the root password and add your SSH key in LuCI (System -> Administration).

## Updating

- **Latest packages, same release:** run `./build.sh` again. The Image Builder reads the release's online package indexes on every build. Kernel modules change only with a new release.
- **New release:** pick the version from [OpenWrt releases](https://downloads.openwrt.org/releases/) and run `./build.sh <version>`. Before installing, check:
  - `rpi-5` is still a profile: `make -C imagebuilder-<version> info`.
  - `imagebuilder-<version>/target/linux/bcm27xx/image/config.txt` exists.
  - `80_mount_root` (see [preinit and root mount](https://openwrt.org/docs/techref/preinit_mount)) and the "Partition layout has changed" full-image write still exist in the release's `base-files`.
  - If apk cannot select a package, the package was renamed; update the list.
  - The release notes mention no config migrations you need to handle.
- **Roll out:** build with `./build.sh --release <version>`, then on the box run `sysupgrade -T`, then sysupgrade. Run the checks above and test the failover by unplugging eth0. If anything fails, delete the new release folder and roll back.
- **Avoid:** Attended Sysupgrade, which installs a stock image without the grow hook or the defaults. Also avoid upgrading every package with `apk upgrade` on the box: the overlay fills with duplicate copies, and kernel modules can stop matching the kernel.

## Save a release

    ./build.sh --release [version]

After a successful build, this creates `releases/YYYY-MM-DD-HHMM/`. The folder name uses the local time to the minute, so several builds on the same day never collide. An existing folder is never overwritten. The folder contains:

| File | Contents |
| --- | --- |
| `*-squashfs-factory.img.gz`, `*-squashfs-sysupgrade.img.gz` | The images |
| `*.manifest` | Package list; the file names carry the OpenWrt version |
| `sha256sums` | Checksums, verified after copying |
| `build-inputs/` | `build.sh`, `files/` and `README.md` exactly as used for the build |

The release is saved before it has been tested on the box. If testing fails, delete that folder.

To rebuild an old release, copy its `build-inputs/*` back into this folder, then run `./build.sh <its version>`.

## Recovery

- **Factory reset:** in LuCI, System -> Backup / Flash Firmware -> Perform reset. Or run `firstboot -y && reboot`. See [failsafe mode and factory reset](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset).
- **Roll back:** sysupgrade the previous release's image with `-n`, or reflash its factory image.
- **Boot stops at "Waiting for root device PARTUUID=...":** the MBR disk ID does not match `cmdline.txt`. Over rpiboot, run `sudo sfdisk --disk-id /dev/sdX 0x<id from partuuid.txt>`.

## References

- [Waveshare CM5-DUAL-ETH-BOX-B wiki](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B)
- [Waveshare CM5-DUAL-ETH-BOX-B NVMe guide](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B-Tutorials-NVMe)
- [OpenWrt Image Builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder)
- [OpenWrt bcm27xx target](https://openwrt.org/docs/techref/targets/bcm27xx) and [25.12.6 downloads](https://downloads.openwrt.org/releases/25.12.6/targets/bcm27xx/bcm2712/)
- [mwan3 multi-WAN](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3)
- [uci-defaults](https://openwrt.org/docs/guide-developer/uci-defaults)
- [sysupgrade](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)
- [Failsafe mode and factory reset](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset)
- [raspberrypi/usbboot (rpiboot)](https://github.com/raspberrypi/usbboot)
- [Raspberry Pi config.txt](https://www.raspberrypi.com/documentation/computers/config_txt.html)
