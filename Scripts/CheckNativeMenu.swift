import AppKit

actor MenuFixtureClient: ContainerServing {
    var running = true
    var machineRunning = false
    var failList = false
    var deleted = false
    let id = "development-machine-with-a-long-name"
    func serviceStatus() async throws -> ServiceStatus {
        ServiceStatus(status: running ? "running" : "unregistered", client: nil, resources: nil)
    }
    func machines() async throws -> [Machine] {
        if failList { throw CLIError.failed("Fixture list failure") }
        if deleted { return [] }
        return [
            .init(
                id: id, status: machineRunning ? "running" : "stopped", isDefault: true,
                cpus: 4, memory: 4_294_967_296, diskSize: nil, ipAddress: nil)
        ]
    }
    func startService() async throws { running = true }
    func stopService() async throws { running = false }
    func startMachine(_ id: String) async throws { machineRunning = true }
    func verifyImage(_ reference: String) async throws -> ImageVerification {
        .init(reference: reference, wasPrepared: false)
    }
    func prepareImage(_ preset: MachineImagePreset) async throws -> ImageVerification {
        .init(reference: preset.reference, wasPrepared: false)
    }
    func createMachine(_ request: MachineCreationRequest) async throws {}
    func stopMachine(_ id: String) async throws { machineRunning = false }
    func deleteMachine(_ id: String) async throws { deleted = true }
    func failNextListing() { failList = true }
    func recoverListing() { failList = false }
}

@main struct CheckNativeMenu {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let client = MenuFixtureClient()
        let store = ContainerStore(client: client)
        await store.refresh()
        let controller = ContainerMenuController(store: store, installsStatusItem: false)
        let root = controller.menu
        try check(root.items.allSatisfy { $0.view == nil }, "Root uses standard native menu items")
        try check(
            root.items.last?.title == "Quit CKit"
                && !root.items.contains { $0.title == "About CKit" },
            "Quit is last and About is omitted")
        try check(
            !root.items.contains {
                ["Refresh", "Preferences", "Choose Executable…", "Retry"].contains($0.title)
            },
            "Healthy menu omits settings and refresh controls")
        let row = root.items.first { $0.title == "development-machine-with-a-long-name" }!
        let submenu = row.submenu!
        try check(submenu.items.allSatisfy { $0.view == nil }, "Machine submenu uses native items")
        try check(
            submenu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
                "Start Machine", "Open Terminal", "Delete Machine",
            ], "Machine submenu contains only actions")
        try check(
            row.subtitle?.contains("4 CPU · 4 GB · Stopped") == true,
            "Machine details appear once, on its parent row")
        try check(!submenu.items[1].isEnabled, "Terminal disabled for a stopped machine")
        try check(
            submenu.items[2].isSeparatorItem && submenu.items[3].image?.isTemplate == true,
            "Delete has a separator and custom template icon")
        try check(submenu.items[3].isEnabled, "Stopped machines can be deleted")
        submenu.performActionForItem(at: 0)
        try await settle()
        try check(
            store.machines.first?.isRunning == true, "Machine action routes through the store")
        try check(
            root.items.contains { $0 === row } && row.submenu === submenu,
            "Refresh preserves open submenu identity")
        try check(submenu.items[1].isEnabled, "Terminal enabled after machine starts")
        try check(submenu.items[3].isEnabled, "Running machines can be deleted")
        root.performActionForItem(at: 0)
        try await settle()
        try check(
            store.service == .stopped && store.machines.isEmpty,
            "Direct native Stop clears machines")
        try check(root.items[0].title == "Start Service", "Native menu updates after Stop")
        try check(
            root.items.contains {
                $0.title == "Create Machine…" && $0.isEnabled && $0.keyEquivalent == "n"
            },
            "Creation is available while service is stopped")
        root.performActionForItem(at: 0)
        try await settle()
        try check(store.service == .running, "Native Start routes through the store")
        await client.failNextListing()
        await store.refresh()
        try await settle()
        let stale = root.items.first { $0.title == "development-machine-with-a-long-name" }!
        try check(!stale.isEnabled, "Stale machine controls are disabled on listing failure")
        try check(
            root.items.contains { $0.title == "Couldn't update status" }, "Failure remains visible")
        try check(
            root.items.contains { $0.title == "Retry" && $0.isEnabled },
            "Failure offers an actionable Retry")
        await client.recoverListing()
        root.performActionForItem(at: root.items.firstIndex { $0.title == "Retry" }!)
        try await settle()
        try check(
            store.errorMessage == nil && store.hasLoadedMachines,
            "Retry recovers status and clears the error")
        try check(!root.items.contains { $0.title == "Retry" }, "Retry disappears after recovery")
        store.operation = .stopService
        try await settle()
        try check(
            !root.items[0].isEnabled && root.items[0].title == "Stopping Service…",
            "Busy service action is disabled")
        try check(
            root.items.contains { $0.title == "Quit CKit" && !$0.isEnabled },
            "Quit is disabled during an action")
        try check(
            root.items.contains { $0.title == "Create Machine…" && !$0.isEnabled },
            "Creation is disabled during an action")
        let activeRow = root.items.first { $0.title == client.id }!
        try check(
            activeRow.submenu!.items.allSatisfy { $0.isSeparatorItem || !$0.isEnabled },
            "Busy state disables all machine actions")
        store.operation = .deleteMachine(client.id)
        try await settle()
        try check(
            activeRow.subtitle?.contains("Deleting…") == true
                && activeRow.submenu!.items[3].title == "Deleting Machine…",
            "Deletion progress appears on the machine and action")
        store.operation = nil
        try await settle()
        activeRow.submenu!.performActionForItem(at: 3)
        try await settle()
        try check(
            store.machines.isEmpty && !root.items.contains { $0.title == client.id },
            "Delete routes through the store and removes the native row")
        store.errorMessage = nil
        store.service = .unknown
        try await settle()
        try check(
            root.items.contains { $0.title == "Checking the service…" },
            "Unknown service state stays explicit")
        store.service = .unavailable
        try await settle()
        try check(
            root.items.contains { $0.title == "Retry" && $0.isEnabled },
            "Unavailable service has a retry without Preferences")
        try check(
            !root.items[0].isEnabled,
            "Unavailable service isn't presented as a Start or Stop action")
        print("Native menu checks passed; fixtures only, no real service changed.")
    }

    static func settle() async throws { try await Task.sleep(for: .milliseconds(80)) }
    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CLIError.failed("FAIL: \(message)") }
        print("PASS: \(message)")
    }
}
