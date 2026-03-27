# Hakchi for macOS

Native macOS port of [Hakchi2 CE](https://github.com/TeamShinkansen/Hakchi2-CE) — the complete tool for managing NES/SNES/Famicom Classic Mini consoles. Reimplemented in Swift with SwiftUI for a native macOS experience.

## Features

- **All Console Variants** — Full support for every Classic Mini region and model
- **Console Detection** — Automatic USB detection in FEL mode
- **Kernel Management** — Dump, flash, backup, and restore console kernels
- **Game Management** — Add, remove, and organize ROMs with drag & drop
- **Import from Console** — Pull existing games back from your modded console
- **Folder Organization** — Alphabetical, by genre, by system, or paginated
- **Delta Sync** — Only uploads new/changed games, removes deleted ones
- **Auto-Metadata** — Automatic game identification via CRC32 database
- **Game Editing** — Edit name, publisher, year, genre, emulator command line
- **Mod Manager** — Install/uninstall .hmod packages (emulators, UI, controllers)
- **RetroArch Cores** — FCEUmm, Snes9x, Genesis Plus GX, mGBA, PCSX, and more
- **Controller Support** — DualShock 3/4, 8BitDo Bluetooth mod packages
- **SSH/SFTP** — Direct console access via SSH and file transfer
- **Clovershell** — USB-based command execution and file transfer
- **USB Storage** — Load games from external USB drive via OTG
- **Native macOS UI** — SwiftUI with dark mode, keyboard shortcuts, menu bar

## Supported Consoles

| Console | Region | ROM Formats | CLV Prefix |
|---------|--------|------------|------------|
| NES Classic Mini | USA | .nes, .fds, .unf, .qd | CLV-H |
| NES Classic Mini | Europe | .nes, .fds, .unf, .qd | CLV-H |
| Famicom Mini | Japan | .nes, .fds, .unf, .qd | CLV-H |
| SNES Classic Mini | USA | .sfc, .smc, .fig, .sfrom | CLV-U |
| SNES Classic Mini | Europe | .sfc, .smc, .fig, .sfrom | CLV-P |
| Super Famicom Mini | Japan | .sfc, .smc, .fig, .sfrom | CLV-S |
| Sega Genesis Mini | USA | .md, .smd, .gen, .gg | CLV-G |
| Mega Drive Mini | Europe | .md, .smd, .gen, .gg | CLV-G |

### RetroArch Additional Formats

With RetroArch and the appropriate core installed, you can also load:
- Game Boy / Color: .gb, .gbc
- Game Boy Advance: .gba
- N64: .n64, .z64
- TurboGrafx-16: .pce, .tg16
- PlayStation 1: via PCSX ReARMed core
- Arcade: CPS1, CPS2, Neo Geo via FB Alpha
- Atari 2600: .a26

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

1. Connect your Classic Mini to your Mac via USB
2. Power on the console while holding the RESET button to enter FEL mode
3. Hakchi will automatically detect the console and its type

### Adding Games

- **Drag & Drop**: Drag ROM files directly into the game list
- **Add Games button**: Opens a file picker filtered to supported formats
- **Import from Console**: Pull games already installed on your modded console
- Games are automatically identified with metadata from the built-in database

### Game Organization

Games > Settings lets you choose folder structure:
- **Flat** — All games in one list
- **Alphabetical** — Grouped by first letter (A, B, C...)
- **By Genre** — Action, RPG, Platformer, etc.
- **By System** — NES, SNES, Genesis groups
- **Paginated** — Split into pages of N games each

### Kernel Operations

- **Dump Kernel** (Cmd+Shift+D): Backup your original kernel first!
- **Flash Custom Kernel** (Cmd+Shift+F): Enable hakchi on your console
- **Restore Original Kernel**: Restore from a previous backup

### Syncing Games

1. Add games to the list and select your console type
2. Connect your console
3. Click "Sync" — only new/changed games are uploaded (delta sync)

### Installing Mods

1. Open Mods > Mod Manager (Cmd+Shift+M)
2. Browse available mods by category (Emulator, System, UI, Controller)
3. Place .hmod files in the mods folder, or use "Import .hmod File"
4. Click "Install" next to the mod you want

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Dump Kernel | Cmd+Shift+D |
| Flash Kernel | Cmd+Shift+F |
| Sync Games | Cmd+Shift+S |
| Import from Console | Cmd+Shift+I |
| Mod Manager | Cmd+Shift+M |
| Select All | Cmd+A |
| Delete Selected | Cmd+Delete |

## Project Structure

```
Sources/Hakchi/
  App/          - Application entry point and state management
  Core/
    FEL/        - Allwinner FEL USB boot protocol
    Console/    - Console detection, type/region/family enums
    Kernel/     - Kernel dump/flash operations
    Shell/      - SSH, SFTP, and Clovershell clients
    Transfer/   - File sync engine
  Games/        - ROM handling, game database, folder organization
  Mods/         - .hmod parsing, mod repository, installation
  Views/        - SwiftUI interface (sidebar, detail, dialogs)
  Models/       - Data models (Game, Mod, SyncOperation)
  Utils/        - CRC32, file utilities, logging, errors
```

## Technical Details

- **FEL Protocol**: Implements the Allwinner FEL USB boot protocol (VID: 0x1F3A, PID: 0xEFE8) for low-level console communication.
- **USB Communication**: Uses libusb via Swift C interop for cross-platform USB device access.
- **SSH/SFTP**: Uses libssh2 via Swift C interop for secure console shell access.
- **Game Database**: Built-in CRC32-based game identification for NES, SNES, and Genesis titles.
- **Delta Sync**: Compares local game list against console contents; only transfers what changed.
- **CLV Codes**: Generates region-correct CLV codes matching Hakchi2 CE format.

## Hakchi2 CE Feature Parity

This port aims for 1:1 feature parity with [Hakchi2 CE v3.9.3](https://github.com/TeamShinkansen/Hakchi2-CE/releases):

- [x] All console variants (NES/SNES/Famicom/SFC/Genesis/MD, all regions)
- [x] Kernel dump/flash/restore
- [x] Game management with drag & drop
- [x] CRC32 game database with auto-metadata
- [x] .desktop file generation with correct CLV codes
- [x] Mod manager with hmod install/uninstall
- [x] RetroArch + emulator cores
- [x] Import games from console (v3.9.0 feature)
- [x] Folder organization by genre/alpha/system/pages (v3.9.0 feature)
- [x] Delta sync (smart upload)
- [x] Game metadata editing with persistence
- [x] DualShock/8BitDo controller mod packages
- [x] USB storage support
- [x] SSH/SFTP and Clovershell communication
- [ ] Game artwork scraper (TheGamesDB integration)
- [ ] Screenshot capture (F8)
- [ ] Multi-boot profiles

## License

GNU General Public License v2.0, consistent with the original hakchi2 project.

## Credits

- Original [hakchi2](https://github.com/clusterm/hakchi2) by ClusterM
- [Hakchi2 CE](https://github.com/TeamShinkansen/Hakchi2-CE) by Team Shinkansen
- [sunxi-tools](https://github.com/linux-sunxi/sunxi-tools) for FEL protocol reference
- [linux-sunxi](https://linux-sunxi.org/FEL/Protocol) for protocol documentation
