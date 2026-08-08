# ScreenManager

A lightweight macOS menu bar app for keyboard-driven window management: bind any
window to a numbered slot and jump straight to it, snap windows around the
screen, and move them between displays — all without touching the mouse.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Accessibility permission (prompted on first launch)

## Build & Run

```sh
make run
```

This compiles a release build, assembles `ScreenManager.app`, code-signs it, and
opens it.

| Command | Description |
|---------|-------------|
| `make build` | Build and assemble the `.app` bundle |
| `make run` | Build and launch the app |
| `make test` | Run the unit tests |
| `make clean` | Remove `.build/` and `ScreenManager.app` |

`make build` prefers SwiftPM and falls back to invoking `swiftc` directly if
`swift build` is unavailable.

The tests use [swift-testing](https://github.com/swiftlang/swift-testing), which
ships with Xcode rather than with the Command Line Tools — `make test` needs a
full Xcode install. Building and running the app needs only the Command Line
Tools.

## Hotkeys

All modifiers are configurable under **Settings** in the menu bar; the defaults
are listed here.

### Slots

| Shortcut | Action |
|----------|--------|
| ⌥1 – ⌥9 | Focus the window bound to that slot |
| ⌥1 again | Return to the window you came from |
| ⌥⇧1 – ⌥⇧9 | Bind the current window to that slot |

Binding is confirmed by the slot number flashing in the menu bar. The bind
shortcut always tracks the focus shortcut plus Shift, so the two can never
collide.

### Layout

| Shortcut | Action |
|----------|--------|
| ⌃⌥← / → | Left / right half |
| ⌃⌥↑ / ↓ | Top / bottom half |
| ⌃⌥U / I / J / K | Top-left / top-right / bottom-left / bottom-right quarter |
| ⌃⌥↩ | Maximize |
| ⌃⌥C | Center without resizing |

Thirds and two-thirds layouts are available from **Window Layout** in the menu.

### Displays

| Shortcut | Action |
|----------|--------|
| ⌃⌥⌘← / → | Move the window to the previous / next display |
| ⌃⌥⌘1 – ⌃⌥⌘9 | Move the window to display 1–9 |

Windows keep their relative position and proportional size when they move
between displays, and are clamped to fit if the target is smaller.

## Usage

Click the keyboard icon in the menu bar. Each slot has a submenu:

- **Pick Window…** — a searchable list of every open window. Type to filter,
  arrow keys to move, Return to bind, Escape to cancel.
- **Bind Frontmost Window** — same as ⌥⇧N.
- **Save Current Position** — remembers where the window sits, and puts it back
  there every time you focus the slot.
- **Clear Slot** — unbinds.

Slot labels track the window's current title, so a VS Code slot follows the tab
you have open. A slot whose window has closed is greyed out and marked
`(closed)`; focusing it reopens the window instead.

### Profiles

**Profiles** keeps independent sets of bindings — one for the desk with two
displays, another for the laptop alone — and switches between them in one click.
Duplicating a profile copies the current bindings into it.

### Settings

- Modifiers for the focus, layout, and display shortcuts
- How many slots to expose (1–9)
- Whether pressing a slot again returns you to the previous window
- Whether focusing a slot also restores its saved position
- Launch at login

If macOS refuses a hotkey because another app already owns it, the menu bar
shows a warning listing exactly which combinations failed.

## Reopening closed windows

Focusing a slot whose window is gone brings it back:

1. If the window had a document, it reopens that file in the same app.
2. VS Code project windows reopen via `code --new-window`, with the folder path
   resolved from VS Code's own history database. The `code` CLI is located
   automatically across Homebrew, `/usr/local`, and the app bundle.
3. Otherwise the app itself is launched or activated.

## Permissions

ScreenManager uses the macOS Accessibility API to enumerate, move, and raise
windows. Grant access in **System Settings → Privacy & Security →
Accessibility**. Without it, the menu shows a warning that links straight to the
settings pane.

Launch at login requires the app to be running from `ScreenManager.app` rather
than directly out of `.build/`.

## Project Structure

```
Sources/ScreenManagerCore/     # All logic — imported by the executable and the tests
├── AppDelegate.swift          # Lifecycle, hotkey dispatch, toggle-back state
├── BindingStore.swift         # Slot → window bindings, profiles, migration
├── HotkeyManager.swift        # Carbon hotkey registration, IDs, and the hotkey plan
├── LayoutCalculator.swift     # Pure frame arithmetic (halves, thirds, display moves)
├── LoginItem.swift            # SMAppService registration
├── MenuBarController.swift    # Status item and menus
├── Models.swift               # WindowInfo, SlotBinding, CodableRect
├── Preferences.swift          # Modifier combos and persisted settings
├── WindowManager.swift        # AX API: enumerate, resolve, focus, move, reopen
└── WindowPicker.swift         # Searchable window picker panel
Sources/ScreenManager/main.swift   # Entry point shim
Tests/ScreenManagerTests/          # Unit tests for the pure logic
```

Windows are matched by `CGWindowID` first, then by document path, then by title,
and only finally by list position — so a binding survives other windows opening,
closing, and being renamed.

## Storage

`~/Library/Application Support/ScreenManager/`

- `bindings.json` — profiles and their slot bindings
- `preferences.json` — modifiers and settings

Older single-profile `bindings.json` files are migrated automatically into a
profile named `Default`.
