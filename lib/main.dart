import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/core/catalog.dart';
import 'src/core/settings.dart';
import 'src/core/tv_remote.dart';
import 'src/pages/browser_page.dart';
import 'src/pages/home_page.dart';
import 'src/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = await Catalog.load();
  final settings = await SiteSettings.load();
  await TvRemoteLink.instance.initialize();
  runApp(MainApp(catalog: catalog, settings: settings));
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.catalog, required this.settings});
  final Catalog catalog;
  final SiteSettings settings;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final link = TvRemoteLink.instance;

  @override
  void initState() {
    super.initState();
    link.onCommand = _command;
    link.onPairRequest = _approve;
  }

  @override
  void dispose() {
    link.onCommand = null;
    link.onPairRequest = null;
    super.dispose();
  }

  Future<bool> _approve(Map<String, dynamic> data) async {
    final context = link.navigatorKey.currentContext;
    if (context == null) return false;
    BuildContext? dialogContext;
    final timeout = Timer(const Duration(seconds: 55), () {
      final context = dialogContext;
      if (context != null &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, false);
      }
    });
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              dialogContext = context;
              return AlertDialog(
                title: Text('อนุญาต ${data['name']} ควบคุม TV?'),
                content: Text(
                  'ตรวจว่าเลขยืนยันบนมือถือคือ ${data['fingerprint']}\nหากเลขไม่ตรงกัน ให้ปฏิเสธ',
                ),
                actions: [
                  TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('ปฏิเสธ'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('เลขตรงกัน · อนุญาต'),
                  ),
                ],
              );
            },
          ) ??
          false;
    } finally {
      timeout.cancel();
    }
  }

  Future<Map<String, dynamic>> _command(Map<String, dynamic> data) async {
    final command = validateRemoteCommand(data, widget.catalog);
    final nav = link.navigatorKey.currentState;
    if (nav == null) throw const FormatException('TV is not ready');
    switch (command['action']) {
      case 'open':
        final uri = Uri.parse(command['url'] as String);
        final site = widget.catalog.sites.firstWhere(
          (s) => s.hosts.contains(uri.host.toLowerCase()),
        );
        await link.input({'action': 'backFullscreen'});
        nav.popUntil((route) => route.isFirst);
        link.loadState = 'loading';
        nav.push(
          MaterialPageRoute(
            builder: (_) => BrowserPage(
              site: site,
              catalog: widget.catalog,
              settings: widget.settings,
              initialUrl: uri,
            ),
          ),
        );
      case 'home':
        await link.input({'action': 'backFullscreen'});
        nav.popUntil((route) => route.isFirst);
        link.loadState = 'idle';
      case 'status':
        break;
      default:
        await link.input(command);
    }
    return {
      'loadState': link.loadState,
      ...?await TvRemoteLink.channel.invokeMapMethod<String, dynamic>(
        'inputState',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movie.exe',
      navigatorKey: link.navigatorKey,
      navigatorObservers: [remoteRoutes],
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
      },
      theme: buildTheme(isTv: link.isTv),
      home: HomePage(catalog: widget.catalog, settings: widget.settings),
    );
  }
}
