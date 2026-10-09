import AppKit
import Observation
import Sparkle

// Sparkle owns download, signature validation, installation, and relaunch UI.
@MainActor
final class UpdateController: NSObject, UpdateChecking, SPUUpdaterDelegate {
    private let store: ContainerStore
    private var controller: SPUStandardUpdaterController!
    private var pendingInstall: (() -> Void)?

    init(store: ContainerStore, startsUpdater: Bool = true) {
        self.store = store
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        // Development builds never contact the production feed or replace themselves.
        #if !DEBUG
            if startsUpdater { controller.startUpdater() }
        #endif
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, !store.isBusy else { return }
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !store.isBusy else {
            throw NSError(
                domain: "dev.local.ckit.updates", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Ckit is finishing a container operation. Please check for updates afterward."
                ])
        }
    }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        postponeInstallationIfBusy(installHandler)
    }

    // Also used by the fixture to verify that a running operation finishes first.
    func postponeInstallationIfBusy(_ installHandler: @escaping () -> Void) -> Bool {
        guard store.isBusy else { return false }
        pendingInstall = installHandler
        observeOperation()
        return true
    }

    private func observeOperation() {
        withObservationTracking {
            if !store.isBusy, let install = pendingInstall {
                pendingInstall = nil
                install()
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeOperation() }
        }
    }
}
