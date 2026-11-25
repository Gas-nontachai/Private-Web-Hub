import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:movieapps/src/core/ad_blocking.dart';
import 'package:movieapps/src/core/browser_protection.dart';
import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Engine extends AdGuardEngine {
  bool ready = true;
  int starts = 0;
  final requests = <Map<String, Object?>>[];
  final pages = <Map<String, Object?>>[];
  Future<Map<String, dynamic>?> result = Future.value({'block': true});

  @override
  Future<bool> ensureReady() async {
    starts++;
    return ready;
  }

  @override
  Future<Map<String, dynamic>?> evaluateRequest(Map<String, Object?> context) {
    requests.add(context);
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getPageRules(
    Map<String, Object?> context,
  ) async {
    pages.add(context);
    return {
      'css': ['.advert'],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BrowserProtection protection;
  late SiteSettings settings;
  late _Engine engine;
  final catalog = Catalog.parse(
    File('assets/catalog/websites.json').readAsStringSync(),
  );
  final site = catalog.sites.first;
  final request = WebResourceRequest(
    url: WebUri('https://ads.example/ad.js'),
    method: 'GET',
    headers: {
      'Referer': 'https://frame.example/player',
      'Sec-Fetch-Dest': 'script',
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SiteSettings.load();
    engine = _Engine();
    protection = BrowserProtection(
      catalog: catalog,
      site: site,
      settings: settings,
      engine: engine,
    );
  });

  test('page rules reject unsafe URLs and preserve frame context', () async {
    expect(await protection.pageRules('file:///secret', null), isNull);
    expect(
      await protection.pageRules('https://example.com/${'a' * 16384}', null),
      isNull,
    );
    expect(engine.pages, isEmpty);
    await protection.pageRules(
      'https://frame.example/player',
      'file:///secret',
    );
    expect(
      engine.pages.single,
      containsPair('sourceUrl', 'https://frame.example/player'),
    );
    expect(engine.pages.single, containsPair('host', 'frame.example'));
    await protection.pageRules(
      'https://frame.example/player',
      site.url.toString(),
    );
    expect(engine.pages.last, containsPair('sourceUrl', site.url.toString()));
  });

  test(
    'network settings and main-frame exclusions bypass the engine',
    () async {
      await settings.setBlockAdsEnabled(false);
      expect(
        await protection.interceptRequest(request, null, isCurrent: () => true),
        isNull,
      );
      await settings.setBlockAdsEnabled(true);
      await settings.setAdGuardEnabled(site.id, 'network', false);
      expect(
        await protection.interceptRequest(request, null, isCurrent: () => true),
        isNull,
      );
      await settings.setAdGuardEnabled(site.id, 'network', true);
      expect(
        await protection.interceptRequest(
          WebResourceRequest(url: request.url, isForMainFrame: true),
          null,
          isCurrent: () => true,
        ),
        isNull,
      );
      expect(engine.requests, isEmpty);
    },
  );

  test(
    'blocking preserves referrer, resource metadata and redirect bytes',
    () async {
      var response = await protection.interceptRequest(
        request,
        site.url,
        isCurrent: () => true,
      );
      expect(response?.statusCode, 204);
      expect(
        engine.requests.single,
        containsPair('sourceUrl', 'https://frame.example/player'),
      );
      expect(engine.requests.single, containsPair('host', 'frame.example'));
      expect(engine.requests.single, containsPair('type', 'Script'));
      expect(engine.requests.single, containsPair('method', 'GET'));
      engine.redirects['noop'] = {
        'contentType': 'image/png;base64',
        'content': base64Encode([1, 2, 3]),
      };
      engine.result = Future.value({'block': true, 'redirect': 'noop'});
      response = await protection.interceptRequest(
        request,
        site.url,
        isCurrent: () => true,
      );
      expect(response?.statusCode, 200);
      expect(response?.contentType, 'image/png');
      expect(response?.data, [1, 2, 3]);
    },
  );

  test('a response from a previous navigation is discarded', () async {
    final pending = Completer<Map<String, dynamic>?>();
    engine.result = pending.future;
    var current = true;
    final response = protection.interceptRequest(
      request,
      site.url,
      isCurrent: () => current,
    );
    current = false;
    pending.complete({'block': true});
    expect(await response, isNull);
  });

  test('site rules survive disabled or unavailable AdGuard', () async {
    await settings.setBlockAdsEnabled(false);
    var scripts = await protection.prepareScripts(site.url);
    expect(scripts.adguard, isNull);
    expect(scripts.rules.source, contains(site.rules.first.id));
    expect(engine.starts, 0);
    await settings.setBlockAdsEnabled(true);
    engine.ready = false;
    scripts = await protection.prepareScripts(site.url);
    expect(scripts.adguard, isNull);
    expect(scripts.rules.source, contains(site.rules.first.id));
  });

  test(
    'script configuration respects site toggles and tracks changes',
    () async {
      final before = protection.settingsSnapshot;
      await settings.setAdGuardEnabled(site.id, 'cosmetic', false);
      expect(protection.settingsSnapshot, isNot(before));
      final scripts = await protection.prepareScripts(site.url);
      expect(scripts.adguard?.source, contains('"cosmetic":false'));
      expect(scripts.adguard?.source, contains('"scriptlets":true'));
      expect(scripts.adguard?.source, isNot(contains('__MV_ADGUARD_CONFIG__')));
      expect(scripts.adguard?.forMainFrameOnly, false);
      expect(scripts.rules.forMainFrameOnly, false);
    },
  );
}
