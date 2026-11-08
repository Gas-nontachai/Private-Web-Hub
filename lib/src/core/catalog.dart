import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

const supportedSchemaVersion = 1;
const allowedActionTypes = {'hide', 'clickWhenVisible', 'tapWhenVisible'};

class CatalogException implements Exception {
  CatalogException(this.message);
  final String message;
  @override
  String toString() => 'CatalogException: $message';
}

class RuleAction {
  const RuleAction({required this.type, required this.selectors});
  final String type;
  final List<String> selectors;

  Map<String, Object> toJson() => {'type': type, 'selectors': selectors};
}

class Rule {
  const Rule({
    required this.id,
    required this.hosts,
    required this.parentHosts,
    required this.enabled,
    required this.actions,
  });
  final String id;
  final List<String> hosts;
  final List<String>? parentHosts;
  final bool enabled;
  final List<RuleAction> actions;

  Map<String, Object> toJson() => {
    'id': id,
    'hosts': hosts,
    'parentHosts': ?parentHosts,
    'actions': actions.map((a) => a.toJson()).toList(),
  };
}

class Site {
  const Site({
    required this.id,
    required this.name,
    required this.category,
    required this.mark,
    required this.url,
    required this.hosts,
    required this.enabled,
    required this.rules,
    this.search,
  });
  final String id;
  final String name;
  final String category;
  final String mark;
  final Uri url;
  final List<String> hosts;
  final bool enabled;
  final List<Rule> rules;
  final SiteSearch? search;
}

class SiteSearch {
  const SiteSearch({required this.path, required this.queryKey});
  final String path;
  final String queryKey;
}

/// Builds a site's configured search URL with URI-safe query encoding.
Uri buildSearchUri(Site site, String query) {
  final search = site.search;
  if (search == null) {
    throw ArgumentError.value(site.id, 'site', 'No search URL configured');
  }
  return site.url.replace(
    path: search.path,
    queryParameters: {search.queryKey: query},
  );
}

class Catalog {
  const Catalog({
    required this.version,
    required this.sites,
    this.globalRules = const [],
  });
  final String version;
  final List<Site> sites;

  /// Rules applied on every host, in every frame.
  final List<Rule> globalRules;

  Set<String> get allowedHosts => {for (final s in sites) ...s.hosts};

  bool isAllowedHost(String host) => allowedHosts.contains(host.toLowerCase());

  static Future<Catalog> load([
    String path = 'assets/catalog/websites.json',
  ]) async => Catalog.parse(await rootBundle.loadString(path));

  static Catalog parse(String source) {
    final Object? root;
    try {
      root = jsonDecode(source);
    } on FormatException catch (e) {
      throw CatalogException('Invalid JSON: ${e.message}');
    }
    if (root is! Map<String, dynamic>) {
      throw CatalogException('Root must be an object');
    }
    if (root['schemaVersion'] != supportedSchemaVersion) {
      throw CatalogException('Unsupported schemaVersion');
    }
    final sites = [for (final s in _list(root, 'sites')) _site(_map(s))];
    if (sites.isEmpty) throw CatalogException('No sites configured');
    final ids = sites.map((s) => s.id).toSet();
    if (ids.length != sites.length) throw CatalogException('Duplicate site id');
    final globals = [
      for (final r in root['globalRules'] as List? ?? const [])
        _rule(_map(r), null),
    ];
    return Catalog(
      version: _str(root, 'version'),
      sites: sites,
      globalRules: globals,
    );
  }

  static Site _site(Map<String, dynamic> j) {
    final url = Uri.tryParse(_str(j, 'url'));
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw CatalogException('Site url must be https: ${j['url']}');
    }
    final hosts = _hosts(j);
    if (!hosts.contains(url.host)) {
      throw CatalogException('Site hosts must include ${url.host}');
    }
    final rules = [for (final r in _list(j, 'rules')) _rule(_map(r), hosts)];
    final searchJson = j['search'];
    final search = searchJson == null ? null : _search(_map(searchJson));
    return Site(
      id: _str(j, 'id'),
      name: _str(j, 'name'),
      category: j['category'] as String? ?? '',
      mark: _str(j, 'mark'),
      url: url,
      hosts: hosts,
      enabled: j['enabled'] != false,
      rules: rules,
      search: search,
    );
  }

  static SiteSearch _search(Map<String, dynamic> json) {
    final path = _str(json, 'path');
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw CatalogException('Search path must be site-relative');
    }
    return SiteSearch(path: path, queryKey: _str(json, 'queryKey'));
  }

  static Rule _rule(Map<String, dynamic> j, List<String>? siteHosts) {
    final hosts = _hosts(j);
    for (final h in hosts) {
      final ok = siteHosts == null ? h == '*' : siteHosts.contains(h);
      if (!ok) {
        throw CatalogException('Rule host $h is outside the site allowlist');
      }
    }
    final actions = <RuleAction>[];
    for (final a in _list(j, 'actions')) {
      final m = _map(a);
      final type = _str(m, 'type');
      if (!allowedActionTypes.contains(type)) {
        throw CatalogException('Unsupported action type: $type');
      }
      final selectors = [
        for (final s in _list(m, 'selectors'))
          if (s is String && s.isNotEmpty && s.length <= 200)
            s
          else
            throw CatalogException('Invalid selector'),
      ];
      actions.add(RuleAction(type: type, selectors: selectors));
    }
    return Rule(
      id: _str(j, 'id'),
      hosts: hosts,
      parentHosts: j.containsKey('parentHosts')
          ? _hosts(j, 'parentHosts')
          : null,
      enabled: j['enabled'] != false,
      actions: actions,
    );
  }

  static List<String> _hosts(Map<String, dynamic> j, [String key = 'hosts']) {
    final hosts = [
      for (final h in _list(j, key)) _str({'h': h}, 'h').toLowerCase(),
    ];
    if (hosts.isEmpty) throw CatalogException('$key must not be empty');
    return hosts;
  }

  static List<dynamic> _list(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v is! List) throw CatalogException('$key must be a list');
    return v;
  }

  static Map<String, dynamic> _map(Object? v) {
    if (v is! Map<String, dynamic>) throw CatalogException('Expected object');
    return v;
  }

  static String _str(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v is! String || v.isEmpty) throw CatalogException('$key must be text');
    return v;
  }
}

/// Builds the JS injected into pages from the enabled rules of enabled sites.
String buildRuleScript(
  String runtimeTemplate,
  Iterable<Site> sites,
  bool Function(Site) isEnabled, {
  Iterable<Rule> globalRules = const [],
}) {
  final rules = [
    for (final r in globalRules)
      if (r.enabled) r.toJson(),
    for (final s in sites)
      if (isEnabled(s))
        for (final r in s.rules)
          if (r.enabled) r.toJson(),
  ];
  // '<' is escaped so the JSON can never close a script context.
  final json = jsonEncode(rules).replaceAll('<', r'\u003c');
  return runtimeTemplate.replaceAll('__RULES__', json);
}

enum NavDecision { allowInApp, openExternal }

/// HTTPS-only, allowlisted hosts load in the app; everything else leaves it.
NavDecision decideNavigation(Uri uri, Catalog catalog) {
  final inApp = uri.scheme == 'https' && catalog.isAllowedHost(uri.host);
  return inApp ? NavDecision.allowInApp : NavDecision.openExternal;
}
