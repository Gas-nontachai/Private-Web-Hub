import 'package:flutter/material.dart';

import 'src/core/catalog.dart';
import 'src/core/settings.dart';
import 'src/pages/home_page.dart';
import 'src/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = await Catalog.load();
  final settings = await SiteSettings.load();
  runApp(MainApp(catalog: catalog, settings: settings));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.catalog, required this.settings});
  final Catalog catalog;
  final SiteSettings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movie.exe',
      theme: buildTheme(),
      home: HomePage(catalog: catalog, settings: settings),
    );
  }
}
