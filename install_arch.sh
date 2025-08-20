#!/bin/bash

# --------------------------------------------
# ARCH LINUX AUTOMATED INSTALLATION SCRIPT
# With FULL KDE Applications Suite
# For User: shubham
# Device: /dev/nvme0n1
# 500GB SSD: 2GB boot, 16GB swap, 50GB root, rest home
# --------------------------------------------

# Exit on error, undefined variable, or pipe failure
set -euo pipefail

# Set Variables
DEVICE="/dev/nvme0n1"
ROOT_PASSWORD="f17@laptop"  # In production, should be set interactively
USER_NAME="shubham"
USER_PASSWORD="shub"        # In production, should be set interactively
HOSTNAME="ARCH"
TIMEZONE="Asia/Kolkata"
DISPLAY_MANAGER="sddm"

# Function to display error and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Function to check if command executed successfully
check_success() {
    if [ $? -ne 0 ]; then
        error_exit "$1"
    fi
}

# Function to check if a package exists in repositories
check_package_exists() {
    if pacman -Si "$1" &>/dev/null; then
        echo "✓ Package found: $1"
        return 0
    else
        echo "✗ Package not found: $1"
        return 1
    fi
}

# Function to check if repository exists
check_repo_exists() {
    if grep -q "\[$1\]" /etc/pacman.conf; then
        echo "✓ Repository found: $1"
        return 0
    else
        echo "✗ Repository not found: $1"
        return 1
    fi
}

# Verify the target device exists
if [ ! -e "$DEVICE" ]; then
    error_exit "Device $DEVICE does not exist"
fi

# Verify internet connection
echo "Checking internet connection..."
if ! ping -c 3 archlinux.org &>/dev/null; then
    error_exit "No internet connection. Please connect to the internet before running this script."
fi

# Update pacman database
echo "Updating package database..."
pacman -Sy

# Verify essential repositories are enabled
echo "Checking essential repositories..."
check_repo_exists "core" || error_exit "Core repository not enabled"
check_repo_exists "extra" || error_exit "Extra repository not enabled"
check_repo_exists "community" || error_exit "Community repository not enabled"
check_repo_exists "multilib" || error_exit "Multilib repository not enabled"

# Verify critical packages exist before installation
echo "Checking critical packages..."
critical_packages=(
    "base" "base-devel" "linux" "linux-headers" "linux-lts" "linux-lts-headers"
    "linux-firmware" "nano" "sudo" "bash-completion" "networkmanager"
    "grub" "efibootmgr" "os-prober" "intel-ucode" "dhcpcd"
    "iwd" "git" "htop" "neofetch" "openssh"
    "pipewire" "pipewire-pulse" "pipewire-alsa" "wireplumber"
    "xdg-user-dirs" "xdg-utils"
)

for pkg in "${critical_packages[@]}"; do
    check_package_exists "$pkg" || error_exit "Critical package $pkg not available"
done

# Verify desktop environment packages
echo "Checking desktop environment packages..."
de_packages=(
    "plasma-meta" "plasma-wayland-session" "sddm" "sddm-kcm"
    "dolphin" "konsole" "kate" "kwrite" "ark" "okular"
    "hyprland" "xdg-desktop-portal-hyprland" "waybar" "rofi" "swaylock" "dunst" "kitty"
)

for pkg in "${de_packages[@]}"; do
    check_package_exists "$pkg" || echo "Warning: Desktop package $pkg not available"
done

# Verify NVIDIA packages if needed
echo "Checking NVIDIA packages..."
nvidia_packages=("nvidia-dkms" "nvidia-utils" "nvidia-settings" "nvidia-prime")
for pkg in "${nvidia_packages[@]}"; do
    check_package_exists "$pkg" || echo "Warning: NVIDIA package $pkg not available"
done

# --- PARTITIONING ---
echo "Partitioning disk $DEVICE (2GB boot, 16GB swap, 50GB root, rest home)..."
if ! parted -s $DEVICE mklabel gpt; then
    error_exit "Failed to create GPT partition table"
fi

parted -s $DEVICE mkpart primary fat32 1MiB 2GiB
check_success "Failed to create boot partition"

parted -s $DEVICE set 1 esp on
check_success "Failed to set ESP flag"

parted -s $DEVICE mkpart primary linux-swap 2GiB 18GiB
check_success "Failed to create swap partition"

parted -s $DEVICE mkpart primary ext4 18GiB 68GiB
check_success "Failed to create root partition"

parted -s $DEVICE mkpart primary ext4 68GiB 100%
check_success "Failed to create home partition"

# --- FORMATTING ---
echo "Formatting partitions..."
mkfs.fat -F32 ${DEVICE}p1
check_success "Failed to format boot partition"

mkswap ${DEVICE}p2
check_success "Failed to create swap"

mkfs.ext4 -F ${DEVICE}p3
check_success "Failed to format root partition"

mkfs.ext4 -F ${DEVICE}p4
check_success "Failed to format home partition"

# --- MOUNTING ---
echo "Mounting filesystems..."
mount ${DEVICE}p3 /mnt
check_success "Failed to mount root partition"

mkdir -p /mnt/boot
mount ${DEVICE}p1 /mnt/boot
check_success "Failed to mount boot partition"

mkdir -p /mnt/home
mount ${DEVICE}p4 /mnt/home
check_success "Failed to mount home partition"

swapon ${DEVICE}p2
check_success "Failed to enable swap"

# --- BASE INSTALLATION ---
echo "Installing base system and ALL kernels..."
# Install only verified available packages
pacstrap -K /mnt base base-devel \
linux linux-headers \
linux-lts linux-lts-headers \
linux-firmware nano sudo bash-completion networkmanager \
grub efibootmgr os-prober intel-ucode man-db man-pages \
texinfo ntfs-3g exfatprogs dosfstools e2fsprogs dhcpcd \
iwd wpa_supplicant git htop neofetch rsync openssh \
pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
xdg-user-dirs xdg-utils
check_success "Failed to install base system"

# Try to install additional kernels if available
additional_kernels=("linux-zen" "linux-zen-headers" "linux-hardened" "linux-hardened-headers")
for kernel in "${additional_kernels[@]}"; do
    if check_package_exists "$kernel" &>/dev/null; then
        echo "Installing additional kernel: $kernel"
        pacstrap -K /mnt "$kernel" || echo "Warning: Failed to install $kernel"
    fi
done

# --- GENERATE FSTAB ---
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
check_success "Failed to generate fstab"

# --- CHROOT SETUP ---
echo "Setting up system configuration..."
arch-chroot /mnt /bin/bash <<EOF || error_exit "Chroot operations failed"

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Set localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Set hosts file
echo "127.0.0.1   localhost" >> /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
useradd -m -G wheel,audio,video,storage -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# Enable sudo for wheel
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# --- BOOTLOADER CONFIGURATION ---
echo "Installing and configuring GRUB for multiple kernels..."
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

# Check if we're in UEFI mode
if [ -d /sys/firmware/efi ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
else
    grub-install $DEVICE
fi

grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
systemctl enable dhcpcd

# --- NVIDIA DRIVERS (DKMS FOR ALL KERNELS) ---
# Only install if available
if pacman -Si nvidia-dkms &>/dev/null; then
    echo "Installing NVIDIA DKMS drivers for all kernels..."
    pacman -S --noconfirm nvidia-dkms nvidia-utils nvidia-settings nvidia-prime
    
    # Configure NVIDIA
    echo "blacklist nouveau" > /etc/modprobe.d/nvidia.conf
    echo "options nvidia-drm modeset=1" >> /etc/modprobe.d/nvidia.conf

    # Only add nvidia_drm.modeset=1 if not already present
    if ! grep -q "nvidia_drm.modeset=1" /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& nvidia_drm.modeset=1/' /etc/default/grub
    fi

    grub-mkconfig -o /boot/grub/grub.cfg
else
    echo "NVIDIA packages not available, skipping installation"
fi

# --- INTEL GRAPHICS DRIVERS (CRITICAL FOR YOUR CPU) ---
echo "Installing Intel graphics drivers..."
pacman -S --noconfirm mesa vulkan-intel intel-media-driver libva-intel-driver

# --- ESSENTIAL DESKTOP UTILITIES ---
echo "Installing essential desktop utilities..."
# Only install available packages
for pkg in firefox chromium thunar thunar-archive-plugin thunar-volman \
file-roller gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb \
ntfs-3g ffmpegthumbnailer vlc mpv viewnior gimp geany code ark okular; do
    if pacman -Si "\$pkg" &>/dev/null; then
        pacman -S --noconfirm "\$pkg" || echo "Failed to install \$pkg"
    else
        echo "Package \$pkg not available, skipping"
    fi
done

# Create default user directories (Downloads, Documents, Music, etc.)
sudo -u $USER_NAME xdg-user-dirs-update

# --- COMPLETE KDE PLASMA SUITE ---
echo "Installing KDE Plasma and applications..."
# Install plasma meta package and essential components
for pkg in plasma-meta plasma-wayland-session sddm sddm-kcm dolphin konsole kate kwrite \
kcalc kcharselect kfind kgpg partitionmanager print-manager systemsettings kinfocenter \
spectacle gwenview okular ark kdenlive kwave elisa kget krdc krfb kdevelop \
noto-fonts noto-fonts-cjk noto-fonts-emoji; do
    if pacman -Si "\$pkg" &>/dev/null; then
        pacman -S --noconfirm "\$pkg" || echo "Failed to install \$pkg"
    else
        echo "Package \$pkg not available, skipping"
    fi
done

# --- HYPRLAND INSTALLATION ---
echo "Installing Hyprland and essentials..."
# Install Hyprland and components if available
for pkg in hyprland xdg-desktop-portal-hyprland grim slurp wl-clipboard \
waybar rofi swaylock swayidle dunst kitty polkit-kde-agent qt5-wayland qt6-wayland; do
    if pacman -Si "\$pkg" &>/dev/null; then
        pacman -S --noconfirm "\$pkg" || echo "Failed to install \$pkg"
    else
        echo "Package \$pkg not available, skipping"
    fi
done

# Create Hyprland config directory
mkdir -p /home/$USER_NAME/.config/hypr

# Create Hyprland config
cat > /home/$USER_NAME/.config/hypr/hyprland.conf <<'HYPR_EOF'
# Monitor configuration
monitor=,preferred,auto,1

# Autostart
exec-once = waybar
exec-once = dunst
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = /usr/lib/polkit-kde-authentication-agent-1

# Environment variables for NVIDIA - only set if NVIDIA is detected
exec-once = bash -c "if [ -f /proc/driver/nvidia/version ]; then
  export LIBVA_DRIVER_NAME=nvidia
  export GBM_BACKEND=nvidia-drm
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export WLR_NO_HARDWARE_CURSORS=1
else
  export WLR_NO_HARDWARE_CURSORS=0
fi"

$terminal = kitty
$fileManager = dolphin
$menu = rofi -show drun

env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GDK_BACKEND,wayland,x11

$mainMod = SUPER

bind = $mainMod, RETURN, exec, $terminal
bind = $mainMod, Q, killactive,
bind = $mainMod, D, exec, $menu
bind = $mainMod, L, exec, swaylock
bind = $mainMod SHIFT, E, exec, hyprctl dispatch exit

bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Window rules
windowrule = float,^(pavucontrol)$
windowrule = float,^(blueman-manager)$
windowrule = float,^(nm-connection-editor)$
HYPR_EOF

# Create a script to auto-detect graphics and set environment
cat > /usr/local/bin/detect-graphics <<'DETECT_EOF'
#!/bin/bash
if [ -f /proc/driver/nvidia/version ]; then
    export LIBVA_DRIVER_NAME=nvidia
    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export WLR_NO_HARDWARE_CURSORS=1
else
    export WLR_NO_HARDWARE_CURSORS=0
fi
exec "\$@"
DETECT_EOF

chmod +x /usr/local/bin/detect-graphics

# Set ownership of user files
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.config

# Enable sddm display manager
systemctl enable sddm.service

# Add user to necessary groups
usermod -aG video,input,audio $USER_NAME

# Regenerate initramfs for all kernels
mkinitcpio -P

EOF

# --- FINAL STEPS ---
echo "Unmounting and finalizing..."
umount -R /mnt
swapoff -a

echo "----------------------------------------"
echo "INSTALLATION COMPLETE!"
echo "----------------------------------------"
echo "Root password: $ROOT_PASSWORD"
echo "User: $USER_NAME"
echo "User password: $USER_PASSWORD"
echo "Hostname: $HOSTNAME"
echo "Display Manager: sddm (KDE compatible)"
echo "----------------------------------------"
echo "Reboot and remove installation media."
echo "At sddm login, click the desktop session button to choose:"
echo "- Plasma (X11) for KDE"
echo "- Plasma (Wayland) for KDE Wayland"
echo "- Hyprland for tiling WM"
echo "----------------------------------------"
