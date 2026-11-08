import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

/// Per-site local toggle for rules; falls back to the catalog default.
class SiteSettings {
  SiteSettings(this._prefs);
  final SharedPreferences _prefs;

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
