# SoftEther VPN Client (Ver 4.44, Build 9807, Intel x64 / AMD64) for Mac OS X
# Makefile
# 
# Copyright (c) SoftEther VPN Project at University of Tsukuba, Japan. All Rights Reserved.
# Platform: macos-arm64 (Apple Silicon M-Series) & ios-arm64 (iPhone 18)

CC=gcc

OPTIONS=-arch arm64 -fPIE -O2 -fsigned-char -lm -lpcap -lpthread -liconv -lz -L./lib lib/libssl.a lib/libcrypto.a lib/libedit.a lib/libncurses.a

default:
	@./.install.sh

core:
	@chmod +x compile_softether_core_arm64.sh
	@./compile_softether_core_arm64.sh

# NOTE:
# You have to read and agree the license agreement at the same directory
#  before using this software.

main:
	@echo "Preparing SoftEther VPN Client for Apple Silicon (arm64)..."
	@test -f lib/libcrypto.a && ranlib lib/libcrypto.a 2>/dev/null || true
	@test -f lib/libssl.a && ranlib lib/libssl.a 2>/dev/null || true
	@test -f code/vpnclient.a || { echo "[Error] code/vpnclient.a not found"; exit 1; }
	-ranlib code/vpnclient.a 2>/dev/null || true
	$(CC) code/vpnclient.a $(OPTIONS) -o vpnclient
	@test -f code/vpncmd.a || { echo "[Error] code/vpncmd.a not found"; exit 1; }
	-ranlib code/vpncmd.a 2>/dev/null || true
	$(CC) code/vpncmd.a $(OPTIONS) -o vpncmd
	@echo
	@echo "--------------------------------------------------------------------"
	@echo "The preparation of SoftEther VPN Client is completed !"
	@echo "--------------------------------------------------------------------"
	@echo

ui:
	@chmod +x build_ui.sh
	@./build_ui.sh

ios:
	@chmod +x build_ios_ipa.sh
	@./build_ios_ipa.sh

clean:
	rm -f vpnclient
	rm -f vpncmd
	rm -rf SoftEtherUI.app
	rm -rf build_ios SoftEtherUI-iOS.ipa SoftEtherUI-iOS-Lite.ipa
