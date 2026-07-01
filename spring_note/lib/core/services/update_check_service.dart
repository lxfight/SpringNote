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

enum UpdateInstallStage { downloading, verifying, launching }

class UpdateInstallProgress {
  const UpdateInstallProgress({
    required this.stage,
    this.receivedBytes = 0,
    this.totalBytes,
  });

  final UpdateInstallStage stage;
  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return receivedBytes.clamp(0, total) / total;
  }
}

class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
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
      'https://api.github.com/repos/Radiant303/SpringNote/contents/update';
  static const _configuredUpdateBaseUrl = String.fromEnvironment(
    'SPRINGNOTE_UPDATE_BASE_URL',
  );
  static const _scheduledCheckIntervalSeconds = 6 * 60 * 60;

  final TrayService trayService;
  bool _autoUpdaterInitialized = false;
  String? _autoUpdaterFeedUrl;

  Future<UpdateCheckResult> check({
    UpdateCheckMode mode = UpdateCheckMode.background,
  }) async {
    final currentVersion = await loadCurrentVersion();
    if (!_supportsUpdates) {
      return UpdateCheckResult.failed(currentVersion: currentVersion);
    }

    return previewLatest();
  }

  Future<void> installUpdate(
    AppUpdateInfo latest, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    if (Platform.isWindows) {
      await _installWindowsUpdate(latest, onProgress: onProgress);
      return;
    }

    await _initializeAutoUpdater(
      feedUrl: _sparkleFeedUrlForVersion(latest.version),
    );
    await autoUpdater.checkForUpdates(inBackground: false);
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

  bool get _supportsUpdates => Platform.isWindows || Platform.isMacOS;

  Future<void> _initializeAutoUpdater({String? feedUrl}) async {
    final resolvedFeedUrl = feedUrl ?? _updateUrl('appcast.xml');
    if (!_autoUpdaterInitialized) {
      autoUpdater.addListener(this);
      _autoUpdaterInitialized = true;
    }
    if (_autoUpdaterFeedUrl != resolvedFeedUrl) {
      await autoUpdater.setFeedURL(resolvedFeedUrl);
      _autoUpdaterFeedUrl = resolvedFeedUrl;
    }
    await autoUpdater.setScheduledCheckInterval(_scheduledCheckIntervalSeconds);
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
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(_timeout);
      if (_isGitHubContentsApi(uri)) {
        request.headers.set('Accept', 'application/vnd.github.raw+json');
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      }
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _UpdateHttpStatusException(response.statusCode);
      }
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  bool _isGitHubContentsApi(Uri uri) {
    return uri.host == 'api.github.com' &&
        uri.pathSegments.length >= 5 &&
        uri.pathSegments[0] == 'repos' &&
        uri.pathSegments.contains('contents');
  }

  Future<void> _installWindowsUpdate(
    AppUpdateInfo latest, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'spring_note_update_',
    );
    final installer = File(
      _joinPath(tempDir.path, _safeFileName(latest.installerName)),
    );

    await _downloadFile(latest.downloadUrl, installer, onProgress: onProgress);
    onProgress?.call(
      const UpdateInstallProgress(stage: UpdateInstallStage.verifying),
    );
    await _verifyWindowsInstallerChecksum(latest, installer);
    onProgress?.call(
      const UpdateInstallProgress(stage: UpdateInstallStage.launching),
    );
    await trayService.prepareForApplicationExit();
    await _launchWindowsInstallerScript(tempDir, installer);
    exit(0);
  }

  Future<void> _launchWindowsInstallerScript(
    Directory tempDir,
    File installer,
  ) async {
    final script = File(
      _joinPath(tempDir.path, 'install_springnote_update.ps1'),
    );
    await script.writeAsString(
      _windowsInstallerScript(
        installerPath: installer.path,
        appPath: Platform.resolvedExecutable,
      ),
      encoding: utf8,
    );

    await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> _downloadFile(
    String url,
    File file, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateInstallException('下载安装包失败 (${response.statusCode})');
      }

      await file.parent.create(recursive: true);
      sink = file.openWrite();
      var received = 0;
      final total = response.contentLength > 0 ? response.contentLength : null;
      onProgress?.call(
        UpdateInstallProgress(
          stage: UpdateInstallStage.downloading,
          totalBytes: total,
        ),
      );
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          UpdateInstallProgress(
            stage: UpdateInstallStage.downloading,
            receivedBytes: received,
            totalBytes: total,
          ),
        );
      }
    } on UpdateInstallException {
      rethrow;
    } on TimeoutException {
      throw const UpdateInstallException('下载更新超时，请稍后重试。');
    } on SocketException {
      throw const UpdateInstallException('网络不可用，请检查连接后重试。');
    } catch (_) {
      throw const UpdateInstallException('下载安装包失败，请稍后重试。');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<void> _verifyWindowsInstallerChecksum(
    AppUpdateInfo latest,
    File installer,
  ) async {
    final expected = await _readExpectedSha256(latest);
    final actual = await _calculateWindowsSha256(installer);
    if (actual.toLowerCase() != expected.toLowerCase()) {
      throw const UpdateInstallException('安装包校验失败，请稍后重试。');
    }
  }

  Future<String> _readExpectedSha256(AppUpdateInfo latest) async {
    final downloadUri = Uri.parse(latest.downloadUrl);
    final segments = downloadUri.pathSegments;
    if (segments.isEmpty) {
      throw const UpdateInstallException('无法读取安装包校验信息。');
    }
    final checksumUri = downloadUri.replace(
      pathSegments: [...segments.take(segments.length - 1), 'SHA256SUMS.txt'],
    );
    final checksums = await _readUrl(checksumUri.toString());
    final fileName = latest.installerName;
    for (final line in checksums.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      final hash = parts.first;
      final name = parts.last.replaceFirst(RegExp(r'^\*'), '');
      if (name == fileName && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
        return hash;
      }
    }
    throw const UpdateInstallException('未找到安装包校验信息。');
  }

  Future<String> _calculateWindowsSha256(File file) async {
    final result = await Process.run('certutil', [
      '-hashfile',
      file.path,
      'SHA256',
    ]);
    if (result.exitCode != 0) {
      throw const UpdateInstallException('安装包校验失败，请稍后重试。');
    }
    final output = '${result.stdout}\n${result.stderr}';
    for (final line in output.split('\n')) {
      final normalized = line.replaceAll(RegExp(r'\s+'), '').trim();
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized)) {
        return normalized;
      }
    }
    throw const UpdateInstallException('安装包校验失败，请稍后重试。');
  }

  String _safeFileName(String fileName) {
    final sanitized = fileName.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    return sanitized.trim().isEmpty ? 'SpringNote-update.exe' : sanitized;
  }

  String _windowsInstallerScript({
    required String installerPath,
    required String appPath,
  }) {
    final installer = _powerShellSingleQuoted(installerPath);
    final app = _powerShellSingleQuoted(appPath);
    return '''
\$installer = $installer
\$app = $app
Start-Sleep -Milliseconds 500
\$process = Start-Process -FilePath \$installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/SP-') -Wait -PassThru
if (\$process.ExitCode -eq 0 -and (Test-Path -LiteralPath \$app)) {
  Start-Process -FilePath \$app
}
''';
  }

  String _powerShellSingleQuoted(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  String _joinPath(String directory, String name) {
    final separator = Platform.pathSeparator;
    if (directory.endsWith(separator)) {
      return '$directory$name';
    }
    return '$directory$separator$name';
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

  String _sparkleFeedUrlForVersion(String version) {
    final configured = _configuredUpdateBaseUrl.trim();
    final uri = Uri.tryParse(
      configured.isEmpty ? _defaultUpdateBaseUrl : configured,
    );
    if (uri == null || !_isGitHubContentsApi(uri)) {
      return _updateUrl('appcast.xml');
    }
    final segments = uri.pathSegments;
    if (segments.length < 5) {
      return _updateUrl('appcast.xml');
    }
    final owner = segments[1];
    final repo = segments[2];
    return 'https://github.com/$owner/$repo/releases/download/$version/appcast.xml';
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
