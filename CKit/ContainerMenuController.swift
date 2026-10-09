import AppKit
import Observation

@MainActor
protocol UpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

// Standard NSMenu items let macOS own the material, metrics, and interaction.
@MainActor
final class ContainerMenuController: NSObject, NSMenuDelegate {
    enum Action {
        case service, refresh, createMachine
        case machine(String)
        case terminal(String)
        case deleteMachine(String)
        case copyError, dismissError, checkForUpdates, automaticUpdates, quit
    }

    let menu = NSMenu(title: "Ckit")
    private let store: ContainerStore
    private let updates: (any UpdateChecking)?
    private var statusItem: NSStatusItem?
    private var creationWindow: CreateMachineWindowController?
    private var machineItems: [String: MachineItems] = [:]

    private struct MachineItems {
        let row: NSMenuItem
        let toggle: NSMenuItem
        let terminal: NSMenuItem
        let delete: NSMenuItem
    }

    private lazy var serviceItem = item("Checking service…", action: .service, icon: .power)
    private let serviceDivider = NSMenuItem.separator()
    private let machinesHeader = NSMenuItem.sectionHeader(title: "Machines")
    private let placeholder = NSMenuItem(
        title: "Checking the service…", action: nil, keyEquivalent: "")
    private lazy var createItem = item(
        "Create Machine…", action: .createMachine, icon: .create, key: "n")
    private let createDivider = NSMenuItem.separator()
    private let machinesDivider = NSMenuItem.separator()
    private let errorHeader = NSMenuItem.sectionHeader(title: "Couldn't update status")
    private let errorDetail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var copyErrorItem = item("Copy Error Details", action: .copyError, icon: .copy)
    private lazy var dismissErrorItem = item("Dismiss Error", action: .dismissError, icon: .close)
    private let errorDivider = NSMenuItem.separator()
    private lazy var retryItem = item("Retry", action: .refresh, icon: .refresh, key: "r")
    private lazy var checkUpdatesItem = item("Check for Updates…", action: .checkForUpdates)
    private lazy var automaticUpdatesItem = item(
        "Automatically Check for Updates", action: .automaticUpdates)
    private lazy var quitItem = item("Quit Ckit", action: .quit, icon: .quit, key: "q")

    init(
        store: ContainerStore, installsStatusItem: Bool = true,
        updates: (any UpdateChecking)? = nil
    ) {
        self.store = store
        self.updates = updates
        super.init()
        menu.autoenablesItems = false
        menu.minimumWidth = 280
        menu.delegate = self
        if installsStatusItem {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            status.button?.image = BrandIcon.menuBarImage
            status.button?.toolTip = "Ckit — container machines"
            status.button?.setAccessibilityLabel("Ckit — container machines")
            status.menu = menu
            statusItem = status
            Task { await store.refresh() }
        }
        observeStore()
    }

    private func observeStore() {
        withObservationTracking {
            updateMenu()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeStore() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        updateMenu()
        store.setPanelVisible(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        store.setPanelVisible(false)
    }

    private func updateMenu() {
        switch store.service {
        case .running: serviceItem.title = "Stop Service"
        case .stopped: serviceItem.title = "Start Service"
        case .unknown: serviceItem.title = "Checking Service…"
        case .unavailable: serviceItem.title = "Service Unavailable"
        }
        if store.operation == .startService { serviceItem.title = "Starting Service…" }
        if store.operation == .stopService { serviceItem.title = "Stopping Service…" }
        serviceItem.isEnabled =
            !store.isBusy && (store.service == .running || store.service == .stopped)
        serviceItem.toolTip =
            store.service == .running
            ? "Stop the service and all container machines and containers"
            : "Start the container service"
        retryItem.title = store.isRefreshing ? "Retrying…" : "Retry"
        retryItem.isEnabled = !store.isBusy
        createItem.isEnabled = !store.isBusy
        quitItem.isEnabled = store.operation == nil
        checkUpdatesItem.isEnabled = !store.isBusy && updates?.canCheckForUpdates == true
        automaticUpdatesItem.isEnabled = updates?.canCheckForUpdates == true
        automaticUpdatesItem.state =
            updates?.automaticallyChecksForUpdates == true ? .on : .off
        [placeholder, errorDetail].forEach { $0.isEnabled = false }

        var rows = [serviceItem, serviceDivider, machinesHeader]
        let visibleMachines = store.service == .running ? store.machines : []
        let visibleIDs = Set(visibleMachines.map(\.id))
        machineItems = machineItems.filter { visibleIDs.contains($0.key) }
        for machine in visibleMachines {
            let items = machineItems[machine.id] ?? makeMachineItems(machine)
            machineItems[machine.id] = items
            items.row.title = machine.id
            let state = machineState(machine)
            items.row.subtitle =
                "\(machine.cpus) CPU · \(machine.memoryLabel) · \(state)\(machine.isDefault ? " · Default" : "")"
            items.row.image = BrandIcon.glyphImage(machine.isRunning ? .machine : .sleepingMachine)
            items.row.isEnabled = store.hasLoadedMachines
            items.row.toolTip = machine.id
            items.toggle.title = "\(machine.isRunning ? "Stop" : "Start") Machine"
            items.toggle.image = BrandIcon.glyphImage(machine.isRunning ? .stop : .play)
            items.toggle.isEnabled =
                !store.isBusy && store.hasLoadedMachines && (machine.isRunning || machine.isStopped)
            items.terminal.isEnabled = !store.isBusy && store.hasLoadedMachines && machine.isRunning
            items.terminal.toolTip =
                machine.isRunning
                ? "Open a shell inside \(machine.id)" : "Start the machine to open Terminal"
            items.delete.title =
                store.operation == .deleteMachine(machine.id)
                ? "Deleting Machine…" : "Delete Machine"
            items.delete.isEnabled = !store.isBusy && store.hasLoadedMachines
            items.delete.toolTip =
                "Permanently delete \(machine.id) and its disk. Stops it first if running."
            rows.append(items.row)
        }
        if visibleMachines.isEmpty {
            switch store.service {
            case .stopped:
                placeholder.title = "Service is stopped"
                placeholder.subtitle = "Start the service to see your machines."
            case .unknown:
                placeholder.title = "Checking the service…"
                placeholder.subtitle = nil
            case .unavailable:
                placeholder.title = "Service unavailable"
                placeholder.subtitle = "Retry to check the service status."
            case .running:
                placeholder.title =
                    store.hasLoadedMachines ? "No machines yet" : "Machine list unavailable"
                placeholder.subtitle =
                    store.hasLoadedMachines
                    ? "Choose Create Machine to get started." : "Retry to load your machines."
                if store.isRefreshing {
                    placeholder.title = "Loading machines…"
                    placeholder.subtitle = nil
                }
            }
            rows.append(placeholder)
        }
        rows += [createDivider, createItem, machinesDivider]
        if let error = store.errorMessage {
            errorDetail.title = String(error.prefix(75)) + (error.count > 75 ? "…" : "")
            errorDetail.toolTip = error
            rows += [errorHeader, errorDetail, copyErrorItem, dismissErrorItem, errorDivider]
        }
        copyErrorItem.title = store.notice ?? "Copy Error Details"
        if store.errorMessage != nil || store.service == .unavailable
            || (store.service == .running && !store.hasLoadedMachines && !store.isRefreshing)
        {
            rows.append(retryItem)
        }
        if updates != nil {
            rows += [checkUpdatesItem, automaticUpdatesItem, .separator()]
        }
        rows.append(quitItem)
        reconcile(menu, with: rows)
    }

    // Keep existing item identities while tracking, so refresh doesn't tear down
    // a highlighted machine or its open submenu.
    private func reconcile(_ menu: NSMenu, with desired: [NSMenuItem]) {
        for existing in menu.items where !desired.contains(where: { $0 === existing }) {
            menu.removeItem(existing)
        }
        for (index, item) in desired.enumerated() {
            if menu.index(of: item) == index { continue }
            if menu.index(of: item) >= 0 { menu.removeItem(item) }
            menu.insertItem(item, at: index)
        }
    }

    private func machineState(_ machine: Machine) -> String {
        guard store.operation?.machineID == machine.id else { return machine.stateTitle }
        switch store.operation {
        case .startMachine: return "Starting…"
        case .stopMachine: return "Stopping…"
        case .deleteMachine: return "Deleting…"
        case .terminal: return "Opening Terminal…"
        default: return machine.stateTitle
        }
    }

    private func makeMachineItems(_ machine: Machine) -> MachineItems {
        let row = NSMenuItem(title: machine.id, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: machine.id)
        submenu.autoenablesItems = false
        let toggle = item("Start Machine", action: .machine(machine.id), icon: .play)
        let terminal = item("Open Terminal", action: .terminal(machine.id), icon: .terminal)
        let delete = item("Delete Machine", action: .deleteMachine(machine.id), icon: .delete)
        [toggle, terminal, .separator(), delete].forEach { submenu.addItem($0) }
        row.submenu = submenu
        return MachineItems(row: row, toggle: toggle, terminal: terminal, delete: delete)
    }

    private func item(_ title: String, action: Action, icon: GlyphKind? = nil, key: String = "")
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: #selector(handleAction(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = action
        if let icon { item.image = BrandIcon.glyphImage(icon) }
        return item
    }

    @objc private func handleAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? Action else { return }
        switch action {
        case .service:
            Task {
                switch store.service {
                case .running: await store.stopService()
                case .stopped: await store.startService()
                default: await store.refresh()
                }
            }
        case .refresh: Task { await store.refresh() }
        case .createMachine:
            guard !store.isBusy else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if creationWindow == nil {
                    let window = CreateMachineWindowController(store: store)
                    window.onClose = { [weak self] in self?.creationWindow = nil }
                    creationWindow = window
                }
                creationWindow?.present()
            }
        case .machine(let id):
            guard let machine = store.machines.first(where: { $0.id == id }) else { return }
            Task { await store.toggleMachine(machine) }
        case .terminal(let id):
            guard let machine = store.machines.first(where: { $0.id == id }) else { return }
            Task { await store.openTerminal(machine) }
        case .deleteMachine(let id):
            guard let machine = store.machines.first(where: { $0.id == id }) else { return }
            Task { await store.deleteMachine(machine) }
        case .copyError: store.copyError()
        case .dismissError:
            store.errorMessage = nil
            store.notice = nil
        case .checkForUpdates:
            guard !store.isBusy, updates?.canCheckForUpdates == true else { return }
            updates?.checkForUpdates()
        case .automaticUpdates:
            guard let updates, updates.canCheckForUpdates else { return }
            updates.automaticallyChecksForUpdates.toggle()
            updateMenu()
        case .quit: NSApplication.shared.terminate(nil)
        }
    }
}
