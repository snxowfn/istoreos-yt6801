#!/usr/bin/env bash
# 把 Motorcomm YT6801 驱动补丁打进 iStoreOS 25.12 源码树（幂等，可重复执行）
set -euo pipefail

SRC="${1:-openwrt}"
cd "$SRC"

echo "== 1. 复制内核补丁到 backport-6.12 =="
cp -f ../patches/kernel/705-01-*.patch ../patches/kernel/705-02-*.patch \
      target/linux/generic/backport-6.12/
ls -1 target/linux/generic/backport-6.12/705-0*.patch

echo "== 2. 校正 755 hack 补丁的内层行号（705-01 在前面插入了 4 行）=="
sed -i 's|@@ -2659,6 +2662,23 @@|@@ -2663,6 +2666,23 @@|' \
  target/linux/generic/hack-6.12/755-net-phy-motorcomm-yt8821-bus-collision-workaround.patch || true

echo "== 3. 新增 kmod-dwmac-motorcomm 并补齐 stmmac-core 依赖 =="
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

echo "== 4. 把驱动加进 x86/64 默认镜像包列表 =="
sed -i 's|kmod-dwmac-intel|kmod-dwmac-intel kmod-dwmac-motorcomm|' target/linux/x86/image/64.mk
grep -n 'DEVICE_PACKAGES' -A 4 target/linux/x86/image/64.mk

echo "== 5. 校验 =="
test -f target/linux/generic/backport-6.12/705-02-v7.0-net-stmmac-Add-glue-driver-for-Motorcomm-YT6801-ethernet.patch
grep -q 'KernelPackage/dwmac-motorcomm' package/kernel/linux/modules/netdevices.mk
grep -q 'kmod-dwmac-motorcomm' target/linux/x86/image/64.mk
echo "补丁应用完成，校验通过"
