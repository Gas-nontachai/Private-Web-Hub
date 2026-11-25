import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:movieapps/src/core/media_playback.dart';
import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:movieapps/src/core/tv_remote.dart';
import 'package:movieapps/src/pages/browser_page.dart';
import 'package:movieapps/src/pages/tv_remote_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WebPlatform extends InAppWebViewPlatform {
  final views = <_WebView>[];
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    if (views.isNotEmpty && !views.last.disposed) return views.last;
    final view = _WebView(params);
    views.add(view);
    return view;
  }
}

class _WebView extends PlatformInAppWebViewWidget {
  _WebView(super.params) : super.implementation();
  bool created = false;
  bool disposed = false;
  @override
  Widget build(BuildContext context) {
    if (!created) {
      created = true;
      final controller = controllerFromPlatform<InAppWebViewController>(
        _Controller(),
      );
      params.onWebViewCreated?.call(controller);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => params.onProgressChanged?.call(controller, 100),
      );
    }
    return const SizedBox(key: ValueKey('source-webview'));
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {
    disposed = true;
  }
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 1),
      );
  @override
  Future<WebUri?> getUrl() async =>
      WebUri('https://www.037-hdd.com/movie-test/');
  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {}
}

void main() {
  for (final accepted in [true, false]) {
    testWidgets(
      'source WebView is disposed only after TV accepts page ($accepted)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'block_ads_enabled': false});
        final mediaCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MediaPlayback.channel, (call) async {
              mediaCalls.add(call.method);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(MediaPlayback.channel, null),
        );
        final platform = _WebPlatform();
        final previous = InAppWebViewPlatform.instance;
        InAppWebViewPlatform.instance = platform;
        final link = TvRemoteLink.instance
          ..isTv = false
          ..connected = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(TvRemoteLink.channel, (call) async {
              if (call.method == 'send') {
                final command = (call.arguments as Map)['command'] as Map;
                if (command['action'] == 'open' && !accepted) {
                  throw PlatformException(code: 'remote');
                }
                return {
                  'loadState': 'loading',
                  'browser': true,
                  'cursor': true,
                };
              }
              return null;
            });
        addTearDown(() {
          link.connected = false;
          link.browserOpen = false;
          if (previous != null) InAppWebViewPlatform.instance = previous;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(TvRemoteLink.channel, null);
        });
        await tester.runAsync(
          () => rootBundle.loadString('assets/runtime/rule_runtime.js'),
        );
        final catalog = Catalog.parse(
          File('assets/catalog/websites.json').readAsStringSync(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: BrowserPage(
              site: catalog.sites[1],
              catalog: catalog,
              settings: await SiteSettings.load(),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(platform.views, hasLength(1));
        await tester.tap(find.byTooltip('เปิดบน TV'));
        await tester.pumpAndSettle();
        expect(platform.views.first.disposed, accepted);
        expect(mediaCalls.contains("detach"), accepted);
        if (accepted) {
          expect(find.byType(TvRemotePage), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(
            find.text('เปิดบน TV แล้ว หยุดเล่นบนมือถือแล้ว'),
            findsOneWidget,
          );
          await tester.tap(find.text('เปิดหน้านี้บนมือถืออีกครั้ง'));
          await tester.pumpAndSettle();
          expect(platform.views, hasLength(2));
          expect(
            platform.views.last.params.initialUrlRequest!.url.toString(),
            'https://www.037-hdd.com/movie-test/',
          );
        } else {
          expect(find.byKey(const ValueKey('source-webview')), findsOneWidget);
          expect(find.byType(TvRemotePage), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'touchpad sends movement before click with finite normalized coordinates',
    (tester) async {
      final link = TvRemoteLink.instance
        ..isTv = false
        ..connected = true
        ..browserOpen = true
        ..cursor = true;
      final commands = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteLink.channel, (call) async {
            if (call.method == 'send') {
              commands.add((call.arguments as Map)['command'] as Map);
              return {'loadState': 'loaded', 'browser': true, 'cursor': true};
            }
            return null;
          });
      addTearDown(() {
        link.connected = false;
        link.browserOpen = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(TvRemoteLink.channel, null);
      });
      await tester.pumpWidget(const MaterialApp(home: TvRemotePage()));
      await tester.pumpAndSettle();
      final pad = find.byKey(const ValueKey('tv-touchpad'));
      await tester.drag(pad, const Offset(50, 30));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(pad);
      await tester.pumpAndSettle();
      final move = commands.indexWhere((c) => c['action'] == 'move');
      final click = commands.indexWhere((c) => c['action'] == 'ok');
      expect(move, greaterThanOrEqualTo(0));
      expect(click, greaterThan(move));
      expect((commands[move]['dx'] as num).isFinite, true);
      expect((commands[move]['dy'] as num).abs(), lessThanOrEqualTo(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
