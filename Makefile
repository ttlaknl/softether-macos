#
# Makefile for OpenWrt SoftEther Client & LuCI Package
#

.PHONY: all help x86_64 arm64 arm32 clean

help:
	@echo "SoftEther OpenWrt IPK Builder"
	@echo "Usage:"
	@echo "  make x86_64     - Build IPK packages for X86_64"
	@echo "  make arm64      - Build IPK packages for ARM64 (aarch64)"
	@echo "  make arm32      - Build IPK packages for ARM32 (cortex-a7)"
	@echo "  make all        - Build IPK packages for all architectures"
	@echo "  make clean      - Clean build artifacts in bin/"

x86_64:
	@bash build.sh x86_64

arm64:
	@bash build.sh aarch64

arm32:
	@bash build.sh arm_cortex-a7

all:
	@bash build.sh all

clean:
	rm -rf bin/
