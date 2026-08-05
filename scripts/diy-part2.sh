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

    # Copy openwrt-support directory as package
    if [ -d "/tmp/rtp2httpd/openwrt-support" ]; then
        cp -r /tmp/rtp2httpd/openwrt-support/rtp2httpd package/rtp2httpd 2>/dev/null || true
        cp -r /tmp/rtp2httpd/openwrt-support/luci-app-rtp2httpd package/luci-app-rtp2httpd 2>/dev/null || true

        # Copy binary files if any
        if [ -d "/tmp/rtp2httpd/openwrt-support/rtp2httpd/files" ]; then
            cp -r /tmp/rtp2httpd/openwrt-support/rtp2httpd/files/* package/rtp2httpd/files/ 2>/dev/null || true
        fi

        echo "  -> rtp2httpd package added to package/"
        ls -la package/rtp2httpd/ 2>/dev/null || echo "  -> rtp2httpd package dir check"
    else
        echo "  -> ERROR: openwrt-support directory not found in rtp2httpd repo"
        echo "  -> Trying alternative: use Makefile from lance65 fork..."
    fi
    rm -rf /tmp/rtp2httpd
else
    echo "  -> rtp2httpd package already exists"
fi

# 2. Fix wireless board file name (known issue in some branches)
echo "[2/4] Checking wireless board files..."
WIFI_DIR="package/firmware/ath11k-wifi"
if [ -d "$WIFI_DIR" ]; then
    # Fix known filename issue: board-cmiot-ax18.bin.IPQ6018.bin -> board-cmiot-ax18.bin.IPQ6018
    if [ -f "$WIFI_DIR/board-cmiot-ax18.bin.IPQ6018.bin" ]; then
        mv "$WIFI_DIR/board-cmiot-ax18.bin.IPQ6018.bin" "$WIFI_DIR/board-cmiot-ax18.bin.IPQ6018"
        echo "  -> Fixed wireless board file name"
    fi
    echo "  -> Wireless board files:"
    ls "$WIFI_DIR/" 2>/dev/null | head -10
fi

# 3. Patch default system settings
echo "[3/4] Applying system patches..."
# Set default timezone to CST-8
if [ -f "package/base-files/files/bin/config_generate" ]; then
    # This is handled by files/etc/config/system instead
    echo "  -> System config will be set via files/etc/config/system"
fi

# 4. Verify packages exist
echo "[4/4] Verifying key packages..."
for pkg in luci-app-passwall rtp2httpd luci-app-rtp2httpd igmpproxy; do
    found=$(find package/ feeds/ -path "*/$pkg/Makefile" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "  -> [OK] $pkg found at: $found"
    else
        echo "  -> [WARN] $pkg NOT found! Check feeds configuration."
    fi
done

# 5. Show build summary
echo ""
echo "============================================"
echo " Build Summary"
echo "============================================"
echo " Target: qualcommax/ipq60xx/zn_m2"
echo " Features: PASSWALL + rtp2httpd + IPTV fusion"
echo " Kernel: $(grep 'LINUX_VERSION' include/kernel-default.mk 2>/dev/null | head -1 || echo 'check in build log')"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
