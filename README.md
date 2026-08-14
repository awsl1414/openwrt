# Askey / Spectrum SBE1V1K OpenWrt

[简体中文](README.zh-CN.md) | [English](README.en.md)

Experimental OpenWrt tree for the Spectrum/Askey **SBE1V1K** (also known as
**RTQ7300T**), based on `qualcommbe/ipq95xx`. Branch: **`dev-sbe1v1k`**.

面向 Spectrum/Askey **SBE1V1K**（别名 **RTQ7300T**）的实验性 OpenWrt 源码树
（`qualcommbe/ipq95xx`）。当前分支：**`dev-sbe1v1k`**。

## Highlights / 主要特性

- Device support: DTS, BDF, eMMC images, LAN/WAN, ath12k caldata, sysupgrade
- Tri-band Wi‑Fi: radio identity via `hwmac`, hostapd per-PHY serialize
- Late ath12k phy: hotplug brings Wi‑Fi up after PCI enumeration
- Default LAN: **`192.168.255.1/24`** (fork-wide `base-files` default; matches HTTP chainloader)
- Default regulatory domain: `US` (change if you are not in the US)
- Daily seed: LuCI HTTPS + Simplified Chinese + diagnostics (`sbe1v1k-diag`)
- 设备支持：DTS、BDF、eMMC 镜像、LAN/WAN、ath12k caldata、sysupgrade
- 三频：`hwmac` 识别 radio；同 phy 上 hostapd 串行启动
- ath12k phy 晚到时由 hotplug 拉起无线
- 默认 LAN：**`192.168.255.1/24`**（本 fork `base-files` 全局默认；与 HTTP chainloader 一致）
- 默认监管域：`US`（非美国部署请改为当地合法国家码）
- 日用配置：LuCI HTTPS、简体中文、`sbe1v1k-diag` 等

## Quick start / 快速开始

```bash
git clone -b dev-sbe1v1k https://github.com/awsl1414/openwrt.git
cd openwrt
./scripts/feeds update -a
./scripts/feeds install -a
cp scripts/sbe1v1k/daily.config .config   # or minimal.config
make defconfig
make -j"$(nproc)" world
```

Images: `bin/targets/qualcommbe/ipq95xx/*askey_sbe1v1k*`

After first boot / factory reset: LuCI / SSH at **`http://192.168.255.1`**.  
首次启动或恢复出厂后：访问 **`http://192.168.255.1`**。

## Documentation / 文档

| Doc | Description |
|---|---|
| [README.zh-CN.md](README.zh-CN.md) | 中文项目说明（推荐） |
| [README.en.md](README.en.md) | English project guide |
| [README-OpenWrt.md](README-OpenWrt.md) | Upstream OpenWrt README |
| [scripts/sbe1v1k/](scripts/sbe1v1k/) | Build seeds, Arch helper, smoke tests |

Workspace-level porting notes (outside this git tree when cloning only `openwrt`):
see the parent `docs/` directory if you use the full local workspace.

## Status / 状态

Not official OpenWrt stable support. Keep a serial console and a verified
recovery path (initramfs / HTTP chainloader). No QSDK ECM/NSS fast path in the
default image; forwarding uses the mainline PPE Ethernet path.

**非** OpenWrt 官方稳定支持。务必保留串口与已验证恢复手段。默认镜像不含
实验性 QSDK ECM/NSS；转发走上游 PPE。

## Credits / 致谢

OpenWrt; Andrew LaMarche ([PR #21586](https://github.com/openwrt/openwrt/pull/21586));
[luckkyboy/SBE1V1K](https://github.com/luckkyboy/SBE1V1K);
[yintaomu/SBE1V1K-OpenWrt](https://github.com/yintaomu/SBE1V1K-OpenWrt);
optional HTTP chainloader: [YYH2913/http-uboot](https://github.com/YYH2913/http-uboot).

## License / 许可证

OpenWrt is GPL-2.0. Individual files retain their upstream licenses. /
OpenWrt 为 GPL-2.0；各文件保留原有许可证与版权声明。
