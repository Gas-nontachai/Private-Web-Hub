import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/settings.dart';
import '../core/updates.dart';
import '../theme/theme.dart';
import 'browser_page.dart';
import 'history_page.dart';
import 'library_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.catalog, required this.settings});
  final Catalog catalog;
  final SiteSettings settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _queries = ['', '', ''];
  final _search = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    widget.settings.faviconRevision.removeListener(_refreshFavicons);
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.settings.faviconRevision.addListener(_refreshFavicons);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => checkForUpdates(context, manual: false),
    );
  }

  void _refreshFavicons() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _explore(),
      LibraryPage(
        catalog: widget.catalog,
        settings: widget.settings,
        embedded: true,
        query: _queries[1],
      ),
      HistoryPage(
        catalog: widget.catalog,
        settings: widget.settings,
        embedded: true,
        query: _queries[2],
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: TextField(
          key: const ValueKey('unified-search'),
          controller: _search,
          decoration: InputDecoration(
            hintText: _tab == 0
                ? 'ค้นหาหนังและซีรีส์'
                : _tab == 1
                ? 'ค้นหาในรายการบันทึก'
                : 'ค้นหาในประวัติ',
            prefixIcon: IconButton(
              tooltip: 'ค้นหาจากเว็บไซต์',
              icon: const Icon(Icons.search),
              onPressed: () {
                FocusScope.of(context).unfocus();
                _startSearch();
              },
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          onChanged: (value) {
            setState(() => _queries[_tab] = value);
          },
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            if (_tab == 0) _startSearch();
          },
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) async {
              if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      catalog: widget.catalog,
                      settings: widget.settings,
                    ),
                  ),
                );
              } else if (value == 'clear-history') {
                final clear = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('ล้างประวัติ?'),
                    content: const Text('รายการโปรดและดูภายหลังจะยังคงอยู่'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('ยกเลิก'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('ล้าง'),
                      ),
                    ],
                  ),
                );
                if (clear == true) {
                  await widget.settings.clearHistory();
                  if (mounted) setState(() {});
                }
              }
            },
            itemBuilder: (_) => [
              if (_tab == 2 && widget.settings.history.isNotEmpty)
                const PopupMenuItem(
                  value: 'clear-history',
                  child: Text('ล้างประวัติ'),
                ),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() {
            _tab = index;
            _search.text = _queries[index];
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favorites',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }

  Widget _explore() => GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 14,
      mainAxisSpacing: 18,
      childAspectRatio: .82,
    ),
    itemCount: widget.catalog.sites.length,
    itemBuilder: (context, index) {
      final site = widget.catalog.sites[index];
      return Semantics(
        button: true,
        label: '${site.name}, ${site.url.host}',
        child: InkWell(
          key: ValueKey('site-${site.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BrowserPage(
                site: site,
                catalog: widget.catalog,
                settings: widget.settings,
              ),
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Palette.appSurface,
                    border: Border.all(color: Palette.appTextMuted, width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.settings.favicon(site.id) case final icon?)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Image.memory(
                            icon,
                            fit: BoxFit.contain,
                            cacheWidth: 256,
                            errorBuilder: (_, _, _) => _siteMark(site.mark),
                          ),
                        )
                      else
                        _siteMark(site.mark),
                      Positioned(
                        top: 5,
                        right: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Palette.appSurfaceActive,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              site.category,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                site.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                site.url.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Palette.appTextMuted,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _siteMark(String mark) => Center(
    child: Text(
      mark,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Palette.appText,
        fontSize: mark.length > 3 ? 22 : 36,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  void _startSearch() {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(
          catalog: widget.catalog,
          settings: widget.settings,
          query: query,
        ),
      ),
    );
  }
}
