import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'browsing_data.dart';

/// Per-site local toggle for rules; falls back to the catalog default.
class SiteSettings {
  SiteSettings(this._prefs) : browsing = BrowsingData(_prefs);
  final SharedPreferences _prefs;
  final BrowsingData browsing;
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

  static Future<SiteSettings> load() async =>
      SiteSettings(await SharedPreferences.getInstance());

  bool isEnabled(Site site) =>
      _prefs.getBool('rules_enabled_${site.id}') ?? site.enabled;

  bool get globalEnabled => _prefs.getBool('rules_enabled_global') ?? true;
  bool get blockAdsEnabled => _prefs.getBool('block_ads_enabled') ?? true;

  Future<void> setBlockAdsEnabled(bool value) =>
      _prefs.setBool('block_ads_enabled', value);

  bool adGuardEnabled(String siteId, String feature) =>
      _prefs.getBool('adguard_${siteId}_$feature') ?? true;

  Future<void> setAdGuardEnabled(String siteId, String feature, bool value) {
    if (!{'network', 'cosmetic', 'scriptlets'}.contains(feature)) {
      throw ArgumentError.value(feature, 'feature');
    }
    return _prefs.setBool('adguard_${siteId}_$feature', value);
  }

  Future<void> setGlobalEnabled(bool value) =>
      _prefs.setBool('rules_enabled_global', value);

  Future<void> setEnabled(Site site, bool value) =>
      _prefs.setBool('rules_enabled_${site.id}', value);

  Set<String>? get searchSites => _prefs.getStringList('search_sites')?.toSet();

  Future<void> setSearchSites(Set<String> siteIds) =>
      _prefs.setStringList('search_sites', siteIds.toList());
}
