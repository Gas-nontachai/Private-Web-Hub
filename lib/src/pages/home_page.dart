import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/settings.dart';
import '../core/updates.dart';
import '../theme/theme.dart';
import 'browser_page.dart';
import 'history_page.dart';
import 'settings_page.dart';

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => checkForUpdates(context, manual: false),
    );
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
              borderRadius: BorderRadius.circular(Design.panelRadius),
              border: Border.all(color: Palette.border),
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
                            fontSize: Design.headingSize,
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
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Design.siteGap),
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
        borderRadius: BorderRadius.circular(Design.linkRadius),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: Design.transitionMs),
          constraints: const BoxConstraints(minHeight: Design.linkMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Design.paddingX,
            vertical: Design.paddingY,
          ),
          decoration: BoxDecoration(
            color: _active ? Palette.accentSoft : Colors.white,
            borderRadius: BorderRadius.circular(Design.linkRadius),
            border: Border.all(
              color: _active ? Palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: Design.transitionMs),
                width: Design.markSize,
                height: Design.markSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _active ? Palette.accent : Palette.mark,
                  borderRadius: BorderRadius.circular(Design.markRadius),
                ),
                child: Text(
                  site.mark,
                  style: TextStyle(
                    fontSize: Design.markFontSize,
                    fontWeight: FontWeight.w600,
                    color: _active ? Palette.markHover : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: Design.contentGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: Design.nameSize,
                        fontWeight: FontWeight.w600,
                        color: Palette.ink,
                      ),
                    ),
                    Text(
                      site.url.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: Design.hostSize,
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
