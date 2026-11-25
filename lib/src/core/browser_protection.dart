import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'ad_blocking.dart';
import 'catalog.dart';
import 'settings.dart';

class BrowserProtection {
  BrowserProtection({
    required this.catalog,
    required this.site,
    required this.settings,
    AdGuardEngine? engine,
  }) : _engine = engine ?? AdGuardEngine.instance;

  final Catalog catalog;
  final Site site;
  final SiteSettings settings;
  final AdGuardEngine _engine;

  String get settingsSnapshot => [
    settings.blockAdsEnabled,
    for (final feature in ['network', 'cosmetic', 'scriptlets'])
      settings.adGuardEnabled(site.id, feature),
    settings.globalEnabled,
    for (final site in catalog.sites) settings.isEnabled(site),
  ].join(':');

  Map<String, Object?> _context(
    Uri url,
    Uri source, {
    String type = 'Document',
    String? method,
  }) => {
    'url': url.toString(),
    'sourceUrl': source.toString(),
    'siteId': site.id,
    'host': (type == 'Document' ? url : source).host.toLowerCase(),
    'type': type,
    'method': method,
  };

  Future<Map<String, dynamic>?> pageRules(
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
    return _engine.getPageRules(
      _context(
        url,
        source != null && {'http', 'https'}.contains(source.scheme)
            ? source
            : url,
      ),
    );
  }

  Future<({UserScript rules, UserScript? adguard})> prepareScripts(
    Uri initial,
  ) async {
    final template = await rootBundle.loadString(
      'assets/runtime/rule_runtime.js',
    );
    UserScript? adguardScript;
    if (settings.blockAdsEnabled && await _engine.ensureReady()) {
      final page = await rootBundle.loadString('assets/adguard/page.js');
      final rules = await pageRules(initial.toString(), null);
      final owned = <String, List<String>>{};
      for (final site in catalog.sites) {
        if (!settings.isEnabled(site)) continue;
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
            'cosmetic': settings.adGuardEnabled(site.id, 'cosmetic'),
            'scriptlets': settings.adGuardEnabled(site.id, 'scriptlets'),
          }),
        ),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      );
    }
    return (
      adguard: adguardScript,
      rules: UserScript(
        source: buildRuleScript(
          template,
          catalog.sites,
          settings.isEnabled,
          globalRules: settings.globalEnabled ? catalog.globalRules : const [],
        ),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    );
  }

  Future<WebResourceResponse?> interceptRequest(
    WebResourceRequest request,
    Uri? currentUrl, {
    required bool Function() isCurrent,
  }) async {
    if (!settings.blockAdsEnabled ||
        !settings.adGuardEnabled(site.id, 'network') ||
        request.isForMainFrame == true) {
      return null;
    }
    final url = request.url.uriValue;
    if (!{'http', 'https'}.contains(url.scheme)) return null;
    final referrers = (request.headers ?? <String, String>{}).entries.where(
      (entry) => entry.key.toLowerCase() == 'referer',
    );
    final referrer = referrers.isEmpty
        ? null
        : Uri.tryParse(referrers.first.value);
    final source =
        referrer != null && {'http', 'https'}.contains(referrer.scheme)
        ? referrer
        : currentUrl ?? site.url;
    final result = await _engine.evaluateRequest(
      _context(
        url,
        source,
        type: adGuardResourceType(request.headers),
        method: request.method,
      ),
    );
    if (!isCurrent() || result?['block'] != true) {
      return null;
    }
    final resource = _engine.redirects[result?['redirect']];
    final mime = resource?['contentType'] as String?;
    final content = resource?['content'] as String?;
    return WebResourceResponse(
      contentType: mime?.replaceAll(';base64', '') ?? 'text/plain',
      contentEncoding: mime?.endsWith(';base64') == true ? null : 'utf-8',
      statusCode: resource != null ? 200 : 204,
      reasonPhrase: resource != null ? 'OK' : 'No Content',
      data: content == null
          ? Uint8List(0)
          : mime!.endsWith(';base64')
          ? base64Decode(content)
          : Uint8List.fromList(utf8.encode(content)),
    );
  }
}
