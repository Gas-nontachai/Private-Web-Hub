import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movieapps/src/core/ad_blocking.dart';
import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('blocks exact ad hosts and subdomains, not lookalikes or URL text', () {
    for (final domain in blockedAdHosts) {
      expect(isBlockedAdUri(Uri.parse('https://$domain/ad.js')), true);
      expect(isBlockedAdUri(Uri.parse('http://ads.$domain:8080/ad.js')), true);
      expect(isBlockedAdUri(Uri.parse('https://not$domain/ad.js')), false);
      expect(isBlockedAdUri(Uri.parse('https://$domain.example/ad.js')), false);
      expect(
        isBlockedAdUri(Uri.parse('https://example.com/?ad=$domain')),
        false,
      );
    }
    expect(isBlockedAdUri(Uri.parse('file://doubleclick.net/ad.js')), false);
    expect(
      isBlockedAdUri(
        Uri.parse('https://doubleclick.net@cdn.example/video.m3u8'),
      ),
      false,
    );
  });
  test('allows catalog sites and shared media CDNs', () {
    final catalog = Catalog.parse(
      File('assets/catalog/websites.json').readAsStringSync(),
    );
    for (final site in catalog.sites) {
      expect(isBlockedAdUri(site.url), false);
    }
    for (final host in [
      'cdn.jwplayer.com',
      'cdn.jsdelivr.net',
      'video.example',
      'cloudfront.net',
    ]) {
      expect(isBlockedAdUri(Uri.https(host, '/video.m3u8')), false);
    }
  });
  test(
    'network blocking toggle persists independently from skip rules',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SiteSettings.load();
      expect(settings.blockAdsEnabled, true);
      await settings.setBlockAdsEnabled(false);
      expect((await SiteSettings.load()).blockAdsEnabled, false);
      expect(settings.globalEnabled, true);
    },
  );
}
