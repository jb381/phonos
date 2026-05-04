# Phonos Mac Client

Native macOS menu-bar app for the Phonos dictation system.

## Requirements

- macOS 14+ (Sonoma)
- Xcode 15+
- Permissions: Microphone, Accessibility

## Setup

```bash
# Open in Xcode
open Package.swift

# Or build the app bundle from CLI
./build.sh
```

## Command Line

From this directory, you can build and launch the app directly:

```bash
swift build
swift run Phonos
```

`swift run Phonos` is useful during development, but `./build.sh` creates the app bundle with the permission usage descriptions macOS expects.

## Features

- Menu-bar status item with connection indicator
- Global hotkey support (Fn/Globe → left Control)
- Hold-to-record and toggle recording modes
- Direct paste into active application
- Model selector from server
- Transcript preview

## Permissions

First launch will prompt for:
1. **Microphone** — to capture audio for transcription
2. **Accessibility** — for global hotkey and paste automation

Grant both in System Settings → Privacy & Security.
