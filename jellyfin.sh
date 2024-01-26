#!/bin/bash

# Check for sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[1;31mPlease run this script with sudo: sudo $0\e[0m"
    exit 1
fi

if grep -qi "ubuntu" /etc/os-release; then
    # Update packages
    sudo apt update

    # Upgrade the system
    sudo apt full-upgrade

    # Install required packages
    sudo apt install apt-transport-https ca-certificates curl -y

    # Download the Jellyfin repository key
    curl -fsSL https://repo.jellyfin.org/ubuntu/jellyfin_team.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/jellyfin.gpg > /dev/null

    # Add the Jellyfin repository
    echo "deb [arch=$( dpkg --print-architecture )] https://repo.jellyfin.org/$( awk -F'=' '/^ID=/{ print $NF }' /etc/os-release ) $( awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release ) main" | sudo tee /etc/apt/sources.list.d/jellyfin.list

    # Update packages
    sudo apt update

    # Install Jellyfin
    sudo apt install -y jellyfin

    # Start Service
    sudo systemctl start jellyfin

    # Enable Service
    sudo systemctl enable jellyfin
    
elif grep -qi "Debian" /etc/os-release || grep -qi "Raspbian" /etc/os-release; then

    # Update packages
    sudo apt update

    # Upgrade the system
    sudo apt full-upgrade
    
    # Install required packages
    sudo apt install apt-transport-https lsb-release
    
    # Download the Jellyfin repository key
    curl https://repo.jellyfin.org/debian/jellyfin_team.gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/jellyfin-archive-keyring.gpg >/dev/null
    
    # Add the Jellyfin repository
    echo "deb [signed-by=/usr/share/keyrings/jellyfin-archive-keyring.gpg arch=$( dpkg --print-architecture )] https://repo.jellyfin.org/debian $( lsb_release -c -s ) main" | sudo tee /etc/apt/sources.list.d/jellyfin.list
    
    # Update packages
    sudo apt update
    
    # Install Jellyfin
    sudo apt install jellyfin -y
else
    echo "Unsupported operating system."
    exit 1
fi

# Ask if you want to mount a hard drive
read -rp "Do you want to mount a hard drive? (y/n): " mount_option

if [[ "$mount_option" =~ ^[Yy]$ ]]; then
    echo "Searching for available hard drives..."

    # Get a list of eligible drives (exclude loop devices and drives with specific LABELs)
    eligible_drives=$(sudo blkid | awk -F: '!/LABEL_FATBOOT=|LABEL=rootfs|TYPE="squashfs"/ && /^\/dev\/sd/{print $1}')

    if [ -z "$eligible_drives" ]; then
        echo "No eligible hard drives found."
        exit 1
    fi

    # Display detected hard drives with numbering
    echo "Detected hard drives:"
    count=1
    while IFS= read -r line; do
        drive_path=$(echo "$line" | awk '{print $1}')
        drive_label=$(blkid -s LABEL -o value "$drive_path")
        drive_type=$(blkid -s TYPE -o value "$drive_path")
        drive_size=$(lsblk -n -o SIZE "$drive_path")
        echo "$count) $drive_path: LABEL=\"$drive_label\" TYPE=\"$drive_type\" SIZE=\"$drive_size\""
        ((count++))
    done <<< "$eligible_drives"

    # Prompt for the drive selection
    read -rp "Enter the number of the drive to mount: " drive_number

    # Validate drive number
    if [[ ! "$drive_number" =~ ^[0-9]+$ || "$drive_number" -le 0 || "$drive_number" -gt $(echo "$eligible_drives" | wc -l) ]]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi

    # Extract information from the selected drive
    selected_drive=$(echo "$eligible_drives" | sed -n "${drive_number}p")
    drive_path=$(echo "$selected_drive" | awk '{print $1}')
    drive_label=$(blkid -s LABEL -o value "$drive_path")
    drive_uuid=$(blkid -s UUID -o value "$drive_path")
    drive_type=$(blkid -s TYPE -o value "$drive_path")

    # Prompt for the mount point
    read -rp "Enter the mount point (e.g., /mnt/exHD): " mount_point

    # Create the directory for the mount point
    sudo mkdir -p "$mount_point"

    # Add comment for the drive to /etc/fstab
    drive_comment="# Mount HD $drive_label"

    # Add entry to /etc/fstab
    echo -e "\n$drive_comment\nUUID=$drive_uuid\t$mount_point\t$drive_type\tdefaults,nofail\t0\t2" | sudo tee -a /etc/fstab

    # Mount the drive
    sudo mount -t "$drive_type" "$drive_path" "$mount_point"

    echo "Drive successfully mounted and added to /etc/fstab."
else
    echo "Skipping drive mount."
fi

