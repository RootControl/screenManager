import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkeyManager = HotkeyManager()
    let windowManager = WindowManager()
    let bindingStore = BindingStore()
    var menuBarController: MenuBarController?

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        WindowManager.promptForAccessibility()

        hotkeyManager.onHotkeyPressed = { [weak self] slot in
            guard let self,
                  let binding = self.bindingStore.binding(forSlot: slot)
            else { return }
            self.windowManager.focus(binding: binding)
        }
        hotkeyManager.registerAll()

        menuBarController = MenuBarController(store: bindingStore, windowManager: windowManager)
    }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregisterAll()
    }
}
