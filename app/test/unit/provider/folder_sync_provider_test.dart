import 'dart:io';

import 'package:localsend_app/model/folder_sync.dart';
import 'package:localsend_app/provider/folder_sync_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

void main() {
  group('FolderSyncNotifier', () {
    late _PersistenceFake persistence;

    setUp(() {
      persistence = _PersistenceFake();
    });

    test('updates replica destructive sync policy and persists the profile', () async {
      final tester = Notifier.test<FolderSyncNotifier, FolderSyncState>(
        notifier: FolderSyncNotifier(persistence),
        initialState: FolderSyncState(
          hostFolderPath: null,
          replicaFolderPath: null,
          profiles: [_profile(role: FolderSyncRole.replica)],
          runtimes: const {},
        ),
      );

      await tester.notifier.setProfileAllowDestructiveSync('profile', false);

      expect(tester.state.profiles.single.allowDestructiveSync, isFalse);
      expect(persistence.savedState, tester.state);
      expect(persistence.saveCount, 1);
    });

    test('accepts re-pairing and replaces secret, policy and error state', () async {
      final root = await Directory.systemTemp.createTemp('localsend_sync_provider_test_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final tester = Notifier.test<FolderSyncNotifier, FolderSyncState>(
        notifier: FolderSyncNotifier(persistence),
        initialState: FolderSyncState(
          hostFolderPath: null,
          replicaFolderPath: root.path,
          profiles: [
            _profile(
              role: FolderSyncRole.replica,
              syncSecret: 'old',
              localFolderPath: root.path,
              allowDestructiveSync: true,
              lastErrorCode: FolderSyncErrorCode.remoteRejected,
              lastError: 'raw',
            ),
          ],
          runtimes: const {},
        ),
      );

      await tester.notifier.acceptPairingRequest(
        profileId: 'profile',
        hostFingerprint: 'fingerprint',
        hostAlias: 'host',
        hostIp: '192.168.1.10',
        hostPort: 53317,
        hostHttps: true,
        syncSecret: 'new',
        allowDestructiveSync: false,
      );

      final profile = tester.state.profiles.single;
      expect(profile.syncSecret, 'new');
      expect(profile.allowDestructiveSync, isFalse);
      expect(profile.enabled, isTrue);
      expect(profile.lastErrorCode, isNull);
      expect(profile.lastError, isNull);
      expect(persistence.savedState, tester.state);
      expect(persistence.saveCount, 1);
    });

    test('updates a profile folder and clears the stored error', () async {
      final root = await Directory.systemTemp.createTemp('localsend_sync_provider_test_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final folder = '${root.path}/new-folder';
      final tester = Notifier.test<FolderSyncNotifier, FolderSyncState>(
        notifier: FolderSyncNotifier(persistence),
        initialState: FolderSyncState(
          hostFolderPath: null,
          replicaFolderPath: null,
          profiles: [
            _profile(
              lastErrorCode: FolderSyncErrorCode.localFolderUnavailable,
              lastError: 'raw',
            ),
          ],
          runtimes: const {},
        ),
      );

      await tester.notifier.setProfileFolderPath('profile', folder);

      final profile = tester.state.profiles.single;
      expect(profile.localFolderPath, folder.replaceAll('\\', '/'));
      expect(profile.lastErrorCode, isNull);
      expect(profile.lastError, isNull);
      expect(await Directory(folder).exists(), isTrue);
      expect(persistence.savedState, tester.state);
      expect(persistence.saveCount, 1);
    });
  });
}

class _PersistenceFake implements PersistenceService {
  FolderSyncState savedState = const FolderSyncState.empty();
  int saveCount = 0;

  @override
  FolderSyncState getFolderSyncState() => savedState;

  @override
  Future<void> setFolderSyncState(FolderSyncState state) async {
    savedState = state;
    saveCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FolderSyncProfile _profile({
  FolderSyncRole role = FolderSyncRole.host,
  String? syncSecret = 'secret',
  String localFolderPath = '/tmp/source',
  bool allowDestructiveSync = true,
  FolderSyncErrorCode? lastErrorCode,
  String? lastError,
}) {
  return FolderSyncProfile(
    id: 'profile',
    role: role,
    enabled: true,
    allowDestructiveSync: allowDestructiveSync,
    localFolderPath: localFolderPath,
    peerFingerprint: 'fingerprint',
    peerAlias: 'peer',
    peerIp: '192.168.1.10',
    peerPort: 53317,
    peerHttps: true,
    syncSecret: syncSecret,
    lastSyncAt: null,
    lastScannedFiles: 0,
    lastUploadedFiles: 0,
    lastMovedFiles: 0,
    lastDeletedFiles: 0,
    lastErrorCode: lastErrorCode,
    lastError: lastError,
  );
}
