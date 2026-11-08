import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<String?> installedVersion() =>
    const MethodChannel('mv/app').invokeMethod<String>('version');

class AppUpdate {
  const AppUpdate(this.tag, this.url);
  final String tag;
  final Uri url;
}

AppUpdate? parseUpdate(Map<String, dynamic> release, String installed) {
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
      .where((a) => a['name'] == 'Movie.exe-$tag.apk')
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

Future<AppUpdate?> fetchUpdate(String installed, {HttpClient? client}) async {
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
      return parseUpdate(release as Map<String, dynamic>, installed);
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
    final update = await fetchUpdate(installed);
    if (!context.mounted) return;
    if (update == null) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have the latest version')),
        );
      }
      return;
    }
    await showDialog<void>(
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
              Navigator.pop(context);
              launchUrl(update.url, mode: LaunchMode.externalApplication);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check for updates: $error')),
      );
    }
  }
}
