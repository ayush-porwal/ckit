import AppKit

@main
struct CKitApp {
    @MainActor
    static func main() {
        // Exercise dyld and code signing without starting UI, containers, or updates.
        if CommandLine.arguments.contains("--check-launch") {
            print("Ckit launch check passed.")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = CKitApplicationDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class CKitApplicationDelegate: NSObject, NSApplicationDelegate {
    private var controller: ContainerMenuController?
    private var store: ContainerStore?
    private var updates: UpdateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = BrandIcon.applicationImage
        let store = ContainerStore()
        self.store = store
        let updates = UpdateController(store: store)
        self.updates = updates
        controller = ContainerMenuController(store: store, updates: updates)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store?.operation != nil ? .terminateCancel : .terminateNow
    }
}
