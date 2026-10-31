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
| Power button | A short press of PSW does a clean poweroff; a press while off powers on |
| Storage | [`75_grow_rootfs_part`](files/lib/preinit/75_grow_rootfs_part) grows partition 2 to the end of the eMMC before the overlay is created, so the f2fs overlay spans the whole eMMC (about 29 GB on a 32 GB CM5) |

The router defaults are set by [`90-router-defaults`](files/etc/uci-defaults/90-router-defaults), a [uci-defaults](https://openwrt.org/docs/guide-developer/uci-defaults) script. [`03_cm5_network`](files/etc/board.d/03_cm5_network) describes eth1 as lan and eth0 as wan in `/etc/board.json`, which LuCI's port status reads. The failover policy is in [`files/etc/config/mwan3`](files/etc/config/mwan3).

The fan header and the RTC battery header are not used by default. See [Optional hardware](#optional-hardware-fan-and-rtc-battery).

## Layout

| Path | Contents | In git |
| --- | --- | --- |
| [`build.sh`](build.sh) | Image Builder download/verify/extract, package list, build | yes |
| [`files/`](files) | Files copied into the image (grow hook, board ports, router defaults, mwan3 config) | yes |
| `imagebuilder-dl/<version>/` | Downloaded Image Builder archive and the release's `sha256sums` | no |
| `imagebuilder-<version>/` | Extracted Image Builder | no |
| `out/` | Output of the last build, emptied at the start of each run | no |
| `releases/YYYY-MM-DD-HHMM/` | Builds saved with `--release`: images, manifest, checksums, `build-inputs/` | no, back it up separately |

## Prerequisites

On Fedora x86_64:

    sudo dnf install make gcc perl python3 rsync wget unzip zstd tar gzip file curl mtools util-linux perl-FindBin perl-Time-Piece perl-IO-Compress perl-File-Compare perl-Thread-Queue perl-IPC-Cmd

On other distributions, install the equivalent packages. If anything is missing, the Image Builder's prerequisite check names it. You also need about 2 GB of free disk space and access to [downloads.openwrt.org](https://downloads.openwrt.org/releases/).

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

**Package list:** add packages to the existing `PACKAGES` list in [`build.sh`](build.sh); never replace the list. A leading `-` excludes a package; Wi-Fi and Attended Sysupgrade are excluded this way. Keep `mwan3`, `luci-app-mwan3` and the `kmod-usb-net-*` drivers, because the USB-tether failover depends on them. Also keep `kmod-gpio-button-hotplug`, which the power button needs.

**Check a build:**

    grep -iE "error|cannot|unable|unsatisf" build.log
    command diff <(sort releases/<last>/*.manifest) <(sort out/*.manifest)

## Install

### Upgrade a box that already runs this image (keeps settings)

In LuCI, go to System -> Backup / Flash Firmware and flash `out/*-squashfs-sysupgrade.img.gz`. Or use the [sysupgrade command line](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli) from the PC:

    scp -O out/*-sysupgrade.img.gz root@192.168.50.1:/tmp/up.img.gz
    ssh root@192.168.50.1 'sha256sum /tmp/up.img.gz; sysupgrade -T /tmp/up.img.gz && sysupgrade /tmp/up.img.gz'

Compare the checksum with `out/sha256sums`. `sysupgrade -n` discards settings. The message "Partition layout has changed. Full image will be written." is expected: the grow hook runs again before your settings are restored.

### Fresh flash over USB (erases the eMMC)

The CM5's eMMC is written from a Linux PC with `rpiboot`, which makes the CM5 show up as a USB disk.

**1. Build rpiboot once.** Use [raspberrypi/usbboot](https://github.com/raspberrypi/usbboot), following its own README:

    sudo dnf install git libusb1-devel pkg-config glibc-devel g++ gcc make       # Fedora
    sudo apt install git libusb-1.0-0-dev pkg-config build-essential             # Debian/Ubuntu
    git clone --recurse-submodules --shallow-submodules --depth=1 https://github.com/raspberrypi/usbboot
    cd usbboot && make

**2. Expose the eMMC as a USB disk.**

1. Power the box off and slide the BOOT switch to ON (see [Waveshare's notes](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B)).
2. Connect the box's USB-C port to the PC with a data cable. In this mode the PC powers the box. Waveshare advises leaving other USB devices unplugged, since they can draw too much power for the box to be recognised.
3. In the `usbboot` folder, run `sudo ./rpiboot -d mass-storage-gadget64`. It loads a small Linux onto the CM5, which exports the eMMC (and an NVMe, if fitted) as USB disks a few seconds after `rpiboot` finishes.

**3. Find the eMMC.** This is the important step, because writing to the wrong disk destroys it.

    lsblk -o NAME,SIZE,TRAN,LABEL,PARTUUID
    sudo dmesg | grep -i "Direct-Access"

The eMMC is a new `usb` disk whose size matches your CM5's eMMC (16, 32 or 64 GB), and dmesg lists it as `mmcblk0`. An NVMe, if fitted, shows as a second new USB disk with the SSD's size. Below, `/dev/sdX` stands for the eMMC. Unmount anything your desktop mounted from it: `sudo umount /dev/sdX?*`.

**4. Optional: back up what is on the eMMC.**

    sudo dd if=/dev/sdX bs=4M status=progress | zstd -T0 -3 -o emmc-backup.img.zst

**5. Write and verify the image.**

    gzip -dc out/*-squashfs-factory.img.gz > /tmp/f.img        # "trailing garbage" warning = image metadata, harmless
    sudo dd if=/tmp/f.img of=/dev/sdX bs=4M conv=fsync status=progress
    sudo cmp -n $(stat -c %s /tmp/f.img) /tmp/f.img /dev/sdX && echo VERIFIED

**6. Boot it.** Unplug the USB-C from the PC and slide BOOT back to OFF. Then connect a 5V 5A supply to the USB-C port, your PC to eth1 (2.5GbE) and the upstream modem or router to eth0 (1GbE).

### After installing

1. Run `ssh-keygen -R 192.168.50.1` if your PC knew an older host key. The key changes after a fresh flash, `sysupgrade -n` or a factory reset.
2. Log in with `ssh root@192.168.50.1`, or open http://192.168.50.1. Check that `dmesg | grep grow_rootfs` shows the grow, `df -h /overlay` shows almost the whole eMMC, and `mwan3 interfaces` shows wan online.
3. Set the root password and add your SSH key in LuCI (System -> Administration).

## Optional hardware: fan and RTC battery

Both headers are left alone by default, because the reference box has neither a fan nor an RTC battery. The steps below are untested on that box.

Settings go in `/boot/config.txt` on the box, which lives on the boot partition rather than the overlay. So a factory reset keeps them, and a sysupgrade with keep settings carries them over. A fresh flash or `sysupgrade -n` replaces `config.txt` with the image's. To make a setting part of the image, add the line to the `for line in ...` list in [`build.sh`](build.sh) that appends to `config.txt`.

### Fan on the 4-pin header

The image already has the `pwm-fan` driver, but the CM5 device tree keeps the fan switched off until it is enabled.

1. Add this line to `/boot/config.txt` and reboot:

        dtparam=cooling_fan=on

2. Check that the fan is registered: `cat /sys/class/thermal/cooling_device*/type` should list `pwm-fan`, and `cat /sys/class/hwmon/hwmon*/pwm1` shows its current speed (0-255).
3. Optionally tune when it spins up with `fan_temp0` ... `fan_temp3`, plus the matching `_speed` and `_hyst` parameters (temperatures in millidegrees Celsius, speeds 0-255). See the [config.txt documentation](https://www.raspberrypi.com/documentation/computers/config_txt.html).

### RTC battery

The CM5 has a real-time clock, which OpenWrt already uses as `/dev/rtc0`. Without a battery, the clock resets whenever power is removed. At boot, `dmesg | grep rtc` then shows 1970, and the time stays wrong until NTP sets it once wan is up.

With a battery on the RTC header:

1. **Rechargeable cell only** (for example a Panasonic ML-series lithium manganese cell): enable trickle charging in `/boot/config.txt` and reboot. Never enable this for a non-rechargeable coin cell.

        dtparam=rtc_bbat_vchg=3000000

2. Keep the RTC in step with NTP. OpenWrt's `sysfixtime` reads the RTC at boot but only writes it at a clean shutdown or reboot. A hotplug script that writes it each time NTP reports a valid time keeps it correct after power cuts as well. Create `/etc/hotplug.d/ntp/20-rtc` on the box, or `files/etc/hotplug.d/ntp/20-rtc` here to build it into the image:

        [ "$ACTION" = "stratum" ] || exit 0
        hwclock -w -u

3. Check: remove power for a minute and boot with wan unplugged. `date` should show the right time, and `dmesg | grep rtc` should no longer show 1970.

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
- **Restore an eMMC backup:** expose the eMMC with `rpiboot` (steps 2 and 3 of [Fresh flash over USB](#fresh-flash-over-usb-erases-the-emmc)), then run `zstd -dc emmc-backup.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress`.
- **Boot stops at "Waiting for root device PARTUUID=...":** the MBR disk ID does not match `cmdline.txt`. This can happen after repartitioning the eMMC with other tools. Expose the eMMC with `rpiboot` as above, then run `sudo sfdisk --disk-id /dev/sdX 0x<id from partuuid.txt>`. `partuuid.txt` is on the boot partition.

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
