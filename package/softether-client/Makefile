#
# SoftEther VPN Client package for OpenWrt
# Supports ARM (32/64-bit) and X86/x64 architectures
#

include $(TOPDIR)/rules.mk

PKG_NAME:=softether-client
PKG_REALVERSION:=4.38-9760
PKG_VERSION:=$(word 1,$(subst -, ,$(PKG_REALVERSION)))
PKG_VERREL:=rtm
PKG_RELEASE:=2

PKG_SOURCE:=softether-src-v$(PKG_REALVERSION)-$(PKG_VERREL).tar.gz
PKG_SOURCE_URL:=https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/v$(PKG_REALVERSION)-$(PKG_VERREL)
PKG_HASH:=e68128b46171bd9f3f9ca38d10e60e8590a833bfc6488fa014674f9a22541f35

PKG_MAINTAINER:=OpenWrt SoftEther Maintainers
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)/v$(PKG_REALVERSION)
PKG_ASLR_PIE:=0

include $(INCLUDE_DIR)/package.mk

define Package/softether-client
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=SoftEther VPN Client for OpenWrt
  URL:=https://www.softether.org/
  DEPENDS:=+libpthread +librt +libreadline +libopenssl +libncurses +kmod-tun +zlib +ip-full +ca-certificates
  PROVIDES:=luci-app-softether-client
endef

define Package/softether-client/description
  SoftEther VPN is a powerful, flexible and ultra-fast cross-platform VPN software.
  This package provides the vpnclient background daemon, vpncmd management CLI utility,
  procd service scripts, automatic UCI account synchronization, routing manager,
  and connection watchdog.
endef

define Package/softether-client/conffiles
/etc/config/softether_client
endef

# Tune CFLAGS for target architecture and musl libc
TARGET_CFLAGS += \
	$(if $(CONFIG_OPENSSL_WITH_SSL3),,-DSSL_OP_NO_SSLv3) \
	$(if $(filter mips mipsel,$(ARCH)),-minterlink-mips16) \
	-DUNIX -DOS_UNIX -DUNIX_LINUX -DUNIX_LINUX_MUSL -fsigned-char

# Select 32-bit or 64-bit Makefile depending on target architecture
MAKE_FLAGS += \
	-f src/makefiles/linux_$(if $(CONFIG_ARCH_64BIT),64,32)bit.mak \
	CC="$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) $(TARGET_LDFLAGS)"

define Build/Configure
	# Provide prebuilt hamcore.se2 to avoid host compilation of hamcorebuilder
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/src/bin/BuiltHamcoreFiles/unix
	if [ -f files/hamcore.se2 ]; then \
		$(CP) files/hamcore.se2 $(PKG_BUILD_DIR)/src/bin/BuiltHamcoreFiles/unix/hamcore.se2; \
	fi
	# Set modtime to future to prevent make from attempting to rebuild hamcore.se2
	touch -d "+1 day" $(PKG_BUILD_DIR)/src/bin/BuiltHamcoreFiles/unix/hamcore.se2 2>/dev/null || true
endef

define Package/softether-client/install
	$(INSTALL_DIR) $(1)/usr/libexec/softether
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/vpnclient/vpnclient $(1)/usr/libexec/softether/vpnclient
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/vpncmd/vpncmd $(1)/usr/libexec/softether/vpncmd
	$(INSTALL_DATA) files/hamcore.se2 $(1)/usr/libexec/softether/hamcore.se2 2>/dev/null || \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/bin/vpnclient/hamcore.se2 $(1)/usr/libexec/softether/hamcore.se2

	# Helper and handler scripts
	$(INSTALL_BIN) files/launcher.sh $(1)/usr/libexec/softether/launcher.sh
	$(INSTALL_BIN) files/softether-helper.sh $(1)/usr/libexec/softether/softether-helper.sh
	$(INSTALL_BIN) files/softether-watchdog.sh $(1)/usr/libexec/softether/softether-watchdog.sh
	$(INSTALL_BIN) files/udhcpc.sh $(1)/usr/libexec/softether/udhcpc.sh
	$(INSTALL_DATA) files/chnroute.txt $(1)/usr/libexec/softether/chnroute.txt

	# CLI command symlinks
	$(INSTALL_DIR) $(1)/usr/bin
	$(LN) /usr/libexec/softether/launcher.sh $(1)/usr/bin/vpncmd
	$(LN) /usr/libexec/softether/launcher.sh $(1)/usr/bin/vpnclient

	# UCI configuration
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) files/softether-client.config $(1)/etc/config/softether_client

	# UCI defaults (firewall zone auto-creation)
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) files/99-softether-firewall $(1)/etc/uci-defaults/99-softether-firewall

	# Procd init script
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) files/softether-client.init $(1)/etc/init.d/softether-client

	# Integrated LuCI Web Management interface
	if [ -d ../luci-app-softether-client/root ]; then \
		$(CP) ../luci-app-softether-client/root/* $(1)/; \
	fi
endef

define Package/softether-client/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	[ -f /etc/uci-defaults/99-softether-firewall ] && {
		sh /etc/uci-defaults/99-softether-firewall
		rm -f /etc/uci-defaults/99-softether-firewall
	}
	[ -f /etc/uci-defaults/luci-app-softether-client ] && {
		sh /etc/uci-defaults/luci-app-softether-client
		rm -f /etc/uci-defaults/luci-app-softether-client
	}
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache* 2>/dev/null || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	/etc/init.d/softether-client enable >/dev/null 2>&1 || true
	exit 0
}
endef

define Package/softether-client/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/softether-client stop >/dev/null 2>&1 || true
	killall -9 vpnclient udhcpc 2>/dev/null || true
	/etc/init.d/softether-client disable >/dev/null 2>&1 || true
	exit 0
}
endef

define Package/softether-client/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -rf /var/run/softether /tmp/softether 2>/dev/null || true
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache* 2>/dev/null || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	exit 0
}
endef

$(eval $(call BuildPackage,softether-client))


