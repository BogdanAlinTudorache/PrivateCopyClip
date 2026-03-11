# PrivateCopyClip

A silent, menu bar clipboard history app for macOS that recovers lost work when apps crash or you accidentally submit without saving.

## 🎯 Problem Solved

When composing long prompts or code snippets in Claude Code (or any text editor) by copying from multiple sources:
- **App crashes** lose all unsaved work instantly
- **Accidental submissions** (cmd+enter) wipe out everything you copied but haven't pasted
- You have **no way to recover** the text you spent time gathering

**PrivateCopyClip** silently records every text copy you make, enabling **one-click recovery** from the menu bar in seconds.

## ✨ Features

- **Silent background monitoring** — Records every text copy without notifications
- **Quick recovery** — Click menu bar icon to see last 30+ items copied in the last hour
- **Time-grouped history** — "Last 10 minutes", "Last hour", "Today" sections for fast browsing
- **One-click restore** — Click any entry → copied to clipboard, ready to paste immediately
- **Search filtering** — Find old copies by content
- **Password detection** — Silently skips passwords, API keys, and secrets (enabled by default)
- **Configurable retention** — Keep 10, 50, or 100 entries (default: 100)
- **Auto-clear** — Automatically clear entries older than 30 days (enabled by default)
- **100% local** — All data stored locally, zero network, zero telemetry
- **No dock icon** — Menu bar only, stays out of the way

## 🔒 Privacy & Security

- **Local-only storage**: All clipboard history saved to `~/Library/Application Support/PrivateCopyClip/history.json`
- **No cloud sync**: Your text never leaves your machine
- **No telemetry**: Zero tracking, zero analytics
- **Password detection**: Automatically detects and skips:
  - Common keywords: password, api_key, token, private_key, credit_card, ssn
  - JWT/Bearer tokens
  - SSH/PEM keys
  - Email + password combos
  - Heuristic detection of strong passwords
- **Manual control**: Delete entries at any time, clear all history with one click

## 📋 Requirements

- macOS 12.0 or later
- Swift 5.7+ (usually pre-installed)

## 🚀 Installation

### From Source (Recommended for First-Time Use)

```bash
# Clone or download the repository
cd /path/to/PrivateCopyClip

# Build the app
chmod +x build.sh
./build.sh

# Install to Applications folder
cp -r build/PrivateCopyClip.app /Applications/

# Launch
open /Applications/PrivateCopyClip.app
```

### Quick Build & Run

```bash
./build.sh && open build/PrivateCopyClip.app
```

## 💻 Usage

1. **Launch the app** from Applications (or run `./build.sh && open build/PrivateCopyClip.app`)
2. **See the menu bar icon**: "📋 N items | Last: [preview]"
3. **Click the icon** to open the clipboard history dropdown
4. **Search** to find specific copies (searches text content)
5. **Browse time groups** ("Last 10 min", "Last hour", "Today") to find recent copies
6. **Click "Copy" button** on any entry → text is copied to your clipboard, ready to paste

### Settings

Click the ⚙️ icon in the history view to configure:
- **History limit**: Keep 10, 50, or 100 entries (default: 100)
- **Password detection**: Toggle to skip passwords (enabled by default)
- **Auto-clear**: Toggle to auto-delete entries >30 days old (enabled by default)
- **Storage info**: See current entry count and storage path

## 🔍 How It Works

### Background Monitoring
- Runs in the background, polling clipboard every 0.5 seconds
- Uses efficient hash-based change detection (minimal CPU overhead)
- When clipboard changes, checks if content matches password patterns
- If not sensitive, saves to memory and marks for disk write

### Persistent Storage
- Every 30 seconds (or on clear/limit), all entries saved to `history.json`
- Uses atomic writes for safety (won't corrupt even if app crashes mid-write)
- On app launch, loads entire history from disk
- Auto-clears entries older than 30 days (toggle in settings)

### One-Click Recovery
- Click any entry in the menu bar dropdown
- Text is copied to NSPasteboard (macOS clipboard)
- Immediately paste in Claude Code or any app with cmd+v
- No extra steps, no friction

## 🛠️ Architecture

```
main.swift (single file, ~700 lines)
├── Data Models
│   ├── ClipboardEntry (Codable)
│   └── DateGroup (UI grouping)
├── Services
│   ├── PasswordDetector (conservative heuristics)
│   └── ClipboardStorage (JSON persistence, atomic writes)
├── ViewModel
│   └── ClipboardMonitor (@StateObject, background polling, batched writes)
├── UI Components
│   ├── ContentView (router between history/settings)
│   ├── ClipboardHistoryView (main recovery interface)
│   ├── ClipboardEntryRow (individual entry display)
│   └── SettingsView (configuration)
└── App Entry
    └── PrivateCopyClipApp (@main, MenuBarExtra)
```

## 📊 Performance

- **CPU**: <1% when idle, brief spike only on actual clipboard changes
- **Memory**: ~5-20MB (stores 100 entries with ~50KB average per entry)
- **Disk**: ~5MB for 100 entries of typical text
- **Polling**: 0.5 second intervals, hash-based change detection (proven by sysMeter)
- **Disk writes**: Batched every 30 seconds (not per-entry)

## 🔐 Password Detection Patterns

Patterns detected (and silently skipped):

1. **Keywords**: password, passwd, pwd, secret, api_key, token, private_key, bearer, credit_card, ssn
2. **Tokens**: JWT (starts with `eyJ`), Bearer tokens
3. **Keys**: SSH/PEM keys (`-----BEGIN...-----END`)
4. **Combos**: Email + password in same text
5. **Heuristic**: >12 character password-like strings (uppercase + lowercase + numbers)

**Philosophy**: Better to miss a real password than annoy users with false positives.

## 🚪 Data Storage Location

All data stored in:
```
~/Library/Application Support/PrivateCopyClip/history.json
```

Format: JSON array of ClipboardEntry objects with id, timestamp, text, preview, byteSize.

Example:
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": "2026-03-11T14:30:00Z",
    "text": "def calculate_checksum(): ...",
    "preview": "def calculate_checksum(): ...",
    "byteSize": 1024,
    "isSensitive": false
  }
]
```

## ⚙️ Configuration (UserDefaults)

Stored in standard macOS preferences:
- `historyLimit` (Int, default: 100) — entries to keep
- `passwordDetectionEnabled` (Bool, default: true) — skip passwords
- `autoClearAfterDays` (Int, default: 30) — clear old entries

## 🐛 Troubleshooting

### No clipboard history after restart
- Check `~/Library/Application Support/PrivateCopyClip/history.json` exists
- If missing, the app will recreate it on next copy

### Password detection skipping legitimate text
- Some legitimate multi-word passwords might trigger heuristics
- Disable "Ignore passwords and secrets" in settings to capture everything
- Re-enable when done

### App not appearing in menu bar
- Check System Settings > General > Login Items to see if app auto-starts
- Manually launch: `open /Applications/PrivateCopyClip.app`

### Memory or disk usage concerns
- Reduce history limit to 10 or 50 entries (settings)
- Enable auto-clear to delete entries >30 days old

## 📝 Build Details

- **Language**: Swift with SwiftUI
- **Framework**: Foundation, SwiftUI, AppKit (NSPasteboard, NSPasteboard.general)
- **Compiler**: swiftc (no Xcode required)
- **Bundle**: Standard macOS app bundle (.app)
- **Activation Policy**: `.accessory` (menu bar only, no dock icon)

## 🔄 Version History

- **v1.0** (Initial release)
  - Silent clipboard monitoring
  - Time-grouped history
  - One-click restore
  - Password detection
  - Settings (retention, detection toggle)
  - Auto-clear after 30 days

## 🚀 Future Ideas (v1.1+)

- Encryption for stored data
- Multi-device sync (intentionally deferred for privacy)
- Rich content support (images, files)
- App context tagging (know which app each copy came from)
- Keyboard shortcuts for quick restore
- Duplicate detection
- Compression for large history

## 📄 License

Built as a personal utility. Share freely.

## 💬 Feedback

Questions? Create an issue or fork the repo to contribute improvements.

---

**Built with ❤️ to recover lost work in Claude Code**
