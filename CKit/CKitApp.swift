import AppKit

@main
struct CKitApp {
    @MainActor
    static func main() {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = BrandIcon.applicationImage
        controller = ContainerMenuController(store: ContainerStore())
    }
}
