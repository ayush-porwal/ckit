import AppKit
import Observation

// A regular native window keeps text editing and async work outside menu tracking.
@MainActor
final class CreateMachineWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate
{
    private let store: ContainerStore
    var onClose: (() -> Void)?
    let nameField = NSTextField(string: "")
    let imageField = NSTextField(string: "")
    let imagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let checkImageButton = NSButton(title: "Check Image", target: nil, action: nil)
    private let imageHint = NSTextField(wrappingLabelWithString: "")
    private var imageCheckTask: Task<Void, Never>?
    private var imageStatusDisplayed = false
    private(set) var isCheckingImage = false
    let cpuField = NSTextField(string: String(min(4, MachineCreationRequest.maximumCPUs)))
    let memoryField = NSTextField(string: String(min(4, MachineCreationRequest.maximumMemoryGiB)))
    let startCheckbox = NSButton(
        checkboxWithTitle: "Start after creating", target: nil, action: nil)
    let createButton = NSButton(title: "Create Machine", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var steppers: [NSStepper] = []
    private(set) var isCreating = false
    private var finished = false

    init(store: ContainerStore) {
        self.store = store
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 464),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Create Machine"
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        buildForm()
        observeOperation()
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    func present() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApplication.shared.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        if !isCreating && !finished { window.makeFirstResponder(nameField) }
    }

    private func buildForm() {
        guard let content = window?.contentView else { return }
        let puff = NSImageView()
        puff.image = BrandIcon.applicationImage
        puff.imageScaling = .scaleProportionallyUpOrDown
        puff.setAccessibilityElement(false)
        puff.widthAnchor.constraint(equalToConstant: 72).isActive = true
        puff.heightAnchor.constraint(equalToConstant: 72).isActive = true

        nameField.placeholderString = "my-machine"
        imageField.placeholderString = "registry/name:tag"
        imageField.delegate = self
        imagePicker.addItems(
            withTitles: MachineImagePreset.allCases.map(\.title) + ["Custom Image…"])
        imagePicker.target = self
        imagePicker.action = #selector(imageSelectionChanged)
        imagePicker.setAccessibilityLabel("Machine image preset")
        imagePicker.widthAnchor.constraint(equalToConstant: 324).isActive = true
        checkImageButton.bezelStyle = .rounded
        checkImageButton.controlSize = .small
        checkImageButton.target = self
        checkImageButton.action = #selector(checkImage)
        checkImageButton.toolTip =
            "Check availability for Apple Silicon. Downloads or prepares the image if needed."
        imageHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        imageHint.textColor = .secondaryLabelColor
        imageHint.preferredMaxLayoutWidth = 200
        let imageActions = NSStackView(views: [checkImageButton, imageHint])
        imageActions.orientation = .horizontal
        imageActions.spacing = 10
        let imageControls = NSStackView(views: [imagePicker, imageField, imageActions])
        imageControls.orientation = .vertical
        imageControls.alignment = .leading
        imageControls.spacing = 8
        imageField.widthAnchor.constraint(equalToConstant: 324).isActive = true
        imageSelectionChanged()
        nameField.setAccessibilityLabel("Machine name")
        imageField.setAccessibilityLabel("Container image")
        cpuField.setAccessibilityLabel("CPU count")
        memoryField.setAccessibilityLabel("Memory in GB")
        let cpu = numberControl(
            cpuField, maximum: MachineCreationRequest.maximumCPUs, tag: 0, unit: "CPUs")
        let memory = numberControl(
            memoryField, maximum: MachineCreationRequest.maximumMemoryGiB, tag: 1, unit: "GB")
        nameField.widthAnchor.constraint(equalToConstant: 324).isActive = true
        startCheckbox.state = .on
        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.preferredMaxLayoutWidth = 300
        messageLabel.maximumNumberOfLines = 4
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.isSelectable = true
        messageLabel.setAccessibilityLabel("Creation status")
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let status = NSStackView(views: [spinner, messageLabel])
        status.orientation = .horizontal
        status.alignment = .top
        status.spacing = 8
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        createButton.bezelStyle = .rounded
        createButton.keyEquivalent = "\r"
        createButton.target = self
        createButton.action = #selector(submit)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        let buttons = NSStackView(views: [cancelButton, createButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        // One shared control column anchors the inputs, checkbox, and feedback.
        let fields = NSStackView(views: [
            nameField, imageControls, cpu, memory, startCheckbox, status,
        ])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 14
        let labels = ["Name", "Image", "CPU", "Memory"].map { NSTextField(labelWithString: $0) }
        let labelControls: [NSView] = [nameField, imagePicker, cpuField, memoryField]
        for view in [puff, fields, buttons] + labels {
            content.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            puff.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            puff.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            fields.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 108),
            fields.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            fields.topAnchor.constraint(equalTo: puff.bottomAnchor, constant: 20),
            imageControls.widthAnchor.constraint(equalTo: fields.widthAnchor),
            status.widthAnchor.constraint(equalTo: fields.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: fields.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: fields.bottomAnchor, constant: 12),
        ])
        for (label, control) in zip(labels, labelControls) {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
                label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                label.trailingAnchor.constraint(
                    lessThanOrEqualTo: fields.leadingAnchor, constant: -16),
            ])
        }
        window?.defaultButtonCell = createButton.cell as? NSButtonCell
        window?.initialFirstResponder = nameField
    }

    private func numberControl(_ field: NSTextField, maximum: Int, tag: Int, unit: String) -> NSView
    {
        field.widthAnchor.constraint(equalToConstant: 66).isActive = true
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = NSNumber(value: maximum)
        field.formatter = formatter
        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = Double(maximum)
        stepper.integerValue = field.integerValue
        stepper.valueWraps = false
        stepper.tag = tag
        stepper.target = self
        stepper.action = #selector(step(_:))
        stepper.setAccessibilityLabel(tag == 0 ? "Adjust CPU count" : "Adjust memory")
        steppers.append(stepper)
        // Synchronize after typed edits, so the arrows continue from the entered value.
        field.delegate = self
        field.tag = tag
        let unitLabel = NSTextField(labelWithString: unit)
        unitLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [field, stepper, unitLabel])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    @objc private func step(_ sender: NSStepper) {
        (sender.tag == 0 ? cpuField : memoryField).integerValue = sender.integerValue
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === imageField {
            clearImageStatus()
            return
        }
        guard field === cpuField || field === memoryField,
            let value = Int(field.stringValue), value >= 1
        else { return }
        steppers[field.tag].integerValue = value
    }

    private var selectedPreset: MachineImagePreset? {
        let index = imagePicker.indexOfSelectedItem
        return MachineImagePreset.allCases.indices.contains(index)
            ? MachineImagePreset.allCases[index] : nil
    }

    private var selectedReference: String { selectedPreset?.reference ?? imageField.stringValue }

    @objc func imageSelectionChanged() {
        guard !isCreating && !isCheckingImage else { return }
        window?.setContentSize(NSSize(width: 460, height: selectedPreset == nil ? 496 : 464))
        imageField.isHidden = selectedPreset != nil
        imageHint.stringValue = selectedPreset?.hint ?? "Needs /sbin/init to boot."
        imageHint.isHidden = imageHint.stringValue.isEmpty
        clearImageStatus()
    }

    private func clearImageStatus() {
        if imageStatusDisplayed {
            showMessage("", error: false)
            imageStatusDisplayed = false
        }
    }

    @objc func checkImage() {
        guard !isCreating && !isCheckingImage && !finished else { return }
        let reference: String
        do { reference = try ImageReference.validated(selectedReference) } catch {
            imageStatusDisplayed = true
            showMessage(error.localizedDescription, error: true)
            return
        }
        let preset = selectedPreset
        isCheckingImage = true
        imageStatusDisplayed = true
        setInputsEnabled(false)
        createButton.isEnabled = false
        spinner.startAnimation(nil)
        showMessage(
            "Checking image… Downloads or first-time preparation may take a few minutes.",
            error: false)
        imageCheckTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isCheckingImage = false
                setInputsEnabled(true)
                createButton.isEnabled = true
                spinner.stopAnimation(nil)
                imageCheckTask = nil
            }
            do {
                let result = try await store.checkImage(reference, preset: preset)
                try Task.checkCancellation()
                let text =
                    preset == nil
                    ? "Image available for Apple Silicon. Boot compatibility is checked when starting the machine."
                    : "\(preset!.title) is ready to use."
                showMessage(result.wasPrepared ? "Image prepared. " + text : text, error: false)
                messageLabel.textColor = .systemGreen
            } catch is CancellationError {
                showMessage("", error: false)
            } catch {
                showMessage("Couldn’t check the image. \(error.localizedDescription)", error: true)
            }
        }
    }

    @objc func submit() {
        guard !isCreating && !isCheckingImage else { return }
        if finished {
            close()
            return
        }
        guard let cpus = Int(cpuField.stringValue), let memory = Int(memoryField.stringValue) else {
            showMessage("Enter whole numbers for CPU and memory.", error: true)
            return
        }
        let request = MachineCreationRequest(
            name: nameField.stringValue, image: selectedReference,
            cpus: cpus, memoryGiB: memory, startAfterCreation: startCheckbox.state == .on,
            preset: selectedPreset)
        do { _ = try request.validated() } catch {
            showMessage(error.localizedDescription, error: true)
            return
        }
        imageStatusDisplayed = false
        setCreating(true)
        Task { [self] in
            let result = await store.createMachine(request)
            setCreating(false)
            switch result {
            case .created(warning: nil): close()
            case .created(let warning): finishWithMessage(warning ?? "Machine created.")
            case .uncertain(let message): finishWithMessage(message)
            case .failed(let message): showMessage(message, error: true)
            }
        }
    }

    private func setCreating(_ creating: Bool) {
        isCreating = creating
        setInputsEnabled(!creating)
        createButton.isEnabled = !creating
        createButton.title = creating ? "Creating…" : "Create Machine"
        cancelButton.isEnabled = !creating
        window?.standardWindowButton(.closeButton)?.isEnabled = !creating
        if creating {
            spinner.startAnimation(nil)
            showMessage("Preparing your machine…", error: false)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    private func setInputsEnabled(_ enabled: Bool) {
        [nameField, imageField, cpuField, memoryField].forEach { $0.isEnabled = enabled }
        steppers.forEach { $0.isEnabled = enabled }
        startCheckbox.isEnabled = enabled
        imagePicker.isEnabled = enabled
        checkImageButton.isEnabled = enabled
    }

    private func observeOperation() {
        withObservationTracking {
            if isCreating || isCheckingImage, let operation = store.operation {
                showMessage(
                    operation.title + " This may take a few minutes on the first download.",
                    error: false)
            } else {
                _ = store.operation
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeOperation() }
        }
    }

    private func finishWithMessage(_ message: String) {
        finished = true
        setInputsEnabled(false)
        createButton.title = "Done"
        cancelButton.isHidden = true
        showMessage(message, error: true)
    }

    private func showMessage(_ message: String, error: Bool) {
        messageLabel.stringValue = message
        messageLabel.toolTip = message
        messageLabel.textColor = error ? .systemRed : .secondaryLabelColor
    }

    @objc private func cancel() { if !isCreating { close() } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !isCreating }
    func windowWillClose(_ notification: Notification) {
        imageCheckTask?.cancel()
        onClose?()
    }
}
