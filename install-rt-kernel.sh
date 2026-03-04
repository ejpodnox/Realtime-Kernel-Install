#!/bin/bash
#
# install-rt-kernel.sh — Build and install a PREEMPT_RT patched Linux kernel
#
# Usage:
#   chmod +x install-rt-kernel.sh
#   ./install-rt-kernel.sh [KERNEL_VERSION] [RT_PATCH_VERSION]
#
# Examples:
#   ./install-rt-kernel.sh 6.6.127 rt69      # Install 6.6.127-rt69
#   ./install-rt-kernel.sh 6.1.119 rt7       # Install 6.1.119-rt7
#   ./install-rt-kernel.sh                    # Defaults to 6.6.127-rt69
#
# Prerequisites:
#   - Ubuntu 22.04 LTS (or compatible Debian-based distro)
#   - Secure Boot DISABLED in BIOS/UEFI
#   - ~15GB free disk space
#   - Internet connection
#

set -euo pipefail

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
KERNEL_VERSION="${1:-6.6.127}"
RT_PATCH_VERSION="${2:-rt69}"
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
RT_BRANCH="${KERNEL_VERSION%.*}"  # e.g., 6.6

WORK_DIR="$HOME/rt-kernel"
KERNEL_DIR="${WORK_DIR}/linux-${KERNEL_VERSION}"
PATCH_FILE="patch-${KERNEL_VERSION}-${RT_PATCH_VERSION}.patch"
PATCH_ARCHIVE="${PATCH_FILE}.xz"

KERNEL_URL="https://mirrors.edge.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz"
PATCH_URL="https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/${RT_BRANCH}/${PATCH_ARCHIVE}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

confirm() {
    local msg="$1"
    echo -en "${YELLOW}${msg} [y/N]: ${NC}"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
}

# ─────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────
preflight() {
    info "─────────────────────────────────────────"
    info "RT Kernel Installer"
    info "─────────────────────────────────────────"
    info "Kernel:    ${KERNEL_VERSION}"
    info "RT Patch:  ${RT_PATCH_VERSION}"
    info "Full name: ${KERNEL_VERSION}-${RT_PATCH_VERSION}"
    info "Work dir:  ${WORK_DIR}"
    info "─────────────────────────────────────────"
    echo

    # Check sudo
    if ! sudo -v 2>/dev/null; then
        die "This script requires sudo privileges."
    fi

    # Check free space (need ~15GB)
    local avail_kb
    avail_kb=$(df --output=avail "$HOME" | tail -1 | tr -d ' ')
    local avail_gb=$((avail_kb / 1024 / 1024))
    if (( avail_gb < 10 )); then
        warn "Low disk space: ${avail_gb}GB available (recommended: 15GB+)"
        confirm "Continue anyway?"
    else
        ok "Disk space: ${avail_gb}GB available"
    fi

    # Check running kernel
    info "Currently running kernel: $(uname -r)"
    echo

    confirm "Proceed with building kernel ${KERNEL_VERSION}-${RT_PATCH_VERSION}?"
}

# ─────────────────────────────────────────────
# Step 1: Install build dependencies
# ─────────────────────────────────────────────
install_dependencies() {
    info "Step 1/7: Installing build dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        build-essential bc curl ca-certificates gnupg2 \
        libssl-dev lsb-release libelf-dev bison flex \
        dwarves zstd libncurses-dev debhelper
    ok "Build dependencies installed."
}

# ─────────────────────────────────────────────
# Step 2: Download sources
# ─────────────────────────────────────────────
download_sources() {
    info "Step 2/7: Downloading kernel source and RT patch..."
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"

    if [[ -f "linux-${KERNEL_VERSION}.tar.xz" ]]; then
        ok "Kernel source already downloaded."
    else
        info "Downloading linux-${KERNEL_VERSION}.tar.xz ..."
        curl -# -O "${KERNEL_URL}" || die "Failed to download kernel source from:\n  ${KERNEL_URL}"
    fi

    if [[ -f "${PATCH_ARCHIVE}" || -f "${PATCH_FILE}" ]]; then
        ok "RT patch already downloaded."
    else
        info "Downloading ${PATCH_ARCHIVE} ..."
        curl -# -O "${PATCH_URL}" || die "Failed to download RT patch from:\n  ${PATCH_URL}"
    fi

    ok "Sources downloaded."
}

# ─────────────────────────────────────────────
# Step 3: Extract and patch
# ─────────────────────────────────────────────
extract_and_patch() {
    info "Step 3/7: Extracting and patching..."
    cd "${WORK_DIR}"

    if [[ -d "${KERNEL_DIR}" ]]; then
        warn "Kernel directory already exists: ${KERNEL_DIR}"
        confirm "Remove and re-extract?"
        rm -rf "${KERNEL_DIR}"
    fi

    tar -xf "linux-${KERNEL_VERSION}.tar.xz"
    cd "${KERNEL_DIR}"

    # Decompress patch if needed
    if [[ -f "../${PATCH_ARCHIVE}" ]]; then
        xz -d "../${PATCH_ARCHIVE}"
    fi

    info "Applying RT patch..."
    patch -p1 < "../${PATCH_FILE}" || die "Patch failed! Check version compatibility."

    ok "Kernel patched successfully."
}

# ─────────────────────────────────────────────
# Step 4: Configure
# ─────────────────────────────────────────────
configure_kernel() {
    info "Step 4/7: Configuring kernel..."
    cd "${KERNEL_DIR}"

    # Start from current config
    local base_config
    base_config=$(ls /boot/config-* 2>/dev/null | sort -V | tail -1)
    if [[ -z "$base_config" ]]; then
        die "No existing kernel config found in /boot/"
    fi
    info "Using base config: ${base_config}"
    cp -v "${base_config}" .config

    # Apply RT settings
    scripts/config --enable PREEMPT_RT

    # Disable certificate requirements
    scripts/config --disable SYSTEM_TRUSTED_KEYS
    scripts/config --disable SYSTEM_REVOCATION_KEYS
    scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
    scripts/config --set-str SYSTEM_REVOCATION_KEYS ""

    # Set 1000Hz timer for low latency
    scripts/config --enable HZ_1000
    scripts/config --set-val HZ 1000

    # Disable debug overhead
    scripts/config --disable DEBUG_PREEMPT
    scripts/config --disable LOCK_STAT
    scripts/config --disable DEBUG_LOCK_ALLOC

    # Resolve any new config options with defaults
    make olddefconfig

    ok "Kernel configured."

    # Offer interactive config
    echo
    echo -en "${YELLOW}Would you like to review the config in menuconfig? [y/N]: ${NC}"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        make menuconfig
    fi
}

# ─────────────────────────────────────────────
# Step 5: Build
# ─────────────────────────────────────────────
build_kernel() {
    info "Step 5/7: Building kernel (this takes 30-60 minutes)..."
    cd "${KERNEL_DIR}"

    local cores
    cores=$(nproc)
    info "Building with ${cores} CPU cores..."
    make -j"${cores}" bindeb-pkg

    ok "Kernel build complete!"
    info "Packages created in ${WORK_DIR}/"
    ls -lh "${WORK_DIR}"/linux-{image,headers}-*.deb 2>/dev/null || true
}

# ─────────────────────────────────────────────
# Step 6: Install
# ─────────────────────────────────────────────
install_kernel() {
    info "Step 6/7: Installing kernel packages..."
    cd "${WORK_DIR}"

    local image_deb headers_deb
    image_deb=$(ls linux-image-${KERNEL_VERSION}-${RT_PATCH_VERSION}*_amd64.deb 2>/dev/null | head -1)
    headers_deb=$(ls linux-headers-${KERNEL_VERSION}-${RT_PATCH_VERSION}*_amd64.deb 2>/dev/null | head -1)

    if [[ -z "$image_deb" ]]; then
        die "Kernel image .deb not found in ${WORK_DIR}"
    fi

    info "Installing: ${image_deb}"
    [[ -n "$headers_deb" ]] && info "Installing: ${headers_deb}"

    if [[ -n "$headers_deb" ]]; then
        sudo dpkg -i "${headers_deb}" "${image_deb}"
    else
        sudo dpkg -i "${image_deb}"
    fi

    ok "Kernel installed."
}

# ─────────────────────────────────────────────
# Step 7: Post-install configuration
# ─────────────────────────────────────────────
post_install() {
    info "Step 7/7: Post-install configuration..."

    # Configure GRUB
    info "Configuring GRUB..."
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
    sudo update-grub

    # Configure realtime group
    info "Setting up realtime user group..."
    if ! getent group realtime > /dev/null 2>&1; then
        sudo addgroup realtime
    else
        ok "realtime group already exists."
    fi
    sudo usermod -a -G realtime "$(whoami)"

    # Create limits file
    if [[ ! -f /etc/security/limits.d/99-realtime.conf ]]; then
        sudo tee /etc/security/limits.d/99-realtime.conf > /dev/null << 'EOF'
@realtime soft rtprio 99
@realtime soft priority 99
@realtime soft memlock 102400
@realtime hard rtprio 99
@realtime hard priority 99
@realtime hard memlock 102400
EOF
        ok "Real-time limits configured."
    else
        ok "Real-time limits already configured."
    fi

    ok "Post-install configuration complete."
}

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
print_summary() {
    echo
    info "═══════════════════════════════════════════"
    ok   "RT Kernel ${KERNEL_VERSION}-${RT_PATCH_VERSION} installed successfully!"
    info "═══════════════════════════════════════════"
    echo
    info "Next steps:"
    info "  1. Ensure Secure Boot is DISABLED in BIOS/UEFI"
    info "  2. Reboot: sudo reboot"
    info "  3. Select '${KERNEL_VERSION}-${RT_PATCH_VERSION}' from the GRUB menu"
    info "  4. After boot, verify with:"
    info "       uname -r           # should show ${KERNEL_VERSION}-${RT_PATCH_VERSION}"
    info "       uname -v           # should show PREEMPT_RT"
    info "       ulimit -r          # should show 99"
    echo
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
    preflight
    install_dependencies
    download_sources
    extract_and_patch
    configure_kernel
    build_kernel
    install_kernel
    post_install
    print_summary
}

main "$@"
