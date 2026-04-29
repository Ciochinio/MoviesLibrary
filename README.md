# Portable Media Library

A desktop media manager for images, GIFs, and videos. Built with Flutter, designed to be fully portable - your library lives in a folder you control, not in a cloud or app database.

> **Platform:** Windows (macOS in progress)

---

## Features

### Library & Organisation
- Import images, GIFs, and videos by drag-and-drop or file picker
- Organise media into **Categories** and **Subcategories**
- Two-tier **tag system** - simple tags and key:value tags (e.g. `director: Kubrick`)
- Tag groups for visual organisation
- Auto-tags on import per subcategory
- Bulk tagging, bulk moving, bulk deletion
- Duplicate detection via SHA-256 - no wasted space
- Favourites

### Viewing
- Grid view with thumbnail generation (via ffmpeg for videos)
- Animated GIF preview in grid (optional)
- Side panel player - images, GIFs, and videos without leaving the grid
- Theatre mode - expands the player panel for a larger view
- Full-screen player with filmstrip navigation, autoplay, and loop
- Videos autoloop in the panel
- Search with multi-tag filtering, type filters, and filename search

### Raffle & Quick Roll
- **Wheel of Fortune** - spin a weighted wheel built from tag-filtered segments to pick a random item
- **Quick Roll** - define presets with tag filters and sample sizes, roll instantly to get a random selection shown in a grid

### Notes
- Freeform notes with file attachments, stored inside the Library folder

### Settings
- Dark / light / system theme
- GIF autoplay toggle
- Video autostart in panel
- Start muted
- Customisable sidebar - hide any nav item you don't use
- Import mode: copy or move
- Tag dialog column layout

---

## Portability

PML stores everything in a **Library folder** you choose:

```
YourLibrary/
  db/          ← SQLite database
  files/       ← imported media (renamed by hash)
  thumbs/      ← generated thumbnails
  attachments/ ← note attachments
  settings.json
```

Move or copy that folder anywhere - USB drive, network share, synced folder - and the app picks it up automatically if it finds the folder next to itself, or asks you to locate it on first launch.

App preferences that are machine-specific (theme, volume, mute) are stored in `global_settings.json` next to the executable, so they don't travel with the Library.

---

## Installation

### Standard install (Windows)

Download `PML-Setup-x.x.x.exe` from the [Releases](../../releases) page and run it. The installer lets you choose any install location:

- **Program Files** - standard install with Start Menu and desktop shortcuts
- **USB drive or custom folder** - portable install, no registry entries written

### Portable use

Place the app in an `App/` subfolder on your drive and create a `Library/` folder next to it:

```
USB Drive/
  App/
    movieslibrary.exe
    ... (app files)
  Library/       ← app finds this automatically on launch
```

---

## Building from Source

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel)
- [NSIS 3.x](https://nsis.sourceforge.io/Download) (for building the installer)
- [ffmpeg](https://ffmpeg.org/download.html) - place the `ffmpeg/` folder in the project root for video thumbnail support

### Run in development

```bash
flutter run -d windows
```

### Build installer

```bash
installer\build_windows.bat
```

Output: `installer\PML-Setup-x.x.x.exe`

See [`installer/README.md`](installer/README.md) for full build documentation.

---

## Project Structure

```
lib/
  main.dart
  src/
    core/
      models.dart           ← domain models
      app_state.dart        ← central state (ChangeNotifier)
      app_settings.dart     ← settings split into library + global
      repositories.dart     ← data access layer
      db.dart               ← SQLite schema + migrations
      import_controller.dart
      thumbnail_service.dart
      portable_paths.dart
      session_volume.dart
    ui/
      shell.dart            ← navigation rail + screen routing
      screens/
      widgets/
installer/
  pml_installer.nsi
  build_windows.bat
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `media_kit` + `media_kit_video` | Video/audio playback |
| `sqflite_common_ffi` | SQLite database |
| `provider` | State management |
| `file_picker` | File/folder picker dialogs |
| `desktop_drop` | Drag-and-drop import |
| `path` | Path manipulation |
| `crypto` | SHA-256 deduplication |
| `window_manager` | Window size/title control |

---

## License

MIT
