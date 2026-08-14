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

| ⌃⌥R | Restore every slot's saved position at once |
| ⌃⌥Z | Undo the last layout or display move |

### Displays and focus

| Shortcut | Action |
|----------|--------|
| ⌃⌥⌘← / → | Move the window to the previous / next display |
| ⌃⌥⌘1 – ⌃⌥⌘9 | Move the window to display 1–9 |
| ⌃⌥⌘H / J / K / L | Focus the window to the left / below / above / right |

Windows keep their relative position and proportional size when they move
between displays, and are clamped to fit if the target is smaller. Directional
focus works across every app and display, preferring windows in the same row or
column so focus travels in straight lines rather than diagonally.

### Spaces

| Shortcut | Action |
|----------|--------|
| ⌃⌥⇧1 – ⌃⌥⇧9 | Move the window to Space 1–9 |

macOS exposes no public API for Spaces, so these use a private one, looked up at
runtime. If a future macOS removes it, the Spaces menu and shortcuts simply
disappear and everything else keeps working.

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

**Use for This Display Setup** ties the active profile to your current monitor
arrangement. Plug in or unplug a display and the matching profile activates on
its own.

### Arrangements

A profile remembers your slots; an **arrangement** remembers the whole screen.
*Save Current Arrangement…* captures where every open window sits, and restoring
it puts them all back. Windows that have since closed are skipped.

### Settings

- Modifiers for the focus, layout, display, and Space shortcuts
- How many slots to expose (1–9)
- What a second press of a slot does: go back, cycle the app's windows, or nothing
- Whether focusing a slot also restores its saved position
- Whether profiles follow the display setup
- Snap windows dragged to a screen edge, with a live preview of where they land
- Show a slot overview while the focus modifier is held down
- Hide specific apps from the window picker
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
Sources/ScreenManagerCore/       # All logic — imported by the executable and the tests
├── AppDelegate.swift            # Lifecycle, hotkey dispatch, repeat-press state
├── ArrangementStore.swift       # Named whole-screen window captures
├── BindingStore.swift           # Slot → window bindings, profiles, migration
├── DragSnapController.swift     # Event tap for edge snapping, with preview
├── HotkeyManager.swift          # Carbon hotkey registration, IDs, and the hotkey plan
├── LayoutCalculator.swift       # Pure frame arithmetic (layouts, direction, fingerprints)
├── LoginItem.swift              # SMAppService registration
├── MenuBarController.swift      # Status item and menus
├── Models.swift                 # WindowInfo, SlotBinding, WindowSnapshot, WindowQuery
├── Preferences.swift            # Modifier combos and persisted settings
├── SlotHUD.swift                # Hold-modifier slot overview
├── SpacesBridge.swift           # Private Spaces API, resolved via dlsym
├── WindowManager.swift          # AX API: enumerate, resolve, focus, move, reopen
└── WindowPicker.swift           # Searchable window picker panel
Sources/ScreenManager/main.swift   # Entry point shim
Tests/ScreenManagerTests/          # Unit tests for the pure logic
```

Windows are matched by `CGWindowID` first, then by document path, then by title,
and only finally by list position — so a binding survives other windows opening,
closing, and being renamed.

## Storage

`~/Library/Application Support/ScreenManager/`

- `bindings.json` — profiles and their slot bindings
- `arrangements.json` — saved whole-screen arrangements
- `preferences.json` — modifiers and settings

Older single-profile `bindings.json` files are migrated automatically into a
profile named `Default`. Preferences decode field by field, so a file written by
an older or newer build keeps every setting it still recognises instead of
resetting to defaults.

Bindings self-heal: when a window has to be found by document, title, or
position — because the app restarted and its window ID changed — the new ID is
written back, so the next lookup matches on identity again.
