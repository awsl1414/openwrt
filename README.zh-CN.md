# SBE1V1K OpenWrt 中文说明

[English](README.en.md) | [项目首页](README.md)

## 项目定位

本仓库是 [awsl1414/openwrt](https://github.com/awsl1414/openwrt) 的 **`dev-sbe1v1k`**
分支：在 OpenWrt `qualcommbe/ipq95xx` 上移植 Spectrum/Askey **SBE1V1K**
（别名 **RTQ7300T**）。

设备支持尚未进入 OpenWrt 官方稳定版，适合能使用串口、initramfs 或 HTTP
chainloader 等恢复手段的高级用户。

## 当前能力

| 项目 | 说明 |
|---|---|
| SoC / 存储 | IPQ9570（DTS compatible `qcom,ipq9574`），约 2 GB RAM / 8 GB eMMC |
| 有线 | WAN + LAN1–3（含 10G / 2.5G / 1G 口定义，见 DTS） |
| 无线 | 三频 ath12k（QCN9274 系列）+ 板级 BDF；默认仅启用 2.4 GHz AP |
| 管理地址 | 默认 LAN **`192.168.255.1/24`**（本 fork `base-files` 全局默认） |
| 监管域 | 默认 **`US`**（非美国环境请改为当地合法国家码） |
| Web / 语言 | 日用种子含 LuCI HTTPS、简体中文；首次可自动设 `luci.main.lang=zh_cn` |
| 诊断 | `sbe1v1k-diag` 收集 board / 分区 / 无线 / dmesg |

本树相对上游设备 PR 额外包含（节选）：

- ath12k phy 晚到后的 `20-askey-sbe1v1k-wifi` hotplug
- 多 radio：`hwmac` 身份 + hostapd 同 phy 串行（`phy-setup-lock`）
- sysupgrade / caldata / envtools 等板级脚本

**不包含**默认路径下的实验性 QSDK ECM/NSS 硬件加速。

## 编译

推荐 Linux（含 WSL2）或本工作区约定的 Arch 构建机。需要大小写敏感文件系统。

```bash
git clone -b dev-sbe1v1k https://github.com/awsl1414/openwrt.git
cd openwrt

./scripts/feeds update -a
./scripts/feeds install -a

# 日用：LuCI + 中文 + 常用工具
cp scripts/sbe1v1k/daily.config .config
# 精简 bring-up：改用 scripts/sbe1v1k/minimal.config

make defconfig
make download -j"$(nproc)"
make -j"$(nproc)" world
```

产物目录：

```text
bin/targets/qualcommbe/ipq95xx/
```

常用文件名模式：

| 镜像 | 用途 |
|---|---|
| `*-initramfs-uImage.itb` | 内存启动、首次测试或救援（不持久写 rootfs） |
| `*-squashfs-sysupgrade.bin` | 已在跑本设备 OpenWrt / chainloader 时的安装与升级 |
| `*-squashfs-factory.bin` | 裸 squashfs rootfs；**不要**用 LuCI 上传，也勿当内核刷 |

本工作区若使用 Arch 远程机：只在其上 `pull` + 编译，**禁止**在 Arch 上改源码。
一键脚本见 `scripts/sbe1v1k/build-arch.sh`（完整说明在工作区 `docs/build-arch.md`）。

## 首次登录

1. PC 接 LAN，DHCP，或静态 `192.168.255.2/24`（可不填网关）。
2. 浏览器打开 `http://192.168.255.1`，或 `ssh root@192.168.255.1`。
3. 全新系统 **root 无密码**、无线默认偏保守（仅 2.4 GHz 有默认 AP、无加密）。
4. 立即设置 root 密码，并配置加密 Wi‑Fi；公开固件**不会**硬编码私人凭据。
5. 非美国部署：在无线设置里改国家码为当地合法监管域。

## 刷机警告

1. 先备份 eMMC `boot0`、`boot1`、GPT 与关键分区。
2. 分清原厂 A/B、mainline 与第三方 large 布局，**勿**混用流程。
3. HTTP chainloader 用户通常从 `http://192.168.255.1/` 的 Firmware 页上传
   **sysupgrade** 镜像。
4. 写入期间保持供电与网线稳定，禁止断电。
5. 可选 HTTP chainloader（非上游安装路径）见
   [YYH2913/http-uboot](https://github.com/YYH2913/http-uboot) 的 `sbe1v1k` 分支。

## 已知限制

- 仍非 OpenWrt 官方稳定支持。
- 无稳定的 NSS 硬件路由加速（默认镜像）。
- 三频冷启动、风扇温控与长时间吞吐仍需更多实机验证。
- 默认 `US` 仅适用于实际位于美国的设备。

## 上游与参考

- 设备 PR：[#21586](https://github.com/openwrt/openwrt/pull/21586)
- 多 radio / MAC 相关：[#24639](https://github.com/openwrt/openwrt/pull/24639)、
  [#23786](https://github.com/openwrt/openwrt/pull/23786)
- 对照树：[luckkyboy/SBE1V1K](https://github.com/luckkyboy/SBE1V1K)、
  [yintaomu/SBE1V1K-OpenWrt](https://github.com/yintaomu/SBE1V1K-OpenWrt)

上游通用说明见 [README-OpenWrt.md](README-OpenWrt.md)。

## 许可证

OpenWrt 为 GPL-2.0。各文件继续保留其原有许可证与版权声明。
