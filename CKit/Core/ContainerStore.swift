import AppKit
import Observation

@MainActor
@Observable
final class ContainerStore {
    var service: ServiceState = .unknown
    var machines: [Machine] = []
    var cliVersion: String?
    var runningContainers = 0
    var lastUpdated: Date?
    var isRefreshing = false
    var operation: Operation?
    var errorMessage: String?
    var notice: String?
    var executable: String
    var hasLoadedMachines = false

    @ObservationIgnored private let automaticallyFindExecutable: Bool
    @ObservationIgnored private var client: any ContainerServing
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    enum Operation: Equatable {
        case startService, stopService
        case startMachine(String)
        case stopMachine(String)
        case deleteMachine(String)
        case terminal(String)
        case createMachine(String)
        case checkImage
        case prepareImage(String)

        var title: String {
            switch self {
            case .startService: "Starting service…"
            case .stopService: "Stopping service…"
            case .startMachine(let name): "Starting \(name)…"
            case .stopMachine(let name): "Stopping \(name)…"
            case .deleteMachine(let name): "Deleting \(name)…"
            case .terminal(let name): "Opening \(name)…"
            case .createMachine(let name): "Creating \(name)…"
            case .checkImage: "Checking image…"
            case .prepareImage(let name): "Preparing \(name)…"
            }
        }

        var machineID: String? {
            switch self {
            case .startMachine(let id), .stopMachine(let id), .deleteMachine(let id),
                .terminal(let id), .createMachine(let id):
                id
            default: nil
            }
        }
    }

    init(
        executable: String? = nil, client: (any ContainerServing)? = nil
    ) {
        let resolved = executable ?? ContainerClient.findExecutable()
        self.executable = resolved
        self.client = client ?? ContainerClient(executable: resolved)
        automaticallyFindExecutable = executable == nil && client == nil
    }

    var isBusy: Bool { operation != nil || isRefreshing }
    var runningMachines: Int { machines.filter(\.isRunning).count }

    func setPanelVisible(_ visible: Bool) {
        pollingTask?.cancel()
        pollingTask = nil
        guard visible else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(clearError: false)
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }

    func refresh(clearError: Bool = true) async {
        guard !isBusy else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await loadSnapshot(clearError: clearError)
    }

    private func discoverExecutable() {
        if automaticallyFindExecutable {
            let resolved = ContainerClient.findExecutable()
            if resolved != executable {
                executable = resolved
                client = ContainerClient(executable: resolved)
            }
        }
    }

    private func loadSnapshot(clearError: Bool) async {
        discoverExecutable()
        let status: ServiceStatus
        do {
            status = try await client.serviceStatus()
            try Task.checkCancellation()
        } catch is CancellationError { return } catch {
            service = .unavailable
            hasLoadedMachines = false
            errorMessage = error.localizedDescription
            return
        }
        service = status.state
        cliVersion = status.client?.version ?? cliVersion
        runningContainers = status.resources?.containersRunning ?? 0
        if status.state == .running {
            do {
                let freshMachines = try await client.machines()
                try Task.checkCancellation()
                machines = freshMachines
                hasLoadedMachines = true
            } catch is CancellationError { return } catch {
                hasLoadedMachines = false
                errorMessage = error.localizedDescription
                return
            }
        } else {
            machines = []
            hasLoadedMachines = false
        }
        lastUpdated = Date()
        if clearError { errorMessage = nil }
    }

    func startService() async {
        guard service == .stopped else { return }
        await perform(.startService) { try await self.client.startService() }
    }

    func stopService() async {
        guard service == .running else { return }
        await perform(.stopService) { try await self.client.stopService() }
    }

    func toggleMachine(_ machine: Machine) async {
        guard service == .running, hasLoadedMachines, machine.isRunning || machine.isStopped else {
            return
        }
        if machine.isRunning {
            await perform(.stopMachine(machine.id)) {
                try await self.client.stopMachine(machine.id)
            }
        } else {
            await perform(.startMachine(machine.id)) {
                try await self.client.startMachine(machine.id)
            }
        }
    }

    func openTerminal(_ machine: Machine) async {
        guard machine.isRunning, service == .running, hasLoadedMachines else { return }
        await perform(.terminal(machine.id), refreshAfter: false) {
            try await TerminalLauncher.open(executable: self.executable, machine: machine.id)
        }
    }

    func deleteMachine(_ machine: Machine) async {
        guard service == .running, hasLoadedMachines,
            machines.contains(where: { $0.id == machine.id })
        else { return }
        await perform(.deleteMachine(machine.id)) {
            try await self.client.deleteMachine(machine.id)
        }
    }

    func createMachine(_ input: MachineCreationRequest) async -> MachineCreationResult {
        guard !isBusy else {
            return .failed("Another action is in progress. Try again when it finishes.")
        }
        let request: MachineCreationRequest
        do { request = try input.validated() } catch { return .failed(error.localizedDescription) }
        operation = .createMachine(request.name)
        errorMessage = nil
        notice = nil
        defer { operation = nil }
        discoverExecutable()
        var submitted = false
        var created = false
        do {
            let status = try await client.serviceStatus()
            if status.state == .stopped {
                operation = .startService
                try await client.startService()
            } else if status.state != .running {
                throw CLIError.failed(
                    "The service is unavailable. Check that container is installed and available on PATH."
                )
            }
            operation = .createMachine(request.name)
            // Use a fresh list, including machines created outside Ckit.
            let existing = try await client.machines()
            guard !existing.contains(where: { $0.id == request.name }) else {
                throw CLIError.failed(
                    "A machine named \(request.name) already exists. Choose another name.")
            }
            if let preset = request.preset {
                operation = .prepareImage(preset.title)
                _ = try await client.prepareImage(preset)
                operation = .createMachine(request.name)
            }
            submitted = true
            try await client.createMachine(request)
            created = true
            if request.startAfterCreation {
                operation = .startMachine(request.name)
                try await client.startMachine(request.name)
            }
            await loadSnapshot(clearError: true)
            for _ in 0..<4 where errorMessage == nil && !creationIsConfirmed(request) {
                try await Task.sleep(for: .milliseconds(750))
                await loadSnapshot(clearError: true)
            }
            let warning =
                errorMessage
                ?? (creationIsConfirmed(request)
                    ? nil
                    : "Machine created. Its current state could not be confirmed; reopen the menu to check it.")
            errorMessage = warning
            return .created(warning: warning)
        } catch {
            let detail = error.localizedDescription
            await loadSnapshot(clearError: false)
            let exists = hasLoadedMachines && machines.contains { $0.id == request.name }
            if created || (submitted && exists) {
                let message =
                    "Machine created, but \(request.startAfterCreation ? "startup did not finish" : "the command reported an error"). Reopen the menu and start it there if needed.\n\n\(detail)"
                errorMessage = message
                return .created(warning: message)
            }
            if submitted && !hasLoadedMachines {
                let message =
                    "Could not confirm whether \(request.name) was created. Reopen the menu before trying again.\n\n\(detail)"
                errorMessage = message
                return .uncertain(message)
            }
            errorMessage = detail
            return .failed(detail)
        }
    }

    func checkImage(_ input: String, preset: MachineImagePreset? = nil) async throws
        -> ImageVerification
    {
        guard !isBusy else {
            throw CLIError.failed("Another action is in progress. Try again when it finishes.")
        }
        let reference = try ImageReference.validated(input)
        if let preset, reference != preset.reference {
            throw CLIError.failed("The selected image preset does not match its reference.")
        }
        let checking: Operation = preset.map { .prepareImage($0.title) } ?? .checkImage
        operation = checking
        defer { operation = nil }
        discoverExecutable()
        let status = try await client.serviceStatus()
        if status.state == .stopped {
            operation = .startService
            try await client.startService()
        } else if status.state != .running {
            throw CLIError.failed("The service is unavailable. Reopen the menu and retry.")
        }
        operation = checking
        let result: ImageVerification
        if let preset {
            result = try await client.prepareImage(preset)
        } else {
            result = try await client.verifyImage(reference)
        }
        await loadSnapshot(clearError: false)
        return result
    }

    private func creationIsConfirmed(_ request: MachineCreationRequest) -> Bool {
        hasLoadedMachines
            && machines.contains {
                $0.id == request.name && (request.startAfterCreation ? $0.isRunning : $0.isStopped)
            }
    }

    private func perform(
        _ operation: Operation, refreshAfter: Bool = true, action: () async throws -> Void
    ) async {
        guard !isBusy else { return }
        self.operation = operation
        errorMessage = nil
        notice = nil
        defer { self.operation = nil }
        do {
            try await action()
            if refreshAfter {
                await loadSnapshot(clearError: true)
                for _ in 0..<4 where !hasReachedDesiredState(operation) && errorMessage == nil {
                    try await Task.sleep(for: .milliseconds(750))
                    await loadSnapshot(clearError: true)
                }
                if errorMessage == nil, !hasReachedDesiredState(operation) {
                    errorMessage =
                        "The command finished, but the new state is not confirmed yet. Reopen the menu to check again."
                }
            }
        } catch {
            let actionError = error.localizedDescription
            if refreshAfter { await loadSnapshot(clearError: false) }
            errorMessage = actionError
        }
    }

    private func hasReachedDesiredState(_ operation: Operation) -> Bool {
        switch operation {
        case .startService: service == .running
        case .stopService: service == .stopped
        case .startMachine(let id): machines.contains { $0.id == id && $0.isRunning }
        case .stopMachine(let id): machines.contains { $0.id == id && $0.isStopped }
        case .deleteMachine(let id):
            service == .running && hasLoadedMachines && !machines.contains { $0.id == id }
        case .terminal: true
        case .createMachine(let id): machines.contains { $0.id == id }
        case .checkImage, .prepareImage: true
        }
    }

    func copyError() {
        guard let errorMessage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorMessage, forType: .string)
        notice = "Error copied"
    }
}
