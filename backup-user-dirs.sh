#!/bin/bash

# Script to compress user directories and copy to SMB share
# Usage: ./backup-user-dirs.sh [--dry-run]

set -e  # Exit on any error

# Check for dry-run flag
DRY_RUN=false
if [ "$1" = "--dry-run" ] || [ "$1" = "-n" ]; then
    DRY_RUN=true
    echo -e "\033[1;33m*** DRY RUN MODE - No files will be compressed or copied ***\033[0m"
fi

USER_DIRS=("Documents" "Downloads" "Desktop")
SMB_MOUNT_POINT="/Volumes/storage1"
SMB_BACKUP_PATH="backup-user"
TEMP_DIR="/tmp/user-backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" = "" ]; then
        echo "0 bytes"
        return
    fi
    if [ $bytes -gt 1073741824 ]; then
        echo "$((bytes / 1073741824)) GB"
    elif [ $bytes -gt 1048576 ]; then
        echo "$((bytes / 1048576)) MB"
    elif [ $bytes -gt 1024 ]; then
        echo "$((bytes / 1024)) KB"
    else
        echo "$bytes bytes"
    fi
}

echo -e "${YELLOW}Starting backup of user directories...${NC}"

# Create temporary directory for archives
mkdir -p "$TEMP_DIR"
echo -e "${YELLOW}Using temporary directory: $TEMP_DIR${NC}"

# Only check SMB mount if not in dry-run mode
if [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}Checking SMB mount...${NC}"

    if [ ! -d "$SMB_MOUNT_POINT" ]; then
        echo -e "${RED}Error: SMB mount point $SMB_MOUNT_POINT does not exist${NC}"
        echo -e "${YELLOW}Please mount the SMB share first: mount -t smbfs -o guest smb://192.168.10.4/storage1 /Volumes/storage1${NC}"
        exit 1
    fi

    # Create backup directory path if it doesn't exist
    SMB_BACKUP_DIR="$SMB_MOUNT_POINT/$SMB_BACKUP_PATH"
    mkdir -p "$SMB_BACKUP_DIR"

    echo -e "${GREEN}Using existing SMB mount at $SMB_MOUNT_POINT${NC}"
    echo -e "${GREEN}Using backup directory: $SMB_BACKUP_DIR${NC}"
else
    echo -e "${YELLOW}Skipping SMB mount check (dry-run mode)${NC}"
    SMB_BACKUP_DIR="$SMB_MOUNT_POINT/$SMB_BACKUP_PATH"
fi

# First pass: Calculate total size of all directories
echo -e "${YELLOW}Calculating total size of directories...${NC}"
total_dirs=0
total_original_size=0
processed_size=0

for dir_name in "${USER_DIRS[@]}"; do
    dir="$HOME/$dir_name"
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}Measuring: $dir_name${NC}"

        # Calculate directory size
        dir_size=$(du -sk "$dir" | cut -f1)
        dir_size_bytes=$((dir_size * 1024))  # Convert KB to bytes

        total_original_size=$((total_original_size + dir_size_bytes))
        total_dirs=$((total_dirs + 1))
    else
        echo -e "${YELLOW}Warning: Directory $dir does not exist, skipping${NC}"
    fi
done

if [ $total_dirs -eq 0 ]; then
    echo -e "${RED}No user directories found${NC}"
    exit 1
fi

# Format total size
total_size_formatted=$(format_bytes $total_original_size)
echo -e "${GREEN}Found $total_dirs directories with total size: $total_size_formatted${NC}"

# Reset for processing
processed=0
processed_size=0

echo -e "${YELLOW}Starting backup process...${NC}"

# Process each user directory
for dir_name in "${USER_DIRS[@]}"; do
    dir="$HOME/$dir_name"
    if [ -d "$dir" ]; then
        archive_name="${dir_name}.tar.gz"
        temp_archive="$TEMP_DIR/$archive_name"
        current_dir=$((processed + 1))

        # Calculate original directory size
        original_size=$(du -sk "$dir" | cut -f1)
        original_size=$((original_size * 1024))  # Convert KB to bytes
        original_size_formatted=$(format_bytes $original_size)

        # Calculate progress percentage based on cumulative size
        if [ $total_original_size -gt 0 ]; then
            progress=$((processed_size * 100 / total_original_size))
        else
            progress=0
        fi

        echo -e "${YELLOW}Processing [$current_dir/$total_dirs] ($progress%): $dir_name${NC}"
        echo -e "  Size: ${original_size_formatted} ($(format_bytes $processed_size)/$(format_bytes $total_original_size))"

        # Check if backup already exists
        if [ -f "$SMB_BACKUP_DIR/$archive_name" ]; then
            echo -e "${GREEN}✓ Backup already exists: $archive_name${NC}"
            processed=$((processed + 1))
            processed_size=$((processed_size + original_size))
            echo "---"
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}  → Would compress to: $archive_name${NC}"
            echo -e "${YELLOW}  → Would copy to: $SMB_BACKUP_DIR/$archive_name${NC}"
            # Update totals for dry run
            processed=$((processed + 1))
            processed_size=$((processed_size + original_size))
        else
            # Create compressed archive
            if tar --numeric-owner -czf "$temp_archive" -C "$HOME" "$dir_name"; then
                echo -e "${GREEN}✓ Compressed: $dir_name${NC}"

                # Copy to SMB backup directory (without extended attributes, ignore permission errors)
                if cp -X "$temp_archive" "$SMB_BACKUP_DIR/" 2>/dev/null || [ -f "$SMB_BACKUP_DIR/$archive_name" ]; then
                    echo -e "${GREEN}✓ Copied to SMB: $archive_name${NC}"
                    processed=$((processed + 1))
                    processed_size=$((processed_size + original_size))
                else
                    echo -e "${RED}✗ Failed to copy $archive_name to SMB share${NC}"
                fi
            else
                echo -e "${RED}✗ Failed to compress $dir_name${NC}"
            fi

            # Remove temporary archive to save space
            rm -f "$temp_archive"
        fi

        echo "---"
    fi
done

# Cleanup
echo -e "${YELLOW}Cleaning up...${NC}"
rmdir "$TEMP_DIR" 2>/dev/null || true

echo -e "${GREEN}Backup completed!${NC}"
echo -e "${GREEN}Processed $processed out of $total_dirs directories${NC}"

if [ $processed -gt 0 ]; then
    echo -e "\n${YELLOW}=== BACKUP SUMMARY ===${NC}"
    total_original_formatted=$(format_bytes $total_original_size)
    echo -e "Total original size: ${total_original_formatted}"
    echo -e "Directories backed up: $processed"
fi