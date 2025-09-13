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
  - `user-dirs`: Documents, Downloads, Desktop
  - `shell-config`: Oh My Zsh, .zshrc, .zprofile
  - `credentials`: SSH keys, AWS, GPG, etc.
  - `git-config`: Git configuration files
  - `network-config`: Cisco VPN configurations
- **Output**: `/Volumes/YOUR_MOUNT_POINT/backup-migration/`
- **Features**: UID detection, architecture-safe selection

```bash
./backup-migration.sh --dry-run  # Preview
./backup-migration.sh            # Full migration backup
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

❌ **Not migrated** (fresh install recommended):
- Applications (architecture-specific)
- Development tools (Homebrew, Node.js, Docker)
- Compiled binaries and caches

## SMB Storage Structure

```
/Volumes/YOUR_MOUNT_POINT/
├── backup-work/        # Work directories (project folders)
├── backup-user/        # User directories (Documents, Downloads, Desktop)
└── backup-migration/   # Complete migration backup
    ├── user-dirs.tar.gz
    ├── shell-config.tar.gz
    ├── credentials.tar.gz
    ├── git-config.tar.gz
    └── network-config.tar.gz
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
3. **Optional work/user directory backups**:
   ```bash
   ./backup-work-dirs.sh
   ./backup-user-dirs.sh
   ```

### ARM Mac (Target)

1. **Mount SMB share**
2. **List available backups**:
   ```bash
   ./restore-migration.sh --list
   ```
3. **Preview restore**:
   ```bash
   ./restore-migration.sh --dry-run
   ```
4. **Execute restore**:
   ```bash
   ./restore-migration.sh
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

## Contributing

This is a personal migration toolkit developed with Claude's assistance, but suggestions and improvements are welcome.

## Credits

- **Development**: Collaborative effort between human user and Claude (Anthropic)
- **Testing**: Real-world Intel to M4 Mac migration scenario
- **Architecture considerations**: Informed by macOS migration best practices and community feedback