import 'dart:io';
import 'dart:async';

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

class DownloadResponse extends Stream<List<int>> implements HttpClientResponse {
  DownloadResponse(
    this.chunks, {
    this.contentLength = 4,
    this.statusCode = 200,
  });
  final List<List<int>> chunks;
  @override
  final int contentLength;
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DownloadRequest extends Fake implements HttpClientRequest {
  DownloadRequest(this.response);
  final HttpClientResponse response;
  @override
  Future<HttpClientResponse> close() async => response;
}

class DownloadClient extends Fake implements HttpClient {
  DownloadClient(this.response);
  final HttpClientResponse response;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => DownloadRequest(response);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final apkUrl = Uri.parse(
    'https://github.com/Gas-nontachai/Private-Web-Hub/releases/download/v1.0.1/Movie.exe-v1.0.1.apk',
  );

  test('selects the TV APK only for TV devices', () {
    final data = release('1.0.1');
    (data['assets'] as List).add({
      'name': 'Movie.exe-TV-v1.0.1.apk',
      'browser_download_url': 'https://example.com/tv.apk',
    });
    expect(parseUpdate(data, '1.0.0', isTv: true)?.url.path, '/tv.apk');
    expect(parseUpdate(data, '1.0.0')?.url.path, '/app.apk');
  });

  test('streams APK bytes and reports progress', () async {
    final directory = await Directory.systemTemp.createTemp('update-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/update.apk');
    final progress = <int>[];
    await downloadUpdate(
      apkUrl,
      file,
      client: DownloadClient(
        DownloadResponse([
          [1, 2],
          [3, 4],
        ]),
      ),
      onProgress: (received, total) {
        expect(total, 4);
        progress.add(received);
      },
    );
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(progress, [2, 4]);
  });

  test('failed or truncated downloads leave no APK', () async {
    final directory = await Directory.systemTemp.createTemp('update-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/update.apk');
    for (final response in [
      DownloadResponse([
        [1],
      ]),
      DownloadResponse([], statusCode: 404),
    ]) {
      await expectLater(
        downloadUpdate(
          apkUrl,
          file,
          client: DownloadClient(response),
          onProgress: (_, _) {},
        ),
        throwsA(isA<HttpException>()),
      );
      expect(await file.exists(), isFalse);
    }
    await expectLater(
      downloadUpdate(
        Uri.parse('https://example.com/app.apk'),
        file,
        client: DownloadClient(DownloadResponse([])),
        onProgress: (_, _) {},
      ),
      throwsFormatException,
    );
  });

  testWidgets('download failure shows retry and cancel controls', (
    tester,
  ) async {
    // A rejected URL exercises the visible failure and retry controls without network.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('mv/app'),
      (call) async => '/unused/update.apk',
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mv/app'),
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateDownloadDialog(
          update: AppUpdate('v1.0.1', Uri.parse('https://example.com/app.apk')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Download failed:'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

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
