# File System Architecture

This document explains how Sordello watches, scans, and manages files in Ableton Live projects.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Project Folder (e.g., "My Song Project")                       │
│  ├── My Song.als                    ← Watched by FileWatcher    │
│  ├── Another Song.als               ← Main LiveSets             │
│  ├── Backup/                        ← Scanned by FileScanner    │
│  │   └── My Song [2024-01-15].als                               │
│  └── .sordello/                     ← Scanned by FileScanner    │
│      ├── db/sordello.db             ← Per-project database      │
│      ├── My Song/                                               │
│      │   ├── versions/              ← LiveSet versions          │
│      │   │   └── 2024-01-15T14-30-00.als                        │
│      │   └── liveSetTracks/         ← Track versions            │
│      │       └── 15/                ← Track ID                  │
│      │           └── 2024-01-15T14-35-00.als                    │
│      └── Another Song/                                          │
│          └── versions/                                          │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### FileWatcher

**Location:** `Services/FileWatcher.swift`

Watches the **project root directory only** using `DispatchSource`. Does NOT watch subdirectories.

```swift
FileWatcher.shared.watchFile(at: projectPath) {
    ProjectManager.shared.reloadProject(folderPath: projectPath)
}
```

**Key details:**
- Uses `DispatchSource.makeFileSystemObjectSource` with `.write` event mask
- Runs on `DispatchQueue.main` (required for Swift 6 concurrency)
- Uses `source.activate()` (not `resume()`) for proper lifecycle
- Triggers `reloadProject()` with 500ms debounce delay

**What triggers the watcher:**
- Saving a main .als file in Ableton Live
- Adding/removing files in the project root
- File modifications in the root folder

**What does NOT trigger the watcher:**
- Changes in `.sordello/` subdirectories
- Changes in `Backup/` folder
- These are discovered via FileScanner during reload

### FileScanner

**Location:** `Helpers/FileScanner.swift`

Scans project directories and detects file changes by comparing database records with filesystem attributes.

#### Full Scan (`scanAndSaveLiveSets`)

Used on first project load when database is empty:
1. Deletes all existing LiveSet records
2. Scans root folder for main .als files
3. Scans `.sordello/{name}/versions/` for version files
4. Scans `.sordello/{name}/liveSetTracks/{trackId}/` for track versions
5. Scans `Backup/` folder
6. Inserts all found files into database

#### Incremental Update (`incrementalUpdate`)

Used on subsequent reloads. Returns `IncrementalUpdateResult` with separate `changed` and `new` arrays.

**Scanned locations:**
1. Root folder → `.main` category
2. `Backup/` → `.backup` category
3. `.sordello/{name}/versions/` → `.version` category
4. `.sordello/{name}/liveSetTracks/{trackId}/` → `.liveSetTrackVersion` category

## Modification Detection Logic

The incremental update compares **database records** with **filesystem attributes** to detect changes.

### Data Compared

| Source | Field | Description |
|--------|-------|-------------|
| Database | `fileModificationDate` | Stored `Date?` from last scan |
| Filesystem | `contentModificationDateKey` | File's actual modification date |

### Detection Algorithm

```swift
for each file on disk:
    currentModDate = filesystem modification date

    if file.path exists in database:
        existing = database record
        storedDate = existing.fileModificationDate

        if storedDate != nil AND currentDate != nil AND
           currentDate - storedDate > 1.0 seconds:
            → Mark as CHANGED (needs reparsing)
            → Update fileModificationDate in database
        else:
            → No change detected
    else:
        → Mark as NEW (needs parsing)
        → Insert new record with fileModificationDate

for each database record:
    if path NOT on disk:
        → DELETE from database
```

### Edge Cases

**File modified:** `currentDate > storedDate + 1 second` → reparsed

**New file:** Path not in database → inserted and parsed

**Deleted file:** Database record with no matching file → deleted from database

## Version Creation

### LiveSet Versions (`createVersion`)

Creates a copy of an entire .als file for versioning.

**Flow:**
1. Generate version path: `.sordello/{liveSetName}/versions/{timestamp}.als`
2. Insert placeholder record (copies original LiveSet, **inherits `fileModificationDate`**)
3. Copy file to version path via `VersionControl.createCopyAsync()`
4. Call `reloadProject()` → `incrementalUpdate()`
5. Scanner finds existing record, compares dates:
   - Stored date = original file's date
   - Current date = new copy's date (now)
   - Difference > 1 second → marked as **changed** → reparsed

### Track Versions (`createLiveSetTrackVersion`)

Extracts a single track (or group with children) to a new .als file.

**Flow:**
1. Generate version path: `.sordello/{liveSetName}/liveSetTracks/{trackId}/{timestamp}.als`
2. Insert placeholder record (copies original LiveSet, **inherits `fileModificationDate`**)
3. Extract track via `AlsExtractor.extractTrack()`
4. Call `reloadProject()` → `incrementalUpdate()`
5. Scanner finds existing record, compares dates:
   - Stored date = original file's date
   - Current date = extracted file's date (now)
   - Difference > 1 second → marked as **changed** → reparsed

**Metadata stored:**
- `parentLiveSetPath` - path to the source LiveSet
- `sourceLiveSetName` - name of the source LiveSet
- `sourceTrackId` - ID of the extracted track
- `sourceTrackName` - name of the extracted track
- `extractedAt` - timestamp when extraction occurred

## Auto-Versioning

When a main LiveSet with `autoVersionEnabled = true` is modified:

1. FileWatcher detects change in root folder
2. `reloadProject()` → `incrementalUpdate()`
3. File detected as **changed** (in `result.changed`, not `result.new`)
4. File is reparsed
5. Auto-version created via `VersionControl.createCopy()`

**Important:** Auto-versioning only runs on `result.changed`, not `result.new`. This prevents creating versions when duplicating files in Finder.

```swift
// Only auto-version CHANGED main LiveSets
for liveSet in result.changed where liveSet.category == .main && liveSet.autoVersionEnabled {
    let versionPath = vc.versionPath(for: liveSet.path)
    try vc.createCopy(of: liveSet.path, to: versionPath)
}
```

## Storage Paths

### VersionControl

**Location:** `Services/VersionControl.swift`

Generates timestamped paths for versions:

```swift
// LiveSet version
.sordello/{liveSetName}/versions/{timestamp}.als
// Example: .sordello/My Song/versions/2024-01-15T14-30-00.als

// Track version
.sordello/{liveSetName}/liveSetTracks/{trackId}/{timestamp}.als
// Example: .sordello/My Song/liveSetTracks/15/2024-01-15T14-35-00.als
```

Timestamp format: `K.dateFormat.timestamp` = `yyyy-MM-dd'T'HH-mm-ss`
