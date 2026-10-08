import Foundation
import Testing

@testable import CKitCore

@Suite("CLI decoding and execution")
struct CoreTests {
    @Test func terminalInputProvidesTTYAndWindowSize() async throws {
        let result = try await ProcessRunner().run(
            executable: "/bin/sh",
            arguments: ["-c", "test -t 0 && stty size"], terminalInput: true)
        #expect(result.exitCode == 0)
        #expect(result.output == "24 80")
    }

    @Test func terminalInputStillHonorsTimeout() async {
        await #expect(throws: CLIError.self) {
            try await ProcessRunner().run(
                executable: "/bin/sleep", arguments: ["30"],
                timeout: 0.05, terminalInput: true)
        }
    }

    @Test func decodeInstalledMachineSchema() throws {
        let data = Data(
            #"[{"diskSize":5431656448,"status":"stopped","id":"dsa","cpus":4,"default":true,"memory":4294967296,"createdDate":"2026-08-03T08:57:50Z"}]"#
                .utf8)
        let machine = try JSONDecoder().decode([Machine].self, from: data)[0]
        #expect(machine.id == "dsa")
        #expect(machine.isStopped)
        #expect(machine.isDefault)
        #expect(machine.memoryLabel == "4 GB")
        #expect(machine.ipAddress == nil)
    }

    @Test(arguments: ["unregistered", "not running"])
    func stoppedServiceStates(_ status: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": status])
        #expect(try JSONDecoder().decode(ServiceStatus.self, from: data).state == .stopped)
    }

    @Test func unknownServiceStateIsNotStopped() throws {
        let data = Data(#"{"status":"broken"}"#.utf8)
        #expect(try JSONDecoder().decode(ServiceStatus.self, from: data).state == .unavailable)
    }

    @Test func capturesBothStreamsAndExitCode() async throws {
        let result = try await ProcessRunner().run(
            executable: "/bin/sh", arguments: ["-c", "printf out; printf err >&2; exit 7"])
        #expect(result.output == "out")
        #expect(result.errorOutput == "err")
        #expect(result.exitCode == 7)
    }

    @Test func preservesArgumentsWithoutShellEvaluation() async throws {
        let argument = "name with 'quotes'; $(touch /tmp/ckit-should-not-exist)"
        let result = try await ProcessRunner().run(
            executable: "/usr/bin/printf", arguments: ["%s", argument])
        #expect(result.output == argument)
    }

    @Test func drainsLargeOutputWithoutPipeDeadlock() async throws {
        let result = try await ProcessRunner().run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "head -c 200000 /dev/zero | tr '\\000' x; head -c 200000 /dev/zero | tr '\\000' y >&2",
            ], timeout: 5)
        #expect(result.output.count == 200000)
        #expect(result.errorOutput.count == 200000)
    }

    @Test func boundsExcessiveOutput() async throws {
        let result = try await ProcessRunner().run(
            executable: "/bin/sh", arguments: ["-c", "head -c 1100000 /dev/zero | tr '\\000' x"],
            timeout: 5)
        #expect(result.output.hasSuffix("[Output truncated]"))
        #expect(result.output.count < 1_049_000)
    }

    @Test func timeoutTerminatesUnresponsiveCommand() async throws {
        do {
            _ = try await ProcessRunner().run(
                executable: "/bin/sleep", arguments: ["30"], timeout: 0.05)
            Issue.record("A hanging command should time out")
        } catch CLIError.timedOut {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func cancellationBeforeLaunchDoesNotHang() async throws {
        let task = Task {
            try await ProcessRunner().run(executable: "/bin/sleep", arguments: ["30"])
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func cancellationDuringCommandDoesNotHang() async throws {
        let task = Task {
            try await ProcessRunner().run(executable: "/bin/sleep", arguments: ["30"])
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func missingExecutableHasActionableError() async throws {
        do {
            _ = try await ProcessRunner().run(
                executable: "/does/not/exist/container", arguments: [])
            Issue.record("Expected a missing executable error")
        } catch CLIError.missingExecutable {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func shellEscapingRoundTripsUntrustedNames() async throws {
        let name = "machine 'with quotes'; $HOME\nsecond line"
        let result = try await ProcessRunner().run(
            executable: "/bin/sh", arguments: ["-c", "printf '%s' " + ShellEscaping.quote(name)])
        #expect(result.output == name)
    }

    @Test @MainActor func terminalScriptUsesInteractiveFlagsAndQuotedArguments() {
        let script = TerminalLauncher.script(
            executable: "/path with space/container", machine: "a'b")
        #expect(
            script.contains(
                "'/path with space/container' machine run --name 'a'\\''b' --interactive --tty"))
        #expect(script.contains("rm -f -- \"$0\""))
    }
}

actor MockClient: ContainerServing {
    var state = "running"
    var machineState = "stopped"
    var failListing = false
    var failStatus = false
    var failAction = false
    var statusCalls = 0
    var actions = 0

    func configure(failListing: Bool = false, failStatus: Bool = false, failAction: Bool = false) {
        self.failListing = failListing
        self.failStatus = failStatus
        self.failAction = failAction
    }

    func serviceStatus() async throws -> ServiceStatus {
        statusCalls += 1
        if failStatus { throw CLIError.failed("XPC unavailable") }
        return ServiceStatus(
            status: state, client: .init(version: "1.5.0"), resources: .init(containersRunning: 0))
    }

    func machines() async throws -> [Machine] {
        if failListing { throw CLIError.failed("Machine list failed") }
        return [
            .init(
                id: "dsa", status: machineState, isDefault: true, cpus: 4, memory: 4_294_967_296,
                diskSize: nil, ipAddress: nil)
        ]
    }

    func startService() async throws {
        actions += 1
        state = "running"
    }
    func stopService() async throws {
        actions += 1
        state = "unregistered"
    }
    func startMachine(_ id: String) async throws {
        actions += 1
        machineState = "running"
        if failAction { throw CLIError.failed("Start failed after boot") }
    }
    func verifyImage(_ reference: String) async throws -> ImageVerification {
        .init(reference: reference, wasPrepared: false)
    }
    func prepareImage(_ preset: MachineImagePreset) async throws -> ImageVerification {
        .init(reference: preset.reference, wasPrepared: false)
    }
    func createMachine(_ request: MachineCreationRequest) async throws {}
    func deleteMachine(_ id: String) async throws {}
    func stopMachine(_ id: String) async throws {
        actions += 1
        machineState = "stopped"
    }
}

@Suite("State coordination") @MainActor
struct StoreTests {
    @Test func serviceStopClearsMachineRows() async {
        let store = ContainerStore(client: MockClient())
        await store.refresh()
        #expect(store.machines.count == 1)
        await store.stopService()
        #expect(store.service == .stopped)
        #expect(store.machines.isEmpty)
        #expect(!store.isBusy)
    }

    @Test func listingFailureKeepsKnownServiceStateAndDisablesRows() async {
        let client = MockClient()
        let store = ContainerStore(client: client)
        await store.refresh()
        await client.configure(failListing: true)
        await store.refresh()
        #expect(store.service == .running)
        #expect(store.machines.count == 1)
        #expect(!store.hasLoadedMachines)
        #expect(store.errorMessage == "Machine list failed")
        await store.toggleMachine(store.machines[0])
        #expect(await client.actions == 0)
    }

    @Test func statusFailureDoesNotMasqueradeAsStopped() async {
        let client = MockClient()
        let store = ContainerStore(client: client)
        await store.refresh()
        await client.configure(failStatus: true)
        await store.refresh()
        #expect(store.service == .unavailable)
        #expect(!store.hasLoadedMachines)
        #expect(store.errorMessage == "XPC unavailable")
    }

    @Test func failedActionRefreshesStateAndRetainsItsError() async {
        let client = MockClient()
        let store = ContainerStore(client: client)
        await store.refresh()
        await client.configure(failAction: true)
        await store.toggleMachine(store.machines[0])
        #expect(store.machines[0].isRunning)
        #expect(store.errorMessage == "Start failed after boot")
        #expect(store.operation == nil)
    }

    @Test func machineControlsConfirmStateAfterAction() async {
        let store = ContainerStore(client: MockClient())
        await store.refresh()
        await store.toggleMachine(store.machines[0])
        #expect(store.machines[0].isRunning)
        await store.toggleMachine(store.machines[0])
        #expect(store.machines[0].isStopped)
        #expect(store.errorMessage == nil)
    }

    @Test func overlappingActionsAreIgnored() async {
        let client = MockClient()
        let store = ContainerStore(client: client)
        await store.refresh()
        store.operation = .stopService
        await store.toggleMachine(store.machines[0])
        await store.refresh()
        #expect(await client.actions == 0)
        #expect(await client.statusCalls == 1)
    }

    @Test func dismissingPanelCancelsPolling() async throws {
        let client = MockClient()
        let store = ContainerStore(client: client)
        store.setPanelVisible(true)
        try await Task.sleep(for: .milliseconds(50))
        store.setPanelVisible(false)
        let calls = await client.statusCalls
        try await Task.sleep(for: .milliseconds(100))
        #expect(await client.statusCalls == calls)
    }
}
