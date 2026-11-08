import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _versionChannel = MethodChannel('mv/app');
  String? _appVersion;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await _versionChannel.invokeMethod<String>('version');
      if (mounted) setState(() => _appVersion = version);
    } catch (_) {}
  }

  Future<void> _checkUpdates({bool manual = true}) async {
    setState(() => _checking = true);
    try {
      final client = HttpClient();
      final request = await client
          .getUrl(
            Uri.parse(
              'https://api.github.com/repos/Gas-nontachai/Private-Web-Hub/releases/latest',
            ),
          )
          .timeout(const Duration(seconds: 10));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await (await request.close().timeout(
        const Duration(seconds: 10),
      )).transform(utf8.decoder).join();
      client.close();
      final release = jsonDecode(response) as Map<String, dynamic>;
      final tag = release['tag_name'] as String? ?? '';
      final match = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$').firstMatch(tag);
      final asset = (release['assets'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((a) => a['name'] == 'Movie.exe-$tag.apk')
          .firstOrNull;
      if (match == null || asset == null) {
        throw Exception('No valid APK release found');
      }
      final latest = List<int>.generate(3, (i) => int.parse(match[i + 1]!));
      final currentMatch = RegExp(r'^(\d+)\.(\d+)\.(\d+)$')
          .firstMatch(_appVersion ?? '');
      if (currentMatch == null) throw Exception('App version unavailable');
      final current = List<int>.generate(
        3,
        (i) => int.parse(currentMatch[i + 1]!),
      );
      var comparison = 0;
      for (var i = 0; i < 3 && comparison == 0; i++) {
        comparison = latest[i].compareTo(current[i]);
      }
      if (comparison > 0 && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Update available'),
            content: Text('Installed: ${_appVersion!}\nLatest: $tag'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse(asset['browser_download_url'] as String),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text('Download'),
              ),
            ],
          ),
        );
      } else if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have the latest version')),
        );
      }
    } catch (e) {
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check for updates: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _clearData() async {
    final messenger = ScaffoldMessenger.of(context);
    await CookieManager.instance().deleteAllCookies();
    await InAppWebViewController.clearAllCache();
    await WebStorageManager.instance().deleteAllData();
    await widget.settings.clearHistory();
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
            subtitle: const Text('Cookies, cache, site storage and history'),
            onTap: _clearData,
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Check for updates'),
            subtitle: Text(
              _appVersion == null
                  ? 'Version unavailable'
                  : 'Version $_appVersion',
            ),
            trailing: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _checking ? null : () => _checkUpdates(),
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
