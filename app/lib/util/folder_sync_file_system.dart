import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:localsend_app/model/folder_sync.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/content_uri_helper.dart';
import 'package:localsend_app/util/native/file_saver.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:uri_content/uri_content.dart';

final _uriContent = UriContent();

bool isContentFolder(String folderPath) => folderPath.startsWith('content://');

Future<bool> syncFolderExists(String folderPath) async {
  if (isContentFolder(folderPath)) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      await android_channel.listDirectoryAndroid(folderPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  return Directory(folderPath).exists();
}

Future<List<FolderSyncLocalFile>> scanSyncFolder(String folderPath) async {
  if (isContentFolder(folderPath)) {
    return _scanContentFolder(folderPath);
  }

  final root = Directory(folderPath);
  if (!await root.exists()) {
    throw Exception('Folder does not exist: $folderPath');
  }

  final files = <FolderSyncLocalFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final relativePath = normalizeSyncRelativePath(
      p.relative(entity.path, from: root.path).replaceAll('\\', '/'),
    );
    final stat = await entity.stat();
    final hash = await hashSyncFile(entity.openRead());
    files.add(
      FolderSyncLocalFile(
        sourcePath: entity.path,
        entry: FolderSyncManifestEntry(
          path: relativePath,
          size: stat.size,
          modifiedAt: stat.modified.toUtc().millisecondsSinceEpoch,
          hash: hash,
        ),
      ),
    );
  }
  files.sort((a, b) => a.entry.path.compareTo(b.entry.path));
  return files;
}

Future<List<FolderSyncLocalFile>> _scanContentFolder(String folderPath) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw Exception('Content URI folders are only supported on Android.');
  }

  final files = <FolderSyncLocalFile>[];
  final androidFiles = await android_channel.listDirectoryAndroid(folderPath);
  for (final file in androidFiles) {
    final relativePath = normalizeSyncRelativePath(file.name);
    final hash = await hashSyncFile(_uriContent.getContentStream(Uri.parse(file.uri)));
    files.add(
      FolderSyncLocalFile(
        sourcePath: file.uri,
        entry: FolderSyncManifestEntry(
          path: relativePath,
          size: file.size,
          modifiedAt: file.lastModified,
          hash: hash,
        ),
      ),
    );
  }
  files.sort((a, b) => a.entry.path.compareTo(b.entry.path));
  return files;
}

Future<String> hashSyncFile(Stream<List<int>> stream) async {
  return (await sha256.bind(stream).first).toString();
}

Stream<List<int>> openSyncFileRead(String sourcePath) {
  if (sourcePath.startsWith('content://')) {
    return _uriContent.getContentStream(Uri.parse(sourcePath));
  }
  return File(sourcePath).openRead();
}

Future<void> writeSyncFile({
  required String folderPath,
  required String relativePath,
  required Stream<List<int>> stream,
  required int modifiedAt,
}) async {
  final normalizedPath = normalizeSyncRelativePath(relativePath);
  if (isContentFolder(folderPath)) {
    await deleteSyncFile(folderPath: folderPath, relativePath: normalizedPath);
    await saveFile(
      destinationDirectory: folderPath,
      fileName: normalizedPath,
      saveToGallery: false,
      isImage: false,
      stream: stream.map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk)),
      onProgress: (_) {},
      createdDirectories: {},
      androidSdkInt: defaultTargetPlatform == TargetPlatform.android ? 1 : null,
      lastModified: DateTime.fromMillisecondsSinceEpoch(modifiedAt, isUtc: true),
    );
    if (!await _contentFileExists(folderPath, normalizedPath)) {
      throw Exception('Could not write sync file: $normalizedPath');
    }
    return;
  }

  final destination = resolveSyncPath(folderPath, normalizedPath);
  await Directory(p.dirname(destination)).create(recursive: true);

  final tempPath = '$destination.localsend-sync-tmp';
  final tempFile = File(tempPath);
  final sink = tempFile.openWrite();
  try {
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();

    final destinationFile = File(destination);
    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }
    await tempFile.rename(destination);
    await File(destination).setLastModified(DateTime.fromMillisecondsSinceEpoch(modifiedAt, isUtc: true));
  } catch (_) {
    try {
      await sink.close();
    } catch (_) {}
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    rethrow;
  }
}

Future<bool> deleteSyncFile({
  required String folderPath,
  required String relativePath,
}) async {
  final normalizedPath = normalizeSyncRelativePath(relativePath);
  if (isContentFolder(folderPath)) {
    if (!await _contentFileExists(folderPath, normalizedPath)) {
      return false;
    }
    final uri = ContentUriHelper.convertTreeUriToDocumentUri(
      treeUri: folderPath,
      suffix: normalizedPath,
    );
    final deleted = await android_channel.deleteDocumentAndroid(uri);
    if (!deleted) {
      throw Exception('Could not delete sync file: $normalizedPath');
    }
    return true;
  }

  final file = File(resolveSyncPath(folderPath, normalizedPath));
  if (await file.exists()) {
    await file.delete();
    return true;
  }
  return false;
}

Future<bool> moveSyncFile({
  required String folderPath,
  required String from,
  required String to,
}) async {
  final normalizedFrom = normalizeSyncRelativePath(from);
  final normalizedTo = normalizeSyncRelativePath(to);
  if (normalizedFrom == normalizedTo) {
    return true;
  }

  if (isContentFolder(folderPath)) {
    await android_channel.createMissingDirectoriesAndroid(
      parentUri: folderPath,
      fileName: normalizedTo,
      createdDirectories: {},
    );
    final sourceUri = ContentUriHelper.convertTreeUriToDocumentUri(
      treeUri: folderPath,
      suffix: normalizedFrom,
    );
    final sourceParent = _parentPath(normalizedFrom);
    final targetParent = _parentPath(normalizedTo);
    return android_channel.moveDocumentAndroid(
      sourceUri: sourceUri,
      sourceParentUri: ContentUriHelper.convertTreeUriToDocumentUri(
        treeUri: folderPath,
        suffix: sourceParent,
      ),
      targetParentUri: ContentUriHelper.convertTreeUriToDocumentUri(
        treeUri: folderPath,
        suffix: targetParent,
      ),
      targetName: p.url.basename(normalizedTo),
    );
  }

  final source = File(resolveSyncPath(folderPath, normalizedFrom));
  if (!await source.exists()) {
    return false;
  }

  final destination = File(resolveSyncPath(folderPath, normalizedTo));
  await Directory(p.dirname(destination.path)).create(recursive: true);
  if (await destination.exists()) {
    await destination.delete();
  }
  try {
    await source.rename(destination.path);
  } catch (_) {
    await source.copy(destination.path);
    await source.delete();
  }
  return true;
}

Future<void> pruneEmptySyncDirectories(String folderPath) async {
  if (isContentFolder(folderPath)) {
    return;
  }

  final root = Directory(folderPath);
  if (!await root.exists()) {
    return;
  }

  final directories = <Directory>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is Directory) {
      directories.add(entity);
    }
  }

  directories.sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final directory in directories) {
    try {
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    } catch (_) {}
  }
}

String resolveSyncPath(String folderPath, String relativePath) {
  final normalizedPath = normalizeSyncRelativePath(relativePath);
  final root = p.normalize(Directory(folderPath).absolute.path);
  final destination = p.normalize(p.joinAll([root, ...normalizedPath.split('/')]));
  if (!p.isWithin(root, destination)) {
    throw Exception('Path traversal detected: $relativePath');
  }
  return destination;
}

String normalizeSyncRelativePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.trim().isEmpty || normalized.startsWith('/')) {
    throw Exception('Invalid relative path: $path');
  }

  final parts = <String>[];
  for (final part in normalized.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      throw Exception('Path traversal detected: $path');
    }
    parts.add(part);
  }

  if (parts.isEmpty) {
    throw Exception('Invalid relative path: $path');
  }
  return parts.join('/');
}

String? lookupSyncMimeType(String path) {
  return lookupMimeType(path) ?? 'application/octet-stream';
}

Future<bool> _contentFileExists(String folderPath, String normalizedPath) async {
  final files = await android_channel.listDirectoryAndroid(folderPath);
  return files.any((file) => normalizeSyncRelativePath(file.name) == normalizedPath);
}

String? _parentPath(String relativePath) {
  final parts = relativePath.split('/');
  if (parts.length <= 1) {
    return null;
  }
  return parts.take(parts.length - 1).join('/');
}
