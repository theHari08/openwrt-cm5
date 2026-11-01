# OpenWrt router image for the Waveshare CM5-DUAL-ETH-BOX-B

Custom [OpenWrt](https://openwrt.org/) image for the [Waveshare CM5-DUAL-ETH-BOX-B](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B), a Raspberry Pi CM5 with eMMC in a dual-Ethernet box. It targets [bcm27xx/bcm2712](https://openwrt.org/docs/techref/targets/bcm27xx) as a squashfs image and is built with the official [OpenWrt Image Builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder). [`build.sh`](build.sh) downloads, verifies and extracts the Image Builder, then builds the image.

## Defaults (first boot and after every factory reset)

| Setting | Default |
| --- | --- |
| lan | eth1 (2.5GbE, RTL8156 on internal USB), br-lan 192.168.50.1/24, DHCP .100-.249 |
| wan | eth0 (1GbE, RP1), DHCP client, [mwan3](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3) primary |
| Backup uplinks | Used by mwan3 in this order when wan has no internet: `wanusb` = usb0 (Android USB tethering), `wanusbeth` = eth2 (iPhone USB tethering, a USB Ethernet adapter or an LTE stick in HiLink mode), `wwan` = an LTE modem in QMI or MBIM mode. See [Backup uplinks](#backup-uplinks) |
| IPv6 | Off: wan6 exists with `auto=0`, no RA/DHCPv6 on lan |
| Firewall | Normal router: wan, wan6 and all backup uplinks NATed, inbound rejected; manage from lan only |
| Login | LuCI over HTTP; no root password until set in LuCI |
| SSH | Off. Turn it on in LuCI after first boot (see [After installing](#after-installing)) |
| SQM | [Cake](https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm) set up on eth0 but disabled until you enter your line speeds |
| Traffic stats | nlbwmon keeps its database in `/etc/nlbwmon` on flash, so per-device usage survives reboots and sysupgrades. It writes once a day and stays small |
| Traffic totals | vnstat counts daily and monthly traffic on eth0, br-lan and the backup uplinks (usb0, eth2, wwan0), which shows mobile data use. Its database is in `/etc/vnstat` on flash and is kept across sysupgrades. LuCI -> Status -> vnStat Traffic Monitor |
| Statistics graphs | collectd with LuCI -> Statistics: CPU, memory, temperature, storage, interfaces, connections, ping and SQM. Graph data is kept in RAM (`/tmp/rrd`) to spare the eMMC, so the graphs start fresh after a reboot. To keep them, set the data directory to a folder on `/mnt/nvme` in Statistics -> Setup |
| Wake-on-LAN | Services -> Wake on LAN can wake a device on the lan by its MAC address |
| DNS | dnsmasq asks Cloudflare (1.1.1.1, 1.0.0.1) as well as the DNS servers the uplink hands out, so names still resolve while a backup uplink is in use |
| Storage | NVMe and USB drives are mounted automatically: NVMe at `/mnt/nvme`, USB drives under their label (e.g. `/mnt/Backup`). See [USB and NVMe storage](#usb-and-nvme-storage) |
| Status LED | Green on with the wan link and blinking with wan traffic. Green blinking with the backup uplink's traffic when only a backup has internet. **Red fast blink when no uplink has internet.** Driven by mwan3's tracking ([`cm5-status-led`](files/usr/libexec/cm5-status-led)) |
| UPnP / NAT-PMP | Installed but off. Turn it on in Services -> UPnP IGD & PCP if a console or app needs it |
| Tailscale | Installed but not started. See [Tailscale](#tailscale) |
| Boot config | Wi-Fi and Bluetooth disabled ([`dtoverlay`](https://www.raspberrypi.com/documentation/computers/config_txt.html)), M.2 slot at PCIe Gen3 as in the [Waveshare NVMe guide](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B-Tutorials-NVMe), the CM5's USB 2.0 OTG controller in host mode (`dtoverlay=dwc2,dr_mode=host`), and the PWM fan header on (`dtparam=cooling_fan=on`) |
| USB ports | The blue USB 3.0 port is on the RP1's first USB controller. The 2.5GbE NIC (eth1) is soldered to the second one. The black USB 2.0 port is wired through a USB switch to the CM5's own USB 2.0 OTG controller, which is also what the USB-C port uses for flashing in BOOT mode. OpenWrt leaves that controller off, so the image turns it on in host mode with `kmod-usb-dwc2`. Without that, the black port gives no power and sees nothing |
| Power button | A short press of PSW does a clean poweroff; a press while off powers on |
| Storage | [`75_grow_rootfs_part`](files/lib/preinit/75_grow_rootfs_part) grows partition 2 to the end of the eMMC before the overlay is created, so the f2fs overlay spans the whole eMMC (about 29 GB on a 32 GB CM5) |

The router defaults are set by [`90-router-defaults`](files/etc/uci-defaults/90-router-defaults), a [uci-defaults](https://openwrt.org/docs/guide-developer/uci-defaults) script. [`03_cm5_network`](files/etc/board.d/03_cm5_network) describes eth1 as lan and eth0 as wan in `/etc/board.json`, which LuCI's port status reads. The failover policy is in [`files/etc/config/mwan3`](files/etc/config/mwan3).

The fan header and the RTC are ready for a fan or a backup battery, with nothing to set up. See [Fan and RTC battery](#fan-and-rtc-battery).

## Layout

| Path | Contents | In git |
| --- | --- | --- |
| [`build.sh`](build.sh) | Image Builder download/verify/extract, package list, build | yes |
| [`files/`](files) | Files copied into the image (grow hook, board ports, router defaults, mwan3 config) | yes |
| [`keys/`](keys) | OpenWrt's public GPG key that signs the release `sha256sums` | yes |
| `imagebuilder-dl/<version>/` | Downloaded Image Builder archive and the release's `sha256sums` | no |
| `imagebuilder-<version>/` | Extracted Image Builder | no |
| `out/` | Output of the last build, emptied at the start of each run | no |
| `releases/YYYY-MM-DD-HHMM/` | Builds saved with `--release`: images, manifest, checksums, `build-inputs/` | no, back it up separately |

## Prerequisites

On Fedora x86_64:

    sudo dnf install make gcc perl python3 rsync wget unzip zstd tar gzip file curl gnupg2 mtools util-linux perl-FindBin perl-Time-Piece perl-IO-Compress perl-File-Compare perl-Thread-Queue perl-IPC-Cmd

On other distributions, install the equivalent packages. If anything is missing, the Image Builder's prerequisite check names it. You also need about 2 GB of free disk space and access to [downloads.openwrt.org](https://downloads.openwrt.org/releases/).

## Build

    ./build.sh                    # OpenWrt 25.12.6 (default)
    ./build.sh 25.12.7            # another OpenWrt release
    OPENWRT_VERSION=25.12.7 ./build.sh
    ./build.sh --release          # build, then save to releases/YYYY-MM-DD-HHMM/
    ./build.sh -r 25.12.7         # same for another OpenWrt release
    ./build.sh --help

Each run does the following:

1. Fetches the release's `sha256sums` and its signature `sha256sums.asc` once, into `imagebuilder-dl/<version>/`. The source is the [target download folder](https://downloads.openwrt.org/releases/25.12.6/targets/bcm27xx/bcm2712/) of that release. On every run it checks the signature with `gpgv` against the keys in [`keys/`](keys). If the signature is bad or from an unknown key, it deletes both files and stops.
2. Verifies the archive against `sha256sums`. It downloads the archive only if it is missing or corrupt. If a fresh download does not match, the run stops.
3. Extracts the archive to `imagebuilder-<version>/` if that folder does not exist yet.
4. Appends the Wi-Fi/BT-off, PCIe Gen3, USB 2.0 host-mode and fan lines to the boot `config.txt` once, and builds squashfs images only.
5. Empties `out/` and runs `make image` with the package list, `files/`, `ROOTFS_PARTSIZE=512` and `EXTRA_IMAGE_NAME=cm5router`. The output goes to `out/`.
6. With `--release`, saves the build to `releases/YYYY-MM-DD-HHMM/` and verifies the checksums there (see [Save a release](#save-a-release)).

**Package list:** packages are added in [`build.sh`](build.sh) with `pkg` lines, grouped by purpose under a comment (base system, hardware, web interface, uplinks, VPN, storage, monitoring, tools). Add to the matching group, or start a new one; never replace the list. A leading `-` excludes a package; the exclusions for Wi-Fi and Attended Sysupgrade are the last group. Keep `mwan3`, `luci-app-mwan3`, the `kmod-usb-net-*` drivers, `usbmuxd`, `uqmi` and `umbim`, because the backup uplinks depend on them. Also keep `kmod-gpio-button-hotplug`, which the power button needs.

**Check a build:**

    grep -iE "error|cannot|unable|unsatisf" build.log
    command diff <(sort releases/<last>/*.manifest) <(sort out/*.manifest)

## Install

### Upgrade a box that already runs this image (keeps settings)

In LuCI, go to System -> Backup / Flash Firmware and flash `out/*-squashfs-sysupgrade.img.gz`. Or use the [sysupgrade command line](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli) from the PC:

    scp -O out/*-sysupgrade.img.gz root@192.168.50.1:/tmp/up.img.gz
    ssh root@192.168.50.1 'sha256sum /tmp/up.img.gz; sysupgrade -T /tmp/up.img.gz && sysupgrade /tmp/up.img.gz'

Compare the checksum with `out/sha256sums`. `sysupgrade -n` discards settings. The message "Partition layout has changed. Full image will be written." is expected: the grow hook runs again before your settings are restored.

OpenWrt runs uci-defaults scripts again after a sysupgrade that keeps settings. [`90-router-defaults`](files/etc/uci-defaults/90-router-defaults) sets `system.@system[0].cm5router_defaults=1` the first time it runs, and does nothing if that marker is already set. So an upgrade never resets your LAN, SSH or other settings. The flip side is that new defaults in a newer image only reach an existing box after a factory reset, or if you add them by hand.

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

1. Open http://192.168.50.1 and set the root password when LuCI asks for it.
2. **SSH is off by default.** To use it, go to System -> Administration -> SSH Access, tick **Enable Instance**, then Save & Apply. Add your public key under SSH-Keys, and consider turning off password login once the key works.
3. **HTTPS is optional.** LuCI serves plain HTTP by default. To force HTTPS, go to System -> Administration -> HTTP(S) Access and tick **Redirect to HTTPS**. The certificate is self-signed, so the browser warns once.
4. If you use SSH and your PC knew an older host key, run `ssh-keygen -R 192.168.50.1`. The key changes after a fresh flash, `sysupgrade -n` or a factory reset.
5. Check that `dmesg | grep grow_rootfs` shows the grow, `df -h /overlay` shows almost the whole eMMC, and `mwan3 interfaces` shows wan online. Status -> Overview in LuCI shows the same.
6. Optional: set up SQM in Network -> SQM QoS. Set download and upload to about 90% of your real line speed, tick Enable, then Save & Apply.

## Backup uplinks

When wan stops reaching the internet, mwan3 moves traffic to the first backup uplink that is online and moves it back when wan recovers. It checks each uplink by pinging 1.1.1.1, 8.8.8.8 and 9.9.9.9 every 5 seconds. Each time wan goes offline or comes back, the router clears its connection table (`flush_conntrack`), so open connections reconnect straight away over the uplink now in use instead of hanging on the old one. A video call or download in progress restarts once at that moment. Status -> MultiWAN Manager in LuCI shows which uplink is in use. More on USB uplinks in the OpenWrt wiki: [smartphone USB tethering](https://openwrt.org/docs/guide-user/network/wan/smartphone.usb.tethering) and [WWAN](https://openwrt.org/docs/guide-user/network/wan/wwan/start).

| Uplink | Device | What to plug in | Setup |
| --- | --- | --- | --- |
| `wanusb` | usb0 | Android phone | Connect it by USB and turn on USB tethering |
| `wanusbeth` | eth2 | iPhone, a USB Ethernet adapter, or an LTE stick in HiLink/router mode | iPhone: turn on Personal Hotspot, connect by USB, unlock it and tap **Trust**. `usbmuxd` pairs it and the pairing is kept across reboots and sysupgrades. Adapters and HiLink sticks need nothing |
| `wwan` | wwan0 | LTE modem in QMI or MBIM mode | Auto-detected. If the carrier needs an APN or the SIM has a PIN, run `uci set network.wwan.apn='your.apn'` (and `network.wwan.pincode`), then `uci commit network; ifup wwan`. LuCI shows the `wwan` protocol as unsupported, but you can switch the interface to the QMI or MBIM protocol there and fill in the APN |

eth2 is the next free Ethernet name. If you plug in more than one USB Ethernet device, only the one that comes up as eth2 is used as a backup uplink. See the [QMI/MBIM dongle guide](https://openwrt.org/docs/guide-user/network/wan/wwan/ltedongle) for modems that start in USB storage mode (`usb-modeswitch` is included).

## USB and NVMe storage

[`20-automount`](files/etc/hotplug.d/block/20-automount) mounts drives as soon as they appear, including drives that are already connected at boot:

| Drive | Mount point |
| --- | --- |
| NVMe in the M.2 slot | `/mnt/nvme`; further partitions at `/mnt/nvme-2`, `/mnt/nvme-3`, ... |
| USB drive (each partition) with a filesystem label | `/mnt/<label>`, for example `/mnt/Backup` or `/mnt/My_Photos` |
| USB drive with no label but a GPT partition name | `/mnt/<partition name>` |
| USB drive with neither | `/mnt/usb0`, `/mnt/usb1`, ... in the order they are plugged in; further partitions on the same drive at `/mnt/usb0-2`, ... |

Supported filesystems are ext2/3/4, f2fs, FAT, exFAT and NTFS. Anything else, including an empty or unformatted drive, is left alone, and so is the eMMC.

- **Give your USB drives a label.** A label travels with the drive, so it gets the same path every time, in either USB port and whatever else is plugged in. Set the label when formatting the drive on a PC, or rename the drive in the PC's file manager. Characters other than letters, digits, `.`, `_` and `-` become `_` (`My Photos` is mounted at `/mnt/My_Photos`). If two drives share a label, the second one gets `-2` (`/mnt/Backup-2`). `/mnt/nvme` never changes, since the box has only one M.2 slot.
- **Unlabelled drives follow plug-in order.** Without a label or partition name, the same stick can be `usb0` today and `usb1` after a reboot. That is fine for copying files. For anything that depends on the path, label the drive, or add a mount point by UUID in LuCI (System -> Mount Points). A drive with an enabled mount point there is mounted by OpenWrt's `block-mount` instead and left alone here.
- **Unmount before unplugging** to avoid losing data: `umount /mnt/Backup`, or the Unmount button in System -> Mount Points.
- `logread | grep automount` shows what was mounted or skipped.

## Tailscale

Tailscale is installed but does not run until you set it up, so it costs nothing for those who do not use it.

1. In LuCI, go to System -> Startup, then Enable and Start `tailscale`. Or over SSH, run `/etc/init.d/tailscale enable && /etc/init.d/tailscale start`.
2. Run `tailscale up` over SSH and open the login link it prints. The Tailscale page under Services can be used for the rest.

[`95-tailscale-autostart`](files/etc/uci-defaults/95-tailscale-autostart) runs on first boot and again after every sysupgrade. It keeps Tailscale enabled once its state file exists (the file is kept across sysupgrades), and off otherwise.

## Fan and RTC battery

Settings in this section go in `/boot/config.txt`, which lives on the boot partition rather than the overlay. So a factory reset keeps them, and a sysupgrade with keep settings carries them over. A fresh flash or `sysupgrade -n` replaces `config.txt` with the image's. To make a setting part of the image, add the line to the `for line in ...` list in [`build.sh`](build.sh) that appends to `config.txt`.

### Fan on the 4-pin header

The fan header is on by default (`dtparam=cooling_fan=on` and the `pwm-fan` driver). Without a fan connected, this does nothing.

1. Connect a 5V PWM fan and boot. It spins up with the CPU temperature and stays off while the CPU is cool.
2. Check that it is registered: `cat /sys/class/thermal/cooling_device*/type` lists `pwm-fan`, and `cat /sys/class/hwmon/hwmon*/pwm1` shows its current speed (0-255).
3. Optionally tune when it spins up with `fan_temp0` ... `fan_temp3`, plus the matching `_speed` and `_hyst` parameters (temperatures in millidegrees Celsius, speeds 0-255). See the [config.txt documentation](https://www.raspberrypi.com/documentation/computers/config_txt.html).

### RTC battery

The CM5 has a real-time clock, which OpenWrt uses as `/dev/rtc0`. Without a battery, the clock resets whenever power is removed. At boot, `dmesg | grep rtc` then shows 1970, and the time stays wrong until NTP sets it once an uplink is up.

[`20-rtc`](files/etc/hotplug.d/ntp/20-rtc) saves the time to the RTC every time NTP reports a valid time. OpenWrt's `sysfixtime` otherwise writes it only at a clean shutdown. With a battery on the RTC header, the clock is therefore right after a power cut too. Without a battery, the hook is harmless.

- **Rechargeable cell only** (for example a lithium manganese ML-series cell): enable trickle charging in `/boot/config.txt` and reboot. Never enable this for a non-rechargeable coin cell.

        dtparam=rtc_bbat_vchg=3000000

- Check: remove power for a minute and boot with wan unplugged. `date` should show the right time, and `dmesg | grep rtc` should no longer show 1970.

## Updating

- **Latest packages, same release:** run `./build.sh` again. The Image Builder reads the release's online package indexes on every build. Kernel modules change only with a new release.
- **New release:** pick the version from [OpenWrt releases](https://downloads.openwrt.org/releases/) and run `./build.sh <version>`. Before installing, check:
  - `rpi-5` is still a profile: `make -C imagebuilder-<version> info`.
  - `imagebuilder-<version>/target/linux/bcm27xx/image/config.txt` exists.
  - `80_mount_root` (see [preinit and root mount](https://openwrt.org/docs/techref/preinit_mount)) and the "Partition layout has changed" full-image write still exist in the release's `base-files`.
  - If apk cannot select a package, the package was renamed; update the list.
  - If the build stops because `sha256sums` is not signed by a key in `keys/`, OpenWrt has moved to a new signing key. Look up the new key on [OpenWrt's signatures page](https://openwrt.org/docs/guide-user/security/signatures), download it from [openwrt/keyring](https://github.com/openwrt/keyring) (`gpg/<key id>.asc`), and check its fingerprint against that page with `gpg --show-keys`. Then add it to `keys/`.
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
| `build-inputs/` | `build.sh`, `files/`, `keys/` and `README.md` exactly as used for the build |

The release is saved before it has been tested on the box. If testing fails, delete that folder.

To rebuild an old release, copy its `build-inputs/*` back into this folder, then run `./build.sh <its version>`.

## Recovery

- **Factory reset:** in LuCI, System -> Backup / Flash Firmware -> Perform reset. Or run `firstboot -y && reboot`. See [failsafe mode and factory reset](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset).
- **Roll back:** sysupgrade the previous release's image with `-n`, or reflash its factory image.
- **Restore an eMMC backup:** expose the eMMC with `rpiboot` (steps 2 and 3 of [Fresh flash over USB](#fresh-flash-over-usb-erases-the-emmc)), then run `zstd -dc emmc-backup.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress`.
- **Boot stops at "Waiting for root device PARTUUID=...":** the MBR disk ID does not match `cmdline.txt`. This can happen after repartitioning the eMMC with other tools. Expose the eMMC with `rpiboot` as above, then run `sudo sfdisk --disk-id /dev/sdX 0x<id from partuuid.txt>`. `partuuid.txt` is on the boot partition.

## License

The contents of this repository (`build.sh`, `files/` and the documentation) are licensed under the [GNU General Public License v2.0 only](LICENSE) (`SPDX-License-Identifier: GPL-2.0-only`), the same license as the OpenWrt core they plug into. The OpenWrt public key in [`keys/`](keys) is published by OpenWrt in [openwrt/keyring](https://github.com/openwrt/keyring) and is included unchanged, so that the release checksums can be verified.

The images that `build.sh` produces are made of OpenWrt and its packages, which keep their own licenses, most of them GPL. If you publish those images, also make the matching source available. For an Image Builder build, that is the OpenWrt release you built from (for example [25.12.6](https://downloads.openwrt.org/releases/25.12.6/)) and its package feeds.

## References

- [Waveshare CM5-DUAL-ETH-BOX-B wiki](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B)
- [Waveshare CM5-DUAL-ETH-BOX-B NVMe guide](https://docs.waveshare.com/CM5-DUAL-ETH-BOX-B-Tutorials-NVMe)
- [OpenWrt Image Builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder)
- [OpenWrt bcm27xx target](https://openwrt.org/docs/techref/targets/bcm27xx) and [25.12.6 downloads](https://downloads.openwrt.org/releases/25.12.6/targets/bcm27xx/bcm2712/)
- [mwan3 multi-WAN](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3)
- [Smartphone USB tethering](https://openwrt.org/docs/guide-user/network/wan/smartphone.usb.tethering), [WWAN](https://openwrt.org/docs/guide-user/network/wan/wwan/start) and [QMI/MBIM dongles](https://openwrt.org/docs/guide-user/network/wan/wwan/ltedongle)
- [SQM (Smart Queue Management)](https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm)
- [OpenWrt signing keys](https://openwrt.org/docs/guide-user/security/signatures) and [openwrt/keyring](https://github.com/openwrt/keyring)
- [uci-defaults](https://openwrt.org/docs/guide-developer/uci-defaults)
- [sysupgrade](https://openwrt.org/docs/guide-user/installation/sysupgrade.cli)
- [Failsafe mode and factory reset](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset)
- [raspberrypi/usbboot (rpiboot)](https://github.com/raspberrypi/usbboot)
- [Raspberry Pi config.txt](https://www.raspberrypi.com/documentation/computers/config_txt.html)
