import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

/// Per-site local toggle for rules; falls back to the catalog default.
class SiteSettings {
  SiteSettings(this._prefs);
  final SharedPreferences _prefs;

  List<BrowseEntry> get history {
    try {
      final stored =
          jsonDecode(_prefs.getString('browse_history') ?? '[]') as List;
      final entries = <BrowseEntry>[];
      for (final item in stored) {
        try {
          if (item is Map<String, dynamic>) {
            entries.add(BrowseEntry.fromJson(item));
          }
        } catch (_) {}
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> recordVisit(Site site, Uri url, String? title) async {
    final uri = url.replace(fragment: '').toString();
    final entries = history.where((e) => e.url != uri).toList();
    entries.insert(
      0,
      BrowseEntry(
        siteId: site.id,
        url: uri,
        title: title?.trim().isNotEmpty == true ? title!.trim() : uri,
        visitedAt: DateTime.now(),
      ),
    );
    await _prefs.setString(
      'browse_history',
      jsonEncode(entries.take(500).map((e) => e.toJson()).toList()),
    );
  }

  Future<void> removeVisit(BrowseEntry entry) async {
    await _prefs.setString(
      'browse_history',
      jsonEncode(
        history
            .where((e) => e.url != entry.url)
            .map((e) => e.toJson())
            .toList(),
      ),
    );
  }

  Future<void> clearHistory() => _prefs.remove('browse_history');

  static Future<SiteSettings> load() async =>
      SiteSettings(await SharedPreferences.getInstance());

  bool isEnabled(Site site) =>
      _prefs.getBool('rules_enabled_${site.id}') ?? site.enabled;

  bool get globalEnabled => _prefs.getBool('rules_enabled_global') ?? true;

  Future<void> setGlobalEnabled(bool value) =>
      _prefs.setBool('rules_enabled_global', value);

  Future<void> setEnabled(Site site, bool value) =>
      _prefs.setBool('rules_enabled_${site.id}', value);
}

class BrowseEntry {
  const BrowseEntry({
    required this.siteId,
    required this.url,
    required this.title,
    required this.visitedAt,
  });
  final String siteId, url, title;
  final DateTime visitedAt;
  Map<String, Object> toJson() => {
    'siteId': siteId,
    'url': url,
    'title': title,
    'visitedAt': visitedAt.toIso8601String(),
  };
  factory BrowseEntry.fromJson(Map<String, dynamic> json) => BrowseEntry(
    siteId: json['siteId'] as String,
    url: json['url'] as String,
    title: json['title'] as String,
    visitedAt: DateTime.parse(json['visitedAt'] as String),
  );
}
