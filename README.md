# ScreenManager

A lightweight macOS menu bar app that lets you bind any open window to a hotkey slot and jump to it instantly.

## How it works

Assign up to 9 windows to slots 1–9 via the menu bar. Press **Ctrl+Option+N** to instantly raise and focus the window bound to slot N, from anywhere.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Accessibility permission (prompted on first launch)

## Build & Run

```sh
make run
```

This compiles a release build, assembles `ScreenManager.app`, code-signs it, and opens it.

| Command | Description |
|---------|-------------|
| `make build` | Build and assemble the `.app` bundle |
| `make run` | Build and launch the app |
| `make clean` | Remove `.build/` and `ScreenManager.app` |

## Usage

1. Click the keyboard icon in the menu bar.
2. Click a slot (e.g. `[1] (empty)`) to open the window picker.
3. Select any open window to bind it to that slot.
4. Press **Ctrl+Option+1–9** to jump to the bound window.

To clear a slot, click it in the menu bar and choose **Clear slot N**.

## Permissions

ScreenManager uses the macOS Accessibility API to enumerate and raise windows. Grant access in **System Settings → Privacy & Security → Accessibility**. If permission is missing, the picker will show a warning with a link to open the settings pane directly.

## Project Structure

```
Sources/ScreenManager/
├── main.swift            # Entry point
├── AppDelegate.swift     # App lifecycle, wires components together
├── HotkeyManager.swift   # Registers Ctrl+Option+1–9 via Carbon event API
├── WindowManager.swift   # AX API: enumerate windows, focus a binding
├── MenuBarController.swift # Status item, slot menu, window picker
├── BindingStore.swift    # Persists slot → window bindings
└── Models.swift          # WindowInfo and SlotBinding types
```

## Hotkeys

| Shortcut | Action |
|----------|--------|
| Ctrl+Option+1 | Focus window bound to slot 1 |
| Ctrl+Option+2 | Focus window bound to slot 2 |
| … | … |
| Ctrl+Option+9 | Focus window bound to slot 9 |

Ctrl+Option was chosen to avoid conflicts with common shortcuts in browsers and editors.
