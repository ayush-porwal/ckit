# Releasing Ckit

The Xcode project, scheme, source folder, and test module keep their existing
`CKit` names. The product is `Ckit.app`; its bundle identifier remains
`dev.local.ckit`. No folder rename is required, and the installed app is still
recognized as the same product.

## One-time update signing setup

Sparkle 2.10.0 is pinned in the Xcode project. The public Ed25519 key is in
`Config/Updates.xcconfig`; the dedicated private key is in the macOS login
Keychain, with account `dev.local.ckit`. Back up this key securely. Do not
generate a different key for each release, and never add the private key to Git.

To enable the release workflow, export the existing key and upload it to the
`ayush-porwal/ckit` repository's **SPARKLE_PRIVATE_KEY** Actions secret:

```sh
stage="$(mktemp -d)"
bash Scripts/FetchSparkle.sh "$stage/tools"
umask 077
"$stage/tools/bin/generate_keys" --account dev.local.ckit -x "$stage/key"
gh secret set SPARKLE_PRIVATE_KEY --repo ayush-porwal/ckit < "$stage/key"
rm -rf "$stage"
```

The secret is passed through stdin to Sparkle's signing tool. The workflow
rejects a missing key and verifies that the update ZIP's signature matches the
public key before tagging or publishing a release.

## Release

Run the **Release Ckit** workflow from the default branch with an `X.Y.Z`
version. It runs tests, packages the app, checks the updater using a separate
fixture, creates a signed `appcast.xml`, and publishes all assets together.
No separate update server or GitHub Pages setup is needed. The stable feed is:

`https://github.com/ayush-porwal/ckit/releases/latest/download/appcast.xml`

Keep the repository and releases public, and include `appcast.xml` in every
release marked latest. Upload the update ZIP before publishing the feed; do not
edit a signed feed after generating it. The feed points at the version-specific
GitHub release ZIP and requires macOS 26 and Apple Silicon. It offers the latest
full ZIP; delta updates are not generated yet.

For a local release:

```sh
bash Scripts/PackageRelease.sh 0.1.0 2
bash Scripts/CheckUpdates.sh dist/releases/v0.1.0/Ckit.app
bash Scripts/GenerateAppcast.sh 0.1.0 dist/releases/v0.1.0
```

Always increase the build number (`CFBundleVersion`); Sparkle compares that
value rather than the display version. CI uses `GITHUB_RUN_NUMBER`. Preserve
its increasing sequence if the workflow is recreated or releases switch to a
different build system.

The package script uses Xcode 27, Swift, Python 3.9+, and `hdiutil`. It installs
pinned `dmgbuild` dependencies in a temporary virtual environment and writes
Finder metadata without opening Finder. Artwork is rendered at 1× and 2× from
the same Puff geometry used by the app. Temporary build products are removed
on exit; the intentional release artifacts remain in `dist/releases/vVERSION`.

## Update behavior

Release builds offer **Check for Updates…** and **Automatically Check for
Updates** in the menu. Automatic checks start enabled; users can turn them off.
Downloads and installation use Sparkle's native prompts. Updates require signed
feeds and Ed25519-signed archives. Development builds never start the updater.
Container operations block new checks and postpone update relaunches until
they finish. Quitting or updating Ckit leaves the container service running.

The first release with Sparkle still requires a manual install for existing
users. After that, Ckit can replace and relaunch itself through Sparkle.

App signing remains ad hoc and releases are not notarized, matching the current
pipeline. Before wider distribution, configure Developer ID signing and
notarization (including Sparkle's embedded helpers); that requires your Apple
Developer certificate and notarization credentials. Ed25519 update signing is
separate from Apple's app signing.

The current ad hoc builds use `Config/AdHoc.entitlements` to disable library
validation: ad hoc signatures have no Apple Team ID, so hardened runtime would
otherwise reject Sparkle at launch. Remove this exception when the app and its
embedded framework are signed with the same Developer ID team.

## Verification and cleanup

`CheckAppBundle.sh` checks the actual app executable's runtime framework search
path, embedded Sparkle framework, and code signature before packaging. This
also runs before the updater fixture, which has its own executable.
It invokes `--check-launch` to verify that macOS actually loads the executable
and its frameworks, then exits before starting UI, containers, or the updater.
Packaging repeats this check on the app inside the finished DMG to catch any
metadata changes that could invalidate its signature.

`CheckUpdates.sh` uses a separate bundle identifier, disables automatic checks,
and never downloads or installs an update. It deletes its fixture on exit.
Core tests and the native-menu fixture do not alter real container machines.

After inspecting a local DMG, eject it and delete the test release directory.
Do not open the test app from the DMG or build folder, and do not copy it into
Applications when only checking artwork.
