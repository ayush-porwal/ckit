import AppKit
import Foundation

@MainActor
enum TerminalLauncher {
    static func script(executable: String, machine: String) -> String {
        """
        #!/bin/sh
        rm -f -- "$0"
        exec \(ShellEscaping.quote(executable)) machine run --name \(ShellEscaping.quote(machine)) --interactive --tty

        """
    }

    static func open(executable: String, machine: String) async throws {
        guard
            let terminal = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Terminal")
        else {
            throw CLIError.failed("Terminal could not be found on this Mac.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Ckit-Terminal", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        for file
            in (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
                date < Date().addingTimeInterval(-86_400), file.pathExtension == "command"
            {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let file = directory.appendingPathComponent("Ckit-\(UUID().uuidString).command")
        try script(executable: executable, machine: machine).write(
            to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(
                [file], withApplicationAt: terminal, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw CLIError.failed("Could not open Terminal: \(error.localizedDescription)")
        }
    }
}
