import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'tray_service.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.changeTime,
    required this.downloadUrl,
    required this.changelog,
  });

  final String version;
  final String changeTime;
  final String downloadUrl;
  final String changelog;

  String get installerName {
    final uri = Uri.tryParse(downloadUrl);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return downloadUrl.split('/').last;
  }
}

enum UpdateCheckStatus { idle, updateAvailable, failed }

enum UpdateCheckFailureKind { none, offline, temporary, permanent }

enum UpdateCheckMode { background, userInitiated }

class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.status,
    required this.currentVersion,
    this.failureKind = UpdateCheckFailureKind.none,
    this.latest,
  });

  factory UpdateCheckResult.updateAvailable({
    required String currentVersion,
    required AppUpdateInfo latest,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.updateAvailable,
      currentVersion: currentVersion,
      latest: latest,
    );
  }

  factory UpdateCheckResult.failed({required String currentVersion}) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.failed,
      currentVersion: currentVersion,
      failureKind: UpdateCheckFailureKind.permanent,
    );
  }

  factory UpdateCheckResult.failedWithKind({
    required String currentVersion,
    required UpdateCheckFailureKind failureKind,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.failed,
      currentVersion: currentVersion,
      failureKind: failureKind,
    );
  }

  static const idle = UpdateCheckResult._(
    status: UpdateCheckStatus.idle,
    currentVersion: '',
  );

  final UpdateCheckStatus status;
  final String currentVersion;
  final UpdateCheckFailureKind failureKind;
  final AppUpdateInfo? latest;
}

class UpdateCheckService with UpdaterListener {
  UpdateCheckService({this.trayService = const TrayService()});

  static const _timeout = Duration(seconds: 10);
  static const _defaultUpdateBaseUrl =
      'https://gitee.com/radiant303/SpringNote/raw/main/update';
  static const _configuredUpdateBaseUrl = String.fromEnvironment(
    'SPRINGNOTE_UPDATE_BASE_URL',
  );
  static const _scheduledCheckIntervalSeconds = 6 * 60 * 60;

  final TrayService trayService;
  bool _autoUpdaterInitialized = false;

  Future<UpdateCheckResult> check({
    UpdateCheckMode mode = UpdateCheckMode.background,
  }) async {
    final currentVersion = await loadCurrentVersion();
    if (!_supportsNativeUpdater) {
      return UpdateCheckResult.failed(currentVersion: currentVersion);
    }

    try {
      await _initializeAutoUpdater();
      await autoUpdater.checkForUpdates(
        inBackground: mode == UpdateCheckMode.background,
      );
      return UpdateCheckResult.idle;
    } catch (_) {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.temporary,
      );
    }
  }

  Future<UpdateCheckResult> previewLatest() async {
    final currentVersion = await loadCurrentVersion();
    final endpoint = _platformEndpoint();
    if (endpoint == null) {
      return UpdateCheckResult.failed(currentVersion: currentVersion);
    }

    try {
      final updateJson = await _readUrl(endpoint);
      final decoded = jsonDecode(updateJson);
      if (decoded is! Map<String, Object?>) {
        return UpdateCheckResult.failed(currentVersion: currentVersion);
      }

      final latestVersion = decoded['version']?.toString().trim() ?? '';
      final changeTime = decoded['change_time']?.toString().trim() ?? '';
      final downloadUrl = decoded['download_url']?.toString().trim() ?? '';
      if (latestVersion.isEmpty || downloadUrl.isEmpty) {
        return UpdateCheckResult.failed(currentVersion: currentVersion);
      }

      if (_compareVersions(latestVersion, currentVersion) <= 0) {
        return UpdateCheckResult.idle;
      }

      final changelog = await _readChangelog();
      return UpdateCheckResult.updateAvailable(
        currentVersion: currentVersion,
        latest: AppUpdateInfo(
          version: latestVersion,
          changeTime: changeTime.isEmpty ? '未提供' : changeTime,
          downloadUrl: downloadUrl,
          changelog: changelog,
        ),
      );
    } on FormatException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.permanent,
      );
    } on _UpdateHttpStatusException catch (error) {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: error.temporary
            ? UpdateCheckFailureKind.temporary
            : UpdateCheckFailureKind.permanent,
      );
    } on SocketException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.offline,
      );
    } on TimeoutException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.temporary,
      );
    } on HandshakeException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.temporary,
      );
    } catch (_) {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.temporary,
      );
    }
  }

  bool get _supportsNativeUpdater => Platform.isWindows || Platform.isMacOS;

  Future<void> _initializeAutoUpdater() async {
    if (_autoUpdaterInitialized) {
      return;
    }
    autoUpdater.addListener(this);
    await autoUpdater.setFeedURL(_updateUrl('appcast.xml'));
    await autoUpdater.setScheduledCheckInterval(_scheduledCheckIntervalSeconds);
    _autoUpdaterInitialized = true;
  }

  Future<String> loadCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version.trim().isEmpty
          ? '1.0.0'
          : packageInfo.version.trim();
    } catch (_) {
      return '1.0.0';
    }
  }

  Future<String> _readChangelog() async {
    try {
      final changelog = await _readUrl(_updateUrl('LATESTCHANGELOG.md'));
      return changelog.trim().isEmpty ? '暂无更新内容。' : changelog;
    } catch (_) {
      return '更新内容加载失败。';
    }
  }

  Future<String> _readUrl(String url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _UpdateHttpStatusException(response.statusCode);
      }
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  String? _platformEndpoint() {
    if (Platform.isWindows) {
      return _updateUrl('windows.json');
    }
    if (Platform.isLinux) {
      return _updateUrl('linux.json');
    }
    if (Platform.isMacOS) {
      return _updateUrl('mac.json');
    }
    return null;
  }

  String _updateUrl(String fileName) {
    final configured = _configuredUpdateBaseUrl.trim();
    final base = configured.isEmpty ? _defaultUpdateBaseUrl : configured;
    return '${base.replaceFirst(RegExp(r'/+$'), '')}/$fileName';
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    unawaited(trayService.prepareForApplicationExit());
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {}

  @override
  void onUpdaterError(UpdaterError? error) {}

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {}

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {}

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {}

  int _compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    for (var index = 0; index < 3; index++) {
      final diff = leftParts[index] - rightParts[index];
      if (diff != 0) {
        return diff;
      }
    }
    return 0;
  }

  List<int> _versionParts(String version) {
    final normalized = version.split('+').first.trim();
    final parts = normalized.split('.');
    return [
      for (var index = 0; index < 3; index++)
        index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
    ];
  }
}

class _UpdateHttpStatusException implements Exception {
  const _UpdateHttpStatusException(this.statusCode);

  final int statusCode;

  bool get temporary => statusCode >= 500 && statusCode < 600;
}
