import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:common/constants.dart';
import 'package:common/model/device.dart';
import 'package:localsend_app/model/folder_sync.dart';
import 'package:localsend_app/model/folder_sync_routes.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/folder_sync_file_system.dart';
import 'package:localsend_app/util/security_helper.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('FolderSync');
const _uuid = Uuid();
const _syncSecretBytes = 32;
const _autoSyncTickInterval = Duration(minutes: 1);
const _autoSyncProfileInterval = Duration(minutes: 5);

final folderSyncProvider = NotifierProvider<FolderSyncNotifier, FolderSyncState>((ref) {
  return FolderSyncNotifier(ref.read(persistenceProvider));
});

class FolderSyncNotifier extends Notifier<FolderSyncState> {
  final PersistenceService _persistence;
  Timer? _autoSyncTimer;
  bool _autoSyncRunning = false;
  final Set<String> _runningProfileIds = {};

  FolderSyncNotifier(this._persistence);

  @override
  FolderSyncState init() => _persistence.getFolderSyncState();

  Future<void> setHostFolderPath(String path) async {
    await _ensureFolder(path);
    state = state.copyWith(hostFolderPath: _normalizeFolderPath(path));
    await _save();
  }

  Future<void> setReplicaFolderPath(String path) async {
    await _ensureFolder(path);
    state = state.copyWith(replicaFolderPath: _normalizeFolderPath(path));
    await _save();
  }

  Future<void> pairWithReplica(
    FavoriteDevice replica, {
    bool allowDestructiveSync = true,
  }) async {
    final folderPath = state.hostFolderPath;
    if (folderPath == null) {
      throw const FolderSyncException(FolderSyncErrorCode.hostFolderMissing);
    }

    await _pairWithReplica(
      replica: replica,
      folderPath: folderPath,
      allowDestructiveSync: allowDestructiveSync,
    );
  }

  Future<void> _pairWithReplica({
    required FavoriteDevice replica,
    required String folderPath,
    required bool allowDestructiveSync,
  }) async {
    await _ensureFolderAvailable(folderPath);
    final target = _resolveDevice(replica.fingerprint) ?? _favoriteToDevice(replica, ref.read(settingsProvider).https);
    if (target.ip == null || target.ip!.isEmpty) {
      throw const FolderSyncException(FolderSyncErrorCode.peerOffline);
    }
    final existing = state.profiles.firstWhereOrNull(
      (profile) => profile.role == FolderSyncRole.host && profile.peerFingerprint == replica.fingerprint && profile.localFolderPath == folderPath,
    );
    final profileId = existing?.id ?? _uuid.v4();
    final origin = ref.read(deviceFullInfoProvider);
    final syncSecret = _generateSyncSecret();

    _setRuntime(profileId, const FolderSyncRuntime(status: FolderSyncRuntimeStatus.pairing, message: 'Pairing'));
    try {
      final response = await _FolderSyncHttpClient(target).postJson(
        folderSyncPairRoute,
        {
          'profileId': profileId,
          'hostFingerprint': origin.fingerprint,
          'hostAlias': origin.alias,
          'hostPort': origin.port,
          'hostHttps': origin.https,
          'syncSecret': syncSecret,
          'allowDestructiveSync': allowDestructiveSync,
        },
      );

      final profile = FolderSyncProfile(
        id: profileId,
        role: FolderSyncRole.host,
        enabled: true,
        allowDestructiveSync: allowDestructiveSync,
        localFolderPath: folderPath,
        peerFingerprint: replica.fingerprint,
        peerAlias: response['replicaAlias'] as String? ?? replica.alias,
        peerIp: target.ip!,
        peerPort: target.port,
        peerHttps: target.https,
        syncSecret: syncSecret,
        lastSyncAt: existing?.lastSyncAt,
        lastSyncStartedAt: existing?.lastSyncStartedAt,
        lastSyncFinishedAt: existing?.lastSyncFinishedAt,
        lastScannedFiles: existing?.lastScannedFiles ?? 0,
        lastUploadedFiles: existing?.lastUploadedFiles ?? 0,
        lastMovedFiles: existing?.lastMovedFiles ?? 0,
        lastDeletedFiles: existing?.lastDeletedFiles ?? 0,
        lastSkippedFiles: existing?.lastSkippedFiles ?? 0,
        lastFailedFiles: existing?.lastFailedFiles ?? 0,
        lastErrorCode: null,
        lastError: null,
      );
      _upsertProfile(profile);
      _setRuntime(profileId, const FolderSyncRuntime(status: FolderSyncRuntimeStatus.idle, message: 'Paired'));
      await _save();
    } catch (e, st) {
      _logger.warning('Pairing failed', e, st);
      _setRuntime(profileId, const FolderSyncRuntime(status: FolderSyncRuntimeStatus.error, message: 'pairingFailed'));
      if (e is FolderSyncException) {
        rethrow;
      }
      throw const FolderSyncException(FolderSyncErrorCode.pairingFailed);
    }
  }

  Future<void> acceptPairingRequest({
    required String profileId,
    required String hostFingerprint,
    required String hostAlias,
    required String hostIp,
    required int hostPort,
    required bool hostHttps,
    required String syncSecret,
    required bool allowDestructiveSync,
  }) async {
    final folderPath = state.replicaFolderPath;
    if (folderPath == null) {
      throw const FolderSyncException(FolderSyncErrorCode.localFolderUnavailable);
    }

    await _ensureFolderAvailable(folderPath);
    final existing = state.profiles.firstWhereOrNull((profile) => profile.id == profileId);
    _upsertProfile(
      FolderSyncProfile(
        id: profileId,
        role: FolderSyncRole.replica,
        enabled: true,
        allowDestructiveSync: allowDestructiveSync,
        localFolderPath: folderPath,
        peerFingerprint: hostFingerprint,
        peerAlias: hostAlias,
        peerIp: hostIp,
        peerPort: hostPort,
        peerHttps: hostHttps,
        syncSecret: syncSecret,
        lastSyncAt: existing?.lastSyncAt,
        lastSyncStartedAt: existing?.lastSyncStartedAt,
        lastSyncFinishedAt: existing?.lastSyncFinishedAt,
        lastScannedFiles: existing?.lastScannedFiles ?? 0,
        lastUploadedFiles: existing?.lastUploadedFiles ?? 0,
        lastMovedFiles: existing?.lastMovedFiles ?? 0,
        lastDeletedFiles: existing?.lastDeletedFiles ?? 0,
        lastSkippedFiles: existing?.lastSkippedFiles ?? 0,
        lastFailedFiles: existing?.lastFailedFiles ?? 0,
        lastErrorCode: null,
        lastError: null,
      ),
    );
    await _save();
  }

  Future<void> syncProfile(String profileId) async {
    final profile = state.profiles.firstWhereOrNull((profile) => profile.id == profileId);
    if (profile == null) {
      throw const FolderSyncException(FolderSyncErrorCode.unknown);
    }
    if (profile.role != FolderSyncRole.host) {
      throw const FolderSyncException(FolderSyncErrorCode.profileDisabled);
    }
    if (!profile.enabled) {
      throw const FolderSyncException(FolderSyncErrorCode.profileDisabled);
    }
    if (profile.syncSecret == null || profile.syncSecret!.isEmpty) {
      throw const FolderSyncException(FolderSyncErrorCode.needsPairing);
    }
    if (!_runningProfileIds.add(profile.id)) {
      throw const FolderSyncException(FolderSyncErrorCode.alreadyRunning);
    }

    final startedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    _setRuntime(profile.id, const FolderSyncRuntime(status: FolderSyncRuntimeStatus.scanning, message: 'Scanning local folder'));
    try {
      await _ensureFolderAvailable(profile.localFolderPath);
      final target = _resolveDevice(profile.peerFingerprint) ?? _profileToDevice(profile);
      if (target.ip == null || target.ip!.isEmpty) {
        throw const FolderSyncException(FolderSyncErrorCode.peerOffline);
      }

      final localFiles = await scanSyncFolder(profile.localFolderPath);
      final localByPath = {
        for (final file in localFiles) file.entry.path: file,
      };

      _setRuntime(profile.id, const FolderSyncRuntime(status: FolderSyncRuntimeStatus.scanning, message: 'Reading replica manifest'));
      final remoteManifest = await _fetchRemoteManifest(target, profile);
      final plan = buildFolderSyncPlan(
        localFiles: localFiles,
        remoteManifest: remoteManifest,
        allowDestructiveSync: profile.allowDestructiveSync,
      );

      _setRuntime(profile.id, FolderSyncRuntime(status: FolderSyncRuntimeStatus.syncing, message: 'Moving ${plan.moves.length} files'));
      final failedMoveTargets = plan.moves.isEmpty ? <String>[] : await _moveRemoteFiles(target, profile, plan.moves);
      final failedMoveTargetSet = failedMoveTargets.toSet();
      final failedMoveSources = plan.moves.where((move) => failedMoveTargetSet.contains(move.to)).map((move) => move.from).toList();

      final uploads = <FolderSyncLocalFile>[
        ...plan.uploads,
        for (final path in failedMoveTargets)
          if (localByPath[path] != null) localByPath[path]!,
      ];
      final uploadedPaths = <String>{};
      var uploaded = 0;
      for (final file in uploads) {
        if (!uploadedPaths.add(file.entry.path)) {
          continue;
        }
        _setRuntime(profile.id, FolderSyncRuntime(status: FolderSyncRuntimeStatus.syncing, message: 'Uploading ${file.entry.path}'));
        await _uploadRemoteFile(target, profile, file);
        uploaded++;
      }

      final deletes = [...plan.deletes, ...failedMoveSources];
      _setRuntime(profile.id, FolderSyncRuntime(status: FolderSyncRuntimeStatus.syncing, message: 'Deleting ${deletes.length} files'));
      if (deletes.isNotEmpty) {
        await _deleteRemoteFiles(target, profile, deletes);
      }

      final stats = FolderSyncStats(
        scanned: localFiles.length,
        uploaded: uploaded,
        moved: plan.moves.length - failedMoveTargets.length,
        deleted: deletes.length,
        skipped: plan.skipped,
        failed: failedMoveTargets.length,
      );
      final finishedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      _upsertProfile(
        profile.copyWith(
          peerIp: target.ip!,
          peerPort: target.port,
          peerHttps: target.https,
          peerAlias: target.alias.isEmpty ? profile.peerAlias : target.alias,
          lastSyncAt: finishedAt,
          lastSyncStartedAt: startedAt,
          lastSyncFinishedAt: finishedAt,
          lastScannedFiles: stats.scanned,
          lastUploadedFiles: stats.uploaded,
          lastMovedFiles: stats.moved,
          lastDeletedFiles: stats.deleted,
          lastSkippedFiles: stats.skipped,
          lastFailedFiles: stats.failed,
          lastErrorCode: null,
          lastError: null,
        ),
      );
      _setRuntime(profile.id, const FolderSyncRuntime(status: FolderSyncRuntimeStatus.idle, message: 'Synced'));
      await _save();
    } catch (e, st) {
      _logger.warning('Folder sync failed', e, st);
      final errorCode = _errorCodeFor(e);
      final finishedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      _upsertProfile(
        profile.copyWith(
          lastSyncStartedAt: startedAt,
          lastSyncFinishedAt: finishedAt,
          lastFailedFiles: 1,
          lastErrorCode: errorCode,
          lastError: e.toString(),
        ),
      );
      _setRuntime(profile.id, FolderSyncRuntime(status: FolderSyncRuntimeStatus.error, message: errorCode.name));
      await _save();
      throw FolderSyncException(errorCode);
    } finally {
      _runningProfileIds.remove(profile.id);
    }
  }

  Future<List<FolderSyncManifestEntry>> buildReplicaManifest({
    required String profileId,
    required String hostFingerprint,
    required String syncSecret,
  }) async {
    final profile = getReplicaProfile(
      profileId: profileId,
      hostFingerprint: hostFingerprint,
      syncSecret: syncSecret,
    );
    final files = await scanSyncFolder(profile.localFolderPath);
    return files.map((file) => file.entry).toList();
  }

  FolderSyncProfile getReplicaProfile({
    required String profileId,
    required String hostFingerprint,
    required String syncSecret,
  }) {
    final profile = state.profiles.firstWhereOrNull(
      (profile) =>
          profile.id == profileId &&
          profile.role == FolderSyncRole.replica &&
          profile.peerFingerprint == hostFingerprint &&
          profile.syncSecret != null &&
          profile.syncSecret == syncSecret,
    );
    if (profile == null) {
      throw const FolderSyncException(FolderSyncErrorCode.needsPairing);
    }
    if (!profile.enabled) {
      throw const FolderSyncException(FolderSyncErrorCode.profileDisabled);
    }
    return profile;
  }

  Future<void> setProfileEnabled(String profileId, bool enabled) async {
    final profile = state.profiles.firstWhereOrNull((profile) => profile.id == profileId);
    if (profile == null) {
      return;
    }
    _upsertProfile(
      profile.copyWith(
        enabled: enabled,
        lastErrorCode: null,
        lastError: null,
      ),
    );
    await _save();
  }

  Future<void> setProfileAllowDestructiveSync(String profileId, bool allowDestructiveSync) async {
    final profile = state.profiles.firstWhereOrNull((profile) => profile.id == profileId);
    if (profile == null) {
      return;
    }

    if (profile.allowDestructiveSync == allowDestructiveSync) {
      return;
    }

    if (profile.role == FolderSyncRole.host) {
      await _pairWithReplica(
        replica: _favoriteForProfile(profile),
        folderPath: profile.localFolderPath,
        allowDestructiveSync: allowDestructiveSync,
      );
      return;
    }

    _upsertProfile(profile.copyWith(allowDestructiveSync: allowDestructiveSync));
    await _save();
  }

  Future<void> setProfileFolderPath(String profileId, String path) async {
    final profile = state.profiles.firstWhereOrNull((profile) => profile.id == profileId);
    if (profile == null) {
      return;
    }
    await _ensureFolder(path);
    _upsertProfile(
      profile.copyWith(
        localFolderPath: _normalizeFolderPath(path),
        lastErrorCode: null,
        lastError: null,
      ),
    );
    await _save();
  }

  Future<void> rePairProfile(String profileId) async {
    final profile = state.profiles.firstWhereOrNull((profile) => profile.id == profileId);
    if (profile == null) {
      throw const FolderSyncException(FolderSyncErrorCode.unknown);
    }
    if (profile.role != FolderSyncRole.host) {
      throw const FolderSyncException(FolderSyncErrorCode.profileDisabled);
    }
    final favorite = _favoriteForProfile(profile);
    await _pairWithReplica(
      replica: favorite,
      folderPath: profile.localFolderPath,
      allowDestructiveSync: profile.allowDestructiveSync,
    );
  }

  Future<void> removeProfile(String profileId) async {
    state = state.copyWith(
      profiles: state.profiles.where((profile) => profile.id != profileId).toList(),
      runtimes: {...state.runtimes}..remove(profileId),
    );
    await _save();
  }

  Future<void> scanFavorites() async {
    final favorites = ref.read(favoritesProvider);
    if (favorites.isEmpty) {
      return;
    }
    await ref
        .redux(nearbyDevicesProvider)
        .dispatchAsync(
          StartFavoriteScan(
            devices: favorites,
            https: ref.read(settingsProvider).https,
          ),
        );
  }

  void startAutoSync() {
    _autoSyncTimer ??= Timer.periodic(_autoSyncTickInterval, (_) {
      unawaited(_runAutoSync());
    });
    unawaited(_runAutoSync());
  }

  Future<void> _runAutoSync() async {
    if (_autoSyncRunning) {
      return;
    }

    final hostProfiles = state.profiles.where((profile) => profile.role == FolderSyncRole.host && profile.enabled).toList();
    if (hostProfiles.isEmpty) {
      return;
    }

    _autoSyncRunning = true;
    try {
      await scanFavorites();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final profile in hostProfiles) {
        final lastSyncAt = profile.lastSyncAt;
        if (lastSyncAt != null && now - lastSyncAt < _autoSyncProfileInterval.inMilliseconds) {
          continue;
        }
        final device = _resolveDevice(profile.peerFingerprint);
        if (device?.ip != null) {
          await syncProfile(profile.id);
        }
      }
    } catch (e, st) {
      _logger.fine('Auto sync skipped', e, st);
    } finally {
      _autoSyncRunning = false;
    }
  }

  Future<List<FolderSyncManifestEntry>> _fetchRemoteManifest(Device target, FolderSyncProfile profile) async {
    final origin = ref.read(deviceFullInfoProvider);
    final json = await _FolderSyncHttpClient(target).postJson(
      folderSyncManifestRoute,
      {
        'profileId': profile.id,
        'hostFingerprint': origin.fingerprint,
        'hostAlias': origin.alias,
      },
      headers: _syncHeaders(profile),
    );
    return (json['files'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => FolderSyncManifestEntry.fromJson(entry.cast<String, dynamic>()))
        .toList();
  }

  Future<List<String>> _moveRemoteFiles(Device target, FolderSyncProfile profile, List<FolderSyncMoveOperation> moves) async {
    final origin = ref.read(deviceFullInfoProvider);
    final json = await _FolderSyncHttpClient(target).postJson(
      folderSyncMoveRoute,
      {
        'profileId': profile.id,
        'hostFingerprint': origin.fingerprint,
        'operations': moves.map((move) => move.toJson()).toList(),
      },
      headers: _syncHeaders(profile),
    );
    return (json['failedTargets'] as List? ?? const []).cast<String>();
  }

  Future<void> _deleteRemoteFiles(Device target, FolderSyncProfile profile, List<String> deletes) async {
    final origin = ref.read(deviceFullInfoProvider);
    await _FolderSyncHttpClient(target).postJson(
      folderSyncDeleteRoute,
      {
        'profileId': profile.id,
        'hostFingerprint': origin.fingerprint,
        'paths': deletes,
      },
      headers: _syncHeaders(profile),
    );
  }

  Future<void> _uploadRemoteFile(Device target, FolderSyncProfile profile, FolderSyncLocalFile file) async {
    final origin = ref.read(deviceFullInfoProvider);
    await _FolderSyncHttpClient(target).postStream(
      folderSyncUploadRoute,
      query: {
        'profileId': profile.id,
        'hostFingerprint': origin.fingerprint,
        'path': file.entry.path,
        'modifiedAt': file.entry.modifiedAt.toString(),
      },
      headers: _syncHeaders(profile),
      size: file.entry.size,
      mime: lookupSyncMimeType(file.entry.path) ?? 'application/octet-stream',
      stream: openSyncFileRead(file.sourcePath),
    );
  }

  Device? _resolveDevice(String fingerprint) {
    return ref
        .read(nearbyDevicesProvider)
        .allDevices
        .values
        .firstWhereOrNull((device) => device.fingerprint == fingerprint && device.ip != null && device.ip!.isNotEmpty);
  }

  Device _favoriteToDevice(FavoriteDevice favorite, bool https) {
    return Device(
      signalingId: null,
      ip: favorite.ip,
      version: protocolVersion,
      port: favorite.port,
      https: https,
      fingerprint: favorite.fingerprint,
      alias: favorite.alias,
      deviceModel: null,
      deviceType: DeviceType.desktop,
      download: false,
      discoveryMethods: {HttpDiscovery(ip: favorite.ip)},
    );
  }

  FavoriteDevice _favoriteForProfile(FolderSyncProfile profile) {
    return ref.read(favoritesProvider).firstWhereOrNull((favorite) => favorite.fingerprint == profile.peerFingerprint) ??
        FavoriteDevice(
          id: profile.peerFingerprint,
          fingerprint: profile.peerFingerprint,
          ip: profile.peerIp,
          port: profile.peerPort,
          alias: profile.peerAlias,
        );
  }

  Device _profileToDevice(FolderSyncProfile profile) {
    return Device(
      signalingId: null,
      ip: profile.peerIp,
      version: protocolVersion,
      port: profile.peerPort,
      https: profile.peerHttps,
      fingerprint: profile.peerFingerprint,
      alias: profile.peerAlias,
      deviceModel: null,
      deviceType: DeviceType.desktop,
      download: false,
      discoveryMethods: profile.peerIp.isEmpty ? const {} : {HttpDiscovery(ip: profile.peerIp)},
    );
  }

  void _upsertProfile(FolderSyncProfile profile) {
    final profiles = [...state.profiles];
    final index = profiles.indexWhere((entry) => entry.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    state = state.copyWith(profiles: profiles);
  }

  void _setRuntime(String profileId, FolderSyncRuntime runtime) {
    state = state.copyWith(
      runtimes: {
        ...state.runtimes,
        profileId: runtime,
      },
    );
  }

  Future<void> _save() async {
    await _persistence.setFolderSyncState(state);
  }

  Future<void> _ensureFolder(String path) async {
    if (isContentFolder(path)) {
      return;
    }
    await Directory(path).create(recursive: true);
  }

  Future<void> _ensureFolderAvailable(String path) async {
    try {
      if (!await syncFolderExists(path)) {
        throw const FolderSyncException(FolderSyncErrorCode.localFolderUnavailable);
      }
    } on FolderSyncException {
      rethrow;
    } catch (_) {
      throw const FolderSyncException(FolderSyncErrorCode.localFolderUnavailable);
    }
  }

  String _normalizeFolderPath(String path) {
    return isContentFolder(path) ? path : path.replaceAll('\\', '/');
  }

  Map<String, String> _syncHeaders(FolderSyncProfile profile) {
    final syncSecret = profile.syncSecret;
    if (syncSecret == null || syncSecret.isEmpty) {
      throw const FolderSyncException(FolderSyncErrorCode.needsPairing);
    }
    return {
      folderSyncSecretHeader: syncSecret,
    };
  }

  String _generateSyncSecret() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(_syncSecretBytes, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  FolderSyncErrorCode _errorCodeFor(Object error) {
    if (error is FolderSyncException) {
      return error.code;
    }
    final message = error.toString().toLowerCase();
    if (message.contains('http 400') || message.contains('http 403') || message.contains('http 409')) {
      return FolderSyncErrorCode.remoteRejected;
    }
    if (message.contains('folder') || message.contains('path') || message.contains('file')) {
      return FolderSyncErrorCode.localFolderUnavailable;
    }
    return FolderSyncErrorCode.unknown;
  }
}

class _FolderSyncHttpClient {
  final Device target;

  _FolderSyncHttpClient(this.target);

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final client = _createClient();
    try {
      final request = await client.postUrl(_targetUri(path));
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));
      final response = await request.close();
      return await _decodeResponse(response);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> postStream(
    String path, {
    required Map<String, String> query,
    required Map<String, String> headers,
    required int size,
    required String mime,
    required Stream<List<int>> stream,
  }) async {
    final client = _createClient();
    try {
      final request = await client.postUrl(_targetUri(path, query: query));
      request.headers.contentType = ContentType.parse(mime);
      headers.forEach(request.headers.set);
      request.contentLength = size;
      await request.addStream(stream);
      final response = await request.close();
      await _decodeResponse(response);
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _createClient() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (certificate, _, _) {
        try {
          return calculateHashOfCertificate(certificate.pem).toLowerCase() == target.fingerprint.toLowerCase();
        } catch (e, st) {
          _logger.warning('Failed to verify sync peer certificate', e, st);
          return false;
        }
      };
  }

  Uri _targetUri(String path, {Map<String, String>? query}) {
    return Uri(
      scheme: target.https ? 'https' : 'http',
      host: target.ip,
      port: target.port,
      path: path,
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> _decodeResponse(HttpClientResponse response) async {
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = body;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        message = json['message'] as String? ?? body;
      } catch (_) {}
      throw Exception('HTTP ${response.statusCode}: $message');
    }
    if (body.trim().isEmpty) {
      return {};
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }
}
