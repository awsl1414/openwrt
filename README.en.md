# SBE1V1K OpenWrt English Guide

[简体中文](README.zh-CN.md) | [Project home](README.md)

## Overview

This repository is the **`dev-sbe1v1k`** branch of
[awsl1414/openwrt](https://github.com/awsl1414/openwrt): OpenWrt
`qualcommbe/ipq95xx` support for the Spectrum/Askey **SBE1V1K** (also known as
**RTQ7300T**).

SBE1V1K support is not an official OpenWrt stable release. Use this firmware
only if you have a serial console, initramfs recovery, HTTP chainloader, or
another verified recovery path.

## Capabilities

| Item | Notes |
|---|---|
| SoC / storage | IPQ9570 (DTS compatible `qcom,ipq9574`), ~2 GB RAM / 8 GB eMMC |
| Ethernet | WAN + LAN1–3 (10G / 2.5G / 1G as described in the DTS) |
| Wi‑Fi | Tri-band ath12k (QCN9274 family) + board BDF; only 2.4 GHz AP enabled by default |
| Management IP | Default LAN **`192.168.255.1/24`** (fork-wide `base-files` default) |
| Regulatory domain | Default **`US`** (change if you are not in the United States) |
| Web UI | Daily seed includes LuCI HTTPS and Simplified Chinese |
| Diagnostics | `sbe1v1k-diag` collects board / partitions / wireless / dmesg |

Extras beyond the upstream device PR (selected):

- Hotplug `20-askey-sbe1v1k-wifi` when the ath12k phy appears late
- Multi-radio identity via `hwmac` and hostapd in-process phy setup queue (to AP steady state; flash hostapd/wpad together with wifi-scripts)
- Board scripts for sysupgrade, caldata, and envtools

The default image does **not** include experimental QSDK ECM/NSS acceleration.

## Build

Use a case-sensitive Linux filesystem (native Linux or WSL2). In the full local
workspace, an Arch build host may run compile-only jobs; do not develop on that
host.

```bash
git clone -b dev-sbe1v1k https://github.com/awsl1414/openwrt.git
cd openwrt

./scripts/feeds update -a
./scripts/feeds install -a

# Daily image: LuCI + zh-CN + common tools
cp scripts/sbe1v1k/daily.config .config
# Slim bring-up: scripts/sbe1v1k/minimal.config

make defconfig
make download -j"$(nproc)"
make -j"$(nproc)" world
```

Images land in:

```text
bin/targets/qualcommbe/ipq95xx/
```

| Image | Use |
|---|---|
| `*-initramfs-uImage.itb` | RAM boot, first test, or rescue (no persistent rootfs) |
| `*-squashfs-sysupgrade.bin` | Install/upgrade when already running this OpenWrt or a chainloader |
| `*-squashfs-factory.bin` | Raw squashfs rootfs; **do not** upload via LuCI or flash as kernel |

Arch one-shot helper (workspace docs): `scripts/sbe1v1k/build-arch.sh`.

## First login

1. Connect a PC to LAN with DHCP, or static `192.168.255.2/24` (gateway optional).
2. Open `http://192.168.255.1` or `ssh root@192.168.255.1`.
3. A clean install has **no root password** and conservative Wi‑Fi defaults
   (2.4 GHz AP only, open).
4. Set a password and encrypted Wi‑Fi immediately. Public images never embed
   private credentials.
5. Outside the US, set a lawful local country code.

## Flashing warning

1. Back up eMMC `boot0`, `boot1`, GPT, and critical partitions first.
2. Identify factory A/B, mainline, or third-party large layouts — never mix
   procedures.
3. HTTP-chainloader users should normally upload the **sysupgrade** image at
   `http://192.168.255.1/`.
4. Keep power and Ethernet stable during every write.
5. Optional HTTP chainloader (not the upstream install path):
   [YYH2913/http-uboot](https://github.com/YYH2913/http-uboot) `sbe1v1k` branch.

## Known limitations

- Not official OpenWrt stable device support.
- No stable NSS hardware routing offload in the default image.
- More cold-boot, fan-control, and long-duration throughput testing is needed.
- Default `US` is only appropriate for hardware operated in the United States.

## Upstream and references

- Device PR: [#21586](https://github.com/openwrt/openwrt/pull/21586)
- Multi-radio / MAC: [#24639](https://github.com/openwrt/openwrt/pull/24639),
  [#23786](https://github.com/openwrt/openwrt/pull/23786)
- Reference trees: [luckkyboy/SBE1V1K](https://github.com/luckkyboy/SBE1V1K),
  [yintaomu/SBE1V1K-OpenWrt](https://github.com/yintaomu/SBE1V1K-OpenWrt)

Generic upstream OpenWrt notes: [README-OpenWrt.md](README-OpenWrt.md).

## License

OpenWrt is licensed under GPL-2.0. Individual files retain their upstream
licenses and copyright notices.
