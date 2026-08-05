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
echo "[1/3] Adding rtp2httpd package..."
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
echo "[2/3] Verifying PPPoE packages..."
for pkg in ppp ppp-mod-pppoe kmod-pppoe; do
    found=$(find feeds/packages/ -name "$pkg" -type d 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "  -> [OK] $pkg available"
    else
        echo "  -> [WARN] $pkg not found in feeds"
    fi
done

# 3. Verify key packages exist
echo "[3/3] Verifying key packages..."
for pkg in luci-app-passwall rtp2httpd luci-app-rtp2httpd; do
    found=$(find package/ feeds/ -path "*/$pkg/Makefile" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "  -> [OK] $pkg found at: $found"
    else
        echo "  -> [WARN] $pkg NOT found! Check feeds configuration."
    fi
done

echo ""
echo "============================================"
echo " Build Summary"
echo "============================================"
echo " Target: qualcommax/ipq60xx/zn_m2"
echo " WiFi:   DISABLED"
echo " IPTV:   Dual-line PPPoE + policy routing"
echo " Features: PASSWALL + rtp2httpd"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
