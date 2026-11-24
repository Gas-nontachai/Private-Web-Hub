import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_remote.dart';

Future<String?> installedVersion() =>
    const MethodChannel('mv/app').invokeMethod<String>('version');

class AppUpdate {
  const AppUpdate(this.tag, this.url);
  final String tag;
  final Uri url;
}

AppUpdate? parseUpdate(
  Map<String, dynamic> release,
  String installed, {
  bool isTv = false,
}) {
  final tag = release['tag_name'];
  final latest = tag is String
      ? RegExp(r'^v(\d+)\.(\d+)\.(\d+)$').firstMatch(tag)
      : null;
  final current = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(installed);
  if (latest == null || current == null || release['assets'] is! List) {
    throw const FormatException('Invalid release or app version');
  }
  final asset = (release['assets'] as List)
      .whereType<Map<String, dynamic>>()
      .where((a) => a['name'] == 'Movie.exe-${isTv ? 'TV-' : ''}$tag.apk')
      .firstOrNull;
  final url = Uri.tryParse(asset?['browser_download_url'] as String? ?? '');
  if (url == null || url.scheme != 'https' || url.host.isEmpty) {
    throw const FormatException('No valid APK release found');
  }
  for (var i = 1; i <= 3; i++) {
    final comparison = int.parse(latest[i]!).compareTo(int.parse(current[i]!));
    if (comparison != 0) {
      return comparison > 0 ? AppUpdate(tag as String, url) : null;
    }
  }
  return null;
}

Future<AppUpdate?> fetchUpdate(
  String installed, {
  HttpClient? client,
  bool isTv = false,
}) async {
  final http = client ?? HttpClient();
  try {
    return await (() async {
      final request = await http.getUrl(
        Uri.parse(
          'https://api.github.com/repos/Gas-nontachai/Private-Web-Hub/releases/latest',
        ),
      );
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Release request failed: ${response.statusCode}');
      }
      final release = jsonDecode(await response.transform(utf8.decoder).join());
      return parseUpdate(
        release as Map<String, dynamic>,
        installed,
        isTv: isTv,
      );
    })().timeout(const Duration(seconds: 10));
  } finally {
    http.close(force: true);
  }
}

Future<void> checkForUpdates(BuildContext context, {bool manual = true}) async {
  try {
    final installed = await installedVersion();
    if (installed == null) {
      throw const FormatException('App version unavailable');
    }
    final update = await fetchUpdate(
      installed,
      isTv: TvRemoteLink.instance.isTv,
    );
    if (!context.mounted) return;
    if (update == null) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have the latest version')),
        );
      }
      return;
    }
    final download = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update available'),
        content: Text('Installed: $installed\nLatest: ${update.tag}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (download == true && context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDownloadDialog(update: update),
      );
    }
  } catch (error) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check for updates: $error')),
      );
    }
  }
}

Future<void> downloadUpdate(
  Uri url,
  File file, {
  required HttpClient client,
  required void Function(int received, int total) onProgress,
}) async {
  if (url.scheme != 'https' ||
      url.host != 'github.com' ||
      !url.path.startsWith(
        '/Gas-nontachai/Private-Web-Hub/releases/download/',
      ) ||
      !url.path.endsWith('.apk')) {
    throw const FormatException('Invalid update download URL');
  }
  IOSink? sink;
  try {
    final request = await client
        .getUrl(url)
        .timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Download failed: ${response.statusCode}');
    }
    sink = file.openWrite();
    var received = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      sink.add(chunk);
      // Keep writes bounded instead of buffering the entire APK in memory.
      await sink.flush();
      received += chunk.length;
      onProgress(received, response.contentLength);
    }
    await sink.close();
    sink = null;
    if (received == 0 ||
        (response.contentLength >= 0 && received != response.contentLength)) {
      throw const HttpException('Incomplete APK download');
    }
  } catch (_) {
    await sink?.close();
    if (await file.exists()) await file.delete();
    rethrow;
  }
}

class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog({super.key, required this.update});
  final AppUpdate update;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  static const channel = MethodChannel('mv/app');
  HttpClient? _client;
  int _received = 0;
  int _total = -1;
  bool _ready = false;
  bool _busy = true;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _download();
  }

  @override
  void dispose() {
    _client?.close(force: true);
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
      _received = 0;
      _total = -1;
    });
    final client = HttpClient();
    _client = client;
    try {
      final path = await channel.invokeMethod<String>('updatePath');
      if (path == null) {
        throw const FileSystemException('Update storage unavailable');
      }
      if (!mounted) return;
      await downloadUpdate(
        widget.update.url,
        File(path),
        client: client,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _ready = true;
        _busy = false;
      });
      await _install();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Download failed: $error';
          _busy = false;
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened = await channel.invokeMethod<bool>('installUpdate');
      if (!mounted) return;
      setState(() {
        _message = opened == true
            ? 'Confirm installation in Android. You can reopen the installer below.'
            : 'Allow installs from this app, then return and select Install.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not open installer: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(_ready ? 'Ready to install' : 'Downloading update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.update.tag),
            if (!_ready) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _error == null ? progress : 0,
                semanticsLabel: 'Update download',
              ),
              const SizedBox(height: 8),
              Text(
                '${(_received / 1048576).toStringAsFixed(1)} MB${progress == null ? '' : ' / ${(_total / 1048576).toStringAsFixed(1)} MB (${(progress * 100).floor()}%)'}',
              ),
            ],
            if (_message != null) Text(_message!),
            if (_error != null) Text(_error!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _client?.close(force: true);
              Navigator.pop(context);
            },
            child: Text(_ready ? 'Close' : 'Cancel'),
          ),
          if (!_busy && (_ready || _error != null))
            FilledButton(
              onPressed: _ready ? _install : _download,
              child: Text(_ready ? 'Install' : 'Retry'),
            ),
        ],
      ),
    );
  }
}
