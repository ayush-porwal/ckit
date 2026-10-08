import Foundation

enum ServiceState: Equatable, Sendable {
    case unknown, running, stopped, unavailable

    var title: String {
        switch self {
        case .unknown: "Checking"
        case .running: "Running"
        case .stopped: "Stopped"
        case .unavailable: "Unavailable"
        }
    }
}

struct ServiceStatus: Decodable, Sendable {
    let status: String
    let client: VersionInfo?
    let resources: Resources?

    struct VersionInfo: Decodable, Sendable {
        let version: String
    }

    struct Resources: Decodable, Sendable {
        let containersRunning: Int
    }

    var state: ServiceState {
        switch status {
        case "running": .running
        case "unregistered", "not running": .stopped
        default: .unavailable
        }
    }
}

struct Machine: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let status: String
    let isDefault: Bool
    let cpus: Int
    let memory: UInt64
    let diskSize: UInt64?
    let ipAddress: String?

    enum CodingKeys: String, CodingKey {
        case id, status, cpus, memory, diskSize, ipAddress
        case isDefault = "default"
    }

    var isRunning: Bool { status == "running" }
    var isStopped: Bool { status == "stopped" }
    var stateTitle: String { status.capitalized }

    var memoryLabel: String {
        let gib = Double(memory) / 1_073_741_824
        return gib >= 1
            ? "\(gib.formatted(.number.precision(.fractionLength(0...1)))) GB"
            : "\(memory / 1_048_576) MB"
    }
}

struct CommandResult: Sendable {
    let exitCode: Int32
    let output: String
    let errorOutput: String
}

enum MachineImagePreset: String, CaseIterable, Sendable {
    case alpine, ubuntu

    var title: String { self == .alpine ? "Alpine 3.22" : "Ubuntu 24.04" }
    var reference: String {
        self == .alpine ? "alpine:3.22" : "local/ckit-ubuntu-machine:24.04-v1"
    }
    var hint: String {
        self == .alpine ? "" : "Prepared locally on first use."
    }

    // Based on Apple's Ubuntu machine example, with the required init system
    // and user-setup tools. Version the local tag when changing this recipe.
    static let ubuntuDockerfile = """
        FROM ubuntu:24.04
        ENV container=container
        RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            systemd systemd-sysv dbus openssh-server sudo iproute2 curl ca-certificates \
            && apt-get clean && rm -rf /var/lib/apt/lists/*
        RUN truncate -s 0 /etc/machine-id /var/lib/dbus/machine-id \
            && systemctl set-default multi-user.target \
            && systemctl mask dev-hugepages.mount sys-fs-fuse-connections.mount \
            systemd-update-utmp.service systemd-tmpfiles-setup.service console-getty.service \
            && sed -i '/^AcceptEnv LANG LC_/d' /etc/ssh/sshd_config
        """
}

struct ContainerImage: Decodable, Sendable {
    struct Configuration: Decodable, Sendable { let name: String }
    struct Variant: Decodable, Sendable {
        struct Platform: Decodable, Sendable {
            let architecture: String
            let os: String
        }
        let platform: Platform
    }
    let configuration: Configuration
    let variants: [Variant]
    var supportsMachinePlatform: Bool {
        variants.contains { $0.platform.architecture == "arm64" && $0.platform.os == "linux" }
    }
}

struct ImageVerification: Equatable, Sendable {
    let reference: String
    let wasPrepared: Bool
}

enum ImageReference {
    static func validated(_ input: String) throws -> String {
        let reference = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty, !reference.hasPrefix("-"),
            !reference.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
            })
        else {
            throw CLIError.failed("Enter an image reference, such as alpine:3.22, without spaces.")
        }
        return reference
    }
}

struct MachineCreationRequest: Equatable, Sendable {
    var name: String
    var image: String
    var cpus: Int
    var memoryGiB: Int
    var startAfterCreation = true
    var preset: MachineImagePreset? = nil

    static var maximumCPUs: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }
    static var maximumMemoryGiB: Int {
        max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
    }

    func validated() throws -> Self {
        var request = self
        request.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        request.image = try ImageReference.validated(image)
        guard
            request.name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", options: .regularExpression)
                != nil
        else {
            throw CLIError.failed(
                "Use a name of 1–63 letters, numbers, dots, underscores, or hyphens, starting with a letter or number."
            )
        }
        if let preset, request.image != preset.reference {
            throw CLIError.failed("The selected image preset does not match its reference.")
        }
        guard (1...Self.maximumCPUs).contains(cpus) else {
            throw CLIError.failed("Choose between 1 and \(Self.maximumCPUs) CPUs.")
        }
        guard (1...Self.maximumMemoryGiB).contains(memoryGiB) else {
            throw CLIError.failed("Choose between 1 and \(Self.maximumMemoryGiB) GB of memory.")
        }
        return request
    }

    // Create separately from booting so neither path enters an interactive shell.
    var createArguments: [String] {
        [
            "machine", "create", "--name", name, "--cpus", String(cpus),
            "--memory", "\(memoryGiB)G", "--home-mount", "none", "--no-boot",
            "--progress", "none", "--", image,
        ]
    }
}

enum MachineCreationResult: Equatable {
    case created(warning: String?)
    case failed(String)
    // A lost connection after submission must not invite a duplicate attempt.
    case uncertain(String)
}

enum CLIError: LocalizedError, Sendable {
    case missingExecutable(String)
    case failed(String)
    case invalidResponse(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "The container CLI could not be found. Install it on your PATH, then reopen the menu."
        case .failed(let message), .invalidResponse(let message):
            message
        case .timedOut:
            "The command took too long. Reopen the menu to check its current state before trying again."
        }
    }
}

enum ShellEscaping {
    static func quote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
