# Movie.exe

Android app that opens allowlisted sites (SerieDay, 037HDD, GoSeries4K) in a WebView and applies the
same declarative ad-hiding rules as the bundled [Chrome extension](extension/).

- Catalog + rules: `assets/catalog/websites.json` (schema v1; `hide`, `clickWhenVisible` and `tapWhenVisible` actions, host-scoped).
- Runtime: `assets/runtime/rule_runtime.js` (bundled, idempotent; no remote code execution).
- Generate shared assets: `python3 tool/generate_shared.py`; verify them: `python3 tool/generate_shared.py --check`
- Settings: per-site rule toggles, clear browsing data, rule version.
- Search: Explore opens configured site search pages in parallel WebViews. Each tab shows its own load state and keeps the existing host rules. Site search URL patterns live in the optional `search` catalog field; adding one requires a same-site path and query key.

Search currently displays each website's own results page in a source tab. It does not extract and merge poster/title cards into a native result list.

## Project structure

```text
lib/
  main.dart                  App startup
  src/
    core/                    Catalog, local settings/history, update checks
    pages/                   Home, browser, history and settings screens
    theme/                   Theme and generated design constants
assets/
  catalog/                   Site and rule source JSON
  design/                    Shared design tokens
  fonts/                     Original fonts and license
  icon/                      App icon sources
  runtime/                   Generated WebView JavaScript
extension/                   Load-unpacked Chrome extension (including generated assets)
test/
  core/                      Catalog, settings and update tests
  pages/                     Screen tests
tool/
  generate_shared.py         Shared asset generation/check entrypoint
  android/                   CI NDK installation with targeted download retries
  gradle/                    Shared Kotlin mirror config and CI init script
  release/                   APK/ZIP validation and release metadata/notes
  templates/runtime/         JavaScript source templates and shared visibility logic
  tests/                     Python and JavaScript tooling tests
.github/
  actions/validate/          Shared toolchain setup and validation
  workflows/                 CI and release entrypoints
android/                     Native Android host and Gradle project
```

Run tooling from the repository root. Release helpers use Python module commands
(`python3 -m tool.release.<module>`) so imports work consistently in scripts and tests.
Keep platform directories in their standard locations; generated runtime assets
stay beside the platform that consumes them. Edit their source JSON/templates,
then run the generator instead of editing generated files directly.

## In-app Android updates

Home checks GitHub Releases outside debug builds; Settings also offers a manual check.
Updates download inside the app with percentage/byte progress, Cancel and Retry.
TV devices select the TV APK. When complete, the app opens Android's installer.
On Android 8+, allow installs from this app when prompted, then return and press
Install. Android still requires installation confirmation and verifies the APK's
signature. Downloads use app cache; incomplete downloads are removed. Closing the
dialog cancels an active download; downloads do not resume after an app restart.

## Release

The existing [release workflow](.github/workflows/release.yml) builds and publishes
**Movie.exe vX.Y.Z** to GitHub Releases in `Gas-nontachai/Private-Web-Hub`, with exactly three uploaded assets:

```text
Movie.exe-v1.0.1.apk
Movie.exe-TV-v1.0.1.apk
Movie.exe-v1.0.1.zip
```

No split APKs, extension CRX files, checksum files, private keys or keystores are
uploaded. GitHub's automatically generated source archives are platform-provided
links, not uploaded release assets. Nothing is published to Google Play or the
Chrome Web Store.

Release notes are generated from [.github/release-template.md](.github/release-template.md)
by [tool/release/generate_release_notes.py](tool/release/generate_release_notes.py). Preview notes
without building the app:

```sh
python3 -m tool.release.generate_release_notes v1.0.0 --output release-notes.md
```

To update notes for an existing release without rebuilding or changing its assets:

```sh
gh release edit v1.0.0 --notes-file release-notes.md
```

Commit and push the pipeline changes first, then push a new tag:

```sh
git tag v1.0.1
git push origin v1.0.1
```

Alternatively, run **Release** using `workflow_dispatch` and supply an **existing**
`vX.Y.Z` tag. Both builds use the commit referenced by that tag, not the current
branch. Tags must have three decimal components, no leading zeros, prerelease
suffixes or build metadata. To fit Chrome's manifest requirements, each component
must be at most 65535 and the version cannot be all zero. For example, `v1.0.1`
becomes extension manifest version `1.0.1`, Android versionName `1.0.1`, and
Android versionCode `1000001`. Both are generated from the Git tag during the
build; you do not need to edit the versions in [pubspec.yaml](pubspec.yaml) or
[extension/manifest.json](extension/manifest.json). Android versionCode is calculated
as MAJOR * 1,000,000 + MINOR * 1,000 + PATCH. This requires MINOR and PATCH <= 999
and a calculated versionCode <= 2,100,000,000. Release tags should increase
monotonically so Android can install updates over older versions.

### Signing secrets

Configure these GitHub Actions secrets before releasing:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the **existing** Android release keystore |
| `ANDROID_STORE_PASSWORD` | Existing keystore password |
| `ANDROID_KEY_ALIAS` | Existing release alias |
| `ANDROID_KEY_PASSWORD` | Existing key password |

Keep using the same Android keystore on every release. The workflow
never generates a release signing key and fails if Android signing secrets are missing or invalid.
Do not commit signing files or passwords, and do not paste them into logs.
Chrome extension releases are distributed as source ZIP archives for Developer Mode
Load unpacked and do not require a Chrome private signing key.

### Build and validation

- Android uses the existing stable-channel Flutter setup and Gradle signing
  configuration. `flutter build apk --release --build-name=X.Y.Z --build-number=N` produces one
  universal APK with `armeabi-v7a`, `arm64-v8a` and `x86_64`. A second build with
  `--target-platform android-arm,android-arm64` produces the TV APK, retaining
  32-bit ARM support for devices such as MiTV-MOSR4. Both APKs use the same
  application ID, version and release certificate, and detect TV mode at runtime.
  Install one APK per device. The workflow verifies
  both signatures with `apksigner`, compares the certificate to the configured
  keystore alias, and checks the display name, application ID and version.
- The Chrome extension is packaged directly from the bundled [extension](extension/)
  directory in this repository, at the tagged commit. No secondary repository or
  cross-repository token is needed. Only its packaged manifest name and version
  are updated; runtime files and host rules remain unchanged.
  [The ZIP packaging helper](tool/release/package_extension_zip.py) validates manifest resources,
  excludes signing material and places manifest.json at the ZIP root.
  Download the ZIP, extract it, enable Developer Mode at chrome://extensions,
  then choose Load unpacked and select the extracted folder.
- Both Android APK builds and the extension ZIP must succeed before release creation. The release
  job has `contents: write`. Both uploaded asset names are checked locally before
  publication. Existing releases are never overwritten. Inspect any partial release
  after a failed upload before deliberately removing it and rerunning.

Direct installation of a non-store CRX can be disabled by Chrome. ZIP plus Load unpacked
is the supported local-development workflow instead. Test the APK on Android and
load the extracted ZIP on Chrome before relying on either build.

Local validation:

```sh
flutter analyze
flutter test
python3 -m unittest discover -s tool/tests -p 'test_*extension*.py'
```

Note: Android Gradle Plugin is pinned to 8.11.1 because `flutter_inappwebview_android` 1.1.3 does not
build with AGP 9.

Both CI and Release use `.github/actions/validate` to pin Java 17, Python 3.12,
Node 22 and Flutter 3.47.6, verify generated files, and run the Python, JavaScript
and Flutter checks before building. Dependency downloads can still fail when a
mirror or upstream service is unavailable; rerun after service recovery.

CI and Release explicitly install the NDK version declared by the pinned Flutter
SDK before Gradle runs. `tool/android/install_ndk.py` skips a complete existing
installation. Archive corruption and recognized network errors trigger up to three
install attempts with 15/30-second delays, clearing SDK download staging and only
the failed version's partial NDK directory before retrying. Other errors (such as
licenses or permissions) fail immediately. A repeated upstream failure still fails
the job; inspect the dedicated NDK step's verbose log before rerunning. No NDK
version override or alternate download mirror is introduced.

Kotlin repository settings share `tool/gradle/kotlin-mirror.properties`. CI installs
`tool/gradle/ci-kotlin-mirror.init.gradle` in Gradle's init directory and sets
`MOVIE_KOTLIN_MIRROR_CONFIG` to that properties file so Flutter's included Gradle
build uses the same mirror. Local Android builds read the same properties directly.
The wrapper distribution URL and SHA-256 remain pinned separately.

## Shared sources

Edit these sources, then run `python3 tool/generate_shared.py` and commit its outputs:

- `assets/catalog/websites.json`: site names, links, marks, host matches and hide selectors.
- `assets/design/design_tokens.json`: shared colors, font declarations and UI dimensions.
- `assets/fonts/`: original font binaries and OFL license; extension copies are generated.
- `tool/templates/runtime/`: platform JavaScript templates and the shared visibility function.

Generated files stay committed so Flutter and Chrome's Load unpacked work directly
from a checkout. The generator writes only changed files. Its `--check` mode never
writes and fails on missing or stale outputs, including font byte differences.
The manifest's icons, metadata and source version stay hand-edited; its
`content_scripts` list is generated. The pubspec font section and adaptive icon
background are generated; dependencies and app version stay hand-edited.

Site CSS currently represents hide rules with the same hosts as their site.
Unsupported site actions or narrower rule host scopes fail generation instead of
silently broadening where a rule runs. Global skip-button behavior stays separate:
Android uses native taps; Chrome uses synthetic clicks and tracks visibility resets.
Flutter and CSS keep their platform-specific layout, using generated constants and
CSS variables for shared values. No runtime fetch of shared config is required.

CRX signing/packaging is removed. APK plus extension ZIP are the supported outputs.
The release workflow creates a public release after all three artifacts are validated;
it refuses to overwrite an existing release. The earlier draft-release and download
retry descriptions do not apply to the current workflow.

Complete local checks (Python 3.12 recommended):

```sh
python3 tool/generate_shared.py --check
python3 -m unittest discover -s tool/tests -p 'test_*.py'
node --test tool/tests/test_visibility.cjs
flutter analyze
flutter test
flutter build apk --debug
```

## Android TV and phone remote

The same app supports Android phones and Android TV / Google TV. TV mode is
detected from Android device features, not the screen width. Install the TV APK
from Releases for ARM TVs; the universal APK also supports x86_64.

1. Open Movie.exe on TV. Select the phone icon (**จับคู่มือถือ**) to display a
   six-digit pairing code (valid for two minutes), local address and identity number.
2. On an Android phone on the same Wi-Fi, select **เชื่อมต่อ TV**. Pick the TV
   or enter its IP address (port 47831). Choose pairing when prompted.
3. Compare the identity number on both screens, enter the six-digit code, and
   approve on TV only if the identity numbers match. Pairing replaces the previous
   controller; TV can revoke it from the same page.
4. Open a supported page on the phone and select **เปิดบน TV**. TV loads the URL
   itself, with its own cookies and website storage. After TV accepts the URL, the
   source WebView on the phone is disposed to stop playback in all frames. The phone
   becomes a remote; use the touchpad to move the TV cursor and tap to click.
   Returning to the phone page shows a receipt and an explicit button to reopen it
   locally. Failed handoffs keep the original phone page running.

The TV remote works independently: arrows move the cursor inside web pages, OK
clicks, Menu switches between cursor and app focus, and Channel/Page Up/Down scroll.
The cursor hides after three seconds of inactivity and reappears on movement or click.
The browser toolbar also provides cursor switching and scrolling. Back exits
fullscreen first, then follows web history and returns to the app. The phone has
the same navigation, click, scroll and cursor controls.

Open the TV app before connecting. Leaving the app closes the receiver; losing
the phone connection does not stop playback. Reconnect explicitly after a network
change; commands are not replayed. Discovery can be blocked by guest Wi-Fi or AP
isolation; IP entry cannot bypass network isolation. Local-network permission
is requested when required by the OS and target SDK.

Pairing uses TLS with a TV certificate held in Android Keystore. Compare the
identity numbers during the first pairing; subsequent connections pin that
certificate. Pairing credentials are encrypted using a Keystore key and excluded
from backups. No accounts, cloud service, casting, remote JavaScript, cookie
transfer or playback-position sync are included.

`flutter build apk --debug` creates **Movie.exe TV Preview** with application ID
`com.nonthachai.privatewebhub.tvpreview`, which installs alongside the release app
and keeps separate settings. CI uploads this preview APK as a downloadable artifact.
Release APKs retain the original application ID and signing configuration.

### Ad blocking and skip controls

The Android app blocks resource requests to a small bundled set of known ad-network
hosts before loading them. This is not the AdBlock extension or a full EasyList
engine. **Settings → บล็อกการโหลดโฆษณา** controls this independently from automatic
skipping; reopen the page after changing it. Main documents, catalog sites and
normal media CDNs are not blocked by these host rules.

The Chrome extension has a separate MV3 AdGuard integration using native DNR
and TsWebExtension, with Base, Tracking Protection and Mobile Ads applied globally
to permitted HTTP/HTTPS pages. Its popup controls the master switch and a per-host
exception. Existing Movie.exe hide/skip rules stay independent. Chrome settings,
engine builds and assets are separate from Android; see
[Chrome build, installation and limitations](tool/extension/README.md).

Skip targets include the original ad-gate button and ready JW Player skip controls.
Exact Thai/English skip labels are considered only inside active ad-player
containers. Chrome runs the reviewed skip script in the page's MAIN world so it
can use JW Player's public `skipAd()` API; other controls retain DOM clicks. The
WebView runtime instead requests native touchscreen events, validates visible
viewport coordinates, and relays acknowledgements through scaled iframe borders.
Off-screen or unavailable bridge attempts do not consume the retry budget; each
new visible ad resets it. Changes belong in the catalog and runtime templates;
run `python3 tool/generate_shared.py` to update both platform outputs.
