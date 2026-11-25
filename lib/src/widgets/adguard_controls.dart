import 'package:flutter/material.dart';

import '../core/ad_blocking.dart';
import '../core/settings.dart';

class AdGuardControls extends StatefulWidget {
  const AdGuardControls({
    super.key,
    required this.settings,
    required this.siteId,
  });
  final SiteSettings settings;
  final String siteId;

  @override
  State<AdGuardControls> createState() => _AdGuardControlsState();
}

class _AdGuardControlsState extends State<AdGuardControls> {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ValueListenableBuilder<AdGuardState>(
        valueListenable: AdGuardEngine.instance.state,
        builder: (_, state, _) => ListTile(
          leading: Icon(
            state == AdGuardState.ready
                ? Icons.verified_user
                : Icons.shield_outlined,
          ),
          title: const Text('AdGuard'),
          subtitle: Text(switch (state) {
            AdGuardState.ready =>
              '${AdGuardEngine.instance.rules} กฎ · บล็อกแล้ว ${AdGuardEngine.instance.blocked} request ในรอบนี้',
            AdGuardState.loading => 'กำลังเตรียมตัวกรองโฆษณา…',
            AdGuardState.failed =>
              'ตัวกรองไม่พร้อมใช้งาน · กฎเฉพาะเว็บยังทำงาน',
            AdGuardState.idle => 'ตัวกรองพร้อมเริ่มเมื่อเปิดเว็บ',
          }),
        ),
      ),
      for (final entry in const {
        'network': 'บล็อก request โฆษณาและ tracker',
        'cosmetic': 'ซ่อนองค์ประกอบโฆษณา',
        'scriptlets': 'ใช้ scriptlets ของ AdGuard',
      }.entries)
        SwitchListTile(
          key: ValueKey('adguard-${widget.siteId}-${entry.key}'),
          title: Text(entry.value),
          value: widget.settings.adGuardEnabled(widget.siteId, entry.key),
          onChanged: widget.settings.blockAdsEnabled
              ? (value) async {
                  await widget.settings.setAdGuardEnabled(
                    widget.siteId,
                    entry.key,
                    value,
                  );
                  if (mounted) setState(() {});
                }
              : null,
        ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Text(
          'โหลดหน้าใหม่หลังเปลี่ยนค่า · กฎซ่อนและข้ามโฆษณาของแอปควบคุมแยกกัน',
        ),
      ),
    ],
  );
}
