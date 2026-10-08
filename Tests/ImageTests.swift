import Foundation
import Testing

@testable import CKitCore

@Suite("Image verification")
struct ImageTests {
    @Test func presetReferencesAreMachineReadyChoices() {
        #expect(MachineImagePreset.alpine.reference == "alpine:3.22")
        #expect(MachineImagePreset.ubuntu.reference.hasPrefix("local/ckit-ubuntu-machine:"))
        #expect(MachineImagePreset.ubuntuDockerfile.contains("systemd-sysv"))
    }

    @Test func platformIsVerifiedIndependentlyOfName() throws {
        let json =
            #"[{"configuration":{"name":"example:latest"},"variants":[{"platform":{"architecture":"amd64","os":"linux"}},{"platform":{"architecture":"arm64","os":"linux"}}]}]"#
        let images = try JSONDecoder().decode([ContainerImage].self, from: Data(json.utf8))
        #expect(images[0].supportsMachinePlatform)
        let wrong =
            #"[{"configuration":{"name":"example:latest"},"variants":[{"platform":{"architecture":"amd64","os":"linux"}}]}]"#
        #expect(
            !(try JSONDecoder().decode([ContainerImage].self, from: Data(wrong.utf8)))[0]
                .supportsMachinePlatform)
    }

    @Test func mismatchedPresetCannotCreateAnotherImage() {
        let request = MachineCreationRequest(
            name: "test", image: "ubuntu:24.04", cpus: 1, memoryGiB: 1, preset: .ubuntu)
        #expect(throws: CLIError.self) { try request.validated() }
    }

    @Test func cachedImageVerifiesWithoutPulling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CKit-image-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("container")
        let body = """
            #!/bin/sh
            if [ "$1" = image ] && [ "$2" = inspect ] && [ "$3" = -- ] && [ "$4" = alpine:3.22 ]; then
              printf '%s' '[{"configuration":{"name":"docker.io/library/alpine:3.22"},"variants":[{"platform":{"architecture":"arm64","os":"linux"}}]}]'
            else
              exit 99
            fi
            """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let result = try await ContainerClient(executable: script.path).verifyImage(" alpine:3.22 ")
        #expect(result == .init(reference: "docker.io/library/alpine:3.22", wasPrepared: false))
    }
}

@Suite("Image check coordination") @MainActor
struct ImageStoreTests {
    @Test func invalidReferenceDoesNotStartService() async {
        let client = CreationFixture()
        let store = ContainerStore(client: client)
        await #expect(throws: CLIError.self) { try await store.checkImage("--flag") }
        #expect(await client.calls.isEmpty)
        #expect(!store.isBusy)
    }

    @Test func checkStartsServiceWithoutCreatingMachine() async throws {
        let client = CreationFixture()
        let store = ContainerStore(client: client)
        let result = try await store.checkImage("alpine:3.22", preset: .alpine)
        #expect(result.reference == "alpine:3.22")
        #expect(await client.calls == ["service"])
        #expect(store.machines.isEmpty)
        #expect(!store.isBusy)
    }

    @Test func busyStoreRejectsImageCheck() async {
        let client = CreationFixture()
        let store = ContainerStore(client: client)
        store.operation = .createMachine("other")
        await #expect(throws: CLIError.self) { try await store.checkImage("alpine:3.22") }
        #expect(await client.calls.isEmpty)
        #expect(store.operation == .createMachine("other"))
    }
}
