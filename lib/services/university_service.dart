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
import '../models/isar_models.dart';
import 'file_hash_service.dart';
import 'file_manager_service.dart';

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
    debugPrint(
      '🏛️ [UniversityService] Initialized for user ${user.uid}'
      ' (university: ${user.universityId}, role: ${user.role})',
    );
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

    await _firestore
        .collection('university_folders')
        .doc(folderId)
        .update({'isDeleted': true});

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
        .orderBy('uploadedAt', descending: false)
        .get();

    return snapshot.docs
        .map((doc) => UniversityFile.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  /// Streams files in a folder in real-time.
  Stream<List<UniversityFile>> streamFilesInFolder(String folderId) {
    _ensureInitialized();

    return _firestore
        .collection('university_files')
        .where('universityId', isEqualTo: _universityId)
        .where('folderId', isEqualTo: folderId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('uploadedAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UniversityFile.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  // =========================================================================
  // SECTION 3: UPLOAD PIPELINE (ADMIN)
  // =========================================================================

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
    final storagePath = '$_universityId/folders/$folderId/$fileName';

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
    );

    await fileRef.set(universityFile.toJson());

    debugPrint(
      '✅ [UniversityService] Upload complete: "$fileName" '
      '(hash: ${fileHash.substring(0, 16)}..., size: ${_formatBytes(fileSize)})',
    );
    return universityFile;
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
  // SECTION 6: UTILITY
  // =========================================================================

  /// Soft-deletes a university file (Admin only).
  Future<void> deleteFile(String fileId) async {
    _ensureInitialized();
    _assertAdmin();

    await _firestore
        .collection('university_files')
        .doc(fileId)
        .update({'isDeleted': true});

    debugPrint('🗑️ [UniversityService] Soft-deleted file $fileId');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}