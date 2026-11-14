#
# LuCI Web Interface for SoftEther VPN Client
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-softether-client
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=OpenWrt SoftEther Maintainers

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-softether-client
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for SoftEther VPN Client
  DEPENDS:=+softether-client
  PKGARCH:=all
endef

define Package/luci-app-softether-client/description
  LuCI Web Management interface for SoftEther VPN Client on OpenWrt.
  Compatible with both modern JavaScript (OpenWrt 21.02+) and classic Lua CBI (OpenWrt 18.06/19.07).
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-softether-client/install
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/* $(1)/usr/share/luci/menu.d/ 2>/dev/null || true

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/* $(1)/usr/share/rpcd/acl.d/ 2>/dev/null || true

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/softether-client
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/softether-client/* $(1)/www/luci-static/resources/view/softether-client/ 2>/dev/null || true

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/* $(1)/usr/lib/lua/luci/controller/ 2>/dev/null || true

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/softether_client
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/model/cbi/softether_client/* $(1)/usr/lib/lua/luci/model/cbi/softether_client/ 2>/dev/null || true

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/* $(1)/etc/uci-defaults/ 2>/dev/null || true
endef

define Package/luci-app-softether-client/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/luci-app-softether-client ) && rm -f /etc/uci-defaults/luci-app-softether-client
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-softether-client))
