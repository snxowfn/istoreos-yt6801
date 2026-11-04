#!/usr/bin/env bash
# 把 Motorcomm YT6801 驱动补丁打进 iStoreOS 24.10 源码树（内核 6.6，opkg/ipk 体系）
# 幂等，可重复执行。
set -euo pipefail

SRC="${1:-openwrt}"
cd "$SRC"

echo "== 0. 环境确认 =="
grep -E '^LINUX_VERSION-6\.6' include/kernel-6.6 || true

echo "== 1. 复制内核补丁到 pending-6.6 =="
# 24.10 的内核是 6.6.144，补丁已按 6.6 校验（705-03 专门修 pcim_iomap_region，
# 该 API 6.9 才引入；6.6 只有 pcim_iomap_regions + pcim_iomap_table）。
mkdir -p target/linux/generic/pending-6.6
cp -f ../patches/kernel-6.6/705-01-*.patch \
      ../patches/kernel-6.6/705-02-*.patch \
      ../patches/kernel-6.6/705-03-*.patch \
      target/linux/generic/pending-6.6/
chmod 644 target/linux/generic/pending-6.6/705-0*.patch
ls -1 target/linux/generic/pending-6.6/705-0*.patch

echo "== 2. 新增 kmod-dwmac-motorcomm 并补齐 stmmac-core 依赖 =="
python3 - <<'PY'
p = 'package/kernel/linux/modules/netdevices.mk'
s = open(p, encoding='utf-8').read()

frag = '''
define KernelPackage/dwmac-motorcomm
  SUBMENU:=$(NETWORK_DEVICES_MENU)
  TITLE:=Motorcomm PCI DWMAC support
  DEPENDS:=@PCI_SUPPORT +kmod-phy-motorcomm +kmod-stmmac-core +kmod-phylink +kmod-mdio-devres
  KCONFIG:=CONFIG_DWMAC_MOTORCOMM
  FILES:=$(LINUX_DIR)/drivers/net/ethernet/stmicro/stmmac/dwmac-motorcomm.ko
  AUTOLOAD:=$(call AutoProbe,dwmac-motorcomm,1)
endef

define KernelPackage/dwmac-motorcomm/description
  Supports the Motorcomm DWMAC-based PCI Ethernet controllers (YT6801).
endef

$(eval $(call KernelPackage,dwmac-motorcomm))
'''

if 'dwmac-motorcomm' not in s:
    s = s.rstrip('\n') + '\n' + frag
    print('  + 已追加 kmod-dwmac-motorcomm 定义')
else:
    print('  = kmod-dwmac-motorcomm 已存在，跳过')

old = 'DEPENDS:=@TARGET_x86_64||TARGET_armsr +kmod-pcs-xpcs +kmod-ptp'
new = 'DEPENDS:=@TARGET_x86_64||TARGET_armsr +kmod-phylink +kmod-mdio-devres +kmod-pcs-xpcs +kmod-ptp'
if old in s and 'kmod-mdio-devres +kmod-pcs-xpcs' not in s:
    s = s.replace(old, new, 1)
    print('  + stmmac-core 依赖已补 kmod-phylink / kmod-mdio-devres')
else:
    print('  = stmmac-core 依赖无需修改')

open(p, 'w', encoding='utf-8').write(s)
PY

echo "== 3. 把驱动加进 x86/64 默认镜像包列表 =="
grep -q 'kmod-dwmac-motorcomm' target/linux/x86/image/64.mk || \
  sed -i 's|kmod-dwmac-intel|kmod-dwmac-intel kmod-dwmac-motorcomm|' target/linux/x86/image/64.mk
grep -n 'DEVICE_PACKAGES' -A 4 target/linux/x86/image/64.mk

echo "== 4. 校验 =="
for f in target/linux/generic/pending-6.6/705-01-*.patch \
         target/linux/generic/pending-6.6/705-02-*.patch \
         target/linux/generic/pending-6.6/705-03-*.patch; do
  test -f "$f" || { echo "::error::缺少补丁 $f"; exit 1; }
done
grep -q 'KernelPackage/dwmac-motorcomm' package/kernel/linux/modules/netdevices.mk
grep -q 'kmod-dwmac-motorcomm' target/linux/x86/image/64.mk
# 确认驱动源码里的 PCI BAR 映射已换成 6.6 可用的 API
grep -q 'pcim_iomap_regions' target/linux/generic/pending-6.6/705-03-*.patch
echo "补丁应用完成，校验通过"
