import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'history deduplicates URLs, caps at 500, and skips corrupt entries',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SiteSettings.load();
      final site = Catalog.parse(
        '''{"schemaVersion":1,"version":"1","sites":[{"id":"demo","name":"Demo","mark":"D","url":"https://example.com","hosts":["example.com"],"rules":[]}]}''',
      ).sites.single;
      await settings.browsing.recordVisit(
        site,
        Uri.parse('https://example.com/page'),
        'First',
      );
      await settings.browsing.recordVisit(
        site,
        Uri.parse('https://example.com/page'),
        'Updated',
      );
      expect(settings.browsing.history, hasLength(1));
      expect(settings.browsing.history.first.title, 'Updated');
      for (var i = 0; i < 505; i++) {
        await settings.browsing.recordVisit(
          site,
          Uri.parse('https://example.com/$i'),
          '$i',
        );
      }
      expect(settings.browsing.history, hasLength(500));
      await settings.browsing.clearHistory();
      expect(settings.browsing.history, isEmpty);
    },
  );

  test('one malformed history item does not hide valid entries', () async {
    SharedPreferences.setMockInitialValues({
      'browse_history': '[{"siteId":"x","url":"https://example.com","title":"ok","visitedAt":"2026-01-01T00:00:00.000"},{"bad":true}]',
    });
    expect((await SiteSettings.load()).browsing.history, hasLength(1));
  });

  test('saved pages toggle idempotently by normalized source URL and survive history clear', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SiteSettings.load();
    final site = Catalog.parse(
      '''{"schemaVersion":1,"version":"1","sites":[{"id":"demo","name":"Demo","mark":"D","url":"https://example.com","hosts":["example.com"],"rules":[]}]}''',
    ).sites.single;
    await settings.browsing.toggleSavedPage(
      site,
      Uri.parse('HTTPS://EXAMPLE.COM/page#one'),
      'Page',
      'favorite',
      posterUrl: 'https://images.example/poster.jpg',
    );
    expect(
      settings.browsing.savedPages('favorite').single.posterUrl,
      'https://images.example/poster.jpg',
    );
    await settings.browsing.toggleSavedPage(
      site,
      Uri.parse('https://example.com/page#two'),
      'Page',
      'watchLater',
    );
    await settings.browsing.toggleSavedPage(
      site,
      Uri.parse('https://example.com/page#three'),
      'Page',
      'favorite',
    );
    expect(settings.browsing.savedPages('favorite'), isEmpty);
    expect(settings.browsing.savedPages('watchLater'), hasLength(1));
    await settings.browsing.clearHistory();
    expect(settings.browsing.savedPages('watchLater'), hasLength(1));
  });
  test('existing saved pages and history keep their storage keys across reload and removal', () async {
    final saved = {
      'siteId': 'demo',
      'url': 'https://example.com/page',
      'identityUrl': 'https://example.com/page',
      'title': 'Saved',
      'savedAt': '2026-01-01T00:00:00.000',
    };
    SharedPreferences.setMockInitialValues({
      'saved_pages': jsonEncode([
        {...saved, 'collection': 'favorite'},
        {...saved, 'collection': 'watchLater'},
      ]),
      'browse_history': jsonEncode([
        {
          'siteId': 'demo',
          'url': saved['url'],
          'title': 'Visited',
          'visitedAt': saved['savedAt'],
        },
      ]),
    });
    final data = (await SiteSettings.load()).browsing;
    await data.removeSavedPage(data.savedPages('favorite').single);
    final restored = (await SiteSettings.load()).browsing;
    expect(restored.savedPages('favorite'), isEmpty);
    expect(restored.savedPages('watchLater').single.title, 'Saved');
    expect(restored.history.single.title, 'Visited');
    await restored.removeVisit(restored.history.single);
    expect((await SiteSettings.load()).browsing.history, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), {
      'saved_pages',
      'browse_history',
    });
  });
}
