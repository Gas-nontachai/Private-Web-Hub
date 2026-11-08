import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movieapps/main.dart';
import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home renders all configured sites', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final catalog = Catalog.parse(
      File('assets/catalog/websites.json').readAsStringSync(),
    );
    final settings = await SiteSettings.load();
    await tester.pumpWidget(MainApp(catalog: catalog, settings: settings));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'Movie.exe');
    for (final name in ['SerieDay', '037HDD', 'GoSeries4K']) {
      expect(find.text(name), findsOneWidget);
    }
  });
}
