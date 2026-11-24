import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movieapps/src/core/catalog.dart';
import 'package:movieapps/src/core/tv_remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = Catalog.parse(
    File('assets/catalog/websites.json').readAsStringSync(),
  );
  test(
    'only HTTPS catalog URLs without embedded credentials can open on TV',
    () {
      final url = catalog.sites.first.url.toString();
      expect(
        validateRemoteCommand({'action': 'open', 'url': url}, catalog)['url'],
        url,
      );
      for (final url in [
        'http://www.serieday-z.com/',
        'https://evil.example/',
        'javascript:alert(1)',
        'file:///data/local/tmp/file',
        'https://www.serieday-z.com.evil.example/',
        'https://user:password@www.serieday-z.com/',
        '',
      ]) {
        expect(
          () => validateRemoteCommand({'action': 'open', 'url': url}, catalog),
          throwsFormatException,
        );
      }
    },
  );
  test('reject malformed commands and non-finite or out-of-range movement', () {
    for (final value in [
      null,
      [],
      {},
      {'action': 'javascript'},
      {'action': 'open', 'url': 1},
    ]) {
      expect(
        () => validateRemoteCommand(value, catalog),
        throwsFormatException,
      );
    }
    for (final value in [double.nan, double.infinity, 1.01, -1.01, '0', null]) {
      expect(
        () => validateRemoteCommand({
          'action': 'move',
          'dx': value,
          'dy': 0,
        }, catalog),
        throwsFormatException,
      );
    }
    expect(
      validateRemoteCommand({
        'action': 'move',
        'dx': -.5,
        'dy': 1,
      }, catalog)['dx'],
      -.5,
    );
    for (final action in remoteActions.difference({'open', 'move'})) {
      expect(
        validateRemoteCommand({'action': action}, catalog)['action'],
        action,
      );
    }
  });
  test(
    'application rejection keeps the connection for the next command',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteLink.channel, (call) async {
            final command = (call.arguments as Map)['command'] as Map;
            if (command['action'] == 'cursor') {
              throw PlatformException(
                code: 'rejected',
                message: 'Open a web page first',
              );
            }
            return {'loadState': 'idle'};
          });
      final link = TvRemoteLink()..connected = true;
      await expectLater(
        link.send({'action': 'cursor'}),
        throwsA(isA<PlatformException>()),
      );
      expect(link.connected, true);
      expect(await link.send({'action': 'status'}), {'loadState': 'idle'});
      link.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteLink.channel, null);
    },
  );
  test('failed command disconnects and is never replayed', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvRemoteLink.channel, (call) async {
          calls.add(call);
          if (call.method == 'send') {
            throw PlatformException(code: 'disconnected');
          }
          return null;
        });
    final link = TvRemoteLink()..connected = true;
    await expectLater(
      link.send({'action': 'ok'}),
      throwsA(isA<PlatformException>()),
    );
    expect(link.connected, false);
    expect(link.busy, false);
    await expectLater(link.send({'action': 'ok'}), throwsFormatException);
    expect(calls.where((c) => c.method == 'send'), hasLength(1));
    link.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvRemoteLink.channel, null);
  });
}
