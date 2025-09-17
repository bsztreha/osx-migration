# macOS Migration Scripts

A collection of backup and restore scripts for seamless migration between macOS systems, specifically designed for Intel to ARM (M4) Mac transitions.

> **Note**: These scripts were developed in collaboration with Claude (Anthropic's AI assistant) to ensure robust error handling, proper UID/GID management, and comprehensive migration coverage.

## Overview

These scripts handle the safe migration of user data, configurations, and development environments while properly managing UID/GID differences between systems and avoiding architecture-specific compatibility issues.

## Scripts

### Backup Scripts

#### `backup-work-dirs.sh`
Backs up all directories in `~/work/` to individual compressed archives.

- **Target**: `~/work/*` directories
- **Output**: `/Volumes/YOUR_MOUNT_POINT/backup-work/`
- **Features**: Size-based progress, existing backup detection, dry-run mode

```bash
./backup-work-dirs.sh --dry-run  # Preview
./backup-work-dirs.sh            # Full backup
```

#### `backup-user-dirs.sh`
Backs up standard macOS user directories.

- **Target**: `~/Documents`, `~/Downloads`, `~/Desktop`
- **Output**: `/Volumes/YOUR_MOUNT_POINT/backup-user/`
- **Features**: Fixed directory list, same progress tracking as work dirs

```bash
./backup-user-dirs.sh --dry-run  # Preview
./backup-user-dirs.sh            # Full backup
```

#### `backup-migration.sh`
Comprehensive migration backup for Intel → ARM Mac transition.

- **Categories**:
  - `shell-config`: Oh My Zsh, .zshrc, .zprofile
  - `credentials`: SSH keys, AWS, GPG, etc.
  - `git-config`: Git configuration files
  - `network-config`: Cisco VPN configurations
- **Note**: User directories (Documents, Downloads, Desktop) are handled separately by `backup-user-dirs.sh`
- **Output**: `/Volumes/YOUR_MOUNT_POINT/backup-migration/`
- **Features**: UID detection, architecture-safe selection

```bash
./backup-migration.sh --dry-run  # Preview
./backup-migration.sh            # Full migration backup
```

#### `backup-app-config.sh`
Backs up application configurations from ~/Library/Application Support.

- **Target**: Individual application folders in `~/Library/Application Support`
- **Output**: `/Volumes/YOUR_MOUNT_POINT/backup-app-config/`
- **Features**: Individual .tar.gz files per application, system directory filtering, cache exclusion
- **Exclusions**: System directories, caches, logs, .DS_Store files

```bash
./backup-app-config.sh --dry-run  # Preview
./backup-app-config.sh            # Full app config backup
```

### Restore Scripts

#### `restore-work-dirs.sh`
Restores work directories from backup archives.

- **Source**: `/Volumes/YOUR_MOUNT_POINT/backup-work/`
- **Target**: `~/work/`
- **Features**: Conflict detection, selective restore, UID/GID handling

```bash
./restore-work-dirs.sh --list                # List available backups
./restore-work-dirs.sh --dry-run             # Preview restore
./restore-work-dirs.sh                       # Restore all
./restore-work-dirs.sh project-name          # Restore specific directory
```

#### `restore-migration.sh`
Restores migration backup on new ARM Mac.

- **Source**: `/Volumes/YOUR_MOUNT_POINT/backup-migration/`
- **Target**: `~/` (various locations)
- **Features**: Category-specific handling, automatic ownership fixes, post-restore guidance

```bash
./restore-migration.sh --list                # List available categories
./restore-migration.sh --dry-run             # Preview restore
./restore-migration.sh                       # Restore all categories
./restore-migration.sh shell-config          # Restore specific category
```

#### `restore-app-config.sh`
Restores application configurations to ~/Library/Application Support.

- **Source**: `/Volumes/YOUR_MOUNT_POINT/backup-app-config/`
- **Target**: `~/Library/Application Support/`
- **Features**: Conflict detection, selective restore, automatic ownership fixes, UID/GID handling

```bash
./restore-app-config.sh --list               # List available app configs
./restore-app-config.sh --dry-run            # Preview restore
./restore-app-config.sh                      # Restore all app configs
./restore-app-config.sh "Visual Studio Code" # Restore specific app
```

## Architecture Considerations

### Intel to ARM Migration

These scripts are specifically designed to handle the migration from Intel Macs to ARM Macs (M4), addressing:

- **UID/GID differences**: Automatic ownership correction between different user IDs
- **Architecture compatibility**: Only migrates architecture-neutral files and configs
- **Permission handling**: Proper SSH key permissions, file ownership fixes

### What's Migrated

✅ **Safe to migrate**:
- User documents and files
- Shell configurations (Oh My Zsh themes, aliases)
- Credentials and keys (SSH, AWS, GPG)
- Git configurations
- Network configurations (VPN profiles)
- Application configurations and preferences

❌ **Not migrated** (fresh install recommended):
- Applications (architecture-specific)
- Development tools (Homebrew, Node.js, Docker)
- Compiled binaries and caches

## SMB Storage Structure

```
/Volumes/YOUR_MOUNT_POINT/
├── backup-work/        # Work directories (project folders)
├── backup-user/        # User directories (Documents, Downloads, Desktop)
├── backup-migration/   # Configuration and credentials backup
│   ├── shell-config.tar.gz
│   ├── credentials.tar.gz
│   ├── git-config.tar.gz
│   └── network-config.tar.gz
└── backup-app-config/  # Application configurations
    ├── Visual_Studio_Code.tar.gz
    ├── Firefox.tar.gz
    ├── Slack.tar.gz
    └── [other-app-configs].tar.gz
```

## Prerequisites

### SMB Share Setup

1. Mount the SMB share:
```bash
mount -t smbfs -o guest smb://YOUR_SMB_SERVER/YOUR_SHARE /Volumes/YOUR_MOUNT_POINT
```

Example:
```bash
mount -t smbfs -o guest smb://192.168.1.100/backup /Volumes/backup
```

2. The scripts will automatically create backup directories as needed.

### Required Tools

- `tar` with sparse file support
- `du`, `find`, `chown` (standard macOS tools)
- SMB client (built into macOS)

## Migration Workflow

### Intel Mac (Source)

1. **Mount SMB share**
2. **Run migration backup**:
   ```bash
   ./backup-migration.sh --dry-run  # Preview
   ./backup-migration.sh            # Execute
   ```
3. **Optional work/user/app directory backups**:
   ```bash
   ./backup-work-dirs.sh
   ./backup-user-dirs.sh
   ./backup-app-config.sh
   ```

### ARM Mac (Target)

1. **Mount SMB share**
2. **List available backups**:
   ```bash
   ./restore-migration.sh --list
   ./restore-app-config.sh --list      # If app configs were backed up
   ```
3. **Preview restore**:
   ```bash
   ./restore-migration.sh --dry-run
   ./restore-app-config.sh --dry-run   # If app configs were backed up
   ```
4. **Execute restore**:
   ```bash
   ./restore-migration.sh
   ./restore-app-config.sh             # If app configs were backed up
   ```
5. **Follow post-restore recommendations**

## Features

### Progress Tracking
- Size-based progress calculation
- Real-time progress display
- Category/directory counting

### Safety Features
- Dry-run mode for all scripts
- Existing backup detection
- Conflict resolution prompts
- Automatic permission fixes

### UID/GID Handling
- Detects user ID differences
- Uses `--numeric-owner` for backups
- Uses `--no-same-owner` for restores
- Automatic `chown` fixes after extraction

## Error Handling

- SMB mount verification
- Extended attribute handling (`-X` flag)
- Permission error suppression
- Graceful failure recovery

## Post-Migration Tasks

After running the migration scripts:

1. **Restart terminal** to apply shell changes
2. **Install fresh applications** (ARM-native versions)
3. **Reinstall development tools**:
   - Homebrew (ARM version)
   - Node.js, Python, etc. (ARM versions)
   - Docker/OrbStack (fresh install)
4. **Test SSH connections** to verify key restoration
5. **Reconnect VPNs** using restored configurations
6. **Launch applications** to verify restored configurations
7. **Re-authenticate applications** as needed (some may require fresh login)

## Troubleshooting

### Common Issues

**SMB Mount Problems**:
```bash
# Unmount and remount
umount /Volumes/YOUR_MOUNT_POINT
mount -t smbfs -o guest smb://YOUR_SMB_SERVER/YOUR_SHARE /Volumes/YOUR_MOUNT_POINT
```

**Permission Denied Errors**:
```bash
# Check file ownership
ls -la ~/Documents
# Fix if needed
chown -R $(whoami):staff ~/Documents
```

**Archive Extraction Fails**:
```bash
# Check archive integrity
tar -tzf backup-file.tar.gz | head -5
```

## License

MIT License - Feel free to modify and distribute.

## Custom Keyboard Layouts

The `keylayouts/` directory contains custom keyboard layout files for macOS that can be installed to provide additional input methods.

### Available Layouts

- **Hungarian WIN.keylayout** - Hungarian keyboard layout with Windows-style key mappings
- **Hungarian_Win.keylayout** - Alternative Hungarian Windows-style layout

### Installation

**User-level installation** (recommended):
```bash
# Create directory if it doesn't exist (optional, macOS will create it)
mkdir -p ~/Library/Keyboard\ Layouts/

# Copy specific layout files
cp keylayouts/"Hungarian WIN.keylayout" ~/Library/Keyboard\ Layouts/
cp keylayouts/"Hungarian_Win.keylayout" ~/Library/Keyboard\ Layouts/
```

**System-wide installation** (requires admin):
```bash
# Copy specific layouts
sudo cp keylayouts/"Hungarian WIN.keylayout" /Library/Keyboard\ Layouts/
sudo cp keylayouts/"Hungarian_Win.keylayout" /Library/Keyboard\ Layouts/
```

### Activation

1. **Open System Settings** → Keyboard → Input Sources
2. **Add new layout**: Click "+" and look in "Others" section
3. **Switch layouts**: Use `Cmd + Space` or input menu in menu bar

**Note**: Log out and log back in after installation for layouts to appear in System Settings.

### Migration Integration

Custom keyboard layouts are **not automatically included** in the current migration scripts. To migrate keyboard layouts to a new Mac:

1. **Manual backup** on source Mac:
   ```bash
   tar -czf keyboard-layouts.tar.gz -C ~/ "Library/Keyboard Layouts"
   cp keyboard-layouts.tar.gz /Volumes/YOUR_MOUNT_POINT/
   ```

2. **Manual restore** on target Mac:
   ```bash
   tar -xzf /Volumes/YOUR_MOUNT_POINT/keyboard-layouts.tar.gz -C ~/
   ```

3. **Or simply copy** the layout files from this repository and install as described above

## Contributing

This is a personal migration toolkit developed with Claude's assistance, but suggestions and improvements are welcome.

## Credits

- **Development**: Collaborative effort between human user and Claude (Anthropic)
- **Testing**: Real-world Intel to M4 Mac migration scenario
- **Architecture considerations**: Informed by macOS migration best practices and community feedback