import Foundation

// Checks that macOS Terminal executes the interactive CLI command.
// Actual keyboard input in the shell remains a manual UI check.
@main
struct TerminalSmokeTest {
    @MainActor
    static func main() async {
        let client = ContainerClient(executable: ContainerClient.findExecutable())
        let name = CommandLine.arguments.dropFirst().first ?? "dsa"
        var originalService: ServiceStatus?
        var originalMachine: Machine?
        var failure: (any Error)?
        do {
            originalService = try await client.serviceStatus()
            if originalService?.state == .stopped { try await client.startService() }
            originalMachine = try await client.machines().first { $0.id == name }
            guard let machine = originalMachine else {
                throw CLIError.failed("Machine \(name) does not exist.")
            }
            if machine.isStopped { try await client.startMachine(name) }
            try await TerminalLauncher.open(executable: client.executable, machine: name)
            var launched = false
            for _ in 0..<20 {
                let processes = try await ProcessRunner().run(
                    executable: "/bin/ps", arguments: ["-axo", "command"])
                launched = processes.output.split(separator: "\n").contains {
                    $0.contains("machine run --name \(name) --interactive --tty")
                }
                if launched { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard launched else {
                throw CLIError.failed("Terminal did not launch the interactive CLI process.")
            }
            print("PASS: Terminal launched the real interactive container command.")
        } catch { failure = error }
        do {
            if originalMachine?.isStopped == true { try await client.stopMachine(name) }
            if originalService?.state == .stopped { try await client.stopService() }
        } catch { failure = failure ?? error }
        if let failure {
            print("FAIL: \(failure.localizedDescription)")
            exit(EXIT_FAILURE)
        }
        print("Terminal launch smoke test passed; original service and machine states restored.")
    }
}
