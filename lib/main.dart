import 'package:flutter/material.dart';

import 'src/catalog.dart';
import 'src/home_page.dart';
import 'src/settings.dart';
import 'src/theme.dart';

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
