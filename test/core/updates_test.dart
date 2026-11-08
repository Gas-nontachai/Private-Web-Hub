import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movieapps/src/core/updates.dart';

Map<String, dynamic> release(String version) => {
  'tag_name': 'v$version',
  'assets': [
    {
      'name': 'Movie.exe-v$version.apk',
      'browser_download_url': 'https://example.com/app.apk',
    },
  ],
};

class FailingClient extends Fake implements HttpClient {
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      throw const SocketException('offline');
  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compares all numeric version components', () {
    expect(parseUpdate(release('1.10.0'), '1.9.9')?.tag, 'v1.10.0');
    expect(parseUpdate(release('1.0.1'), '1.0.0'), isNotNull);
    expect(parseUpdate(release('1.0.0'), '1.0.0'), isNull);
    expect(parseUpdate(release('1.0.0'), '2.0.0'), isNull);
  });

  test('rejects malformed versions, missing APK and unsafe URLs', () {
    for (final data in [
      <String, dynamic>{},
      {...release('1.0.0'), 'tag_name': 'v1.0-beta'},
      {...release('1.0.0'), 'assets': []},
      {
        'tag_name': 'v1.0.0',
        'assets': [
          {
            'name': 'Movie.exe-v1.0.0.apk',
            'browser_download_url': 'file:///tmp/app.apk',
          },
        ],
      },
    ]) {
      expect(() => parseUpdate(data, '0.1.0'), throwsFormatException);
    }
    expect(
      () => parseUpdate(release('1.0.0'), 'unknown'),
      throwsFormatException,
    );
  });

  test('network failures close the client', () async {
    final client = FailingClient();
    await expectLater(
      fetchUpdate('1.0.0', client: client),
      throwsA(isA<SocketException>()),
    );
    expect(client.closed, isTrue);
  });

  for (final manual in [false, true]) {
    testWidgets('version failure is ${manual ? "reported" : "silent"}', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mv/app'),
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mv/app'),
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => checkForUpdates(context, manual: manual),
                child: const Text('Check'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not check for updates:'),
        manual ? findsOneWidget : findsNothing,
      );
    });
  }
}
