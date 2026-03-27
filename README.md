# Hakchi for macOS

Native macOS application for managing NES/SNES Classic Mini consoles. A complete reimplementation of [hakchi2](https://github.com/clusterm/hakchi2) in Swift with SwiftUI.

## Features

- **Console Detection** - Automatic USB detection of NES/SNES Classic in FEL mode
- **Kernel Management** - Dump, flash, backup, and restore console kernels
- **Game Management** - Add, remove, and organize ROMs with drag & drop support
- **Auto-Metadata** - Automatic game identification via CRC32 hash database
- **Mod Manager** - Install and manage .hmod modification packages
- **SSH/SFTP** - Direct console access via SSH and file transfer
- **Clovershell** - USB-based command execution and file transfer
- **Native macOS UI** - SwiftUI interface with dark mode, keyboard shortcuts, and macOS menu bar integration

## Supported Consoles

| Console | ROM Formats |
|---------|------------|
| NES Classic Mini | .nes, .fds, .unf |
| SNES Classic Mini | .sfc, .smc, .fig |
| Sega Genesis Mini | .md, .smd, .gen |

## Requirements

- macOS 13 (Ventura) or later
- Intel or Apple Silicon Mac
- [Homebrew](https://brew.sh) (for dependencies)

## Installation

### Option A: Build the .app (Drag & Drop Install)

```bash
brew install libusb libssh2
git clone https://github.com/jorgeamartinezjr02/Hakchi2-macOS-Port.git
cd Hakchi2-macOS-Port
make app
```

This creates `Hakchi.app` in `.build/`. Drag it to `/Applications` — or run `make install` to do it automatically.

You can also create a DMG installer:

```bash
make dmg
```

### Option B: Run from Source

```bash
brew install libusb libssh2
git clone https://github.com/jorgeamartinezjr02/Hakchi2-macOS-Port.git
cd Hakchi2-macOS-Port
swift run Hakchi
```

## Usage

### Connecting Your Console

1. Connect your NES/SNES Classic to your Mac via USB
2. Power on the console while holding the RESET button to enter FEL mode
3. Hakchi will automatically detect the console (status indicator turns orange)

### Adding Games

- **Drag & Drop**: Drag ROM files directly into the game list
- **File Menu**: Use the "Add Games" button or File > Add Games
- Games are automatically identified and metadata is populated from the built-in database

### Kernel Operations

- **Dump Kernel**: Menu > Kernel > Dump Kernel (backup your original kernel first!)
- **Flash Custom Kernel**: Menu > Kernel > Flash Custom Kernel
- **Restore**: Menu > Kernel > Restore Original Kernel

### Syncing Games

1. Add games to the list
2. Connect your console
3. Click "Sync" in the toolbar or use Console > Sync Games

### Installing Mods

1. Open Mods > Mod Manager
2. Place .hmod files in the mods folder, or use "Import .hmod File"
3. Click "Install" next to the mod you want to install

## Project Structure

```
Sources/Hakchi/
  App/          - Application entry point and state management
  Core/
    FEL/        - Allwinner FEL USB boot protocol
    Console/    - Console detection and connection
    Kernel/     - Kernel dump/flash operations
    Shell/      - SSH, SFTP, and Clovershell clients
    Transfer/   - File sync engine
  Games/        - ROM handling, game database, game manager
  Mods/         - .hmod parsing and installation
  Views/        - SwiftUI interface
  Models/       - Data models
  Utils/        - CRC32, file utilities, logging
```

## Technical Details

- **FEL Protocol**: Implements the Allwinner FEL USB boot protocol (VID: 0x1F3A, PID: 0xEFE8) for low-level console communication. Based on the [sunxi-tools](https://github.com/linux-sunxi/sunxi-tools) reference implementation.
- **USB Communication**: Uses libusb via Swift C interop for cross-platform USB device access.
- **SSH/SFTP**: Uses libssh2 via Swift C interop for secure console shell access.
- **Game Database**: Built-in CRC32-based game identification for NES, SNES, and Genesis titles.

## License

This project is licensed under the GNU General Public License v2.0, consistent with the original hakchi2 project.

## Credits

- Original [hakchi2](https://github.com/clusterm/hakchi2) by ClusterM
- [Hakchi2 CE](https://github.com/TeamShinkansen/Hakchi2-CE) by Team Shinkansen
- [sunxi-tools](https://github.com/linux-sunxi/sunxi-tools) for FEL protocol reference
- [linux-sunxi](https://linux-sunxi.org/FEL/Protocol) for protocol documentation
