import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/catalog.dart';
import '../core/settings.dart';
import '../core/updates.dart';
import '../theme/theme.dart';

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
  String? _appVersion;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await installedVersion();
      if (mounted) setState(() => _appVersion = version);
    } catch (_) {}
  }

  Future<void> _checkUpdates() async {
    setState(() => _checking = true);
    try {
      await checkForUpdates(context);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear browsing data?'),
        content: const Text(
          'This clears cookies, cache and website storage. History and saved pages stay on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'Make Movie.exe yours',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Control browsing rules and local website data.',
            style: TextStyle(color: Palette.appTextMuted),
          ),
          const SizedBox(height: 26),
          _sectionTitle(Icons.shield_outlined, 'Browsing rules'),
          const SizedBox(height: 10),
          _group([
            SwitchListTile(
              key: const ValueKey('toggle-global'),
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: const Text('All sites'),
              subtitle: const Text('Auto-skip ad buttons on every site'),
              value: widget.settings.globalEnabled,
              onChanged: (v) async {
                await widget.settings.setGlobalEnabled(v);
                if (mounted) setState(() {});
              },
            ),
            for (final site in catalog.sites) ...[
              const Divider(height: 1, indent: 72),
              SwitchListTile(
                key: ValueKey('toggle-${site.id}'),
                secondary: CircleAvatar(
                  backgroundColor: Palette.appSurfaceActive,
                  child: Text(
                    site.mark,
                    style: const TextStyle(
                      color: Palette.appText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(site.name),
                subtitle: Text(
                  '${site.url.host} · ${site.rules.length} rule(s)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                value: widget.settings.isEnabled(site),
                onChanged: (v) async {
                  await widget.settings.setEnabled(site, v);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ]),
          const SizedBox(height: 26),
          _sectionTitle(Icons.tune, 'App & data'),
          const SizedBox(height: 10),
          _group([
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.orangeAccent,
              ),
              title: const Text('Clear browsing data'),
              subtitle: const Text('Cookies, cache and website storage'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _clearData,
            ),
            const Divider(height: 1, indent: 72),
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('Check for updates'),
              subtitle: Text(
                _appVersion == null
                    ? 'Version unavailable'
                    : 'Installed version $_appVersion',
              ),
              trailing: _checking
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _checking ? null : _checkUpdates,
            ),
            const Divider(height: 1, indent: 72),
            ListTile(
              leading: const Icon(Icons.rule_folder_outlined),
              title: const Text('Rule version'),
              subtitle: Text('Catalog ${catalog.version}'),
              trailing: const Icon(Icons.verified_outlined),
            ),
          ]),
          const SizedBox(height: 18),
          Center(
            child: Text(
              _appVersion == null ? 'Movie.exe' : 'Movie.exe · $_appVersion',
              style: const TextStyle(color: Palette.appTextMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Palette.appTextMuted),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget _group(List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    color: Palette.appSurface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}
