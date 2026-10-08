import Foundation
import Testing

@testable import CKitCore

@Suite("Automatic CLI discovery")
struct ExecutableDiscoveryTests {
    private func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CKit-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func binary(in directory: URL, executable: Bool = true) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("container")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: url.path)
        return url.path
    }

    @Test func respectsPathOrderBeforeFallbacks() throws {
        try fixture { root in
            let first = root.appendingPathComponent("first")
            let second = root.appendingPathComponent("second")
            let fallback = root.appendingPathComponent("fallback")
            let expected = try binary(in: first)
            _ = try binary(in: second)
            _ = try binary(in: fallback)
            #expect(
                ContainerClient.findExecutable(
                    path: "\(first.path):\(second.path)", fallbackDirectories: [fallback.path])
                    == expected)
        }
    }

    @Test func usesFallbackForFinderPath() throws {
        try fixture { root in
            let fallback = root.appendingPathComponent("homebrew")
            let expected = try binary(in: fallback)
            #expect(
                ContainerClient.findExecutable(
                    path: root.appendingPathComponent("missing").path,
                    fallbackDirectories: [fallback.path]) == expected)
        }
    }

    @Test func skipsNonexecutablesAndDirectories() throws {
        try fixture { root in
            let notExecutable = root.appendingPathComponent("non-executable")
            _ = try binary(in: notExecutable, executable: false)
            let directory = root.appendingPathComponent("directory")
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("container"), withIntermediateDirectories: true
            )
            let valid = root.appendingPathComponent("valid")
            let expected = try binary(in: valid)
            #expect(
                ContainerClient.findExecutable(
                    path: "\(notExecutable.path):\(directory.path):\(valid.path)",
                    fallbackDirectories: []) == expected)
        }
    }

    @Test func handlesSpacesAndExecutableSymlinks() throws {
        try fixture { root in
            let target = try binary(in: root.appendingPathComponent("real bin"))
            let linked = root.appendingPathComponent("linked bin")
            try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                atPath: linked.appendingPathComponent("container").path, withDestinationPath: target
            )
            #expect(
                ContainerClient.findExecutable(path: linked.path, fallbackDirectories: [])
                    == linked.appendingPathComponent("container").path)
        }
    }
}
