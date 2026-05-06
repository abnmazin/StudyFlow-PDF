import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../models/annotations.dart';
import '../models/isar_models.dart';
import 'file_hash_service.dart';

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
      final oldRoot = Directory(p.join(appDocDir.path, 'StudyFlow'));
      final root = Directory(p.join(appDocDir.path, 'StudyFlowPdf'));

      // Migrate if old exists
      if (await oldRoot.exists() && !await root.exists()) {
        try {
          await oldRoot.rename(root.path);
        } catch (e) {
          debugPrint('Migration failed: $e');
        }
      }

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
        IsarHighlightSchema,
        IsarCommentSchema,
        IsarBookmarkSchema,
        DeletedAnnotationSchema,
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

    // Canonical calculation for metadata (used for both existence check and new records)
    final originalName = p.basename(sourcePath);
    String? fileHash;
    try {
      fileHash = await FileHashService.calculateFileHash(sourcePath);
    } catch (e) {
      debugPrint('⚠️ [FileManagerService] Failed to calculate hash for $sourcePath: $e');
    }

    int totalPages = 0;
    try {
      final pdfDoc = await pdfrx.PdfDocument.openFile(sourcePath);
      totalPages = pdfDoc.pages.length;
      await pdfDoc.dispose();
    } catch (e) {
      debugPrint('⚠️ [FileManagerService] Failed to get page count for $sourcePath: $e');
    }

    // Check if a PDF with this HASH already exists in the requested class
    // (If classId is null, we check globally or in 'quick_access' depending on implementation)
    final existing = await _isar.pdfDocuments
        .filter()
        .fileHashEqualTo(fileHash)
        .and()
        .classIdEqualTo(classId)
        .findFirst();

    if (existing != null) {
      debugPrint('ℹ️ [FileManagerService] Found existing PDF with hash $fileHash in class $classId');
      await _ensureWorkingCopy(existing);
      await _isar.writeTxn(() async {
        existing.lastOpenedAt = DateTime.now();
        // Update metadata if it was missing
        existing.originalDisplayName ??= originalName;
        existing.totalPages = (existing.totalPages == 0) ? totalPages : existing.totalPages;
        await _isar.pdfDocuments.put(existing);
      });
      return existing;
    }

    final uuid = const Uuid().v4();
    final basename = p.basenameWithoutExtension(sourcePath);

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
      originalDisplayName: originalName,
      workingPath: sessionDest,
      workingCreatedAt: DateTime.now(),
      workingModifiedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      fileSize: fileSize,
      classId: classId,
      fileHash: fileHash,
      totalPages: totalPages,
    );

    debugPrint('📁 [FileManagerService] Importing new PDF: $originalName');
    debugPrint('   - Hash: $fileHash');
    debugPrint('   - Pages: $totalPages');
    debugPrint('   - UUID: $uuid');

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

  Future<void> updateReadingState(String pdfUuid, {int? page, double? zoom, double? scroll}) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      final doc = await _isar.pdfDocuments.filter().uuidEqualTo(pdfUuid).findFirst();
      if (doc != null) {
        if (page != null) doc.lastPage = page;
        if (zoom != null) doc.lastZoom = zoom;
        if (scroll != null) doc.lastScroll = scroll;
        doc.lastOpenedAt = DateTime.now();
        await _isar.pdfDocuments.put(doc);
      }
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
    
    // Clean up associated files
    if (item.filePath.isNotEmpty) {
      final f = File(item.filePath);
      if (await f.exists()) await f.delete();
    }
    
    // Clean up history/snapshots for this PDF
    try {
      final snapshots = await _isar.pdfSnapshots.filter().pdfIdEqualTo(item.originalPdfId).findAll();
      for (var s in snapshots) {
        final f = File(s.filePath);
        if (await f.exists()) await f.delete();
      }
      await _isar.writeTxn(() async {
        await _isar.pdfSnapshots.filter().pdfIdEqualTo(item.originalPdfId).deleteAll();
      });
    } catch (e) {
      debugPrint('Error cleaning snapshots during permanent delete: $e');
    }

    // Clean up original record
    try {
      final meta = jsonDecode(item.originalDataJson ?? '{}');
      final originalPath = meta['originalPath'] as String?;
      if (originalPath != null) {
        final f = File(originalPath);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}

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

  // ── 6. Annotation Helpers (Private & Resilient) ──────────────────────────

  Future<List<IsarHighlight>> _getHighlights(String pdfUuid) async {
    try {
      return await _isar.isarHighlights.where().pdfUuidEqualTo(pdfUuid).findAll();
    } catch (e) {
      debugPrint('⚠️ [FileManagerService] Could not query highlights for $pdfUuid using index. Falling back to filter. Error: $e');
      // Fallback for safety, though it should not be needed with the new index.
      return await _isar.isarHighlights.filter().pdfUuidEqualTo(pdfUuid).findAll();
    }
  }

  Future<List<IsarComment>> _getComments(String pdfUuid) async {
    try {
      return await _isar.isarComments.where().pdfUuidEqualTo(pdfUuid).findAll();
    } catch (e) {
      debugPrint('⚠️ [FileManagerService] Could not query comments for $pdfUuid using index. Falling back to filter. Error: $e');
      return await _isar.isarComments.filter().pdfUuidEqualTo(pdfUuid).findAll();
    }
  }

  Future<List<IsarBookmark>> _getBookmarks(String pdfUuid) async {
    try {
      return await _isar.isarBookmarks.where().pdfUuidEqualTo(pdfUuid).findAll();
    } catch (e) {
      debugPrint('⚠️ [FileManagerService] Could not query bookmarks for $pdfUuid using index. Falling back to filter. Error: $e');
      return await _isar.isarBookmarks.filter().pdfUuidEqualTo(pdfUuid).findAll();
    }
  }

  // ── 7. Folders ─────────────────────────────────────────────────────────────

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

  // ── 8. Migration ──────────────────────────────────────────────────────────

  /// Merges legacy data from SharedPreferences classes into Isar.
  /// This is an idempotent operation.
  Future<void> migrateFromLegacyPrefs(dynamic legacyClassesRaw) async {
    if (!_isInitialized) await init();
    if (legacyClassesRaw == null || legacyClassesRaw is! List) return;

    debugPrint('🚀 [FileManagerService] Starting Legacy Prefs Migration...');
    int folderCount = 0;
    int pdfCount = 0;

    await _isar.writeTxn(() async {
      for (final clsJson in legacyClassesRaw) {
        if (clsJson is! Map<String, dynamic>) continue;

        final String uuid = clsJson['id']?.toString() ?? '';
        final String name = clsJson['name']?.toString() ?? 'بدون اسم';
        final List pdfsJson = clsJson['pdfs'] as List? ?? [];

        // Check if folder exists
        var folder =
            await _isar.classFolders.filter().uuidEqualTo(uuid).findFirst();

        if (folder == null) {
          folder = ClassFolder.create(uuid: uuid, name: name);
          await _isar.classFolders.put(folder);
          folderCount++;
        }

        // Migrate PDFs
        for (final pdfJson in pdfsJson) {
          if (pdfJson is! Map<String, dynamic>) continue;

          final String pUuid = pdfJson['id']?.toString() ?? '';
          final String pPath = pdfJson['path']?.toString() ?? '';
          final int? pLastPage = pdfJson['lastPage'];
          final double? pScroll = (pdfJson['scrollTop'] as num?)?.toDouble();

          // Check if document exists by UUID or original path
          var doc =
              await _isar.pdfDocuments.filter().uuidEqualTo(pUuid).findFirst();

          if (doc == null) {
            doc = PdfDocument.create(
              uuid: pUuid,
              originalPath: pdfJson['originalPath'] ?? pPath,
              workingPath: pPath,
              classId: uuid,
              fileHash: pdfJson['fileHash'],
              lastPage: pLastPage ?? 1,
              lastScroll: pScroll ?? 0.0,
              totalPages: (pdfJson['pageCount'] as num?)?.toInt() ?? 0,
            );
            await _isar.pdfDocuments.put(doc);
            pdfCount++;
          }
        }
      }
    });

    debugPrint(
      '✅ [FileManagerService] Migration finished: $folderCount classes, $pdfCount pdfs migrated.',
    );
    _notify();
  }

  Future<void> updateFolderSelection(String folderUuid, String? lastActivePdfId) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      final folder = await _isar.classFolders.filter().uuidEqualTo(folderUuid).findFirst();
      if (folder != null) {
        folder.lastActivePdfId = lastActivePdfId;
        await _isar.classFolders.put(folder);
      }
    });
  }

  Future<void> updateFolderOrder(List<String> folderUuids) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      for (int i = 0; i < folderUuids.length; i++) {
        final folder = await _isar.classFolders.filter().uuidEqualTo(folderUuids[i]).findFirst();
        if (folder != null) {
          folder.orderIndex = i;
          await _isar.classFolders.put(folder);
        }
      }
    });
    _notify();
  }

  Future<void> updatePdfOrder(String folderUuid, List<String> pdfUuids) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      final folder = await _isar.classFolders.filter().uuidEqualTo(folderUuid).findFirst();
      if (folder != null) {
        folder.pdfIds = List<String>.from(pdfUuids);
        await _isar.classFolders.put(folder);
      }
    });
    _notify();
  }

  Future<void> movePdf(String pdfUuid, String fromFolderUuid, String toFolderUuid) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      // 1. Update Document
      final doc = await _isar.pdfDocuments.filter().uuidEqualTo(pdfUuid).findFirst();
      if (doc != null) {
        doc.classId = toFolderUuid;
        await _isar.pdfDocuments.put(doc);
      }

      // 2. Remove from Source
      final source = await _isar.classFolders.filter().uuidEqualTo(fromFolderUuid).findFirst();
      if (source != null) {
        final updatedSource = List<String>.from(source.pdfIds);
        updatedSource.remove(pdfUuid);
        source.pdfIds = updatedSource;
        if (source.lastActivePdfId == pdfUuid) source.lastActivePdfId = null;
        await _isar.classFolders.put(source);
      }

      // 3. Add to Target
      final target = await _isar.classFolders.filter().uuidEqualTo(toFolderUuid).findFirst();
      if (target != null) {
        final updatedTarget = List<String>.from(target.pdfIds);
        if (!updatedTarget.contains(pdfUuid)) {
          updatedTarget.add(pdfUuid);
        }
        target.pdfIds = updatedTarget;
        await _isar.classFolders.put(target);
      }
    });

    _notify();
  }

  Future<void> deleteFolder(String uuid) async {
    if (!_isInitialized) await init();

    // 1. Find all documents belonging to this folder
    final docs = await getDocumentsInFolder(uuid);

    // 2. Delete each document (this handles annotations and files)
    for (var doc in docs) {
      try {
        await deleteDocument(doc.uuid);
      } catch (e) {
        debugPrint('⚠️ [FileManagerService] Failed to delete document ${doc.uuid} while deleting folder $uuid. Skipping. Error: $e');
      }
    }

    // 3. Delete the folder itself
    await _isar.writeTxn(() async {
      final folder = await _isar.classFolders.filter().uuidEqualTo(uuid).findFirst();
      if (folder != null) {
        await _isar.classFolders.delete(folder.id);
      }
    });

    _notify();
  }

  Future<void> deleteDocument(String uuid) async {
    if (!_isInitialized) await init();

    debugPrint('🗑️ [FileManagerService] deleteDocument شروع: $uuid');

    try {
      // 1. Find the document metadata
      final doc = await _isar.pdfDocuments.filter().uuidEqualTo(uuid).findFirst();
      if (doc == null) {
        debugPrint('ℹ️ [FileManagerService] deleteDocument called for a non-existent document: $uuid');
        return;
      }

      final String? workingPath = doc.workingPath;
      final String? classId = doc.classId;

      await _isar.writeTxn(() async {
        // 2. Remove document ID from the parent folder's list
        if (classId != null) {
          final folder = await _isar.classFolders.filter().uuidEqualTo(classId).findFirst();
          if (folder != null) {
            final updatedList = List<String>.from(folder.pdfIds);
            updatedList.remove(uuid);
            folder.pdfIds = updatedList;
            if (folder.lastActivePdfId == uuid) folder.lastActivePdfId = null;
            await _isar.classFolders.put(folder);
            debugPrint('🗑️ [FileManagerService] Removed $uuid from folder $classId pdfIds');
          }
        }

        // 3. Clean up all associated annotations from Isar using index-based queries
        await _isar.isarHighlights.where().pdfUuidEqualTo(uuid).deleteAll();
        debugPrint('🗑️ [FileManagerService] Deleted highlights for $uuid');

        await _isar.isarComments.where().pdfUuidEqualTo(uuid).deleteAll();
        debugPrint('🗑️ [FileManagerService] Deleted comments for $uuid');

        await _isar.isarBookmarks.where().pdfUuidEqualTo(uuid).deleteAll();
        debugPrint('🗑️ [FileManagerService] Deleted bookmarks for $uuid');

        // 4. Delete the main document record
        await _isar.pdfDocuments.where().uuidEqualTo(uuid).deleteFirst();
        debugPrint('🗑️ [FileManagerService] Deleted PdfDocument row for $uuid');
      });

      // 5. Safe Deletion of physical files
      final bool isManagedOriginal = doc.originalPath.startsWith(_originalsDir.path);

      for (var path in [workingPath, isManagedOriginal ? doc.originalPath : null]) {
        if (path != null) {
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
              debugPrint('🗑️ [FileManagerService] Deleted physical PDF (${path == workingPath ? "working" : "original"}): $path');
            }
          } catch (e) {
            debugPrint('⚠️ [FileManagerService] Failed to delete physical file $path: $e');
          }
        }
      }

      debugPrint('✅ [FileManagerService] deleteDocument completed: $uuid');
      _notify();
    } catch (e) {
      debugPrint('❌ [FileManagerService] deleteDocument failed for $uuid: $e');
      rethrow;
    }
  }

  // ── 10. Annotations (High Level - Model Based) ───────────────────────────

  /// Saves runtime [Highlight] models to Isar for a specific PDF.
  /// Handles orphaned record deletion and preserves sync metadata.
  Future<void> saveHighlights(String pdfUuid, List<Highlight> highlights) async {
    if (!_isInitialized) await init();

    // 1. Deduplicate incoming by uuid (keeping the last one)
    final Map<String, Highlight> dedupedMap = {};
    for (var h in highlights) {
      if (h.id.isEmpty) {
        debugPrint('[Isar Upsert] Skipped invalid empty highlight uuid');
        continue;
      }
      if (dedupedMap.containsKey(h.id)) {
        debugPrint('[Isar Upsert] Dropped duplicate incoming Highlight uuid: ${h.id}');
      }
      dedupedMap[h.id] = h;
    }
    final finalIncoming = dedupedMap.values.toList();

    await _isar.writeTxn(() async {
      // 2. Load existing records for this PDF
      final existingRecords = await _isar.isarHighlights.filter().pdfUuidEqualTo(pdfUuid).findAll();
      final Map<String, int> uuidToIdMap = {for (var r in existingRecords) r.uuid: r.id};

      debugPrint('[Isar Upsert] Existing highlights for PDF $pdfUuid: ${existingRecords.length}');

      // 3. Reconcile Incoming with Existing
      final List<IsarHighlight> toPut = [];
      final Set<String> incomingUuids = {};
      int reusedCount = 0;
      int newCount = 0;

      for (var h in finalIncoming) {
        final isarH = _toIsarHighlight(pdfUuid, h);
        if (uuidToIdMap.containsKey(isarH.uuid)) {
          isarH.id = uuidToIdMap[isarH.uuid]!; // Reuse existing Isar row ID
          reusedCount++;
        } else {
          newCount++;
        }
        toPut.add(isarH);
        incomingUuids.add(isarH.uuid);
      }

      // 4. Identify and delete Orphans
      final orphanedIds = existingRecords.where((e) => !incomingUuids.contains(e.uuid)).map((e) => e.id).toList();
      if (orphanedIds.isNotEmpty) {
        debugPrint('[Isar Upsert] Deleted orphaned highlights: ${orphanedIds.length}');
        await _isar.isarHighlights.deleteAll(orphanedIds);
      }

      debugPrint('[Isar Upsert] Reconciled highlights: $reusedCount restored ID, $newCount new items');

      // 5. Final Upsert
      await _isar.isarHighlights.putAll(toPut);
    });
  }

  /// Saves runtime [PdfComment] models to Isar for a specific PDF.
  Future<void> saveComments(String pdfUuid, List<PdfComment> comments) async {
    if (!_isInitialized) await init();

    // 1. Deduplicate incoming by uuid
    final Map<String, PdfComment> dedupedMap = {};
    for (var c in comments) {
      if (c.id.isEmpty) {
        debugPrint('[Isar Upsert] Skipped invalid empty comment uuid');
        continue;
      }
      if (dedupedMap.containsKey(c.id)) {
        debugPrint('[Isar Upsert] Dropped duplicate incoming Comment uuid: ${c.id}');
      }
      dedupedMap[c.id] = c;
    }
    final finalIncoming = dedupedMap.values.toList();

    await _isar.writeTxn(() async {
      // 2. Load existing
      final existingRecords = await _isar.isarComments.filter().pdfUuidEqualTo(pdfUuid).findAll();
      final Map<String, int> uuidToIdMap = {for (var r in existingRecords) r.uuid: r.id};

      debugPrint('[Isar Upsert] Existing comments for PDF $pdfUuid: ${existingRecords.length}');

      // 3. Reconcile
      final List<IsarComment> toPut = [];
      final Set<String> incomingUuids = {};
      int reusedCount = 0;
      int newCount = 0;

      for (var c in finalIncoming) {
        final isarC = _toIsarComment(pdfUuid, c);
        if (uuidToIdMap.containsKey(isarC.uuid)) {
          isarC.id = uuidToIdMap[isarC.uuid]!;
          reusedCount++;
        } else {
          newCount++;
        }
        toPut.add(isarC);
        incomingUuids.add(isarC.uuid);
      }

      // 4. Delete Orphans
      final orphanedIds = existingRecords.where((e) => !incomingUuids.contains(e.uuid)).map((e) => e.id).toList();
      if (orphanedIds.isNotEmpty) {
        debugPrint('[Isar Upsert] Deleted orphaned comments: ${orphanedIds.length}');
        await _isar.isarComments.deleteAll(orphanedIds);
      }

      debugPrint('[Isar Upsert] Reconciled comments: $reusedCount restored ID, $newCount new items');

      await _isar.isarComments.putAll(toPut);
    });
  }

  /// Saves runtime [PdfBookmark] models to Isar for a specific PDF.
  Future<void> saveBookmarks(String pdfUuid, List<PdfBookmark> bookmarks) async {
    if (!_isInitialized) await init();

    // 1. Deduplicate incoming by uuid
    final Map<String, PdfBookmark> dedupedMap = {};
    for (var b in bookmarks) {
      if (b.id.isEmpty) {
        debugPrint('[Isar Upsert] Skipped invalid empty bookmark uuid');
        continue;
      }
      if (dedupedMap.containsKey(b.id)) {
        debugPrint('[Isar Upsert] Dropped duplicate incoming Bookmark uuid: ${b.id}');
      }
      dedupedMap[b.id] = b;
    }
    final finalIncoming = dedupedMap.values.toList();

    await _isar.writeTxn(() async {
      // 2. Load existing
      final existingRecords = await _isar.isarBookmarks.filter().pdfUuidEqualTo(pdfUuid).findAll();
      final Map<String, int> uuidToIdMap = {for (var r in existingRecords) r.uuid: r.id};

      debugPrint('[Isar Upsert] Existing bookmarks for PDF $pdfUuid: ${existingRecords.length}');

      // 3. Reconcile
      final List<IsarBookmark> toPut = [];
      final Set<String> incomingUuids = {};
      int reusedCount = 0;
      int newCount = 0;

      for (var b in finalIncoming) {
        final isarB = _toIsarBookmark(pdfUuid, b);
        if (uuidToIdMap.containsKey(isarB.uuid)) {
          isarB.id = uuidToIdMap[isarB.uuid]!;
          reusedCount++;
        } else {
          newCount++;
        }
        toPut.add(isarB);
        incomingUuids.add(isarB.uuid);
      }

      // 4. Delete Orphans
      final orphanedIds = existingRecords.where((e) => !incomingUuids.contains(e.uuid)).map((e) => e.id).toList();
      if (orphanedIds.isNotEmpty) {
        debugPrint('[Isar Upsert] Deleted orphaned bookmarks: ${orphanedIds.length}');
        await _isar.isarBookmarks.deleteAll(orphanedIds);
      }

      debugPrint('[Isar Upsert] Reconciled bookmarks: $reusedCount restored ID, $newCount new items');

      await _isar.isarBookmarks.putAll(toPut);
    });
  }

  // ── Annotations (Low Level - Isar Based) ──────────────────────────────────

  /// Loads [IsarHighlight] models from Isar for a specific PDF.
  Future<List<IsarHighlight>> loadHighlightsForPdf(String pdfUuid) async {
    if (!_isInitialized) await init();
    return await _getHighlights(pdfUuid);
  }

  /// Loads [IsarComment] models from Isar for a specific PDF.
  Future<List<IsarComment>> loadCommentsForPdf(String pdfUuid) async {
    if (!_isInitialized) await init();
    return await _getComments(pdfUuid);
  }

  /// Loads [IsarBookmark] models from Isar for a specific PDF.
  Future<List<IsarBookmark>> loadBookmarksForPdf(String pdfUuid) async {
    if (!_isInitialized) await init();
    return await _getBookmarks(pdfUuid);
  }

  Future<void> saveHighlightsForPdf(String pdfUuid, List<IsarHighlight> highlights) async {
    if (!_isInitialized) await init();

    // 1. Deduplicate by uuid
    final Map<String, IsarHighlight> dedupedMap = {};
    for (var h in highlights) {
      if (h.uuid.isEmpty) continue;
      dedupedMap[h.uuid] = h;
    }
    final finalIncoming = dedupedMap.values.toList();

    await _isar.writeTxn(() async {
      // 2. Load existing and Map UUID -> ID
      final existing = await _isar.isarHighlights.filter().pdfUuidEqualTo(pdfUuid).findAll();
      final Map<String, int> uuidToIdMap = {for (var r in existing) r.uuid: r.id};

      final List<IsarHighlight> toPut = [];
      final Set<String> incomingUuids = {};

      for (var h in finalIncoming) {
        h.pdfUuid = pdfUuid;
        if (uuidToIdMap.containsKey(h.uuid)) {
          h.id = uuidToIdMap[h.uuid]!; // REUSE ID
        } else {
          h.id = Isar.autoIncrement; // Ensure it treats as new if not found
        }
        toPut.add(h);
        incomingUuids.add(h.uuid);
      }

      // 3. Delete orphans
      final orphanedIds = existing.where((e) => !incomingUuids.contains(e.uuid)).map((e) => e.id).toList();
      if (orphanedIds.isNotEmpty) {
        await _isar.isarHighlights.deleteAll(orphanedIds);
      }

      // 4. Save reconciled list
      await _isar.isarHighlights.putAll(toPut);
    });
  }

  Future<void> saveCommentsForPdf(String pdfUuid, List<IsarComment> comments) async {
    if (!_isInitialized) await init();

    final Map<String, IsarComment> dedupedMap = {};
    for (var c in comments) {
      if (c.uuid.isEmpty) continue;
      dedupedMap[c.uuid] = c;
    }
    final finalIncoming = dedupedMap.values.toList();

    await _isar.writeTxn(() async {
      final existing = await _isar.isarComments.filter().pdfUuidEqualTo(pdfUuid).findAll();
      final Map<String, int> uuidToIdMap = {for (var r in existing) r.uuid: r.id};

      final List<IsarComment> toPut = [];
      final Set<String> incomingUuids = {};

      for (var c in finalIncoming) {
        c.pdfUuid = pdfUuid;
        if (uuidToIdMap.containsKey(c.uuid)) {
          c.id = uuidToIdMap[c.uuid]!; // REUSE ID
        } else {
          c.id = Isar.autoIncrement;
        }
        toPut.add(c);
        incomingUuids.add(c.uuid);
      }

      final orphanedIds = existing.where((e) => !incomingUuids.contains(e.uuid)).map((e) => e.id).toList();
      if (orphanedIds.isNotEmpty) {
        await _isar.isarComments.deleteAll(orphanedIds);
      }

      await _isar.isarComments.putAll(toPut);
    });
  }

  Future<void> saveBookmarksForPdf(String pdfUuid, List<IsarBookmark> bookmarks) async {
    if (!_isInitialized) await init();

    final Map<String, IsarBookmark> dedupedMap = {};
    for (var b in bookmarks) {
      if (b.uuid.isEmpty) continue;
      dedupedMap[b.uuid] = b;
    }
    final finalIncoming = dedupedMap.values.toList();

    await _isar.writeTxn(() async {
      final existing = await _isar.isarBookmarks.filter().pdfUuidEqualTo(pdfUuid).findAll();
      final Map<String, int> uuidToIdMap = {for (var r in existing) r.uuid: r.id};

      final List<IsarBookmark> toPut = [];
      final Set<String> incomingUuids = {};

      for (var b in finalIncoming) {
        b.pdfUuid = pdfUuid;
        if (uuidToIdMap.containsKey(b.uuid)) {
          b.id = uuidToIdMap[b.uuid]!; // REUSE ID
        } else {
          b.id = Isar.autoIncrement;
        }
        toPut.add(b);
        incomingUuids.add(b.uuid);
      }

      final orphanedIds = existing.where((e) => !incomingUuids.contains(e.uuid)).map((e) => e.id).toList();
      if (orphanedIds.isNotEmpty) {
        await _isar.isarBookmarks.deleteAll(orphanedIds);
      }

      await _isar.isarBookmarks.putAll(toPut);
    });
  }

  /// One-time idempotent migration fromlegacy blob
  Future<bool> migrateAnnotationsFromBlob(Map<String, dynamic> blobData) async {
    if (!_isInitialized) await init();
    try {
      await _isar.writeTxn(() async {
        for (final entry in blobData.entries) {
          final pdfUuid = entry.key;
          final data = entry.value as Map<String, dynamic>;

          // 1. Delete existing for THIS pdf (Safe ONLY for migration)
          await _isar.isarHighlights.filter().pdfUuidEqualTo(pdfUuid).deleteAll();
          await _isar.isarComments.filter().pdfUuidEqualTo(pdfUuid).deleteAll();
          await _isar.isarBookmarks.filter().pdfUuidEqualTo(pdfUuid).deleteAll();

          // 2. Migration: Highlights
          if (data.containsKey('highlights')) {
            final highlights = (data['highlights'] as List).map((hJson) {
              final h = _mapJsonToIsarHighlight(hJson);
              h.pdfUuid = pdfUuid;
              return h;
            }).toList();
            await _isar.isarHighlights.putAll(highlights);
          }

          // 3. Migration: Comments
          if (data.containsKey('comments')) {
            final comments = (data['comments'] as List).map((cJson) {
              final c = _mapJsonToIsarComment(cJson);
              c.pdfUuid = pdfUuid;
              return c;
            }).toList();
            await _isar.isarComments.putAll(comments);
          }

          // 4. Migration: Bookmarks
          if (data.containsKey('bookmarks')) {
            final bookmarks = (data['bookmarks'] as List).map((bJson) {
              final b = _mapJsonToIsarBookmark(bJson);
              b.pdfUuid = pdfUuid;
              return b;
            }).toList();
            await _isar.isarBookmarks.putAll(bookmarks);
          }
        }
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ Migration failed: $e');
      return false;
    }
  }

  // ── Mapping Helpers (Model -> Isar) ───────────────────────────────────────

  IsarHighlight _toIsarHighlight(String pdfUuid, Highlight h) {
    return IsarHighlight()
      ..uuid = h.id
      ..pdfUuid = pdfUuid
      ..page = h.page
      ..color = h.color.value
      ..strokeWidth = h.strokeWidth
      ..type = h.type.toString()
      ..backgroundColor = h.backgroundColor
      ..isSynced = h.isSynced
      ..updatedAt = h.updatedAt
      ..path = h.path.map((o) => (IsarPoint()
        ..dx = o.dx
        ..dy = o.dy)
      ).toList()
      ..rects = h.rects?.map((r) => (IsarRect()
        ..left = r.left
        ..top = r.top
        ..right = r.right
        ..bottom = r.bottom)
      ).toList();
  }

  IsarComment _toIsarComment(String pdfUuid, PdfComment c) {
    return IsarComment()
      ..uuid = c.id
      ..pdfUuid = pdfUuid
      ..createdBy = c.createdBy ?? ''
      ..page = c.page
      ..content = c.content
      ..attachedMediaUrl = c.attachedMediaUrl ?? ''
      ..date = c.date
      ..color = c.color.value
      ..fontSize = c.fontSize
      ..isBold = c.isBold
      ..isLatex = c.isLatex
      ..fontFamily = c.fontFamily
      ..showBorder = c.showBorder
      ..borderColor = c.borderColor.value
      ..bgColor = c.bgColor.value
      ..isSynced = c.isSynced
      ..updatedAt = c.updatedAt
      ..mediaHeight = c.mediaHeight
      ..position = (IsarPoint()
        ..dx = c.position.dx
        ..dy = c.position.dy);
  }

  IsarBookmark _toIsarBookmark(String pdfUuid, PdfBookmark b) {
    return IsarBookmark()
      ..uuid = b.id
      ..pdfUuid = pdfUuid
      ..page = b.page
      ..name = b.name;
  }

  // ── Mapping Helpers (JSON -> Isar) ─────────────────────────────────────────

  IsarHighlight _mapJsonToIsarHighlight(Map<String, dynamic> json) {
    return IsarHighlight()
      ..uuid = json['id'] ?? ''
      ..path = (json['path'] as List?)?.map((p) => (IsarPoint()
        ..dx = (p['dx'] as num?)?.toDouble()
        ..dy = (p['dy'] as num?)?.toDouble())
      ).toList() ?? []
      ..color = json['color'] ?? 0
      ..page = json['page'] ?? 1
      ..strokeWidth = (json['strokeWidth'] as num?)?.toDouble() ?? 5.0
      ..type = json['type'] ?? ''
      ..isSynced = json['isSynced'] ?? false
      ..updatedAt = json['updatedAt'] ?? 0
      ..backgroundColor = json['backgroundColor']
      ..rects = (json['rects'] as List?)?.map((r) => (IsarRect()
        ..left = (r['L'] as num?)?.toDouble()
        ..top = (r['T'] as num?)?.toDouble()
        ..right = (r['R'] as num?)?.toDouble()
        ..bottom = (r['B'] as num?)?.toDouble())
      ).toList();
  }

  IsarComment _mapJsonToIsarComment(Map<String, dynamic> json) {
    return IsarComment()
      ..uuid = json['id'] ?? ''
      ..createdBy = (json['createdBy'] as String?) ?? ''
      ..page = json['page'] ?? 1
      ..content = json['content'] ?? ''
      ..attachedMediaUrl =
          (json['attachedMediaUrl'] as String?) ??
          (json['mediaUrl'] as String?) ??
          ''
      ..date = json['date'] != null ? DateTime.parse(json['date']) : DateTime.now()
      ..color = json['color'] ?? 0
      ..fontSize = (json['fontSize'] as num?)?.toDouble() ?? 14.0
      ..isBold = json['isBold'] ?? false
      ..isLatex = json['isLatex'] ?? false
      ..fontFamily = json['fontFamily'] ?? 'Times New Roman'
      ..showBorder = json['showBorder'] ?? true
      ..borderColor = json['borderColor'] ?? 0
      ..bgColor = json['bgColor'] ?? 0
      ..isSynced = json['isSynced'] ?? false
      ..updatedAt = json['updatedAt'] ?? 0
      ..mediaHeight = (json['mediaHeight'] as num?)?.toDouble()
      ..position = (IsarPoint()
        ..dx = (json['dx'] as num?)?.toDouble()
        ..dy = (json['dy'] as num?)?.toDouble());
  }

  IsarBookmark _mapJsonToIsarBookmark(Map<String, dynamic> json) {
    return IsarBookmark()
      ..uuid = json['id'] ?? ''
      ..page = json['page'] ?? 1
      ..name = json['name'] ?? '';
  }

  // ── 10. Document Retrieval Methods ────────────────────────────────────────

  /// Get all documents from the database
  Future<List<PdfDocument>> getAllDocuments() async {
    if (!_isInitialized) await init();
    return _isar.pdfDocuments.where().findAll();
  }

  /// Get recent documents, optionally limited
  Future<List<PdfDocument>> getRecentDocuments({int limit = 10}) async {
    if (!_isInitialized) await init();
    return _isar.pdfDocuments
        .where()
        .sortByLastOpenedAtDesc()
        .limit(limit)
        .findAll();
  }

  /// Get all documents in a specific folder
  Future<List<PdfDocument>> getDocumentsInFolder(String folderUuid) async {
    if (!_isInitialized) await init();
    return _isar.pdfDocuments
        .filter()
        .classIdEqualTo(folderUuid)
        .findAll();
  }

  // ── 11. Study Tasks ────────────────────────────────────────────────────────

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

  // ── 12. Deleted Annotations (Trash) ────────────────────────────────────────

  Future<void> saveDeletedAnnotation(DeletedAnnotation deleted) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      await _isar.deletedAnnotations.put(deleted);
    });
    _notify();
  }

  Future<List<DeletedAnnotation>> getDeletedAnnotations() async {
    if (!_isInitialized) await init();
    return _isar.deletedAnnotations.where().sortByDeletedAtDesc().findAll();
  }

  Future<List<DeletedAnnotation>> getUnsyncedDeletedAnnotations() async {
    if (!_isInitialized) await init();
    return _isar.deletedAnnotations.filter().isSyncedEqualTo(false).findAll();
  }

  Future<void> markDeletedAnnotationsAsSynced(List<int> ids) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      for (final id in ids) {
        final item = await _isar.deletedAnnotations.get(id);
        if (item != null) {
          item.isSynced = true;
          await _isar.deletedAnnotations.put(item);
        }
      }
    });
  }

  Future<void> saveRemoteDeletedAnnotations(
    List<DeletedAnnotation> items,
  ) async {
    if (!_isInitialized) await init();
    await _isar.writeTxn(() async {
      for (final item in items) {
        // Check if we already have it
        final existing = await _isar.deletedAnnotations
            .filter()
            .originalIdEqualTo(item.originalId)
            .findFirst();
        if (existing == null) {
          await _isar.deletedAnnotations.put(item);
        }
      }
    });
    _notify();
  }
}
