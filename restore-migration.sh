#!/bin/bash

# Script to restore migration backup on ARM Mac (M4)
# Usage: ./restore-migration.sh [--dry-run] [--list] [category-name]

set -e  # Exit on any error

# Check for flags and arguments
DRY_RUN=false
LIST_ONLY=false
SPECIFIC_CATEGORY=""

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
            SPECIFIC_CATEGORY="$1"
            shift
            ;;
    esac
done

SMB_MOUNT_POINT="/Volumes/storage1"
SMB_BACKUP_PATH="backup-migration"
TEMP_DIR="/tmp/migration-restore-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define category descriptions
declare -A CATEGORY_DESCRIPTIONS
CATEGORY_DESCRIPTIONS["user-dirs"]="📁 Documents, Downloads, Desktop"
CATEGORY_DESCRIPTIONS["shell-config"]="🔧 Oh My Zsh, .zshrc, .zprofile"
CATEGORY_DESCRIPTIONS["credentials"]="🔑 SSH keys, AWS, GPG, etc."
CATEGORY_DESCRIPTIONS["git-config"]="🔧 Git configuration files"
CATEGORY_DESCRIPTIONS["network-config"]="🌐 Cisco VPN configurations"

echo -e "${YELLOW}Starting migration restore on ARM Mac...${NC}"

# Check current user UID/GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USER=$(id -un)

echo -e "${YELLOW}Current user info on M4 Mac:${NC}"
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
    echo -e "${RED}Error: Migration backup directory $SMB_BACKUP_DIR does not exist${NC}"
    exit 1
fi

echo -e "${GREEN}Using backup directory: $SMB_BACKUP_DIR${NC}"

# Find all migration archives
if [ -n "$SPECIFIC_CATEGORY" ]; then
    # Look for specific category
    ARCHIVE_FILE="$SMB_BACKUP_DIR/${SPECIFIC_CATEGORY}.tar.gz"
    if [ -f "$ARCHIVE_FILE" ]; then
        ARCHIVES=("$ARCHIVE_FILE")
    else
        echo -e "${RED}Error: Archive for '$SPECIFIC_CATEGORY' not found: $ARCHIVE_FILE${NC}"
        exit 1
    fi
else
    # Find all .tar.gz files in backup directory
    ARCHIVES=($(find "$SMB_BACKUP_DIR" -name "*.tar.gz" -type f))
fi

if [ ${#ARCHIVES[@]} -eq 0 ]; then
    echo -e "${RED}No migration archives found in $SMB_BACKUP_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Found ${#ARCHIVES[@]} migration archive(s)${NC}"

# List mode - just show available backups
if [ "$LIST_ONLY" = true ]; then
    echo -e "\n${YELLOW}Available migration archives:${NC}"
    for archive in "${ARCHIVES[@]}"; do
        archive_name=$(basename "$archive")
        category_name="${archive_name%.tar.gz}"
        archive_size=$(du -h "$archive" | cut -f1)
        description="${CATEGORY_DESCRIPTIONS[$category_name]:-"Unknown category"}"
        echo -e "  ${GREEN}$category_name${NC} (${archive_size}) - $description"
    done
    echo -e "\n${YELLOW}Usage examples:${NC}"
    echo -e "  ./restore-migration.sh --dry-run              # Preview all"
    echo -e "  ./restore-migration.sh user-dirs              # Restore just user directories"
    echo -e "  ./restore-migration.sh shell-config           # Restore just shell config"
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
    category_name="${archive_name%.tar.gz}"
    current_archive=$((processed + 1))

    # Calculate progress percentage
    progress=$((current_archive * 100 / total_archives))

    echo -e "${YELLOW}Processing [$current_archive/$total_archives] ($progress%): $category_name${NC}"
    description="${CATEGORY_DESCRIPTIONS[$category_name]:-"Unknown category"}"
    echo -e "  $description"

    if [ "$DRY_RUN" = true ]; then
        archive_size=$(du -h "$archive" | cut -f1)
        echo -e "${YELLOW}  → Would extract: $archive_name (${archive_size})${NC}"

        # Preview contents without extracting
        echo -e "${YELLOW}  → Contents:${NC}"
        if tar -tzf "$archive" 2>/dev/null | head -10; then
            file_count=$(tar -tzf "$archive" 2>/dev/null | wc -l)
            if [ $file_count -gt 10 ]; then
                echo -e "${YELLOW}    ... and $((file_count - 10)) more files${NC}"
            fi
        else
            echo -e "${RED}    Failed to read archive contents${NC}"
        fi
        processed=$((processed + 1))
    else
        # Check for potential conflicts
        conflicts=false
        conflict_items=()

        # Check what would be extracted
        if tar -tzf "$archive" 2>/dev/null | while read -r item; do
            target_path="$HOME/$item"
            if [ -e "$target_path" ]; then
                echo "$item"
            fi
        done | head -5 > "$TEMP_DIR/conflicts_${category_name}.txt"; then
            if [ -s "$TEMP_DIR/conflicts_${category_name}.txt" ]; then
                conflicts=true
                mapfile -t conflict_items < "$TEMP_DIR/conflicts_${category_name}.txt"
            fi
        fi

        if [ "$conflicts" = true ]; then
            echo -e "${YELLOW}  Warning: The following items already exist:${NC}"
            for item in "${conflict_items[@]}"; do
                echo -e "${YELLOW}    $HOME/$item${NC}"
            done

            # Special handling for different categories
            case "$category_name" in
                "shell-config")
                    echo -e "${YELLOW}  This will overwrite your current shell configuration!${NC}"
                    echo -e "${YELLOW}  Recommendation: Backup your current .zshrc first${NC}"
                    ;;
                "credentials")
                    echo -e "${YELLOW}  This will merge/overwrite SSH keys and credentials${NC}"
                    echo -e "${YELLOW}  Existing keys will be preserved if different${NC}"
                    ;;
            esac

            read -p "  Continue with extraction? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}  Skipping $category_name${NC}"
                echo "---"
                continue
            fi
        fi

        # Extract archive (don't preserve original ownership, assign to current user)
        echo -e "  Extracting: $archive_name"
        if tar --no-same-owner -xzf "$archive" -C "$HOME" 2>/dev/null; then
            echo -e "${GREEN}✓ Extracted: $category_name${NC}"

            # Fix ownership to current user (handles UID mismatch between Intel/ARM Macs)
            echo -e "  Fixing file ownership..."
            case "$category_name" in
                "user-dirs")
                    # Fix ownership for user directories
                    for item in Documents Downloads Desktop; do
                        if [ -d "$HOME/$item" ]; then
                            chown -R "$CURRENT_USER:staff" "$HOME/$item" 2>/dev/null || true
                        fi
                    done
                    ;;
                "shell-config")
                    # Fix ownership for shell config files
                    for item in .oh-my-zsh .zshrc .zprofile; do
                        if [ -e "$HOME/$item" ]; then
                            chown -R "$CURRENT_USER:staff" "$HOME/$item" 2>/dev/null || true
                        fi
                    done
                    echo -e "${GREEN}  → Shell config restored. Restart terminal or run: source ~/.zshrc${NC}"
                    ;;
                "credentials")
                    # Fix ownership and permissions for credentials
                    for item in .ssh .aws .gnupg .boto; do
                        if [ -e "$HOME/$item" ]; then
                            chown -R "$CURRENT_USER:staff" "$HOME/$item" 2>/dev/null || true
                        fi
                    done
                    if [ -d "$HOME/.ssh" ]; then
                        chmod 700 "$HOME/.ssh" 2>/dev/null || true
                        chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
                        echo -e "${GREEN}  → SSH ownership and permissions fixed${NC}"
                    fi
                    ;;
                "git-config")
                    # Fix ownership for git config files
                    for item in .gitconfig .gitignore_global .hgignore_global; do
                        if [ -f "$HOME/$item" ]; then
                            chown "$CURRENT_USER:staff" "$HOME/$item" 2>/dev/null || true
                        fi
                    done
                    ;;
                "network-config")
                    # Fix ownership for network configs
                    if [ -d "$HOME/.cisco" ]; then
                        chown -R "$CURRENT_USER:staff" "$HOME/.cisco" 2>/dev/null || true
                    fi
                    echo -e "${GREEN}  → Network configs restored. You may need to reconnect VPNs${NC}"
                    ;;
            esac

            echo -e "${GREEN}  → File ownership updated for UID $CURRENT_UID${NC}"
            processed=$((processed + 1))
        else
            echo -e "${RED}✗ Failed to extract $archive_name${NC}"
        fi

        # Cleanup temp files for this category
        rm -f "$TEMP_DIR/conflicts_${category_name}.txt"
    fi

    echo "---"
done

# Cleanup
if [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}Cleaning up...${NC}"
    rmdir "$TEMP_DIR" 2>/dev/null || true
fi

echo -e "${GREEN}Migration restore completed!${NC}"
echo -e "${GREEN}Processed $processed out of $total_archives archives${NC}"

if [ $processed -gt 0 ] && [ "$DRY_RUN" = false ]; then
    echo -e "\n${YELLOW}=== POST-RESTORE RECOMMENDATIONS ===${NC}"
    echo -e "🔄 Restart your terminal to apply shell changes"
    echo -e "🔧 Install Oh My Zsh if not already installed: sh -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
    echo -e "🌐 Reconnect to VPNs using restored Cisco configs"
    echo -e "🔑 Test SSH connections to verify key restoration"
    echo -e "📁 Your Documents, Downloads, and Desktop have been restored"
    echo -e "\n${GREEN}Welcome to your new ARM Mac! 🎉${NC}"
fi