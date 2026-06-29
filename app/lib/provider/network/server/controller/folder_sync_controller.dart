import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/folder_sync.dart';
import 'package:localsend_app/model/folder_sync_routes.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/folder_sync_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/util/folder_sync_file_system.dart';
import 'package:localsend_app/util/simple_server.dart';

class FolderSyncController {
  final ServerUtils server;

  FolderSyncController(this.server);

  void installRoutes({
    required SimpleServerRouteBuilder router,
  }) {
    router.post(folderSyncPairRoute, _pairHandler);
    router.post(folderSyncManifestRoute, _manifestHandler);
    router.post(folderSyncMoveRoute, _moveHandler);
    router.post(folderSyncDeleteRoute, _deleteHandler);
    router.post(folderSyncUploadRoute, _uploadHandler);
  }

  Future<void> _pairHandler(HttpRequest request) async {
    final body = await _readJson(request);
    if (body == null) {
      return;
    }

    final hostFingerprint = body['hostFingerprint'] as String?;
    final profileId = body['profileId'] as String?;
    final hostAlias = body['hostAlias'] as String? ?? '';
    final hostPort = body['hostPort'] as int?;
    final hostHttps = body['hostHttps'] as bool?;
    final syncSecret = body['syncSecret'] as String?;
    final allowDestructiveSync = body['allowDestructiveSync'] as bool? ?? true;
    if (hostFingerprint == null || profileId == null || hostPort == null || hostHttps == null || syncSecret == null || syncSecret.isEmpty) {
      return request.respondJson(400, message: 'Request body malformed.');
    }

    if (!_isTrustedFavoritePairingRequest(hostFingerprint, request.ip)) {
      return request.respondJson(403, message: 'The host must be added to favorites on this replica first.');
    }

    if (server.ref.read(folderSyncProvider).replicaFolderPath == null) {
      return request.respondJson(428, message: 'Replica folder is not selected.');
    }

    try {
      await server.ref
          .notifier(folderSyncProvider)
          .acceptPairingRequest(
            profileId: profileId,
            hostFingerprint: hostFingerprint,
            hostAlias: hostAlias,
            hostIp: request.ip,
            hostPort: hostPort,
            hostHttps: hostHttps,
            syncSecret: syncSecret,
            allowDestructiveSync: allowDestructiveSync,
          );

      final device = server.ref.read(deviceFullInfoProvider);
      return request.respondJson(
        200,
        body: {
          'profileId': profileId,
          'replicaAlias': device.alias,
        },
      );
    } catch (e) {
      return request.respondJson(500, message: e.toString());
    }
  }

  Future<void> _manifestHandler(HttpRequest request) async {
    final body = await _readJson(request);
    if (body == null) {
      return;
    }

    final (profileId, hostFingerprint) = _readProfileIdentity(body);
    final syncSecret = _readSyncSecret(request, body: body);
    if (profileId == null || hostFingerprint == null || syncSecret == null) {
      return request.respondJson(400, message: 'Request body malformed.');
    }
    if (!_isFavorite(hostFingerprint)) {
      return request.respondJson(403, message: 'The host must be in favorites.');
    }

    try {
      final files = await server.ref
          .notifier(folderSyncProvider)
          .buildReplicaManifest(
            profileId: profileId,
            hostFingerprint: hostFingerprint,
            syncSecret: syncSecret,
          );
      return request.respondJson(
        200,
        body: {
          'files': files.map((file) => file.toJson()).toList(),
        },
      );
    } catch (e) {
      return request.respondJson(403, message: e.toString());
    }
  }

  Future<void> _moveHandler(HttpRequest request) async {
    final body = await _readJson(request);
    if (body == null) {
      return;
    }

    final profile = _getReplicaProfileFromBody(request, body);
    if (profile == null) {
      return request.respondJson(403, message: 'Sync profile is not paired.');
    }
    if (!profile.allowDestructiveSync) {
      return request.respondJson(409, message: 'Destructive sync is disabled.');
    }

    final operationsRaw = body['operations'];
    if (operationsRaw is! List) {
      return request.respondJson(400, message: 'Missing operations.');
    }

    final failedTargets = <String>[];
    try {
      for (final operation in operationsRaw.whereType<Map>()) {
        final from = operation['from'] as String?;
        final to = operation['to'] as String?;
        if (from == null || to == null) {
          continue;
        }
        final moved = await moveSyncFile(folderPath: profile.localFolderPath, from: from, to: to);
        if (!moved) {
          failedTargets.add(to);
        }
      }
      await pruneEmptySyncDirectories(profile.localFolderPath);
      return request.respondJson(200, body: {'failedTargets': failedTargets});
    } catch (e) {
      return request.respondJson(400, message: e.toString());
    }
  }

  Future<void> _deleteHandler(HttpRequest request) async {
    final body = await _readJson(request);
    if (body == null) {
      return;
    }

    final profile = _getReplicaProfileFromBody(request, body);
    if (profile == null) {
      return request.respondJson(403, message: 'Sync profile is not paired.');
    }
    if (!profile.allowDestructiveSync) {
      return request.respondJson(409, message: 'Destructive sync is disabled.');
    }

    final pathsRaw = body['paths'];
    if (pathsRaw is! List || pathsRaw.any((path) => path is! String)) {
      return request.respondJson(400, message: 'Request body malformed.');
    }

    try {
      for (final path in pathsRaw.cast<String>()) {
        await deleteSyncFile(folderPath: profile.localFolderPath, relativePath: path);
      }
      await pruneEmptySyncDirectories(profile.localFolderPath);
      return request.respondJson(200);
    } catch (e) {
      return request.respondJson(400, message: e.toString());
    }
  }

  Future<void> _uploadHandler(HttpRequest request) async {
    final profileId = request.uri.queryParameters['profileId'];
    final hostFingerprint = request.uri.queryParameters['hostFingerprint'];
    final relativePath = request.uri.queryParameters['path'];
    final modifiedAt = int.tryParse(request.uri.queryParameters['modifiedAt'] ?? '');
    final syncSecret = _readSyncSecret(request);
    if (profileId == null || hostFingerprint == null || relativePath == null || modifiedAt == null || syncSecret == null) {
      return request.respondJson(400, message: 'Missing query parameters.');
    }

    if (!_isFavorite(hostFingerprint)) {
      return request.respondJson(403, message: 'The host must be in favorites.');
    }

    late final FolderSyncProfile profile;
    try {
      profile = server.ref
          .notifier(folderSyncProvider)
          .getReplicaProfile(
            profileId: profileId,
            hostFingerprint: hostFingerprint,
            syncSecret: syncSecret,
          );
    } catch (e) {
      return request.respondJson(403, message: e.toString());
    }

    try {
      await writeSyncFile(
        folderPath: profile.localFolderPath,
        relativePath: relativePath,
        stream: request,
        modifiedAt: modifiedAt,
      );
      return request.respondJson(200);
    } catch (e) {
      return request.respondJson(500, message: e.toString());
    }
  }

  Future<Map<String, dynamic>?> _readJson(HttpRequest request) async {
    try {
      return jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      await request.respondJson(400, message: 'Request body malformed.');
      return null;
    }
  }

  (String?, String?) _readProfileIdentity(Map<String, dynamic> body) {
    return (
      body['profileId'] as String?,
      body['hostFingerprint'] as String?,
    );
  }

  FolderSyncProfile? _getReplicaProfileFromBody(HttpRequest request, Map<String, dynamic> body) {
    final (profileId, hostFingerprint) = _readProfileIdentity(body);
    final syncSecret = _readSyncSecret(request, body: body);
    if (profileId == null || hostFingerprint == null || syncSecret == null || !_isFavorite(hostFingerprint)) {
      return null;
    }

    try {
      return server.ref
          .notifier(folderSyncProvider)
          .getReplicaProfile(
            profileId: profileId,
            hostFingerprint: hostFingerprint,
            syncSecret: syncSecret,
          );
    } catch (_) {
      return null;
    }
  }

  String? _readSyncSecret(HttpRequest request, {Map<String, dynamic>? body}) {
    final header = request.headers.value(folderSyncSecretHeader);
    if (header != null && header.isNotEmpty) {
      return header;
    }
    final bodySecret = body?['syncSecret'] as String?;
    if (bodySecret != null && bodySecret.isNotEmpty) {
      return bodySecret;
    }
    final querySecret = request.uri.queryParameters['syncSecret'];
    return querySecret == null || querySecret.isEmpty ? null : querySecret;
  }

  bool _isFavorite(String fingerprint) {
    return server.ref.read(favoritesProvider).any((favorite) => favorite.fingerprint == fingerprint);
  }

  bool _isTrustedFavoritePairingRequest(String fingerprint, String requestIp) {
    final normalizedRequestIp = _normalizeRequestIp(requestIp);
    final favorites = server.ref.read(favoritesProvider).where((favorite) => favorite.fingerprint == fingerprint).toList();
    if (favorites.isEmpty) {
      return false;
    }
    if (favorites.any((favorite) => _normalizeRequestIp(favorite.ip) == normalizedRequestIp)) {
      return true;
    }

    return server.ref
        .read(nearbyDevicesProvider)
        .allDevices
        .values
        .any((device) => device.fingerprint == fingerprint && device.ip != null && _normalizeRequestIp(device.ip!) == normalizedRequestIp);
  }

  String _normalizeRequestIp(String ip) {
    return ip.startsWith('::ffff:') ? ip.substring('::ffff:'.length) : ip;
  }
}
