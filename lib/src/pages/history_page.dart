import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/settings.dart';
import 'browser_page.dart';

String _thaiDateTime(DateTime value) {
  const months = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  final local = value.toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$time ${local.day} ${months[local.month - 1]} ${local.year + 543}';
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({
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
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    if (await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear history?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ==
        true) {
      await widget.settings.clearHistory();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.embedded ? widget.query : _query.text;
    final history = widget.settings.history
        .where(
          (e) => '${e.title} ${e.url}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    final content = Column(
      children: [
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ค้นหาในประวัติ',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        Expanded(
          child: history.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 76, color: Colors.white70),
                      SizedBox(height: 20),
                      Text(
                        'ยังไม่มีประวัติ',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'หน้าเว็บที่เปิดจะปรากฏที่นี่',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    final site = widget.catalog.sites
                        .where((s) => s.id == entry.siteId)
                        .firstOrNull;
                    final uri = Uri.tryParse(entry.url);
                    return ListTile(
                      title: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${site?.name ?? uri?.host ?? ''} · ${_thaiDateTime(entry.visitedAt)}',
                      ),
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
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await widget.settings.removeVisit(entry);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('History'),
              actions: [
                if (history.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear history',
                    icon: const Icon(Icons.delete_sweep),
                    onPressed: _clear,
                  ),
              ],
            ),
      body: content,
    );
  }
}
