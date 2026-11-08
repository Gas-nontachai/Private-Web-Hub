# Movie.exe

Android app that opens allowlisted sites (SerieDay, 037HDD, GoSeries4K) in a WebView and applies the
same declarative ad-hiding rules as the bundled [Chrome extension](extension/).

- Catalog + rules: `assets/catalog/websites.json` (schema v1; `hide`, `clickWhenVisible` and `tapWhenVisible` actions, host-scoped).
- Runtime: `assets/runtime/rule_runtime.js` (bundled, idempotent; no remote code execution).
- Generate shared assets: `python3 tool/generate_shared.py`; verify them: `python3 tool/generate_shared.py --check`
- Settings: per-site rule toggles, clear browsing data, rule version.

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

## Release

The existing [release workflow](.github/workflows/release.yml) builds and publishes
**Movie.exe vX.Y.Z** to GitHub Releases in `Gas-nontachai/Private-Web-Hub`, with exactly two uploaded assets:

```text
Movie.exe-v1.0.1.apk
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
  universal APK with `armeabi-v7a`, `arm64-v8a` and `x86_64`. The workflow verifies
  its signature with `apksigner`, compares the certificate to the configured
  keystore alias, and checks the display name, application ID and version.
- The Chrome extension is packaged directly from the bundled [extension](extension/)
  directory in this repository, at the tagged commit. No secondary repository or
  cross-repository token is needed. Only its packaged manifest name and version
  are updated; runtime files and host rules remain unchanged.
  [The ZIP packaging helper](tool/release/package_extension_zip.py) validates manifest resources,
  excludes signing material and places manifest.json at the ZIP root.
  Download the ZIP, extract it, enable Developer Mode at chrome://extensions,
  then choose Load unpacked and select the extracted folder.
- APK and extension ZIP builds must both succeed before release creation. The release
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
The release workflow creates a public release after both artifacts are validated;
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
