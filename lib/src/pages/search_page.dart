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
  late final List<BrowserLoadState> _states = List.filled(
    _sites.length,
    BrowserLoadState.loading,
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: _sites.length,
    child: Builder(
      builder: (context) {
        final tabs = DefaultTabController.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text('ผลค้นหา: ${widget.query}'),
            bottom: TabBar(
              isScrollable: true,
              tabs: [
                for (var i = 0; i < _sites.length; i++)
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _statusIcon(_states[i]),
                        const SizedBox(width: 8),
                        Text(_sites[i].name),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          body: AnimatedBuilder(
            animation: tabs,
            builder: (context, _) => IndexedStack(
              index: tabs.index,
              children: [
                for (var i = 0; i < _sites.length; i++)
                  BrowserPage(
                    key: ValueKey(_sites[i].id),
                    site: _sites[i],
                    catalog: widget.catalog,
                    settings: widget.settings,
                    initialUrl: buildSearchUri(_sites[i], widget.query),
                    handleSystemBack: i == tabs.index,
                    loadTimeout: const Duration(seconds: 12),
                    onLoadStateChanged: (state) {
                      if (_states[i] != state && mounted) {
                        setState(() => _states[i] = state);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

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
