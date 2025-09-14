#!/bin/bash

# Script to backup migration-safe items from Intel Mac to ARM Mac
# Usage: ./backup-migration.sh [--dry-run]

set -e  # Exit on any error

# Check for dry-run flag
DRY_RUN=false
if [ "$1" = "--dry-run" ] || [ "$1" = "-n" ]; then
    DRY_RUN=true
    echo -e "\033[1;33m*** DRY RUN MODE - No files will be compressed or copied ***\033[0m"
fi

SMB_MOUNT_POINT="/Volumes/storage1"
SMB_BACKUP_PATH="backup-migration"
TEMP_DIR="/tmp/migration-backup-$(date +%Y%m%d-%H%M%S)"

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

# Define migration categories using regular variables (compatible with bash 3.2)
# Note: user-dirs (Documents, Downloads, Desktop) are handled by backup-user-dirs.sh
CATEGORIES=("shell-config" "credentials" "git-config" "network-config")

# Shell configuration
shell_config=".oh-my-zsh .zshrc .zprofile"

# Credentials and keys
credentials=".ssh .aws .gnupg .boto"

# Git configuration
git_config=".gitconfig .gitignore_global .hgignore_global"

# Network configurations
network_config=".cisco"

# Function to get category items by name
get_category_items() {
    local category=$1
    case "$category" in
        "shell-config") echo "$shell_config" ;;
        "credentials") echo "$credentials" ;;
        "git-config") echo "$git_config" ;;
        "network-config") echo "$network_config" ;;
        *) echo "" ;;
    esac
}

echo -e "${YELLOW}Starting Intel to ARM Mac migration backup...${NC}"

# Check current user UID/GID and warn about potential migration issues
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USER=$(id -un)

echo -e "${YELLOW}Current user info:${NC}"
echo -e "  User: $CURRENT_USER"
echo -e "  UID: $CURRENT_UID"
echo -e "  GID: $CURRENT_GID"

if [ $CURRENT_UID -ne 501 ]; then
    echo -e "${YELLOW}⚠️  WARNING: Your UID is $CURRENT_UID, not 501${NC}"
    echo -e "${YELLOW}   On the M4 Mac, if you're the first user, you'll get UID 501${NC}"
    echo -e "${YELLOW}   The restore script will handle ownership changes automatically${NC}"
fi

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

# First pass: Calculate total size of all items
echo -e "${YELLOW}Calculating total size of migration items...${NC}"
total_categories=0
total_original_size=0
processed_size=0

for category in "${CATEGORIES[@]}"; do
    items="$(get_category_items "$category")"

    echo -e "${YELLOW}Measuring category: $category${NC}"
    category_size=0

    for item in $items; do
        # Config items are in home root
        path="$HOME/$item"

        if [ -e "$path" ]; then
            if [ -d "$path" ]; then
                item_size=$(du -sk "$path" | cut -f1)
            else
                item_size=$(du -sk "$path" | cut -f1)
            fi
            item_size_bytes=$((item_size * 1024))
            category_size=$((category_size + item_size_bytes))
            echo -e "  Found: $item ($(format_bytes $item_size_bytes))"
        else
            echo -e "  Missing: $item (skipping)"
        fi
    done

    if [ $category_size -gt 0 ]; then
        total_original_size=$((total_original_size + category_size))
        total_categories=$((total_categories + 1))
        echo -e "${GREEN}Category $category total: $(format_bytes $category_size)${NC}"
    fi
    echo "---"
done

if [ $total_categories -eq 0 ]; then
    echo -e "${RED}No migration items found${NC}"
    exit 1
fi

# Format total size
total_size_formatted=$(format_bytes $total_original_size)
echo -e "${GREEN}Found $total_categories categories with total size: $total_size_formatted${NC}"

# Reset for processing
processed=0
processed_size=0

echo -e "${YELLOW}Starting backup process...${NC}"

# Process each category
for category in "${CATEGORIES[@]}"; do
    items="$(get_category_items "$category")"
    archive_name="${category}.tar.gz"
    temp_archive="$TEMP_DIR/$archive_name"
    current_category=$((processed + 1))

    echo -e "${YELLOW}Processing [$current_category/$total_categories]: $category${NC}"

    # Calculate progress percentage based on cumulative size
    if [ $total_original_size -gt 0 ]; then
        progress=$((processed_size * 100 / total_original_size))
    else
        progress=0
    fi

    echo -e "  Progress: $progress% ($(format_bytes $processed_size)/$(format_bytes $total_original_size))"

    # Check if backup already exists
    if [ -f "$SMB_BACKUP_DIR/$archive_name" ]; then
        echo -e "${GREEN}✓ Backup already exists: $archive_name${NC}"

        # Calculate category size for progress
        category_size=0
        for item in $items; do
            path="$HOME/$item"
            if [ -e "$path" ]; then
                if [ -d "$path" ]; then
                    item_size=$(du -sk "$path" | cut -f1)
                else
                    item_size=$(du -sk "$path" | cut -f1)
                fi
                category_size=$((category_size + $(($item_size * 1024))))
            fi
        done

        processed=$((processed + 1))
        processed_size=$((processed_size + category_size))
        echo "---"
        continue
    fi

    # Collect existing items for this category
    items_to_backup=()
    category_size=0

    for item in $items; do
        path="$HOME/$item"
        if [ -e "$path" ]; then
            items_to_backup+=("$item")
            if [ -d "$path" ]; then
                item_size=$(du -sk "$path" | cut -f1)
            else
                item_size=$(du -sk "$path" | cut -f1)
            fi
            category_size=$((category_size + $(($item_size * 1024))))
        fi
    done

    if [ ${#items_to_backup[@]} -eq 0 ]; then
        echo -e "${YELLOW}No items found for category: $category${NC}"
        echo "---"
        continue
    fi

    echo -e "  Items: ${items_to_backup[*]}"
    echo -e "  Size: $(format_bytes $category_size)"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}  → Would compress to: $archive_name${NC}"
        echo -e "${YELLOW}  → Would copy to: $SMB_BACKUP_DIR/$archive_name${NC}"
        processed=$((processed + 1))
        processed_size=$((processed_size + category_size))
    else
        # Create compressed archive
        echo -e "  Creating archive..."

        # Create tar command with items that exist (preserve numeric ownership)
        if tar --numeric-owner -czf "$temp_archive" -C "$HOME" "${items_to_backup[@]}" 2>/dev/null; then
            echo -e "${GREEN}✓ Compressed: $category${NC}"

            # Copy to SMB backup directory (without extended attributes, ignore permission errors)
            if cp -X "$temp_archive" "$SMB_BACKUP_DIR/" 2>/dev/null || [ -f "$SMB_BACKUP_DIR/$archive_name" ]; then
                echo -e "${GREEN}✓ Copied to SMB: $archive_name${NC}"
                processed=$((processed + 1))
                processed_size=$((processed_size + category_size))
            else
                echo -e "${RED}✗ Failed to copy $archive_name to SMB share${NC}"
            fi
        else
            echo -e "${RED}✗ Failed to compress $category${NC}"
        fi

        # Remove temporary archive to save space
        rm -f "$temp_archive"
    fi

    echo "---"
done

# Cleanup
echo -e "${YELLOW}Cleaning up...${NC}"
rmdir "$TEMP_DIR" 2>/dev/null || true

echo -e "${GREEN}Migration backup completed!${NC}"
echo -e "${GREEN}Processed $processed out of $total_categories categories${NC}"

if [ $processed -gt 0 ]; then
    echo -e "\n${YELLOW}=== MIGRATION BACKUP SUMMARY ===${NC}"
    echo -e "Total data size: $(format_bytes $total_original_size)"
    echo -e "Categories backed up: $processed"
    echo -e "\n${YELLOW}=== BACKUP CONTENTS ===${NC}"
    echo -e "🔧 shell-config.tar.gz  - Oh My Zsh, .zshrc, .zprofile"
    echo -e "🔑 credentials.tar.gz   - SSH keys, AWS, GPG, etc."
    echo -e "🔧 git-config.tar.gz    - Git configuration files"
    echo -e "🌐 network-config.tar.gz - Cisco VPN configurations"
    echo -e "\n${GREEN}Ready for Intel → ARM Mac migration!${NC}"
fi