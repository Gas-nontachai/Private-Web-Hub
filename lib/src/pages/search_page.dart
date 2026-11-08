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
  late final Set<String> _selectedSites = widget.settings.searchSites == null
      ? _sites.map((site) => site.id).toSet()
      : widget.settings.searchSites!
            .intersection(_sites.map((site) => site.id).toSet());
  late final Map<String, BrowserLoadState> _states = {
    for (final site in _sites) site.id: BrowserLoadState.loading,
  };

  Future<void> _showFilters() async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _SearchFilterDialog(
        sites: _sites,
        selectedSites: _selectedSites,
      ),
    );
    if (selected == null) return;
    await widget.settings.setSearchSites(selected);
    if (mounted) setState(() {
      _selectedSites
        ..clear()
        ..addAll(selected);
    });
  }

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
              actions: [
                IconButton(
                  tooltip: 'Filter',
                  icon: const Icon(Icons.filter_list),
                  onPressed: _showFilters,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(sites.isEmpty ? 0 : 48),
                child: sites.isEmpty
                    ? const SizedBox.shrink()
                    : TabBar(
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
              ),
            ),
            body: sites.isEmpty
                ? const Center(child: Text('เลือกเว็บเพื่อค้นหา'))
                : AnimatedBuilder(
                    animation: tabs,
                    builder: (context, _) {
                      final activeSite = sites[tabs.index];
                      return BrowserPage(
                        key: ValueKey(activeSite.id),
                        site: activeSite,
                        catalog: widget.catalog,
                        settings: widget.settings,
                        initialUrl: buildSearchUri(activeSite, widget.query),
                        loadTimeout: const Duration(seconds: 12),
                        onLoadStateChanged: (state) {
                          if (_states[activeSite.id] != state && mounted) {
                            setState(() => _states[activeSite.id] = state);
                          }
                        },
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

class _SearchFilterDialog extends StatefulWidget {
  const _SearchFilterDialog({required this.sites, required this.selectedSites});
  final List<Site> sites;
  final Set<String> selectedSites;

  @override
  State<_SearchFilterDialog> createState() => _SearchFilterDialogState();
}

class _SearchFilterDialogState extends State<_SearchFilterDialog> {
  late final Set<String> _selected = {...widget.selectedSites};
  late final List<String> _categories = widget.sites
      .map((site) => site.category)
      .toSet()
      .toList();
  late final Set<String> _selectedCategories = {..._categories};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filter'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category.isEmpty ? 'อื่นๆ' : category),
                      selected: _selectedCategories.contains(category),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _selectedCategories.add(category);
                        } else {
                          _selectedCategories.remove(category);
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final site in widget.sites.where(
                    (site) => _selectedCategories.contains(site.category),
                  ))
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(site.name),
                      value: _selected.contains(site.id),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(site.id);
                        } else {
                          _selected.remove(site.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _selected),
        child: const Text('Apply'),
      ),
    ],
  );
}
