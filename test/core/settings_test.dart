import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('favicon is stored per site and can be read back', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SiteSettings.load();
    final icon = Uint8List.fromList([1, 2, 3, 4]);
    await settings.saveFavicon('demo', icon);
    expect(settings.favicon('demo'), icon);
    expect(settings.favicon('other'), isNull);
  });

  test(
    'history deduplicates URLs, caps at 500, and skips corrupt entries',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SiteSettings.load();
      final site = Catalog.parse(
        '''{"schemaVersion":1,"version":"1","sites":[{"id":"demo","name":"Demo","mark":"D","url":"https://example.com","hosts":["example.com"],"rules":[]}]}''',
      ).sites.single;
      await settings.recordVisit(
        site,
        Uri.parse('https://example.com/page'),
        'First',
      );
      await settings.recordVisit(
        site,
        Uri.parse('https://example.com/page'),
        'Updated',
      );
      expect(settings.history, hasLength(1));
      expect(settings.history.first.title, 'Updated');
      for (var i = 0; i < 505; i++) {
        await settings.recordVisit(
          site,
          Uri.parse('https://example.com/$i'),
          '$i',
        );
      }
      expect(settings.history, hasLength(500));
      await settings.clearHistory();
      expect(settings.history, isEmpty);
    },
  );

  test('one malformed history item does not hide valid entries', () async {
    SharedPreferences.setMockInitialValues({
      'browse_history': '[{"siteId":"x","url":"https://example.com","title":"ok","visitedAt":"2026-01-01T00:00:00.000"},{"bad":true}]',
    });
    expect((await SiteSettings.load()).history, hasLength(1));
  });

  test('saved pages toggle idempotently by normalized source URL and survive history clear', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SiteSettings.load();
    final site = Catalog.parse(
      '''{"schemaVersion":1,"version":"1","sites":[{"id":"demo","name":"Demo","mark":"D","url":"https://example.com","hosts":["example.com"],"rules":[]}]}''',
    ).sites.single;
    await settings.toggleSavedPage(
      site,
      Uri.parse('HTTPS://EXAMPLE.COM/page#one'),
      'Page',
      'favorite',
      posterUrl: 'https://images.example/poster.jpg',
    );
    expect(
      settings.savedPages('favorite').single.posterUrl,
      'https://images.example/poster.jpg',
    );
    await settings.toggleSavedPage(
      site,
      Uri.parse('https://example.com/page#two'),
      'Page',
      'watchLater',
    );
    await settings.toggleSavedPage(
      site,
      Uri.parse('https://example.com/page#three'),
      'Page',
      'favorite',
    );
    expect(settings.savedPages('favorite'), isEmpty);
    expect(settings.savedPages('watchLater'), hasLength(1));
    await settings.clearHistory();
    expect(settings.savedPages('watchLater'), hasLength(1));
  });
}
