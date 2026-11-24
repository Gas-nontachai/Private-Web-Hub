import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movieapps/main.dart';
import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/settings.dart';
import 'package:movieapps/src/core/tv_remote.dart';
import 'package:movieapps/src/pages/tv_remote_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'TV grid fits landscape and D-pad moves visible focus between sites',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TvRemoteLink.instance.isTv = true;
      addTearDown(() => TvRemoteLink.instance.isTv = false);
      SharedPreferences.setMockInitialValues({});
      final catalog = Catalog.parse(
        File('assets/catalog/websites.json').readAsStringSync(),
      );
      await tester.pumpWidget(
        MainApp(catalog: catalog, settings: await SiteSettings.load()),
      );
      await tester.pump();
      final first = find.byKey(ValueKey('site-${catalog.sites.first.id}'));
      final second = find.byKey(ValueKey('site-${catalog.sites[1].id}'));
      bool focused(Finder finder) => Focus.of(
        tester.element(
          find.descendant(of: finder, matching: find.byType(Column)).first,
        ),
      ).hasFocus;
      expect(focused(first), true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focused(second), true);
      expect(focused(first), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TV pairing displays code and identity and closes pairing when leaving',
    (tester) async {
      final calls = <String>[];
      TvRemoteLink.instance.isTv = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteLink.channel, (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'permission' => true,
              'pairing' => {
                'code': '123456',
                'address': '192.168.1.39',
                'port': 47831,
                'fingerprint': 'aabbccddeeff',
              },
              _ => null,
            };
          });
      addTearDown(() {
        TvRemoteLink.instance.isTv = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(TvRemoteLink.channel, null);
      });
      await tester.pumpWidget(const MaterialApp(home: TvRemotePage()));
      await tester.pumpAndSettle();
      expect(find.text('123456'), findsOneWidget);
      expect(find.textContaining('aabbccddeeff'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls, contains('endPairing'));
    },
  );
}
