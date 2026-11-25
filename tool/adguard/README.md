# Bundled AdGuard filtering

The Android app uses TSUrlFilter 6.1.0 in a dedicated Web Worker inside a
private, headless Android WebView. It shares the system's V8 engine without
exposing the filter worker to website scripts. The visible WebView stays the same.
One filter worker serves browser and search pages. All worker files and filters
come from the APK through Android WebViewAssetLoader at a private HTTPS origin;
external requests and navigation are denied in the filter host. Parsing, indexing
and matching run on the worker thread rather than Flutter's UI isolate.

The QuickJS approach was rejected after actual 32-bit TV testing: older versions
lack BigInt and the newer runtime used enough memory for Android to kill the app.
No additional native JavaScript runtime is now required. No browser extension,
VPN, remote scripts or HTTPS interception is installed.

## Build and verify

Node 22 and the project's pinned Flutter SDK:

```sh
npm --prefix tool/adguard ci --ignore-scripts
npm --prefix tool/adguard run check
npm --prefix tool/adguard test
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm,android-arm64,android-x64
```

`npm run build` in this directory regenerates the engine, page runtime,
redirect resources and license notices. Assets are committed and normal Flutter
builds need no npm or remote filter downloads. `npm run update-filters` fetches
Base (2), Tracking Protection (3), and Mobile Ads (11) at the Git revision in
`build.mjs`, converts them at build time, and records SHA-256 hashes. Use the
platform-specific **Chromium** lists: raw cross-platform sources contain
`$app` exceptions for unrelated native apps and unresolved preprocessor branches.
The three pinned lists contain 612,554 rules with no conversion errors.
Annoyances and Social filters are not enabled.

The Node suite runs the actual worker with all three bundled lists under a
192 MiB V8 old-generation limit. It also checks exceptions, redirects, scriptlets,
Extended CSS, owned selectors, repeated injection and stale iframe responses.
Actual Android loading and interception are checked on a 32-bit MiTV as well;
Node matching alone is not treated as evidence of a complete device integration.

## Ownership and compatibility

- Existing catalog/runtime templates remain responsible for clicks, native taps,
  ad skips, JW Player controls and `mvTap`. The Chrome extension is unchanged.
- AdGuard provides network matching, native CSS, Extended CSS and bundled
  scriptlets. Its click/dispatch automation scriptlets are excluded so they do
  not create a second click controller. No raw JavaScript filter rules are run.
- Exact cosmetic selectors owned by an enabled app rule are excluded from the
  AdGuard stylesheet. Identical CSS and scriptlet calls are deduplicated per
  document. Other selector overlap requires a tested compatibility exception;
  there is no blanket CDN or player allowlist.
- `assets/adguard/compatibility.json` is an array, initially empty. Each entry
  requires `siteId`, a lowercase DNS `host`, `networkExceptions` (only AdGuard
  `@@` rules), `disabledRules` (exact converted rule text), and
  `disabledScriptlets` (exact names). Host scope includes subdomains. Unknown
  fields, invalid hosts and blocking rules in `networkExceptions` are rejected.
  User switches run first, then these application exceptions, then normal
  upstream matching and exception precedence.
- Settings preserve `block_ads_enabled` as the master switch and keep existing
  app-rule switches independent. Per-site network/cosmetic/scriptlet overrides
  apply to the catalog page and its frames. Use the page's bookmark menu →
  **AdGuard และกฎเฉพาะเว็บ** → **โหลดหน้าใหม่** after editing. Recreating the
  WebView removes scriptlet effects; toggling a setting cannot undo them in place.

## WebView limitations and failure behavior

The engine is ready before a protected WebView loads. Initialization failure
allows the page and app-owned rules to continue, with an explicit unavailable
message. A matcher response taking longer than three seconds fails open; stale
navigation responses are discarded. No request URLs or cookies are logged.

Main documents remain governed by the existing catalog navigation policy, not
AdGuard document blocking. Android exposes no reliable resource-type/frame-ID
API in this callback: use Sec-Fetch-Dest when present and Other when missing,
never URL extensions. Referer identifies the source frame when available;
otherwise use the current top-level page. HTTP method is passed to the engine.
This limits type-specific rules and third-party classification when metadata
is missing. WebSocket, service worker and redirect-chain traffic is not fully
covered by WebView's request interception. Response-header, cookie, CSP,
HTML/body filtering and URL rewrites are not implemented.

Known initial main-frame rules run at document start. Newly navigated documents
and unknown cross-origin frames request their own rules through the existing
WebView bridge; scriptlets may arrive after the site's earliest scripts. Opaque
about:blank/srcdoc frames and live SPA path-specific cosmetic updates are not
covered. CSP may restrict inline CSS. Supported redirect responses come only
from the bundled resource table; parameterized redirect templates are excluded.

The full lists need transient memory during indexing; no low-memory-device
performance guarantee is made. The UI stays separate from the filter worker. Real website
playback, TV controls and cross-frame behavior still require device checks when
updating filters; never equate passing matcher tests with universal compatibility.

## Licenses and dependency review

All imported dependency license texts and the AdGuard filter license are bundled
under `assets/adguard/licenses/`. AdGuard components/filters include GPL-3.0
licenses: distributing a combined APK requires the corresponding source and
applicable notices. Keep the source, lockfiles, build scripts and exact filter
revision with distributions. This change does not publish a release.

The TSUrlFilter tree pins Zod 3. Upgrading it to Zod 4 breaks the upstream API.
`npm audit` reports GHSA-mrhx-c7xc-m3w5 (oversized collection validation) through
Zod and its dependents. Its configuration/filter-conversion inputs here are
reviewed, bundled build data; websites cannot supply filter lists or Zod schemas.
`js-yaml` is overridden to patched 3.15.2. Revisit the Zod advisory on the next
upstream engine update; do not apply npm's suggested downgrade to TSUrlFilter 1.
