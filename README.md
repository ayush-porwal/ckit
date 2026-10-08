# CKit

A small native macOS menu bar app for Apple’s `container` CLI.

## Features

- Start and stop the container service.
- Create machines from a native form, with optional automatic startup.
- List machines and their running or stopped state.
- Start, stop, or delete individual machines.
- Open Terminal inside a running machine.
- Automatic status updates and error recovery.

The app checks status when its menu opens and every 10 seconds while open. Retry appears only after an error or unavailable status. Quitting leaves the service and machines alone. Start Service and Stop Service act directly; stopping it stops all machines and containers.

## Requirements

- Apple Silicon Mac with macOS 26 or later.
- Apple `container` 1.5.0 or a compatible release, installed and initialized.
- Xcode 27 to build from source.

CKit finds `container` on the app’s inherited `PATH`, then checks standard locations including `/opt/homebrew/bin` and `/usr/local/bin`. CLI discovery runs again during status checks; there is no executable picker. Initial kernel setup belongs in Terminal; CKit starts the service without an interactive installation prompt.

## Install

Open the release DMG and drag **CKit** onto **Applications**. Or unzip the app and move `CKit.app` into `/Applications`. Launch it from Applications; Puff appears in the menu bar. Install Apple’s `container` CLI separately.

For the current local build, copy `dist/CKit.app` into Applications.

Releases use ad hoc signing without notarization. If macOS blocks a downloaded build you trust, open **System Settings → Privacy & Security → Open Anyway**. See [Apple’s instructions](https://support.apple.com/en-us/102445). Developer ID signing and notarization require an Apple Developer account and are not configured here.

## Build

To run from source, open `CKit.xcodeproj`, select **CKit → My Mac**, and press **Command-R**. Click Puff in the menu bar. Open a machine’s submenu to start, stop, delete it, or open Terminal.

```sh
xcodebuild -project CKit.xcodeproj -scheme CKit -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Release/CKit.app
```

Build an app, ZIP, and DMG locally:

```sh
bash Scripts/PackageRelease.sh 0.1.0
open dist/releases/v0.1.0
```

The optional second argument sets the build number. Outputs include `CKit.app`, `CKit-0.1.0-arm64.zip`, `CKit-0.1.0-arm64.dmg`, and `SHA256SUMS.txt`. Existing version folders are not overwritten.

## GitHub releases

1. Commit and push the project, including `.github/workflows/release.yml`, to the repository’s default branch.
2. Open **Actions → Release CKit → Run workflow** on that branch.
3. Enter a new version such as `0.1.0` and run it.

The workflow runs core and native UI fixture checks, builds the app, creates an annotated `v0.1.0` tag for the selected commit, and publishes a GitHub Release with the DMG, ZIP, and checksums. The app version matches the tag; the Actions run number becomes the build number. Assets upload to a draft before publication.

It uses GitHub’s [Xcode 27 Apple Silicon runner](https://github.com/actions/runner-images#available-images), currently a public preview, and the built-in `GITHUB_TOKEN`. No personal token or Apple signing secrets are needed. Repository rules must permit the workflow to create tags and releases. Existing tags are rejected. If a run fails after tagging, remove its incomplete release and tag before retrying, or use a new version.

## What to commit

This folder has not been initialized as a Git repository. For a first commit:

```sh
git init -b main
git add .gitignore .github CKit CKit.xcodeproj Package.swift Scripts Tests README.md LEARN.md
git commit -m "Add CKit app and release workflow"
```

Include the PNG icons inside `CKit/Assets.xcassets` and the shared Xcode scheme. `Design/` contains local design history and is ignored. `.gitignore` also excludes build output, installers, logs, private signing files, and personal Xcode state. Release binaries belong in GitHub Release assets.

## Create a machine

Click Puff → **Create Machine…**. Choose an image preset, then enter a name, CPU count, and memory. The default is Alpine 3.22, with up to 4 CPUs and 4 GB of memory.

The selector always offers these choices, even on a fresh Mac:

- **Alpine 3.22**: ready-to-use Linux image.
- **Ubuntu 24.04**: CKit prepares a machine-ready image locally on first use, following [Apple’s Ubuntu machine example](https://github.com/apple/container/blob/1.5.0/docs/container-machine.md). The first build can take several minutes; later creations reuse it.
- **Custom Image…**: enter a registry reference or local image tag.

**Check Image** verifies Linux/arm64 availability and downloads or prepares the image if needed. It can start the service, but does not create a machine. Custom images still need a working init system; availability alone does not guarantee they will boot. Closing the form cancels the check.

**Start after creating** is checked by default. Uncheck it to create a stopped machine, then use its submenu → **Start Machine** later. The service starts automatically when you submit.

CKit validates the form, checks for duplicate names, and shows progress and errors inline. If creation succeeds but boot fails, reopen the menu to start the machine later. New machines do not mount your Mac’s home folder. Other images must meet [Apple’s machine image requirements](https://github.com/apple/container/blob/1.5.0/docs/container-machine.md).

## Check

```sh
swift test --scratch-path .build/tests
```

Check the native menu using fixtures, without changing real machines:

```sh
swiftc -parse-as-library CKit/Core/*.swift CKit/Interface/*.swift CKit/ContainerMenuController.swift Scripts/CheckNativeMenu.swift -o .build/check-native-menu
.build/check-native-menu
```

Check the native creation form with fixtures and render its light and dark appearances:

```sh
swiftc -parse-as-library CKit/Core/*.swift CKit/Interface/*.swift Scripts/CheckCreationWindow.swift -o .build/check-creation-window
.build/check-creation-window
```

Check real creation, both startup choices, and deletion of stopped and running disposable machines:

```sh
swiftc -parse-as-library CKit/Core/*.swift Scripts/CreationSmokeTest.swift -o .build/creation-smoke-test
.build/creation-smoke-test
```

`Scripts/ImagePresetSmokeTest.swift` checks Alpine and Ubuntu presets, boots a disposable Ubuntu machine, and rejects a nonexistent tag. It keeps prepared images for reuse.

The creation test removes its own machines and preserves existing machine and service states. It may download Alpine into the CLI image cache.

`Scripts/LiveSmokeTest.swift` checks real service and machine actions. `Scripts/TerminalSmokeTest.swift` checks Terminal launches the interactive CLI. Both restore initial service and machine states. Keyboard input inside Terminal is a manual check. Use a stopped machine you intend to test.

## Project files

- `.github/workflows/release.yml`: tested release build, tag, and asset publication.
- `Scripts/PackageRelease.sh`: local and CI app, ZIP, DMG, and checksum packaging.
- `CKit/CKitApp.swift`: AppKit application entry and lifecycle.
- `CKit/ContainerMenuController.swift`: native status item, menu, observation, and actions.
- `CKit/Core/`: CLI execution, state, and Terminal integration.
- `CKit/Interface/CreateMachineWindow.swift`: native creation form and progress.
- `CKit/Interface/`: custom vector icons and AppKit controls.
- `CKit/Interface/PuffArtwork.swift`: Puff app artwork and menu bar face.
- `LEARN.md`: short learning notes for each phase.

Puff is the app and menu bar icon. CKit uses standard AppKit menus, so macOS controls the glass appearance, light and dark colors, keyboard navigation, and accessibility behavior. Each machine has a submenu for its actions. Status refreshes preserve existing menu items. Machine submenus contain Start/Stop, Open Terminal, and Delete Machine. Deletion acts directly, stops a running machine first, and permanently removes its disk. Quit is the last option.

Rebuild the app icon assets from the same vector drawing used in the panel:

```sh
mkdir -p .build
swiftc CKit/Interface/PuffArtwork.swift Scripts/GenerateIcons.swift -o .build/generate-icons
.build/generate-icons
```

The menu bar face is a template image, so it adapts to the macOS appearance.

Puff and the action icons use smooth curves and rounded corners. `Scripts/PreviewIcons.swift` renders the native paths at actual and enlarged sizes for inspection.
