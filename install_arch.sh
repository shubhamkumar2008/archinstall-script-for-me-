#!/bin/bash

# --------------------------------------------
# ARCH LINUX AUTOMATED INSTALLATION SCRIPT
# With FULL KDE Applications Suite
# For User: shubham
# Device: /dev/nvme0n1
# 500GB SSD: 2GB boot, 16GB swap, 50GB root, rest home
# --------------------------------------------

# Set Variables
DEVICE="/dev/nvme0n1"
ROOT_PASSWORD="f17@laptop"
USER_NAME="shubham"
USER_PASSWORD="shub"
HOSTNAME="ARCH"
TIMEZONE="Asia/Kolkata"

# --- PARTITIONING ---
echo "Partitioning disk $DEVICE (2GB boot, 16GB swap, 50GB root, rest home)..."
parted -s $DEVICE mklabel gpt
parted -s $DEVICE mkpart primary fat32 1MiB 2GiB
parted -s $DEVICE set 1 esp on
parted -s $DEVICE mkpart primary linux-swap 2GiB 18GiB
parted -s $DEVICE mkpart primary ext4 18GiB 68GiB
parted -s $DEVICE mkpart primary ext4 68GiB 100%

# --- FORMATTING ---
echo "Formatting partitions..."
mkfs.fat -F32 ${DEVICE}p1
mkswap ${DEVICE}p2
mkfs.ext4 ${DEVICE}p3
mkfs.ext4 ${DEVICE}p4

# --- MOUNTING ---
echo "Mounting filesystems..."
mount ${DEVICE}p3 /mnt
mkdir -p /mnt/boot
mount ${DEVICE}p1 /mnt/boot
mkdir -p /mnt/home
mount ${DEVICE}p4 /mnt/home
swapon ${DEVICE}p2

# --- BASE INSTALLATION ---
echo "Installing base system and ALL kernels..."
pacstrap -K /mnt base base-devel \
linux linux-headers \
linux-lts linux-lts-headers \
linux-zen linux-zen-headers \
linux-hardened linux-hardened-headers \
linux-firmware nano sudo bash-completion networkmanager \
grub efibootmgr os-prober intel-ucode man-db man-pages \
texinfo ntfs-3g exfatprogs dosfstools e2fsprogs dhcpcd \
iwd wpa_supplicant git htop neofetch rsync openssh \
pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
xdg-user-dirs xdg-utils

# --- GENERATE FSTAB ---
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- CHROOT SETUP ---
echo "Setting up system configuration..."
arch-chroot /mnt /bin/bash <<EOF

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
useradd -m -G wheel -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# Enable sudo for wheel
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# --- BOOTLOADER CONFIGURATION ---
echo "Installing and configuring GRUB for multiple kernels..."
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager

# --- NVIDIA DRIVERS (DKMS FOR ALL KERNELS) ---
echo "Installing NVIDIA DKMS drivers for all kernels..."
pacman -S --noconfirm nvidia-dkms nvidia-utils nvidia-settings nvidia-prime

# --- INTEL GRAPHICS DRIVERS (CRITICAL FOR YOUR CPU) ---
echo "Installing Intel graphics drivers..."
pacman -S --noconfirm mesa vulkan-intel intel-media-driver

# Configure NVIDIA
echo "blacklist nouveau" > /etc/modprobe.d/nvidia.conf
echo "options nvidia-drm modeset=1" >> /etc/modprobe.d/nvidia.conf
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& nvidia_drm.modeset=1/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# --- ESSENTIAL DESKTOP UTILITIES ---
echo "Installing essential desktop utilities..."
pacman -S --noconfirm firefox chromium \
thunar thunar-archive-plugin thunar-volman \
file-roller gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb \
ntfs-3g ffmpegthumbnailer \
vlc mpv \
viewnior gimp \
geany code \
ark okular

# Create default user directories (Downloads, Documents, Music, etc.)
sudo -u $USER_NAME xdg-user-dirs-update

# --- COMPLETE KDE PLASMA SUITE ---
echo "Installing COMPLETE KDE Plasma and applications..."
pacman -S --noconfirm plasma-meta plasma-wayland-session \
kde-system-meta kde-utilities-meta kde-graphics-meta kde-multimedia-meta \
kde-network-meta kde-sdk-meta \
dolphin konsole kate kwrite \
kcalc kcharselect kfind kgpg \
partitionmanager print-manager systemsettings kinfocenter \
spectacle gwenview okular ark \
kdenlive kwave elisa \
kget krdc krfb \
kdevelop kate dolphin-plugins \
noto-fonts noto-fonts-cjk noto-fonts-emoji

# --- HYPRLAND INSTALLATION ---
echo "Installing Hyprland and essentials..."
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland grim slurp wl-clipboard \
waybar rofi swaylock dunst

# Create Hyprland config directory
mkdir -p /home/$USER_NAME/.config/hypr

# Create PROVEN Hyprland config
cat > /home/$USER_NAME/.config/hypr/hyprland.conf <<'HYPR_EOF'
env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1

monitor=,preferred,auto,1

exec-once = waybar
exec-once = dunst

$terminal = kitty
$fileManager = dolphin
$menu = rofi -show drun

env = XCURSOR_SIZE,24

$mainMod = SUPER

bind = $mainMod, RETURN, exec, $terminal
bind = $mainMod, Q, killactive,
bind = $mainMod, D, exec, $menu
bind = $mainMod, L, exec, swaylock
bind = $mainMod, SHIFT, E, exec, hyprctl dispatch exit

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
HYPR_EOF

# Set ownership of user files
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.config

# Install and enable ly display manager
pacman -S --noconfirm ly
systemctl enable ly.service

# Add user to necessary groups
usermod -aG video,input,audio $USER_NAME

# Regenerate initramfs for all kernels with NVIDIA
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
echo "Kernels: linux, linux-lts, linux-zen, linux-hardened"
echo "Desktop: FULL KDE Plasma Suite + Hyprland"
echo "----------------------------------------"
echo "Reboot and remove installation media."
echo "At ly login, press F1 to choose:"
echo "- Plasma (X11/Wayland) for KDE"
echo "- Hyprland for tiling WM"
echo "----------------------------------------"