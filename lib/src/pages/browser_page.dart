import 'dart:collection';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/catalog.dart';
import '../core/ad_blocking.dart';
import '../core/settings.dart';
import '../core/tv_remote.dart';
import 'tv_remote_page.dart';

enum BrowserLoadState { loading, loaded, failed }

class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.site,
    required this.catalog,
    required this.settings,
    this.initialUrl,
    this.onLoadStateChanged,
    this.handleSystemBack = true,
    this.loadTimeout,
  });
  final Site site;
  final Catalog catalog;
  final SiteSettings settings;
  final Uri? initialUrl;
  final ValueChanged<BrowserLoadState>? onLoadStateChanged;
  final bool handleSystemBack;
  final Duration? loadTimeout;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with RouteAware {
  static const _tapChannel = MethodChannel('mv/tap');

  InAppWebViewController? _controller;
  UserScript? _script;
  double _progress = 0;
  String? _error;
  bool _canGoBack = false;
  bool _canGoForward = false;
  Timer? _loadTimeout;
  PageRoute<dynamic>? _route;
  Uri? _resumeUrl;
  bool _playingOnTv = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      remoteRoutes.unsubscribe(this);
      _route = route;
      remoteRoutes.subscribe(this, route);
    }
  }

  @override
  void didPush() => _active(true);
  @override
  void didPopNext() => _active(true);
  @override
  void didPushNext() => _active(false);
  @override
  void didPop() => _active(false);

  void _active(bool active) {
    unawaited(TvRemoteLink.instance.browser(active));
  }

  void _loadState(BrowserLoadState state) {
    if (TvRemoteLink.instance.isTv) {
      TvRemoteLink.instance.loadState = state.name;
    }
    widget.onLoadStateChanged?.call(state);
  }

  Future<void> _sendToTv() async {
    final link = TvRemoteLink.instance;
    if (!link.connected) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TvRemotePage()));
    }
    if (!mounted || !link.connected) return;
    final url = await _controller?.getUrl();
    if (url == null) return;
    try {
      validateRemoteCommand({
        'action': 'open',
        'url': url.toString(),
      }, widget.catalog);
      await link.send({'action': 'open', 'url': url.toString()});
      if (mounted) {
        // Disposing the source WebView stops media even inside cross-origin frames.
        setState(() {
          _resumeUrl = url.uriValue;
          _playingOnTv = true;
          _controller = null;
          _progress = 1;
        });
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const TvRemotePage()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(remoteError(e))));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _prepareScript();
  }

  Future<void> _prepareScript() async {
    final template = await rootBundle.loadString(
      'assets/runtime/rule_runtime.js',
    );
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

  @override
  void dispose() {
    remoteRoutes.unsubscribe(this);
    _loadTimeout?.cancel();
    super.dispose();
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
      canPop: !widget.handleSystemBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !widget.handleSystemBack) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        bottomNavigationBar: TvRemoteLink.instance.isTv
            ? SafeArea(
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'ลูกศรขยับ · OK คลิก · Menu สลับเคอร์เซอร์',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    IconButton(
                      tooltip: 'เลื่อนหน้าขึ้น',
                      onPressed: () =>
                          TvRemoteLink.instance.input({'action': 'scrollUp'}),
                      icon: const Icon(Icons.vertical_align_top),
                    ),
                    IconButton(
                      tooltip: 'เลื่อนหน้าลง',
                      onPressed: () =>
                          TvRemoteLink.instance.input({'action': 'scrollDown'}),
                      icon: const Icon(Icons.vertical_align_bottom),
                    ),
                  ],
                ),
              )
            : null,
        appBar: AppBar(
          title: Text(widget.site.name),
          actions: [
            if (TvRemoteLink.instance.isTv)
              IconButton(
                tooltip: 'สลับเคอร์เซอร์ / เลือกปุ่ม (Menu บนรีโมต)',
                icon: const Icon(Icons.mouse_outlined),
                onPressed: () =>
                    TvRemoteLink.instance.input({'action': 'cursor'}),
              )
            else
              IconButton(
                tooltip: _playingOnTv ? 'ควบคุม TV' : 'เปิดบน TV',
                icon: const Icon(Icons.tv),
                onPressed: _playingOnTv
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TvRemotePage()),
                      )
                    : _sendToTv,
              ),
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
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
            PopupMenuButton<String>(
              tooltip: 'Save page',
              icon: const Icon(Icons.bookmark_add_outlined),
              onSelected: _saveCurrentPage,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'favorite', child: Text('รายการโปรด')),
                PopupMenuItem(value: 'watchLater', child: Text('ดูภายหลัง')),
              ],
            ),
            IconButton(
              tooltip: 'Open in external browser',
              icon: const Icon(Icons.open_in_browser),
              onPressed: () async {
                final url = await _controller?.getUrl();
                if (url != null) await _openExternal(url.uriValue);
              },
            ),
          ],
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress),
                )
              : null,
        ),
        body: _playingOnTv
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tv, size: 64),
                    const SizedBox(height: 16),
                    const Text('เปิดบน TV แล้ว หยุดเล่นบนมือถือแล้ว'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TvRemotePage()),
                      ),
                      icon: const Icon(Icons.settings_remote),
                      label: const Text('ควบคุม TV'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _playingOnTv = false;
                        _progress = 0;
                        _error = null;
                      }),
                      child: const Text('เปิดหน้านี้บนมือถืออีกครั้ง'),
                    ),
                  ],
                ),
              )
            : script == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri.uri(
                        (_resumeUrl ?? widget.initialUrl) != null &&
                                decideNavigation(
                                      (_resumeUrl ?? widget.initialUrl)!,
                                      widget.catalog,
                                    ) ==
                                    NavDecision.allowInApp
                            ? (_resumeUrl ?? widget.initialUrl)!
                            : widget.site.url,
                      ),
                    ),
                    initialUserScripts: UnmodifiableListView([script]),
                    initialSettings: InAppWebViewSettings(
                      useShouldInterceptRequest:
                          widget.settings.blockAdsEnabled,
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
                    shouldInterceptRequest: (_, request) async {
                      if (widget.settings.blockAdsEnabled &&
                          request.isForMainFrame != true &&
                          isBlockedAdUri(request.url.uriValue)) {
                        return WebResourceResponse(
                          contentType: 'text/plain',
                          contentEncoding: 'utf-8',
                          statusCode: 204,
                          reasonPhrase: 'No Content',
                          data: Uint8List(0),
                        );
                      }
                      return null;
                    },
                    onReceivedIcon: (_, icon) =>
                        widget.settings.saveFavicon(widget.site.id, icon),
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
                    onLoadStart: (c, url) {
                      _loadTimeout?.cancel();
                      final timeout = widget.loadTimeout;
                      if (timeout != null) {
                        _loadTimeout = Timer(timeout, () {
                          if (!mounted) return;
                          setState(() => _error = 'Timed out');
                          _loadState(BrowserLoadState.failed);
                          _controller?.stopLoading();
                        });
                      }
                      setState(() => _error = null);
                      _loadState(BrowserLoadState.loading);
                    },
                    onProgressChanged: (c, p) =>
                        setState(() => _progress = p / 100),
                    onLoadStop: (c, url) async {
                      _loadTimeout?.cancel();
                      // Rules are idempotent, so reapplying after navigation is safe.
                      await c.evaluateJavascript(source: script.source);
                      await _refreshNavState();
                      final uri = url?.uriValue;
                      _loadState(
                        _error == null
                            ? BrowserLoadState.loaded
                            : BrowserLoadState.failed,
                      );
                      if (uri != null &&
                          decideNavigation(uri, widget.catalog) ==
                              NavDecision.allowInApp &&
                          _error == null) {
                        await widget.settings.recordVisit(
                          widget.site,
                          uri,
                          await c.getTitle(),
                        );
                      }
                    },
                    onUpdateVisitedHistory: (c, url, _) async {
                      await _refreshNavState();
                    },
                    onReceivedError: (c, request, error) {
                      if (request.isForMainFrame ?? false) {
                        _loadTimeout?.cancel();
                        setState(() => _error = error.description);
                        _loadState(BrowserLoadState.failed);
                      }
                    },
                    onReceivedHttpError: (c, request, response) {
                      if ((request.isForMainFrame ?? false) &&
                          (response.statusCode ?? 0) >= 400) {
                        _loadTimeout?.cancel();
                        setState(() => _error = 'HTTP ${response.statusCode}');
                        _loadState(BrowserLoadState.failed);
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

  Future<void> _saveCurrentPage(String collection) async {
    final url = await _controller?.getUrl();
    if (url == null ||
        decideNavigation(url.uriValue, widget.catalog) !=
            NavDecision.allowInApp) {
      return;
    }
    final title = await _controller?.getTitle() ?? '';
    Object? rawPoster;
    try {
      rawPoster = await _controller?.evaluateJavascript(
        source: """document.querySelector('meta[property="og:image"]')?.content || document.querySelector('meta[name="twitter:image"]')?.content || ''""",
      );
    } catch (_) {}
    final poster = rawPoster is String && rawPoster.trim().isNotEmpty
        ? url.uriValue.resolve(rawPoster.trim())
        : null;
    await widget.settings.toggleSavedPage(
      widget.site,
      url.uriValue,
      title,
      collection,
      posterUrl:
          poster != null &&
              (poster.scheme == 'https' || poster.scheme == 'http')
          ? poster.toString()
          : null,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('รายการบันทึกอัปเดตแล้ว')));
    }
  }

  // Only taps requested by an allowlisted page are forwarded to native input.
  Future<bool> _nativeTap(List<dynamic> args) async {
    if (args.length != 3 || args.any((a) => a is! num || !a.isFinite)) {
      return false;
    }
    final url = await _controller?.getUrl();
    final host = url?.host ?? '';
    if (!widget.catalog.isAllowedHost(host)) return false;
    return await _tapChannel.invokeMethod<bool>('tap', {
          'x': (args[0] as num).toDouble(),
          'y': (args[1] as num).toDouble(),
          'viewportWidth': (args[2] as num).toDouble(),
        }) ==
        true;
  }

  Future<void> _setFullscreen(bool on) async {
    if (TvRemoteLink.instance.isTv) {
      await TvRemoteLink.channel.invokeMethod('fullscreen', {'active': on});
    }
    await SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      on
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : TvRemoteLink.instance.isTv
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
