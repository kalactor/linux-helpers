#!/bin/bash

set -e

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD_WHITE='\033[1;37m'
NC='\033[0m'  # No Color

main() {
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

    mkfs.ext4 /dev/sdb4          # Format Linux filesystem partition as ext4

    echo "Partitioning and formatting complete on $selected_disk."

    # Mount partitions
    mount /dev/sdb4 /mnt

    #--------------------------------------------------------------------------------------------------------------------------------
    # Install base system and necessary packages
    pacstrap /mnt base base-devel linux linux-headers linux-firmware intel-ucode sudo git vim cmake make networkmanager ntfs-3g

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
    echo kallo > /etc/hostname

    echo "127.0.0.1    localhost" >> /etc/hosts
    echo "::1	   localhost" >> /etc/hosts
    echo "127.0.1.1    kallo.localdomain   kallo" >> /etc/hosts


    # Enable NetworkManager
    systemctl enable NetworkManager

    exit

    git clone https://github.com/kalactor/HyprMoni
    cd HyprMoni
    ./install.sh

EOF

}
#--------------------------------------------------------------------------------------------------------------------------------

main



# Unmount all partitions
umount -lR /mnt
