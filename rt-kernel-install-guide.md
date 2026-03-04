# Real-Time (PREEMPT_RT) Kernel Installation Guide

> **Target System**: Ubuntu 22.04 LTS (Debian-based)
> **Tested On**: Lenovo ThinkPad T14s (Intel, 8 cores)
> **Author**: Generated from successful 6.6.127-rt69 installation experience

---

## Overview

This guide walks you through building and installing a **PREEMPT_RT** patched Linux kernel from source on Ubuntu. The RT kernel provides deterministic scheduling behavior required for real-time audio, robotics, industrial control, and other latency-sensitive applications.

> [!IMPORTANT]
> **Secure Boot must be disabled** in your BIOS/UEFI before booting a custom kernel. Custom kernels are not signed with Microsoft/Canonical keys.

---

## Prerequisites

- Ubuntu 22.04 LTS (or compatible Debian-based distro)
- At least **15 GB** of free disk space (kernel source + build output)
- Internet connection
- `sudo` privileges
- ~30–60 minutes of build time (varies by CPU core count)

---

## Step 1: Choose Your Kernel + RT Patch Version

Visit the RT patch repository to find a compatible pair:

- **Kernel sources**: https://mirrors.edge.kernel.org/pub/linux/kernel/
- **RT patches**: https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/

> [!TIP]
> **Use LTS kernel branches** (e.g., 6.6.x, 6.1.x) for stability. Non-LTS RT kernels (e.g., 6.8.x) may have incomplete lock-conversion coverage, causing `scheduling while atomic` bugs.

The kernel version and patch version **must match exactly**. For example:
- Kernel: `linux-6.6.127.tar.xz`
- Patch: `patch-6.6.127-rt69.patch.xz`

---

## Step 2: Install Build Dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential bc curl ca-certificates gnupg2 \
  libssl-dev lsb-release libelf-dev bison flex \
  dwarves zstd libncurses-dev debhelper
```

---

## Step 3: Download Kernel Source and RT Patch

```bash
# Create a working directory
mkdir -p ~/rt-kernel && cd ~/rt-kernel

# Download kernel source (replace version as needed)
KERNEL_VERSION="6.6.127"
KERNEL_MAJOR="6"
RT_PATCH="patch-6.6.127-rt69.patch.xz"

curl -O "https://mirrors.edge.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz"
curl -O "https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/6.6/${RT_PATCH}"
```

---

## Step 4: Extract and Apply the RT Patch

```bash
cd ~/rt-kernel

# Extract the kernel source
tar -xf linux-${KERNEL_VERSION}.tar.xz
cd linux-${KERNEL_VERSION}

# Decompress and apply the RT patch
xz -d ../${RT_PATCH}
patch -p1 < ../${RT_PATCH%.xz}
```

You should see a long list of patched files with no errors or `FAILED` messages.

---

## Step 5: Configure the Kernel

### 5a. Start from your current kernel config

```bash
cp -v /boot/config-$(uname -r) .config
```

### 5b. Apply RT-specific settings

```bash
# Enable Full Real-Time Preemption
scripts/config --enable PREEMPT_RT

# Disable certificate requirements (prevents build failures)
scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS
scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
scripts/config --set-str SYSTEM_REVOCATION_KEYS ""

# Set timer frequency for low latency
scripts/config --enable HZ_1000
scripts/config --set-val HZ 1000

# Disable some debug options that add overhead (optional but recommended)
scripts/config --disable DEBUG_PREEMPT
scripts/config --disable LOCK_STAT
scripts/config --disable DEBUG_LOCK_ALLOC

# Update config with defaults for all new options
make olddefconfig
```

### 5c. (Optional) Interactive configuration

If you want to review/customize further:

```bash
make menuconfig
```

Key menu paths:
- **General Setup → Preemption Model** → Select "Fully Preemptible Kernel (Real-Time)"
- **General Setup → Local version** → Set to e.g. `-rt69` (or any identifier you like)

---

## Step 6: Build the Kernel as .deb Packages

```bash
# Build using all available CPU cores
make -j$(nproc) bindeb-pkg
```

This produces `.deb` files in the parent directory (`~/rt-kernel/`):
- `linux-image-<version>_*.deb` — the kernel itself
- `linux-headers-<version>_*.deb` — headers for module compilation

> [!NOTE]
> Build time is approximately **30–60 minutes** on an 8-core machine. You can monitor CPU usage with `htop` in another terminal.

---

## Step 7: Install the Kernel

```bash
cd ~/rt-kernel

# Install the image and headers packages
sudo dpkg -i linux-headers-${KERNEL_VERSION}-rt*_amd64.deb linux-image-${KERNEL_VERSION}-rt*_amd64.deb
```

> [!WARNING]
> If you see DKMS warnings about third-party modules (e.g., `librealsense2-dkms`), these are usually non-critical. The core kernel is still installed correctly.

---

## Step 8: Configure GRUB Bootloader

```bash
# Allow selecting kernels at boot
sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub

# Update GRUB configuration
sudo update-grub
```

After reboot, you'll see a GRUB menu with a 5-second timeout where you can select your kernel.

---

## Step 9: Configure Real-Time User Permissions

```bash
# Create the realtime group and add your user
sudo addgroup realtime
sudo usermod -a -G realtime $(whoami)

# Create limits configuration
sudo tee /etc/security/limits.d/99-realtime.conf > /dev/null << 'EOF'
@realtime soft rtprio 99
@realtime soft priority 99
@realtime soft memlock 102400
@realtime hard rtprio 99
@realtime hard priority 99
@realtime hard memlock 102400
EOF
```

---

## Step 10: Reboot and Verify

```bash
sudo reboot
```

After rebooting, select your new RT kernel from the GRUB menu, then verify:

```bash
# Should show your RT kernel version (e.g., 6.6.127-rt69)
uname -r

# Should show PREEMPT_RT
uname -v

# Verify RT config is enabled
grep CONFIG_PREEMPT_RT /boot/config-$(uname -r)

# Check real-time user limits
ulimit -r   # should show 99
ulimit -l   # should show 102400

# Verify no scheduling bugs in kernel log
dmesg | grep -i "scheduling while atomic"
```

---

## Removing an Old RT Kernel

To remove a previously installed RT kernel (e.g., `6.8.2-rt11`):

```bash
# Remove packages
sudo apt-get purge -y linux-image-<version> linux-headers-<version>
# Example: sudo apt-get purge -y linux-image-6.8.2-rt11 linux-headers-6.8.2-rt11

# Clean up any remaining boot files
sudo rm -f /boot/*-<version>

# Update GRUB
sudo update-grub

# Optional: remove build directory
rm -rf ~/rt-kernel/linux-<version>
```

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| `scheduling while atomic` errors | Non-LTS RT kernel with incomplete lock conversion | Use an LTS kernel branch (6.6.x, 6.1.x) |
| Kernel hangs on boot | `nomodeset` in GRUB blocking GPU driver | Remove `nomodeset` from `GRUB_CMDLINE_LINUX_DEFAULT` |
| GDM/display doesn't load | Missing GPU driver module | Ensure `CONFIG_DRM_I915=m` (Intel) is set in config |
| WiFi not working | Missing WiFi driver module | Ensure `CONFIG_IWLWIFI=m` is set in config |
| DKMS build warnings | Third-party modules incompatible | Usually safe to ignore; rebuild manually if needed |
| Kernel not in GRUB menu | GRUB not updated | Run `sudo update-grub` |

---

## Recommended Kernel Versions

| Kernel | RT Patch | Status | Notes |
|--------|----------|--------|-------|
| 6.6.x | rt69+ | ✅ LTS, Stable | Recommended for production use |
| 6.1.x | rt7+ | ✅ LTS, Stable | Long-term support, very mature |
| 6.8.x | rt11 | ⚠️ Unstable | Known `scheduling while atomic` bugs |
