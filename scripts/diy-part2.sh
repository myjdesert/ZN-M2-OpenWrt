#!/bin/bash
# ============================================================
# DIY Part 2 - Executed AFTER feeds install, BEFORE make
# For VIKINGYFY/ImmortalWrt main branch (ZN-M2 already supported)
# ============================================================

set -e

echo "============================================"
echo " DIY Part 2: Customizing VIKINGYFW/ImmortalWrt"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Remove WiFi from DEFAULT_PACKAGES (user doesn't need WiFi)
# IMPORTANT: DEFAULT_PACKAGES is a multi-line block. The first line is only
# "DEFAULT_PACKAGES += \" and the actual package names live on the tab-indented
# continuation lines. Sed must target those continuation lines, otherwise
# nothing gets removed at all.
echo "[1/5] Removing WiFi from DEFAULT_PACKAGES..."
TARGET_MAKEFILE="target/linux/qualcommax/Makefile"
IPQ60XX_MK="target/linux/qualcommax/ipq60xx/target.mk"

if [ -f "$TARGET_MAKEFILE" ]; then
    # Longest names first, so "kmod-ath11k" never partially matches
    # "kmod-ath11k-ahb" and leaves a dangling "-ahb" token behind.
    for pkg in kmod-ath11k-ahb kmod-ath11k-pci kmod-ath11k wpad-openssl; do
        sed -i "/^\t/s/ *${pkg}\b//g" "$TARGET_MAKEFILE"
    done
    # Collapse the double spaces left behind by the removals
    sed -i '/^\t/s/  \+/ /g' "$TARGET_MAKEFILE"
    echo "  -> WiFi packages removed from $TARGET_MAKEFILE"
else
    echo "  -> WARNING: $TARGET_MAKEFILE not found!"
fi

if [ -f "$IPQ60XX_MK" ]; then
    sed -i "/^DEFAULT_PACKAGES/s/ *ath11k-firmware-ipq6018-ddwrt\b//g" "$IPQ60XX_MK"
    echo "  -> WiFi firmware removed from $IPQ60XX_MK"
else
    echo "  -> WARNING: $IPQ60XX_MK not found!"
fi

echo "  -> Default packages after cleanup:"
sed -n '/^DEFAULT_PACKAGES/,/^\$(eval/p' "$TARGET_MAKEFILE" 2>/dev/null | head -8
grep "^DEFAULT_PACKAGES" "$IPQ60XX_MK" 2>/dev/null || true

# 2. Clone and install rtp2httpd as a package
echo "[2/5] Adding rtp2httpd package..."
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

# 3. Clone and install gecoosac (集客AC controller) as a package
echo "[3/5] Adding gecoosac (集客AC) package..."
if [ ! -d "package/luci-app-gecoosac" ]; then
    git clone --depth 1 https://github.com/laipeng668/luci-app-gecoosac.git package/luci-app-gecoosac 2>/dev/null || {
        echo "  -> Failed to clone from github.com, trying gitcode mirror..."
        git clone --depth 1 https://gitcode.com/laipeng668/luci-app-gecoosac.git package/luci-app-gecoosac 2>/dev/null || {
            echo "  -> ERROR: Could not clone gecoosac repo!"
        }
    }
    if [ -d "package/luci-app-gecoosac/gecoosac" ] && [ -d "package/luci-app-gecoosac/luci-app-gecoosac" ]; then
        echo "  -> gecoosac + luci-app-gecoosac packages added"
    else
        echo "  -> WARNING: gecoosac package structure incomplete"
    fi
else
    echo "  -> gecoosac package already exists"
fi

# 4. Clone and install fullconenat-nft as a package
echo "[4/5] Adding fullconenat-nft (Full Cone NAT) package..."
if [ ! -d "package/fullconenat-nft" ]; then
    git clone --depth 1 https://github.com/hubbylei/fullconenat-nft.git /tmp/fullconenat-nft 2>/dev/null || {
        echo "  -> Failed to clone from github.com, trying gitcode mirror..."
        git clone --depth 1 https://gitcode.com/hubbylei/fullconenat-nft.git /tmp/fullconenat-nft 2>/dev/null || {
            echo "  -> ERROR: Could not clone fullconenat-nft repo!"
        }
    }
    if [ -d "/tmp/fullconenat-nft" ]; then
        # Copy Makefile and patches (not .github folder)
        mkdir -p package/fullconenat-nft
        cp /tmp/fullconenat-nft/Makefile package/fullconenat-nft/Makefile
        if [ -d "/tmp/fullconenat-nft/patches" ]; then
            cp -r /tmp/fullconenat-nft/patches package/fullconenat-nft/
        fi
        echo "  -> fullconenat-nft (kmod-nft-fullcone) package added"
        rm -rf /tmp/fullconenat-nft
    fi
else
    echo "  -> fullconenat-nft package already exists"
fi

# 5. Verify everything is in place
echo "[5/5] Final verification..."
echo ""

echo "  -> ZN-M2 device definition (should be built-in):"
IPQ60XX_IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"
grep -A8 "define Device/zn_m2" "$IPQ60XX_IMAGE_MK" 2>/dev/null || echo "  -> WARNING: zn_m2 not found in ipq60xx.mk!"
echo ""

echo "  -> ZN-M2 DTS (per-port netdevs -> port status display):"
DTS_FILE="target/linux/qualcommax/dts/ipq6000-m2.dts"
DTSI_FILE="target/linux/qualcommax/dts/ipq6000-cmiot.dtsi"
if [ -f "$DTS_FILE" ]; then
    echo "    [OK] $DTS_FILE exists"
    grep -E "label|status" "$DTSI_FILE" 2>/dev/null | head -8
else
    echo "    [WARN] $DTS_FILE NOT found!"
fi
echo ""

echo "  -> NSS stack (backup: these are also in DEFAULT_PACKAGES):"
for pkg in qca-nss-drv qca-nss-ecm qca-nss-dp qca-ssdk qca-nss-crypto nss-firmware; do
    if [ -d "package/qca-nss/$pkg" ]; then
        echo "    [OK] package/qca-nss/$pkg"
    else
        echo "    [WARN] package/qca-nss/$pkg NOT found!"
    fi
done
echo ""

echo "  -> Kernel version:"
grep "KERNEL_PATCHVER" "$TARGET_MAKEFILE" 2>/dev/null || true
echo ""

echo "  -> Key packages:"
for pkg in luci-app-passwall rtp2httpd luci-app-rtp2httpd gecoosac luci-app-gecoosac fullconenat-nft; do
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
echo " Source:  VIKINGYFY/ImmortalWrt main (NSS Full Support)"
echo " Kernel:  6.18"
echo " Target:  qualcommax/ipq60xx/zn_m2"
echo " WiFi:    DISABLED"
echo " NSS:     nss-drv + ecm + nss-dp + ssdk + firmware (from DEFAULT_PACKAGES)"
echo " Ports:   lan1 / lan2 / lan3 / wan (independent netdevs, labels in DTS)"
echo " IPTV:    Dual-line PPPoE + policy routing"
echo " Features: PASSWALL (Xray+sing-box) + rtp2httpd + 集客AC + Argon主题 + NSS + 全锥型NAT"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
