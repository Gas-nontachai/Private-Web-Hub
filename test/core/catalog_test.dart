import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movieapps/src/core/catalog.dart';

void main() {
  final source = File('assets/catalog/websites.json').readAsStringSync();

  test('bundled catalog has the configured sites once', () {
    final c = Catalog.parse(source);
    expect(c.sites.map((s) => s.name), [
      'SerieDay', '037HDD', 'GoSeries4K', 'AnimeRuka',
    ]);
    expect(c.sites.map((s) => s.id).toSet().length, c.sites.length);
    expect(c.sites.every((s) => s.url.scheme == 'https'), isTrue);
  });

  test('AnimeRuka search URL encodes Thai text and spaces', () {
    final c = Catalog.parse(source);
    final site = c.sites.singleWhere((s) => s.id == 'animeruka');
    expect(site.url.toString(), 'https://animeruka.com/');
    expect(
      buildSearchUri(site, 'รักนะ 2026').toString(),
      'https://animeruka.com/?s=%E0%B8%A3%E0%B8%B1%E0%B8%81%E0%B8%99%E0%B8%B0%202026',
    );
    expect(
      site.rules.single.actions.single.selectors,
      [
        '#box-side-r', '#box-side-l', '[id^="ad-group-"]',
        '#box-footer-fix', '.ar-adgrid',
      ],
    );
  });

  test(
    'rejects http urls, unknown actions and out-of-allowlist rule hosts',
    () {
      expect(
        () => Catalog.parse(
          source.replaceFirst(
            'https://www.serieday-z.com/',
            'http://www.serieday-z.com/',
          ),
        ),
        throwsA(isA<CatalogException>()),
      );
      expect(
        () => Catalog.parse(source.replaceFirst('"hide"', '"eval"')),
        throwsA(isA<CatalogException>()),
      );
      final json = jsonDecode(source) as Map<String, dynamic>;
      json['sites'][0]['rules'][0]['hosts'] = ['evil.example'];
      expect(
        () => Catalog.parse(jsonEncode(json)),
        throwsA(isA<CatalogException>()),
      );
    },
  );

  test('navigation policy keeps allowlisted https in-app only', () {
    final c = Catalog.parse(source);
    NavDecision d(String u) => decideNavigation(Uri.parse(u), c);
    expect(d('https://www.037-hdd.com/x'), NavDecision.allowInApp);
    expect(d('http://www.037-hdd.com/x'), NavDecision.openExternal);
    expect(d('https://ads.example/'), NavDecision.openExternal);
    expect(d('intent://foo'), NavDecision.openExternal);
  });

  test('rule script only includes enabled sites', () {
    final c = Catalog.parse(source);
    final s = buildRuleScript(
      'R=__RULES__;',
      c.sites,
      (s) => s.id == 'goseries4k',
    );
    expect(s, contains('goseries4k-hide-ads'));
    final real = buildRuleScript(
      File('assets/runtime/rule_runtime.js').readAsStringSync(),
      c.sites,
      (_) => true,
    );
    expect(real, isNot(contains('__RULES__')));
    expect(c.globalRules.single.hosts, ['*']);
    final g = buildRuleScript(
      'R=__RULES__;',
      c.sites,
      (_) => false,
      globalRules: c.globalRules,
    );
    expect(g, contains('global-adgate-skip'));
    expect(s, isNot(contains('serieday-hide-ads')));
  });
}
