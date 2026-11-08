import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/settings.dart';
import '../theme/theme.dart';
import 'browser_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.catalog,
    required this.settings,
    this.embedded = false,
    this.query = '',
  });
  final Catalog catalog;
  final SiteSettings settings;
  final bool embedded;
  final String query;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Library'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'รายการโปรด'),
                  Tab(text: 'ดูภายหลัง'),
                ],
              ),
            ),
      body: Column(
        children: [
          if (widget.embedded)
            const TabBar(
              tabs: [
                Tab(text: 'รายการโปรด'),
                Tab(text: 'ดูภายหลัง'),
              ],
            ),
          if (!widget.embedded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ค้นหาในรายการบันทึก',
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [_collection('favorite'), _collection('watchLater')],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _collection(String key) {
    final query = widget.embedded ? widget.query : _query.text;
    final pages = widget.settings
        .savedPages(key)
        .where(
          (p) => '${p.title} ${Uri.tryParse(p.url)?.host ?? ''}'
              .toLowerCase()
              .contains(query.trim().toLowerCase()),
        )
        .toList();
    return pages.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  key == 'favorite'
                      ? Icons.favorite_border
                      : Icons.bookmark_border,
                  size: 76,
                  color: Colors.white70,
                ),
                const SizedBox(height: 20),
                Text(
                  query.trim().isNotEmpty
                      ? 'ไม่พบรายการที่ตรงกัน'
                      : key == 'favorite'
                      ? 'ยังไม่มีรายการโปรด'
                      : 'ยังไม่มีรายการดูภายหลัง',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'บันทึกหน้าเว็บจาก Explore แล้วจะแสดงที่นี่',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 600 ? 3 : 2;
              const spacing = 12.0;
              final width =
                  (constraints.maxWidth - 32 - spacing * (columns - 1)) /
                  columns;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: 18,
                  childAspectRatio: width / (width * 1.5 + 70),
                ),
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final entry = pages[index];
                  final site = widget.catalog.sites
                      .where((s) => s.id == entry.siteId)
                      .firstOrNull;
                  final uri = Uri.tryParse(entry.url);
                  return _SavedPageCard(
                    entry: entry,
                    sourceName: site?.name ?? uri?.host ?? '',
                    sourceMark: site?.mark ?? 'WEB',
                    onTap: site == null || uri == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BrowserPage(
                                site: site,
                                catalog: widget.catalog,
                                settings: widget.settings,
                                initialUrl: uri,
                              ),
                            ),
                          ),
                    onRemove: () async {
                      await widget.settings.removeSavedPage(entry);
                      if (mounted) setState(() {});
                    },
                  );
                },
              );
            },
          );
  }
}

class _SavedPageCard extends StatelessWidget {
  const _SavedPageCard({
    required this.entry,
    required this.sourceName,
    required this.sourceMark,
    required this.onTap,
    required this.onRemove,
  });
  final SavedPage entry;
  final String sourceName, sourceMark;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final poster = Uri.tryParse(entry.posterUrl ?? '');
    final posterUrl =
        poster != null && (poster.scheme == 'https' || poster.scheme == 'http')
        ? poster.toString()
        : null;
    return Semantics(
      button: true,
      label: '${entry.title}, $sourceName',
      child: Material(
        color: Palette.appSurface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl == null)
                      _PosterPlaceholder(mark: sourceMark)
                    else
                      Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _PosterPlaceholder(mark: sourceMark),
                      ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .76),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black.withValues(alpha: .65),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Remove from this list',
                          onPressed: onRemove,
                          icon: Icon(
                            entry.collection == 'favorite'
                                ? Icons.favorite
                                : Icons.bookmark,
                            size: 20,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Uri.tryParse(entry.url)?.host ?? sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Palette.appTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({required this.mark});
  final String mark;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Palette.appSurfaceActive,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.movie_outlined,
            size: 42,
            color: Palette.appTextMuted,
          ),
          const SizedBox(height: 8),
          Text(mark, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}
