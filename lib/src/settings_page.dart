import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'catalog.dart';
import 'settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.catalog,
    required this.settings,
  });
  final Catalog catalog;
  final SiteSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _clearData() async {
    final messenger = ScaffoldMessenger.of(context);
    await CookieManager.instance().deleteAllCookies();
    await InAppWebViewController.clearAllCache();
    await WebStorageManager.instance().deleteAllData();
    messenger.showSnackBar(
      const SnackBar(content: Text('Browsing data cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Page rules'),
          ),
          SwitchListTile(
            key: const ValueKey('toggle-global'),
            title: const Text('All sites'),
            subtitle: const Text('Auto-skip "ข้ามโฆษณา" buttons everywhere'),
            value: widget.settings.globalEnabled,
            onChanged: (v) async {
              await widget.settings.setGlobalEnabled(v);
              setState(() {});
            },
          ),
          for (final site in catalog.sites)
            SwitchListTile(
              key: ValueKey('toggle-${site.id}'),
              title: Text(site.name),
              subtitle: Text('${site.rules.length} rule(s)'),
              value: widget.settings.isEnabled(site),
              onChanged: (v) async {
                await widget.settings.setEnabled(site, v);
                setState(() {});
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear browsing data'),
            subtitle: const Text('Cookies, cache and site storage'),
            onTap: _clearData,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Rule version'),
            subtitle: Text(catalog.version),
          ),
        ],
      ),
    );
  }
}
