#!/bin/bash

# Script to restore application configurations from SMB share to ~/Library/Application Support
# Usage: ./restore-app-config.sh [--dry-run] [--list] [app-name]

set -e  # Exit on any error

# Check for flags and arguments
DRY_RUN=false
LIST_ONLY=false
SPECIFIC_APP=""

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
            SPECIFIC_APP="$1"
            shift
            ;;
    esac
done

APP_SUPPORT_DIR="$HOME/Library/Application Support"
SMB_MOUNT_POINT="/Volumes/storage1"
SMB_BACKUP_PATH="backup-app-config"
TEMP_DIR="/tmp/app-config-restore-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting restore of application configurations...${NC}"

# Check current user UID/GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USER=$(id -un)

echo -e "${YELLOW}Current user info:${NC}"
echo -e "  User: $CURRENT_USER"
echo -e "  UID: $CURRENT_UID"
echo -e "  GID: $CURRENT_GID"

# Check if SMB share is mounted
if [ ! -d "$SMB_MOUNT_POINT" ]; then
    echo -e "${RED}Error: SMB mount point $SMB_MOUNT_POINT not found${NC}"
    echo -e "${YELLOW}Please mount the SMB share first:${NC}"
    echo -e "  mount -t smbfs -o guest smb://YOUR_SMB_SERVER/YOUR_SHARE $SMB_MOUNT_POINT"
    exit 1
fi

# Check if backup directory exists
BACKUP_DIR="$SMB_MOUNT_POINT/$SMB_BACKUP_PATH"
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}Error: Backup directory not found: $BACKUP_DIR${NC}"
    echo -e "${YELLOW}Please run backup-app-config.sh first${NC}"
    exit 1
fi

echo -e "${GREEN}Using backup directory: $BACKUP_DIR${NC}"

# Get list of available archives
if [ -n "$SPECIFIC_APP" ]; then
    ARCHIVE_PATTERN="${SPECIFIC_APP}*.tar.gz"
else
    ARCHIVE_PATTERN="*.tar.gz"
fi

ARCHIVES=("$BACKUP_DIR"/$ARCHIVE_PATTERN)

# Check if any archives exist
if [ ! -e "${ARCHIVES[0]}" ]; then
    if [ -n "$SPECIFIC_APP" ]; then
        echo -e "${RED}Error: No backup found for application: $SPECIFIC_APP${NC}"
        echo -e "${YELLOW}Available applications:${NC}"
        for archive in "$BACKUP_DIR"/*.tar.gz; do
            if [ -f "$archive" ]; then
                app_name=$(basename "$archive" .tar.gz)
                echo -e "  ${GREEN}$app_name${NC}"
            fi
        done
    else
        echo -e "${RED}Error: No application configuration backups found${NC}"
    fi
    exit 1
fi

# Count archives
total_archives=0
for archive in "${ARCHIVES[@]}"; do
    if [ -f "$archive" ]; then
        total_archives=$((total_archives + 1))
    fi
done

echo -e "${YELLOW}Found $total_archives application configuration archive(s)${NC}"

# If list mode, show available archives
if [ "$LIST_ONLY" = true ]; then
    echo -e "\n${YELLOW}Available application configuration archives:${NC}"
    for archive in "${ARCHIVES[@]}"; do
        if [ -f "$archive" ]; then
            archive_name=$(basename "$archive")
            app_name="${archive_name%.tar.gz}"
            app_name=$(echo "$app_name" | sed 's/_/ /g')  # Convert underscores back to spaces
            archive_size=$(du -h "$archive" | cut -f1)
            echo -e "  ${GREEN}$app_name${NC} (${archive_size})"
        fi
    done
    echo -e "\n${YELLOW}Usage examples:${NC}"
    echo -e "  ./restore-app-config.sh --dry-run              # Preview all"
    echo -e "  ./restore-app-config.sh \"Visual Studio Code\"   # Restore specific app"
    echo -e "  ./restore-app-config.sh Firefox               # Restore Firefox config"
    exit 0
fi

# Create temporary directory for extraction
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$TEMP_DIR"
    echo -e "${YELLOW}Using temporary directory: $TEMP_DIR${NC}"
else
    echo -e "${YELLOW}Skipping temporary directory creation (dry-run mode)${NC}"
fi

# Create Application Support directory if it doesn't exist
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$APP_SUPPORT_DIR"
fi

# Process each archive
current_archive=0
processed=0

for archive in "${ARCHIVES[@]}"; do
    if [ -f "$archive" ]; then
        current_archive=$((current_archive + 1))
        archive_name=$(basename "$archive")
        app_name="${archive_name%.tar.gz}"
        app_display_name=$(echo "$app_name" | sed 's/_/ /g')  # Convert underscores back to spaces
        progress=$((current_archive * 100 / total_archives))

        echo -e "${YELLOW}Processing [$current_archive/$total_archives] ($progress%): $app_display_name${NC}"

        if [ "$DRY_RUN" = true ]; then
            archive_size=$(du -h "$archive" | cut -f1)
            echo -e "${YELLOW}  → Would extract: $archive_name ($archive_size)${NC}"
            echo -e "${YELLOW}  → Contents:${NC}"
            tar -tzf "$archive" 2>/dev/null | head -10 | while read -r item; do
                echo -e "${YELLOW}    $item${NC}"
            done

            # Show if there are more files
            total_files=$(tar -tzf "$archive" 2>/dev/null | wc -l)
            if [ $total_files -gt 10 ]; then
                remaining=$((total_files - 10))
                echo -e "${YELLOW}    ... and $remaining more files${NC}"
            fi
        else
            # Check for potential conflicts
            conflicts=false
            conflict_items=()

            # Check what would be extracted
            if tar -tzf "$archive" 2>/dev/null | while read -r item; do
                target_path="$APP_SUPPORT_DIR/$item"
                if [ -e "$target_path" ]; then
                    echo "$item"
                fi
            done | head -5 > "$TEMP_DIR/conflicts_${app_name}.txt"; then
                if [ -s "$TEMP_DIR/conflicts_${app_name}.txt" ]; then
                    conflicts=true
                    # Read conflicts into array (bash 3.2 compatible)
                    conflict_items=()
                    while IFS= read -r line; do
                        conflict_items+=("$line")
                    done < "$TEMP_DIR/conflicts_${app_name}.txt"
                fi
            fi

            if [ "$conflicts" = true ]; then
                echo -e "${YELLOW}  Warning: The following items already exist:${NC}"
                for item in "${conflict_items[@]}"; do
                    echo -e "${YELLOW}    $APP_SUPPORT_DIR/$item${NC}"
                done

                # Prompt for confirmation
                echo -e "${YELLOW}  Overwrite existing files? [y/N]:${NC} "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    echo -e "${YELLOW}  Skipping $app_display_name${NC}"
                    echo "---"
                    continue
                fi
            fi

            echo -e "  Extracting: $archive_name"
            if tar --no-same-owner -xzf "$archive" -C "$APP_SUPPORT_DIR" 2>/dev/null; then
                echo -e "${GREEN}  ✓ Extracted: $app_display_name${NC}"

                # Fix ownership to current user (handles UID mismatch between Intel/ARM Macs)
                echo -e "  Fixing file ownership..."

                # Get the top-level directory/file from the archive
                top_level_item=$(tar -tzf "$archive" 2>/dev/null | head -1 | cut -d'/' -f1)
                if [ -n "$top_level_item" ] && [ -e "$APP_SUPPORT_DIR/$top_level_item" ]; then
                    chown -R "$CURRENT_USER:staff" "$APP_SUPPORT_DIR/$top_level_item" 2>/dev/null || true
                    echo -e "${GREEN}  ✓ Fixed ownership for: $top_level_item${NC}"
                fi

                processed=$((processed + 1))
            else
                echo -e "${RED}  ✗ Failed to extract $app_display_name${NC}"
            fi

            # Clean up conflict detection file
            rm -f "$TEMP_DIR/conflicts_${app_name}.txt"
        fi

        echo "---"
    fi
done

# Clean up
if [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}Cleaning up...${NC}"
    rm -rf "$TEMP_DIR"
fi

# Final summary
if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}Application configuration restore preview completed!${NC}"
    echo -e "${GREEN}Would process $total_archives application configurations${NC}"
else
    echo -e "${GREEN}Application configuration restore completed!${NC}"
    echo -e "${GREEN}Processed $processed out of $total_archives application configurations${NC}"
fi

if [ $processed -gt 0 ] || [ "$DRY_RUN" = true ]; then
    echo -e "\n${YELLOW}=== APPLICATION CONFIG RESTORE SUMMARY ===${NC}"
    echo -e "Total archives: $total_archives"
    if [ "$DRY_RUN" = false ]; then
        echo -e "Successfully restored: $processed"
    fi
    echo -e "Restore location: $APP_SUPPORT_DIR"

    echo -e "\n${YELLOW}=== POST-RESTORE NOTES ===${NC}"
    echo -e "📱 Application configurations restored to ~/Library/Application Support"
    echo -e "🔄 You may need to restart applications to pick up restored settings"
    echo -e "🔐 Some applications may require re-authentication"
    echo -e "⚠️  Review application preferences after first launch"

    echo -e "\n${GREEN}Application configuration restore completed!${NC}"
fi