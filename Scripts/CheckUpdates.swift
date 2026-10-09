import AppKit
import Sparkle

@MainActor
final class UpdateFixture: UpdateChecking {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = true
    var checks = 0
    func checkForUpdates() { checks += 1 }
}

@main
struct CheckUpdates {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let store = ContainerStore(executable: "/nonexistent/container")
        let fixture = UpdateFixture()
        let controller = ContainerMenuController(
            store: store, installsStatusItem: false, updates: fixture)
        let root = controller.menu
        try check(root.title == "Ckit", "Visible app name uses a lowercase k")
        let checkItem = root.items.first { $0.title == "Check for Updates…" }!
        let automaticItem = root.items.first { $0.title == "Automatically Check for Updates" }!
        try check(automaticItem.state == .on, "Automatic checks reflect updater preferences")
        root.performActionForItem(at: root.index(of: checkItem))
        try check(fixture.checks == 1, "Manual check reaches the updater")
        root.performActionForItem(at: root.index(of: automaticItem))
        try check(
            !fixture.automaticallyChecksForUpdates && automaticItem.state == .off,
            "Automatic checks can be turned off")
        store.operation = .createMachine("fixture")
        try await settle()
        try check(!checkItem.isEnabled, "Busy operations disable manual update checks")
        root.performActionForItem(at: root.index(of: checkItem))
        try check(fixture.checks == 1, "Busy operations cannot start update checks")
        store.operation = nil
        try await settle()
        try check(checkItem.isEnabled, "Update checks recover after an operation")
        fixture.canCheckForUpdates = false
        store.operation = .checkImage
        try await settle()
        store.operation = nil
        try await settle()
        try check(!checkItem.isEnabled, "Concurrent Sparkle checks disable the menu action")

        // The fixture bundle disables automatic checks, so this validates Sparkle's
        // configuration and helper layout without contacting an update server.
        let validation = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        try validation.updater.start()
        let updates = UpdateController(store: store)
        try await settle()
        try check(updates.canCheckForUpdates, "Sparkle starts with valid bundle configuration")
        try check(
            updates.responds(
                to: NSSelectorFromString(
                    "updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:")),
            "Sparkle can invoke the relaunch-safety delegate")
        try updates.updater(validation.updater, mayPerform: .updates)
        store.operation = .checkImage
        var rejectedBusyCheck = false
        do {
            try updates.updater(validation.updater, mayPerform: .updatesInBackground)
        } catch {
            rejectedBusyCheck = (error as NSError).domain == "dev.local.ckit.updates"
        }
        try check(rejectedBusyCheck, "Automatic checks cannot interrupt a container operation")
        store.operation = nil
        var installs = 0
        try check(
            !updates.postponeInstallationIfBusy { installs += 1 },
            "An idle app does not postpone installation")
        store.operation = .createMachine("fixture")
        try check(
            updates.postponeInstallationIfBusy { installs += 1 },
            "A running operation postpones update relaunch")
        try check(installs == 0, "Installation waits for the operation")
        store.operation = nil
        try await settle()
        try check(installs == 1, "Installation resumes once after the operation")
        print("Ckit update checks passed without network requests or installing an update.")
    }

    static func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw NSError(
                domain: "Ckit.UpdateFixture", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: message
                ])
        }
    }
}
