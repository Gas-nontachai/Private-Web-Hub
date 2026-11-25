# Chrome AdGuard integration

Chrome 121+ only. This build uses `@adguard/tswebextension` 5.0.3 (MV3) and the
pinned `@adguard/dnr-rulesets` 5.0.20261013160024 snapshot. Chrome's native
Declarative Net Request engine blocks requests; AdGuard's content runtime applies
CSS, Extended CSS and bundled scriptlets. Base (2), Tracking Protection (3), and
Mobile Ads (11) are enabled, without Annoyances or Social filters. The popup's
rule count includes cosmetic/scriptlet rules, not just native network rules.

## Platform boundary

| Behavior | Chrome Extension | Android mobile / TV |
| --- | --- | --- |
| Network engine | Chrome native DNR + TsWebExtension | TSUrlFilter in private WebView Worker |
| Scope | All permitted HTTP/HTTPS sites | Pages opened inside the app |
| Settings | Extension popup; master and exact-host exception | App settings; request/CSS/scriptlet switches per catalog site |
| Skip controls | Existing MAIN-world JS / DOM clicks | Existing runtime and native `mvTap` bridge |
| Build | `tool/extension` → `extension/adguard` | `tool/adguard` → `assets/adguard` |

Chrome settings live in `chrome.storage.local.movieExtensionAdguard`; Android
preferences and APK assets are unaffected. Turning AdGuard off leaves Movie.exe's
existing hide/skip rules running. Reload after changing settings: a scriptlet's
side effects cannot reliably be undone in the existing document. Chrome's
allowlist covers the selected top-level host and its loaded frames; host matching
for cosmetic rules remains AdGuard's responsibility.

Generated compatibility exceptions suppress identical catalog CSS selectors and
AdGuard's `trusted-click-element` / `trusted-dispatch-event` scriptlets. Movie.exe
owns skip/click behavior. Other AdGuard rules may still affect players; this is
not a guarantee against every conflict. No broad CDN/video exemptions are added.

No runtime filter or JavaScript downloads, raw JavaScript filter rules, telemetry,
stealth mode or automatic cookie deletion are enabled. The official engine needs
`cookies`, `webRequest`, scripting/navigation and all-site permissions; this is
why Chrome shows broader permission prompts. Browser-internal pages and the
Chrome Web Store cannot be filtered. MV3 limits and preconverted rules mean the
Android and Chrome rule counts and supported syntax differ. The engine reports
initialization errors in the popup; static rulesets start disabled and are enabled
by successful initialization. Existing skip controls remain available on failure.

## Build and test

Node 22; npm dependencies and filter snapshot are pinned in `package-lock.json`.

```sh
npm --prefix tool/extension ci --ignore-scripts
npm --prefix tool/extension run build
npm --prefix tool/extension test
python3 tool/generate_shared.py --check
python3 -m unittest discover -s tool/tests -p 'test_*extension*.py'
python3 -m tool.release.package_extension_zip extension v1.1.4 dist/Movie.exe-AdGuard-preview.zip
```

Extract the ZIP and use **chrome://extensions → Developer mode → Load unpacked**.
Replace/disable the older Movie.exe copy to avoid duplicate skip observers.
For the real Chromium smoke test, set `CHROMIUM_PATH` to a Chrome for Testing
executable and run `node tool/extension/browser-test.mjs`. It uses a fresh profile
and local fixture server to verify real network blocking, cosmetics, scriptlets,
site exceptions, master off and independence of existing CSS/skip controls.
This does not validate playback on every live catalog site.

`extension/adguard/build-info.json` records selected filter hashes. Dependency
license notices are bundled under `extension/adguard/licenses/`; AdGuard packages
include GPL-3.0 licenses. Preserve notices and provide corresponding source when
distributing a derivative. This preview ZIP is not a Chrome Web Store release.

Dependency audit currently reports upstream high-severity advisories through
Zod's schema parsing. These parsers receive bundled configuration/filter metadata;
website messages are restricted by sender ID and setting mutations by popup URL.
Do not expose the engine's configuration API to webpage bridges. Upgrading the
engine requires checking its converter metadata format against this snapshot;
6.x is not compatible with the pinned 5.x ruleset format.
