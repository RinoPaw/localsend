enum FolderSyncRole {
  host,
  replica;

  static FolderSyncRole fromJson(String value) {
    return FolderSyncRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => FolderSyncRole.replica,
    );
  }
}

enum FolderSyncRuntimeStatus {
  idle,
  pairing,
  scanning,
  syncing,
  error,
}

enum FolderSyncErrorCode {
  alreadyRunning,
  hostFolderMissing,
  localFolderUnavailable,
  needsPairing,
  peerOffline,
  pairingFailed,
  profileDisabled,
  remoteRejected,
  unknown;

  static FolderSyncErrorCode? fromJson(String? value) {
    if (value == null) {
      return null;
    }
    return FolderSyncErrorCode.values.firstWhere(
      (code) => code.name == value,
      orElse: () => FolderSyncErrorCode.unknown,
    );
  }
}

class FolderSyncException implements Exception {
  final FolderSyncErrorCode code;

  const FolderSyncException(this.code);

  @override
  String toString() => code.name;
}

class FolderSyncState {
  final String? hostFolderPath;
  final String? replicaFolderPath;
  final List<FolderSyncProfile> profiles;
  final Map<String, FolderSyncRuntime> runtimes;

  const FolderSyncState({
    required this.hostFolderPath,
    required this.replicaFolderPath,
    required this.profiles,
    required this.runtimes,
  });

  const FolderSyncState.empty() : hostFolderPath = null, replicaFolderPath = null, profiles = const [], runtimes = const {};

  factory FolderSyncState.fromJson(Map<String, dynamic> json) {
    return FolderSyncState(
      hostFolderPath: json['hostFolderPath'] as String?,
      replicaFolderPath: json['replicaFolderPath'] as String?,
      profiles: (json['profiles'] as List? ?? const [])
          .whereType<Map>()
          .map((profile) => FolderSyncProfile.fromJson(profile.cast<String, dynamic>()))
          .toList(),
      runtimes: const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hostFolderPath': hostFolderPath,
      'replicaFolderPath': replicaFolderPath,
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
    };
  }

  FolderSyncState copyWith({
    Object? hostFolderPath = _noValue,
    Object? replicaFolderPath = _noValue,
    List<FolderSyncProfile>? profiles,
    Map<String, FolderSyncRuntime>? runtimes,
  }) {
    return FolderSyncState(
      hostFolderPath: hostFolderPath == _noValue ? this.hostFolderPath : hostFolderPath as String?,
      replicaFolderPath: replicaFolderPath == _noValue ? this.replicaFolderPath : replicaFolderPath as String?,
      profiles: profiles ?? this.profiles,
      runtimes: runtimes ?? this.runtimes,
    );
  }
}

class FolderSyncProfile {
  final String id;
  final FolderSyncRole role;
  final bool enabled;
  final bool allowDestructiveSync;
  final String localFolderPath;
  final String peerFingerprint;
  final String peerAlias;
  final String peerIp;
  final int peerPort;
  final bool peerHttps;
  final String? syncSecret;
  final int? lastSyncAt;
  final int? lastSyncStartedAt;
  final int? lastSyncFinishedAt;
  final int lastScannedFiles;
  final int lastUploadedFiles;
  final int lastMovedFiles;
  final int lastDeletedFiles;
  final int lastSkippedFiles;
  final int lastFailedFiles;
  final FolderSyncErrorCode? lastErrorCode;
  final String? lastError;

  const FolderSyncProfile({
    required this.id,
    required this.role,
    required this.enabled,
    this.allowDestructiveSync = true,
    required this.localFolderPath,
    required this.peerFingerprint,
    required this.peerAlias,
    required this.peerIp,
    required this.peerPort,
    required this.peerHttps,
    required this.syncSecret,
    required this.lastSyncAt,
    this.lastSyncStartedAt,
    this.lastSyncFinishedAt,
    required this.lastScannedFiles,
    required this.lastUploadedFiles,
    required this.lastMovedFiles,
    required this.lastDeletedFiles,
    this.lastSkippedFiles = 0,
    this.lastFailedFiles = 0,
    this.lastErrorCode,
    required this.lastError,
  });

  factory FolderSyncProfile.fromJson(Map<String, dynamic> json) {
    final lastError = json['lastError'] as String?;
    return FolderSyncProfile(
      id: json['id'] as String,
      role: FolderSyncRole.fromJson(json['role'] as String? ?? FolderSyncRole.replica.name),
      enabled: json['enabled'] as bool? ?? true,
      allowDestructiveSync: json['allowDestructiveSync'] as bool? ?? true,
      localFolderPath: json['localFolderPath'] as String,
      peerFingerprint: json['peerFingerprint'] as String,
      peerAlias: json['peerAlias'] as String? ?? '',
      peerIp: json['peerIp'] as String? ?? '',
      peerPort: json['peerPort'] as int? ?? -1,
      peerHttps: json['peerHttps'] as bool? ?? true,
      syncSecret: json['syncSecret'] as String?,
      lastSyncAt: json['lastSyncAt'] as int?,
      lastSyncStartedAt: json['lastSyncStartedAt'] as int?,
      lastSyncFinishedAt: json['lastSyncFinishedAt'] as int? ?? json['lastSyncAt'] as int?,
      lastScannedFiles: json['lastScannedFiles'] as int? ?? 0,
      lastUploadedFiles: json['lastUploadedFiles'] as int? ?? 0,
      lastMovedFiles: json['lastMovedFiles'] as int? ?? 0,
      lastDeletedFiles: json['lastDeletedFiles'] as int? ?? 0,
      lastSkippedFiles: json['lastSkippedFiles'] as int? ?? 0,
      lastFailedFiles: json['lastFailedFiles'] as int? ?? 0,
      lastErrorCode: FolderSyncErrorCode.fromJson(json['lastErrorCode'] as String?) ?? (lastError == null ? null : FolderSyncErrorCode.unknown),
      lastError: lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'enabled': enabled,
      'allowDestructiveSync': allowDestructiveSync,
      'localFolderPath': localFolderPath,
      'peerFingerprint': peerFingerprint,
      'peerAlias': peerAlias,
      'peerIp': peerIp,
      'peerPort': peerPort,
      'peerHttps': peerHttps,
      if (syncSecret != null) 'syncSecret': syncSecret,
      'lastSyncAt': lastSyncAt,
      'lastSyncStartedAt': lastSyncStartedAt,
      'lastSyncFinishedAt': lastSyncFinishedAt,
      'lastScannedFiles': lastScannedFiles,
      'lastUploadedFiles': lastUploadedFiles,
      'lastMovedFiles': lastMovedFiles,
      'lastDeletedFiles': lastDeletedFiles,
      'lastSkippedFiles': lastSkippedFiles,
      'lastFailedFiles': lastFailedFiles,
      if (lastErrorCode != null) 'lastErrorCode': lastErrorCode!.name,
      'lastError': lastError,
    };
  }

  FolderSyncProfile copyWith({
    String? id,
    FolderSyncRole? role,
    bool? enabled,
    bool? allowDestructiveSync,
    String? localFolderPath,
    String? peerFingerprint,
    String? peerAlias,
    String? peerIp,
    int? peerPort,
    bool? peerHttps,
    Object? syncSecret = _noValue,
    Object? lastSyncAt = _noValue,
    Object? lastSyncStartedAt = _noValue,
    Object? lastSyncFinishedAt = _noValue,
    int? lastScannedFiles,
    int? lastUploadedFiles,
    int? lastMovedFiles,
    int? lastDeletedFiles,
    int? lastSkippedFiles,
    int? lastFailedFiles,
    Object? lastErrorCode = _noValue,
    Object? lastError = _noValue,
  }) {
    return FolderSyncProfile(
      id: id ?? this.id,
      role: role ?? this.role,
      enabled: enabled ?? this.enabled,
      allowDestructiveSync: allowDestructiveSync ?? this.allowDestructiveSync,
      localFolderPath: localFolderPath ?? this.localFolderPath,
      peerFingerprint: peerFingerprint ?? this.peerFingerprint,
      peerAlias: peerAlias ?? this.peerAlias,
      peerIp: peerIp ?? this.peerIp,
      peerPort: peerPort ?? this.peerPort,
      peerHttps: peerHttps ?? this.peerHttps,
      syncSecret: syncSecret == _noValue ? this.syncSecret : syncSecret as String?,
      lastSyncAt: lastSyncAt == _noValue ? this.lastSyncAt : lastSyncAt as int?,
      lastSyncStartedAt: lastSyncStartedAt == _noValue ? this.lastSyncStartedAt : lastSyncStartedAt as int?,
      lastSyncFinishedAt: lastSyncFinishedAt == _noValue ? this.lastSyncFinishedAt : lastSyncFinishedAt as int?,
      lastScannedFiles: lastScannedFiles ?? this.lastScannedFiles,
      lastUploadedFiles: lastUploadedFiles ?? this.lastUploadedFiles,
      lastMovedFiles: lastMovedFiles ?? this.lastMovedFiles,
      lastDeletedFiles: lastDeletedFiles ?? this.lastDeletedFiles,
      lastSkippedFiles: lastSkippedFiles ?? this.lastSkippedFiles,
      lastFailedFiles: lastFailedFiles ?? this.lastFailedFiles,
      lastErrorCode: lastErrorCode == _noValue ? this.lastErrorCode : lastErrorCode as FolderSyncErrorCode?,
      lastError: lastError == _noValue ? this.lastError : lastError as String?,
    );
  }
}

class FolderSyncRuntime {
  final FolderSyncRuntimeStatus status;
  final String message;

  const FolderSyncRuntime({
    required this.status,
    required this.message,
  });
}

class FolderSyncManifestEntry {
  final String path;
  final int size;
  final int modifiedAt;
  final String hash;

  const FolderSyncManifestEntry({
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.hash,
  });

  factory FolderSyncManifestEntry.fromJson(Map<String, dynamic> json) {
    return FolderSyncManifestEntry(
      path: json['path'] as String,
      size: json['size'] as int,
      modifiedAt: json['modifiedAt'] as int? ?? 0,
      hash: json['hash'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'size': size,
      'modifiedAt': modifiedAt,
      'hash': hash,
    };
  }

  String get contentKey => '$size:$hash';
}

class FolderSyncLocalFile {
  final FolderSyncManifestEntry entry;
  final String sourcePath;

  const FolderSyncLocalFile({
    required this.entry,
    required this.sourcePath,
  });
}

class FolderSyncMoveOperation {
  final String from;
  final String to;

  const FolderSyncMoveOperation({
    required this.from,
    required this.to,
  });

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
    };
  }
}

class FolderSyncPlan {
  final List<FolderSyncLocalFile> uploads;
  final List<FolderSyncMoveOperation> moves;
  final List<String> deletes;
  final int skipped;

  const FolderSyncPlan({
    required this.uploads,
    required this.moves,
    required this.deletes,
    required this.skipped,
  });
}

class FolderSyncStats {
  final int scanned;
  final int uploaded;
  final int moved;
  final int deleted;
  final int skipped;
  final int failed;

  const FolderSyncStats({
    required this.scanned,
    required this.uploaded,
    required this.moved,
    required this.deleted,
    required this.skipped,
    required this.failed,
  });
}

FolderSyncPlan buildFolderSyncPlan({
  required List<FolderSyncLocalFile> localFiles,
  required List<FolderSyncManifestEntry> remoteManifest,
  required bool allowDestructiveSync,
}) {
  final remoteByPath = {
    for (final entry in remoteManifest) entry.path: entry,
  };
  final localPaths = localFiles.map((file) => file.entry.path).toSet();
  final uploads = <FolderSyncLocalFile>[];

  if (!allowDestructiveSync) {
    for (final localFile in localFiles) {
      final local = localFile.entry;
      final samePathRemote = remoteByPath[local.path];
      if (samePathRemote?.contentKey == local.contentKey) {
        continue;
      }
      uploads.add(localFile);
    }

    return FolderSyncPlan(
      uploads: uploads,
      moves: const [],
      deletes: const [],
      skipped: remoteManifest.where((remote) => !localPaths.contains(remote.path)).length,
    );
  }

  final remoteByContent = <String, List<FolderSyncManifestEntry>>{};
  for (final entry in remoteManifest) {
    remoteByContent.putIfAbsent(entry.contentKey, () => []).add(entry);
  }

  final moves = <FolderSyncMoveOperation>[];
  final usedMoveSources = <String>{};

  for (final localFile in localFiles) {
    final local = localFile.entry;
    final samePathRemote = remoteByPath[local.path];
    if (samePathRemote?.contentKey == local.contentKey) {
      continue;
    }

    final moveSource = _findMoveSource(
      remoteByContent[local.contentKey],
      local.path,
      usedMoveSources,
    );
    if (moveSource != null) {
      moves.add(FolderSyncMoveOperation(from: moveSource.path, to: local.path));
      usedMoveSources.add(moveSource.path);
    } else {
      uploads.add(localFile);
    }
  }

  final deletes = remoteManifest
      .where((remote) => !localPaths.contains(remote.path) && !usedMoveSources.contains(remote.path))
      .map((remote) => remote.path)
      .toList();

  return FolderSyncPlan(
    uploads: uploads,
    moves: moves,
    deletes: deletes,
    skipped: 0,
  );
}

FolderSyncManifestEntry? _findMoveSource(
  List<FolderSyncManifestEntry>? candidates,
  String localPath,
  Set<String> usedMoveSources,
) {
  if (candidates == null) {
    return null;
  }
  for (final remote in candidates) {
    if (remote.path != localPath && !usedMoveSources.contains(remote.path)) {
      return remote;
    }
  }
  return null;
}

const Object _noValue = Object();
