import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';

const remoteActions = {
  'up',
  'down',
  'left',
  'right',
  'ok',
  'back',
  'home',
  'cursor',
  'move',
  'scrollUp',
  'scrollDown',
  'status',
  'open',
};

/// Validate commands again at the receiver, even after the native TLS handshake.
Map<String, dynamic> validateRemoteCommand(Object? value, Catalog catalog) {
  if (value is! Map || !remoteActions.contains(value['action'])) {
    throw const FormatException('Unsupported command');
  }
  final command = Map<String, dynamic>.from(value);
  if (command['action'] == 'open') {
    final raw = command['url'];
    final uri = raw is String && raw.length <= 8192 ? Uri.tryParse(raw) : null;
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        decideNavigation(uri, catalog) != NavDecision.allowInApp) {
      throw const FormatException('URL is not allowed on TV');
    }
  }
  if (command['action'] == 'move') {
    for (final key in ['dx', 'dy']) {
      final n = command[key];
      if (n is! num || !n.isFinite || n.abs() > 1) {
        throw const FormatException('Invalid pointer movement');
      }
    }
  }
  return command;
}

final remoteRoutes = RouteObserver<PageRoute<dynamic>>();

class TvRemoteLink extends ChangeNotifier {
  static final instance = TvRemoteLink();
  static const channel = MethodChannel('mv/remote');
  final navigatorKey = GlobalKey<NavigatorState>();
  bool isTv = false;
  bool connected = false;
  bool cursor = true;
  bool browserOpen = false;
  bool busy = false;
  String? error;
  String? fingerprint;
  String? host;
  int port = 47831;
  String loadState = 'idle';
  List<Map<String, dynamic>> devices = [];
  Map<String, dynamic>? pairing;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? onCommand;
  Future<bool> Function(Map<String, dynamic>)? onPairRequest;
  Timer? _heartbeat;

  Future<void> initialize() async {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'command':
          if (onCommand == null) throw PlatformException(code: 'unavailable');
          try {
            return await onCommand!(
              Map<String, dynamic>.from(call.arguments as Map),
            );
          } on FormatException catch (e) {
            throw PlatformException(code: 'invalid', message: e.message);
          }
        case 'pairRequest':
          final data = Map<String, dynamic>.from(call.arguments as Map);
          final allow = await onPairRequest?.call(data) ?? false;
          await channel.invokeMethod('approve', {
            'id': data['id'],
            'allow': allow,
          });
        case 'devices':
          devices = [
            for (final d in call.arguments as List)
              Map<String, dynamic>.from(d as Map),
          ];
          notifyListeners();
        case 'receiverError':
        case 'discoveryError':
          error = call.arguments as String?;
          notifyListeners();
        case 'cursor':
          cursor = call.arguments == true;
          notifyListeners();
      }
    });
    try {
      final info = await channel.invokeMapMethod<String, dynamic>('info');
      isTv = info?['isTv'] == true;
      if (isTv && await permission()) await channel.invokeMethod('start');
    } on MissingPluginException {
      /* Widget tests and non-Android previews. */
    } on PlatformException catch (e) {
      error = e.message;
    } on FormatException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  Future<bool> permission() async {
    final allowed = await channel.invokeMethod<bool>('permission') == true;
    if (!allowed) {
      throw const FormatException('กรุณาอนุญาตการเข้าถึงเครือข่ายใน Settings');
    }
    return allowed;
  }

  Future<void> discover() async {
    await permission();
    error = null;
    await channel.invokeMethod('discover');
  }

  Future<void> beginPairing() async {
    await permission();
    await channel.invokeMethod('start');
    pairing = await channel.invokeMapMethod<String, dynamic>('pairing');
    notifyListeners();
  }

  Future<void> endPairing() async {
    pairing = null;
    await channel.invokeMethod('endPairing');
    notifyListeners();
  }

  Future<void> connect(
    String address,
    int targetPort, {
    bool pairing = false,
  }) async {
    await permission();
    _heartbeat?.cancel();
    connected = false;
    host = address;
    port = targetPort;
    final result = await channel.invokeMapMethod<String, dynamic>('connect', {
      'host': address,
      'port': targetPort,
      'pairing': pairing,
    });
    fingerprint = result?['fingerprint'] as String?;
    connected = result?['paired'] == true;
    error = null;
    if (connected) _startHeartbeat();
    notifyListeners();
  }

  Future<void> pair(String code) async {
    await channel.invokeMethod('pair', {'code': code});
    connected = true;
    error = null;
    _startHeartbeat();
    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) {
      if (connected && !busy) {
        unawaited(
          send({'action': 'status'})
              .catchError((Object _) => <String, dynamic>{}),
        );
      }
    });
  }

  Future<Map<String, dynamic>> send(Map<String, dynamic> command) async {
    if (!connected) throw const FormatException('เชื่อมต่อ TV ก่อน');
    if (busy) throw const FormatException('กำลังส่งคำสั่ง กรุณาลองอีกครั้ง');
    busy = true;
    try {
      final state =
          await channel.invokeMapMethod<String, dynamic>('send', {
            'command': command,
          }) ??
          {};
      loadState = state['loadState'] as String? ?? loadState;
      cursor = state['cursor'] as bool? ?? cursor;
      browserOpen = state['browser'] as bool? ?? browserOpen;
      error = null;
      return state;
    } catch (e) {
      if (e is PlatformException && e.code == 'rejected') {
        error = e.message;
        rethrow;
      }
      connected = false;
      _heartbeat?.cancel();
      error = 'ขาดการเชื่อมต่อ ลองเชื่อมต่อ TV อีกครั้ง';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _heartbeat?.cancel();
    connected = false;
    await channel.invokeMethod('disconnect');
    notifyListeners();
  }

  Future<void> input(Map<String, dynamic> command) =>
      channel.invokeMethod('input', command);
  Future<void> browser(bool active) async {
    if (isTv) await channel.invokeMethod('browser', {'active': active});
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}
