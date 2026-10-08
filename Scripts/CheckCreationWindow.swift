import AppKit

actor CreationWindowFixture: ContainerServing {
    enum Failure { case none, create, start, image }
    var failure: Failure = .none
    var items: [Machine] = []
    var calls = 0
    var imageCalls = 0
    func configure(_ failure: Failure) { self.failure = failure }
    func serviceStatus() async throws -> ServiceStatus {
        .init(status: "running", client: nil, resources: nil)
    }
    func machines() async throws -> [Machine] { items }
    func startService() async throws {}
    func stopService() async throws {}
    func verifyImage(_ reference: String) async throws -> ImageVerification {
        imageCalls += 1
        try await Task.sleep(for: .milliseconds(100))
        if failure == .image { throw CLIError.failed("Image tag not found") }
        return .init(reference: reference, wasPrepared: false)
    }
    func prepareImage(_ preset: MachineImagePreset) async throws -> ImageVerification {
        try await verifyImage(preset.reference)
    }
    func createMachine(_ request: MachineCreationRequest) async throws {
        calls += 1
        try await Task.sleep(for: .milliseconds(200))
        if failure == .create {
            throw CLIError.failed("Image not found. Check the image reference and try again.")
        }
        items = [
            .init(
                id: request.name, status: "stopped", isDefault: false, cpus: request.cpus,
                memory: UInt64(request.memoryGiB) * 1_073_741_824, diskSize: nil, ipAddress: nil)
        ]
    }
    func startMachine(_ id: String) async throws {
        if failure == .start { throw CLIError.failed("Boot failed") }
        let item = items[0]
        items[0] = .init(
            id: item.id, status: "running", isDefault: false, cpus: item.cpus,
            memory: item.memory, diskSize: nil, ipAddress: nil)
    }
    func deleteMachine(_ id: String) async throws {}
    func stopMachine(_ id: String) async throws {}
}

@main struct CheckCreationWindow {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let client = CreationWindowFixture()
        let form = CreateMachineWindowController(store: ContainerStore(client: client))
        try check(
            form.imagePicker.itemTitles == ["Alpine 3.22", "Ubuntu 24.04", "Custom Image…"],
            "Presets are offered without relying on downloaded images")
        try check(form.imageField.isHidden, "Preset hides the raw image reference")
        form.checkImage()
        form.checkImage()
        try check(
            form.isCheckingImage && !form.createButton.isEnabled,
            "Verification blocks concurrent creation")
        try check(
            form.windowShouldClose(form.window!),
            "Image verification can be cancelled by closing the window")
        try await waitUntil("Verification succeeds before entering a machine name") {
            form.messageLabel.stringValue.contains("ready to use")
        }
        try check(await client.imageCalls == 1, "Repeated Check does not duplicate verification")
        form.imagePicker.selectItem(at: 1)
        form.imageSelectionChanged()
        try check(form.messageLabel.stringValue.isEmpty, "Changing presets clears old verification")
        form.imagePicker.selectItem(at: 2)
        form.imageSelectionChanged()
        try check(!form.imageField.isHidden, "Custom selection exposes a reference field")
        try render(form, appearance: .aqua, file: "Design/create-machine-custom.png")
        form.checkImage()
        try check(
            form.messageLabel.stringValue.contains("Enter an image reference"),
            "Empty custom reference is rejected inline")
        await client.configure(.image)
        form.imageField.stringValue = "alpine:missing"
        form.checkImage()
        try await waitUntil("Failed verification leaves an editable form") {
            form.messageLabel.stringValue.contains("Image tag not found")
                && form.createButton.isEnabled
        }
        form.imagePicker.selectItem(at: 0)
        form.imageSelectionChanged()
        await client.configure(.none)
        try check(form.startCheckbox.state == .on, "Start after creating is the default")
        try render(form, appearance: .aqua, file: "Design/create-machine-light.png")
        try render(form, appearance: .darkAqua, file: "Design/create-machine-dark.png")
        form.nameField.stringValue = "bad name"
        form.submit()
        try check(form.messageLabel.stringValue.contains("Use a name"), "Validation appears inline")
        try check(await client.calls == 0, "Invalid form never reaches the CLI")
        form.nameField.stringValue = "puffy"
        await client.configure(.create)
        form.submit()
        form.submit()
        try check(
            form.isCreating && !form.createButton.isEnabled && !form.cancelButton.isEnabled,
            "Creation disables duplicate submission and Cancel")
        try check(!form.windowShouldClose(form.window!), "Window stays open during creation")
        try await Task.sleep(for: .milliseconds(50))
        try render(form, appearance: .darkAqua, file: "Design/create-machine-busy.png")
        try await waitUntil("Failed creation preserves an editable form") {
            !form.isCreating && form.createButton.isEnabled && form.nameField.isEnabled
        }
        try check(await client.calls == 1, "Repeated submission creates only once")
        try render(form, appearance: .aqua, file: "Design/create-machine-error.png")
        await client.configure(.start)
        form.submit()
        try await waitUntil(
            "Partial success switches to Done instead of offering duplicate creation"
        ) {
            form.createButton.title == "Done" && !form.nameField.isEnabled
        }
        try check(
            form.messageLabel.stringValue.contains("Machine created"),
            "Boot failure explains partial success")
        try render(form, appearance: .darkAqua, file: "Design/create-machine-warning.png")
        let cancelledStore = ContainerStore(client: CreationWindowFixture())
        let cancelledForm = CreateMachineWindowController(store: cancelledStore)
        cancelledForm.checkImage()
        try await waitUntil("Check is active before cancellation") { cancelledStore.isBusy }
        cancelledForm.close()
        try await waitUntil("Closing the form cancels verification and releases busy state") {
            !cancelledStore.isBusy && !cancelledForm.isCheckingImage
        }
        print("Creation window checks passed; native controls rendered in both appearances.")
    }

    @MainActor static func render(
        _ form: CreateMachineWindowController, appearance: NSAppearance.Name, file: String
    ) throws {
        let window = form.window!
        window.appearance = NSAppearance(named: appearance)
        let view = window.contentView!
        view.layoutSubtreeIfNeeded()
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        window.appearance!.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
            view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext.current!)
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: file))
        // Layout must leave every native input and footer within the window.
        for control in [
            form.nameField, form.imageField, form.imagePicker, form.checkImageButton, form.cpuField,
            form.memoryField,
            form.startCheckbox, form.createButton, form.cancelButton, form.messageLabel,
        ] as [NSView] {
            if control.isHidden { continue }
            let frame = view.convert(control.bounds, from: control)
            try check(
                view.bounds.contains(frame),
                "\(control.accessibilityLabel() ?? "Control") stays inside the form")
        }
    }

    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CLIError.failed("FAIL: \(message)") }
        print("PASS: \(message)")
    }

    // The fixture holds each image or create call open on purpose. A fixed sleep
    // races that hold; CI scheduling can finish the hold after the sleep returns.
    @MainActor static func waitUntil(
        _ message: String, timeout: Duration = .seconds(2),
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if await condition() {
                print("PASS: \(message)")
                return
            }
            if clock.now >= deadline { throw CLIError.failed("FAIL: \(message)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
