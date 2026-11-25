import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

enum AdGuardState { idle, loading, ready, failed }

/// TSUrlFilter runs in a private V8 worker, isolated from UI and website scripts.
class AdGuardEngine {
  static final instance = AdGuardEngine();
  static const _host = 'appassets.androidplatform.net';
  static const _path = '/assets/flutter_assets/assets/adguard/';
  final state = ValueNotifier<AdGuardState>(AdGuardState.idle);
  String? error;
  int rules = 0;
  int blocked = 0;
  Future<bool>? _initializing;
  HeadlessInAppWebView? _view;
  final _pending = <int, Completer<dynamic>>{};
  int _sequence = 0;
  Map<String, dynamic> redirects = {};

  Future<bool> ensureReady() => state.value == AdGuardState.failed
      ? Future.value(false)
      : _initializing ??= _start();

  Future<bool> _start() async {
    state.value = AdGuardState.loading;
    final ready = Completer<bool>();
    void fail(String message) {
      if (state.value == AdGuardState.failed) return;
      error = message;
      state.value = AdGuardState.failed;
      if (kDebugMode) debugPrint('AdGuard unavailable: $error');
      if (!ready.isCompleted) ready.complete(false);
      for (final item in _pending.values) {
        if (!item.isCompleted) item.complete(null);
      }
      _pending.clear();
      unawaited(_view?.dispose() ?? Future<void>.value());
    }

    try {
      redirects = jsonDecode(
        await rootBundle.loadString('assets/adguard/redirects.json'),
      ) as Map<String, dynamic>;
      _view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('https://$_host${_path}host.html'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          cacheMode: CacheMode.LOAD_NO_CACHE,
          useOnRenderProcessGone: true,
          webViewAssetLoader: WebViewAssetLoader(
            pathHandlers: [AssetsPathHandler(path: '/assets/')],
          ),
          useShouldInterceptRequest: true,
          useShouldOverrideUrlLoading: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
          allowFileAccess: false,
          allowContentAccess: false,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
        ),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'mvAdguardEngine',
            callback: (args) {
              if (args.isEmpty || args[0] is! Map) return null;
              final message = args[0] as Map;
              switch (message['kind']) {
                case 'ready':
                  rules = (message['rules'] as num).toInt();
                  state.value = AdGuardState.ready;
                  if (kDebugMode) debugPrint('AdGuard ready: $rules rules');
                  if (!ready.isCompleted) ready.complete(true);
                case 'fatal':
                  fail(message['error'].toString());
                case 'result':
                  _pending.remove(message['id'])?.complete(message['result']);
              }
              return null;
            },
          );
        },
        shouldInterceptRequest: (_, request) async =>
            request.url.host == _host && request.url.path.startsWith(_path)
            ? null
            : WebResourceResponse(
                statusCode: 204,
                reasonPhrase: 'No Content',
                data: Uint8List(0),
              ),
        shouldOverrideUrlLoading: (_, action) async =>
            action.request.url?.host == _host
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL,
        onRenderProcessGone: (_, _) =>
            fail('Filter renderer stopped; reopen the app to retry'),
        onReceivedError: (_, request, failure) {
          if (request.isForMainFrame == true) fail(failure.description);
        },
        onPermissionRequest: (_, request) async => PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.DENY,
        ),
      );
      await _view!.run();
      return await ready.future.timeout(const Duration(seconds: 120));
    } catch (e) {
      fail(e.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>?> _call(
    String method,
    Map<String, Object?> context,
  ) async {
    if (state.value != AdGuardState.ready) return null;
    final id = ++_sequence;
    final result = Completer<dynamic>();
    _pending[id] = result;
    try {
      await _view!.webViewController!.evaluateJavascript(
        source:
            'window.mvAdguardWorker.postMessage(${jsonEncode({'id': id, 'method': method, 'context': context})})',
      );
      final value = await result.future.timeout(const Duration(seconds: 3));
      return value is Map ? value.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  Future<Map<String, dynamic>?> evaluateRequest(
    Map<String, Object?> context,
  ) async {
    final result = await _call('evaluateRequest', context);
    if (result?['block'] == true) blocked++;
    return result;
  }

  Future<Map<String, dynamic>?> getPageRules(Map<String, Object?> context) =>
      _call('getPageRules', context);
}

/// Android WebView exposes headers, not Chromium's resource type enum.
String adGuardResourceType(
  Map<String, String>? headers, {
  bool mainFrame = false,
}) {
  if (mainFrame) return 'Document';
  final normalized = {
    for (final entry in (headers ?? <String, String>{}).entries)
      entry.key.toLowerCase(): entry.value.toLowerCase(),
  };
  return switch (normalized['sec-fetch-dest']) {
    'iframe' || 'frame' => 'SubDocument',
    'script' || 'worker' || 'sharedworker' || 'serviceworker' => 'Script',
    'style' => 'Stylesheet',
    'image' => 'Image',
    'font' => 'Font',
    'audio' || 'video' || 'track' => 'Media',
    'object' || 'embed' => 'Object',
    'empty' =>
      normalized['x-requested-with'] == 'xmlhttprequest'
          ? 'XmlHttpRequest'
          : 'Other',
    _ => 'Other', // shortcut: WebView omits request type, refine only with reliable metadata.
  };
}
