import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

/// Per-site local toggle for rules; falls back to the catalog default.
class SiteSettings {
  SiteSettings(this._prefs);
  final SharedPreferences _prefs;
  final faviconRevision = ValueNotifier<int>(0);

  Uint8List? favicon(String siteId) {
    final value = _prefs.getString('site_favicon_$siteId');
    if (value == null) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveFavicon(String siteId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 512 * 1024) return;
    await _prefs.setString('site_favicon_$siteId', base64Encode(bytes));
    faviconRevision.value++;
  }

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
    final identity = normalizeIdentityUrl(url);
    final entries = history.where((e) {
      final oldUrl = Uri.tryParse(e.url);
      return e.siteId != site.id ||
          oldUrl == null ||
          normalizeIdentityUrl(oldUrl) != identity;
    }).toList();
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

  List<SavedPage> savedPages(String collection) {
    try {
      final values =
          jsonDecode(_prefs.getString('saved_pages') ?? '[]') as List;
      return [
        for (final value in values)
          if (value is Map<String, dynamic> &&
              value['collection'] == collection)
            SavedPage.fromJson(value),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> toggleSavedPage(
    Site site,
    Uri url,
    String title,
    String collection, {
    String? posterUrl,
  }) async {
    final identity = normalizeIdentityUrl(url);
    final pages = <SavedPage>[];
    try {
      final values =
          jsonDecode(_prefs.getString('saved_pages') ?? '[]') as List;
      pages.addAll(
        values.whereType<Map<String, dynamic>>().map(SavedPage.fromJson),
      );
    } catch (_) {}
    final existing = pages.indexWhere(
      (p) =>
          p.siteId == site.id &&
          p.identityUrl == identity &&
          p.collection == collection,
    );
    if (existing >= 0) {
      pages.removeAt(existing);
    } else {
      pages.insert(
        0,
        SavedPage(
          siteId: site.id,
          url: url.toString(),
          identityUrl: identity,
          title: title.trim().isEmpty ? url.host : title.trim(),
          posterUrl: posterUrl,
          collection: collection,
          savedAt: DateTime.now(),
        ),
      );
    }
    await _prefs.setString(
      'saved_pages',
      jsonEncode(pages.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> removeSavedPage(SavedPage entry) async {
    final values = savedPages(entry.collection)
        .where((p) => p != entry)
        .toList();
    final other = _allSavedPages().where(
      (p) => p.collection != entry.collection,
    );
    await _prefs.setString(
      'saved_pages',
      jsonEncode([...values, ...other].map((p) => p.toJson()).toList()),
    );
  }

  List<SavedPage> _allSavedPages() {
    try {
      return (jsonDecode(_prefs.getString('saved_pages') ?? '[]') as List)
          .whereType<Map<String, dynamic>>()
          .map(SavedPage.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<SiteSettings> load() async =>
      SiteSettings(await SharedPreferences.getInstance());

  bool isEnabled(Site site) =>
      _prefs.getBool('rules_enabled_${site.id}') ?? site.enabled;

  bool get globalEnabled => _prefs.getBool('rules_enabled_global') ?? true;

  Future<void> setGlobalEnabled(bool value) =>
      _prefs.setBool('rules_enabled_global', value);

  Future<void> setEnabled(Site site, bool value) =>
      _prefs.setBool('rules_enabled_${site.id}', value);

  Set<String>? get searchSites => _prefs.getStringList('search_sites')?.toSet();

  Future<void> setSearchSites(Set<String> siteIds) =>
      _prefs.setStringList('search_sites', siteIds.toList());
}

String normalizeIdentityUrl(Uri url) => url
    .replace(
      scheme: url.scheme.toLowerCase(),
      host: url.host.toLowerCase(),
      fragment: '',
    )
    .toString();

class SavedPage {
  const SavedPage({
    required this.siteId,
    required this.url,
    required this.identityUrl,
    required this.title,
    required this.collection,
    required this.savedAt,
    this.posterUrl,
  });
  final String siteId, url, identityUrl, title, collection;
  final String? posterUrl;
  final DateTime savedAt;
  Map<String, Object?> toJson() => {
    'siteId': siteId,
    'url': url,
    'identityUrl': identityUrl,
    'title': title,
    'posterUrl': posterUrl,
    'collection': collection,
    'savedAt': savedAt.toIso8601String(),
  };
  factory SavedPage.fromJson(Map<String, dynamic> json) => SavedPage(
    siteId: json['siteId'] as String,
    url: json['url'] as String,
    identityUrl: json['identityUrl'] as String,
    title: json['title'] as String,
    posterUrl: json['posterUrl'] as String?,
    collection: json['collection'] as String,
    savedAt: DateTime.parse(json['savedAt'] as String),
  );
  @override
  bool operator ==(Object other) =>
      other is SavedPage &&
      siteId == other.siteId &&
      identityUrl == other.identityUrl &&
      collection == other.collection;
  @override
  int get hashCode => Object.hash(siteId, identityUrl, collection);
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
