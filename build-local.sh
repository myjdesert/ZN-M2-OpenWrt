#!/bin/bash
# ============================================================
# ZN-M2 OpenWrt Local Build Script
# Requires: Ubuntu 22.04+ or Debian 12+ (or WSL2)
# Disk space: at least 20GB free
# Memory: at least 4GB (8GB recommended)
# ============================================================

set -e

# --- Configuration ---
REPO_URL="https://github.com/immortalwrt/immortalwrt"
REPO_BRANCH="master"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/openwrt"
CONFIG_FILE="${SCRIPT_DIR}/configs/zn-m2.config"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Pre-flight checks ---
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN} ZN-M2 OpenWrt Local Build Script${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Check OS
if [ "$(uname -s)" != "Linux" ]; then
    error "This script must run on Linux. Use WSL2 or a Linux VM on Windows."
fi

# Check root/sudo
if [ "$(id -u)" -eq 0 ]; then
    warn "Running as root is not recommended. Use a regular user with sudo."
fi

# Check disk space
FREE_SPACE=$(df -m "${SCRIPT_DIR}" | awk 'NR==2{print $4}')
if [ "$FREE_SPACE" -lt 20480 ]; then
    warn "Less than 20GB free disk space (${FREE_SPACE}MB). Build may fail."
    read -p "Continue anyway? (y/N) " -r
    [[ "$REPLY" =~ ^[Yy]$ ]] || exit 0
fi

# Check memory
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
info "Total memory: ${TOTAL_MEM}MB"
if [ "$TOTAL_MEM" -lt 4096 ]; then
    warn "Less than 4GB RAM. Build will be slow and may fail."
    # Create swap if needed
    if [ ! -f /swapfile ]; then
        info "Creating 8GB swap file..."
        sudo fallocate -l 8G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        info "Swap enabled."
    fi
fi

# --- Step 1: Install dependencies ---
info "Step 1: Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential clang flex bison g++ gawk gcc-multilib \
    g++-multilib gettext git libncurses5-dev libssl-dev \
    python3-distutils python3-setuptools rsync unzip zlib1g-dev \
    wget curl time coreutils quilt perl python3-pip
sudo apt-get clean
echo ""

# --- Step 2: Clone source ---
info "Step 2: Cloning ImmortalWrt source..."
if [ -d "$BUILD_DIR" ]; then
    warn "Build directory exists: $BUILD_DIR"
    read -p "Reuse existing source? (y/N) " -r
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        rm -rf "$BUILD_DIR"
        git clone --depth 1 --single-branch -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"
    fi
else
    git clone --depth 1 --single-branch -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"
fi
cd "$BUILD_DIR"
info "Source: $(git log -1 --format='%H %ci')"
info "Kernel: $(grep 'LINUX_VERSION' include/kernel-default.mk 2>/dev/null | head -1)"
echo ""

# --- Step 3: Add custom feeds ---
info "Step 3: Adding custom feeds..."
FEEDS_CUSTOM="${SCRIPT_DIR}/scripts/feeds.conf.custom"
if [ -f "$FEEDS_CUSTOM" ]; then
    sed -i '/passwall/d' feeds.conf.default
    cat "$FEEDS_CUSTOM" | grep -v '^#' | grep -v '^$' >> feeds.conf.default
    info "Custom feeds added."
fi

# Run DIY part 1
DIY1="${SCRIPT_DIR}/scripts/diy-part1.sh"
if [ -f "$DIY1" ]; then
    chmod +x "$DIY1"
    "$DIY1"
fi
echo ""

# --- Step 4: Update and install feeds ---
info "Step 4: Updating and installing feeds..."
./scripts/feeds update -a
./scripts/feeds install -a
echo ""

# --- Step 5: Run DIY part 2 ---
info "Step 5: Running DIY part 2..."
DIY2="${SCRIPT_DIR}/scripts/diy-part2.sh"
if [ -f "$DIY2" ]; then
    chmod +x "$DIY2"
    "$DIY2"
fi
echo ""

# --- Step 6: Copy custom files and apply config ---
info "Step 6: Applying configuration..."
cp -r "${SCRIPT_DIR}/files/"* . 2>/dev/null || true
cp "$CONFIG_FILE" .config
make defconfig
info "Config applied. Key settings:"
grep -E "TARGET_qualcommax|TARGET_ipq60xx|DEVICE_zn|passwall|rtp2httpd|igmp" .config | head -20
echo ""

# --- Step 7: Download ---
info "Step 7: Downloading sources (this may take a while)..."
make download -j$(nproc) 2>&1 | tail -10 || make download -j1
echo ""

# --- Step 8: Compile ---
info "Step 8: Compiling firmware (this will take 2-5 hours)..."
info "Start time: $(date)"
echo ""

make -j$(nproc) V=s || {
    warn "First pass failed, retrying with single thread..."
    make -j1 V=s
}

info "Compile finished at: $(date)"
echo ""

# --- Step 9: Show output ---
info "Step 9: Build output:"
echo ""
find bin/targets/ -name "*.bin" -o -name "*.ubi" -o -name "*.itb" 2>/dev/null
echo ""
ls -lh bin/targets/*/*/ 2>/dev/null
echo ""

info "Build completed successfully!"
info "Firmware files are in: ${BUILD_DIR}/bin/targets/"
info ""
info "Next steps:"
info "  1. Use *-sysupgrade.bin to upgrade from existing OpenWrt"
info "  2. Use *-factory.ubi to flash via U-Boot"
info "  3. Default IP: 192.168.1.1"
info "  4. Configure PPPoE credentials after first boot"
