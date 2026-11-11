#
# v6watch - IPv6 出口自愈与诊断
#
# 在 OpenWrt / ImmortalWrt SDK 里编译：
#   echo "src-git v6watch https://github.com/Jonnyan404/openwrt-v6watch.git" >> feeds.conf.default
#   ./scripts/feeds update v6watch && ./scripts/feeds install v6watch
#   make menuconfig   # Network -> v6watch
#   make package/v6watch/compile V=s
#
# 25.x（apk）与 24.10 及更早（opkg）共用这份 Makefile，
# 产物格式由 SDK 自身的版本决定。

include $(TOPDIR)/rules.mk

PKG_NAME:=v6watch
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Jonnyan404 <jonnyan404@users.noreply.github.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_PARALLEL:=1
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

# PKGARCH:=all 在 25.x 必须写进 Package 块内部：Package/Default 会用
# PKGARCH:=$(ARCH_PACKAGES) 覆盖掉顶部的设置，否则 apk 里会记成 arch:x86_64，
# 装到 aarch64 路由器上报架构不匹配。写成 all 后 apk 记为 noarch。
define Package/v6watch
  SECTION:=net
  CATEGORY:=Network
  TITLE:=IPv6 egress watchdog with layered diagnosis
  URL:=https://github.com/Jonnyan404/openwrt-v6watch
  DEPENDS:=+ubus +jsonfilter
  PKGARCH:=all
endef

define Package/v6watch/description
  Monitors IPv6 egress and, unlike a plain "ping failed, restart the
  interface" watchdog, first locates the fault:

    link_down        upstream gateway unreachable  -> do nothing
    egress_down      upstream ok, egress dead      -> report only
    delegation_lost  delegated prefix unusable     -> re-run DHCPv6

  The last one is the common real-world case: the router keeps valid
  addresses, prefixes, routes and lifetimes, yet the upstream silently
  drops traffic sourced from the delegated IA_NA / PD addresses.
  A plain connectivity watchdog will hammer the interface forever in
  the second case; v6watch waits instead.
endef

define Package/v6watch/conffiles
/etc/config/v6watch
endef

define Build/Compile
endef

define Package/v6watch/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/v6watch $(1)/usr/bin/v6watch
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/v6watch $(1)/etc/init.d/v6watch
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/v6watch $(1)/etc/config/v6watch
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/90-v6watch $(1)/etc/uci-defaults/90-v6watch
endef

$(eval $(call BuildPackage,v6watch))
