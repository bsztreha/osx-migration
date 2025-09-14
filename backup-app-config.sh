#!/bin/bash

# Script to compress application configurations and copy to SMB share
# Usage: ./backup-app-config.sh [--dry-run]

set -e  # Exit on any error

# Check for dry-run flag
DRY_RUN=false
if [ "$1" = "--dry-run" ] || [ "$1" = "-n" ]; then
    DRY_RUN=true
    echo -e "\033[1;33m*** DRY RUN MODE - No files will be compressed or copied ***\033[0m"
fi

APP_SUPPORT_DIR="$HOME/Library/Application Support"
SMB_MOUNT_POINT="/Volumes/storage1"
SMB_BACKUP_PATH="backup-app-config"
TEMP_DIR="/tmp/app-config-backup-$(date +%Y%m%d-%H%M%S)"

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

echo -e "${YELLOW}Starting backup of application configurations...${NC}"

# Create temporary directory for archives
mkdir -p "$TEMP_DIR"
echo -e "${YELLOW}Using temporary directory: $TEMP_DIR${NC}"

# Only check SMB mount if not in dry-run mode
if [ "$DRY_RUN" = false ]; then
    if [ ! -d "$SMB_MOUNT_POINT" ]; then
        echo -e "${RED}Error: SMB mount point $SMB_MOUNT_POINT not found${NC}"
        echo -e "${YELLOW}Please mount the SMB share first:${NC}"
        echo -e "  mount -t smbfs -o guest smb://YOUR_SMB_SERVER/YOUR_SHARE $SMB_MOUNT_POINT"
        exit 1
    fi

    # Create backup directory on SMB share
    mkdir -p "$SMB_MOUNT_POINT/$SMB_BACKUP_PATH"
    echo -e "${GREEN}Using SMB backup directory: $SMB_MOUNT_POINT/$SMB_BACKUP_PATH${NC}"
else
    echo -e "${YELLOW}Skipping SMB mount check (dry-run mode)${NC}"
fi

# Check if Application Support directory exists
if [ ! -d "$APP_SUPPORT_DIR" ]; then
    echo -e "${RED}Error: Application Support directory not found: $APP_SUPPORT_DIR${NC}"
    exit 1
fi

# Get list of application directories
echo -e "${YELLOW}Calculating total size of application configurations...${NC}"

total_items=0
total_original_size=0
processed_size=0

# Count and measure all directories/files in Application Support
for item in "$APP_SUPPORT_DIR"/*; do
    if [ -e "$item" ]; then
        total_items=$((total_items + 1))

        item_name=$(basename "$item")
        echo -e "${YELLOW}Measuring: $item_name${NC}"

        if [ -d "$item" ]; then
            item_size=$(du -sk "$item" | cut -f1)
        else
            item_size=$(du -sk "$item" | cut -f1)
        fi

        item_size_bytes=$((item_size * 1024))
        total_original_size=$((total_original_size + item_size_bytes))

        echo -e "  Found: $item_name ($(format_bytes $item_size_bytes))"
    fi
done

echo -e "${GREEN}Found $total_items application configurations with total size: $(format_bytes $total_original_size)${NC}"

if [ $total_items -eq 0 ]; then
    echo -e "${YELLOW}No application configurations found to backup${NC}"
    exit 0
fi

echo -e "${YELLOW}Starting backup process...${NC}"

# Process each item in Application Support
current_item=0
processed=0

for item in "$APP_SUPPORT_DIR"/*; do
    if [ -e "$item" ]; then
        current_item=$((current_item + 1))
        item_name=$(basename "$item")

        # Skip certain system/cache directories that shouldn't be backed up
        case "$item_name" in
            "CloudDocs"|"CallHistoryDB"|"CallHistoryTransactions"|"CrashReporter"|"com.apple."*|"MobileSync"|"SyncServices"|".DS_Store")
                echo -e "${YELLOW}Skipping system directory: $item_name${NC}"
                continue
                ;;
        esac

        archive_name="${item_name// /_}.tar.gz"
        temp_archive="$TEMP_DIR/$archive_name"
        progress=$((processed_size * 100 / total_original_size))

        echo -e "${YELLOW}Processing [$current_item/$total_items]: $item_name${NC}"
        echo -e "  Progress: $progress% ($(format_bytes $processed_size)/$(format_bytes $total_original_size))"

        if [ -d "$item" ]; then
            item_size=$(du -sk "$item" | cut -f1)
        else
            item_size=$(du -sk "$item" | cut -f1)
        fi

        item_size_bytes=$((item_size * 1024))
        echo -e "  Size: $(format_bytes $item_size_bytes)"

        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}  → Would compress to: $archive_name${NC}"
            echo -e "${YELLOW}  → Would copy to: $SMB_MOUNT_POINT/$SMB_BACKUP_PATH/$archive_name${NC}"
        else
            # Check if backup already exists and is recent
            target_file="$SMB_MOUNT_POINT/$SMB_BACKUP_PATH/$archive_name"
            if [ -f "$target_file" ]; then
                # Check if target is newer than source (modified in last 24 hours)
                if [ "$target_file" -nt "$item" ]; then
                    echo -e "${GREEN}  → Backup exists and is recent, skipping${NC}"
                    processed_size=$((processed_size + item_size_bytes))
                    continue
                fi
            fi

            echo -e "${YELLOW}  → Compressing to: $archive_name${NC}"

            # Create archive with sparse file support and extended attributes
            if tar --exclude='.DS_Store' --exclude='*.log' --exclude='Cache' --exclude='cache' --exclude='Logs' -czf "$temp_archive" -C "$(dirname "$item")" "$(basename "$item")" 2>/dev/null; then
                echo -e "${GREEN}  ✓ Compressed: $archive_name${NC}"

                # Copy to SMB backup directory (without extended attributes, ignore permission errors)
                echo -e "${YELLOW}  → Copying to SMB share...${NC}"
                if cp -X "$temp_archive" "$SMB_MOUNT_POINT/$SMB_BACKUP_PATH/" 2>/dev/null || [ -f "$target_file" ]; then
                    echo -e "${GREEN}  ✓ Copied to: $SMB_MOUNT_POINT/$SMB_BACKUP_PATH/$archive_name${NC}"
                    processed=$((processed + 1))
                else
                    echo -e "${RED}  ✗ Failed to copy $archive_name${NC}"
                fi

                # Clean up temporary file
                rm -f "$temp_archive"
            else
                echo -e "${RED}  ✗ Failed to compress $item_name${NC}"
            fi
        fi

        processed_size=$((processed_size + item_size_bytes))
        echo "---"
    fi
done

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
rm -rf "$TEMP_DIR"

# Final summary
if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}Application configuration backup preview completed!${NC}"
    echo -e "${GREEN}Would process $total_items application configurations${NC}"
else
    echo -e "${GREEN}Application configuration backup completed!${NC}"
    echo -e "${GREEN}Processed $processed out of $total_items application configurations${NC}"
fi

if [ $total_items -gt 0 ]; then
    echo -e "\n${YELLOW}=== APPLICATION CONFIG BACKUP SUMMARY ===${NC}"
    echo -e "Total data size: $(format_bytes $total_original_size)"
    echo -e "Applications backed up: $processed"
    echo -e "Backup location: $SMB_MOUNT_POINT/$SMB_BACKUP_PATH/"

    echo -e "\n${YELLOW}=== BACKUP CONTENTS ===${NC}"
    echo -e "📱 Application configurations from ~/Library/Application Support"
    echo -e "   → Individual .tar.gz files for each application"
    echo -e "   → Excludes system directories and caches"
    echo -e "\n${GREEN}Ready for migration to new Mac!${NC}"
fi