import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/settings.dart';
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
                  key == 'favorite'
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
        : ListView.builder(
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final entry = pages[index];
              final site = widget.catalog.sites
                  .where((s) => s.id == entry.siteId)
                  .firstOrNull;
              return ListTile(
                title: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  site?.name ?? Uri.tryParse(entry.url)?.host ?? '',
                ),
                onTap: site == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BrowserPage(
                            site: site,
                            catalog: widget.catalog,
                            settings: widget.settings,
                            initialUrl: Uri.tryParse(entry.url),
                          ),
                        ),
                      ),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await widget.settings.removeSavedPage(entry);
                    setState(() {});
                  },
                ),
              );
            },
          );
  }
}
