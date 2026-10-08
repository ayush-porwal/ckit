# Learning notes

Read these when you want to understand the finished app. Each entry covers a completed phase.

## 1. A native menu bar app

Start with `CKitApp.swift` and `ContainerMenuController.swift`.

- `@main` marks the app's entry point.
- `NSApplication` runs the native event loop; its delegate handles launch.
- `NSStatusItem` puts Puff in the menu bar. `NSMenu` supplies the OS appearance.
- Xcode's Command-R builds and runs the project.

## 2. Talking to the container CLI

Read `Core/ContainerClient.swift`, then `Models.swift` and `ProcessRunner.swift`.

- `Decodable` converts JSON into Swift values. `CodingKeys` maps JSON's `default` to `isDefault`.
- `Process` runs an executable with an argument array. It does not need a shell.
- `async`/`await` lets a function wait without blocking the app's interface.
- Service status and machine status are separate. A stopped service cannot list machines.
- A stopped service returns JSON with exit code 1. Other failures must remain errors.
- Machine Start runs `/bin/true`, avoiding the CLI's default login shell.
- Timeouts and cancellation prevent a stuck CLI from keeping the interface busy indefinitely.

Focus on one command's path from arguments to JSON to a Swift value.

## 3. State and actions

Read `Core/ContainerStore.swift`.

- `@Observable` lets SwiftUI update when values change.
- `@MainActor` keeps interface state on macOS's main thread.
- The store coordinates commands and prevents overlapping actions.
- Refresh after an action: a failed command can still have changed the machine.
- Keep unknown states and errors visible; do not guess that a machine stopped.

## 4. Interface and icons

Read `ContainerMenuController.swift` and `Interface/Icons.swift`.

- `NSMenuItem` provides native titles, subtitles, shortcuts, and submenus.
- Target/action connects a menu selection to the store.
- `Shape` and `Path` draw our own vector icons at any size.
- Template images adapt icons to the OS appearance.
- Menu delegate callbacks start and stop polling when the menu opens and closes.

## 5. Checking behavior

Read `Tests/CoreTests.swift` and `Scripts/LiveSmokeTest.swift`.

- Unit tests cover JSON decoding, cancellation, timeouts, quoting, and state transitions.
- A mock client lets us test failures without changing real machines.
- A live smoke test checks the actual installed CLI and restores initial states.
- Light and dark previews help catch clipping and contrast problems.

## 6. Finishing the Graphite design

Read `Interface/Icons.swift`. Graphite was the first finished visual direction; Puff replaces its app artwork in phase 10.

- Core Graphics draws the app icon from shapes, gradients, and shadows.
- Recessed tracks and raised knobs create depth without a large image dependency.
- App icons need several pixel sizes; the asset catalog tells Xcode which to use.
- Action icons stay simple at 15 pixels. Tooltips and accessible labels explain icon-only buttons.
- Native menus and scroll views need a hosting window for accurate preview rendering.

The compact layout removes the title block, reduces the service area to one row, and uses icons for Refresh and Quit.

## 7. Packaging and launch

- A release build creates a self-contained `.app` bundle in `dist/`.
- Local ad hoc signing is enough to run your own build. Public distribution needs separate signing and notarization.
- Terminal opens a quoted `.command` file through Launch Services. The file deletes itself when it runs.
- The live checks verified service actions, machine actions, and an interactive CLI process launched by Terminal.
- Terminal keyboard input remains a manual check because the UI automation tool restricts Terminal.

## 8. Exploring character icons

Open `Design/cute-icon-options.html`.

- SVG symbols reuse one drawing at several sizes.
- A clear silhouette makes a character recognizable at 32 pixels.
- Menu bar marks simplify the same character into a monochrome outline.
- Compare light and dark backgrounds before choosing an icon. Preview choices stay separate from app assets.

## 9. Direct service control

Read `handleAction` in `ContainerMenuController.swift`.

- A button starts an asynchronous store action with `Task`.
- Start Service and Stop Service call the store directly, without a confirmation dialog.
- The store disables overlapping actions and refreshes the service state when the command finishes.

## 10. Bringing Puff into the app

Read `Interface/PuffArtwork.swift`, `Interface/Icons.swift`, and `ContainerMenuController.swift`.

- One Core Graphics drawing supplies the app icon and the panel companion.
- Happy, sleepy, working, and concerned expressions follow real app state.
- The menu bar uses a simpler monochrome face, legible at 20 pixels.
- Adaptive colors give light and dark appearances the same soft mint palette.
- Button hover and press animations respect the system's Reduce Motion setting.
- Native previews cover running, stopped, empty, busy, error, and long-name states.

The release build and 20 core tests passed. A live direct Stop check cleared machine rows and restored the original service state.

## 11. Letting macOS draw the menu

Read `CKitApp.swift`, `ContainerMenuController.swift`, and `Scripts/CheckNativeMenu.swift`.

- Standard `NSMenu` items inherit macOS materials, appearance, highlighting, and keyboard navigation.
- Use native section headers and subtitles instead of custom cards and fonts.
- `withObservationTracking` updates menu items when the store changes.
- Keep menu item identities stable so refresh does not tear down an open submenu.
- Menu actions launch independent tasks; closing the menu only cancels polling.
- Fixture checks cover Start/Stop routing, stale controls, busy states, and submenu identity.

The release build and all 14 native-menu fixture checks passed. The running app uses the new build.

## 12. Smoothing the icon paths

Read `Interface/PuffArtwork.swift` and `Interface/Icons.swift`.

- Matching Bézier tangents smooth the joins between Puff's cloud lobes.
- Rounded stroke joins do not round the corners of a filled shape; Play needs curved geometry.
- The app artwork and menu bar face share the same cloud outline.
- Check native paths at 18 and 20 points as well as enlarged sizes. `Scripts/PreviewIcons.swift` renders both.

Regenerated all app icon sizes and SVG exports, inspected the native paths in light and dark previews, and launched the successful release build.

## 13. Keeping About artwork current

Read `BrandIcon.applicationImage` and the About action in `ContainerMenuController.swift`.

- The standard About panel accepts an explicit application icon.
- Passing Puff's current vector artwork avoids relying on an older macOS icon lookup.
- Set the running application's icon at launch, too, so both use the same image.

Confirmed the packaged icon already contains Puff. The explicit About icon fix builds successfully and is running.


## 14. Creating machines from the menu

Read `MachineCreationRequest`, `ContainerStore.createMachine`, and `CreateMachineWindow.swift`.

- Validate input before starting the service or running commands.
- Use a fresh machine list to check names; cached UI state can be stale.
- Keep creation and startup separate so users can choose when to launch.
- Track partial success: a boot failure must not invite duplicate creation.
- Native AppKit controls handle appearance, text editing, and accessibility.
- `container` 1.5.0 requires terminal stdin for first-boot user setup. `ProcessRunner` supplies it only for machine startup, while preserving timeouts and output capture.

All 34 core tests and native form/menu checks passed. Real creation, manual launch, and automatic launch passed with disposable machines that were removed afterward. The release build is running.


## 15. Keeping the menu minimal

Read `ContainerMenuController`, `ContainerClient.findExecutable`, and `ContainerStore.discoverExecutable`.

- Show machine details once, on the parent row; keep its submenu for actions.
- Put About directly above Quit and let its native window show the app version.
- Refresh automatically when opening the menu and while it stays open. Offer Retry only for recovery.
- Discover the CLI from PATH, with standard installation paths for Finder launches.
- Check executable files rather than accepting any matching directory; preserve PATH for CLI subprocesses.

Removed Preferences, the executable picker, repeated machine details, and IP rows. All 38 core tests and 25 native menu checks passed, including PATH discovery and Retry recovery.


## 16. Image presets and checks

Read `MachineImagePreset`, `ContainerClient.prepareImage`, and the image controls in `CreateMachineWindow.swift`.

- Offer known presets independently of the local image cache.
- A distro image and a machine-ready image can differ: Ubuntu needs an init system.
- Reuse prepared images; make the first-build cost visible.
- Check cached images offline, then pull the Linux/arm64 variant when needed.
- Keep availability separate from boot compatibility for custom references.
- Clear verification when the selected image changes; cancel checks when closing the form.
- Keep self-explanatory controls concise: the launch checkbox needs no helper paragraph.

All 45 core tests and native form checks passed. Live checks verified Alpine, prepared and booted Ubuntu, and rejected a nonexistent tag. The disposable Ubuntu machine was removed; prepared images stay cached.


## 17. Form alignment

Read the layout constraints in `CreateMachineWindow.swift`.

- Use one shared column for the fields, checkbox, and status.
- Center a larger Puff above the form; let the window title identify its purpose.
- Align labels to the controls they describe, including the image picker.
- Keep consistent outer margins and leave room for progress and errors.

Native form checks passed for presets, custom images, progress, and errors in light and dark appearances. The release build passed.


## 18. Deleting machines

Read `ContainerStore.deleteMachine`, `ContainerClient.deleteMachine`, and the machine submenu.

- Pass the exact machine ID as an argument, after `--`.
- Disable overlapping actions and show deletion progress.
- Separate the machine list from Create Machine with a standard menu divider.
- Keep the menu focused on actions; omit About and leave Quit last.
- Confirm deletion from a successful fresh list; an unavailable list is not proof.
- Refresh after failures too, since commands can partially complete.

All 51 core tests and 31 native menu checks passed. Live checks deleted stopped and running disposable machines; existing machines and service state were preserved.


## 19. Packaging and releases

Read `Scripts/PackageRelease.sh` and `.github/workflows/release.yml`.

- An app bundle is the runnable product; a DMG packages it for drag-to-Applications installation.
- Set the app version during the build and tag the exact source commit.
- Test before tagging, then upload assets to a draft before publishing.
- Commit source, icon assets, the shared scheme, and workflows; ignore generated binaries.
- Ad hoc signing verifies bundle integrity. Developer ID signing and notarization provide trusted distribution.
- Keep `.gitignore` scoped: ignore local design history and build artifacts, while retaining app icon PNGs and the shared Xcode scheme.
