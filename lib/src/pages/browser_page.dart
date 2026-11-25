import 'dart:collection';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/catalog.dart';
import '../core/ad_blocking.dart';
import '../core/settings.dart';
import '../core/media_playback.dart';
import '../core/tv_remote.dart';
import 'tv_remote_page.dart';
import '../widgets/adguard_controls.dart';

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
  final _mediaOwner = MediaPlayback.newOwner();
  bool get _supportsMedia => kDebugMode && !TvRemoteLink.instance.isTv;
  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  InAppWebViewController? _controller;
  UserScript? _script;
  UserScript? _adguardScript;
  int _webRevision = 0;
  int _navigationEpoch = 0;
  Uri? _currentUrl;
  String _settingsSnapshot = '';

  String get _protectionSettings => [
    widget.settings.blockAdsEnabled,
    for (final feature in ['network', 'cosmetic', 'scriptlets'])
      widget.settings.adGuardEnabled(widget.site.id, feature),
    widget.settings.globalEnabled,
    for (final site in widget.catalog.sites) widget.settings.isEnabled(site),
  ].join(':');

  Map<String, Object?> _filterContext(
    Uri url,
    Uri source, {
    String type = 'Document',
    String? method,
  }) => {
    'url': url.toString(),
    'sourceUrl': source.toString(),
    'siteId': widget.site.id,
    'host': (type == 'Document' ? url : source).host.toLowerCase(),
    'type': type,
    'method': method,
  };

  Future<Map<String, dynamic>?> _pageRules(
    String value,
    String? referrer,
  ) async {
    final url = Uri.tryParse(value);
    if (url == null ||
        !{'http', 'https'}.contains(url.scheme) ||
        value.length > 16384) {
      return null;
    }
    final source = Uri.tryParse(referrer ?? '');
    return AdGuardEngine.instance.getPageRules(
      _filterContext(
        url,
        source != null && {'http', 'https'}.contains(source.scheme)
            ? source
            : url,
      ),
    );
  }

  Future<void> _reloadProtection() async {
    final url = await _controller?.getUrl();
    if (!mounted || _playingOnTv) return;
    _resumeUrl =
        url?.uriValue ?? _currentUrl ?? widget.initialUrl ?? widget.site.url;
    _navigationEpoch++;
    if (_supportsMedia) await MediaPlayback.instance.detach(_mediaOwner);
    if (!mounted) return;
    setState(() {
      _script = null;
      _adguardScript = null;
      _controller = null;
      _webRevision++;
    });
    await _prepareScript();
  }

  Future<void> _showAdGuard() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ตัวกรอง · ${widget.site.name}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: AdGuardControls(
              settings: widget.settings,
              siteId: widget.site.id,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _reloadProtection();
            },
            child: const Text('โหลดหน้าใหม่'),
          ),
        ],
      ),
    );
  }

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
    MediaPlayback.instance.removeListener(_mediaChanged);
    MediaPlayback.instance.addListener(_mediaChanged);
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
  void didPopNext() {
    _active(true);
    if (_settingsSnapshot != _protectionSettings) {
      unawaited(_reloadProtection());
    }
  }

  @override
  void didPushNext() => _active(false);
  @override
  void didPop() => _active(false);

  void _attachMedia() {
    if (_supportsMedia) {
      unawaited(
        MediaPlayback.instance.attach(
          _mediaOwner,
          widget.catalog.allowedHosts,
          allowSkip: const {'เพลง', 'วิดีโอ'}.contains(widget.site.category),
        ),
      );
    }
  }

  void _active(bool active) {
    if (!active && _supportsMedia) {
      unawaited(MediaPlayback.instance.detach(_mediaOwner));
    }
    if (active && _controller != null) _attachMedia();
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
        if (_supportsMedia) await MediaPlayback.instance.detach(_mediaOwner);
        if (!mounted) return;
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
    UserScript? adguardScript;
    _settingsSnapshot = _protectionSettings;
    if (widget.settings.blockAdsEnabled &&
        await AdGuardEngine.instance.ensureReady()) {
      final page = await rootBundle.loadString('assets/adguard/page.js');
      final initial = _resumeUrl ?? widget.initialUrl ?? widget.site.url;
      final rules = await _pageRules(initial.toString(), null);
      final owned = <String, List<String>>{};
      for (final site in widget.catalog.sites) {
        if (!widget.settings.isEnabled(site)) continue;
        for (final rule in site.rules.where((rule) => rule.enabled)) {
          for (final host in rule.hosts) {
            owned
                .putIfAbsent(host, () => [])
                .addAll(
                  rule.actions
                      .where((action) => action.type == 'hide')
                      .expand((action) => action.selectors),
                );
          }
        }
      }
      adguardScript = UserScript(
        source: page.replaceAll(
          '__MV_ADGUARD_CONFIG__',
          jsonEncode({
            'initialUrl': initial.toString(),
            'initialRules': rules,
            'owned': owned,
            'cosmetic': widget.settings.adGuardEnabled(
              widget.site.id,
              'cosmetic',
            ),
            'scriptlets': widget.settings.adGuardEnabled(
              widget.site.id,
              'scriptlets',
            ),
          }),
        ),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      );
    }
    if (!mounted) return;
    setState(() {
      _adguardScript = adguardScript;
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
    MediaPlayback.instance.removeListener(_mediaChanged);
    if (_supportsMedia) unawaited(MediaPlayback.instance.detach(_mediaOwner));
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
        appBar: MediaPlayback.instance.value
            ? null
            : AppBar(
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
                              MaterialPageRoute(
                                builder: (_) => const TvRemotePage(),
                              ),
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
                    onPressed: _canGoForward
                        ? () => _controller?.goForward()
                        : null,
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
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Save page',
                    icon: const Icon(Icons.bookmark_add_outlined),
                    onSelected: (value) {
                      if (value == 'adguard') {
                        _showAdGuard();
                      } else {
                        _saveCurrentPage(value);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'adguard',
                        child: Text('AdGuard และกฎเฉพาะเว็บ'),
                      ),
                      PopupMenuItem(
                        value: 'favorite',
                        child: Text('รายการโปรด'),
                      ),
                      PopupMenuItem(
                        value: 'watchLater',
                        child: Text('ดูภายหลัง'),
                      ),
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
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('กำลังเตรียมตัวกรองและหน้าเว็บ…'),
                  ],
                ),
              )
            : Stack(
                children: [
                  InAppWebView(
                    key: ValueKey(_webRevision),
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
                    initialUserScripts: UnmodifiableListView([
                      ?_adguardScript,
                      script,
                    ]),
                    initialSettings: InAppWebViewSettings(
                      useShouldInterceptRequest: true,
                      useOnRenderProcessGone: true,
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      allowBackgroundAudioPlaying: _supportsMedia,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                      supportMultipleWindows: false,
                      javaScriptCanOpenWindowsAutomatically: false,
                    ),
                    onWebViewCreated: (c) {
                      _controller = c;
                      _attachMedia();
                      c.addJavaScriptHandler(
                        handlerName: 'mvAdguardRules',
                        callback: (args) async {
                          if (!widget.settings.blockAdsEnabled ||
                              args.isEmpty ||
                              args[0] is! String) {
                            return null;
                          }
                          final epoch = _navigationEpoch;
                          final rules = await _pageRules(
                            args[0] as String,
                            args.length > 1 && args[1] is String
                                ? args[1] as String
                                : null,
                          );
                          return mounted && epoch == _navigationEpoch
                              ? rules
                              : null;
                        },
                      );
                      c.addJavaScriptHandler(
                        handlerName: 'mvTap',
                        callback: (args) => _nativeTap(args),
                      );
                    },
                    shouldInterceptRequest: (_, request) async {
                      if (!widget.settings.blockAdsEnabled ||
                          !widget.settings.adGuardEnabled(
                            widget.site.id,
                            'network',
                          ) ||
                          request.isForMainFrame == true) {
                        return null;
                      }
                      final url = request.url.uriValue;
                      if (!{'http', 'https'}.contains(url.scheme)) return null;
                      final epoch = _navigationEpoch;
                      final referrers = (request.headers ?? <String, String>{})
                          .entries
                          .where(
                            (entry) => entry.key.toLowerCase() == 'referer',
                          );
                      final referrer = referrers.isEmpty
                          ? null
                          : Uri.tryParse(referrers.first.value);
                      final source =
                          referrer != null &&
                              {'http', 'https'}.contains(referrer.scheme)
                          ? referrer
                          : _currentUrl ?? widget.site.url;
                      final result = await AdGuardEngine.instance
                          .evaluateRequest(
                            _filterContext(
                              url,
                              source,
                              type: adGuardResourceType(request.headers),
                              method: request.method,
                            ),
                          );
                      if (!mounted ||
                          epoch != _navigationEpoch ||
                          result?['block'] != true) {
                        return null;
                      }
                      final resource =
                          AdGuardEngine.instance.redirects[result?['redirect']];
                      final mime = resource?['contentType'] as String?;
                      final content = resource?['content'] as String?;
                      return WebResourceResponse(
                        contentType:
                            mime?.replaceAll(';base64', '') ?? 'text/plain',
                        contentEncoding: mime?.endsWith(';base64') == true
                            ? null
                            : 'utf-8',
                        statusCode: resource != null ? 200 : 204,
                        reasonPhrase: resource != null ? 'OK' : 'No Content',
                        data: content == null
                            ? Uint8List(0)
                            : mime!.endsWith(';base64')
                            ? base64Decode(content)
                            : Uint8List.fromList(utf8.encode(content)),
                      );
                    },
                    onRenderProcessGone: (_, _) {
                      _controller = null;
                      if (mounted) {
                        setState(
                          () => _error = 'หน้าเว็บหยุดทำงาน · โหลดหน้าใหม่เพื่อลองอีกครั้ง',
                        );
                      }
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
                      _navigationEpoch++;
                      _currentUrl = url?.uriValue;
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
                      _currentUrl = url?.uriValue ?? _currentUrl;
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
                  if (widget.settings.blockAdsEnabled && _adguardScript == null)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: Material(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'AdGuard ไม่พร้อมใช้งาน · กฎเฉพาะเว็บยังทำงาน',
                          ),
                        ),
                      ),
                    ),
                  if (_error != null)
                    _ErrorView(
                      message: _error!,
                      onRetry: () {
                        setState(() => _error = null);
                        if (_controller == null) {
                          _reloadProtection();
                        } else {
                          _controller?.reload();
                        }
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
