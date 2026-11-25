import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Only Android mobile uses this bridge; browser extensions keep browser playback.
class MediaPlayback extends ValueNotifier<bool> {
  MediaPlayback._() : super(false) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pip') value = call.arguments == true;
    });
  }
  static final instance = MediaPlayback._();
  static const channel = MethodChannel('mv/media');
  static int _nextOwner = 0;
  static String newOwner() => 'media-${++_nextOwner}';
  Future<void> attach(
    String owner,
    Iterable<String> hosts, {
    required bool allowSkip,
  }) =>
      _call('attach', owner, {'hosts': hosts.toList(), 'allowSkip': allowSkip});
  Future<void> detach(String owner) => _call('detach', owner);
  Future<void> _call(
    String method,
    String owner, [
    Map<String, Object>? options,
  ]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>(method, {'owner': owner, ...?options});
    } on MissingPluginException {
      // Widget tests have no Android media controller.
    }
  }
}
