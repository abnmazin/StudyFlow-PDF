import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' hide PdfBookmark;
import '../models/models.dart';
import '../models/app_user.dart';
import '../services/sync_service.dart';
import '../services/file_hash_service.dart';

enum DrawingSyncStrategy { disabled, immediate, buffered, isolate }

// Top-level function for Compute Isolate Serialization
List<Map<String, dynamic>> _serializeAnnotationsForIsolate(Map<String, dynamic> data) {
  final List<Highlight> highlights = data['highlights'] as List<Highlight>;
  final List<PdfComment> comments = data['comments'] as List<PdfComment>;
  
  final hJson = highlights.map((h) => {...h.toJson(), 'kind': 'highlight'}).toList();
  final cJson = comments.map((c) => {...c.toJson(), 'kind': 'comment'}).toList();
  return [...hJson, ...cJson];
}

// Action types for undo/redo
class ActionRecord {
  final String pdfId;
  final String actionType;
  final String itemId;
  final Map<String, dynamic>? oldState;
  final Map<String, dynamic>? newState;

  ActionRecord({
    required this.pdfId,
    required this.actionType,
    required this.itemId,
    this.oldState,
    this.newState,
  });

  String toLegacyString() => '$pdfId:$actionType:$itemId';
}

extension ActionTypes on AppProvider {
  static const String ACTION_ADD_HIGHLIGHT = 'add_highlight';
  static const String ACTION_ADD_COMMENT = 'add_comment';
  static const String ACTION_UPDATE_HIGHLIGHT = 'update_highlight';
  static const String ACTION_UPDATE_COMMENT = 'update_comment';
  static const String ACTION_MOVE_COMMENT = 'move_comment';
  static const String ACTION_DELETE_HIGHLIGHT = 'delete_highlight';
  static const String ACTION_DELETE_COMMENT = 'delete_comment';
}

class AppProvider extends ChangeNotifier {
  final SyncService _syncService = SyncService();

  // ─── STATE FIELDS ──────────────────────────────────────────────────────────
  List<ClassItem> _classes = [];
  String? _activeClassId;
  String? _activePdfId;
  AppUser? _currentUser;
  Map<String, String> _pdfSessionCodes = {}; // Key: fileHash, Value: sessionCode
  bool _sessionLocked = false;
  bool _sessionJoinLocked = false;
  List<ActionRecord> _actionHistory = [];
  List<ActionRecord> _redoHistory = [];
  StreamSubscription? _kickSub;
  StreamSubscription? _userDocSub;
  String? _forcedLogoutReason;
  bool _isGlobalLogout = false;
  bool _isKicked = false;
  bool _isLocked = false;

  // UI State
  bool _isMobileOpen = false;
  bool _showDevInfo = false;
  bool _isSidebarCollapsed = false;
  bool _isDarkMode = false;
  bool _isSettingsOpen = false;
  DrawingSyncStrategy _drawingSyncStrategy = DrawingSyncStrategy.disabled;

  DrawingSyncStrategy get drawingSyncStrategy => _drawingSyncStrategy;

  void setDrawingSyncStrategy(DrawingSyncStrategy strategy) {
    _drawingSyncStrategy = strategy;
    _notify();
  }

  // AI & Models
  String _aiProvider = 'groq';
  String _geminiModel = 'gemini-2.5-flash';
  String _groqModel = 'llama-3.3-70b-versatile';
  String _geminiApiKey = '';
  String _groqApiKey = '';

  // Concurrency & Flow
  bool _isSaving = false;
  bool _needsSave = false;
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  ToolType _currentTool = ToolType.cursor;
  ToolType get currentTool => _currentTool;

  final Completer<void> _initCompleter = Completer<void>();
  Future<void>? get initialized => _initCompleter.future;

  // ─── TRIGGER SYNC ──────────────────────────────────────────────────────────

  final Map<String, Timer?> _syncTimers = {};
  final Map<String, bool> _pendingSyncs = {};

  // Helper to trigger sync in background safely
  void triggerSync(String fileHash) {
    _triggerSync(fileHash);
  }

  /// Fetch → Purge orphans → Download missing → Upload new.
  /// Has a cooldown guard so concurrent calls are silently ignored.
  Future<void> performBidirectionalSync() async {
    if (_isSyncing) {
      debugPrint('DEBUG: Sync already in progress – skipping.');
      return;
    }

    // --- STEP 0: ACCOUNT VALIDITY CHECK ---
    if (_currentUser != null) {
      final exists = await _syncService.checkUserExists(_currentUser!.uid);
      if (!exists) {
        _handleForceLogout('هذا الحساب لم يعد موجوداً في النظام (تم حذفه).');
        return;
      }
    }

    // --- STEP 0.1: SESSION KICK FALLBACK ---
    final code = this.currentSessionCode;
    if (code != null && _currentUser != null) {
      final isKicked = await _syncService.isUserKicked(code, _currentUser!.hardwareId);
      if (isKicked) {
        _handleForceLogout('لقد تم إنهاء وصولك لهذه الجلسة من قبل المالك (Manual Check)');
        return;
      }
    }

    final activePdf = this.activePdf;
    final sessionCode = currentSessionCode;
    if (activePdf == null || sessionCode == null) return;

    _isSyncing = true;
    _notify();
    debugPrint('DEBUG: performBidirectionalSync started (session: $sessionCode, hash: ${activePdf.fileHash}).');

    try {
      final result = await _syncService.syncExistingAnnotations(
        code: sessionCode,
        fileHash: activePdf.fileHash ?? '',
        highlights: activePdf.highlights,
        comments: activePdf.comments,
      );

      // ── Purge local orphans (items deleted server-side) ─────────────────
      if (result.deletedCount > 0) {
        final serverIds = {
          ...result.toAddHighlights.map((e) => e['id']?.toString() ?? ''),
          ...result.toAddComments.map((e)   => e['id']?.toString() ?? ''),
        };
        for (final h in List.of(activePdf.highlights)) {
          if (h.isSynced && !serverIds.contains(h.id)) {
            removeHighlightById(activePdf.id, h.id);
          }
        }
      }

      // ── Inject server-only highlights (no duplicates) ───────────────────
      if (result.toAddHighlights.isNotEmpty) {
        final existingIds = {for (final h in activePdf.highlights) h.id};
        for (final json in result.toAddHighlights) {
          try {
            final h = Highlight.fromJson(Map<String, dynamic>.from(json));
            if (!existingIds.contains(h.id)) {
              addHighlight(activePdf.id, h.copyWith(isSynced: true));
            }
          } catch (_) {}
        }
      }

      // ── Inject server-only comments (no duplicates) ─────────────────────
      if (result.toAddComments.isNotEmpty) {
        final existingIds = {for (final c in activePdf.comments) c.id};
        for (final json in result.toAddComments) {
          try {
            final c = PdfComment.fromJson(Map<String, dynamic>.from(json));
            if (!existingIds.contains(c.id)) {
              addComment(activePdf.id, c.copyWith(isSynced: true));
            }
          } catch (_) {}
        }
      }

      debugPrint('DEBUG: performBidirectionalSync done. Deleted: ${result.deletedCount}, Downloaded: ${result.downloadedCount}, Uploaded: ${result.uploadedCount}.');
    } catch (e) {
      debugPrint('ERROR: performBidirectionalSync failed: $e');
    } finally {
      _isSyncing = false;
      _notify();
    }
  }

  void setCurrentTool(ToolType tool) {
    _currentTool = tool;
    _notify();

    // Trigger sync ONLY if switching to hand tool and in active session
    if (tool == ToolType.cursor && currentSessionCode != null) {
      debugPrint("DEBUG: AppProvider switching to Hand Tool. Triggering Manual Sync Logic...");
      SchedulerBinding.instance.addPostFrameCallback((_) {
        performBidirectionalSync();
      });
    }
  }

  void _triggerSync(String fileHash) {
    if (_currentUser?.role != 'lecturer') return;
    
    final code = _pdfSessionCodes[fileHash];
    if (code == null) return;
    
    // Find a PDF with this hash to get its highlights
    PdfItem? pdf;
    for (var cls in _classes) {
       for (var p in cls.pdfs) {
         if (p.fileHash == fileHash) {
            pdf = p;
            break;
         }
       }
       if (pdf != null) break;
    }
    if (pdf == null) return;

    if (_drawingSyncStrategy == DrawingSyncStrategy.disabled) {
      return;
    } else if (_drawingSyncStrategy == DrawingSyncStrategy.immediate) {
      // Unawaited background sync to avoid blocking UI mutation
      _syncService.uploadDelta(
        code,
        fileHash,
        pdf.highlights,
        pdf.comments,
      ).catchError((e) {
        debugPrint('❌ Sync Error: $e');
      });
      debugPrint('DEBUG: Drawing captured. Size: ${pdf.highlights.isNotEmpty ? pdf.highlights.last.path.length : 0} points. Destination: sync_sessions/$code/annotations/$fileHash.');
    } else if (_drawingSyncStrategy == DrawingSyncStrategy.buffered) {
      _pendingSyncs[fileHash] = true;
      if (_syncTimers[fileHash] == null || !_syncTimers[fileHash]!.isActive) {
        _syncTimers[fileHash] = Timer(const Duration(seconds: 5), () {
          if (_pendingSyncs[fileHash] == true) {
            _pendingSyncs[fileHash] = false;
            _syncService.uploadDelta(code, fileHash, pdf!.highlights, pdf.comments).catchError((e) {
              debugPrint('❌ Buffered Sync Error: $e');
            });
            debugPrint('DEBUG: Buffered Sync Triggered for $fileHash.');
          }
        });
      }
      debugPrint('DEBUG: Drawing captured (Buffered). Size: ${pdf.highlights.isNotEmpty ? pdf.highlights.last.path.length : 0} points.');
    } else if (_drawingSyncStrategy == DrawingSyncStrategy.isolate) {
      // Offload JSON serialization to a separate Isolate
      compute(_serializeAnnotationsForIsolate, {
        'highlights': pdf.highlights,
        'comments': pdf.comments,
      }).then((serialized) {
        _syncService.uploadSerializedDelta(code, fileHash, serialized).catchError((e) {
          debugPrint('❌ Isolate Sync Error: $e');
        });
      });
      debugPrint('DEBUG: Drawing captured (Isolate). Size: ${pdf.highlights.isNotEmpty ? pdf.highlights.last.path.length : 0} points. Destination: sync_sessions/$code/annotations/$fileHash.');
    }
  }

  void _notify() {
    // Phase 11.6: Flutter Threading Shield (Fix shell.cc errors)
    // Ensures state updates from Firestore background threads are safely 
    // dispatched to the Main/Platform thread for UI rendering.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      try {
        notifyListeners();
      } catch (_) {
        // Fallback for background threads
        SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
      }
    }
  }

  void updateHighlight(
    String pdfId,
    Highlight oldHighlight,
    Highlight newHighlight,
  ) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      final index = pdf.highlights.indexWhere((h) => h.id == oldHighlight.id);
      if (index != -1) {
        pdf.highlights[index] = newHighlight;
        // سجل التعديل في سجل العمليات
        recordUpdate(
          pdfId: pdfId,
          itemId: oldHighlight.id,
          actionType: ActionTypes.ACTION_UPDATE_HIGHLIGHT,
          oldState: {
            'color': oldHighlight.color.value,
            'strokeWidth': oldHighlight.strokeWidth,
            'backgroundColor': oldHighlight.backgroundColor,
            'path': oldHighlight.path
                .map((p) => {'dx': p.dx, 'dy': p.dy})
                .toList(),
          },
          newState: {
            'color': newHighlight.color.value,
            'strokeWidth': newHighlight.strokeWidth,
            'backgroundColor': newHighlight.backgroundColor,
            'path': newHighlight.path
                .map((p) => {'dx': p.dx, 'dy': p.dy})
                .toList(),
          },
        );
        _notify();
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
        _triggerSync(pdf.fileHash ?? '');
      }
      return;
    }
  }

  void recordUpdate({
    required String pdfId,
    required String itemId,
    required String actionType,
    required Map<String, dynamic> oldState,
    required Map<String, dynamic> newState,
  }) {
    _actionHistory.add(
      ActionRecord(
        pdfId: pdfId,
        actionType: actionType,
        itemId: itemId,
        oldState: oldState,
        newState: newState,
      ),
    );
    _redoHistory.clear();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
    _notify();
  }

  // --- Statistics Getters ---
  int get totalPdfs => _classes.fold(0, (sum, cls) => sum + cls.pdfs.length);

  int get totalHighlights => _classes.fold(
    0,
    (sum, cls) =>
        sum + cls.pdfs.fold(0, (pdfSum, pdf) => pdfSum + pdf.highlights.length),
  );

  int get totalComments => _classes.fold(
    0,
    (sum, cls) =>
        sum + cls.pdfs.fold(0, (pdfSum, pdf) => pdfSum + pdf.comments.length),
  );

  AppProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadState();
    // Start user monitor if we have a persisted user
    if (_currentUser != null) {
      _startUserMonitor(_currentUser!.uid);
    }
    _initCompleter.complete();
  }

  // Getters
  List<ClassItem> get classes => _classes;
  String? get activeClassId => _activeClassId;
  String? get activePdfId => _activePdfId;
  bool get isMobileOpen => _isMobileOpen;
  bool get showDevInfo => _showDevInfo;
  bool get isSidebarCollapsed => _isSidebarCollapsed;
  bool get isDarkMode => _isDarkMode;
  bool get isSettingsOpen => _isSettingsOpen;
  String get aiProvider => _aiProvider;
  String get geminiModel => _geminiModel;
  String get groqModel => _groqModel;
  String get geminiApiKey => _geminiApiKey;
  String get groqApiKey => _groqApiKey;

  // Session / User getters
  AppUser? get currentUser => _currentUser;
  String? get currentSessionCode {
    final pdf = activePdf;
    if (pdf == null) return null;
    return _pdfSessionCodes[pdf.fileHash ?? ''];
  }
  bool get sessionLocked => _sessionLocked;
  bool get sessionJoinLocked => _sessionJoinLocked;
  String? get forcedLogoutReason => _forcedLogoutReason;
  bool get isGlobalLogout => _isGlobalLogout;
  bool get isKicked => _isKicked;

  void clearForcedLogoutReason() {
    _forcedLogoutReason = null;
    _isGlobalLogout = false;
    _isKicked = false;
    _notify();
  }

  void _startUserMonitor(String uid) {
    _userDocSub?.cancel();
    _userDocSub = _syncService.watchUserExists(uid).listen((exists) {
      if (!exists) {
        _handleForceLogout('تم حذف حسابك من النظام. يرجى تسجيل الدخول مجدداً.');
      }
    });
  }

  void _stopUserMonitor() {
    _userDocSub?.cancel();
    _userDocSub = null;
  }

  void toggleSettings(bool open) {
    _isSettingsOpen = open;
    _notify();
  }

  void setCurrentUser(AppUser user) {
    _currentUser = user;
    _startUserMonitor(user.uid);
    _notify();
  }

  void setSessionCode(String? code) {
    final pdf = activePdf;
    if (pdf != null && pdf.fileHash != null) {
      final hash = pdf.fileHash!;
      if (code == null) {
        _pdfSessionCodes.remove(hash);
      } else {
        _pdfSessionCodes[hash] = code;
      }

      // Manage Kick Listener
      _stopKickListener();
      if (code != null && _currentUser != null) {
        _startKickListener(code);
      }

      _saveState();
      _notify();
    }
  }

  void logout() {
    _currentUser = null;
    _pdfSessionCodes.clear();
    _sessionLocked = false;
    _sessionJoinLocked = false;
    _stopKickListener();
    _stopUserMonitor();
    _saveState();
    _notify();
  }

  void setSessionLocked(bool locked) {
    _sessionLocked = locked;
    _notify();
  }

  void setSessionJoinLocked(bool locked) {
    _sessionJoinLocked = locked;
    _notify();
  }

  // ─── SECURITY HELPERS ──────────────────────────────────────────────────────

  void _startKickListener(String code) {
    final uid = _currentUser?.uid;
    if (uid == null) return;

    _kickSub?.cancel();
    // Phase 11.6: Race Condition Guard (Delayed Start)
    _kickSub = Stream.fromFuture(Future.delayed(const Duration(milliseconds: 500)))
        .asyncExpand((_) => _syncService.watchSessionSecurity(code))
        .listen((state) {
      if (state['exists'] == false) {
        _handleForceLogout('تم إغلاق الجلسة من قبل المالك');
        return;
      }

      // 0. Owner Immunity Guard (by Username)
      final String? ownerId = state['createdBy']; // Session owner Username
      if (ownerId != null && ownerId == _currentUser?.username) {
        debugPrint('DEBUG: User is Session Owner. Security Immunity Granted.');
        return;
      }

      // 1. Kick Check (by UID)
      final kickedUids = state['kicked_uids'] as List<dynamic>? ?? [];

      if (kickedUids.contains(uid)) {
        _handleForceLogout('لقد تم حظرك من هذه الجلسة');
        return;
      }

      // 2. Lock Check (isDrawingEnabled logic)
      final locked = state['isLocked'] as bool;
      if (locked != _isLocked) {
        _isLocked = locked;
        if (locked) {
          // Locked: Wipe unsynced and switch to hand
          clearUnsyncedAnnotationsForActivePdf();
          setCurrentTool(ToolType.cursor);
          debugPrint('DEBUG: Session LOCKED. Switching to Hand tool.');
        } else {
          debugPrint('DEBUG: Session UNLOCKED.');
        }
        _notify();
      }

      // 3. Membership Check (Phase 11.5)
      final participants = state['participants'] as List<dynamic>? ?? [];
      final stillMember = participants.any((p) {
        if (p is Map) {
          final pUid = (p['uid'] ?? p['id'] ?? '')?.toString();
          return pUid == uid;
        }
        return false;
      });

      if (!stillMember) {
        _handleForceLogout('لقد تمت إزالتك من قائمة المشاركين في هذا الدرس');
        return;
      }
    });
  }

  void _stopKickListener() {
    _kickSub?.cancel();
    _kickSub = null;
  }

  void _handleForceLogout(String reason) {
    _isKicked = true;
    _forcedLogoutReason = reason;
    _isGlobalLogout = reason.contains('النظام');
    _isLocked = false;
    
    // Cleanup active session
    final pdf = activePdf;
    if (pdf != null && pdf.fileHash != null) {
      _pdfSessionCodes.remove(pdf.fileHash);
    }
    _sessionLocked = false;
    _sessionJoinLocked = false;
    _stopKickListener();
    _stopUserMonitor(); // Also stop monitoring the deleted account

    // WIPE SCREEN
    if (pdf != null) {
      for (var i = 0; i < _classes.length; i++) {
        final pdfIdx = _classes[i].pdfs.indexWhere((p) => p.id == pdf.id);
        if (pdfIdx != -1) {
          _classes[i].pdfs[pdfIdx] = _classes[i].pdfs[pdfIdx].copyWith(
            highlights: [],
            comments: [],
          );
        }
      }
    }

    // Account check specific: If account deleted, wipe user
    if (reason.contains('النظام')) {
       _currentUser = null;
    }

    _saveState();
    _notify();
  }

  void clearUnsyncedAnnotationsForActivePdf() {
    // This logic ensures that if the session is locked, any local-only (un-synced) 
    // drawings are reverted to the last known 'synced' state or removed.
    final pdf = activePdf;
    if (pdf == null) return;

    // Filter out un-synced items
    final syncedHighlights = pdf.highlights.where((h) => h.isSynced == true).toList();
    final syncedComments = pdf.comments.where((c) => c.isSynced == true).toList();

    for (var i = 0; i < _classes.length; i++) {
      final pdfIdx = _classes[i].pdfs.indexWhere((p) => p.id == pdf.id);
      if (pdfIdx != -1) {
        _classes[i].pdfs[pdfIdx] = _classes[i].pdfs[pdfIdx].copyWith(
          highlights: syncedHighlights,
          comments: syncedComments,
        );
        break;
      }
    }
    _notify();
  }

  /// Updates local annotations for a PDF from Firestore sync data based on global fileHash.
  /// Handles combined highlights and comments via the 'kind' tag.
  void syncFromFirestore(String fileHash, List<dynamic> remoteData) {
    bool changed = false;
    for (var i = 0; i < _classes.length; i++) {
      for (var j = 0; j < _classes[i].pdfs.length; j++) {
        final pdf = _classes[i].pdfs[j];
        if (pdf.fileHash == fileHash) {
          final List<Highlight> newHighlights = [];
          final List<PdfComment> newComments = [];
          
          for (var item in remoteData) {
            if (item is Map) {
              final data = Map<String, dynamic>.from(item);
              final kind = data['kind'];
              if (kind == 'highlight') {
                newHighlights.add(Highlight.fromJson(data));
              } else if (kind == 'comment') {
                newComments.add(PdfComment.fromJson(data));
              }
            }
          }
          
          // Absolute parity check with the host
          _classes[i].pdfs[j] = pdf.copyWith(
            highlights: newHighlights,
            comments: newComments,
          );
          changed = true;
        }
      }
    }

    if (changed) {
      _notify();
      // We don't necessarily need to trigger a full _saveState() here 
      // if these are fleeting session notes, but typically we want them 
      // to survive a quick restart if sync is on.
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 1000), _saveState);
    }
  }

  PdfItem? get activePdf {
    if (_activeClassId == null || _activePdfId == null) return null;
    try {
      final cls = _classes.firstWhere((c) => c.id == _activeClassId);
      return cls.pdfs.firstWhere((p) => p.id == _activePdfId);
    } catch (_) {
      return null;
    }
  }

  // Constants for SharedPreferences
  static const String _prefsKeyClasses = 'pdfreader_classes';
  static const String _prefsKeyActiveClass = 'pdfreader_active_class';
  static const String _prefsKeyDarkMode = 'pdfreader_dark_mode';
  static const String _prefsKeyAiProvider = 'pdfreader_ai_provider';
  static const String _prefsKeyGeminiModel = 'pdfreader_gemini_model';
  static const String _prefsKeyGroqModel = 'pdfreader_groq_model';
  static const String _prefsKeyGeminiApiKey = 'pdfreader_gemini_api_key';
  static const String _prefsKeyGroqApiKey = 'pdfreader_groq_api_key';
  static const String _prefsKeyPdfSessionCodes = 'pdfreader_session_codes';

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load Classes
      final classesJson = prefs.getString(_prefsKeyClasses);
      if (classesJson != null) {
        try {
          final dynamic decoded = jsonDecode(classesJson);
          if (decoded is List) {
            _classes = decoded.map((item) => ClassItem.fromJson(item)).toList();
          } else {
            debugPrint('Error loading classes: JSON is not a List');
          }
        } catch (e) {
          debugPrint('Error decoding classes JSON: $e');
        }
      }

      // Load Active Class
      final savedClassId = prefs.getString(_prefsKeyActiveClass);
      if (savedClassId != null && _classes.any((c) => c.id == savedClassId)) {
        _activeClassId = savedClassId;

        // Auto-open last active PDF for this class
        final cls = _classes.firstWhere((c) => c.id == savedClassId);
        if (cls.lastActivePdfId != null &&
            cls.pdfs.any((p) => p.id == cls.lastActivePdfId)) {
          _activePdfId = cls.lastActivePdfId;
        }
      } else if (_classes.isNotEmpty) {
        // Default to first class if no saved active class
        _activeClassId = _classes.first.id;
      }

      // Load dark mode preference
      _isDarkMode = prefs.getBool(_prefsKeyDarkMode) ?? false;
      _aiProvider = prefs.getString(_prefsKeyAiProvider) ?? 'groq';
      _geminiModel =
          prefs.getString(_prefsKeyGeminiModel) ?? 'gemini-2.5-flash';
      _groqModel =
          prefs.getString(_prefsKeyGroqModel) ?? 'llama-3.3-70b-versatile';
      _geminiApiKey = prefs.getString(_prefsKeyGeminiApiKey) ?? '';
      _groqApiKey = prefs.getString(_prefsKeyGroqApiKey) ?? '';

      // Recalculate missing hashes/pageCounts for existing files
      for (var i = 0; i < _classes.length; i++) {
        for (var j = 0; j < _classes[i].pdfs.length; j++) {
          final pdf = _classes[i].pdfs[j];
          if (pdf.fileHash == null || pdf.pageCount == null) {
            try {
              final file = File(pdf.path);
              if (await file.exists()) {
                final hash = await FileHashService.calculateFileHash(pdf.path);
                final bytes = await file.readAsBytes();
                final doc = PdfDocument(inputBytes: bytes);
                final pCount = doc.pages.count;
                doc.dispose();
                
                _classes[i].pdfs[j] = pdf.copyWith(
                  fileHash: hash,
                  pageCount: pCount,
                );
                debugPrint('✅ Computed missing metadata for ${pdf.name}');
              }
            } catch (e) {
              debugPrint('⚠️ Failed to compute hash for ${pdf.name}: $e');
            }
          }
        }
      }

      // Load session codes map
      final sessionCodesJson = prefs.getString(_prefsKeyPdfSessionCodes);
      if (sessionCodesJson != null) {
        try {
          final decoded = jsonDecode(sessionCodesJson);
          if (decoded is Map) {
            _pdfSessionCodes = Map<String, String>.from(decoded);
          }
        } catch (e) {
          debugPrint('Error loading session codes: $e');
        }
      }

      // CRITICAL SYSTEM CLEANUP: Drop orphaned temp files
      await _cleanupTempFiles();
    } catch (e) {
      debugPrint('Critical error during state initialization: $e');
    }

    _notify();
  }

  Future<void> _cleanupTempFiles() async {
    try {
      final Set<String> activePaths = {};
      final Set<String> directoriesToScan = {};

      for (var cls in _classes) {
        for (var pdf in cls.pdfs) {
          if (pdf.path.isNotEmpty) {
            activePaths.add(pdf.path);
            try {
              directoriesToScan.add(File(pdf.path).parent.path);
            } catch (_) {}
          }
          if (pdf.originalPath != null) {
            activePaths.add(pdf.originalPath!);
          }
        }
      }

      for (var dirPath in directoriesToScan) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is File) {
              final path = entity.path;
              if (RegExp(r'_studyflow_temp_\d+\.pdf$').hasMatch(path)) {
                if (!activePaths.contains(path)) {
                  try {
                    await entity.delete();
                    debugPrint('Cleaned up orphaned temp file: $path');
                  } catch (e) {
                    debugPrint('Failed to delete orphan: $e');
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error in temp file cleanup routine: $e');
    }
  }

  Future<void> _saveState() async {
    // If a save is already in progress, flag that another save is needed and abort.
    if (_isSaving) {
      _needsSave = true;
      return;
    }

    _isSaving = true;
    _needsSave = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Snapshot the state synchronously to avoid mutation during async write
      final classesJson = jsonEncode(_classes.map((c) => c.toJson()).toList());
      final activeClassSnapshot = _activeClassId;

      await prefs.setString(_prefsKeyClasses, classesJson);
      if (activeClassSnapshot != null) {
        await prefs.setString(_prefsKeyActiveClass, activeClassSnapshot);
      }
      
      // Save session codes
      await prefs.setString(_prefsKeyPdfSessionCodes, jsonEncode(_pdfSessionCodes));
    } catch (e) {
      debugPrint('Error saving state: $e');
    } finally {
      _isSaving = false;
      // If state mutated while we were saving, trigger the queued save immediately
      if (_needsSave) {
        _saveState();
      }
    }
  }

  // Actions
  void toggleMobile() {
    _isMobileOpen = !_isMobileOpen;
    _notify();
  }

  void toggleDevInfo(bool show) {
    _showDevInfo = show;
    _notify();
  }

  void toggleSidebar() {
    _isSidebarCollapsed = !_isSidebarCollapsed;
    _notify();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    _notify();
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool(_prefsKeyDarkMode, _isDarkMode),
    );
  }

  void setAiProvider(String provider) {
    if (provider != 'gemini' && provider != 'groq') return;
    _aiProvider = provider;
    _notify();
    _persistAiSettings();
  }

  void setGeminiModel(String model) {
    _geminiModel = model;
    _notify();
    _persistAiSettings();
  }

  void setGroqModel(String model) {
    _groqModel = model;
    _notify();
    _persistAiSettings();
  }

  void setGeminiApiKey(String key) {
    _geminiApiKey = key.trim();
    _notify();
    _persistAiSettings();
  }

  void setGroqApiKey(String key) {
    _groqApiKey = key.trim();
    _notify();
    _persistAiSettings();
  }

  void _persistAiSettings() {
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString(_prefsKeyAiProvider, _aiProvider);
      await prefs.setString(_prefsKeyGeminiModel, _geminiModel);
      await prefs.setString(_prefsKeyGroqModel, _groqModel);
      await prefs.setString(_prefsKeyGeminiApiKey, _geminiApiKey);
      await prefs.setString(_prefsKeyGroqApiKey, _groqApiKey);
    });
  }

  void setActiveClass(String id) {
    _activeClassId = id;

    // Auto-open last active PDF when switching class
    final cls = _classes.firstWhere(
      (c) => c.classIdCheck(id),
      orElse: () => _classes.first,
    );
    if (cls.id == id && cls.lastActivePdfId != null) {
      // Verify it still exists
      if (cls.pdfs.any((p) => p.id == cls.lastActivePdfId)) {
        _activePdfId = cls.lastActivePdfId;
      } else {
        _activePdfId = null;
      }
    } else {
      _activePdfId = null;
    }

    _saveState();
    _notify();
  }

  void setActivePdf(String id) {
    _activePdfId = id;
    _isMobileOpen = false; // Close mobile drawer on selection

    // Update last active PDF for the class
    if (_activeClassId != null) {
      final index = _classes.indexWhere((c) => c.id == _activeClassId);
      if (index != -1) {
        _classes[index].lastActivePdfId = id;
      }
    }

    _saveState();
    _notify();

    // AUTO-JOIN: If lecturer opens a PDF, look for an active session.
    final hash = activePdf?.fileHash;
    final username = _currentUser?.username;
    if (_currentUser?.role == 'lecturer' && hash != null && username != null) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        _syncService.findExistingSession(username, hash).then((existingCode) {
          if (existingCode != null) {
            setSessionCode(existingCode);
            debugPrint('DEBUG: Auto-joined existing session ($existingCode) for $hash.');
          }
        });
      });
    }
  }

  // WINDOWS FILE ASSOCIATION: Load PDF file from command-line path
  Future<void> loadPdfFromPath(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return;
      }

      // Get filename without extension for display
      final fileName = file.uri.pathSegments.last;

      // Find or create "Quick Access" class
      final quickAccessName = 'Quick Access';
      ClassItem? quickAccessClass = _classes.cast<ClassItem?>().firstWhere(
        (c) => c?.name == quickAccessName,
        orElse: () => null,
      );

      if (quickAccessClass == null) {
        // Create Quick Access class
        quickAccessClass = ClassItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: quickAccessName,
          pdfs: [],
        );
        _classes.insert(0, quickAccessClass); // Add at the beginning
      }

      // Check if PDF already exists in Quick Access
      final existingPdf = quickAccessClass.pdfs.cast<PdfItem?>().firstWhere(
        (p) => p?.path == filePath,
        orElse: () => null,
      );

      if (existingPdf != null) {
        // PDF already exists, just activate it
        _activeClassId = quickAccessClass.id;
        _activePdfId = existingPdf.id;
        quickAccessClass.lastActivePdfId = existingPdf.id;
      } else {
        // Create new PDF entry
        final bytes = await file.readAsBytes();
        final hash = await FileHashService.calculateFileHash(filePath);
        final doc = PdfDocument(inputBytes: bytes);
        final pCount = doc.pages.count;
        doc.dispose();

        final newPdf = PdfItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: fileName,
          path: filePath,
          originalPath: filePath,
          fileHash: hash,
          pageCount: pCount,
        );
        quickAccessClass.pdfs.add(newPdf);

        // Set as active
        _activeClassId = quickAccessClass.id;
        _activePdfId = newPdf.id;
        quickAccessClass.lastActivePdfId = newPdf.id;
      }

      await _saveState();
      _notify();
    } catch (e) {
      debugPrint('Error loading PDF from path: $e');
    }
  }

  void addClass(String name) {
    final newClass = ClassItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      pdfs: [],
    );
    _classes.add(newClass);
    if (_activeClassId == null) {
      _activeClassId = newClass.id;
    }
    _saveState();
    _notify();
  }

  void reorderClasses(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _classes.length) return;
    if (newIndex < 0 || newIndex > _classes.length) return;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final moved = _classes.removeAt(oldIndex);
    _classes.insert(newIndex, moved);

    _saveState();
    _notify();
  }

  Future<void> uploadPdf(String classId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final file = File(filePath);
      
      final bytes = await file.readAsBytes();
      final hash = await FileHashService.calculateFileHash(filePath);
      final doc = PdfDocument(inputBytes: bytes);
      final pCount = doc.pages.count;
      doc.dispose();

      final newPdf = PdfItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result.files.single.name,
        path: filePath,
        fileHash: hash,
        pageCount: pCount,
        highlights: [],
      );

      final classIndex = _classes.indexWhere((c) => c.id == classId);
      if (classIndex != -1) {
        _classes[classIndex].pdfs.add(newPdf);
        _activeClassId = classId;
        _activePdfId = newPdf.id;
        _classes[classIndex].lastActivePdfId = newPdf.id; // Set as active
        _saveState();
        _notify();
      }
    }
  }

  void addHighlight(String pdfId, Highlight highlight) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex].highlights.add(highlight);
        // سجل الإضافة في سجل العمليات
        _actionHistory.add(
          ActionRecord(
            pdfId: pdfId,
            actionType: ActionTypes.ACTION_ADD_HIGHLIGHT,
            itemId: highlight.id,
            newState: highlight.toJson(),
          ),
        );
        debugPrint('📝 Action recorded: highlight ${highlight.id}');
        _redoHistory.clear();
        _saveState();
        _notify();
        _triggerSync(cls.pdfs[pdfIndex].fileHash ?? '');
        return;
      }
    }
  }

  Timer? _saveTimer;

  void updatePdfScroll(String pdfId, {double? scrollTop, int? pageNumber}) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        if (scrollTop != null) cls.pdfs[pdfIndex].scrollTop = scrollTop;
        if (pageNumber != null) cls.pdfs[pdfIndex].lastPage = pageNumber;

        // Debounce save
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(seconds: 1), () {
          _saveState();
        });
      }
    }
  }

  void removeHighlight(String pdfId, Highlight highlight) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.highlights.remove(highlight);
      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      
      // Anti-Resurrection: Immediate server-side delete if session is active
      final code = _pdfSessionCodes[pdf.fileHash];
      if (code != null && highlight.isSynced) {
        _syncService.deleteAnnotation(code, pdf.fileHash ?? '', highlight.id).catchError((e) {
          debugPrint('❌ deleteAnnotation failed: $e');
        });
      } else {
        _triggerSync(pdf.fileHash ?? '');
      }
      return;
    }
  }

  /// Removes a highlight by its string [id] — used during bidirectional sync cleanup.
  void removeHighlightById(String pdfId, String highlightId) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.highlights.removeWhere((h) => h.id == highlightId);
      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      return;
    }
  }


  void addComment(String pdfId, PdfComment comment) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.comments.add(comment);
      // سجل الإضافة في سجل العمليات
      _actionHistory.add(
        ActionRecord(
          pdfId: pdfId,
          actionType: ActionTypes.ACTION_ADD_COMMENT,
          itemId: comment.id,
          newState: comment.toJson(),
        ),
      );
      debugPrint('📝 Action recorded: comment ${comment.id}');
      _redoHistory.clear();
      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      return;
    }
  }

  void removeComment(String pdfId, PdfComment comment) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.comments.removeWhere((c) => c.id == comment.id);
      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);

      // Anti-Resurrection: Immediate server-side delete if session is active
      final code = _pdfSessionCodes[pdf.fileHash];
      if (code != null && comment.isSynced) {
        _syncService.deleteAnnotation(code, pdf.fileHash ?? '', comment.id).catchError((e) {
          debugPrint('❌ deleteComment failed: $e');
        });
      } else {
        _triggerSync(pdf.fileHash ?? '');
      }
      return;
    }
  }

  void clearAllAnnotations(String pdfId) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.highlights.clear();
      pdf.comments.clear();

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);

      // PHASE 10: If a session is active, wipe that fileHash's server doc
      // immediately so the next sync won't pull back deleted items.
      final fileHash = pdf.fileHash;
      final sessionCode = fileHash != null ? _pdfSessionCodes[fileHash] : null;
      if (fileHash != null && fileHash.isNotEmpty && sessionCode != null) {
        _syncService.clearAnnotationsForHash(sessionCode, fileHash).catchError((e) {
          debugPrint('clearAnnotationsForHash failed: $e');
        });
        debugPrint('DEBUG: Cleared server annotations for $fileHash (session: $sessionCode).');
      } else {
        // No session — standard buffered sync (will push empty list)
        _triggerSync(fileHash ?? '');
      }
      return;
    }
  }


  /// Wipes ALL highlights and comments across ALL documents in ALL classes.
  void clearAllGlobalAnnotations() {
    for (var cls in _classes) {
      for (var pdf in cls.pdfs) {
        pdf.highlights.clear();
        pdf.comments.clear();
      }
    }
    _actionHistory.clear();
    _redoHistory.clear();
    _notify();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1000), _saveState);
  }

  void clearAllHighlightsOnly(String pdfId) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.highlights.removeWhere((h) => h.type == HighlightType.highlight);

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      _triggerSync(pdf.fileHash ?? '');
      return;
    }
  }

  void clearAllDrawingsOnly(String pdfId) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.highlights.removeWhere(
        (h) =>
            h.type == HighlightType.pen ||
            h.type == HighlightType.arrow ||
            h.type == HighlightType.rectangle ||
            h.type == HighlightType.circle,
      );

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      _triggerSync(pdf.fileHash ?? '');
      return;
    }
  }

  void clearAllBookmarks(String pdfId) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.bookmarks.clear();

      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      return;
    }
  }

  void clearAllComments(String pdfId) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.comments.clear();

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _notify();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      return;
    }
  }

  void updateComment(
    String pdfId,
    PdfComment oldComment,
    PdfComment newComment,
  ) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      final index = pdf.comments.indexWhere((c) => c.id == oldComment.id);
      if (index != -1) {
        pdf.comments[index] = newComment;
        // سجل التعديل في سجل العمليات
        recordUpdate(
          pdfId: pdfId,
          itemId: oldComment.id,
          actionType: ActionTypes.ACTION_UPDATE_COMMENT,
          oldState: {
            'content': oldComment.content,
            'color': oldComment.color.value,
            'fontSize': oldComment.fontSize,
            'isBold': oldComment.isBold,
            'isLatex': oldComment.isLatex,
            'fontFamily': oldComment.fontFamily,
            'showBorder': oldComment.showBorder,
            'borderColor': oldComment.borderColor.value,
            'bgColor': oldComment.bgColor.value,
            'position': {
              'dx': oldComment.position.dx,
              'dy': oldComment.position.dy,
            },
          },
          newState: {
            'content': newComment.content,
            'color': newComment.color.value,
            'fontSize': newComment.fontSize,
            'isBold': newComment.isBold,
            'isLatex': newComment.isLatex,
            'fontFamily': newComment.fontFamily,
            'showBorder': newComment.showBorder,
            'borderColor': newComment.borderColor.value,
            'bgColor': newComment.bgColor.value,
            'position': {
              'dx': newComment.position.dx,
              'dy': newComment.position.dy,
            },
          },
        );
      }
      return;
    }
  }

  // ─── UNDO SYSTEM: Global Action Reversal ───────────────────────────────────
  /// Undo the most recent action (highlight or comment creation).
  /// This method:
  /// 1. Pops the most recent action ID from history
  /// 2. Finds the corresponding item in highlights or comments
  /// 3. Removes it from the state
  /// 4. Calls notifyListeners() to update UI
  void undoLastAction() {
    if (_actionHistory.isEmpty) {
      debugPrint('⚠️ Undo: No actions to undo');
      return;
    }

    final action = _actionHistory.removeLast();

    // Find the PDF
    PdfItem? pdf;
    for (var cls in _classes) {
      final found = cls.pdfs.firstWhere(
        (p) => p.id == action.pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (found.id.isNotEmpty) {
        pdf = found;
        break;
      }
    }
    if (pdf == null) {
      debugPrint('⚠️ Undo: PDF not found');
      return;
    }

    switch (action.actionType) {
      case ActionTypes.ACTION_ADD_HIGHLIGHT:
        final idx = pdf.highlights.indexWhere((h) => h.id == action.itemId);
        if (idx != -1) {
          final removed = pdf.highlights.removeAt(idx);
          _redoHistory.add(
            ActionRecord(
              pdfId: action.pdfId,
              actionType: ActionTypes.ACTION_ADD_HIGHLIGHT,
              itemId: action.itemId,
              newState: removed.toJson(),
            ),
          );
          debugPrint('🔙 Undo: Removed highlight ${action.itemId}');
        }
        break;
      case ActionTypes.ACTION_ADD_COMMENT:
        final idx = pdf.comments.indexWhere((c) => c.id == action.itemId);
        if (idx != -1) {
          final removed = pdf.comments.removeAt(idx);
          _redoHistory.add(
            ActionRecord(
              pdfId: action.pdfId,
              actionType: ActionTypes.ACTION_ADD_COMMENT,
              itemId: action.itemId,
              newState: removed.toJson(),
            ),
          );
          debugPrint('🔙 Undo: Removed comment ${action.itemId}');
        }
        break;
      case ActionTypes.ACTION_UPDATE_HIGHLIGHT:
        if (action.oldState != null) {
          final idx = pdf.highlights.indexWhere((h) => h.id == action.itemId);
          if (idx != -1) {
            _redoHistory.add(
              ActionRecord(
                pdfId: action.pdfId,
                actionType: action.actionType,
                itemId: action.itemId,
                oldState: action.newState,
                newState: action.oldState,
              ),
            );
            final restored = Highlight.fromJson(action.oldState!);
            pdf.highlights[idx] = restored;
            debugPrint('🔙 Undo: Restored highlight ${action.itemId}');
          }
        }
        break;
      case ActionTypes.ACTION_UPDATE_COMMENT:
      case ActionTypes.ACTION_MOVE_COMMENT:
        if (action.oldState != null) {
          final idx = pdf.comments.indexWhere((c) => c.id == action.itemId);
          if (idx != -1) {
            _redoHistory.add(
              ActionRecord(
                pdfId: action.pdfId,
                actionType: action.actionType,
                itemId: action.itemId,
                oldState: action.newState,
                newState: action.oldState,
              ),
            );
            final restored = PdfComment.fromJson(action.oldState!);
            pdf.comments[idx] = restored;
            debugPrint('🔙 Undo: Restored comment ${action.itemId}');
          }
        }
        break;
      case ActionTypes.ACTION_DELETE_HIGHLIGHT:
        if (action.newState != null) {
          final restored = Highlight.fromJson(action.newState!);
          pdf.highlights.add(restored);
          _redoHistory.add(
            ActionRecord(
              pdfId: action.pdfId,
              actionType: action.actionType,
              itemId: action.itemId,
              oldState: action.newState,
            ),
          );
          debugPrint('🔙 Undo: Restored deleted highlight ${action.itemId}');
        }
        break;
      case ActionTypes.ACTION_DELETE_COMMENT:
        if (action.newState != null) {
          final restored = PdfComment.fromJson(action.newState!);
          pdf.comments.add(restored);
          _redoHistory.add(
            ActionRecord(
              pdfId: action.pdfId,
              actionType: action.actionType,
              itemId: action.itemId,
              oldState: action.newState,
            ),
          );
          debugPrint('🔙 Undo: Restored deleted comment ${action.itemId}');
        }
        break;
    }

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
    _notify();
    _triggerSync(pdf.fileHash ?? '');
  }

  void redoLastAction() {
    if (_redoHistory.isEmpty) {
      debugPrint('⚠️ Redo: No actions to redo');
      return;
    }

    final action = _redoHistory.removeLast();

    PdfItem? pdf;
    for (var cls in _classes) {
      final found = cls.pdfs.firstWhere(
        (p) => p.id == action.pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (found.id.isNotEmpty) {
        pdf = found;
        break;
      }
    }
    if (pdf == null) {
      debugPrint('⚠️ Redo: PDF not found');
      return;
    }

    switch (action.actionType) {
      case ActionTypes.ACTION_ADD_HIGHLIGHT:
        if (action.newState != null) {
          final restored = Highlight.fromJson(action.newState!);
          pdf.highlights.add(restored);
          _actionHistory.add(action);
          debugPrint('↪️ Redo: Restored highlight ${action.itemId}');
        }
        break;
      case ActionTypes.ACTION_ADD_COMMENT:
        if (action.newState != null) {
          final restored = PdfComment.fromJson(action.newState!);
          pdf.comments.add(restored);
          _actionHistory.add(action);
          debugPrint('↪️ Redo: Restored comment ${action.itemId}');
        }
        break;
      case ActionTypes.ACTION_UPDATE_HIGHLIGHT:
        if (action.oldState != null) {
          final idx = pdf.highlights.indexWhere((h) => h.id == action.itemId);
          if (idx != -1) {
            _actionHistory.add(
              ActionRecord(
                pdfId: action.pdfId,
                actionType: action.actionType,
                itemId: action.itemId,
                oldState: action.newState,
                newState: action.oldState,
              ),
            );
            final restored = Highlight.fromJson(action.oldState!);
            pdf.highlights[idx] = restored;
            debugPrint('↪️ Redo: Restored highlight ${action.itemId}');
          }
        }
        break;
      case ActionTypes.ACTION_UPDATE_COMMENT:
      case ActionTypes.ACTION_MOVE_COMMENT:
        if (action.oldState != null) {
          final idx = pdf.comments.indexWhere((c) => c.id == action.itemId);
          if (idx != -1) {
            _actionHistory.add(
              ActionRecord(
                pdfId: action.pdfId,
                actionType: action.actionType,
                itemId: action.itemId,
                oldState: action.newState,
                newState: action.oldState,
              ),
            );
            final restored = PdfComment.fromJson(action.oldState!);
            pdf.comments[idx] = restored;
            debugPrint('↪️ Redo: Restored comment ${action.itemId}');
          }
        }
        break;
      case ActionTypes.ACTION_DELETE_HIGHLIGHT:
        if (action.oldState != null) {
          final idx = pdf.highlights.indexWhere((h) => h.id == action.itemId);
          if (idx != -1) {
            final removed = pdf.highlights.removeAt(idx);
            _actionHistory.add(
              ActionRecord(
                pdfId: action.pdfId,
                actionType: action.actionType,
                itemId: action.itemId,
                newState: removed.toJson(),
              ),
            );
            debugPrint('↪️ Redo: Removed highlight ${action.itemId}');
          }
        }
        break;
      case ActionTypes.ACTION_DELETE_COMMENT:
        if (action.oldState != null) {
          final idx = pdf.comments.indexWhere((c) => c.id == action.itemId);
          if (idx != -1) {
            final removed = pdf.comments.removeAt(idx);
            _actionHistory.add(
              ActionRecord(
                pdfId: action.pdfId,
                actionType: action.actionType,
                itemId: action.itemId,
                newState: removed.toJson(),
              ),
            );
            debugPrint('↪️ Redo: Removed comment ${action.itemId}');
          }
        }
        break;
    }

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
    _notify();
    _triggerSync(pdf.fileHash ?? '');
  }

  void clearActionHistory() {
    _actionHistory.clear();
    _redoHistory.clear();
    debugPrint('🧹 Action history cleared');
  }

  // Active editing state
  String? _activeEditingCommentId;
  String? get activeEditingCommentId => _activeEditingCommentId;

  // ── Color-picker ID cache (survives focus-loss during dialog) ─────────────
  String? _cachedTargetIdForColor;
  String? get cachedTargetIdForColor => _cachedTargetIdForColor;

  /// Call this BEFORE the color-picker dialog opens so the target id is safe.
  void cacheTargetIdForColor(String? id) {
    _cachedTargetIdForColor = id;
  }

  /// Apply color fields to the cached comment.
  /// Works even if activeEditingCommentId was cleared by focus loss.
  void applyColorToCachedComment({
    Color? color,
    Color? bgColor,
    Color? borderColor,
  }) {
    final id = _cachedTargetIdForColor;
    if (id == null) return;

    // Case 1: still in temp-editing mode ─ update live styles
    if (_tempStyles.containsKey(id)) {
      updateEditingStyle(
        commentId: id,
        color: color,
        bgColor: bgColor,
        borderColor: borderColor,
      );
      return;
    }

    // Case 2: not editing any more ─ patch the stored comment directly
    for (final cls in _classes) {
      for (final pdf in cls.pdfs) {
        final idx = pdf.comments.indexWhere((c) => c.id == id);
        if (idx == -1) continue;
        final old = pdf.comments[idx];
        pdf.comments[idx] = old.copyWith(
          color: color ?? old.color,
          bgColor: bgColor ?? old.bgColor,
          borderColor: borderColor ?? old.borderColor,
        );
        _notify();
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
        return;
      }
    }
  }

  /// Call this AFTER the color-picker dialog is fully dismissed.
  void clearCachedTargetId() {
    _cachedTargetIdForColor = null;
  }

  // Temporary style states (NO text content stored here!)
  final Map<String, Map<String, dynamic>> _tempStyles = {};

  // Start editing a comment
  void startEditing(String commentId, PdfComment comment) {
    _activeEditingCommentId = commentId;
    // Store initial styles
    _tempStyles[commentId] = {
      'color': comment.color.value,
      'fontSize': comment.fontSize,
      'isBold': comment.isBold,
      'isLatex': comment.isLatex,
      'fontFamily': comment.fontFamily,
      'showBorder': comment.showBorder,
      'borderColor': comment.borderColor.value,
      'bgColor': comment.bgColor.value,
    };
    _notify();
  }

  // Update style during editing (called from right panel)
  void updateEditingStyle({
    required String commentId,
    Color? color,
    double? fontSize,
    bool? isBold,
    bool? isLatex,
    String? fontFamily,
    bool? showBorder,
    Color? borderColor,
    Color? bgColor,
  }) {
    if (!_tempStyles.containsKey(commentId)) return;

    final styles = _tempStyles[commentId]!;
    if (color != null) styles['color'] = color.value;
    if (fontSize != null) styles['fontSize'] = fontSize;
    if (isBold != null) styles['isBold'] = isBold;
    if (isLatex != null) styles['isLatex'] = isLatex;
    if (fontFamily != null) styles['fontFamily'] = fontFamily;
    if (showBorder != null) styles['showBorder'] = showBorder;
    if (borderColor != null) styles['borderColor'] = borderColor.value;
    if (bgColor != null) styles['bgColor'] = bgColor.value;

    _notify(); // Triggers rebuild of DraggableTextWidget with new styles
  }

  // Get current temporary styles (or null if not editing)
  Map<String, dynamic>? getEditingStyles(String commentId) {
    return _tempStyles[commentId];
  }

  // End editing and save final comment
  Future<void> endEditing(String commentId, String finalContent) async {
    final styles = _tempStyles[commentId];
    if (styles == null) return;

    // Find the original comment
    final pdf = activePdf;
    if (pdf == null) return;

    try {
      final originalComment = pdf.comments.firstWhere((c) => c.id == commentId);

      // Create updated comment with final styles
      final updatedComment = originalComment.copyWith(
        content: finalContent,
        color: Color(styles['color']),
        fontSize: styles['fontSize'],
        isBold: styles['isBold'],
        isLatex: styles['isLatex'],
        fontFamily: styles['fontFamily'],
        showBorder: styles['showBorder'],
        borderColor: Color(styles['borderColor']),
        bgColor: Color(styles['bgColor']),
      );

      // Save to database
      updateComment(pdf.id, originalComment, updatedComment);
    } catch (e) {
      debugPrint('Error ending editing: $e');
    }

    // Clean up
    _tempStyles.remove(commentId);
    if (_activeEditingCommentId == commentId) {
      _activeEditingCommentId = null;
    }
    _notify();
  }

  // Cancel editing without saving
  void cancelEditing(String commentId) {
    _tempStyles.remove(commentId);
    if (_activeEditingCommentId == commentId) {
      _activeEditingCommentId = null;
    }
    _notify();
  }

  // app_state.dart updates

  Future<void> deletePage(String pdfId, int pageIndex) async {
    final cls = _classes.firstWhere((c) => c.pdfs.any((p) => p.id == pdfId));
    final pdfItem = cls.pdfs.firstWhere((p) => p.id == pdfId);
    final file = File(pdfItem.path);

    if (!await file.exists()) return;

    if (pageIndex >= 0) {
      _shiftAnnotationsAfterDelete(pdfItem, pageIndex);

      final sourcePath = pdfItem.path;
      final realPath = pdfItem.originalPath ?? pdfItem.path;
      final tempPath =
          "${realPath.replaceAll('.pdf', '')}_studyflow_temp_${DateTime.now().microsecondsSinceEpoch}.pdf";

      // ISOLATE OPERATION
      final bool success = await Isolate.run(() async {
        try {
          final isolateSourceFile = File(sourcePath);
          if (!await isolateSourceFile.exists()) return false;

          final bytes = await isolateSourceFile.readAsBytes();
          final document = PdfDocument(inputBytes: bytes);

          if (pageIndex < document.pages.count && document.pages.count > 1) {
            document.pages.removeAt(pageIndex);
            final newBytes = await document.save();
            await File(tempPath).writeAsBytes(newBytes, flush: true);

            if (realPath != tempPath) {
              await File(realPath).writeAsBytes(newBytes, flush: true);
            }
            document.dispose();
            return true;
          }
          document.dispose();
          return false;
        } catch (e) {
          return false;
        }
      });

      if (!success) return;

      if (pdfItem.path != realPath && pdfItem.path != tempPath) {
        try {
          await File(pdfItem.path).delete();
        } catch (_) {}
      }

      await Future.delayed(const Duration(milliseconds: 100));
      final int newTimestamp = DateTime.now().millisecondsSinceEpoch;

      final updatedPdf = pdfItem.copyWith(
        path: tempPath,
        originalPath: realPath,
        lastModified: newTimestamp,
        lastPage: pdfItem.lastPage,
      );

      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex] = updatedPdf;
      }
      _notify();
    }
  }

  Future<void> addPage(String pdfId, {int? insertAtIndex}) async {
    try {
      final cls = _classes.firstWhere((c) => c.pdfs.any((p) => p.id == pdfId));
      final pdfItem = cls.pdfs.firstWhere((p) => p.id == pdfId);
      final file = File(pdfItem.path);

      if (!await file.exists()) return;

      final sourcePath = pdfItem.path;
      final realPath = pdfItem.originalPath ?? pdfItem.path;
      final tempPath =
          "${realPath.replaceAll('.pdf', '')}_studyflow_temp_${DateTime.now().microsecondsSinceEpoch}.pdf";

      // ISOLATE OPERATION
      final bool success = await Isolate.run(() async {
        try {
          final isolateSourceFile = File(sourcePath);
          if (!await isolateSourceFile.exists()) return false;

          final bytes = await isolateSourceFile.readAsBytes();
          final document = PdfDocument(inputBytes: bytes);

          if (insertAtIndex != null &&
              insertAtIndex >= 0 &&
              insertAtIndex <= document.pages.count) {
            document.pages.insert(insertAtIndex);
          } else {
            document.pages.add();
          }

          final newBytes = await document.save();
          await File(tempPath).writeAsBytes(newBytes, flush: true);

          if (realPath != tempPath) {
            await File(realPath).writeAsBytes(newBytes, flush: true);
          }
          document.dispose();
          return true;
        } catch (e) {
          return false;
        }
      });

      if (!success) return;

      if (pdfItem.path != realPath && pdfItem.path != tempPath) {
        try {
          await File(pdfItem.path).delete();
        } catch (_) {}
      }

      await Future.delayed(const Duration(milliseconds: 100));
      final int newTimestamp = DateTime.now().millisecondsSinceEpoch;

      final updatedPdf = pdfItem.copyWith(
        path: tempPath,
        originalPath: realPath,
        lastModified: newTimestamp,
        lastPage: insertAtIndex != null ? insertAtIndex + 1 : null,
      );

      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex] = updatedPdf;
      }
      _notify();
    } catch (e) {
      debugPrint("Error adding page: $e");
    }
  }

  void _shiftAnnotationsAfterDelete(PdfItem pdf, int deletedPageIndex) {
    // pageIndex is 0-based.
    // Models use 1-based indexing for pages.
    final int deletedPageNum = deletedPageIndex + 1;

    // 1. Remove annotations on the deleted page
    pdf.highlights.removeWhere((h) => h.page == deletedPageNum);
    pdf.comments.removeWhere((c) => c.page == deletedPageNum);

    // 2. Shift subsequent annotations up (decrement page number)
    // We need to replace the lists because logic might require new instances
    // But since we have a List<Highlight>, we can just replace elements or use a new list.

    // Highlights
    List<Highlight> updatedHighlights = [];
    for (var h in pdf.highlights) {
      if (h.page > deletedPageNum) {
        updatedHighlights.add(h.copyWith(page: h.page - 1));
      } else {
        updatedHighlights.add(h);
      }
    }
    pdf.highlights.clear();
    pdf.highlights.addAll(updatedHighlights);

    // Comments
    List<PdfComment> updatedComments = [];
    for (var c in pdf.comments) {
      if (c.page > deletedPageNum) {
        updatedComments.add(c.copyWith(page: c.page - 1));
      } else {
        updatedComments.add(c);
      }
    }
    pdf.comments.clear();
    pdf.comments.addAll(updatedComments);

    // Save the state with shifted annotations
    _saveState();
  }

  // Management Methods
  void closeActivePdf() {
    _activePdfId = null;
    if (_activeClassId != null) {
      final clsIndex = _classes.indexWhere((c) => c.id == _activeClassId);
      if (clsIndex != -1) {
        _classes[clsIndex].lastActivePdfId = null;
      }
    }
    _saveState();
    _notify();
  }

  Future<void> deleteClass(String classId) async {
    _classes.removeWhere((c) => c.id == classId);

    if (_activeClassId == classId) {
      _activeClassId = _classes.isNotEmpty ? _classes.first.id : null;
      _activePdfId = null;
    }

    _saveState();
    _notify();
  }

  Future<void> deletePdf(String classId, String pdfId) async {
    final clsIndex = _classes.indexWhere((c) => c.id == classId);
    if (clsIndex == -1) return;

    final cls = _classes[clsIndex];
    final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
    if (pdfIndex == -1) return;

    final pdf = cls.pdfs[pdfIndex];

    // Physical deletion
    try {
      final file = File(pdf.path);
      if (await file.exists()) await file.delete();

      if (pdf.originalPath != null) {
        final originalFile = File(pdf.originalPath!);
        if (await originalFile.exists()) await originalFile.delete();
      }
    } catch (e) {
      debugPrint("Error deleting file: $e");
    }

    // State update
    cls.pdfs.removeAt(pdfIndex);

    if (_activePdfId == pdfId) {
      _activePdfId = null;
    }

    if (cls.lastActivePdfId == pdfId) {
      _classes[clsIndex].lastActivePdfId = null;
    }

    _saveState();
    _notify();
  }

  void addBookmark(String pdfId, String name, int pageNumber) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        final newBookmark = PdfBookmark(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          page: pageNumber,
          name: name,
        );
        cls.pdfs[pdfIndex].bookmarks.add(newBookmark);
        _saveState();
        _notify();
        return;
      }
    }
  }

  void deleteBookmark(String pdfId, String bookmarkId) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex].bookmarks.removeWhere((b) => b.id == bookmarkId);
        _saveState();
        _notify();
        return;
      }
    }
  }

  void movePdf(String pdfId, String sourceClassId, String targetClassId) {
    if (sourceClassId == targetClassId) return;

    final sourceClassIndex = _classes.indexWhere((c) => c.id == sourceClassId);
    final targetClassIndex = _classes.indexWhere((c) => c.id == targetClassId);

    if (sourceClassIndex == -1 || targetClassIndex == -1) return;

    final sourceClass = _classes[sourceClassIndex];
    final targetClass = _classes[targetClassIndex];

    final pdfIndex = sourceClass.pdfs.indexWhere((p) => p.id == pdfId);
    if (pdfIndex == -1) return;

    final pdf = sourceClass.pdfs[pdfIndex];

    // Remove from source
    sourceClass.pdfs.removeAt(pdfIndex);
    if (sourceClass.lastActivePdfId == pdfId) {
      sourceClass.lastActivePdfId = null;
    }

    // Add to target
    targetClass.pdfs.add(pdf);

    // Update active state
    _activeClassId = targetClassId;
    if (_activePdfId == pdfId) {
      // If the moved PDF was active, keep it active but ensure ensuring class context is correct
      // (activeClassId is already updated above)
    }

    _saveState();
    _notify();
  }

  void reorderPdfWithinClass(
    String classId,
    String draggedPdfId,
    String targetPdfId,
  ) {
    final classIndex = _classes.indexWhere((c) => c.id == classId);
    if (classIndex == -1) return;

    final cls = _classes[classIndex];
    final oldIndex = cls.pdfs.indexWhere((p) => p.id == draggedPdfId);
    final targetIndex = cls.pdfs.indexWhere((p) => p.id == targetPdfId);
    if (oldIndex == -1 || targetIndex == -1 || oldIndex == targetIndex) return;

    final dragged = cls.pdfs.removeAt(oldIndex);
    var insertIndex = targetIndex;
    if (oldIndex < targetIndex) {
      insertIndex -= 1;
    }
    cls.pdfs.insert(insertIndex, dragged);

    _saveState();
    _notify();
  }

  @override
  void dispose() {
    _stopKickListener();
    _stopUserMonitor();
    for (var timer in _syncTimers.values) {
      timer?.cancel();
    }
    if (_saveTimer != null && _saveTimer!.isActive) {
      _saveTimer!.cancel();
      _saveState(); // Flush pending save immediately
    }
    super.dispose();
  }
}

extension ClassIdHelper on ClassItem {
  bool classIdCheck(String id) => this.id == id;
}
