#!/bin/bash
# ============================================================
# DIY Part 1 - Executed BEFORE feeds update/install
# This script runs in the openwrt source directory
# ============================================================

set -e

echo "============================================"
echo " DIY Part 1: Pre-feeds customization"
echo "============================================"

# 1. Add custom feeds to feeds.conf.default
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FEEDS_CUSTOM="$SCRIPT_DIR/feeds.conf.custom"

if [ -f "$FEEDS_CUSTOM" ]; then
    echo "[1/3] Adding custom feeds..."
    # Remove existing passwall entries to avoid duplicates
    sed -i '/passwall/d' feeds.conf.default
    # Append custom feeds
    cat "$FEEDS_CUSTOM" | grep -v '^#' | grep -v '^$' >> feeds.conf.default
    echo "  -> Custom feeds added:"
    grep -E "passwall" feeds.conf.default
fi

# 2. Set default hostname and timezone
echo "[2/3] Setting default hostname and timezone..."
# These will be overridden by files/etc/config/system if present

# 3. Display kernel version info
echo "[3/3] Kernel version info:"
grep -r "LINUX_VERSION" include/kernel-default.mk 2>/dev/null || \
grep -r "LINUX_VERSION" include/kernel-6.18 2>/dev/null || \
grep -r "LINUX_VERSION" include/ 2>/dev/null | head -5 || \
echo "  (kernel version info not found in expected location)"

echo ""
echo "=== feeds.conf.default content ==="
cat feeds.conf.default

echo ""
echo "DIY Part 1 completed successfully."
