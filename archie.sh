#!/bin/bash

set -e

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD_WHITE='\033[1;37m'
NC='\033[0m'  # No Color

# Display banner
echo -e "           ${RED}**************************************************${NC}"
echo -e "           ${RED}*                                                *${NC}"
echo -e "           ${RED}*       ${BOLD_WHITE}WELCOME TO THE ARCH LINUX INSTALLER!${RED}       *${NC}"
echo -e "           ${RED}*                                                *${NC}"
echo -e "           ${RED}**************************************************${NC}"
echo -e "           ${RED}*              ${GREEN}created by Amit Kumar${RED}              *${NC}"
echo -e "           ${RED}**************************************************${NC}"


# Sync and install necessary packages
pacman -Sy archlinux-keyring --noconfirm

#--------------------------------------------------------------------------------------------------------------------------------

# List available disks with sizes
echo "Available disks:"
declare -a disks
declare -a sizes
i=1
while read -r disk size; do
    echo "$i) /dev/$disk ($size)"
    disks[$i]="$disk"
    sizes[$i]="$size"
    ((i++))
done < <(lsblk -d -n -o NAME,SIZE | grep -E '^(sd|nvme|vd)')

# Define default disk as /dev/sdb
default_disk="/dev/sdb"
default_disk_size="223.6G"
default_index=""

# Look for the default disk in the list
for index in "${!disks[@]}"; do
    if [ "/dev/${disks[$index]}" == "$default_disk" ] && [ "${sizes[$index]}" == $default_disk_size ]; then
        default_index=$index
        break
    fi
done

selected_disk="/dev/${disks[$default_index]}"
echo "You have selected $selected_disk of size ${sizes[$default_index]}."

# Warning before proceeding
echo -e "\nWARNING: ALL DATA on $selected_disk will be erased."
echo
sleep 5

# Determine partition naming scheme (for NVMe devices)
if [[ "$selected_disk" =~ nvme ]]; then
    part1="${selected_disk}p1"
    part2="${selected_disk}p2"
    part3="${selected_disk}p3"
    part4="${selected_disk}p4"
else
    part1="${selected_disk}1"
    part2="${selected_disk}2"
    part3="${selected_disk}3"
    part4="${selected_disk}4"
fi

# Create a new GPT partition table to remove existing partitions
sudo parted -s "$selected_disk" mklabel gpt

# Create partitions using parted
# Partition 1: 1GB EFI System Partition (from 1MiB to 1025MiB)
parted -s "$selected_disk" mkpart primary fat32 1MiB 1025MiB
parted -s "$selected_disk" set 1 esp on

# Partition 2: 4GB Linux swap partition (from 1025MiB to 5121MiB)
parted -s "$selected_disk" mkpart primary linux-swap 1025MiB 5121MiB

# Partition 3: Linux filesystem partition (from 5121MiB to the end of the disk)
parted -s "$selected_disk" mkpart primary ext4 5121MiB 125953MiB

# Partition 4: Linux filesystem partition (from 5121MiB to the end of the disk)
parted -s "$selected_disk" mkpart primary ext4 125953MiB 100%

# Pause briefly to allow the kernel to recognize the changes
sleep 2

# Format the partitions
mkfs.fat -F32 "$part1"      # Format EFI partition as FAT32
mkswap "$part2"             # Prepare swap partition
mkfs.ext4 "$part3"          # Format Linux filesystem partition as ext4
mkfs.ext4 "$part4"          # Format Linux filesystem partition as ext4

echo "Partitioning and formatting complete on $selected_disk."

# Mount partitions
mount $part3 /mnt
mkdir -p /mnt/boot
mount $part1 /mnt/boot

# Enable swap
swapon $part2
#--------------------------------------------------------------------------------------------------------------------------------
# Install base system and necessary packages
pacstrap /mnt base base-devel linux linux-headers linux-firmware intel-ucode sudo git vim cmake make networkmanager cargo gcc ntfs-3g

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

echo "Entering chroot ##################################################"

#--------------------------------------------------------------------------------------------------------------------------------

# Change root to the new system
arch-chroot /mnt /bin/bash <<EOF

# Set root password
echo "root:moni" | chpasswd

# Add user amit and set password
useradd -m -g users -G wheel,storage,video,audio -s /bin/bash amit
echo "amit:root" | chpasswd

# Grant sudo permissions to amit
echo "Editing the sudoers file."
sed -i "/^# %wheel ALL=(ALL:ALL) ALL/c\%wheel ALL=(ALL:ALL) ALL" /etc/sudoers
if ! visudo -c; then
    echo "Error: Invalid syntax in /etc/sudoers. Aborting!"
    exit 1
fi

# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

# setting automatic time upate
timedatectl set-ntp true

# Configure locale
#echo "en_IN.UTF-8 UTF-8" >> /etc/locale.gen
sed -i "/^#en_IN UTF-8/c\en_IN UTF-8" /etc/locale.gen
locale-gen
echo "LANG=en_IN.UTF-8" > /etc/locale.conf

# Set Keymap
echo "KEYMAP=us" > /etc/vconsole.conf

# Set hostname
echo kali > /etc/hostname

echo "127.0.0.1    localhost" >> /etc/hosts
echo "::1	   localhost" >> /etc/hosts
echo "127.0.1.1    kali.localdomain   kali" >> /etc/hosts

# Configure GRUB and dual boot
pacman -S --noconfirm grub efibootmgr dosfstools mtools os-prober
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

if [ -f /etc/default/grub ]; then
	sudo sed -i "/^#GRUB_DISABLE_OS_PROBER=false/c\GRUB_DISABLE_OS_PROBER=false" /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

exit

EOF

#--------------------------------------------------------------------------------------------------------------------------------

# Unmount all partitions
umount -lR /mnt