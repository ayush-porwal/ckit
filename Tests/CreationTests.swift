import Foundation
import Testing

@testable import CKitCore

private func request(_ name: String = "puff-test", start: Bool = true) -> MachineCreationRequest {
    .init(name: name, image: "alpine:3.22", cpus: 1, memoryGiB: 1, startAfterCreation: start)
}

@Suite("Machine creation validation")
struct CreationValidationTests {
    @Test func trimsFieldsAndBuildsNoninteractiveArguments() throws {
        var input = request("  dev-box  ")
        input.image = " alpine:3.22\n"
        let valid = try input.validated()
        #expect(valid.name == "dev-box")
        #expect(
            valid.createArguments == [
                "machine", "create", "--name", "dev-box", "--cpus", "1",
                "--memory", "1G", "--home-mount", "none", "--no-boot", "--progress", "none", "--",
                "alpine:3.22",
            ])
    }

    @Test(arguments: ["", "-flag", "has space", "../path", "💨", String(repeating: "a", count: 64)])
    func rejectsInvalidNames(_ name: String) {
        #expect(throws: CLIError.self) { try request(name).validated() }
    }

    @Test(arguments: ["", "--debug", "alpine latest", "alpine\n:3.22", "alpine\u{0}:3.22"])
    func rejectsInvalidImages(_ image: String) {
        var input = request()
        input.image = image
        #expect(throws: CLIError.self) { try input.validated() }
    }

    @Test func boundsResourcesToHost() {
        for cpus in [0, MachineCreationRequest.maximumCPUs + 1] {
            var input = request()
            input.cpus = cpus
            #expect(throws: CLIError.self) { try input.validated() }
        }
        for memory in [0, MachineCreationRequest.maximumMemoryGiB + 1] {
            var input = request()
            input.memoryGiB = memory
            #expect(throws: CLIError.self) { try input.validated() }
        }
    }
}

actor CreationFixture: ContainerServing {
    enum Failure { case none, beforeCreation, afterCreation, start, lostConnection }
    var running = false
    var items: [Machine] = []
    var calls: [String] = []
    var failure: Failure = .none
    var connectionLost = false
    var delayCreation = false

    func configure(
        running: Bool = false, failure: Failure = .none, duplicate: Bool = false,
        delayed: Bool = false
    ) {
        self.running = running
        self.failure = failure
        delayCreation = delayed
        if duplicate { items = [machine(request(), status: "stopped")] }
    }
    func serviceStatus() async throws -> ServiceStatus {
        if connectionLost { throw CLIError.failed("Connection lost") }
        return .init(status: running ? "running" : "unregistered", client: nil, resources: nil)
    }
    func machines() async throws -> [Machine] {
        if connectionLost { throw CLIError.failed("Connection lost") }
        return items
    }
    func startService() async throws {
        calls.append("service")
        running = true
    }
    func stopService() async throws {
        calls.append("stop-service")
        running = false
    }
    func verifyImage(_ reference: String) async throws -> ImageVerification {
        .init(reference: reference, wasPrepared: false)
    }
    func prepareImage(_ preset: MachineImagePreset) async throws -> ImageVerification {
        .init(reference: preset.reference, wasPrepared: false)
    }
    func createMachine(_ input: MachineCreationRequest) async throws {
        calls.append("create")
        if delayCreation { try await Task.sleep(for: .milliseconds(120)) }
        if failure == .beforeCreation { throw CLIError.failed("Image not found") }
        items.append(machine(input, status: "stopped"))
        if failure == .lostConnection {
            connectionLost = true
            throw CLIError.failed("Connection lost")
        }
        if failure == .afterCreation { throw CLIError.failed("Create returned an error") }
    }
    func startMachine(_ id: String) async throws {
        calls.append("start")
        if failure == .start { throw CLIError.failed("Boot failed") }
        items = items.map { item in
            item.id == id
                ? .init(
                    id: item.id, status: "running", isDefault: item.isDefault, cpus: item.cpus,
                    memory: item.memory, diskSize: nil, ipAddress: nil) : item
        }
    }
    func deleteMachine(_ id: String) async throws {}
    func stopMachine(_ id: String) async throws { calls.append("stop-machine") }
    private func machine(_ input: MachineCreationRequest, status: String) -> Machine {
        .init(
            id: input.name, status: status, isDefault: false, cpus: input.cpus,
            memory: UInt64(input.memoryGiB) * 1_073_741_824, diskSize: nil, ipAddress: nil)
    }
}

@Suite("Machine creation coordination") @MainActor
struct CreationStoreTests {
    @Test func startsServiceCreatesAndBoots() async {
        let client = CreationFixture()
        let store = ContainerStore(client: client)
        let result = await store.createMachine(request())
        #expect(result == .created(warning: nil))
        #expect(await client.calls == ["service", "create", "start"])
        #expect(store.service == .running)
        #expect(store.machines.first?.isRunning == true)
        #expect(!store.isBusy)
    }

    @Test func manualLaunchLeavesNewMachineStopped() async {
        let client = CreationFixture()
        await client.configure(running: true)
        let store = ContainerStore(client: client)
        #expect(await store.createMachine(request(start: false)) == .created(warning: nil))
        #expect(await client.calls == ["create"])
        #expect(store.machines.first?.isStopped == true)
    }

    @Test func freshDuplicateCheckPreventsCLIInvocation() async {
        let client = CreationFixture()
        await client.configure(running: true, duplicate: true)
        let store = ContainerStore(client: client)
        guard case .failed(let message) = await store.createMachine(request()) else {
            Issue.record("Expected duplicate failure")
            return
        }
        #expect(message.contains("already exists"))
        #expect(await client.calls.isEmpty)
    }

    @Test func invalidFormDoesNotStartService() async {
        let client = CreationFixture()
        let store = ContainerStore(client: client)
        guard case .failed = await store.createMachine(request("invalid name")) else {
            Issue.record("Expected validation failure")
            return
        }
        #expect(await client.calls.isEmpty)
    }

    @Test func failedImageCanBeRetried() async {
        let client = CreationFixture()
        await client.configure(running: true, failure: .beforeCreation)
        let store = ContainerStore(client: client)
        #expect(await store.createMachine(request()) == .failed("Image not found"))
        #expect(store.machines.isEmpty)
        #expect(!store.isBusy)
    }

    @Test(arguments: [CreationFixture.Failure.start, .afterCreation])
    func partialSuccessKeepsMachineAndPreventsDuplicateRetry(_ failure: CreationFixture.Failure)
        async
    {
        let client = CreationFixture()
        await client.configure(running: true, failure: failure)
        let store = ContainerStore(client: client)
        guard case .created(let warning) = await store.createMachine(request()) else {
            Issue.record("Expected partial success")
            return
        }
        #expect(warning?.contains("Machine created") == true)
        #expect(store.machines.first?.isStopped == true)
        #expect(!store.isBusy)
    }

    @Test func lossOfConnectionAfterSubmissionIsUncertain() async {
        let client = CreationFixture()
        await client.configure(running: true, failure: .lostConnection)
        let store = ContainerStore(client: client)
        guard case .uncertain(let message) = await store.createMachine(request()) else {
            Issue.record("Expected uncertain outcome")
            return
        }
        #expect(message.contains("Reopen the menu before trying again"))
        #expect(!store.hasLoadedMachines)
        #expect(!store.isBusy)
    }

    @Test func creationHoldsBusyStateAcrossAsyncWork() async throws {
        let client = CreationFixture()
        await client.configure(running: true, delayed: true)
        let store = ContainerStore(client: client)
        await store.refresh()
        let task = Task { await store.createMachine(request()) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.isBusy)
        await store.stopService()
        #expect(
            await store.createMachine(request("second"))
                == .failed("Another action is in progress. Try again when it finishes."))
        _ = await task.value
        #expect(await client.calls == ["create", "start"])
    }
}
