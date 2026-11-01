#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the custom OpenWrt squashfs router image for the
# Waveshare CM5-DUAL-ETH-BOX-B with the official Image Builder.
#
#   ./build.sh                     build OpenWrt $OPENWRT_VERSION (default below)
#   ./build.sh 25.12.7             build another OpenWrt release
#   ./build.sh --release [ver]     build, then save it to releases/YYYY-MM-DD-HHMM/
#
# The Image Builder is kept in this folder, one copy per release:
#   imagebuilder-dl/<version>/   the downloaded archive + the release's sha256sums
#   imagebuilder-<version>/      the extracted Image Builder
# Each run checks the GPG signature on sha256sums against the OpenWrt keys in
# keys/, then verifies the archive against sha256sums; download and extraction
# are skipped when already done.
# Output: out/*-squashfs-factory.img.gz (flash) and *-squashfs-sysupgrade.img.gz
set -e

usage() {
	echo "usage: $0 [-r|--release] [openwrt-version]"
	echo "  -r, --release   after the build, save images, manifest, checksums and"
	echo "                  build inputs to releases/YYYY-MM-DD-HHMM/"
}

HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="${OPENWRT_VERSION:-25.12.6}"
RELEASE=0
for arg in "$@"; do
	case "$arg" in
	-r|--release) RELEASE=1 ;;
	-h|--help) usage; exit 0 ;;
	-*) echo "unknown option: $arg" >&2; usage >&2; exit 1 ;;
	*) VERSION="$arg" ;;
	esac
done

TARGET="bcm27xx/bcm2712"
URL="https://downloads.openwrt.org/releases/$VERSION/targets/$TARGET"
ARCHIVE="openwrt-imagebuilder-$VERSION-$(echo "$TARGET" | tr / -).Linux-x86_64.tar.zst"
DL="$HERE/imagebuilder-dl/$VERSION"
IB="$HERE/imagebuilder-$VERSION"

verify_archive() {
	[ -f "$DL/$ARCHIVE" ] &&
		(cd "$DL" && grep " \*\?$ARCHIVE\$" sha256sums | sha256sum -c --status -)
}

# sha256sums: fetch it with its signature and check it against OpenWrt's keys
mkdir -p "$DL"
[ -s "$DL/sha256sums" ] || curl -fsSL -o "$DL/sha256sums" "$URL/sha256sums"
[ -s "$DL/sha256sums.asc" ] || curl -fsSL -o "$DL/sha256sums.asc" "$URL/sha256sums.asc"
GNUPG_TMP="$(mktemp -d)"
gpg --homedir "$GNUPG_TMP" --quiet --import "$HERE"/keys/*.asc 2>/dev/null
gpg --homedir "$GNUPG_TMP" --export > "$DL/openwrt-keys.gpg"
rm -rf "$GNUPG_TMP"
if gpgv --keyring "$DL/openwrt-keys.gpg" "$DL/sha256sums.asc" "$DL/sha256sums" 2>/dev/null; then
	echo "Image Builder $VERSION: sha256sums signature verified"
else
	echo "Image Builder $VERSION: sha256sums is not signed by a key in keys/, deleting it" >&2
	rm -f "$DL/sha256sums" "$DL/sha256sums.asc"
	exit 1
fi

# Image Builder: download if missing or corrupt, verify, extract if missing
if verify_archive; then
	echo "Image Builder $VERSION: archive verified, download skipped"
else
	echo "Image Builder $VERSION: downloading"
	curl -fL --progress-bar -o "$DL/$ARCHIVE.part" "$URL/$ARCHIVE"
	mv "$DL/$ARCHIVE.part" "$DL/$ARCHIVE"
	if ! verify_archive; then
		echo "Image Builder $VERSION: checksum mismatch, deleting $ARCHIVE" >&2
		rm -f "$DL/$ARCHIVE"
		exit 1
	fi
	echo "Image Builder $VERSION: archive verified"
fi

if [ -f "$IB/.config" ]; then
	echo "Image Builder $VERSION: already extracted, extraction skipped"
else
	echo "Image Builder $VERSION: extracting"
	rm -rf "$IB.tmp"
	mkdir -p "$IB.tmp"
	tar --zstd -xf "$DL/$ARCHIVE" -C "$IB.tmp" --strip-components=1
	mkdir -p "$IB.tmp/dl" "$IB.tmp/tmp"
	mv "$IB.tmp" "$IB"
fi

# Boot partition: Wi-Fi/BT off in hardware, M.2 slot at PCIe Gen3, the CM5's
# USB 2.0 OTG controller in host mode (drives the box's USB 2.0 Type-A port), and
# the PWM fan header on (harmless without a fan)
CFG="$IB/target/linux/bcm27xx/image/config.txt"
for line in dtoverlay=disable-wifi-pi5 dtoverlay=disable-bt-pi5 dtparam=pciex1_gen=3 dtoverlay=dwc2,dr_mode=host dtparam=cooling_fan=on; do
	grep -qx "$line" "$CFG" || echo "$line" >> "$CFG"
done

# squashfs images only
sed -i 's/^CONFIG_TARGET_ROOTFS_EXT4FS=y$/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/' "$IB/.config"

PACKAGES=""
pkg() { PACKAGES="$PACKAGES $*"; }

# base system, as in OpenWrt's rpi-5 profile
pkg apk-mbedtls base-files bcm27xx-gpu-fw bcm27xx-utils ca-bundle dnsmasq dropbear e2fsprogs firewall4
pkg fstools libc libgcc libustream-mbedtls logd mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only
pkg partx-utils ppp ppp-mod-pppoe procd-ujail uci uclient-fetch urandom-seed

# hardware: CM5 board, 2.5GbE NIC, power button, USB 2.0 port, fan
pkg kmod-fs-vfat kmod-hwmon-pwmfan kmod-i2c-bcm2835 kmod-i2c-brcmstb kmod-i2c-designware-platform
pkg kmod-nft-offload kmod-nls-cp437 kmod-nls-iso8859-1 kmod-r8169 kmod-sound-arm-bcm2835 kmod-sound-core
pkg kmod-spi-bcm2835 kmod-spi-dw-mmio kmod-thermal kmod-usb-hid kmod-usb-net-lan78xx kmod-usb-net-rtl8152
pkg kmod-gpio-button-hotplug kmod-usb-dwc2

# web interface and router features
pkg luci luci-ssl luci-app-upnp sqm-scripts luci-app-sqm

# failover and backup uplinks: phone tethering, USB Ethernet, LTE modems
pkg mwan3 luci-app-mwan3
pkg kmod-usb-net-rndis kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim
pkg kmod-usb-net-qmi-wwan kmod-usb-net-huawei-cdc-ncm kmod-usb-net-ipheth kmod-usb-net-asix
pkg kmod-usb-net-asix-ax88179 kmod-usb-net-rtl8150 kmod-usb-serial-option usb-modeswitch uqmi umbim
pkg usbmuxd libimobiledevice-utils luci-proto-qmi luci-proto-mbim

# VPN
pkg kmod-wireguard wireguard-tools luci-proto-wireguard qrencode kmod-tun tailscale luci-app-tailscale-community

# storage: automount, filesystems, disk tools
pkg block-mount kmod-usb-storage kmod-fs-ext4 kmod-fs-exfat kmod-fs-ntfs3 resize2fs parted losetup lsblk
pkg nvme-cli smartmontools

# monitoring: per-device usage, per-interface totals, graphs
pkg nlbwmon luci-app-nlbwmon vnstat2 luci-app-vnstat2 luci-app-statistics collectd-mod-rrdtool
pkg collectd-mod-conntrack collectd-mod-cpu collectd-mod-cpufreq collectd-mod-df collectd-mod-disk
pkg collectd-mod-exec collectd-mod-interface collectd-mod-load collectd-mod-memory collectd-mod-ping
pkg collectd-mod-processes collectd-mod-sqm collectd-mod-thermal collectd-mod-uptime

# tools
pkg htop iperf3 ethtool tcpdump curl iputils-arping etherwake luci-app-wol

# left out: onboard Wi-Fi (disabled in hardware), Attended Sysupgrade (would install a stock image)
pkg -kmod-brcmfmac -wpad-basic-mbedtls -cypress-firmware-43455-sdio -brcmfmac-nvram-43455-sdio
pkg -luci-app-attendedsysupgrade

# start from an empty out/ so a release never picks up an older build
rm -rf "$HERE/out"

make -C "$IB" image \
	PROFILE=rpi-5 \
	PACKAGES="$(echo $PACKAGES)" \
	FILES="$HERE/files" \
	ROOTFS_PARTSIZE=512 \
	EXTRA_IMAGE_NAME=cm5router \
	BIN_DIR="$HERE/out"

echo "Built OpenWrt $VERSION images in $HERE/out"

[ "$RELEASE" = 1 ] || exit 0

REL="$HERE/releases/$(date +%Y-%m-%d-%H%M)"
if [ -e "$REL" ]; then
	echo "$REL already exists, not overwriting it" >&2
	exit 1
fi
mkdir -p "$REL/build-inputs"
cp -p "$HERE"/out/*.img.gz "$HERE"/out/*.manifest "$HERE/out/sha256sums" "$REL/"
cp -pr "$HERE/build.sh" "$HERE/files" "$HERE/keys" "$HERE/README.md" "$REL/build-inputs/"
(cd "$REL" && sha256sum -c --ignore-missing --quiet sha256sums)
echo "Saved release $REL"
