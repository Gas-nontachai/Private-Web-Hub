# Movie.exe

Android app that opens allowlisted sites (SerieDay, 037HDD, GoSeries4K) in a WebView and applies the
same declarative ad-hiding rules as the bundled [Chrome extension](extension/).

- Catalog + rules: `assets/websites.json` (schema v1; only `hide` and `clickWhenVisible` actions, host-scoped).
- Runtime: `assets/rule_runtime.js` (bundled, idempotent; no remote code execution).
- Check drift against the bundled extension: `tool/sync_from_extension.sh extension`
- Settings: per-site rule toggles, clear browsing data, rule version.

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
  [The ZIP packaging helper](tool/package_extension_zip.py) validates manifest resources,
  excludes signing material and places manifest.json at the ZIP root.
  Download the ZIP, extract it, enable Developer Mode at chrome://extensions,
  then choose Load unpacked and select the extracted folder.
- APK and extension ZIP builds must both succeed before release creation. Only the publish
  job has `contents: write`. Releases are created as drafts, both uploaded asset
  names are checked, and only then is the release published. Existing releases
  are never overwritten. If upload or final validation fails, inspect the leftover
  draft and deliberately remove it before rerunning; the workflow refuses to
  replace it automatically.

Direct installation of a non-store CRX can be disabled by Chrome. ZIP plus Load unpacked
is the supported local-development workflow instead. Test the APK on Android and
load the extracted ZIP on Chrome before relying on either build.

Local validation:

```sh
flutter analyze
flutter test
python3 -m unittest discover -s tool -p 'test_*extension*.py'
```

Note: Android Gradle Plugin is pinned to 8.11.1 because `flutter_inappwebview_android` 1.1.3 does not
build with AGP 9.

The release workflow caches Gradle dependencies and fetches the smaller Gradle binary distribution
from a verified alternate distribution mirror after GitHub-hosted Gradle downloads returned HTTP 504.
The wrapper verifies the downloaded ZIP against the official SHA-256 checksum.
Wrapper download attempts use a delay between retries.
The workflow also retries APK builds up to three times when Flutter reports a Gradle network
artifact-download failure, waiting 15 then 30 seconds between attempts. Other build errors fail
immediately. If all attempts fail with HTTP 504, rerun the failed job once the upstream download
service recovers.

Kotlin compiler dependencies are resolved from the Alibaba Cloud Maven mirror
first, because Maven Central's redirects to GitHub releases returned HTTP 504
in CI. In addition to the Android project repositories, GitHub Actions installs
[the CI-only Gradle init script](tool/ci-kotlin-mirror.init.gradle) under
`GRADLE_USER_HOME/init.d/` before the build. This configures Kotlin repositories
for Flutter's separately configured included Gradle build (`:gradle:compileKotlin`)
as well as the Android app. It is not installed for local builds. Other dependency
groups still use Google Maven and Maven Central. Gradle, Kotlin and AGP versions
remain unchanged. A mirror outage can still fail the build; inspect the URL in
the Gradle error before changing toolchain versions.
