import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/isar_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FileManagerService
// Singleton ChangeNotifier — register once in main.dart, access via
//   context.read<FileManagerService>() or context.watch<FileManagerService>()
// ─────────────────────────────────────────────────────────────────────────────

class FileManagerService extends ChangeNotifier {
  // Singleton
  static final FileManagerService _instance = FileManagerService._internal();
  factory FileManagerService() => _instance;
  FileManagerService._internal();

  void _notify() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  // ── State ──────────────────────────────────────────────────────────────────

  late Isar _isar;
  late Directory _originalsDir;
  late Directory _sessionsDir;
  late Directory _historyDir;
  late Directory _trashDir;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Isar get isar => _isar;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final root = Directory(p.join(appDocDir.path, 'StudyFlow'));

      _originalsDir = Directory(p.join(root.path, 'Originals'));
      _sessionsDir = Directory(p.join(root.path, 'Sessions'));
      _historyDir = Directory(p.join(root.path, 'History'));
      _trashDir = Directory(p.join(root.path, 'Trash'));
      final dbDir = Directory(p.join(root.path, 'Database'));

      await Future.wait([
        _originalsDir.create(recursive: true),
        _sessionsDir.create(recursive: true),
        _historyDir.create(recursive: true),
        _trashDir.create(recursive: true),
        dbDir.create(recursive: true),
      ]);

      _isar = await Isar.open([
        ClassFolderSchema,
        PdfDocumentSchema,
        PdfSnapshotSchema,
        TrashItemSchema,
        StudyTaskSchema,
      ], directory: dbDir.path);

      _isInitialized = true;
      _notify();
    } catch (e) {
      debugPrint('[FileManagerService] init error: $e');
      rethrow;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _copyFile(String source, String destination) async {
    final src = File(source);
    if (!await src.exists()) throw Exception('Source not found: $source');
    await src.copy(destination);
  }

  // ── 1. Import & Open ───────────────────────────────────────────────────────

  Future<PdfDocument> importAndOpenPdf(
    String sourcePath, {
    String? classId,
  }) async {
    if (!_isInitialized) await init();

    final existing = await _isar.pdfDocuments
        .filter()
        .originalPathEqualTo(sourcePath)
        .findFirst();

    if (existing != null) {
      await _ensureWorkingCopy(existing);
      await _isar.writeTxn(() async {
        existing.lastOpenedAt = DateTime.now();
        await _isar.pdfDocuments.put(existing);
      });
      return existing;
    }

    final basename = p.basenameWithoutExtension(sourcePath);
    final doc = PdfDocument.create(originalPath: '');
    final uuid = doc.uuid; // already generated

    final originalDest = p.join(_originalsDir.path, '${uuid}_$basename.pdf');
    final sessionDest = p.join(
      _sessionsDir.path,
      '${uuid}_${basename}_working.pdf',
    );

    await _copyFile(sourcePath, originalDest);
    await _copyFile(sourcePath, sessionDest);

    final fileSize = await File(sourcePath).length();

    final newDoc = PdfDocument.create(
      uuid: uuid,
      originalPath: originalDest,
      workingPath: sessionDest,
      workingCreatedAt: DateTime.now(),
      workingModifiedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      fileSize: fileSize,
      classId: classId,
    );

    await _isar.writeTxn(() async {
      await _isar.pdfDocuments.put(newDoc);
    });

    _notify();
    return newDoc;
  }

  Future<void> _ensureWorkingCopy(PdfDocument doc) async {
    if (doc.workingPath == null || !await File(doc.workingPath!).exists()) {
      await _createWorkingCopy(doc);
    }
  }

  Future<void> _createWorkingCopy(PdfDocument doc) async {
    final basename = p.basenameWithoutExtension(doc.originalPath);
    final dest = p.join(
      _sessionsDir.path,
      '${doc.uuid}_${basename}_working.pdf',
    );
    await _copyFile(doc.originalPath, dest);
    await _isar.writeTxn(() async {
      doc.workingPath = dest;
      doc.workingCreatedAt = DateTime.now();
      doc.workingModifiedAt = DateTime.now();
      await _isar.pdfDocuments.put(doc);
    });
  }

  // ── 2. Persist Changes ─────────────────────────────────────────────────────

  Future<void> markSaved(String pdfUuid) async {
    if (!_isInitialized) await init();
    final doc = await _isar.pdfDocuments
        .filter()
        .uuidEqualTo(pdfUuid)
        .findFirst();
    if (doc == null) return;
    await _isar.writeTxn(() async {
      doc.hasUnsavedChanges = false;
      doc.workingModifiedAt = DateTime.now();
      await _isar.pdfDocuments.put(doc);
    });
    _notify();
  }

  Future<void> updateReadingState({
    required String pdfUuid,
    int? page,
    double? zoom,
    double? scroll,
  }) async {
    if (!_isInitialized) await init();
    final doc = await _isar.pdfDocuments
        .filter()
        .uuidEqualTo(pdfUuid)
        .findFirst();
    if (doc == null) return;
    await _isar.writeTxn(() async {
      if (page != null) doc.lastPage = page;
      if (zoom != null) doc.lastZoom = zoom;
      if (scroll != null) doc.lastScroll = scroll;
      await _isar.pdfDocuments.put(doc);
    });
  }

  // ── 3. Snapshots ───────────────────────────────────────────────────────────

  Future<PdfSnapshot> createSnapshot(
    String pdfUuid, {
    String? label,
    String createdBy = 'user',
  }) async {
    if (!_isInitialized) await init();

    final doc = await _isar.pdfDocuments
        .filter()
        .uuidEqualTo(pdfUuid)
        .findFirst();
    if (doc == null) throw Exception('PDF not found: $pdfUuid');
    if (doc.workingPath == null)
      throw Exception('No working copy for: $pdfUuid');

    final count = await _isar.pdfSnapshots
        .filter()
        .pdfIdEqualTo(pdfUuid)
        .count();
    final nextVersion = count + 1;

    final snapshotDest = p.join(
      _historyDir.path,
      '${doc.uuid}_v$nextVersion.pdf',
    );
    await _copyFile(doc.workingPath!, snapshotDest);

    final snapshot = PdfSnapshot.create(
      pdfId: pdfUuid,
      filePath: snapshotDest,
      version: nextVersion,
      description: label,
      annotationCount: doc.annotationCount,
      commentCount: doc.commentCount,
      createdBy: createdBy,
    );

    await _isar.writeTxn(() async {
      await _isar.pdfSnapshots.put(snapshot);
    });

    _notify();
    return snapshot;
  }

  Future<void> restoreSnapshot(String snapshotUuid) async {
    if (!_isInitialized) await init();
    final snapshot = await _isar.pdfSnapshots
        .filter()
        .uuidEqualTo(snapshotUuid)
        .findFirst();
    if (snapshot == null) throw Exception('Snapshot not found: $snapshotUuid');
    final doc = await _isar.pdfDocuments
        .filter()
        .uuidEqualTo(snapshot.pdfId)
        .findFirst();
    if (doc == null) throw Exception('PDF not found for snapshot');

    await _ensureWorkingCopy(doc);
    await File(snapshot.filePath).copy(doc.workingPath!);

    await _isar.writeTxn(() async {
      doc.workingModifiedAt = DateTime.now();
      doc.hasUnsavedChanges = true;
      await _isar.pdfDocuments.put(doc);
    });
    _notify();
  }

  Future<List<PdfSnapshot>> getSnapshots(String pdfUuid) async {
    if (!_isInitialized) await init();
    return _isar.pdfSnapshots
        .filter()
        .pdfIdEqualTo(pdfUuid)
        .sortByVersionDesc()
        .findAll();
  }

  // ── 4. Trash ───────────────────────────────────────────────────────────────

  Future<void> moveToTrash(String pdfUuid) async {
    if (!_isInitialized) await init();
    final doc = await _isar.pdfDocuments
        .filter()
        .uuidEqualTo(pdfUuid)
        .findFirst();
    if (doc == null) throw Exception('PDF not found: $pdfUuid');

    String trashFilePath = '';
    if (doc.workingPath != null) {
      final fileName = p.basename(doc.workingPath!);
      trashFilePath = p.join(_trashDir.path, fileName);
      await File(doc.workingPath!).rename(trashFilePath);
    }

    final metaJson = jsonEncode({
      'uuid': doc.uuid,
      'originalPath': doc.originalPath,
      'classId': doc.classId,
      'tags': doc.tags,
      'isPinned': doc.isPinned,
      'lastPage': doc.lastPage,
      'lastZoom': doc.lastZoom,
    });

    final trashItem = TrashItem.create(
      originalPdfId: pdfUuid,
      name: p.basenameWithoutExtension(doc.originalPath),
      filePath: trashFilePath,
      fileSize: doc.fileSize,
      originalClassId: doc.classId,
      originalDataJson: metaJson,
    );

    await _isar.writeTxn(() async {
      await _isar.trashItems.put(trashItem);
      await _isar.pdfDocuments.delete(doc.id);
    });
    _notify();
  }

  Future<PdfDocument?> restoreFromTrash(String trashUuid) async {
    if (!_isInitialized) await init();
    final item = await _isar.trashItems
        .filter()
        .uuidEqualTo(trashUuid)
        .findFirst();
    if (item == null) throw Exception('Trash item not found: $trashUuid');

    final restored = p.join(_sessionsDir.path, p.basename(item.filePath));
    if (item.filePath.isNotEmpty && await File(item.filePath).exists()) {
      await File(item.filePath).rename(restored);
    }

    Map<String, dynamic> meta = {};
    try {
      if (item.originalDataJson != null) {
        meta = jsonDecode(item.originalDataJson!) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[FileManagerService] meta parse error: $e');
    }

    final doc = PdfDocument.create(
      uuid: item.originalPdfId,
      originalPath: (meta['originalPath'] as String?) ?? '',
      workingPath: restored,
      workingCreatedAt: DateTime.now(),
      workingModifiedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      classId: item.originalClassId,
      fileSize: item.fileSize,
    );

    await _isar.writeTxn(() async {
      await _isar.pdfDocuments.put(doc);
      await _isar.trashItems.delete(item.id);
    });
    _notify();
    return doc;
  }

  Future<void> permanentlyDelete(String trashUuid) async {
    if (!_isInitialized) await init();
    final item = await _isar.trashItems
        .filter()
        .uuidEqualTo(trashUuid)
        .findFirst();
    if (item == null) return;
    if (item.filePath.isNotEmpty) {
      final f = File(item.filePath);
      if (await f.exists()) await f.delete();
    }
    await _isar.writeTxn(() async {
      await _isar.trashItems.delete(item.id);
    });
    _notify();
  }

  // ── 5. Cleanup ─────────────────────────────────────────────────────────────

  Future<void> cleanUp() async {
    if (!_isInitialized) await init();
    final now = DateTime.now();
    final expired = await _isar.trashItems
        .filter()
        .expiresAtLessThan(now)
        .findAll();
    for (final item in expired) {
      try {
        if (item.filePath.isNotEmpty) {
          final f = File(item.filePath);
          if (await f.exists()) await f.delete();
        }
        await _isar.writeTxn(() async {
          await _isar.trashItems.delete(item.id);
        });
      } catch (e) {
        debugPrint('[FileManagerService] cleanUp item error: $e');
      }
    }
    await _cleanOrphanedSessions();
    _notify();
  }

  Future<void> _cleanOrphanedSessions() async {
    try {
      final docs = await _isar.pdfDocuments.where().findAll();
      final activePaths = docs
          .map((d) => d.workingPath)
          .whereType<String>()
          .toSet();
      for (final entity in _sessionsDir.listSync()) {
        if (entity is File && !activePaths.contains(entity.path)) {
          try {
            await entity.delete();
          } catch (e) {
            /* skip */
          }
        }
      }
    } catch (e) {
      debugPrint('[FileManagerService] _cleanOrphanedSessions error: $e');
    }
  }

  // ── 6. Folders ─────────────────────────────────────────────────────────────

  Future<ClassFolder> createFolder({
    required String name,
    String? icon,
    int? color,
  }) async {
    if (!_isInitialized) await init();
    final count = await _isar.classFolders.count();
    final folder = ClassFolder.create(
      name: name,
      icon: icon,
      color: color,
      orderIndex: count,
    );
    await _isar.writeTxn(() async {
      await _isar.classFolders.put(folder);
    });
    _notify();
    return folder;
  }

  Future<List<ClassFolder>> getFoldersOrdered() async {
    if (!_isInitialized) await init();
    return _isar.classFolders.where().sortByOrderIndex().findAll();
  }

  Future<void> deleteFolder(String folderUuid) async {
    if (!_isInitialized) await init();
    final folder = await _isar.classFolders
        .filter()
        .uuidEqualTo(folderUuid)
        .findFirst();
    if (folder == null) return;
    await _isar.writeTxn(() async {
      await _isar.classFolders.delete(folder.id);
    });
    _notify();
  }

  // ── 7. Documents ───────────────────────────────────────────────────────────

  Future<List<PdfDocument>> getDocumentsInFolder(String classId) async {
    if (!_isInitialized) await init();
    return _isar.pdfDocuments.filter().classIdEqualTo(classId).findAll();
  }

  Future<List<PdfDocument>> getAllDocuments() async {
    if (!_isInitialized) await init();
    return _isar.pdfDocuments.where().findAll();
  }

  Future<List<PdfDocument>> searchDocuments(String query) async {
    if (!_isInitialized) await init();
    final lq = query.toLowerCase();
    final all = await _isar.pdfDocuments.where().findAll();
    return all
        .where(
          (d) =>
              d.originalPath.toLowerCase().contains(lq) ||
              d.tags.any((t) => t.toLowerCase().contains(lq)),
        )
        .toList();
  }

  Future<List<PdfDocument>> getRecentDocuments({int limit = 6}) async {
    if (!_isInitialized) await init();
    return _isar.pdfDocuments
        .where()
        .sortByLastOpenedAtDesc()
        .limit(limit)
        .findAll();
  }

  Future<List<TrashItem>> getTrashItems() async {
    if (!_isInitialized) await init();
    return _isar.trashItems.where().sortByDeletedAtDesc().findAll();
  }

  // ── 6. Study Tasks ────────────────────────────────────────────────────────

  Future<List<StudyTask>> getAllTasks() async {
    if (!_isInitialized) await init();
    return _isar.studyTasks.where().sortByCreatedAt().findAll();
  }

  Future<void> saveTask(StudyTask task) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      await _isar.studyTasks.put(task);
    });
    _notify();
  }

  Future<void> deleteTaskByUuid(String uuid) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      await _isar.studyTasks.filter().uuidEqualTo(uuid).deleteFirst();
    });
    _notify();
  }
}
