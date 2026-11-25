import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

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
}
