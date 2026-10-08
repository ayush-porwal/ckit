import Foundation

@main struct ImagePresetSmokeTest {
    @MainActor static func main() async {
        do { try await run() } catch {
            announce("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
    @MainActor static func run() async throws {
        let client = ContainerClient(executable: ContainerClient.findExecutable())
        let originalService = try await client.serviceStatus()
        let originalMachines = originalService.state == .running ? try await client.machines() : []
        let store = ContainerStore(client: client)
        let name = "ckit-image-smoke-" + UUID().uuidString.lowercased().prefix(8)
        let runner = ProcessRunner()
        func cleanup() async throws {
            if let machine = try await client.machines().first(where: { $0.id == name }) {
                if machine.isRunning { try await client.stopMachine(name) }
                let deleted = try await runner.run(
                    executable: client.executable,
                    arguments: ["machine", "delete", "--", name], timeout: 60)
                try check(deleted.exitCode == 0, "Disposable Ubuntu machine removed")
            }
            if originalService.state == .stopped { try await client.stopService() }
        }
        do {
            announce("Checking Alpine preset")
            _ = try await store.checkImage(MachineImagePreset.alpine.reference, preset: .alpine)
            try check(!store.isBusy, "Alpine verification releases busy state")
            announce("Preparing Ubuntu 24.04 preset; first build may take several minutes.")
            let ubuntu = try await store.checkImage(
                MachineImagePreset.ubuntu.reference, preset: .ubuntu)
            try check(
                ubuntu.reference.contains("ckit-ubuntu-machine"),
                "Ubuntu preset resolves to the prepared image")
            let request = MachineCreationRequest(
                name: name, image: MachineImagePreset.ubuntu.reference,
                cpus: 2, memoryGiB: 2, startAfterCreation: true, preset: .ubuntu)
            let created = await store.createMachine(request)
            try check(
                created == .created(warning: nil), "Ubuntu machine creates and boots: \(created)")
            try check(
                store.machines.contains { $0.id == name && $0.isRunning },
                "Prepared Ubuntu is running")
            let invalid = "alpine:ckit-missing-" + UUID().uuidString.lowercased().prefix(8)
            do {
                _ = try await store.checkImage(invalid)
                throw CLIError.failed("Missing image tag was incorrectly accepted")
            } catch let error as CLIError {
                try check(
                    !error.localizedDescription.contains("incorrectly accepted"),
                    "Missing image tag is rejected")
            }
            try await cleanup()
            if originalService.state == .running {
                try check(
                    try await client.machines() == originalMachines,
                    "Existing machines are unchanged")
            }
            announce("Image preset smoke test passed; prepared images kept for reuse.")
        } catch {
            do { try await cleanup() } catch {
                announce("Cleanup failed for \(name): \(error.localizedDescription)")
            }
            throw error
        }
    }
    static func announce(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CLIError.failed(message) }
        announce("PASS: \(message)")
    }
}
