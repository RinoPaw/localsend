import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/folder_sync.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/pages/tabs/sync_tab.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/folder_sync_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('host profiles show sync now while replica profiles do not', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FolderSyncState(
          hostFolderPath: 'C:/Host',
          replicaFolderPath: 'C:/Replica',
          profiles: [
            _profile(id: 'host', role: FolderSyncRole.host, peerAlias: 'Phone'),
            _profile(id: 'replica', role: FolderSyncRole.replica, peerAlias: 'Laptop'),
          ],
          runtimes: const {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.syncTab.syncNow), findsOneWidget);
    expect(find.textContaining('${t.syncTab.roleHost} · Phone'), findsOneWidget);
    expect(find.textContaining('${t.syncTab.roleReplica} · Laptop'), findsOneWidget);
  });

  testWidgets('profile cards show localized error recovery state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FolderSyncState(
          hostFolderPath: 'C:/Host',
          replicaFolderPath: 'C:/Replica',
          profiles: [
            _profile(
              id: 'replica',
              role: FolderSyncRole.replica,
              lastErrorCode: FolderSyncErrorCode.localFolderUnavailable,
              lastError: 'raw',
            ),
          ],
          runtimes: const {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.syncTab.errorLocalFolderUnavailable), findsOneWidget);
    expect(find.text(t.syncTab.syncNow), findsNothing);
    expect(find.text(t.syncTab.fullMirror), findsOneWidget);
  });
}

Widget _wrap(FolderSyncState state) {
  final persistence = _PersistenceFake(folderSyncState: state);
  return RefenaScope(
    overrides: [
      persistenceProvider.overrideWithValue(persistence),
      favoritesProvider.overrideWithNotifier((ref) => FavoritesService(persistence)),
      folderSyncProvider.overrideWithNotifier((ref) => FolderSyncNotifier(persistence)),
    ],
    child: TranslationProvider(
      child: const MaterialApp(
        home: Scaffold(
          body: SyncTab(),
        ),
      ),
    ),
  );
}

class _PersistenceFake implements PersistenceService {
  FolderSyncState folderSyncState;

  _PersistenceFake({required this.folderSyncState});

  @override
  List<FavoriteDevice> getFavorites() => const [];

  @override
  Future<void> setFavorites(List<FavoriteDevice> favorites) async {}

  @override
  FolderSyncState getFolderSyncState() => folderSyncState;

  @override
  Future<void> setFolderSyncState(FolderSyncState state) async {
    folderSyncState = state;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FolderSyncProfile _profile({
  required String id,
  required FolderSyncRole role,
  String peerAlias = 'Peer',
  FolderSyncErrorCode? lastErrorCode,
  String? lastError,
}) {
  return FolderSyncProfile(
    id: id,
    role: role,
    enabled: true,
    localFolderPath: 'C:/Sync/$id',
    peerFingerprint: 'fingerprint-$id',
    peerAlias: peerAlias,
    peerIp: '192.168.1.10',
    peerPort: 53317,
    peerHttps: true,
    syncSecret: 'secret',
    lastSyncAt: null,
    lastScannedFiles: 3,
    lastUploadedFiles: 1,
    lastMovedFiles: 0,
    lastDeletedFiles: 0,
    lastErrorCode: lastErrorCode,
    lastError: lastError,
  );
}
