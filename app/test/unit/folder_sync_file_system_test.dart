import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/util/folder_sync_file_system.dart';
import 'package:test/test.dart';

void main() {
  group('folder sync file system', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('localsend_sync_test_');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('scans, moves, overwrites and deletes files', () async {
      final source = File('${root.path}/old/name.txt');
      await source.parent.create(recursive: true);
      await source.writeAsString('hello');

      final files = await scanSyncFolder(root.path);
      expect(files.map((file) => file.entry.path), ['old/name.txt']);
      expect(files.single.entry.size, 5);

      final moved = await moveSyncFile(
        folderPath: root.path,
        from: 'old/name.txt',
        to: 'new/name.txt',
      );
      expect(moved, isTrue);
      expect(await source.exists(), isFalse);

      final destination = File('${root.path}/new/name.txt');
      expect(await destination.readAsString(), 'hello');

      await writeSyncFile(
        folderPath: root.path,
        relativePath: 'new/name.txt',
        stream: Stream.value(utf8.encode('changed')),
        modifiedAt: DateTime.utc(2026).millisecondsSinceEpoch,
      );
      expect(await destination.readAsString(), 'changed');

      final deleted = await deleteSyncFile(folderPath: root.path, relativePath: 'new/name.txt');
      await pruneEmptySyncDirectories(root.path);
      expect(deleted, isTrue);
      expect(await destination.exists(), isFalse);
      expect(await Directory('${root.path}/new').exists(), isFalse);
    });

    test('delete returns false for missing files', () async {
      final deleted = await deleteSyncFile(folderPath: root.path, relativePath: 'missing.txt');

      expect(deleted, isFalse);
    });

    test('checks whether a normal sync folder exists', () async {
      expect(await syncFolderExists(root.path), isTrue);
      expect(await syncFolderExists('${root.path}/missing'), isFalse);
    });

    test('rejects path traversal', () {
      expect(() => normalizeSyncRelativePath('../escape.txt'), throwsException);
      expect(() => resolveSyncPath(root.path, '../escape.txt'), throwsException);
    });
  });
}
