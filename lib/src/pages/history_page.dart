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
  const HistoryPage({super.key, required this.catalog, required this.settings});
  final Catalog catalog;
  final SiteSettings settings;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
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
    final history = widget.settings.history;
    return Scaffold(
      appBar: AppBar(
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
      body: history.isEmpty
          ? const Center(child: Text('No history yet'))
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
    );
  }
}
