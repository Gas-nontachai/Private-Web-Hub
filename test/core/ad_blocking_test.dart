import 'package:flutter_test/flutter_test.dart';
import 'package:movieapps/src/core/ad_blocking.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('resource types use metadata and never guess from URL suffixes', () {
    expect(adGuardResourceType(null), 'Other');
    expect(adGuardResourceType({'sec-fetch-dest': 'empty'}), 'Other');
    expect(
      adGuardResourceType({
        'sec-fetch-dest': 'empty',
        'X-Requested-With': 'XMLHttpRequest',
      }),
      'XmlHttpRequest',
    );
    expect(adGuardResourceType({'Sec-Fetch-Dest': 'script'}), 'Script');
    expect(adGuardResourceType({'sec-fetch-dest': 'iframe'}), 'SubDocument');
    expect(adGuardResourceType({'sec-fetch-dest': 'video'}), 'Media');
    expect(adGuardResourceType({'Accept': 'image/png'}), 'Other');
    expect(adGuardResourceType(null, mainFrame: true), 'Document');
  });
  test(
    'existing master setting and independent per-site settings survive reload',
    () async {
      SharedPreferences.setMockInitialValues({
        'block_ads_enabled': false,
        'rules_enabled_global': true,
      });
      final settings = await SiteSettings.load();
      expect(settings.blockAdsEnabled, false);
      expect(settings.adGuardEnabled('a', 'network'), true);
      await settings.setAdGuardEnabled('a', 'network', false);
      await settings.setAdGuardEnabled('a', 'scriptlets', false);
      final restored = await SiteSettings.load();
      expect(restored.adGuardEnabled('a', 'network'), false);
      expect(restored.adGuardEnabled('a', 'scriptlets'), false);
      expect(restored.adGuardEnabled('a', 'cosmetic'), true);
      expect(restored.adGuardEnabled('b', 'network'), true);
      expect(restored.globalEnabled, true);
      expect(
        () => settings.setAdGuardEnabled('a', 'unknown', true),
        throwsArgumentError,
      );
    },
  );
}
