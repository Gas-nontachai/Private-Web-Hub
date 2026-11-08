import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalog.dart';
import 'settings.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.site,
    required this.catalog,
    required this.settings,
  });
  final Site site;
  final Catalog catalog;
  final SiteSettings settings;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  static const _tapChannel = MethodChannel('mv/tap');

  InAppWebViewController? _controller;
  UserScript? _script;
  double _progress = 0;
  String? _error;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _prepareScript();
  }

  Future<void> _prepareScript() async {
    final template = await rootBundle.loadString('assets/rule_runtime.js');
    if (!mounted) return;
    setState(() {
      _script = UserScript(
        source: buildRuleScript(
          template,
          widget.catalog.sites,
          widget.settings.isEnabled,
          globalRules: widget.settings.globalEnabled
              ? widget.catalog.globalRules
              : const [],
        ),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      );
    });
  }

  Future<void> _refreshNavState() async {
    final c = _controller;
    if (c == null) return;
    final back = await c.canGoBack();
    final fwd = await c.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _canGoForward = fwd;
    });
  }

  Future<void> _openExternal(Uri uri) async {
    const allowed = {'http', 'https', 'mailto', 'tel'};
    if (!allowed.contains(uri.scheme)) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app available to open this link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final script = _script;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.site.name),
          actions: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: _canGoBack ? () => _controller?.goBack() : null,
            ),
            IconButton(
              tooltip: 'Forward',
              icon: const Icon(Icons.arrow_forward),
              onPressed: _canGoForward ? () => _controller?.goForward() : null,
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() => _error = null);
                _controller?.reload();
              },
            ),
            IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.home),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress),
                )
              : null,
        ),
        body: script == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri.uri(widget.site.url),
                    ),
                    initialUserScripts: UnmodifiableListView([script]),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                      supportMultipleWindows: false,
                      javaScriptCanOpenWindowsAutomatically: false,
                    ),
                    onWebViewCreated: (c) {
                      _controller = c;
                      c.addJavaScriptHandler(
                        handlerName: 'mvTap',
                        callback: (args) => _nativeTap(args),
                      );
                    },
                    shouldOverrideUrlLoading: (c, action) async {
                      final uri = action.request.url?.uriValue;
                      if (uri == null) return NavigationActionPolicy.CANCEL;
                      if (decideNavigation(uri, widget.catalog) ==
                          NavDecision.allowInApp) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      await _openExternal(uri);
                      return NavigationActionPolicy.CANCEL;
                    },
                    onLoadStart: (c, url) => setState(() => _error = null),
                    onProgressChanged: (c, p) =>
                        setState(() => _progress = p / 100),
                    onLoadStop: (c, url) async {
                      // Rules are idempotent, so reapplying after navigation is safe.
                      await c.evaluateJavascript(source: script.source);
                      await _refreshNavState();
                    },
                    onUpdateVisitedHistory: (c, url, _) => _refreshNavState(),
                    onReceivedError: (c, request, error) {
                      if (request.isForMainFrame ?? false) {
                        setState(() => _error = error.description);
                      }
                    },
                    onReceivedHttpError: (c, request, response) {
                      if ((request.isForMainFrame ?? false) &&
                          (response.statusCode ?? 0) >= 400) {
                        setState(() => _error = 'HTTP ${response.statusCode}');
                      }
                    },
                    // Default behavior cancels on TLS errors; never proceed.
                    onReceivedServerTrustAuthRequest: (c, challenge) async =>
                        ServerTrustAuthResponse(
                          action: ServerTrustAuthResponseAction.CANCEL,
                        ),
                    onEnterFullscreen: (c) => _setFullscreen(true),
                    onExitFullscreen: (c) => _setFullscreen(false),
                    onPermissionRequest: (c, request) async =>
                        PermissionResponse(
                          resources: request.resources,
                          action: PermissionResponseAction.DENY,
                        ),
                  ),
                  if (_error != null)
                    _ErrorView(
                      message: _error!,
                      onRetry: () {
                        setState(() => _error = null);
                        _controller?.reload();
                      },
                    ),
                ],
              ),
      ),
    );
  }

  // Only taps requested by an allowlisted page are forwarded to native input.
  Future<void> _nativeTap(List<dynamic> args) async {
    if (args.length < 3 || args.any((a) => a is! num)) return;
    final url = await _controller?.getUrl();
    final host = url?.host ?? '';
    if (!widget.catalog.isAllowedHost(host)) return;
    await _tapChannel.invokeMethod('tap', {
      'x': (args[0] as num).toDouble(),
      'y': (args[1] as num).toDouble(),
      'viewportWidth': (args[2] as num).toDouble(),
    });
  }

  Future<void> _setFullscreen(bool on) async {
    await SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      on
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'Could not load page',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
