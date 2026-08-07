#!/bin/bash
# ============================================================
# DIY Part 2 - Executed AFTER feeds install, BEFORE make
# Adds ZN-M2 device support to ImmortalWrt v25.12.1
# ============================================================

set -e

echo "============================================"
echo " DIY Part 2: Adding ZN-M2 device support"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Add ZN-M2 device definition to ipq60xx.mk
echo "[1/5] Adding ZN-M2 device definition to ipq60xx.mk..."
IPQ60XX_MK="target/linux/qualcommax/image/ipq60xx.mk"

if [ -f "$IPQ60XX_MK" ]; then
    # Check if zn_m2 already exists
    if grep -q "define Device/zn_m2" "$IPQ60XX_MK"; then
        echo "  -> zn_m2 already defined, skipping"
    else
        # Append zn_m2 device definition before the last line
        cat >> "$IPQ60XX_MK" << 'DEVICE_DEF'

define Device/zn_m2
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := ZN
	DEVICE_MODEL := M2
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	SOC := ipq6000
	DEVICE_DTS_CONFIG := config@cp03-c1
endef
TARGET_DEVICES += zn_m2
DEVICE_DEF
        echo "  -> zn_m2 device definition added"
    fi
else
    echo "  -> ERROR: $IPQ60XX_MK not found!"
    exit 1
fi

# 2. Copy ZN-M2 DTS file to target directory
echo "[2/5] Installing ZN-M2 DTS file..."
DTS_DIR="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
DTS_FILE="$DTS_DIR/ipq6000-m2.dts"

if [ -f "$SCRIPT_DIR/patches/ipq6000-m2.dts" ]; then
    mkdir -p "$DTS_DIR"
    cp "$SCRIPT_DIR/patches/ipq6000-m2.dts" "$DTS_FILE"
    echo "  -> DTS file installed: $DTS_FILE"
else
    echo "  -> ERROR: patches/ipq6000-m2.dts not found!"
    exit 1
fi

# 3. Remove WiFi from DEFAULT_PACKAGES (user doesn't need WiFi)
echo "[3/5] Removing WiFi from DEFAULT_PACKAGES..."
TARGET_MAKEFILE="target/linux/qualcommax/Makefile"

if [ -f "$TARGET_MAKEFILE" ]; then
    # v25.12.1 has: kmod-ath11k-ahb wpad-openssl in DEFAULT_PACKAGES
    sed -i '/^DEFAULT_PACKAGES/s/kmod-ath11k-ahb //g' "$TARGET_MAKEFILE"
    sed -i '/^DEFAULT_PACKAGES/s/wpad-openssl //g' "$TARGET_MAKEFILE"
    echo "  -> WiFi packages removed from DEFAULT_PACKAGES"
    echo "  -> Updated DEFAULT_PACKAGES:"
    grep "DEFAULT_PACKAGES" "$TARGET_MAKEFILE" | head -3
else
    echo "  -> WARNING: $TARGET_MAKEFILE not found!"
fi

# 4. Clone and install rtp2httpd as a package
echo "[4/5] Adding rtp2httpd package..."
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

# 5. Verify everything is in place
echo "[5/5] Final verification..."
echo ""
echo "  -> ZN-M2 device definition:"
grep -A8 "define Device/zn_m2" "$IPQ60XX_MK" 2>/dev/null || echo "  -> ERROR: zn_m2 not found!"
echo ""
echo "  -> DTS file exists:"
ls -la "$DTS_FILE" 2>/dev/null || echo "  -> ERROR: DTS file not found!"
echo ""
echo "  -> Kernel version:"
grep "KERNEL_PATCHVER" "$TARGET_MAKEFILE" 2>/dev/null || true
echo ""
echo "  -> Key packages:"
for pkg in luci-app-passwall rtp2httpd luci-app-rtp2httpd; do
    found=$(find package/ feeds/ -path "*/$pkg/Makefile" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "    [OK] $pkg"
    else
        echo "    [WARN] $pkg NOT found!"
    fi
done

echo ""
echo "============================================"
echo " Build Summary"
echo "============================================"
echo " Source:  ImmortalWrt v25.12.1 (STABLE)"
echo " Kernel:  6.12"
echo " Target:  qualcommax/ipq60xx/zn_m2"
echo " WiFi:    DISABLED"
echo " IPTV:    Dual-line PPPoE + policy routing"
echo " Features: PASSWALL (Xray+sing-box) + rtp2httpd"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
