import 'package:flutter/material.dart';

import 'browser_page.dart';
import 'catalog.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.catalog, required this.settings});
  final Catalog catalog;
  final SiteSettings settings;

  @override
  Widget build(BuildContext context) {
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
