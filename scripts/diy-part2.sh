#!/bin/bash
# ============================================================
# DIY Part 2 - Executed AFTER feeds install, BEFORE make
# This script runs in the openwrt source directory
# ============================================================

set -e

echo "============================================"
echo " DIY Part 2: Post-feeds customization"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 0. Patch out WiFi from target defaults and device definition
echo "[0/4] Patching out WiFi packages..."
IPQ60XX_MK="target/linux/qualcommax/image/ipq60xx.mk"
TARGET_MAKEFILE="target/linux/qualcommax/Makefile"

if [ -f "$IPQ60XX_MK" ]; then
    # Change zn_m2 DEVICE_PACKAGES to explicitly disable WiFi
    sed -i '/define Device\/zn_m2/,/^endef/s/DEVICE_PACKAGES := ipq-wifi-zn_m2/DEVICE_PACKAGES := -kmod-ath -kmod-ath11k -kmod-ath11k-ahb -kmod-ath11k-pci -ath11k-firmware-ipq6018 -ipq-wifi-zn_m2 -wpad-openssl/' "$IPQ60XX_MK"
    echo "  -> Patched zn_m2 device: WiFi packages disabled"
else
    echo "  -> WARNING: $IPQ60XX_MK not found!"
fi

if [ -f "$TARGET_MAKEFILE" ]; then
    # Remove WiFi from DEFAULT_PACKAGES
    sed -i '/^DEFAULT_PACKAGES/s/kmod-ath11k kmod-ath11k-ahb kmod-ath11k-pci//g' "$TARGET_MAKEFILE"
    sed -i '/^DEFAULT_PACKAGES/s/wpad-openssl//g' "$TARGET_MAKEFILE"
    echo "  -> Patched target Makefile: WiFi removed from DEFAULT_PACKAGES"
else
    echo "  -> WARNING: $TARGET_MAKEFILE not found!"
fi

# 1. Clone and install rtp2httpd as a package
echo "[1/4] Adding rtp2httpd package..."
if [ ! -d "package/rtp2httpd" ]; then
    git clone --depth 1 https://github.com/stackia/rtp2httpd.git /tmp/rtp2httpd 2>/dev/null || {
        echo "  -> Failed to clone from github.com, trying mirror..."
        git clone --depth 1 https://gitcode.com/stackia/rtp2httpd.git /tmp/rtp2httpd 2>/dev/null || {
            echo "  -> WARNING: Could not clone rtp2httpd. Will try lance65 fork."
            git clone --depth 1 https://github.com/lance65/rtp2httpd.git /tmp/rtp2httpd
        }
    }

    if [ -d "/tmp/rtp2httpd/openwrt-support" ]; then
        cp -r /tmp/rtp2httpd/openwrt-support/rtp2httpd package/rtp2httpd 2>/dev/null || true
        cp -r /tmp/rtp2httpd/openwrt-support/luci-app-rtp2httpd package/luci-app-rtp2httpd 2>/dev/null || true
        if [ -d "/tmp/rtp2httpd/openwrt-support/rtp2httpd/files" ]; then
            cp -r /tmp/rtp2httpd/openwrt-support/rtp2httpd/files/* package/rtp2httpd/files/ 2>/dev/null || true
        fi
        echo "  -> rtp2httpd package added"
    else
        echo "  -> ERROR: openwrt-support not found in rtp2httpd repo"
    fi
    rm -rf /tmp/rtp2httpd
else
    echo "  -> rtp2httpd package already exists"
fi

# 2. Verify PPPoE support
echo "[2/4] Verifying PPPoE packages..."
for pkg in ppp ppp-mod-pppoe kmod-pppoe; do
    found=$(find feeds/packages/ -name "$pkg" -type d 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "  -> [OK] $pkg available"
    else
        echo "  -> [WARN] $pkg not found in feeds"
    fi
done

# 3. Verify key packages exist
echo "[3/4] Verifying key packages..."
for pkg in luci-app-passwall rtp2httpd luci-app-rtp2httpd; do
    found=$(find package/ feeds/ -path "*/$pkg/Makefile" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "  -> [OK] $pkg found at: $found"
    else
        echo "  -> [WARN] $pkg NOT found! Check feeds configuration."
    fi
done

# 4. Final verification
echo "[4/4] Final verification..."
echo "  -> ZN-M2 device definition:"
grep -A5 "define Device/zn_m2" target/linux/qualcommax/image/ipq60xx.mk 2>/dev/null || echo "  -> WARNING: zn_m2 not found!"
echo ""
echo "  -> Kernel version:"
grep "KERNEL_PATCHVER" target/linux/qualcommax/Makefile 2>/dev/null || true

echo ""
echo "============================================"
echo " Build Summary"
echo "============================================"
echo " Target: qualcommax/ipq60xx/zn_m2"
echo " Source: VIKINGYFY/immortalwrt"
echo " WiFi:   DISABLED (patched out)"
echo " IPTV:   Dual-line PPPoE + policy routing"
echo " Features: PASSWALL + rtp2httpd"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
