import Foundation

@main struct CreationSmokeTest {
    @MainActor static func main() async {
        do { try await run() } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
    @MainActor static func run() async throws {
        let client = ContainerClient(executable: ContainerClient.findExecutable())
        let originalService = try await client.serviceStatus()
        let originalMachines = originalService.state == .running ? try await client.machines() : []
        let store = ContainerStore(client: client)
        let prefix = "ckit-create-smoke-" + UUID().uuidString.lowercased().prefix(8)
        let names = [prefix + "-manual", prefix + "-auto"]
        let runner = ProcessRunner()
        func cleanup() async throws {
            let machines = try await client.machines()
            for machine in machines where names.contains(machine.id) {
                if machine.isRunning { try await client.stopMachine(machine.id) }
                let result = try await runner.run(
                    executable: client.executable,
                    arguments: ["machine", "delete", "--", machine.id], timeout: 60)
                try check(result.exitCode == 0, "Disposable machine \(machine.id) removed")
            }
            if originalService.state == .stopped { try await client.stopService() }
        }
        do {
            for (index, name) in names.enumerated() {
                let request = MachineCreationRequest(
                    name: name, image: CommandLine.arguments.dropFirst().first ?? "alpine:3.22",
                    cpus: 1,
                    memoryGiB: 1, startAfterCreation: index == 1)
                print("Creating disposable \(name)")
                let result = await store.createMachine(request)
                try check(result == .created(warning: nil), "Creation confirmed: \(result)")
                let machine = store.machines.first { $0.id == name }!
                try check(
                    machine.cpus == 1 && machine.memory == 1_073_741_824,
                    "CPU and memory options persisted")
                if index == 0 {
                    try check(machine.isStopped, "Unchecked startup leaves the new machine stopped")
                    await store.toggleMachine(machine)
                    try check(
                        store.machines.contains { $0.id == name && $0.isRunning },
                        "Manual launch from store boots the machine: \(store.errorMessage ?? "no error")"
                    )
                    await store.toggleMachine(store.machines.first { $0.id == name }!)
                    try check(
                        store.machines.first { $0.id == name }?.isStopped == true,
                        "Manual machine stops before deletion")
                } else {
                    try check(machine.isRunning, "Checked startup boots the new machine")
                }
                await store.deleteMachine(store.machines.first { $0.id == name }!)
                try check(
                    store.hasLoadedMachines && store.errorMessage == nil
                        && !store.machines.contains { $0.id == name },
                    "Store confirms deletion of the \(index == 0 ? "stopped" : "running") machine")
            }
            try await cleanup()
            if originalService.state == .running {
                let after = try await client.machines()
                try check(
                    after == originalMachines, "Existing machines and their states are unchanged")
            }
            try check(
                try await client.serviceStatus().state == originalService.state,
                "Initial service state restored")
            print("Live creation and deletion smoke test passed; both disposable machines removed.")
        } catch {
            do { try await cleanup() } catch {
                print("Cleanup failed for \(names): \(error.localizedDescription)")
            }
            throw error
        }
    }
    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CLIError.failed("FAIL: \(message)") }
        print("PASS: \(message)")
    }
}
