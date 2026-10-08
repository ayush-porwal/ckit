import Foundation
import Testing

@testable import CKitCore

actor DeletionFixture: ContainerServing {
    var items: [Machine] = [
        .init(
            id: "target", status: "stopped", isDefault: true, cpus: 1, memory: 1_073_741_824,
            diskSize: nil, ipAddress: nil),
        .init(
            id: "keep", status: "stopped", isDefault: false, cpus: 1, memory: 1_073_741_824,
            diskSize: nil, ipAddress: nil),
    ]
    var deletedIDs: [String] = []
    var failDelete = false
    var failListingAfterDelete = false
    var delayed = false

    func configure(
        running: Bool = false, failDelete: Bool = false, failListingAfterDelete: Bool = false,
        delayed: Bool = false
    ) {
        self.failDelete = failDelete
        self.failListingAfterDelete = failListingAfterDelete
        self.delayed = delayed
        if running {
            let item = items[0]
            items[0] = .init(
                id: item.id, status: "running", isDefault: item.isDefault, cpus: item.cpus,
                memory: item.memory, diskSize: nil, ipAddress: nil)
        }
    }
    func serviceStatus() async throws -> ServiceStatus {
        .init(status: "running", client: nil, resources: nil)
    }
    func machines() async throws -> [Machine] {
        if failListingAfterDelete && !deletedIDs.isEmpty {
            throw CLIError.failed("List unavailable")
        }
        return items
    }
    func deleteMachine(_ id: String) async throws {
        deletedIDs.append(id)
        if delayed { try await Task.sleep(for: .milliseconds(120)) }
        if failDelete { throw CLIError.failed("Delete failed") }
        items.removeAll { $0.id == id }
    }
    func startService() async throws {}
    func stopService() async throws {}
    func startMachine(_ id: String) async throws {}
    func stopMachine(_ id: String) async throws {}
    func createMachine(_ request: MachineCreationRequest) async throws {}
    func verifyImage(_ reference: String) async throws -> ImageVerification {
        .init(reference: reference, wasPrepared: false)
    }
    func prepareImage(_ preset: MachineImagePreset) async throws -> ImageVerification {
        .init(reference: preset.reference, wasPrepared: false)
    }
}

@Suite("Machine deletion") @MainActor
struct DeletionTests {
    @Test(arguments: [false, true])
    func removesOnlySelectedMachineAndConfirmsAbsence(_ running: Bool) async {
        let client = DeletionFixture()
        await client.configure(running: running)
        let store = ContainerStore(client: client)
        await store.refresh()
        await store.deleteMachine(store.machines[0])
        #expect(await client.deletedIDs == ["target"])
        #expect(store.machines.map(\.id) == ["keep"])
        #expect(store.hasLoadedMachines && store.errorMessage == nil && !store.isBusy)
    }

    @Test func failedDeletionKeepsMachineAndReportsError() async {
        let client = DeletionFixture()
        await client.configure(failDelete: true)
        let store = ContainerStore(client: client)
        await store.refresh()
        await store.deleteMachine(store.machines[0])
        #expect(store.machines.map(\.id) == ["target", "keep"])
        #expect(store.errorMessage == "Delete failed")
        #expect(!store.isBusy)
    }

    @Test func unavailableListingCannotConfirmDeletion() async {
        let client = DeletionFixture()
        await client.configure(failListingAfterDelete: true)
        let store = ContainerStore(client: client)
        await store.refresh()
        await store.deleteMachine(store.machines[0])
        #expect(!store.hasLoadedMachines)
        #expect(store.errorMessage == "List unavailable")
        #expect(!store.isBusy)
    }

    @Test func staleMissingAndUnavailableTargetsNeverReachCLI() async {
        let client = DeletionFixture()
        let store = ContainerStore(client: client)
        await store.refresh()
        let target = store.machines[0]
        store.hasLoadedMachines = false
        await store.deleteMachine(target)
        store.hasLoadedMachines = true
        store.service = .stopped
        await store.deleteMachine(target)
        store.service = .running
        store.machines = []
        await store.deleteMachine(target)
        #expect(await client.deletedIDs.isEmpty)
    }

    @Test func deletionBlocksRepeatedAndOverlappingActions() async throws {
        let client = DeletionFixture()
        await client.configure(delayed: true)
        let store = ContainerStore(client: client)
        await store.refresh()
        let target = store.machines[0]
        let task = Task { await store.deleteMachine(target) }
        try await Task.sleep(for: .milliseconds(25))
        #expect(store.operation == .deleteMachine("target"))
        await store.deleteMachine(target)
        await store.stopService()
        await store.refresh()
        await task.value
        #expect(await client.deletedIDs == ["target"])
        #expect(store.service == .running && !store.isBusy)
    }

    @Test func CLIReceivesExactIDWithoutOptionOrShellEvaluation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CKit-delete-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("container")
        let arguments = root.appendingPathComponent("arguments")
        let body =
            "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + ShellEscaping.quote(arguments.path) + "\n"
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let id = "--flag; $(not-a-command) 'quoted'"
        try await ContainerClient(executable: script.path).deleteMachine(id)
        #expect(
            try String(contentsOf: arguments, encoding: .utf8) == "machine\ndelete\n--\n\(id)\n")
    }
}
