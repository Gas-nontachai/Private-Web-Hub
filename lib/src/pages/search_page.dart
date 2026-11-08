import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/settings.dart';
import 'browser_page.dart';

// shortcut: results stay in source WebViews, replace when verified parsers are available.
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.catalog,
    required this.settings,
    required this.query,
  });
  final Catalog catalog;
  final SiteSettings settings;
  final String query;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final List<Site> _sites = widget.catalog.sites
      .where((site) => site.search != null)
      .toList();
  late final Set<String> _selectedSites = _sites.map((site) => site.id).toSet();
  final Set<String> _visitedSites = {};
  late final Map<String, BrowserLoadState> _states = {
    for (final site in _sites) site.id: BrowserLoadState.loading,
  };

  @override
  Widget build(BuildContext context) {
    final sites = _sites
        .where((site) => _selectedSites.contains(site.id))
        .toList();
    return DefaultTabController(
      key: ValueKey(sites.map((site) => site.id).join(',')),
      length: sites.length,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text('ผลค้นหา: ${widget.query}'),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(sites.isEmpty ? 52 : 104),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final site in _sites)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(site.name),
                                selected: _selectedSites.contains(site.id),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _selectedSites.add(site.id);
                                  } else {
                                    _selectedSites.remove(site.id);
                                  }
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (sites.isNotEmpty)
                      TabBar(
                        isScrollable: true,
                        tabs: [
                          for (final site in sites)
                            Tab(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _statusIcon(_states[site.id]!),
                                  const SizedBox(width: 8),
                                  Text(site.name),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            body: sites.isEmpty
                ? const Center(child: Text('เลือกเว็บเพื่อค้นหา'))
                : AnimatedBuilder(
                    animation: tabs,
                    builder: (context, _) {
                      final activeSite = sites[tabs.index];
                      _visitedSites.add(activeSite.id);
                      return IndexedStack(
                        index: tabs.index,
                        children: [
                          for (var i = 0; i < sites.length; i++)
                            if (_visitedSites.contains(sites[i].id))
                              BrowserPage(
                                key: ValueKey(sites[i].id),
                                site: sites[i],
                                catalog: widget.catalog,
                                settings: widget.settings,
                                initialUrl: buildSearchUri(
                                  sites[i],
                                  widget.query,
                                ),
                                handleSystemBack: i == tabs.index,
                                loadTimeout: const Duration(seconds: 12),
                                onLoadStateChanged: (state) {
                                  if (_states[sites[i].id] != state &&
                                      mounted) {
                                    setState(
                                      () => _states[sites[i].id] = state,
                                    );
                                  }
                                },
                              )
                            else
                              const SizedBox.expand(),
                        ],
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _statusIcon(BrowserLoadState state) => switch (state) {
    BrowserLoadState.loading => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    BrowserLoadState.loaded => const Icon(Icons.check_circle, size: 16),
    BrowserLoadState.failed => const Icon(Icons.error_outline, size: 16),
  };
}
