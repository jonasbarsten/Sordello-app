# Sordello

A macOS companion app for creating Reaper-style subprojects in Ableton Live.

## Project Goal

Enable extracting a group (folder track) from an Ableton Live set (.als) into its own separate .als file that can be opened in another Live instance. When work is done in the subproject, bounced audio can be imported back to the original project.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Ableton Live                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Max for Live Device (on each group track)               │   │
│  │  - Sends OSC commands to Sordello                        │   │
│  │  - Receives status updates via OSC                       │   │
│  │  - Buttons: Extract, Open Subproject, Import Bounce      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │ OSC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Sordello (macOS App)                                           │
│  - Listens for OSC commands from M4L devices                    │
│  - Displays connected projects in tree view                     │
│  - Parses .als files (gzipped XML)                              │
│  - Extracts groups to new .als files                            │
│  - Imports bounced audio back to original projects              │
│  - Opens subprojects in new Ableton instances                   │
└─────────────────────────────────────────────────────────────────┘
```

## Communication Protocol (OSC)

### M4L → Sordello (Port 47200)

All messages are prefixed with `/byJoBa/` for namespacing across future products.

| Address | Arguments | Description |
|---------|-----------|-------------|
| `/byJoBa/sordello/register` | instanceId (string), projectPath (string), liveVersion (string) | Register M4L device on load |
| `/byJoBa/sordello/unregister` | instanceId | M4L device unloading |
| `/byJoBa/sordello/extract` | instanceId, groupTrackId (int), groupName (string) | Extract group to subproject |
| `/byJoBa/sordello/open` | instanceId | Open the subproject in new Ableton instance |
| `/byJoBa/sordello/import` | instanceId | Import bounce track back to original |
| `/byJoBa/sordello/status` | instanceId | Request current status |

**Note**: The M4L device sends `/byJoBa/sordello/register` automatically when it loads, including:
- `instanceId`: Unique identifier for this device instance
- `projectPath`: Full path to the .als file (from Live API)
- `liveVersion`: Ableton Live version string (e.g., "12.1")

### Sordello → M4L (Port 47201)

| Address | Arguments | Description |
|---------|-----------|-------------|
| `/byJoBa/sordello/response` | instanceId, status (string), message (string) | Response to commands |
| `/byJoBa/sordello/bounceReady` | instanceId, ready (int 0/1) | Notify when bounce track detected |

## Main Window

The app displays a tree view of all connected projects:

```
Sordello
├── My Song Project.als (connected)
│   ├── Drums (Group)
│   │   └── [Subproject: Drums-subproject.als]
│   ├── Bass (Group)
│   └── Synths (Group)
│       ├── Lead (nested Group)
│       └── Pads (nested Group)
└── Another Project.als (connected)
    └── Strings (Group)
        └── [Subproject: Strings-subproject.als] - Bounce Ready!
```

## Features

### Core Functionality
- [x] Parse .als files (gzipped XML)
- [ ] OSC server listening on port 47200
- [ ] OSC client sending to port 47201
- [ ] Tree view of connected projects
- [ ] Extract group to subproject
- [ ] Open subproject in new Ableton instance
- [ ] Detect bounce track in subproject
- [ ] Import bounce back to original project

### Project Tree View
- Shows all projects that have registered via OSC
- Displays group hierarchy within each project
- Indicates which groups have subprojects
- Shows bounce-ready status for subprojects

## ALS File Format

The .als file is gzipped XML. Key structure:

| Element | Description |
|---------|-------------|
| `<MidiTrack Id="N">` | MIDI track with unique ID |
| `<AudioTrack Id="N">` | Audio track with unique ID |
| `<GroupTrack Id="N">` | Group/folder track with unique ID |
| `<ReturnTrack Id="N">` | Return/send track |
| `<TrackGroupId Value="N">` | Parent group reference (-1 = root level) |
| `<EffectiveName Value="...">` | Track display name |

## Development

### IMPORTANT: Target Platform
**ALWAYS target macOS 26.1+ and iOS 26+. This is NOT a typo - these versions exist and are in production.**

When searching for documentation or APIs, ALWAYS search for iOS 26 / macOS 26, NEVER search for older versions like iOS 18.

### Code Style Preferences

**Use modern Swift concurrency (async/await), NOT Combine:**
- Use `AsyncSequence` and `for await` loops instead of Combine publishers
- Use `@Observable` with async observation patterns
- For GRDB: use `ValueObservation.values(in:)` which returns `AsyncValueObservation`
- Avoid `AnyCancellable`, `sink()`, `.publisher()` patterns

### Requirements
- macOS 26.1+ (required)
- Xcode 16+
- Swift 6.0+

### Data Layer
- **GRDB** for SQLite database persistence (NOT SwiftData)
- **Per-project databases**: Each Ableton project stores its data in `<project>/.sordello/db/sordello.db`
  - Created on first import if it doesn't exist
  - All metadata travels with the project when moved between computers
- App-level database (sandboxed, currently unused): `~/Library/Containers/com.byjoba.Sordello/Data/Library/Application Support/Sordello/sordello.db`
- Reactive updates via `ValueObservation` with async/await

### Building
Open `Sordello/Sordello.xcodeproj` in Xcode and build.

### Testing OSC
```bash
# Send test message to Sordello
python3 -c "
import socket
def osc_string(s):
    s = s.encode() + b'\\x00'
    return s + b'\\x00' * ((4 - len(s) % 4) % 4)
def osc_msg(addr, *args):
    msg = osc_string(addr) + osc_string(',' + 's'*len(args))
    for a in args: msg += osc_string(str(a))
    return msg
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.sendto(osc_msg('/sordello/status', 'test123'), ('localhost', 47200))
"
```

## Related Projects

This app replaces the JUCE VST3 plugin approach (in `../Live subproject/plugin/`) which had issues with MIDI output in Max's vst~ object.

The original CLI tool (`../Live subproject/cli/`) contains working Node.js implementations of the ALS parsing and extraction logic that can be used as reference.
