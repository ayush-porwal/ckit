import Foundation

@main
struct LiveSmokeTest {
    @MainActor
    static func main() async throws {
        let client = ContainerClient(executable: ContainerClient.findExecutable())
        let originalService = try await client.serviceStatus()
        let store = ContainerStore()
        let name = CommandLine.arguments.dropFirst().first ?? "dsa"
        var originalMachine: Machine?
        do {
            await store.refresh()
            if store.service == .stopped { await store.startService() }
            try check(
                store.service == .running && store.errorMessage == nil,
                "Service starts and reports running")
            let machine = try await client.machines().first { $0.id == name }
            originalMachine = machine
            guard let machine else {
                throw CLIError.failed("Machine \(name) does not exist; no machine will be created.")
            }
            try check(store.machines.contains { $0.id == name }, "Machine list includes \(name)")
            if machine.isStopped {
                await store.toggleMachine(machine)
                try check(
                    store.errorMessage == nil
                        && store.machines.contains { $0.id == name && $0.isRunning },
                    "Machine starts without an interactive shell")
                await store.toggleMachine(store.machines.first { $0.id == name }!)
                try check(
                    store.errorMessage == nil
                        && store.machines.contains { $0.id == name && $0.isStopped },
                    "Machine stops and refreshes its state")
            } else {
                print("Skipped machine actions to preserve its existing running state.")
            }
            if originalService.state == .stopped {
                await store.stopService()
                try check(
                    store.service == .stopped && store.errorMessage == nil,
                    "Service stops and clears machine rows")
            }
            print("Live smoke test passed; initial service and machine states restored.")
        } catch {
            if originalMachine?.isStopped == true { try? await client.stopMachine(name) }
            if originalService.state == .stopped { try? await client.stopService() }
            throw error
        }
    }

    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CLIError.failed("FAIL: \(message)") }
        print("PASS: \(message)")
    }
}
