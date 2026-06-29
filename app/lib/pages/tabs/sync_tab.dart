import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/folder_sync.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/folder_sync_provider.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _selectedReplicaFingerprintProvider = StateProvider<String?>(
  (ref) => null,
  debugLabel: '_selectedReplicaFingerprintProvider',
);

final _pairAllowDestructiveSyncProvider = StateProvider<bool>(
  (ref) => true,
  debugLabel: '_pairAllowDestructiveSyncProvider',
);

class SyncTab extends StatelessWidget {
  const SyncTab();

  @override
  Widget build(BuildContext context) {
    final syncState = context.watch(folderSyncProvider);
    final favorites = context.watch(favoritesProvider);
    final selectedFingerprint = context.watch(_selectedReplicaFingerprintProvider);
    final pairAllowDestructiveSync = context.watch(_pairAllowDestructiveSyncProvider);
    final selectedReplica = _selectedFavorite(favorites, selectedFingerprint);
    final canPickFolder = checkPlatformWithFileSystem();

    return Stack(
      children: [
        ResponsiveListView(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
          children: [
            Text(
              t.syncTab.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 15),
            _FolderSection(
              title: t.syncTab.hostFolder,
              icon: Icons.folder_special,
              folder: syncState.hostFolderPath,
              enabled: canPickFolder,
              onPick: () async => _pickFolder(
                context,
                (path) => context.ref.notifier(folderSyncProvider).setHostFolderPath(path),
              ),
            ),
            const SizedBox(height: 10),
            _HostPairingSection(
              favorites: favorites,
              selectedReplica: selectedReplica,
              allowDestructiveSync: pairAllowDestructiveSync,
              onReplicaChanged: (favorite) {
                context.ref.notifier(_selectedReplicaFingerprintProvider).setState((_) => favorite?.fingerprint);
              },
              onDestructiveChanged: (allowDestructiveSync) {
                context.ref.notifier(_pairAllowDestructiveSyncProvider).setState((_) => allowDestructiveSync);
              },
              onScan: () async => _runAction(
                context,
                () => context.ref.notifier(folderSyncProvider).scanFavorites(),
              ),
              onPair: syncState.hostFolderPath == null || selectedReplica == null
                  ? null
                  : () async => _runAction(
                      context,
                      () => context.ref
                          .notifier(folderSyncProvider)
                          .pairWithReplica(
                            selectedReplica,
                            allowDestructiveSync: pairAllowDestructiveSync,
                          ),
                    ),
            ),
            const SizedBox(height: 10),
            _FolderSection(
              title: t.syncTab.replicaFolder,
              icon: Icons.folder_shared,
              folder: syncState.replicaFolderPath,
              enabled: canPickFolder,
              onPick: () async => _pickFolder(
                context,
                (path) => context.ref.notifier(folderSyncProvider).setReplicaFolderPath(path),
              ),
            ),
            const SizedBox(height: 10),
            _ProfilesSection(profiles: syncState.profiles),
            const SizedBox(height: 50),
          ],
        ),
        checkPlatform([TargetPlatform.macOS]) ? SizedBox(height: 50, child: MoveWindow()) : const SizedBox(height: 0, width: 0),
      ],
    );
  }

  FavoriteDevice? _selectedFavorite(List<FavoriteDevice> favorites, String? fingerprint) {
    if (favorites.isEmpty) {
      return null;
    }
    return favorites.firstWhereOrNull((favorite) => favorite.fingerprint == fingerprint) ?? favorites.first;
  }

  Future<void> _pickFolder(BuildContext context, Future<void> Function(String path) save) async {
    final directory = await pickDirectoryPath();
    if (directory == null || !context.mounted) {
      return;
    }
    await _runAction(context, () => save(directory));
  }
}

class _HostPairingSection extends StatelessWidget {
  final List<FavoriteDevice> favorites;
  final FavoriteDevice? selectedReplica;
  final bool allowDestructiveSync;
  final void Function(FavoriteDevice?) onReplicaChanged;
  final void Function(bool) onDestructiveChanged;
  final Future<void> Function() onScan;
  final Future<void> Function()? onPair;

  const _HostPairingSection({
    required this.favorites,
    required this.selectedReplica,
    required this.allowDestructiveSync,
    required this.onReplicaChanged,
    required this.onDestructiveChanged,
    required this.onScan,
    required this.onPair,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.syncTab.pairing, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selectedReplica?.fingerprint,
              items: favorites
                  .map(
                    (favorite) => DropdownMenuItem(
                      value: favorite.fingerprint,
                      child: Text(favorite.alias),
                    ),
                  )
                  .toList(),
              onChanged: favorites.isEmpty
                  ? null
                  : (fingerprint) {
                      onReplicaChanged(favorites.firstWhereOrNull((favorite) => favorite.fingerprint == fingerprint));
                    },
              decoration: InputDecoration(
                labelText: t.syncTab.replicaFavorite,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: allowDestructiveSync,
              onChanged: onDestructiveChanged,
              title: Text(t.syncTab.allowDestructiveSync),
              subtitle: Text(t.syncTab.allowDestructiveSyncDescription),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.search),
                  label: Text(t.sendTab.scan),
                ),
                FilledButton.icon(
                  onPressed: onPair,
                  icon: const Icon(Icons.link),
                  label: Text(t.syncTab.startPairing),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? folder;
  final bool enabled;
  final Future<void> Function() onPick;

  const _FolderSection({
    required this.title,
    required this.icon,
    required this.folder,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Icon(icon, size: 40),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text(
                    folder ?? t.syncTab.noFolder,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: folder == null ? Colors.grey : null),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.folder_open),
              tooltip: t.syncTab.chooseFolder,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilesSection extends StatelessWidget {
  final List<FolderSyncProfile> profiles;

  const _ProfilesSection({required this.profiles});

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Text(t.syncTab.noPairs),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.syncTab.pairedFolders, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        for (final profile in profiles) ...[
          _ProfileCard(profile: profile),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final FolderSyncProfile profile;

  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final runtime = context.watch(folderSyncProvider.select((state) => state.runtimes[profile.id]));
    final isHost = profile.role == FolderSyncRole.host;
    final needsPairing = profile.syncSecret == null || profile.syncSecret!.isEmpty;
    final status = _profileStatus(runtime, profile);
    final isError = runtime?.status == FolderSyncRuntimeStatus.error || profile.lastErrorCode != null || needsPairing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isHost ? Icons.upload : Icons.download),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${isHost ? t.syncTab.roleHost : t.syncTab.roleReplica} · ${profile.peerAlias}',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isHost ? t.syncTab.directionHostToReplica : t.syncTab.directionReplicaFromHost,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: profile.enabled,
                  onChanged: (enabled) async => _runAction(
                    context,
                    () => context.ref.notifier(folderSyncProvider).setProfileEnabled(profile.id, enabled),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(profile.localFolderPath, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: profile.allowDestructiveSync,
              onChanged: (enabled) async => _runAction(
                context,
                () => context.ref.notifier(folderSyncProvider).setProfileAllowDestructiveSync(profile.id, enabled),
              ),
              title: Text(profile.allowDestructiveSync ? t.syncTab.fullMirror : t.syncTab.uploadChangesOnly),
              subtitle: Text(t.syncTab.allowDestructiveSyncDescription),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(icon: Icons.schedule, label: t.syncTab.lastSync, value: _formatTime(profile.lastSyncFinishedAt ?? profile.lastSyncAt)),
                _StatusChip(icon: Icons.description, label: t.general.files, value: '${profile.lastScannedFiles}'),
                _StatusChip(icon: Icons.upload_file, label: t.syncTab.uploaded, value: '${profile.lastUploadedFiles}'),
                _StatusChip(icon: Icons.drive_file_move, label: t.syncTab.moves, value: '${profile.lastMovedFiles}'),
                _StatusChip(icon: Icons.delete_outline, label: t.general.delete, value: '${profile.lastDeletedFiles}'),
                _StatusChip(icon: Icons.block, label: t.syncTab.skipped, value: '${profile.lastSkippedFiles}'),
                _StatusChip(icon: Icons.error_outline, label: t.syncTab.failed, value: '${profile.lastFailedFiles}'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isError ? Theme.of(context).colorScheme.error : null,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  IconButton(
                    onPressed: checkPlatformWithFileSystem() ? () async => _pickProfileFolder(context, profile.id) : null,
                    icon: const Icon(Icons.folder_open),
                    tooltip: t.syncTab.chooseFolder,
                  ),
                  if (isHost)
                    IconButton(
                      onPressed: profile.enabled
                          ? () async => _runAction(
                              context,
                              () => context.ref.notifier(folderSyncProvider).rePairProfile(profile.id),
                            )
                          : null,
                      icon: const Icon(Icons.link),
                      tooltip: t.syncTab.repair,
                    ),
                  IconButton(
                    onPressed: () async => _runAction(
                      context,
                      () => context.ref.notifier(folderSyncProvider).removeProfile(profile.id),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: t.general.delete,
                  ),
                  if (isHost)
                    FilledButton.icon(
                      onPressed: profile.enabled
                          ? () async => _runAction(
                              context,
                              () => needsPairing
                                  ? context.ref.notifier(folderSyncProvider).rePairProfile(profile.id)
                                  : context.ref.notifier(folderSyncProvider).syncProfile(profile.id),
                            )
                          : null,
                      icon: const Icon(Icons.sync),
                      label: Text(needsPairing ? t.syncTab.repair : t.syncTab.syncNow),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
    );
  }
}

Future<void> _runAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorMessage(e))));
  }
}

Future<void> _pickProfileFolder(BuildContext context, String profileId) async {
  final directory = await pickDirectoryPath();
  if (directory == null || !context.mounted) {
    return;
  }
  await _runAction(
    context,
    () => context.ref.notifier(folderSyncProvider).setProfileFolderPath(profileId, directory),
  );
}

String _formatTime(int? millis) {
  if (millis == null) {
    return t.syncTab.never;
  }
  return DateTime.fromMillisecondsSinceEpoch(millis).toLocal().toString().split('.').first;
}

String _profileStatus(FolderSyncRuntime? runtime, FolderSyncProfile profile) {
  if (runtime != null) {
    switch (runtime.status) {
      case FolderSyncRuntimeStatus.pairing:
        return t.syncTab.statusPairing;
      case FolderSyncRuntimeStatus.scanning:
        return t.syncTab.statusScanning;
      case FolderSyncRuntimeStatus.syncing:
        return t.syncTab.statusSyncing;
      case FolderSyncRuntimeStatus.error:
        return _errorMessage(FolderSyncException(FolderSyncErrorCode.fromJson(runtime.message) ?? FolderSyncErrorCode.unknown));
      case FolderSyncRuntimeStatus.idle:
        break;
    }
  }

  if (profile.syncSecret == null || profile.syncSecret!.isEmpty) {
    return _errorMessage(const FolderSyncException(FolderSyncErrorCode.needsPairing));
  }
  final errorCode = profile.lastErrorCode;
  if (errorCode != null) {
    return _errorMessage(FolderSyncException(errorCode));
  }
  if (profile.lastFailedFiles > 0) {
    return t.syncTab.statusCompletedWithFailures;
  }
  return t.syncTab.ready;
}

String _errorMessage(Object error) {
  final code = error is FolderSyncException ? error.code : FolderSyncErrorCode.unknown;
  switch (code) {
    case FolderSyncErrorCode.alreadyRunning:
      return t.syncTab.errorAlreadyRunning;
    case FolderSyncErrorCode.hostFolderMissing:
      return t.syncTab.errorHostFolderMissing;
    case FolderSyncErrorCode.localFolderUnavailable:
      return t.syncTab.errorLocalFolderUnavailable;
    case FolderSyncErrorCode.needsPairing:
      return t.syncTab.errorNeedsPairing;
    case FolderSyncErrorCode.peerOffline:
      return t.syncTab.errorPeerOffline;
    case FolderSyncErrorCode.pairingFailed:
      return t.syncTab.errorPairingFailed;
    case FolderSyncErrorCode.profileDisabled:
      return t.syncTab.errorProfileDisabled;
    case FolderSyncErrorCode.remoteRejected:
      return t.syncTab.errorRemoteRejected;
    case FolderSyncErrorCode.unknown:
      return t.syncTab.errorUnknown;
  }
}
