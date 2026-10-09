import Darwin
import Foundation

struct ProcessRunner: Sendable {
    func run(
        executable: String, arguments: [String], timeout: TimeInterval = 30,
        terminalInput: Bool = false
    ) async throws
        -> CommandResult
    {
        let execution = CommandExecution(
            executable: executable, arguments: arguments, timeout: timeout,
            terminalInput: terminalInput)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                execution.start(continuation)
            }
        } onCancel: {
            execution.cancel()
        }
    }
}

// Process and its continuation are accessed only on this serial queue.
// Private temporary files avoid deadlocks caused by full stdout/stderr pipes.
private final class CommandExecution: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.local.ckit.command")
    private let process = Process()
    private let executable: String
    private let arguments: [String]
    private let timeout: TimeInterval
    private let terminalInput: Bool
    private var continuation: CheckedContinuation<CommandResult, any Error>?
    private var directory: URL?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var inputHandle: FileHandle?
    private var terminalMaster: FileHandle?
    private var timeoutWork: DispatchWorkItem?
    private var failure: (any Error)?
    private var cancelled = false
    private var finished = false

    init(executable: String, arguments: [String], timeout: TimeInterval, terminalInput: Bool) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
        self.terminalInput = terminalInput
    }

    func start(_ continuation: CheckedContinuation<CommandResult, any Error>) {
        queue.async { [self] in
            self.continuation = continuation
            if cancelled {
                finish(.failure(CancellationError()))
                return
            }
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                finish(.failure(CLIError.missingExecutable(executable)))
                return
            }
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Ckit-\(UUID().uuidString)", isDirectory: true)
                self.directory = directory
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                outputHandle = try makeOutputFile(directory.appendingPathComponent("stdout"))
                errorHandle = try makeOutputFile(directory.appendingPathComponent("stderr"))
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                if terminalInput {
                    // container 1.5.0's first-boot setup requires terminal stdin
                    // even for an explicit noninteractive command. No shell is opened.
                    var master: Int32 = -1
                    var slave: Int32 = -1
                    var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
                    guard openpty(&master, &slave, nil, nil, &size) == 0 else {
                        throw CLIError.failed("Could not prepare a terminal for machine startup.")
                    }
                    terminalMaster = FileHandle(fileDescriptor: master, closeOnDealloc: true)
                    inputHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
                    process.standardInput = inputHandle
                } else {
                    process.standardInput = FileHandle.nullDevice
                }
                process.standardOutput = outputHandle
                process.standardError = errorHandle
                var environment = ProcessInfo.processInfo.environment
                let inheritedDirectories = (environment["PATH"] ?? "").split(separator: ":")
                    .map(String.init).filter { $0.hasPrefix("/") }
                environment["PATH"] =
                    ([URL(fileURLWithPath: executable).deletingLastPathComponent().path]
                    + inheritedDirectories + ContainerClient.standardExecutableDirectories).joined(
                        separator: ":")
                environment["NO_COLOR"] = "1"
                process.environment = environment
                process.terminationHandler = { [self] _ in
                    queue.async { [self] in
                        if let failure {
                            finish(.failure(failure))
                        } else {
                            finish(
                                .success(
                                    CommandResult(
                                        exitCode: process.terminationStatus,
                                        output: readOutput("stdout"),
                                        errorOutput: readOutput("stderr"))))
                        }
                    }
                }
                try process.run()
                let work = DispatchWorkItem { [weak self] in self?.stop(with: CLIError.timedOut) }
                timeoutWork = work
                queue.asyncAfter(deadline: .now() + timeout, execute: work)
            } catch {
                finish(.failure(error))
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            cancelled = true
            stop(with: CancellationError())
        }
    }

    private func stop(with error: any Error) {
        guard !finished else { return }
        failure = error
        guard process.isRunning else { return }
        process.terminate()
        // The CLI intercepts SIGTERM; bound timeout/cancellation even in that case.
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.process.isRunning else { return }
            Darwin.kill(self.process.processIdentifier, SIGKILL)
        }
    }

    private func makeOutputFile(_ url: URL) throws -> FileHandle {
        guard
            FileManager.default.createFile(
                atPath: url.path, contents: nil,
                attributes: [.posixPermissions: 0o600])
        else {
            throw CLIError.failed("Could not create a temporary command output file.")
        }
        return try FileHandle(forWritingTo: url)
    }

    private func readOutput(_ name: String) -> String {
        guard let directory,
            let handle = try? FileHandle(forReadingFrom: directory.appendingPathComponent(name))
        else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 1_048_577)) ?? Data()
        let text = String(decoding: data.prefix(1_048_576), as: UTF8.self)
        return (text + (data.count > 1_048_576 ? "\n[Output truncated]" : ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finish(_ result: Result<CommandResult, any Error>) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        timeoutWork = nil
        process.terminationHandler = nil
        try? outputHandle?.close()
        try? errorHandle?.close()
        try? inputHandle?.close()
        try? terminalMaster?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        continuation?.resume(with: result)
        continuation = nil
    }
}
