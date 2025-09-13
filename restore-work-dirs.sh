#!/bin/bash

# Script to restore compressed directories from SMB share to ~/work
# Usage: ./restore-work-dirs.sh [--dry-run] [--list] [directory-name]

set -e  # Exit on any error

# Check for flags and arguments
DRY_RUN=false
LIST_ONLY=false
SPECIFIC_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            echo -e "\033[1;33m*** DRY RUN MODE - No files will be extracted ***\033[0m"
            shift
            ;;
        --list|-l)
            LIST_ONLY=true
            shift
            ;;
        *)
            SPECIFIC_DIR="$1"
            shift
            ;;
    esac
done

WORK_DIR="$HOME/work"
SMB_MOUNT_POINT="/Volumes/storage1"
SMB_BACKUP_PATH="backup-work"
TEMP_DIR="/tmp/work-restore-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting restore of work directories...${NC}"

# Check current user UID/GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USER=$(id -un)

echo -e "${YELLOW}Current user info:${NC}"
echo -e "  User: $CURRENT_USER"
echo -e "  UID: $CURRENT_UID"
echo -e "  GID: $CURRENT_GID"

# Check if SMB share is mounted and accessible
if [ ! -d "$SMB_MOUNT_POINT" ]; then
    echo -e "${RED}Error: SMB mount point $SMB_MOUNT_POINT does not exist${NC}"
    echo -e "${YELLOW}Please mount the SMB share first: mount -t smbfs -o guest smb://192.168.10.4/storage1 /Volumes/storage1${NC}"
    exit 1
fi

SMB_BACKUP_DIR="$SMB_MOUNT_POINT/$SMB_BACKUP_PATH"

if [ ! -d "$SMB_BACKUP_DIR" ]; then
    echo -e "${RED}Error: Backup directory $SMB_BACKUP_DIR does not exist${NC}"
    exit 1
fi

echo -e "${GREEN}Using backup directory: $SMB_BACKUP_DIR${NC}"

# Create work directory if it doesn't exist
if [ "$DRY_RUN" = false ] && [ "$LIST_ONLY" = false ]; then
    mkdir -p "$WORK_DIR"
    echo -e "${GREEN}Work directory: $WORK_DIR${NC}"
fi

# Find all backup archives
if [ -n "$SPECIFIC_DIR" ]; then
    # Look for specific directory
    ARCHIVE_FILE="$SMB_BACKUP_DIR/${SPECIFIC_DIR}.tar.gz"
    if [ -f "$ARCHIVE_FILE" ]; then
        ARCHIVES=("$ARCHIVE_FILE")
    else
        echo -e "${RED}Error: Archive for '$SPECIFIC_DIR' not found: $ARCHIVE_FILE${NC}"
        exit 1
    fi
else
    # Find all .tar.gz files in backup directory
    ARCHIVES=($(find "$SMB_BACKUP_DIR" -name "*.tar.gz" -type f))
fi

if [ ${#ARCHIVES[@]} -eq 0 ]; then
    echo -e "${RED}No backup archives found in $SMB_BACKUP_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Found ${#ARCHIVES[@]} backup archive(s)${NC}"

# List mode - just show available backups
if [ "$LIST_ONLY" = true ]; then
    echo -e "\n${YELLOW}Available backup archives:${NC}"
    for archive in "${ARCHIVES[@]}"; do
        archive_name=$(basename "$archive")
        dir_name="${archive_name%.tar.gz}"
        archive_size=$(du -h "$archive" | cut -f1)
        echo -e "  ${GREEN}$dir_name${NC} (${archive_size})"
    done
    exit 0
fi

# Create temporary directory for extraction
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$TEMP_DIR"
    echo -e "${YELLOW}Using temporary directory: $TEMP_DIR${NC}"
fi

# Process each archive
processed=0
total_archives=${#ARCHIVES[@]}

for archive in "${ARCHIVES[@]}"; do
    archive_name=$(basename "$archive")
    dir_name="${archive_name%.tar.gz}"
    current_archive=$((processed + 1))

    # Calculate progress percentage
    progress=$((current_archive * 100 / total_archives))

    echo -e "${YELLOW}Processing [$current_archive/$total_archives] ($progress%): $dir_name${NC}"

    # Check if directory already exists
    target_dir="$WORK_DIR/$dir_name"
    if [ -d "$target_dir" ]; then
        echo -e "${YELLOW}  Warning: Directory $target_dir already exists${NC}"
        if [ "$DRY_RUN" = false ]; then
            read -p "  Overwrite? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}  Skipping $dir_name${NC}"
                echo "---"
                continue
            fi
            rm -rf "$target_dir"
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        archive_size=$(du -h "$archive" | cut -f1)
        echo -e "${YELLOW}  → Would extract: $archive_name (${archive_size})${NC}"
        echo -e "${YELLOW}  → Would create: $target_dir${NC}"
        processed=$((processed + 1))
    else
        # Extract archive (don't preserve original ownership, assign to current user)
        echo -e "  Extracting: $archive_name"
        if tar --no-same-owner -xzf "$archive" -C "$WORK_DIR"; then
            echo -e "${GREEN}✓ Extracted: $dir_name${NC}"

            # Fix ownership to current user (handles UID mismatch between machines)
            echo -e "  Fixing file ownership..."
            if [ -d "$target_dir" ]; then
                chown -R "$CURRENT_USER:staff" "$target_dir" 2>/dev/null || true
                echo -e "${GREEN}  → File ownership updated for UID $CURRENT_UID${NC}"
            fi

            processed=$((processed + 1))
        else
            echo -e "${RED}✗ Failed to extract $archive_name${NC}"
        fi
    fi

    echo "---"
done

# Cleanup
if [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}Cleaning up...${NC}"
    rmdir "$TEMP_DIR" 2>/dev/null || true
fi

echo -e "${GREEN}Restore completed!${NC}"
echo -e "${GREEN}Processed $processed out of $total_archives archives${NC}"

if [ $processed -gt 0 ]; then
    echo -e "\n${YELLOW}=== RESTORE SUMMARY ===${NC}"
    echo -e "Archives restored: $processed"
    if [ "$DRY_RUN" = false ]; then
        echo -e "Restored to: $WORK_DIR"
    fi
fi