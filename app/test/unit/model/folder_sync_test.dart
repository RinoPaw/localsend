import 'package:localsend_app/model/folder_sync.dart';
import 'package:test/test.dart';

void main() {
  group('FolderSyncProfile', () {
    test('persists sync secret, policy and result details', () {
      const profile = FolderSyncProfile(
        id: 'profile',
        role: FolderSyncRole.host,
        enabled: true,
        allowDestructiveSync: false,
        localFolderPath: '/tmp/source',
        peerFingerprint: 'fingerprint',
        peerAlias: 'peer',
        peerIp: '192.168.1.10',
        peerPort: 53317,
        peerHttps: true,
        syncSecret: 'secret',
        lastSyncAt: 3000,
        lastSyncStartedAt: 1000,
        lastSyncFinishedAt: 3000,
        lastScannedFiles: 10,
        lastUploadedFiles: 2,
        lastMovedFiles: 1,
        lastDeletedFiles: 3,
        lastSkippedFiles: 4,
        lastFailedFiles: 5,
        lastErrorCode: FolderSyncErrorCode.remoteRejected,
        lastError: 'raw',
      );

      final parsed = FolderSyncProfile.fromJson(profile.toJson());

      expect(parsed.syncSecret, 'secret');
      expect(parsed.allowDestructiveSync, isFalse);
      expect(parsed.lastSyncStartedAt, 1000);
      expect(parsed.lastSyncFinishedAt, 3000);
      expect(parsed.lastSkippedFiles, 4);
      expect(parsed.lastFailedFiles, 5);
      expect(parsed.lastErrorCode, FolderSyncErrorCode.remoteRejected);
    });

    test('keeps old profiles readable without a sync secret and defaults to full mirror', () {
      final parsed = FolderSyncProfile.fromJson({
        'id': 'profile',
        'role': 'host',
        'enabled': true,
        'localFolderPath': '/tmp/source',
        'peerFingerprint': 'fingerprint',
        'peerAlias': 'peer',
        'peerIp': '192.168.1.10',
        'peerPort': 53317,
        'peerHttps': true,
      });

      expect(parsed.syncSecret, isNull);
      expect(parsed.allowDestructiveSync, isTrue);
      expect(parsed.lastSkippedFiles, 0);
      expect(parsed.lastFailedFiles, 0);
      expect(parsed.lastErrorCode, isNull);
    });
  });

  group('buildFolderSyncPlan', () {
    test('uploads changed files and mirrors moves and deletes when destructive sync is enabled', () {
      final localFiles = [
        _local('renamed.txt', size: 5, hash: 'same'),
        _local('changed.txt', size: 7, hash: 'new'),
      ];
      const remoteManifest = [
        FolderSyncManifestEntry(path: 'old.txt', size: 5, modifiedAt: 1, hash: 'same'),
        FolderSyncManifestEntry(path: 'changed.txt', size: 7, modifiedAt: 1, hash: 'old'),
        FolderSyncManifestEntry(path: 'deleted.txt', size: 3, modifiedAt: 1, hash: 'gone'),
      ];

      final plan = buildFolderSyncPlan(
        localFiles: localFiles,
        remoteManifest: remoteManifest,
        allowDestructiveSync: true,
      );

      expect(plan.uploads.map((file) => file.entry.path), ['changed.txt']);
      expect(plan.moves.map((move) => '${move.from}->${move.to}'), ['old.txt->renamed.txt']);
      expect(plan.deletes, ['deleted.txt']);
      expect(plan.skipped, 0);
    });

    test('skips remote moves and deletes when destructive sync is disabled', () {
      final localFiles = [
        _local('renamed.txt', size: 5, hash: 'same'),
        _local('changed.txt', size: 7, hash: 'new'),
      ];
      const remoteManifest = [
        FolderSyncManifestEntry(path: 'old.txt', size: 5, modifiedAt: 1, hash: 'same'),
        FolderSyncManifestEntry(path: 'changed.txt', size: 7, modifiedAt: 1, hash: 'old'),
        FolderSyncManifestEntry(path: 'deleted.txt', size: 3, modifiedAt: 1, hash: 'gone'),
      ];

      final plan = buildFolderSyncPlan(
        localFiles: localFiles,
        remoteManifest: remoteManifest,
        allowDestructiveSync: false,
      );

      expect(plan.uploads.map((file) => file.entry.path), ['renamed.txt', 'changed.txt']);
      expect(plan.moves, isEmpty);
      expect(plan.deletes, isEmpty);
      expect(plan.skipped, 2);
    });
  });
}

FolderSyncLocalFile _local(String path, {required int size, required String hash}) {
  return FolderSyncLocalFile(
    sourcePath: path,
    entry: FolderSyncManifestEntry(
      path: path,
      size: size,
      modifiedAt: 1,
      hash: hash,
    ),
  );
}
