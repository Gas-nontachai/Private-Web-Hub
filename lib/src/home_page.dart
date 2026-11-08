import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'browser_page.dart';
import 'catalog.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.catalog, required this.settings});
  final Catalog catalog;
  final SiteSettings settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    try {
      final installed = await const MethodChannel('mv/app')
          .invokeMethod<String>('version');
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
      final installedMatch = RegExp(r'^(\d+)\.(\d+)\.(\d+)$')
          .firstMatch(installed ?? '');
      if (!mounted ||
          match == null ||
          installedMatch == null ||
          asset == null) {
        return;
      }
      final latest = List<int>.generate(3, (i) => int.parse(match[i + 1]!));
      final current = List<int>.generate(
        3,
        (i) => int.parse(installedMatch[i + 1]!),
      );
      var comparison = 0;
      for (var i = 0; i < 3 && comparison == 0; i++) {
        comparison = latest[i].compareTo(current[i]);
      }
      if (comparison <= 0) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update available'),
          content: Text('Installed: $installed\nLatest: $tag'),
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
    } catch (_) {
      /* Update checks must not block app use. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    final settings = widget.settings;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Palette.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Palette.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'เลือกเว็บไซต์',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'History',
                        icon: const Icon(Icons.history),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HistoryPage(
                              catalog: catalog,
                              settings: settings,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.settings),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SettingsPage(
                              catalog: catalog,
                              settings: settings,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: catalog.sites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, i) => _SiteLink(
                      site: catalog.sites[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BrowserPage(
                            site: catalog.sites[i],
                            catalog: catalog,
                            settings: settings,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SiteLink extends StatefulWidget {
  const _SiteLink({required this.site, required this.onTap});
  final Site site;
  final VoidCallback onTap;

  @override
  State<_SiteLink> createState() => _SiteLinkState();
}

class _SiteLinkState extends State<_SiteLink> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return GestureDetector(
      onTapDown: (_) => setState(() => _active = true),
      onTapCancel: () => setState(() => _active = false),
      onTapUp: (_) => setState(() => _active = false),
      child: InkWell(
        key: ValueKey('site-${site.id}'),
        borderRadius: BorderRadius.circular(9),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: _active ? Palette.accentSoft : Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _active ? Palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _active ? Palette.accent : Palette.mark,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  site.mark,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _active ? Palette.markHover : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Palette.ink,
                      ),
                    ),
                    Text(
                      site.url.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 3),
                child: Icon(Icons.chevron_right, size: 20, color: Palette.mark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
