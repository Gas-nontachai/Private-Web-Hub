import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_remote.dart';

String remoteError(Object error) => switch (error) {
  PlatformException(:final message) => message ?? 'เชื่อมต่อไม่สำเร็จ',
  FormatException(:final message) => message,
  _ => 'เชื่อมต่อไม่สำเร็จ กรุณาลองอีกครั้ง',
};

class TvRemotePage extends StatefulWidget {
  const TvRemotePage({super.key});
  @override
  State<TvRemotePage> createState() => _TvRemotePageState();
}

class _TvRemotePageState extends State<TvRemotePage> {
  final link = TvRemoteLink.instance;
  final _address = TextEditingController();
  bool _working = false;
  String? _message;
  Timer? _expiry;
  Timer? _moveTimer;
  Offset _pendingMove = Offset.zero;
  Future<void> _pointerFlight = Future.value();

  @override
  void initState() {
    super.initState();
    _address.text = link.host ?? '';
    unawaited(
      _run(() async {
        if (link.isTv) {
          await link.beginPairing();
        } else if (link.connected) {
          await link.send({'action': 'status'});
        } else {
          await link.discover();
        }
      }),
    );
    _moveTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!_working && !link.busy && _pendingMove != Offset.zero) {
        _pointerFlight = _flushPointer();
      }
    });
    _expiry = Timer(const Duration(minutes: 2), () {
      if (mounted && link.isTv) {
        unawaited(link.endPairing());
        setState(() => _message = 'รหัสหมดอายุ กดสร้างรหัสใหม่');
      }
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _moveTimer?.cancel();
    _address.dispose();
    if (link.isTv) {
      unawaited(link.endPairing());
    } else {
      unawaited(TvRemoteLink.channel.invokeMethod('stopDiscovery'));
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => _message = remoteError(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _connect(String host, int port) async {
    await _run(() async {
      try {
        await link.connect(host, port);
      } catch (_) {
        if (!mounted) return;
        final pair = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('จับคู่ TV'),
            content: const Text(
              'เปิด “จับคู่มือถือ” บน TV ก่อน หากเคยจับคู่แล้วแต่เชื่อมต่อไม่ได้ ให้ตรวจว่าแอปบน TV ยังเปิดอยู่',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('จับคู่ใหม่'),
              ),
            ],
          ),
        );
        if (pair != true) return;
        await link.connect(host, port, pairing: true);
        if (!mounted) return;
        final code = TextEditingController();
        final entered = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('กรอกรหัสจาก TV'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ตรวจเลขยืนยันให้ตรงกับ TV: ${link.fingerprint}'),
                const SizedBox(height: 16),
                TextField(
                  controller: code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'รหัส 6 หลัก'),
                  onSubmitted: (value) {
                    if (value.length == 6) Navigator.pop(context, value);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () {
                  if (code.text.length == 6) Navigator.pop(context, code.text);
                },
                child: const Text('รอการยืนยันบน TV'),
              ),
            ],
          ),
        );
        // The dialog's closing animation still owns its TextField for one frame.
        Future<void>.delayed(const Duration(seconds: 1), code.dispose);
        if (entered == null) {
          await link.disconnect();
          return;
        }
        if (mounted) {
          setState(
            () => _message = 'กรุณายืนยันบน TV และตรวจเลขยืนยันให้ตรงกัน',
          );
        }
        await link.pair(entered);
      }
    });
  }

  void _command(String action) {
    if (link.busy || _working) return;
    unawaited(
      _run(() async {
        await link.send({'action': action});
      }),
    );
  }

  Future<void> _flushPointer() async {
    if (!link.connected || link.busy || _pendingMove == Offset.zero) return;
    final delta = _pendingMove;
    _pendingMove = Offset.zero;
    try {
      await link.send({
        'action': 'move',
        'dx': delta.dx.clamp(-1, 1),
        'dy': delta.dy.clamp(-1, 1),
      });
    } catch (e) {
      if (mounted) setState(() => _message = remoteError(e));
    }
  }

  void _clickPointer() {
    unawaited(
      _run(() async {
        await _pointerFlight;
        while (link.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await _flushPointer();
        await link.send({'action': 'ok'});
      }),
    );
  }

  Widget _button(String action, IconData icon, String label) => SizedBox(
    width: 76,
    height: 64,
    child: IconButton.filledTonal(
      onPressed: _working ? null : () => _command(action),
      icon: Icon(icon),
      tooltip: label,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: link,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(link.isTv ? 'จับคู่มือถือ' : 'เชื่อมต่อ TV'),
        actions: [
          if (!link.isTv)
            IconButton(
              onPressed: _working ? null : () => _run(link.discover),
              icon: const Icon(Icons.refresh),
              tooltip: 'ค้นหาอีกครั้ง',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_working) const LinearProgressIndicator(),
          if (_message ?? link.error case final message?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(message, semanticsLabel: message),
            ),
          if (link.isTv) ...[
            const Text(
              'เปิดแอปบนมือถือ แล้วเลือก “เชื่อมต่อ TV”',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 16),
            if (link.pairing case final data?) ...[
              SelectableText(
                '${data['code']}',
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text('รหัสใช้ได้ 2 นาที · ${data['address']}:${data['port']}'),
              const SizedBox(height: 12),
              Text('เลขยืนยัน: ${data['fingerprint']}'),
              const Text('ก่อนอนุญาต ตรวจว่าเลขยืนยันบนมือถือและ TV ตรงกัน'),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _working
                  ? null
                  : () {
                      _expiry?.cancel();
                      _expiry = Timer(const Duration(minutes: 2), () {
                        if (mounted) unawaited(link.endPairing());
                      });
                      _run(link.beginPairing);
                    },
              child: const Text('สร้างรหัสใหม่'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _run(() async {
                final revoke = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('ยกเลิกสิทธิ์มือถือที่จับคู่?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('ยกเลิก'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('ยกเลิกสิทธิ์'),
                      ),
                    ],
                  ),
                );
                if (revoke == true) {
                  await TvRemoteLink.channel.invokeMethod('revoke');
                  await link.endPairing();
                }
              }),
              child: const Text('ยกเลิกสิทธิ์มือถือที่จับคู่'),
            ),
          ] else if (link.connected) ...[
            Text(
              'เชื่อมต่อ ${link.host}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(switch (link.loadState) {
              'loading' => 'TV กำลังโหลดหน้าเว็บ',
              'loaded' => 'TV เปิดหน้าเว็บแล้ว',
              'failed' => 'TV โหลดหน้าเว็บไม่สำเร็จ',
              _ => 'พร้อมควบคุม TV',
            }),
            Text(
              link.browserOpen && link.cursor
                  ? 'โหมดเคอร์เซอร์ · ลากเพื่อเล็งปุ่มบน TV'
                  : 'โหมดเลือกปุ่ม · ใช้ลูกศรและ OK',
            ),
            if (link.browserOpen && link.cursor) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => Semantics(
                  label: 'ทัชแพดควบคุม TV ลากเพื่อขยับตัวชี้ แตะเพื่อคลิก',
                  child: GestureDetector(
                    key: const ValueKey('tv-touchpad'),
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => _pendingMove += Offset(
                      details.delta.dx / constraints.maxWidth,
                      details.delta.dy / 160,
                    ),
                    onTap: _clickPointer,
                    child: Container(
                      height: 160,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: const Text(
                        'ลากเพื่อขยับตัวชี้บน TV\nแตะเพื่อคลิก',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  _button('up', Icons.keyboard_arrow_up, 'ขึ้น'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _button('left', Icons.keyboard_arrow_left, 'ซ้าย'),
                      const SizedBox(width: 8),
                      _button('ok', Icons.check_circle_outline, 'ตกลง / คลิก'),
                      const SizedBox(width: 8),
                      _button('right', Icons.keyboard_arrow_right, 'ขวา'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _button('down', Icons.keyboard_arrow_down, 'ลง'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _button('back', Icons.arrow_back, 'ย้อนกลับ'),
                _button('home', Icons.home_outlined, 'หน้าหลักแอป'),
                _button(
                  'cursor',
                  Icons.mouse_outlined,
                  'สลับเคอร์เซอร์ / เลือกปุ่ม',
                ),
                _button('scrollUp', Icons.vertical_align_top, 'เลื่อนหน้าขึ้น'),
                _button(
                  'scrollDown',
                  Icons.vertical_align_bottom,
                  'เลื่อนหน้าลง',
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'เปิดหน้าหนังในมือถือ แล้วกด “เปิดบน TV” บนแถบเครื่องมือ\nปิดมือถือได้ TV จะเล่นต่อเอง',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _run(link.disconnect),
              child: const Text('ตัดการเชื่อมต่อ'),
            ),
          ] else ...[
            const Text('เปิดแอป Movie.exe บน TV และใช้ Wi-Fi เดียวกัน'),
            for (final device in link.devices)
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(device['name'] as String),
                subtitle: Text(device['host'] as String),
                onTap: _working
                    ? null
                    : () => _connect(
                        device['host'] as String,
                        device['port'] as int,
                      ),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'IP ของ TV',
                hintText: '192.168.1.39',
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _connect(_address.text.trim(), 47831),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _working
                  ? null
                  : () => _connect(_address.text.trim(), 47831),
              child: const Text('เชื่อมต่อด้วย IP'),
            ),
          ],
        ],
      ),
    ),
  );
}
