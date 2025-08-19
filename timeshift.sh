#!/bin/bash

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi

# Check if timeshift is installed
if ! command -v timeshift >/dev/null 2>&1; then
  echo "Timeshift is not installed. Please install it first:"
  echo "  sudo pacman -S timeshift"
  exit 1
fi

echo "Arch Linux Timeshift Backup & Restore"
echo "Choose option:"
echo "1) Backup (Create Snapshot)"
echo "2) Restore (Restore Snapshot)"
read -p "Enter 1 or 2: " CHOICE

case $CHOICE in
  1)
    echo "Creating snapshot with Timeshift..."
    timeshift --create --comments "Manual backup $(date '+%Y-%m-%d %H:%M:%S')" --tags D
    if [ $? -eq 0 ]; then
      echo "Backup successful."
    else
      echo "Backup failed."
    fi
    ;;
  2)
    echo "Available snapshots:"
    timeshift --list
    read -p "Enter snapshot number to restore: " SNAP_NUM

    # Get snapshot name to restore from snapshot number input
    SNAP_NAME=$(timeshift --list | awk -v num="$SNAP_NUM" 'NR==num+2 {print $2}')

    if [ -z "$SNAP_NAME" ]; then
      echo "Invalid snapshot number."
      exit 1
    fi

    echo "You have selected snapshot: $SNAP_NAME"
    read -p "Are you sure you want to restore this snapshot? This will overwrite current system! [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
      echo "Restoring snapshot..."
      timeshift --restore --snapshot "$SNAP_NAME" --yes
      echo "Restore process finished. Please reboot your system."
    else
      echo "Restore cancelled."
    fi
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac
