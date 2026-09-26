import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:isar/isar.dart';

import '../models/app_user.dart';
import '../models/university_folder.dart';
import '../models/university_file.dart';
import '../models/university_video.dart';
import '../models/isar_models.dart';
import 'file_hash_service.dart';
import 'file_manager_service.dart';
import 'library_sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UniversityService
// Singleton service handling all multi-tenant university backend operations:
//   - Folder CRUD (Admin only for writes, scoped to user's universityId)
//   - File upload/download with hash-based dedup and local cache
//   - Reading progress sync across devices
// ─────────────────────────────────────────────────────────────────────────────

class UniversityService {
  // Singleton
  static final UniversityService _instance = UniversityService._internal();
  factory UniversityService() => _instance;
  UniversityService._internal();

  // ── Dependencies ──────────────────────────────────────────────────────────

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  SupabaseClient get _supabase => Supabase.instance.client;
  final FileManagerService _fileManager = FileManagerService();

  // Bucket name for university PDFs
  static const String _bucketName = 'university-pdfs';

  // ── Internal State ────────────────────────────────────────────────────────

  bool _isInitialized = false;

  /// User must be set via [init] before any operations.
  AppUser? _currentUser;
  AppUser get currentUser {
    final user = _currentUser;
    if (user == null) {
      throw StateError(
        'UniversityService not initialized. Call init(user) first.',
      );
    }
    return user;
  }

  String get _universityId => currentUser.universityId ?? '';
  String get _userId => currentUser.uid;

  // ── Initialization ────────────────────────────────────────────────────────

  /// Must be called once with the authenticated user before any service calls.
  Future<void> init(AppUser user) async {
    if (_isInitialized && _currentUser?.uid == user.uid) return;
    _currentUser = user;
    await _fileManager.init();
    _isInitialized = true;
  }

  /// Update the current user (e.g., after profile refresh).
  void updateUser(AppUser user) {
    _currentUser = user;
  }

  /// Returns true if the service is properly initialized and the user has a universityId.
  /// Use this for graceful fallback instead of catching exceptions.
  bool get isReady => _isInitialized && _currentUser != null && _universityId.isNotEmpty;

  void _ensureInitialized() {
    if (!_isInitialized || _currentUser == null) {
      throw StateError(
        'UniversityService not initialized. Call init(user) first.',
      );
    }
    if (_universityId.isEmpty) {
      debugPrint(
        '⚠️ [UniversityService] User has no universityId assigned. '
        'Skipping university operation.',
      );
      return; // Graceful exit instead of throw — allows read-only fallback
    }
  }

  /// Asserts that the current user is an admin. Throws otherwise.
  void _assertAdmin() {
    if (!currentUser.isAdmin) {
      throw UnsupportedError(
        'Only admins can perform this operation. '
        'Current role: ${currentUser.role}',
      );
    }
  }

  // =========================================================================
  // SECTION 1: FOLDER CRUD
  // =========================================================================

  /// Fetches all folders for the current user's university (excluding soft-deleted).
  Future<List<UniversityFolder>> getFolders() async {
    _ensureInitialized();

    final snapshot = await _firestore
        .collection('university_folders')
        .where('universityId', isEqualTo: _universityId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('sortOrder', descending: false)
        .get();

    final folders = snapshot.docs
        .map((doc) => UniversityFolder.fromFirestore(doc.id, doc.data()))
        .toList();

    debugPrint(
      '📂 [UniversityService] Fetched ${folders.length} folders for university $_universityId',
    );
    return folders;
  }

  /// Streams folders in real-time for the current user's university.
  Stream<List<UniversityFolder>> streamFolders() {
    _ensureInitialized();

    return _firestore
        .collection('university_folders')
        .where('universityId', isEqualTo: _universityId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('sortOrder', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UniversityFolder.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  /// Creates a new folder (Admin only).
  Future<UniversityFolder> createFolder({
    required String name,
    int sortOrder = 0,
  }) async {
    _ensureInitialized();
    _assertAdmin();

    final folderRef = _firestore.collection('university_folders').doc();

    final folder = UniversityFolder(
      id: folderRef.id,
      universityId: _universityId,
      name: name.trim(),
      createdBy: _userId,
      createdAt: DateTime.now(),
      isDeleted: false,
      sortOrder: sortOrder,
    );

    await folderRef.set(folder.toJson());

    debugPrint(
      '📂 [UniversityService] Created folder "${folder.name}" (${folder.id})',
    );
    return folder;
  }

  /// Updates folder metadata (Admin only).
  Future<void> updateFolder({
    required String folderId,
    String? name,
    int? sortOrder,
  }) async {
    _ensureInitialized();
    _assertAdmin();

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name.trim();
    if (sortOrder != null) updates['sortOrder'] = sortOrder;

    if (updates.isNotEmpty) {
      await _firestore
          .collection('university_folders')
          .doc(folderId)
          .update(updates);

      debugPrint(
        '📂 [UniversityService] Updated folder $folderId: $updates',
      );
    }
  }

  /// Soft-deletes a folder (Admin only).
  Future<void> deleteFolder(String folderId) async {
    _ensureInitialized();
    _assertAdmin();

    // Soft-delete the folder itself.
    await _firestore
        .collection('university_folders')
        .doc(folderId)
        .update({'isDeleted': true});

    // Also soft-delete any video links inside the folder so they stop
    // showing for every member.
    final videos = await _firestore
        .collection('university_videos')
        .where('universityId', isEqualTo: _universityId)
        .where('folderId', isEqualTo: folderId)
        .where('isDeleted', isEqualTo: false)
        .get();
    final batch = _firestore.batch();
    for (final doc in videos.docs) {
      batch.update(doc.reference, {'isDeleted': true});
    }
    await batch.commit();

    debugPrint(
      '📂 [UniversityService] Soft-deleted folder $folderId',
    );
  }

  // =========================================================================
  // SECTION 2: FILE LISTING
  // =========================================================================

  /// Fetches all files in a specific folder for the current user's university.
  Future<List<UniversityFile>> getFilesInFolder(String folderId) async {
    _ensureInitialized();

    final snapshot = await _firestore
        .collection('university_files')
        .where('universityId', isEqualTo: _universityId)
        .where('folderId', isEqualTo: folderId)
        .where('isDeleted', isEqualTo: false)
        .get();

    return snapshot.docs
        .map((doc) => UniversityFile.fromFirestore(doc.id, doc.data()))
        .toList()
      ..sort(_compareFiles);
  }

  /// Sorts by the manual [UniversityFile.sortOrder] first (drag & drop), then
  /// by upload time (oldest first) so legacy files (all sortOrder 0) keep
  /// their original display order.
  static int _compareFiles(UniversityFile a, UniversityFile b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.uploadedAt.compareTo(b.uploadedAt);
  }

  /// Streams files in a folder in real-time.
  Stream<List<UniversityFile>> streamFilesInFolder(String folderId) {
    _ensureInitialized();

    return _firestore
        .collection('university_files')
        .where('universityId', isEqualTo: _universityId)
        .where('folderId', isEqualTo: folderId)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UniversityFile.fromFirestore(doc.id, doc.data()))
            .toList()
          ..sort(_compareFiles));
  }

  /// Looks up a university library file by its content hash. Used by the
  /// document settings to surface the per-file sync code for an open PDF
  /// that came from the university library. Returns `null` when the user has
  /// no university, is not inited, or no file matches.
  Future<UniversityFile?> findUniversityFileByHash(String fileHash) async {
    if (!isReady || fileHash.isEmpty) return null;
    try {
      final snapshot = await _firestore
          .collection('university_files')
          .where('universityId', isEqualTo: _universityId)
          .where('fileHash', isEqualTo: fileHash)
          .where('isDeleted', isEqualTo: false)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      return UniversityFile.fromFirestore(
        snapshot.docs.first.id,
        snapshot.docs.first.data(),
      );
    } catch (e) {
      debugPrint('⚠️ [UniversityService] findUniversityFileByHash failed: $e');
      return null;
    }
  }

  // =========================================================================
  // SECTION 3: UPLOAD PIPELINE (ADMIN)
  // =========================================================================

  /// Replaces characters that Supabase Storage rejects in object keys
  /// (spaces, non-ASCII/Arabic, reserved symbols) with '_', collapses runs of
  /// '_', and trims leading/trailing '_'. Result uses only [A-Za-z0-9._-].
  String _sanitizeStorageSegment(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned;
  }

  /// Sanitizes a display file name for use as the final storage key segment,
  /// keeping the original extension. Falls back to a timestamped ASCII name if
  /// the stem sanitizes to empty (e.g. an all-Arabic name), so the storage path
  /// never ends in '/' or an empty segment (both also trigger InvalidKey).
  String _sanitizeStorageFileName(String fileName) {
    final ext = p.extension(fileName);
    final stem = p.basenameWithoutExtension(fileName);
    final safeStem = _sanitizeStorageSegment(stem);
    final effectiveStem = safeStem.isEmpty
        ? 'file_${DateTime.now().millisecondsSinceEpoch}'
        : safeStem;
    return '$effectiveStem$ext';
  }

  /// Complete upload pipeline:
  /// 1. Compute SHA-256 hash of the selected PDF
  /// 2. Deduplication check against Firestore
  /// 3. Upload file bytes to Supabase `university-pdfs` bucket
  /// 4. Save UniversityFile document to Firestore
  ///
  /// Returns the created [UniversityFile] on success, or throws on failure.
  Future<UniversityFile> uploadPdf({
    required String filePath,
    required String folderId,
  }) async {
    _ensureInitialized();
    _assertAdmin();

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    // ── Step 1: Compute SHA-256 hash ───────────────────────────────────
    debugPrint('📤 [UniversityService] Step 1/4: Computing hash for $filePath...');
    final fileHash = await FileHashService.calculateFileHash(filePath);

    final fileName = p.basename(filePath);
    final fileSize = await file.length();

    // ── Step 2: Deduplication Check ────────────────────────────────────
    debugPrint('📤 [UniversityService] Step 2/4: Checking for duplicate hash...');
    final existing = await _firestore
        .collection('university_files')
        .where('universityId', isEqualTo: _universityId)
        .where('fileHash', isEqualTo: fileHash)
        .where('isDeleted', isEqualTo: false)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final dupFile = UniversityFile.fromFirestore(
        existing.docs.first.id,
        existing.docs.first.data(),
      );
      throw Exception(
        'File already exists in this university.\n'
        'File: "${dupFile.name}"\n'
        'Folder ID: ${dupFile.folderId}\n'
        'Hash: ${fileHash.substring(0, 16)}...',
      );
    }

    // ── Step 3: Upload to Supabase Storage ─────────────────────────────
    debugPrint('📤 [UniversityService] Step 3/4: Uploading to Supabase...');
    // Supabase Storage rejects keys with spaces/non-ASCII chars (HTTP 400
    // "Invalid key"), so the storage path is sanitized while the original
    // display name is kept in Firestore.
    final safeFolderId = _sanitizeStorageSegment(folderId);
    final safeFileName = _sanitizeStorageFileName(fileName);
    final storagePath = '$_universityId/folders/$safeFolderId/$safeFileName';

    if (storagePath != '$_universityId/folders/$folderId/$fileName') {
      debugPrint(
        '⚠️ [UniversityService] Storage key sanitized: '
        '"$fileName" ($folderId) -> "$safeFileName" ($safeFolderId)',
      );
    }

    final bytes = await file.readAsBytes();

    await _supabase.storage.from(_bucketName).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: 'application/pdf',
          ),
        );

    debugPrint('📤 [UniversityService] Uploaded to storage path: $storagePath');

    // Optionally compute page count using pdfrx
    int? totalPages;
    try {
      final pdfDoc = await pdfrx.PdfDocument.openFile(filePath);
      totalPages = pdfDoc.pages.length;
      await pdfDoc.dispose();
      debugPrint('📤 [UniversityService] PDF pages: $totalPages');
    } catch (e) {
      debugPrint('⚠️ [UniversityService] Could not extract page count: $e');
    }

    // ── Step 4: Save Firestore document ────────────────────────────────
    debugPrint('📤 [UniversityService] Step 4/4: Saving Firestore record...');
    final fileRef = _firestore.collection('university_files').doc();

    // Every uploaded file gets its own sync code for the library sync.
    final syncCode = await _generateUniqueSyncCode();

    // New files append at the end of the folder (manual drag & drop order).
    int sortOrder = 0;
    try {
      sortOrder = (await getFilesInFolder(folderId)).length;
    } catch (e) {
      debugPrint('⚠️ [UniversityService] Could not compute sortOrder: $e');
    }

    final universityFile = UniversityFile(
      id: fileRef.id,
      universityId: _universityId,
      folderId: folderId,
      name: fileName,
      fileHash: fileHash,
      storagePath: storagePath,
      sizeBytes: fileSize,
      mimeType: 'application/pdf',
      uploadedBy: _userId,
      uploadedAt: DateTime.now(),
      totalPages: totalPages,
      isDeleted: false,
      syncCode: syncCode,
      sortOrder: sortOrder,
    );

    await fileRef.set(universityFile.toJson());

    debugPrint(
      '✅ [UniversityService] Upload complete: "$fileName" '
      '(hash: ${fileHash.substring(0, 16)}..., size: ${_formatBytes(fileSize)})',
    );
    return universityFile;
  }

  // =========================================================================
  // SECTION 3.5: PER-FILE SYNC CODES
  // =========================================================================

  /// Generates a 6-char sync code unique among this university's files.
  Future<String> _generateUniqueSyncCode() async {
    final existing = await _firestore
        .collection('university_files')
        .where('universityId', isEqualTo: _universityId)
        .get();
    final codes = existing.docs
        .map((d) => (d.data()['syncCode'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toSet();

    for (var attempt = 0; attempt < 6; attempt++) {
      final code = LibrarySyncService.generateSyncCode();
      if (!codes.contains(code)) return code;
    }
    return 'FILE${DateTime.now().millisecondsSinceEpoch % 1000000}';
  }

  /// Backfills a sync code onto every already-uploaded file of this university
  /// that is missing one. Admin only. Returns the number of files updated.
  Future<int> backfillSyncCodes() async {
    _ensureInitialized();
    _assertAdmin();

    final snapshot = await _firestore
        .collection('university_files')
        .where('universityId', isEqualTo: _universityId)
        .where('isDeleted', isEqualTo: false)
        .get();

    var count = 0;
    for (final doc in snapshot.docs) {
      final syncCode = (doc.data()['syncCode'] ?? '').toString();
      if (syncCode.isNotEmpty) continue;
      try {
        final code = await _generateUniqueSyncCode();
        await _firestore
            .collection('university_files')
            .doc(doc.id)
            .update({'syncCode': code});
        count++;
        debugPrint(
          '📡 [UniversityService] Backfilled syncCode "$code" for file ${doc.id}',
        );
      } catch (e) {
        debugPrint(
          '⚠️ [UniversityService] Backfill failed for ${doc.id}: $e',
        );
      }
    }

    if (count > 0) {
      debugPrint('✅ [UniversityService] Backfilled $count file(s) with sync codes.');
    }
    return count;
  }

  // =========================================================================
  // SECTION 4: DOWNLOAD & LOCAL CACHE PIPELINE (STUDENT)
  // =========================================================================

  /// Lightweight download: downloads bytes from Supabase to a temp path
  /// in getApplicationDocumentsDirectory. Does NOT insert into Isar —
  /// the UI layer calls FileManagerService.importAndOpenPdf() to finalize.
  ///
  /// NOTE: Uses getPublicUrl() + http.get() to avoid Supabase RLS auth issues.
  /// The bucket 'university-pdfs' must have public download enabled, with
  /// path-based access controlled via Supabase Storage RLS.
  Future<String> downloadPdfToLocal(UniversityFile file) async {
    _ensureInitialized();

    debugPrint(
      '📥 [UniversityService] downloadPdfToLocal: ${file.name} '
      '(hash: ${file.fileHash.substring(0, 16)}...)',
    );

    final publicUrl = _supabase.storage
        .from(_bucketName)
        .getPublicUrl(file.storagePath);

    final response = await http.get(Uri.parse(publicUrl));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download PDF: HTTP ${response.statusCode} — $publicUrl',
      );
    }

    // Save to permanent app documents directory (not temp)
    final appDocDir = await getApplicationDocumentsDirectory();
    final uniDir = Directory(p.join(appDocDir.path, 'university_pdfs'));
    await uniDir.create(recursive: true);

    // Use original filename to avoid duplicates
    final fileName = file.storagePath.split('/').last;
    final savedFile = File(p.join(uniDir.path, fileName));
    await savedFile.writeAsBytes(response.bodyBytes);

    debugPrint(
      '✅ [UniversityService] Downloaded to: ${savedFile.path} '
      '(${_formatBytes(response.bodyBytes.length)})',
    );
    return savedFile.path;
  }

  /// Full download pipeline:
  /// 1. Check local Isar DB for existing [PdfDocument] by fileHash
  /// 2. If found and file exists on disk → return local path (already cached)
  /// 3. If missing → download from Supabase, save to local docs dir,
  ///    insert PdfDocument into Isar, return the local path
  ///
  /// Returns the local file path where the PDF is available.
  Future<String> downloadPdf(UniversityFile universityFile) async {
    _ensureInitialized();

    // ── Step 1: Check local Isar cache by fileHash ─────────────────────
    debugPrint(
      '📥 [UniversityService] Checking local cache for hash: '
      '${universityFile.fileHash.substring(0, 16)}...',
    );

    final existingDoc = await _fileManager.isar.pdfDocuments
        .filter()
        .fileHashEqualTo(universityFile.fileHash)
        .findFirst();

    if (existingDoc != null) {
      final localPath = existingDoc.workingPath ?? existingDoc.originalPath;
      final fileExists = await File(localPath).exists();
      if (fileExists) {
        debugPrint(
          '✅ [UniversityService] File already cached locally: $localPath',
        );
        // Touch the lastOpenedAt timestamp
        await _fileManager.isar.writeTxn(() async {
          existingDoc.lastOpenedAt = DateTime.now();
          await _fileManager.isar.pdfDocuments.put(existingDoc);
        });
        return localPath;
      }
    }

    // ── Step 2: Download from Supabase Storage ─────────────────────────
    debugPrint('📥 [UniversityService] Downloading from Supabase Storage...');

    final appDocDir = await getApplicationDocumentsDirectory();
    final universityDir = Directory(
      p.join(appDocDir.path, 'StudyFlowPdf', 'UniversityCache'),
    );
    await universityDir.create(recursive: true);

    // Use hash as filename for stable cross-device identity
    final safeFilename = 'sha256_${universityFile.fileHash}.pdf';
    final localFilePath = p.join(universityDir.path, safeFilename);

    final localFile = File(localFilePath);

    // Download from Supabase via public URL (avoids RLS auth issues with anon key)
    final publicUrl = _supabase.storage
        .from(_bucketName)
        .getPublicUrl(universityFile.storagePath);

    final httpResponse = await http.get(Uri.parse(publicUrl));
    if (httpResponse.statusCode != 200) {
      throw Exception(
        'Failed to download PDF: HTTP ${httpResponse.statusCode} — $publicUrl',
      );
    }

    // Write bytes to local file
    await localFile.writeAsBytes(httpResponse.bodyBytes);

    debugPrint(
      '📥 [UniversityService] Downloaded to: $localFilePath '
      '(${_formatBytes(httpResponse.bodyBytes.length)})',
    );

    // ── Step 3: Create local PdfDocument record in Isar ───────────────
    final uuid = const Uuid().v4();

    final newDoc = PdfDocument.create(
      uuid: uuid,
      originalPath: localFilePath,
      originalDisplayName: universityFile.name,
      workingPath: localFilePath,
      workingCreatedAt: DateTime.now(),
      workingModifiedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      fileHash: universityFile.fileHash,
      totalPages: universityFile.totalPages ?? 0,
      fileSize: universityFile.sizeBytes,
    );

    await _fileManager.isar.writeTxn(() async {
      await _fileManager.isar.pdfDocuments.put(newDoc);
    });

    debugPrint(
      '✅ [UniversityService] Cached in Isar as PdfDocument(uuid: $uuid)',
    );
    return localFilePath;
  }

  /// Checks if a file is already cached locally (without downloading).
  Future<bool> isFileCachedLocally(String fileHash) async {
    _ensureInitialized();

    final existing = await _fileManager.isar.pdfDocuments
        .filter()
        .fileHashEqualTo(fileHash)
        .findFirst();

    if (existing == null) return false;

    final path = existing.workingPath ?? existing.originalPath;
    return File(path).exists();
  }

  /// Returns the local path if the file is cached, or null.
  Future<String?> getCachedPath(String fileHash) async {
    _ensureInitialized();

    final existing = await _fileManager.isar.pdfDocuments
        .filter()
        .fileHashEqualTo(fileHash)
        .findFirst();

    if (existing == null) return null;

    final path = existing.workingPath ?? existing.originalPath;
    final fileExists = await File(path).exists();
    if (fileExists) return path;
    return null;
  }

  /// The directory downloaded library PDFs are kept in.
  Future<Directory> _downloadedDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDocDir.path, 'university_pdfs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The on-disk path a library file occupies once downloaded, whether or not
  /// it still has a local database record.
  String _downloadedPathFor(Directory dir, UniversityFile file) {
    final name = file.storagePath.split('/').last;
    return p.join(dir.path, name.isEmpty ? file.name : name);
  }

  /// Local path of an already-downloaded file, or null when it has to be
  /// fetched. This asks the disk only, with no database and no network, so a
  /// file that is present opens instantly and while offline even if its local
  /// record is missing.
  Future<String?> getDownloadedPath(UniversityFile file) async {
    try {
      final dir = await _downloadedDir();
      final path = _downloadedPathFor(dir, file);
      return await File(path).exists() ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// Basenames of every library PDF already sitting on disk, so a listing can
  /// tell downloaded files from the rest without one database read per file.
  Future<Set<String>> getDownloadedFileNames() async {
    try {
      final dir = await _downloadedDir();
      final names = <String>{};
      await for (final entity in dir.list()) {
        if (entity is File) names.add(p.basename(entity.path));
      }
      return names;
    } catch (_) {
      return <String>{};
    }
  }

  // =========================================================================
  // SECTION 5: READING PROGRESS SYNC (CROSS-DEVICE)
  // =========================================================================

  /// Writes the current reading progress to Firestore.
  /// Firestore doc path: `university_file_progress/{fileHash}_{userId}`
  Future<void> saveReadingProgress({
    required String fileHash,
    required int lastPage,
    required double scrollTop,
  }) async {
    _ensureInitialized();

    final progressId = '${fileHash}_$_userId';
    final progressRef = _firestore
        .collection('university_file_progress')
        .doc(progressId);

    await progressRef.set({
      'fileHash': fileHash,
      'userId': _userId,
      'universityId': _universityId,
      'lastPage': lastPage,
      'scrollTop': scrollTop,
      'lastReadAt': FieldValue.serverTimestamp(),
      'deviceId': _currentUser?.primaryDeviceId ?? '',
    }, SetOptions(merge: true));

    debugPrint(
      '📖 [UniversityService] Saved progress for file ${fileHash.substring(0, 12)}... '
      '→ page $lastPage, scroll $scrollTop',
    );
  }

  /// Reads the reading progress from Firestore.
  /// Returns a map with `lastPage` and `scrollTop`, or null if no progress exists.
  Future<Map<String, dynamic>?> getReadingProgress({
    required String fileHash,
  }) async {
    _ensureInitialized();

    final progressId = '${fileHash}_$_userId';
    final progressRef = _firestore
        .collection('university_file_progress')
        .doc(progressId);

    final doc = await progressRef.get();

    if (!doc.exists || doc.data() == null) {
      debugPrint(
        '📖 [UniversityService] No saved progress for file '
        '${fileHash.substring(0, 12)}...',
      );
      return null;
    }

    final data = doc.data()!;
    debugPrint(
      '📖 [UniversityService] Restored progress for file '
      '${fileHash.substring(0, 12)}... '
      '→ page ${data['lastPage']}, scroll ${data['scrollTop']}',
    );
    return {
      'lastPage': data['lastPage'] ?? 1,
      'scrollTop': (data['scrollTop'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Streams reading progress in real-time (for cross-device live sync).
  Stream<Map<String, dynamic>?> streamReadingProgress({
    required String fileHash,
  }) {
    _ensureInitialized();

    final progressId = '${fileHash}_$_userId';
    return _firestore
        .collection('university_file_progress')
        .doc(progressId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) return null;
          final data = snapshot.data()!;
          return {
            'lastPage': data['lastPage'] ?? 1,
            'scrollTop': (data['scrollTop'] as num?)?.toDouble() ?? 0.0,
          };
        });
  }

  /// Deletes reading progress (e.g., when user removes a file from their device).
  Future<void> deleteReadingProgress({
    required String fileHash,
  }) async {
    _ensureInitialized();

    final progressId = '${fileHash}_$_userId';
    await _firestore
        .collection('university_file_progress')
        .doc(progressId)
        .delete();

    debugPrint(
      '🗑️ [UniversityService] Deleted reading progress for file '
      '${fileHash.substring(0, 12)}...',
    );
  }

  // =========================================================================
  // SECTION 6: REORDER + UTILITY
  // =========================================================================

  /// Reorders two folders via drag & drop (Admin only). The dragged folder is
  /// moved in front of the target folder; dense `sortOrder` 0..n-1 is
  /// batch-written to every folder so the order syncs to all members.
  Future<void> reorderFolders({
    required String draggedFolderId,
    required String targetFolderId,
  }) async {
    _ensureInitialized();
    _assertAdmin();

    final folders = await getFolders();
    final draggedIndex = folders.indexWhere((f) => f.id == draggedFolderId);
    final targetIndex = folders.indexWhere((f) => f.id == targetFolderId);
    if (draggedIndex == -1 || targetIndex == -1) return;

    final dragged = folders.removeAt(draggedIndex);
    folders.insert(targetIndex, dragged);

    final batch = _firestore.batch();
    for (var i = 0; i < folders.length; i++) {
      if (folders[i].sortOrder == i) continue;
      batch.update(
        _firestore.collection('university_folders').doc(folders[i].id),
        {'sortOrder': i},
      );
    }
    await batch.commit();
    debugPrint('📂 [UniversityService] Reordered folders (dragged=$draggedFolderId).');
  }

  /// Reorders two files within a folder via drag & drop (Admin only). Dense
  /// `sortOrder` 0..n-1 is batch-written so the order syncs to all members.
  Future<void> reorderFiles({
    required String folderId,
    required String draggedFileId,
    required String targetFileId,
  }) async {
    _ensureInitialized();
    _assertAdmin();

    final files = await getFilesInFolder(folderId);
    final draggedIndex = files.indexWhere((f) => f.id == draggedFileId);
    final targetIndex = files.indexWhere((f) => f.id == targetFileId);
    if (draggedIndex == -1 || targetIndex == -1) return;

    final dragged = files.removeAt(draggedIndex);
    files.insert(targetIndex, dragged);

    final batch = _firestore.batch();
    for (var i = 0; i < files.length; i++) {
      if (files[i].sortOrder == i) continue;
      batch.update(
        _firestore.collection('university_files').doc(files[i].id),
        {'sortOrder': i},
      );
    }
    await batch.commit();
    debugPrint(
      '🗂️ [UniversityService] Reordered files in $folderId (dragged=$draggedFileId).',
    );
  }

  /// Deletes a university file (Admin only). Removes the PDF object from the
  /// Supabase `university-pdfs` bucket (best-effort), then soft-deletes the
  /// Firestore doc so the stream removes it for every member.
  Future<void> deleteFile(UniversityFile file) async {
    _ensureInitialized();
    _assertAdmin();

    if (file.storagePath.isNotEmpty) {
      try {
        await _supabase.storage
            .from(_bucketName)
            .remove([file.storagePath]);
        debugPrint(
          '🗄️ [UniversityService] Removed storage object: ${file.storagePath}',
        );
      } catch (e) {
        debugPrint(
          '⚠️ [UniversityService] Storage remove failed (ignored): $e',
        );
      }
    }

    await _firestore
        .collection('university_files')
        .doc(file.id)
        .update({'isDeleted': true});

    debugPrint(
      '🗑️ [UniversityService] Deleted file ${file.id} ("${file.name}")',
    );
  }

  // =========================================================================
  // SECTION 7: VIDEO LINKS (YouTube)
  // Videos live in the `university_videos` collection, separate from PDFs.
  // =========================================================================

  /// Extracts the 11-char YouTube video ID from a wide range of URL formats
  /// (`watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`, `/live/`, `m.youtube.com`).
  /// Returns `null` when the URL is not a valid YouTube watch link.
  static String? videoIdFromUrl(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    final isYouTube = host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'youtu.be' ||
        host == 'www.youtu.be' ||
        host.endsWith('.youtube.com');
    if (!isYouTube) return null;

    // ?v=<id>
    final queryId = uri.queryParameters['v'];
    if (queryId != null && _isValidVideoId(queryId)) return queryId;

    // youtu.be/<id>
    if (host.contains('youtu.be')) {
      final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      if (_isValidVideoId(seg)) return seg;
    }

    // /shorts/<id> | /embed/<id> | /live/<id> | /v/<id> | /watch/<id>
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2) {
      const kinds = {'shorts', 'embed', 'live', 'v', 'watch'};
      if (kinds.contains(segments[0]) && _isValidVideoId(segments[1])) {
        return segments[1];
      }
    }
    return null;
  }

  static bool _isValidVideoId(String id) {
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);
  }

  /// Converts any supported YouTube URL into a canonical watch URL.
  static String normalizeVideoUrl(String url) {
    final id = videoIdFromUrl(url);
    if (id == null) {
      throw FormatException('رابط يوتيوب غير صالح');
    }
    return 'https://www.youtube.com/watch?v=$id';
  }

  /// Adds a YouTube video link to a folder (Admin only).
  Future<UniversityVideo> addVideo({
    required String folderId,
    required String title,
    required String videoUrl,
  }) async {
    _ensureInitialized();
    _assertAdmin();

    final id = videoIdFromUrl(videoUrl);
    if (id == null) {
      throw FormatException(
        'رابط يوتيوب غير صالح. تأكد من الرابط ثم أعد المحاولة.',
      );
    }

    final ref = _firestore.collection('university_videos').doc();

    // New videos append at the end of the folder (manual drag & drop order).
    int sortOrder = 0;
    try {
      sortOrder = (await getVideosInFolder(folderId)).length;
    } catch (e) {
      debugPrint('⚠️ [UniversityService] Could not compute video sortOrder: $e');
    }

    final video = UniversityVideo(
      id: ref.id,
      universityId: _universityId,
      folderId: folderId,
      title: title.trim().isEmpty ? 'درس فيديو' : title.trim(),
      videoId: id,
      videoUrl: 'https://www.youtube.com/watch?v=$id',
      uploadedBy: _userId,
      uploadedAt: DateTime.now(),
      isDeleted: false,
      sortOrder: sortOrder,
    );

    await ref.set(video.toJson());

    debugPrint(
      '🎬 [UniversityService] Added video ${ref.id} (videoId=$id) to $folderId',
    );
    return video;
  }

  /// Fetches all videos in a specific folder for the current user's university.
  Future<List<UniversityVideo>> getVideosInFolder(String folderId) async {
    _ensureInitialized();

    final snapshot = await _firestore
        .collection('university_videos')
        .where('universityId', isEqualTo: _universityId)
        .where('folderId', isEqualTo: folderId)
        .where('isDeleted', isEqualTo: false)
        .get();

    return snapshot.docs
        .map((doc) => UniversityVideo.fromFirestore(doc.id, doc.data()))
        .toList()
      ..sort(_compareVideos);
  }

  /// Sorts by the manual [UniversityVideo.sortOrder] first (drag & drop), then
  /// by upload time.
  static int _compareVideos(UniversityVideo a, UniversityVideo b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.uploadedAt.compareTo(b.uploadedAt);
  }

  /// Streams videos in a folder in real-time.
  Stream<List<UniversityVideo>> streamVideosInFolder(String folderId) {
    _ensureInitialized();

    return _firestore
        .collection('university_videos')
        .where('universityId', isEqualTo: _universityId)
        .where('folderId', isEqualTo: folderId)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UniversityVideo.fromFirestore(doc.id, doc.data()))
            .toList()
          ..sort(_compareVideos));
  }

  /// Deletes a university video link (Admin only). Videos have no storage
  /// object to remove, so this soft-deletes the Firestore doc directly.
  Future<void> deleteVideo(UniversityVideo video) async {
    _ensureInitialized();
    _assertAdmin();

    await _firestore
        .collection('university_videos')
        .doc(video.id)
        .update({'isDeleted': true});

    debugPrint(
      '🗑️ [UniversityService] Deleted video ${video.id} ("${video.title}")',
    );
  }

  /// Reorders two videos within a folder via drag & drop (Admin only). Dense
  /// `sortOrder` 0..n-1 is batch-written so the order syncs to all members.
  Future<void> reorderVideos({
    required String folderId,
    required String draggedVideoId,
    required String targetVideoId,
  }) async {
    _ensureInitialized();
    _assertAdmin();

    final videos = await getVideosInFolder(folderId);
    final draggedIndex = videos.indexWhere((v) => v.id == draggedVideoId);
    final targetIndex = videos.indexWhere((v) => v.id == targetVideoId);
    if (draggedIndex == -1 || targetIndex == -1) return;

    final dragged = videos.removeAt(draggedIndex);
    videos.insert(targetIndex, dragged);

    final batch = _firestore.batch();
    for (var i = 0; i < videos.length; i++) {
      if (videos[i].sortOrder == i) continue;
      batch.update(
        _firestore.collection('university_videos').doc(videos[i].id),
        {'sortOrder': i},
      );
    }
    await batch.commit();
    debugPrint(
      '🎬 [UniversityService] Reordered videos in $folderId (dragged=$draggedVideoId).',
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}