# iStoreOS 25.12 + Motorcomm YT6801 网卡驱动

给 **领效 M120（N100 单网口小主机，网卡为 Motorcomm YT6801）** 用的 iStoreOS 固件构建仓库。

## 为什么需要这个仓库

- YT6801 是国产裕太微的 PCIe 千兆网卡（基于 DWMAC4 IP），Linux 驱动 2025 年才进内核主线（6.14）。
- iStoreOS 24.10 基于 6.6 内核 → **完全没有**该驱动，网卡不识别、网口灯不亮。
- iStoreOS 25.12 基于 6.12 内核 → 只有 PHY 驱动，**缺 PCIe 胶水层**，同样不识别。
- OpenWrt 官方在 2026-04 通过 PR [#22923](https://github.com/openwrt/openwrt/pull/22923) 把驱动反向移植到 6.12/6.18，但**没有**打进 x86 默认镜像。

所以本仓库做的事：把官方补丁打进 iStoreOS 25.12 源码，并强制把 `kmod-dwmac-motorcomm` 加入 x86/64 默认包，编译出刷机即识别的完整固件。

## 目录结构

```
.
├── .github/workflows/build.yml      # GitHub Actions 云端构建
├── scripts/apply-patches.sh         # 打补丁脚本（幂等）
├── patches/kernel/705-01-*.patch    # YT8531S PHY 支持（来自 PR 22923）
└── patches/kernel/705-02-*.patch    # YT6801 DWMAC 胶水驱动（来自 PR 22923）
```

`apply-patches.sh` 会做四件事：

1. 把两枚内核补丁放进 `target/linux/generic/backport-6.12/`
2. 校正 `755` hack 补丁的内层行号（因为 705-01 在前面插入了 4 行）
3. 在 `netdevices.mk` 里新增 `kmod-dwmac-motorcomm`，并给 `stmmac-core` 补上 `kmod-phylink` / `kmod-mdio-devres` 依赖
4. 把 `kmod-dwmac-motorcomm` 加进 `target/linux/x86/image/64.mk` 的 `DEVICE_PACKAGES`

## 使用方法

### 1. 在 GitHub 建一个空仓库

打开 https://github.com/new ，仓库名随意（例：`istoreos-yt6801`），**不要**勾选 README / .gitignore。

### 2. 推送本目录

```bash
cd yt6801-build
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git branch -M main
git push -u origin main
```

### 3. 等构建

推送后自动触发（也可以到 Actions 页面点 `Run workflow`）。构建约 **2~4 小时**，完成后在 Actions → 对应运行记录 → Artifacts 下载 `istoreos-25.12-yt6801`。

产物里最关键的是 `istoreos-25.12.x-x86-64-squashfs-combined-efi.img.gz`。

### 4. 刷机

1. 解压得到 `.img`，用 **balenaEtcher** 或 Rufus（DD 模式）写入 U 盘
2. 插到 M120 上，BIOS 里关掉 Secure Boot，启动项选带 `UEFI:` 的 U 盘
3. 首次启动会自动把系统写入内置硬盘，完成后拔 U 盘重启

### 5. 验证网卡

控制台（root / password）执行：

```sh
lspci -nn | grep -i ethernet     # 应看到 Motorcomm YT6801
ip -br link                      # 应出现 eth0
dmesg | grep -i dwmac            # 应看到 dwmac-motorcomm 接管
ethtool eth0 | grep -E "Speed|Link"   # 插网线后应显示 1000Mb/s + yes
```

## 说明与限制

- **构建时长**：GitHub 免费账户的公开仓库 Actions 额度不限，私有仓库每月 2000 分钟；单次构建预计消耗 120~240 分钟。
- **产物保留**：14 天，请及时下载。
- **构建失败**：Actions 会自动上传 `build-log-failure` 附件，把最后 100 行日志发出来即可定位。
- **无线网卡**：Realtek 8852BE 在 6.12 内核有现成驱动，联网后 `apk add kmod-rtw89-8852be` 即可（可选）。
- **本仓库不含 iStoreOS 源码**，CI 会实时 clone `istoreos-25.12` 分支，始终跟随上游最新代码。

## 本机编译（可选）

任何 x86_64 Linux（Debian/Ubuntu）都可：

```bash
sudo apt install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev python3 python3-setuptools rsync unzip \
  zlib1g-dev file wget cpio swig time subversion mercurial
git clone --depth 1 -b istoreos-25.12 https://github.com/istoreos/istoreos.git openwrt
./scripts/apply-patches.sh openwrt
cd openwrt && ./scripts/feeds update -a && ./scripts/feeds install -a
cp ../seed.config .config && make defconfig
make -j$(nproc) download && make -j$(nproc)
```
