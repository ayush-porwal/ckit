import Foundation

protocol ContainerServing: Sendable {
    func serviceStatus() async throws -> ServiceStatus
    func machines() async throws -> [Machine]
    func startService() async throws
    func stopService() async throws
    func startMachine(_ id: String) async throws
    func stopMachine(_ id: String) async throws
    func deleteMachine(_ id: String) async throws
    func createMachine(_ request: MachineCreationRequest) async throws
    func verifyImage(_ reference: String) async throws -> ImageVerification
    func prepareImage(_ preset: MachineImagePreset) async throws -> ImageVerification
}

struct ContainerClient: ContainerServing {
    let executable: String
    private let runner = ProcessRunner()

    static let standardExecutableDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    static func findExecutable(
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        fallbackDirectories: [String] = standardExecutableDirectories
    ) -> String {
        // Finder may provide a minimal PATH; Homebrew locations remain discoverable.
        // Ignore relative/empty entries rather than searching the app's working directory.
        let directories =
            path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
            + fallbackDirectories
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("container").path
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
                !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: candidate)
            {
                return candidate
            }
        }
        // An absolute placeholder lets execution produce the installation guidance.
        return "/opt/homebrew/bin/container"
    }

    func serviceStatus() async throws -> ServiceStatus {
        let result = try await runner.run(
            executable: executable, arguments: ["system", "status", "--format", "json"], timeout: 20
        )
        // Version 1.5.0 returns JSON and exit code 1 for a stopped service.
        if let status = try? JSONDecoder().decode(
            ServiceStatus.self, from: Data(result.output.utf8))
        {
            guard status.state != .unavailable else {
                throw CLIError.invalidResponse(
                    "The CLI reported an unfamiliar service state: \(status.status).")
            }
            guard result.exitCode == 0 || (result.exitCode == 1 && status.state == .stopped) else {
                throw failure(for: result)
            }
            return status
        }
        if result.exitCode != 0 { throw failure(for: result) }
        throw CLIError.invalidResponse(
            "Could not read service status. Ckit requires container 1.5.0 or a compatible JSON format."
        )
    }

    func machines() async throws -> [Machine] {
        let output = try await checked(["machine", "list", "--format", "json"])
        do {
            let machines = try JSONDecoder().decode([Machine].self, from: Data(output.utf8))
            guard Set(machines.map(\.id)).count == machines.count,
                machines.allSatisfy({ !$0.id.isEmpty })
            else {
                throw CLIError.invalidResponse("The CLI returned duplicate or empty machine names.")
            }
            return machines.sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        } catch let error as CLIError { throw error } catch {
            throw CLIError.invalidResponse(
                "Could not read the machine list. The CLI's JSON format may have changed.")
        }
    }

    func startService() async throws {
        _ = try await checked(
            ["system", "start", "--disable-kernel-install", "--timeout", "30"], timeout: 90)
    }

    func stopService() async throws { _ = try await checked(["system", "stop"], timeout: 60) }

    func startMachine(_ id: String) async throws {
        // Version 1.5.0 requires terminal stdin during first-boot user setup.
        // An explicit executable avoids the default interactive login shell.
        _ = try await checked(
            ["machine", "run", "--name", id, "/bin/true"], timeout: 90, terminalInput: true)
    }

    func stopMachine(_ id: String) async throws {
        _ = try await checked(["machine", "stop", "--", id], timeout: 60)
    }

    func deleteMachine(_ id: String) async throws {
        _ = try await checked(["machine", "delete", "--", id], timeout: 90)
    }

    func createMachine(_ request: MachineCreationRequest) async throws {
        let request = try request.validated()
        _ = try await checked(request.createArguments, timeout: 600)
    }

    func verifyImage(_ input: String) async throws -> ImageVerification {
        let reference = try ImageReference.validated(input)
        if let image = try await inspectedImage(reference), image.supportsMachinePlatform {
            return .init(reference: image.configuration.name, wasPrepared: false)
        }
        _ = try await checked(
            ["image", "pull", "--platform", "linux/arm64", "--progress", "none", "--", reference],
            timeout: 600)
        guard let image = try await inspectedImage(reference), image.supportsMachinePlatform else {
            throw CLIError.failed("This image does not include Linux for Apple Silicon (arm64).")
        }
        return .init(reference: image.configuration.name, wasPrepared: true)
    }

    func prepareImage(_ preset: MachineImagePreset) async throws -> ImageVerification {
        if preset == .alpine { return try await verifyImage(preset.reference) }
        if let image = try await inspectedImage(preset.reference), image.supportsMachinePlatform {
            return .init(reference: image.configuration.name, wasPrepared: false)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Ckit-Ubuntu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(MachineImagePreset.ubuntuDockerfile.utf8).write(
            to: directory.appendingPathComponent("Dockerfile"))
        _ = try await checked(
            [
                "build", "--platform", "linux/arm64", "--progress", "plain", "--tag",
                preset.reference, "--", directory.path,
            ], timeout: 1200)
        guard let image = try await inspectedImage(preset.reference), image.supportsMachinePlatform
        else {
            throw CLIError.failed(
                "Ubuntu preparation finished, but the machine image could not be verified.")
        }
        return .init(reference: image.configuration.name, wasPrepared: true)
    }

    private func inspectedImage(_ reference: String) async throws -> ContainerImage? {
        let result = try await runner.run(
            executable: executable, arguments: ["image", "inspect", "--", reference])
        guard result.exitCode == 0 else { return nil }
        guard
            let images = try? JSONDecoder().decode(
                [ContainerImage].self, from: Data(result.output.utf8)),
            images.count == 1, let image = images.first, !image.configuration.name.isEmpty
        else {
            throw CLIError.invalidResponse("Could not read image details from the container CLI.")
        }
        return image
    }

    private func checked(
        _ arguments: [String], timeout: TimeInterval = 30,
        terminalInput: Bool = false
    ) async throws -> String {
        let result = try await runner.run(
            executable: executable, arguments: arguments, timeout: timeout,
            terminalInput: terminalInput)
        guard result.exitCode == 0 else { throw failure(for: result) }
        return result.output
    }

    private func failure(for result: CommandResult) -> CLIError {
        let message = result.errorOutput.isEmpty ? result.output : result.errorOutput
        return .failed(
            message.isEmpty ? "The container command failed (exit \(result.exitCode))." : message)
    }
}
