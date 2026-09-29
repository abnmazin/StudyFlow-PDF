import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' hide PdfBookmark;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../models/app_user.dart';
import '../models/lecture_slot.dart';
import '../models/timetable_entry.dart';
import '../models/folder_announcement.dart';
import '../models/isar_models.dart' hide PdfDocument;
import 'package:isar/isar.dart';
import '../models/structure.dart';
import '../services/file_manager_service.dart';
import '../services/file_hash_service.dart';
import '../services/sync_service.dart';
import '../services/pdf_mutation_service.dart';
import '../services/reading_stats_service.dart';
import '../services/timetable_service.dart';
import '../services/folder_announcement_service.dart';
import '../services/university_service.dart';
import '../services/library_sync_service.dart';
import '../services/hardware_service.dart';
import '../services/mcp_client_service.dart';
import '../screens/auth/login_screen.dart';

enum DrawingSyncStrategy { disabled, immediate, buffered, isolate }

Timer? _readingStateTimer;

class DevSettings {
  int? trimDelayMs;
  int? trimMinIntervalMs;
  bool? telemetryEnabled;

  DevSettings({
    this.trimDelayMs,
    this.trimMinIntervalMs,
    this.telemetryEnabled,
  });
}

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

class AppProvider extends ChangeNotifier with WidgetsBindingObserver {
  final SyncService _syncService;
  final FileManagerService _fileManager = FileManagerService();
  final HardwareService _hardwareService = HardwareService();

  AppProvider({SyncService? syncService})
    : _syncService = syncService ?? SyncService() {
    _initConnectivity();
    _initialize();
    WidgetsBinding.instance.addObserver(this);
  }

  void _initConnectivity() {
    // connectivity_plus 6.x activates a Windows Network List Manager listener
    // that fails with PlatformException(298, NetworkManager::StartListen) on
    // machines where that service is unavailable. The throw happens inside
    // EventChannel.receiveBroadcastStream while the platform stream is being
    // activated, so the `onError` below never sees it: it reaches the zone as
    // an unhandled "Exception caught by services library" with a stack that
    // contains no app frames at all. Nothing in the app reads `isOffline`, so
    // the subscription is simply not opened on Windows rather than opening a
    // stream that is guaranteed to fail and print a stack trace on every cold
    // start. Other platforms keep the listener.
    if (Platform.isWindows) return;

    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        final isNowOffline = results.contains(ConnectivityResult.none);
        if (_isOffline != isNowOffline) {
          _isOffline = isNowOffline;
          _notify();
          debugPrint(
            '🌐 Network Status Changed: ${_isOffline ? 'OFFLINE' : 'ONLINE'}',
          );
        }
      },
      onError: (Object error) {
        debugPrint(
          '⚠️ [Network] Connectivity stream unavailable, staying online: $error',
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _stopKickListener();
    _stopUserMonitor();
    _syncDebounce?.cancel();
    _disposeTimetable();
    _disposeAnnouncements();
    unawaited(_syncService.dispose());
    for (var timer in _syncTimers.values) {
      timer?.cancel();
    }
    if (_saveTimer != null && _saveTimer!.isActive) {
      _saveTimer!.cancel();
      _saveState(); // Flush pending save immediately
    }

    // Auto-sync disabled by design: no network flush on dispose.

    if (_readingStateTimer != null && _readingStateTimer!.isActive) {
      _readingStateTimer!.cancel();
      final pdf = activePdf;
      if (pdf != null) {
        FileManagerService().updateReadingState(
          pdf.id,
          page: pdf.lastPage,
          scroll: pdf.scrollTop,
        );
      }
    }

    _suspendReadingSession();

    McpClientService.instance.stop();
    super.dispose();
  }

  // ─── SYNC MUTATION BRIDGE ──────────────────────────────────────────────────
  // Routes structural mutation broadcasts through AppProvider so that UI
  // widgets in Overlays/new Routes don't need to find SyncService in context.
  Future<void> broadcastMutation(
    String fileHash,
    String action,
    int pageIndex,
  ) async {
    await _syncService.broadcastMutation(fileHash, action, pageIndex);
  }

  // ─── STATE FIELDS ──────────────────────────────────────────────────────────
  List<ClassItem> _classes = [];
  String? _activeClassId;
  String? _activePdfId;
  String? _secondaryPdfId;

  /// PDF opened from the college collection without saving to any folder.
  /// Not persisted to Isar; view-only ephemeral reader.
  PdfItem? _ephemeralPdf;
  bool _isSplitMode = false;
  AppUser? _currentUser;
  Map<String, String> _pdfSessionCodes =
      {}; // Key: fileHash, Value: sessionCode
  bool _sessionLocked = false;
  bool _sessionJoinLocked = false;
  List<ActionRecord> _actionHistory = [];

  /// The gesture whose history entry is currently on top, or null when the last
  /// recorded edit was discrete. Set by [recordUpdate]; it is what lets the
  /// frames of one drag fold into a single entry without folding into an
  /// unrelated edit that happened to precede them.
  int? _coalescingGesture;
  List<ActionRecord> _redoHistory = [];
  StreamSubscription? _kickSub;
  Timer? _userMonitorTimer;
  String? _forcedLogoutReason;
  bool _isGlobalLogout = false;
  bool _isKicked = false;
  bool _isKeyboardLocked = false;
  bool get isKeyboardLocked => _isKeyboardLocked;

  // UI State
  bool _isMobileOpen = false;
  bool _showDevInfo = false;
  bool _isSidebarCollapsed = false;
  bool _isDarkMode = true;
  bool _isSettingsOpen = false;

  /// The university-library folder whose announcements are filling the main
  /// content area, or null when the dashboard owns it.
  ///
  /// A view selection, not a domain fact, so it is deliberately not persisted:
  /// reopening the app on a folder's announcements with no memory of how the
  /// reader got there would be a trap.
  UniversityFolder? _announcementsFolder;
  DrawingSyncStrategy _drawingSyncStrategy = DrawingSyncStrategy.disabled;
  final DevSettings _devSettings = DevSettings();

  // Connectivity State
  bool _isOffline = false;
  bool get isOffline => _isOffline;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // List to save notification IDs hidden by the student locally
  final Set<String> _hiddenAnnouncements = {};
  bool isAnnouncementHidden(String id) => _hiddenAnnouncements.contains(id);
  void hideAnnouncementLocally(String id) {
    _hiddenAnnouncements.add(id);
    _notify();
  }

  // Phase 3B: Dirty PDF tracking for annotation persistence
  final Set<String> _dirtyPdfIds = {};

  void markPdfDirty(String pdfId) {
    if (pdfId.isEmpty) return;
    // `Set.add` reports whether the id was new. A shape drag marks its document
    // dirty on every pointer frame, and the id stays in the set until the flush
    // clears it, so this logs the start of a burst instead of one line per
    // frame — which is what buried the console during a drag.
    final added = _dirtyPdfIds.add(pdfId);
    if (added) debugPrint('📝 [AppProvider] Marked PDF as dirty: $pdfId');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
  }

  DrawingSyncStrategy get drawingSyncStrategy => _drawingSyncStrategy;
  DevSettings get devSettings => _devSettings;
  FileManagerService get fileManager => FileManagerService();

  void setDrawingSyncStrategy(DrawingSyncStrategy strategy) {
    _drawingSyncStrategy = strategy;
    _notify();
  }

  // AI & Models
  static const List<String> geminiModelsList = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];
  static const List<String> groqModelsList = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
  ];
  static const List<String> mcpModelsList = [
    'gemini-2.5 (personal)',
    'gemini-2.0 (personal)',
  ];

  String _aiProvider = 'groq';
  String _geminiModel = 'gemini-2.5-flash';
  String _groqModel = 'llama-3.3-70b-versatile';
  String _mcpModel = 'gemini-2.5 (personal)';
  String _geminiApiKey = '';
  String _groqApiKey = '';
  int _fallbackAttempts = 0;

  // Concurrency & Flow
  bool _isSaving = false;
  bool _needsSave = false;
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  /// Bumped whenever the open file or its session code changes. A sync that
  /// resumes after an await and finds a different generation was started for a
  /// file the user has already left, and its code and hash no longer describe
  /// the same document, so it must not write anything.
  int _syncGeneration = 0;
  bool _notifyScheduled = false;
  String? _lastMutationListenerHash;
  bool _isJoiningSession = false;
  bool get isJoiningSession => _isJoiningSession;
  Timer? _syncDebounce; // Debouncer for background sync

  /// Window that coalesces bursts of annotation edits (drag frames, text
  /// keystrokes) into a single sync pass. Because every call cancels the
  /// previous timer, a continuous drag keeps deferring the sync until the
  /// pointer settles, which is exactly the desired coalescing behaviour.
  static const Duration _syncDebounceWindow = Duration(milliseconds: 1200);

  /// When the last annotation edit was applied, or null if none this session.
  ///
  /// The debounce keeps *new* syncs away from an active gesture but cannot
  /// recall one already in flight — started 1.4s ago, or fired by the other
  /// client's realtime update — which lands mid-drag and rewrites the
  /// annotation lists under the pointer. That rewrite is what makes a dragged
  /// shape jump. This stamp is what lets a running sync wait its turn.
  DateTime? _lastAnnotationEditFrame;

  /// How long a sync defers to an annotation edit, measured from the last edit.
  /// Converges by construction: a pointer that stops stops refreshing the stamp.
  /// Long enough to cover the gap between two frames of a slow drag, short
  /// enough that pausing does not stall the sync.
  static const Duration _annotationEditGraceWindow = Duration(
    milliseconds: 600,
  );

  ToolType _currentTool = ToolType.cursor;
  ToolType get currentTool => _currentTool;

  void setKeyboardLock(bool isLocked) {
    if (_isKeyboardLocked != isLocked) {
      _isKeyboardLocked = isLocked;
      notifyListeners();
    }
  }

  final Completer<void> _initCompleter = Completer<void>();
  Future<void>? get initialized => _initCompleter.future;

  // ─── TRIGGER SYNC ──────────────────────────────────────────────────────────

  final Map<String, Timer?> _syncTimers = {};
  final Map<String, bool> _pendingSyncs = {};
  final Map<String, Set<String>> _locallyDeletedIds = {}; // Key: fileHash
  final Map<String, Set<String>> _lockedLocalOnlyHighlightIds = {};
  final Set<String> _intentionallyDeletedIds = {};

  /// fileHash values confirmed to belong to the university library, so the
  /// reading position of those booklets is mirrored to Firestore.
  final Set<String> _libraryLinkedHashes = {};

  /// Last time a reading position was pushed per file, so scrolling does not
  /// turn into a Firestore write on every debounce tick.
  final Map<String, DateTime> _lastProgressPush = {};

  static const Duration _progressPushInterval = Duration(seconds: 10);

  Future<void> triggerSync() async {
    if (_isSyncing) return;
    await performBidirectionalSync(silent: true);
  }

  /// Fetch → Purge orphans → Download missing → Upload new.
  /// Has a cooldown guard so concurrent calls are silently ignored.
  Future<void> performBidirectionalSync({bool silent = false}) async {
    // Everything this run needs is captured in one synchronous block, before
    // the first await. Reading the file and the session code separately, with
    // network calls in between, let a run pick up the code of the file the
    // user just opened and pair it with the hash of the one they just left.
    final activePdf = this.activePdf;
    if (activePdf == null) return;
    final fileHash = activePdf.fileHash;
    if (fileHash == null) return;
    final sessionCode = currentSessionCode;
    if (sessionCode == null) return;
    final generation = _syncGeneration;

    // ── Phase 1: Wait for any pending buffered syncs to finish ────────────────
    if (_pendingSyncs[fileHash] == true) {
      debugPrint(
        'DEBUG: Waiting for pending buffered sync before reconciliation...',
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // The lock is taken here, synchronously, rather than further down. Setting
    // it after the awaits above let every caller that arrived in that window
    // pass the check, which is how several syncs of one session ended up
    // writing at the same time.
    if (_isSyncing) {
      debugPrint('DEBUG: Sync already in progress – skipping.');
      return;
    }
    _isSyncing = true;
    if (!silent) {
      _notify();
    }

    try {
      // --- STEP 0: ACCOUNT VALIDITY CHECK ---
      if (_currentUser != null) {
        final exists = await _syncService.checkUserExists(_currentUser!.uid);
        if (!exists) {
          _handleForceLogout('هذا الحساب لم يعد موجوداً في النظام (تم حذفه).');
          return;
        }
      }

      // --- STEP 0.1: SESSION KICK FALLBACK ---
      if (_currentUser != null) {
        final isKicked = await _syncService.isUserKicked(
          sessionCode,
          _currentUser!.username,
        );
        if (isKicked) {
          _handleForceLogout(
            'لقد تم إنهاء وصولك لهذه الجلسة من قبل المالك (Manual Check)',
          );
          return;
        }
      }

      // The user may have moved on during those calls. The captured pair
      // belongs to a file that is no longer open, so writing it now would mix
      // one document's annotations into another's session.
      if (generation != _syncGeneration) {
        debugPrint(
          'DEBUG: Sync for $sessionCode/$fileHash abandoned: the open file or '
          'its session changed while the checks were running.',
        );
        return;
      }

      // An annotation is being edited right now. A pass that starts now would
      // rewrite the highlights and comments lists between two frames of that
      // gesture, which is what makes a dragged shape jump — and the remote
      // copies it injects are older than the frame the pointer just produced.
      // The debounce cannot prevent this on its own: a pass started 1.4s ago by
      // the previous frame, or by the other client's realtime update, is already
      // past it. Re-arming the timer is not a retry loop: the stamp is refreshed
      // by every frame, so a pointer that stops stops deferring.
      final lastEdit = _lastAnnotationEditFrame;
      if (lastEdit != null &&
          DateTime.now().difference(lastEdit) < _annotationEditGraceWindow) {
        debugPrint(
          'DEBUG: Sync for $sessionCode/$fileHash deferred: an annotation is '
          'being edited right now.',
        );
        triggerDebouncedSync();
        return;
      }

      debugPrint(
        'DEBUG: performBidirectionalSync started (session: $sessionCode, hash: $fileHash, silent: $silent).',
      );

      _purgeLockedLocalOnlyHighlightsForPdf(activePdf);

      final result = await _syncService.syncExistingAnnotations(
        code: sessionCode,
        fileHash: fileHash,
        highlights: activePdf.highlights,
        comments: activePdf.comments,
        locallyDeletedIds: _locallyDeletedIds[fileHash] ?? {},
      );

      // Successfully synced? Clear the locally deleted ids for this hash
      _locallyDeletedIds[fileHash]?.clear();

      // ── Orphan Pruning & Sync State Persistence ─────────────────────────
      final serverIds = result.serverIds;
      final orphans = result.orphans;

      // Update local highlights: mark synced or remove orphans
      final localHighlights = List.of(activePdf.highlights);
      for (final h in localHighlights) {
        if (orphans.contains(h.id)) {
          if (_intentionallyDeletedIds.contains(h.id)) continue;
          activePdf.highlights.removeWhere((item) => item.id == h.id);
        } else if (serverIds.contains(h.id)) {
          if (!h.isSynced) {
            final idx = activePdf.highlights.indexWhere(
              (item) => item.id == h.id,
            );
            if (idx != -1)
              activePdf.highlights[idx] = h.copyWith(isSynced: true);
          }
        }
      }

      // Update local comments: mark synced or remove orphans
      final localComments = List.of(activePdf.comments);
      for (final c in localComments) {
        if (orphans.contains(c.id)) {
          if (_intentionallyDeletedIds.contains(c.id)) continue;
          activePdf.comments.removeWhere((item) => item.id == c.id);
        } else if (serverIds.contains(c.id)) {
          if (!c.isSynced) {
            final idx = activePdf.comments.indexWhere(
              (item) => item.id == c.id,
            );
            if (idx != -1) activePdf.comments[idx] = c.copyWith(isSynced: true);
          }
        }
      }

      // ── Inject/Update Highlights from Server ────────────────────────────
      for (final json in result.toAddHighlights) {
        try {
          final h = Highlight.fromJson(
            Map<String, dynamic>.from(json),
          ).copyWith(isSynced: true);
          if (_intentionallyDeletedIds.contains(h.id)) continue;
          final idx = activePdf.highlights.indexWhere(
            (item) => item.id == h.id,
          );
          if (idx != -1) {
            activePdf.highlights[idx] = h;
          } else {
            activePdf.highlights.add(h);
          }
          debugPrint('📥 Downloaded highlight: ${h.id}');
        } catch (e) {
          debugPrint('❌ Error parsing highlight from server: $e');
        }
      }

      // ── Inject/Update Comments from Server ──────────────────────────────
      for (final json in result.toAddComments) {
        try {
          final c = PdfComment.fromJson(
            Map<String, dynamic>.from(json),
          ).copyWith(isSynced: true);
          if (_intentionallyDeletedIds.contains(c.id)) continue;
          final idx = activePdf.comments.indexWhere((item) => item.id == c.id);
          if (idx != -1) {
            activePdf.comments[idx] = c;
          } else {
            activePdf.comments.add(c);
          }
          debugPrint('📥 Downloaded comment: ${c.id}');
        } catch (e) {
          debugPrint('❌ Error parsing comment from server: $e');
        }
      }

      // ── Collaborative Trash Sync ──────────────────────────────────────────
      // The captured code is reused rather than re-read, so the trash lands in
      // the same session as the annotations this run just reconciled.
      if (generation == _syncGeneration) {
        try {
          final unsyncedTrash = await _fileManager
              .getUnsyncedDeletedAnnotations();
          final remoteTrashJson = await _syncService.syncDeletedAnnotations(
            sessionCode: sessionCode,
            localUnsynced: unsyncedTrash.map((e) => e.toJson()).toList(),
          );

          // Mark local as synced
          if (unsyncedTrash.isNotEmpty) {
            await _fileManager.markDeletedAnnotationsAsSynced(
              unsyncedTrash.map((e) => e.id).toList(),
            );
          }

          // Save remote to local
          if (remoteTrashJson.isNotEmpty) {
            final remoteModels = remoteTrashJson
                .map((e) => DeletedAnnotation.fromJson(e))
                .toList();
            await _fileManager.saveRemoteDeletedAnnotations(remoteModels);
          }
        } catch (trashError) {
          debugPrint('⚠️ Collaborative Trash Sync failed: $trashError');
        }
      }

      debugPrint(
        'DEBUG: performBidirectionalSync done. Deleted: ${result.deletedCount}, Downloaded: ${result.downloadedCount}, Uploaded: ${result.uploadedCount}.',
      );

      if (result.uploadedCount >= 0) {
        // Successfully synced
      }
    } catch (e) {
      debugPrint('ERROR: performBidirectionalSync failed: $e');
    } finally {
      _isSyncing = false;
      // Unconditional: every caller passes silent: true, and the injected
      // remote highlights/comments live in the model only. Gating this on
      // !silent meant synced annotations were applied but never rendered until
      // some unrelated interaction happened to notify. _notify() is already
      // coalesced through a microtask, so this is cheap.
      _notify();
      _startRealtimeAnnotationListener();
    }
  }

  void _startRealtimeAnnotationListener() {
    final pdf = activePdf;
    final code = currentSessionCode;
    final fileHash = pdf?.fileHash;
    if (pdf == null || code == null || fileHash == null || fileHash.isEmpty) {
      unawaited(_syncService.stopRealtimeAnnotations());
      return;
    }

    unawaited(
      _syncService.startRealtimeAnnotations(
        code,
        fileHash,
        onData: (items, lastDeletedAt) {
          if (_isSyncing ||
              currentSessionCode != code ||
              activePdf?.fileHash != fileHash) {
            return;
          }
          unawaited(performBidirectionalSync(silent: true));
        },
        onError: (error, stackTrace) {
          debugPrint('Realtime annotation listener error: $error');
        },
      ),
    );
  }

  /// Schedules a debounced [performBidirectionalSync] after
  /// [_syncDebounceWindow]. Used for gestures and tool changes to avoid UI lag.
  ///
  /// `silent` is retained for call-site compatibility but is intentionally
  /// unused: [performBidirectionalSync] now always notifies after injecting
  /// remote data, and callers must not reintroduce a UI-suppressing path.
  void triggerDebouncedSync({bool silent = true}) {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(_syncDebounceWindow, () {
      _syncDebounce = null;
      unawaited(performBidirectionalSync());
    });
  }

  /// Cancels any pending debounced sync.
  void cancelDebouncedSync() {
    _syncDebounce?.cancel();
  }

  void _markUnsavedChanges() {
    // Marked as unsaved for tracking purposes
  }

  void setCurrentTool(ToolType tool) {
    _currentTool = tool;
    _notify();

    // Trigger sync ONLY if switching to hand tool and in active session
    if (tool == ToolType.cursor && currentSessionCode != null) {
      debugPrint(
        "DEBUG: AppProvider switching to Hand Tool. Triggering Debounced Sync...",
      );
      triggerDebouncedSync(silent: true);
    }
  }

  void _triggerSync(String fileHash) {
    // Guard against a stale hash: if the caller already knows which document it
    // touched, only push when that document is still the active one. An empty
    // hash means the caller could not identify it, so the sync is allowed
    // through rather than silently dropped.
    if (fileHash.isNotEmpty && fileHash != activePdf?.fileHash) {
      return;
    }
    // Debounced, not immediate. This runs once per pointer frame while a shape
    // is moved or resized. Syncing immediately put a Firestore round trip and a
    // full annotation diff between two frames of the same drag, and every pass
    // rewrote the annotation lists while the pointer was still down on one of
    // them — which is what made a dragged shape jump and the gesture feel
    // heavy. Every frame re-arms the timer, so one drag produces one sync,
    // ~1.2s after the pointer settles. Matches updateComment, which already
    // debounced.
    triggerDebouncedSync();
  }

  void _notify() {
    if (!hasListeners || _notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      try {
        if (hasListeners) notifyListeners();
      } catch (e) {
        debugPrint('Safe Notify Error: $e');
      }
    });
  }

  // --- LIFECYCLE MANAGEMENT (Patch 2) ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    //-- debugPrint('📱 AppLifecycleState changed to: $state');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _pauseAllListeners();
      _suspendReadingSession();
    } else if (state == AppLifecycleState.resumed) {
      _resumeAllListeners();
    }
  }

  void _pauseAllListeners() {
    // --- debugPrint('⏸️ Pausing background listeners & timers.');
    _kickSub?.pause();
    _userMonitorTimer?.cancel();
    _userMonitorTimer = null;
    _syncDebounce?.cancel(); // Stop pending syncs
  }

  void _resumeAllListeners() {
    debugPrint('▶️ Resuming background listeners & timers.');
    _kickSub?.resume();
    if (_currentUser != null &&
        _currentUser!.uid.isNotEmpty &&
        _userMonitorTimer == null) {
      _startUserMonitor(_currentUser!.uid);
    }
  }

  // --- READING SESSION (feeds the dashboard reading statistics) -------------
  //
  // The app keeps no reading history anywhere else, so the dashboard's "read
  // today / average / pages / streak" figures are produced here and nowhere.
  // Two gates keep the numbers honest:
  //
  //   * a document must be open (`_activePdfId`), and
  //   * the last interaction must be recent. Without the second gate, a PDF
  //     left open on a second monitor would bill the hours it sits untouched.
  //
  // Time is credited in fixed ticks rather than measured from a stopwatch, so
  // the total never claims more than the window the app was actually foreground
  // and in use.

  static const Duration _readingTickInterval = Duration(seconds: 30);

  /// How long after the last interaction a document still counts as being read.
  static const Duration _readingInteractionWindow = Duration(minutes: 2);

  /// Pending seconds are written once this much has accumulated, so a long
  /// reading session does not produce a transaction every tick.
  static const int _readingFlushThresholdSeconds = 120;

  Timer? _readingTicker;
  DateTime? _lastReadingInteraction;

  /// Page the reading session last credited, and the document it belongs to,
  /// so switching files does not bill the jump from one document's last page to
  /// the next document's first page.
  int? _lastCreditedPage;
  String? _creditedPdfId;

  /// Marks the user as active in a document and starts the ticker on first use.
  void _noteReadingInteraction(String pdfId) {
    _lastReadingInteraction = DateTime.now();
    if (_creditedPdfId != pdfId) {
      _creditedPdfId = pdfId;
      _lastCreditedPage = null;
    }
    _readingTicker ??= Timer.periodic(_readingTickInterval, _onReadingTick);
  }

  void _onReadingTick(Timer timer) {
    if (_activePdfId == null) {
      // Document closed: stop billing and persist whatever is buffered.
      _suspendReadingSession();
      return;
    }

    final last = _lastReadingInteraction;
    if (last == null ||
        DateTime.now().difference(last) > _readingInteractionWindow) {
      // Idle. The ticker keeps running so an idle document does not have to be
      // re-armed on the next interaction, but it earns nothing.
      return;
    }

    ReadingStatsService().addFocusSeconds(_readingTickInterval.inSeconds);
    if (ReadingStatsService().pendingSeconds >= _readingFlushThresholdSeconds) {
      unawaited(ReadingStatsService().flush());
    }
  }

  /// Credits forward page movement. Backwards jumps and repeats count for
  /// nothing, which keeps the figure an approximation of pages covered rather
  /// than pages turned.
  void _creditPageAdvance(String pdfId, int? pageNumber) {
    if (pageNumber == null) return;
    if (pageNumber < 1) return;
    final previous = _lastCreditedPage;
    _lastCreditedPage = pageNumber;
    if (previous == null || pageNumber <= previous) return;
    ReadingStatsService().addPagesAdvanced(pageNumber - previous);
  }

  /// Stops the ticker and writes the buffer out. Called when the app leaves the
  /// foreground and on dispose, so the last seconds of a session are not lost.
  void _suspendReadingSession() {
    _readingTicker?.cancel();
    _readingTicker = null;
    _lastReadingInteraction = null;
    unawaited(ReadingStatsService().flush());
  }

  void updateHighlight(
    String pdfId,
    Highlight oldHighlight,
    Highlight newHighlight, {
    // Identifies the gesture this edit belongs to, or null for a discrete edit.
    // `_updateShapeTransform` calls this on every pointer frame, so without a
    // gesture the drag appends a history entry per frame and undo walks back
    // pixel by pixel instead of undoing the gesture. The caller owns the value,
    // because it is the only place that knows when a gesture starts and ends.
    int? gesture,
  }) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      final index = pdf.highlights.indexWhere((h) => h.id == oldHighlight.id);
      if (index != -1) {
        // Transform and style edits arrive as a copyWith of the original, so
        // without restamping here the element keeps its previous updatedAt and
        // its synced=true flag. The LWW diff would then classify the drag as a
        // no-op and never upload it, which is why moving a shape or a text
        // annotation never reached the other client.
        final stored = newHighlight.copyWith(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          isSynced: false,
        );
        pdf.highlights[index] = stored;
        if (isLockedDrawingForCurrentUser) {
          _markLockedLocalOnlyHighlight(pdf.fileHash, stored.id);
        }
        // سجل التعديل في سجل العمليات
        recordUpdate(
          pdfId: pdfId,
          itemId: oldHighlight.id,
          actionType: ActionTypes.ACTION_UPDATE_HIGHLIGHT,
          notify: false, // PATCH 3: Avoid double notify
          gesture: gesture,
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
        _notify(); // Single notify here
        // Stamped before the sync is asked for, so a pass that was already in
        // flight when the drag started defers instead of overwriting the shape
        // under the pointer.
        _lastAnnotationEditFrame = DateTime.now();
        markPdfDirty(pdfId);
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
    bool notify = true, // PATCH 3
    // Identifies the gesture this edit belongs to, or null for a discrete edit.
    // The frames of one gesture fold into a single history entry, which keeps
    // the entry that opened the gesture and its pre-gesture `oldState`. Appending
    // every frame turned one drag into hundreds of undo steps while copying the
    // whole path twice per frame.
    //
    // An identity, rather than a boolean, is what makes this correct: a flag
    // would fold the *first* frame of a new drag into whatever the previous entry
    // happened to be — a colour change on the same shape, say — and one undo
    // would then step over two separate operations.
    int? gesture,
  }) {
    // `_coalescingGesture` is only ever the gesture whose entry is currently on
    // top, so a mismatch means this frame opens a new entry rather than
    // extending an old one. The emptiness check is not redundant: undo can pop
    // the entry mid-gesture.
    if (gesture != null &&
        gesture == _coalescingGesture &&
        _actionHistory.isNotEmpty) {
      final last = _actionHistory.last;
      if (last.pdfId == pdfId &&
          last.itemId == itemId &&
          last.actionType == actionType) {
        _actionHistory[_actionHistory.length - 1] = ActionRecord(
          pdfId: pdfId,
          actionType: actionType,
          itemId: itemId,
          // The state before the gesture began, not before the last frame.
          oldState: last.oldState,
          // The state as of the latest frame.
          newState: newState,
        );
        _redoHistory.clear();
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
        if (notify) _notify();
        return;
      }
    }
    // A discrete edit passes null, which also ends any run: the next gesture must
    // not fold into it.
    _coalescingGesture = gesture;
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
    if (notify) _notify();
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

  PdfItem? _findPdfById(String pdfId) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isNotEmpty) return pdf;
    }
    return null;
  }

  Future<void> _initialize() async {
    await _loadState();

    // PHASE 1-2: Migration + Hydration from Isar (Canonical Source)
    await _migrateLegacyLibraryIfNeeded();
    await _hydrateClassesFromIsar();

    // PHASE 3A Safety Migration
    await _migrateAnnotationsIfNeeded();

    // Load tasks from Isar
    await _loadTasks();

    // STARTUP SECURITY GUARD: Verify account still exists and device is authorized
    if (_currentUser != null) {
      final currentFingerprint = await _hardwareService.getDeviceFingerprint();
      if (_currentUser!.primaryDeviceFingerprint != null &&
          _currentUser!.primaryDeviceFingerprint != currentFingerprint) {
        debugPrint(
          '🛡️ [Security] Startup Device Mismatch Detected for ${_currentUser!.username}',
        );
        _handleForceLogout('الحساب مسجل على جهاز آخر، ولا يمكن استخدامه هنا.');
      } else {
        _startUserMonitor(_currentUser!.uid);
      }
    }

    _initCompleter.complete();
    _warmUpMcpIfSelected();
  }

  void _warmUpMcpIfSelected() {
    if (_aiProvider != 'mcp') return;
    McpClientService.instance.isNodeAvailable.then((available) {
      if (available) {
        McpClientService.instance.start().catchError((e) {
          debugPrint('[Mcp] background start failed: $e');
        });
      }
    });
  }

  // Getters
  SyncService get syncService => _syncService;
  List<ClassItem> get classes => _classes;
  String? get activeClassId => _activeClassId;
  String? get activePdfId => _activePdfId;
  String? get secondaryPdfId => _secondaryPdfId;
  bool get isMobileOpen => _isMobileOpen;
  bool get showDevInfo => _showDevInfo;
  bool get isSidebarCollapsed => _isSidebarCollapsed;

  /// Which folder's announcements the main content area is showing, or null
  /// while the dashboard owns that area.
  UniversityFolder? get announcementsFolder => _announcementsFolder;

  /// On the home page the explorer is the only route to a file: the dashboard
  /// folder grid merely picks a class (`setActiveClass`), it never opens a
  /// document. So the sidebar is pinned open there, which is also what makes it
  /// safe to hide the viewer toolbar while no file is open.
  bool get isSidebarForcedOpen => _activePdfId == null;

  /// What the layout should actually render. Reading the raw
  /// [isSidebarCollapsed] would let a collapse made on the home page survive
  /// into it, where the sidebar has no way back open again.
  bool get isSidebarCollapsedEffective =>
      _isSidebarCollapsed && !isSidebarForcedOpen;

  bool get isDarkMode => _isDarkMode;
  Set<String> get intentionallyDeletedIds =>
      Set.unmodifiable(_intentionallyDeletedIds);
  bool get isSettingsOpen => _isSettingsOpen;
  String get aiProvider => _aiProvider;
  String get geminiModel => _geminiModel;
  String get groqModel => _groqModel;
  String get mcpModel => _mcpModel;
  String get geminiApiKey => _geminiApiKey;
  String get groqApiKey => _groqApiKey;

  /// The currently-active model name (whichever provider is selected).
  String get currentModel {
    if (_aiProvider == 'mcp') return _mcpModel;
    return _aiProvider == 'gemini' ? _geminiModel : _groqModel;
  }

  // Session / User getters
  AppUser? get currentUser => _currentUser;
  String? get currentSessionCode {
    final pdf = activePdf;
    if (pdf == null) return null;
    return _pdfSessionCodes[pdf.fileHash ?? ''];
  }

  bool get sessionLocked => _sessionLocked;
  bool get isLockedDrawingForCurrentUser {
    return sessionLocked && (_currentUser?.isStudent ?? true);
  }

  bool get sessionJoinLocked => _sessionJoinLocked;
  String? get forcedLogoutReason => _forcedLogoutReason;
  bool get isGlobalLogout => _isGlobalLogout;
  bool get isKicked => _isKicked;

  void _markLockedLocalOnlyHighlight(String? fileHash, String highlightId) {
    if (fileHash == null) return;
    _lockedLocalOnlyHighlightIds
        .putIfAbsent(fileHash, () => <String>{})
        .add(highlightId);
  }

  void _clearLockedLocalOnlyHighlight(String? fileHash, String highlightId) {
    if (fileHash == null) return;
    final ids = _lockedLocalOnlyHighlightIds[fileHash];
    if (ids == null) return;
    ids.remove(highlightId);
    if (ids.isEmpty) {
      _lockedLocalOnlyHighlightIds.remove(fileHash);
    }
  }

  void _purgeLockedLocalOnlyHighlightsForPdf(PdfItem pdf) {
    final fileHash = pdf.fileHash;
    if (fileHash == null) return;
    final ids = _lockedLocalOnlyHighlightIds[fileHash];
    if (ids == null || ids.isEmpty) return;

    pdf.highlights.removeWhere((h) => ids.contains(h.id));
    _actionHistory.removeWhere(
      (a) => a.pdfId == pdf.id && ids.contains(a.itemId),
    );
    _redoHistory.removeWhere(
      (a) => a.pdfId == pdf.id && ids.contains(a.itemId),
    );
    _locallyDeletedIds[fileHash]?.removeAll(ids);
    _lockedLocalOnlyHighlightIds.remove(fileHash);
  }

  // ─── OPTIMISTIC UI / SILENT ACCOUNT VERIFICATION ───────────────────────────
  Future<void> verifyAccountStatusSilently(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? _currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final isActive = doc.data()?['isActive'] ?? true; // fallback to true

      if (!doc.exists || isActive == false) {
        debugPrint(
          '🚫 Background Verification Guard: Account invalid or suspended.',
        );
        await FirebaseAuth.instance.signOut();
        _currentUser = null;
        await _saveState();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("تم تسجيل الخروج. الحساب غير موجود أو تم إيقافه."),
              backgroundColor: Colors.red,
            ),
          );
          // Navigate back to LoginScreen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint("Silent verification failed: \$e");
    }
  }

  void clearForcedLogoutReason() {
    _forcedLogoutReason = null;
    _isGlobalLogout = false;
    _isKicked = false;
    _notify();
  }

  void _startUserMonitor(String uid) {
    _userMonitorTimer?.cancel();

    // Initial check
    _syncService.checkUserExists(uid).then((exists) {
      if (!exists) {
        _handleForceLogout('تم حذف حسابك من النظام. يرجى تسجيل الدخول مجدداً.');
      }
    });

    // Patch 1: 5-minute Polling instead of snapshots
    _userMonitorTimer = Timer.periodic(const Duration(minutes: 5), (
      timer,
    ) async {
      final exists = await _syncService.checkUserExists(uid);
      if (!exists) {
        timer.cancel();
        _handleForceLogout(
          'تم حذف حسابك من النظام (تم التأكد عبر الفحص الدوري).',
        );
      }
    });
  }

  void _stopUserMonitor() {
    _userMonitorTimer?.cancel();
    _userMonitorTimer = null;
  }

  void toggleSettings(bool open) {
    _isSettingsOpen = open;
    _notify();
  }

  void setCurrentUser(AppUser user) {
    _currentUser = user;
    _startUserMonitor(user.uid);
    _saveState(); // PERSISTENT LOGIN: Save user on set

    if (user.isLecturer) {
      _preloadLecturerSessions(user.username);
    }

    // The timetable is read by everyone, so the subscription starts for every
    // role — but the service's copy of the user is what decides who may write, so
    // it has to be handed over here rather than at construction.
    _beginTimetableSession(user);

    _notify();
  }

  /// Resolves the live Firebase session once Auth has finished restoring.
  ///
  /// [FirebaseAuth.currentUser] is null while a persisted token is still being
  /// read back from disk, so reading it straight away would throw away a
  /// perfectly valid session. [FirebaseAuth.authStateChanges] deliberately does
  /// not emit until the initial state is known, which is what makes the value
  /// trustworthy. Returns null when there is no session and also when the
  /// restore never completes, and callers treat both the same way.
  static Future<User?> _awaitInitialAuthUser() async {
    try {
      final restored = FirebaseAuth.instance.currentUser;
      if (restored != null) return restored;
      return await FirebaseAuth.instance.authStateChanges().first.timeout(
        const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('⚠️ Auth state restore failed: $e');
      return null;
    }
  }

  Future<void> _preloadLecturerSessions(String username) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sync_sessions')
          .where('createdBy', isEqualTo: username)
          .get();

      bool updated = false;
      for (var doc in snap.docs) {
        final hash = doc.data()['fileHash'] as String?;
        if (hash != null) {
          if (_pdfSessionCodes[hash] != doc.id) {
            _pdfSessionCodes[hash] = doc.id;
            updated = true;
          }
        }
      }
      if (updated) {
        _saveState();
        _notify();
        debugPrint(
          'DEBUG: Pre-loaded ${snap.docs.length} active sessions upon login.',
        );
      }
    } catch (e) {
      debugPrint('DEBUG: Error pre-loading lecturer sessions: $e');
    }
  }

  void setSessionCode(String? code) {
    final pdf = activePdf;
    if (pdf != null && pdf.fileHash != null) {
      final hash = pdf.fileHash!;
      // A different code for the same file is a different session, so any sync
      // still running for the previous one must not be allowed to write.
      if (code != _pdfSessionCodes[hash]) _syncGeneration++;
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

      // Start mutation listener when session is set AND a PDF is already open
      if (code != null && pdf.fileHash != null) {
        if (_lastMutationListenerHash != pdf.fileHash) {
          _lastMutationListenerHash = pdf.fileHash;
          debugPrint(
            '🎧 [SESSION] Starting mutation listener after session code set',
          );
          _syncService.listenToMutations(pdf.fileHash!, pdf.id, this);
        }
      }

      _saveState();
      _notify();

      // Attaching a code is the moment remote annotations become reachable, so
      // reconcile now instead of waiting for the first local edit.
      if (code != null && _currentUser != null) {
        unawaited(performBidirectionalSync(silent: true));
      }
    }
  }

  // ─── PHASE 13: MASTER BUNDLE INTEGRATION ──────────────────────────────────
  Map<String, dynamic> linkMasterBundle(List<dynamic> bundle) {
    int successCount = 0;
    List<String> missingFiles = [];

    // Collect all local PDF hashes for quick lookup
    final localHashes = <String>{};
    for (var cls in _classes) {
      for (var pdf in cls.pdfs) {
        if (pdf.fileHash != null) {
          localHashes.add(pdf.fileHash!);
        }
      }
    }

    for (var item in bundle) {
      if (item is Map) {
        final hash = item['hash']?.toString();
        final sessionCode = item['sessionCode']?.toString();
        final name = item['name']?.toString() ?? 'ملف غير معروف';

        if (hash != null && sessionCode != null) {
          if (localHashes.contains(hash)) {
            // Passive Link
            _pdfSessionCodes[hash] = sessionCode;
            successCount++;
          } else {
            // Missing File
            missingFiles.add(name);
          }
        }
      }
    }

    _saveState();
    _notify();

    return {'successCount': successCount, 'missingFiles': missingFiles};
  }

  void logout() {
    _currentUser = null;
    _pdfSessionCodes.clear();
    _sessionLocked = false;
    _sessionJoinLocked = false;
    _stopKickListener();
    _stopUserMonitor();
    _saveState();
    _updateImageCacheGovernance();
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
    if (_currentUser?.username == 'abn') {
      debugPrint('DEBUG: Joker abn detected. Security bypass active.');
      return;
    }
    final uid = _currentUser?.uid;
    if (uid == null) return;

    _kickSub?.cancel();
    // Phase 11.6: Race Condition Guard (Delayed Start)
    _kickSub =
        Stream.fromFuture(
          Future.delayed(const Duration(milliseconds: 500)),
        ).asyncExpand((_) => _syncService.watchSessionSecurity(code)).listen((
          state,
        ) {
          if (state['exists'] == false) {
            _handleForceLogout('تم إغلاق الجلسة من قبل المالك');
            return;
          }

          // 0. Owner Immunity Guard (by Username)
          final String? ownerId = state['createdBy']; // Session owner Username
          if (ownerId != null && ownerId == _currentUser?.username) {
            debugPrint(
              'DEBUG: User is Session Owner. Security Immunity Granted.',
            );
            return;
          }

          // 1. Kick Check (by UID)
          final kickedUsernames =
              state['kicked_usernames'] as List<dynamic>? ?? [];

          if (kickedUsernames.contains(_currentUser?.username)) {
            _handleForceLogout('لقد تم حظرك من هذه الجلسة');
            return;
          }

          // 2. Lock Check (isDrawingEnabled logic)
          final locked = state['isLocked'] as bool;
          if (locked != _sessionLocked) {
            _sessionLocked = locked;
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
            _handleForceLogout(
              'لقد تمت إزالتك من قائمة المشاركين في هذا الدرس',
            );
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

    // Cleanup active session
    final pdf = activePdf;
    if (pdf != null && pdf.fileHash != null) {
      _pdfSessionCodes.remove(pdf.fileHash);
    }
    _sessionLocked = false;
    _sessionJoinLocked = false;
    _stopKickListener();
    _stopUserMonitor(); // Also stop monitoring the deleted account

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
    final syncedHighlights = pdf.highlights
        .where((h) => h.isSynced == true)
        .toList();
    final syncedComments = pdf.comments
        .where((c) => c.isSynced == true)
        .toList();

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

    if (pdf.fileHash != null) {
      _lockedLocalOnlyHighlightIds.remove(pdf.fileHash);
    }

    _notify();
  }

  /// Updates local annotations for a PDF from Firestore sync data based on global fileHash.
  /// Uses MERGE strategy (not replace) to combine local + remote annotations in real-time.
  void syncFromFirestore(String fileHash, List<dynamic> remoteData) {
    bool changed = false;
    for (var i = 0; i < _classes.length; i++) {
      for (var j = 0; j < _classes[i].pdfs.length; j++) {
        final pdf = _classes[i].pdfs[j];
        if (pdf.fileHash == fileHash) {
          final serverIds = <String>{};
          // MERGE strategy: Start with existing local annotations
          final mergedHighlights = Map<String, Highlight>.fromIterable(
            pdf.highlights,
            key: (h) => h.id,
          );
          final mergedComments = Map<String, PdfComment>.fromIterable(
            pdf.comments,
            key: (c) => c.id,
          );

          // Process remote data and merge it in
          for (var item in remoteData) {
            if (item is Map) {
              final data = Map<String, dynamic>.from(item);
              final kind = data['kind'];
              final id = data['id'] as String?;
              if (id != null) {
                serverIds.add(id);
              }
              if (id != null && _intentionallyDeletedIds.contains(id)) {
                continue;
              }

              if (kind == 'highlight' && id != null) {
                final highlight = Highlight.fromJson(data);
                // MERGE + UPDATE: Always assign (add new OR update existing)
                final isNew = !mergedHighlights.containsKey(id);
                mergedHighlights[id] = highlight;
                changed = true;
                if (isNew) {
                  debugPrint('✨ [RealTime] NEW highlight from peer: $id');
                } else {
                  debugPrint('🔄 [RealTime] UPDATED highlight from peer: $id');
                }
              } else if (kind == 'comment' && id != null) {
                final comment = PdfComment.fromJson(data);
                // MERGE + UPDATE: Always assign (add new OR update existing)
                final isNew = !mergedComments.containsKey(id);
                mergedComments[id] = comment;
                changed = true;
                if (isNew) {
                  debugPrint('💬 [RealTime] NEW comment from peer: $id');
                } else {
                  debugPrint('✏️ [RealTime] UPDATED comment from peer: $id');
                }
              }
            }
          }

          final targetPdf = pdf.copyWith(
            highlights: mergedHighlights.values.toList(),
            comments: mergedComments.values.toList(),
          );

          // Orphan cleanup: ONLY if server has data (don't wipe on empty sync)
          if (serverIds.isNotEmpty) {
            final beforeH = targetPdf.highlights.length;
            targetPdf.highlights.removeWhere((h) => !serverIds.contains(h.id));
            if (targetPdf.highlights.length != beforeH) changed = true;

            final beforeC = targetPdf.comments.length;
            targetPdf.comments.removeWhere((c) => !serverIds.contains(c.id));
            if (targetPdf.comments.length != beforeC) changed = true;
          }

          // Update PDF with merged annotations
          if (changed) {
            _classes[i].pdfs[j] = targetPdf;
          }
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

  void clearDeletionIntent(String pdfId) {
    _intentionallyDeletedIds.clear();
  }

  PdfItem? get activePdf {
    if (_ephemeralPdf != null && _activePdfId == _ephemeralPdf!.id) {
      return _ephemeralPdf;
    }
    final cls = _activeClass();
    if (cls == null || _activePdfId == null) return null;
    for (final pdf in cls.pdfs) {
      if (pdf.id == _activePdfId) return pdf;
    }
    if (_isSplitMode) {
      return _findPdfById(_activePdfId!);
    }
    return null;
  }

  PdfItem? get secondaryPdf {
    if (!_isSplitMode || _secondaryPdfId == null) return null;
    if (_secondaryPdfId == _activePdfId) return null;
    return _findPdfById(_secondaryPdfId!);
  }

  bool get isSplitMode => _isSplitMode;

  ClassItem? _activeClass() {
    if (_activeClassId == null) return null;
    try {
      return _classes.firstWhere((c) => c.id == _activeClassId);
    } catch (_) {
      return null;
    }
  }

  String? _fallbackSecondaryPdfId({String? primaryPdfId}) {
    final cls = _activeClass();
    if (cls == null) return null;
    for (final pdf in cls.pdfs) {
      if (pdf.id != primaryPdfId) return pdf.id;
    }
    return null;
  }

  void _normalizeSplitSelection() {
    if (!_isSplitMode) {
      _secondaryPdfId = null;
      return;
    }

    final primaryId = _activePdfId;
    if (primaryId == null) {
      _secondaryPdfId = null;
      _isSplitMode = false;
      return;
    }

    if (_secondaryPdfId == null || _secondaryPdfId == primaryId) {
      _secondaryPdfId = _fallbackSecondaryPdfId(primaryPdfId: primaryId);
    } else {
      final secondary = _findPdfById(_secondaryPdfId!);
      if (secondary == null || secondary.id == primaryId) {
        _secondaryPdfId = _fallbackSecondaryPdfId(primaryPdfId: primaryId);
      }
    }

    if (_secondaryPdfId == null) {
      _isSplitMode = false;
    }
  }

  void toggleSplitMode() {
    if (_isSplitMode) {
      _isSplitMode = false;
      _secondaryPdfId = null;
    } else {
      _isSplitMode = true;
      _secondaryPdfId = _fallbackSecondaryPdfId(primaryPdfId: _activePdfId);
      if (_secondaryPdfId == null) {
        _isSplitMode = false;
      }
    }

    _saveState();
    _notify();
  }

  void setSecondaryPdf(String? pdfId) {
    if (pdfId == null) {
      _secondaryPdfId = null;
      _isSplitMode = false;
      _saveState();
      _notify();
      return;
    }

    final resolved = _findPdfById(pdfId);
    if (resolved == null || resolved.id == _activePdfId) return;

    _secondaryPdfId = resolved.id;
    _isSplitMode = true;
    _normalizeSplitSelection();
    _saveState();
    _notify();
  }

  // Constants for SharedPreferences
  static const String _prefsKeyClasses = 'studyflowpdf_classes';
  static const String _prefsKeyActiveClass = 'studyflowpdf_active_class';
  static const String _prefsKeyDarkMode = 'studyflowpdf_dark_mode';
  static const String _prefsKeyAiProvider = 'studyflowpdf_ai_provider';
  static const String _prefsKeyGeminiModel = 'studyflowpdf_gemini_model';
  static const String _prefsKeyGroqModel = 'studyflowpdf_groq_model';
  static const String _prefsKeyMcpModel = 'studyflowpdf_mcp_model';
  static const String _prefsKeyGeminiApiKey = 'studyflowpdf_gemini_api_key';
  static const String _prefsKeyGroqApiKey = 'studyflowpdf_groq_api_key';
  static const String _prefsKeyPdfSessionCodes = 'studyflowpdf_session_codes';
  static const String _prefsKeyUser = 'studyflowpdf_user';
  static const String _prefsKeyAnnotations = 'studyflowpdf_annotations_blob';
  static const String _prefsKeyAnnotationsMigrated =
      'annotations_blob_migrated_v1';
  static const String _prefsKeyLibraryMigrated =
      'studyflowpdf_library_migrated_v2';
  static const String _prefsKeySplitMode = 'studyflowpdf_split_mode';
  static const String _prefsKeySecondaryPdf = 'studyflowpdf_secondary_pdf';

  Future<void> _loadState() async {
    try {
      // Windows-specific file migration for SharedPreferences
      if (Platform.isWindows) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final companyDir = supportDir.parent;
          final oldSupportDir = Directory(p.join(companyDir.path, 'pdfreader'));
          final oldPrefsFile = File(
            p.join(oldSupportDir.path, 'shared_preferences.json'),
          );
          final newPrefsFile = File(
            p.join(supportDir.path, 'shared_preferences.json'),
          );

          if (await oldPrefsFile.exists() && !await newPrefsFile.exists()) {
            await supportDir.create(recursive: true);
            await oldPrefsFile.copy(newPrefsFile.path);
            debugPrint(
              '✅ Migrated SharedPreferences file from pdfreader to StudyFlowPdf',
            );
          }
        } catch (e) {
          debugPrint('⚠️ SharedPreferences file migration failed: $e');
        }
      }
      final prefs = await SharedPreferences.getInstance();

      // MIGRATION: from pdfreader_ to studyflowpdf_
      final legacyKeys = {
        'pdfreader_classes': _prefsKeyClasses,
        'pdfreader_active_class': _prefsKeyActiveClass,
        'pdfreader_dark_mode': _prefsKeyDarkMode,
        'pdfreader_ai_provider': _prefsKeyAiProvider,
        'pdfreader_gemini_model': _prefsKeyGeminiModel,
        'pdfreader_groq_model': _prefsKeyGroqModel,
        'pdfreader_gemini_api_key': _prefsKeyGeminiApiKey,
        'pdfreader_groq_api_key': _prefsKeyGroqApiKey,
        'pdfreader_session_codes': _prefsKeyPdfSessionCodes,
        'pdfreader_user': _prefsKeyUser,
      };

      for (var entry in legacyKeys.entries) {
        if (prefs.containsKey(entry.key) && !prefs.containsKey(entry.value)) {
          final val = prefs.get(entry.key);
          if (val is String)
            await prefs.setString(entry.value, val);
          else if (val is bool)
            await prefs.setBool(entry.value, val);
          else if (val is int)
            await prefs.setInt(entry.value, val);
        }
      }

      // Load User Session (Auto-Login)
      final userJson = prefs.getString(_prefsKeyUser);
      if (userJson != null) {
        try {
          final restored = AppUser.fromJson(jsonDecode(userJson));
          // SharedPreferences holds a cached profile, it is not proof of an
          // identity. Every rule keys off request.auth, so a cached user with
          // no live Firebase session fails on the very first read with
          // permission-denied. The cached profile is therefore kept only when
          // a live session for exactly the same uid exists.
          final live = await _awaitInitialAuthUser();
          if (live == null || live.uid != restored.uid) {
            debugPrint(
              '⚠️ Auto-Login: no live Firebase session for '
              '${restored.username} (cached=${restored.uid}, '
              'live=${live?.uid}). Clearing cached session.',
            );
            await prefs.remove(_prefsKeyUser);
          } else {
            _currentUser = restored;
            // Reached without [setCurrentUser], which is the only other caller
            // of the handover: this path adopts a session that was already
            // persisted, so it has to perform it itself. Without it the stream is
            // never subscribed — the admin's `+` opened a dialog that spun for
            // ever — and the service kept no user, so its very first write failed
            // with "يجب تسجيل الدخول أولاً" while the app was demonstrably signed
            // in. One method for both paths is what stops them drifting apart.
            _beginTimetableSession(restored);
            debugPrint('✅ Auto-Login: Loaded user ${_currentUser?.username}');
          }
        } catch (e) {
          debugPrint('⚠️ Error decoding user session: $e');
        }
      }

      // ── PHASE 1: LIBRARY LOADING ──────────────────────────────────────────
      // Note: We no longer load _classes directly from SharedPreferences.
      // Migration and Hydration happen in _initialize() after this returns.

      _activeClassId = prefs.getString(_prefsKeyActiveClass);
      _activePdfId = null; // Reset on load, hydration will restore if needed
      _secondaryPdfId = prefs.getString(_prefsKeySecondaryPdf);
      _isSplitMode = prefs.getBool(_prefsKeySplitMode) ?? false;

      // Load dark mode preference
      _isDarkMode = prefs.getBool(_prefsKeyDarkMode) ?? true;
      _aiProvider = prefs.getString(_prefsKeyAiProvider) ?? 'groq';
      _geminiModel =
          prefs.getString(_prefsKeyGeminiModel) ?? 'gemini-2.5-flash';
      _groqModel =
          prefs.getString(_prefsKeyGroqModel) ?? 'llama-3.3-70b-versatile';
      _mcpModel = prefs.getString(_prefsKeyMcpModel) ?? 'gemini-2.5 (personal)';
      _geminiApiKey = prefs.getString(_prefsKeyGeminiApiKey) ?? '';
      _groqApiKey = prefs.getString(_prefsKeyGroqApiKey) ?? '';

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

  // ── PHASE 1: NEW CANONICAL PERSISTENCE LOGIC ────────────────────────────

  Future<void> _migrateLegacyLibraryIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKeyLibraryMigrated) == true) {
        debugPrint('ℹ️ Legacy library migration already completed. Skipping.');
        return;
      }

      final classesJson = prefs.getString(_prefsKeyClasses);

      if (classesJson != null && classesJson.isNotEmpty) {
        final List<dynamic> legacyData = jsonDecode(classesJson);

        final fileManager = FileManagerService();
        await fileManager.migrateFromLegacyPrefs(legacyData);

        await prefs.setBool(_prefsKeyLibraryMigrated, true);
        await prefs.remove('pdfreader_classes');

        // Clear legacy key to prevent double migration
        await prefs.remove(_prefsKeyClasses);
        debugPrint(
          '🗑️ Cleared legacy classes payload and marked library migration complete.',
        );
      }
    } catch (e) {
      debugPrint('❌ Error during legacy migration: $e');
    }
  }

  Future<void> _hydrateClassesFromIsar() async {
    try {
      final fileManager = FileManagerService();
      if (!fileManager.isInitialized) await fileManager.init();

      final folders = await fileManager.getFoldersOrdered();
      final allPdfs = await fileManager.getAllDocuments();

      // Rebuild _classes projection
      final List<ClassItem> tempClasses = [];

      for (final folder in folders) {
        final pdfs = allPdfs
            .where(
              (p) =>
                  p.classId == folder.uuid ||
                  (folder.uuid == 'quick_access' && p.classId == null),
            )
            .toList();

        // Map Isar PdfDocument to UI PdfItem
        final List<PdfItem> pdfItems = [];

        for (var p in pdfs) {
          // 💧 SAFE BACKFILL: Ensure every record has a hash and page count
          String? currentHash = p.fileHash;
          int currentTotalPages = p.totalPages;
          bool needsUpdate = false;

          if (currentHash == null || currentHash.isEmpty) {
            try {
              final pathToHash = p.originalPath;
              if (await File(pathToHash).exists()) {
                currentHash = await FileHashService.calculateFileHash(
                  pathToHash,
                );
                p.fileHash = currentHash;
                needsUpdate = true;
              }
            } catch (e) {
              debugPrint('⚠️ [Hydration] Failed to backfill hash: $e');
            }
          }

          if (currentTotalPages == 0) {
            try {
              if (await File(p.originalPath).exists()) {
                final pdfDoc = await pdfrx.PdfDocument.openFile(p.originalPath);
                currentTotalPages = pdfDoc.pages.length;
                await pdfDoc.dispose();
                p.totalPages = currentTotalPages;
                needsUpdate = true;
              }
            } catch (e) {
              debugPrint('⚠️ [Hydration] Failed to backfill pages: $e');
            }
          }

          if (needsUpdate) {
            await fileManager.isar.writeTxn(() async {
              await fileManager.isar.pdfDocuments.put(p);
            });
          }

          // UI Projection: Prioritize originalDisplayName for the name
          final displayName =
              p.originalDisplayName ??
              p.originalPath.split(Platform.pathSeparator).last;

          final item = PdfItem(
            id: p.uuid,
            name: displayName,
            path: p.workingPath ?? p.originalPath,
            originalPath: p.originalPath,
            fileHash: currentHash,
            pageCount: currentTotalPages,
            lastPage: p.lastPage,
            lastModified: p.workingModifiedAt?.millisecondsSinceEpoch,
            scrollTop: p.lastScroll,
          );

          // PHASE 3A: Load annotations from Isar for THIS document.
          // Keep hydration resilient: one broken PDF must not hide sidebar folders.
          List<IsarHighlight> iHighlights = const [];
          List<IsarComment> iComments = const [];
          List<IsarBookmark> iBookmarks = const [];
          try {
            iHighlights = await fileManager.loadHighlightsForPdf(p.uuid);
            iComments = await fileManager.loadCommentsForPdf(p.uuid);
            iBookmarks = await fileManager.loadBookmarksForPdf(p.uuid);
          } catch (e) {
            debugPrint(
              '⚠️ [Hydration] Annotation load failed for PDF ${p.uuid}: $e',
            );
          }

          item.highlights.addAll(
            iHighlights.map(
              (ih) => Highlight(
                id: ih.uuid,
                path: ih.path
                    .map((ip) => Offset(ip.dx ?? 0, ip.dy ?? 0))
                    .toList(),
                color: Color(ih.color),
                page: ih.page,
                strokeWidth: ih.strokeWidth,
                type: HighlightType.values.firstWhere(
                  (e) => e.toString() == ih.type,
                  orElse: () => HighlightType.pen,
                ),
                isSynced: ih.isSynced,
                updatedAt: ih.updatedAt,
                backgroundColor: ih.backgroundColor,
                rects: ih.rects
                    ?.map(
                      (ir) => Rect.fromLTRB(
                        ir.left ?? 0,
                        ir.top ?? 0,
                        ir.right ?? 0,
                        ir.bottom ?? 0,
                      ),
                    )
                    .toList(),
              ),
            ),
          );

          item.comments.addAll(
            iComments.map(
              (ic) => PdfComment(
                id: ic.uuid,
                page: ic.page,
                position: Offset(ic.position?.dx ?? 0, ic.position?.dy ?? 0),
                content: ic.content,
                attachedMediaUrl: ic.attachedMediaUrl.isEmpty
                    ? null
                    : ic.attachedMediaUrl,
                date: ic.date,
                createdBy: ic.createdBy.isEmpty ? null : ic.createdBy,
                color: Color(ic.color),
                fontSize: ic.fontSize,
                isBold: ic.isBold,
                isLatex: ic.isLatex,
                fontFamily: ic.fontFamily,
                showBorder: ic.showBorder,
                borderColor: Color(ic.borderColor),
                bgColor: Color(ic.bgColor),
                mediaHeight: ic.mediaHeight,
                isSynced: ic.isSynced,
                updatedAt: ic.updatedAt,
              ),
            ),
          );

          item.bookmarks.addAll(
            iBookmarks.map(
              (ib) => PdfBookmark(id: ib.uuid, page: ib.page, name: ib.name),
            ),
          );

          pdfItems.add(item);
        }

        // Reorder pdfItems based on folder.pdfIds if available
        if (folder.pdfIds.isNotEmpty) {
          pdfItems.sort((a, b) {
            final idxA = folder.pdfIds.indexOf(a.id);
            final idxB = folder.pdfIds.indexOf(b.id);
            if (idxA == -1 && idxB == -1) return 0;
            if (idxA == -1) return 1;
            if (idxB == -1) return -1;
            return idxA.compareTo(idxB);
          });
        }

        tempClasses.add(
          ClassItem(
            id: folder.uuid,
            name: folder.name,
            pdfs: pdfItems,
            lastActivePdfId: folder.lastActivePdfId,
          ),
        );
      }

      _classes = tempClasses;
      debugPrint('💧 Hydrated ${_classes.length} classes from Isar.');
      _notify();
    } catch (e, stack) {
      debugPrint('❌ Error hydrating classes from Isar: $e\n$stack');
    }
  }

  Future<void> _migrateAnnotationsIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isMigrated = prefs.getBool(_prefsKeyAnnotationsMigrated) ?? false;
      if (isMigrated) return;

      final blob = prefs.getString(_prefsKeyAnnotations);
      if (blob == null || blob.isEmpty) return;

      final Map<String, dynamic> blobData = jsonDecode(blob);
      final fileManager = FileManagerService();

      final success = await fileManager.migrateAnnotationsFromBlob(blobData);
      if (success) {
        await prefs.setBool(_prefsKeyAnnotationsMigrated, true);
        debugPrint(
          '🛡️ Phase 3A: Annotation migration successful. Marker set.',
        );
        // Re-hydrate to ensure UI has latest Isar data
        await _hydrateClassesFromIsar();
      }
    } catch (e) {
      debugPrint('⚠️ Annotation migration failed: $e');
    }
  }

  /*
  Future<void> _loadAnnotations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blob = prefs.getString(_prefsKeyAnnotations);
      if (blob == null || blob.isEmpty) return;

      final Map<String, dynamic> data = jsonDecode(blob);
      int restoredCount = 0;

      for (var cls in _classes) {
        for (var pdf in cls.pdfs) {
          if (data.containsKey(pdf.id)) {
            final pdfData = data[pdf.id] as Map<String, dynamic>;
            
            // Highlights
            if (pdfData.containsKey('highlights')) {
              pdf.highlights.clear();
              pdf.highlights.addAll(
                (pdfData['highlights'] as List).map((h) => Highlight.fromJson(h)),
              );
            }
            
            // Comments
            if (pdfData.containsKey('comments')) {
              pdf.comments.clear();
              pdf.comments.addAll(
                (pdfData['comments'] as List).map((c) => PdfComment.fromJson(c)),
              );
            }
            
            // Bookmarks
            if (pdfData.containsKey('bookmarks')) {
              pdf.bookmarks.clear();
              pdf.bookmarks.addAll(
                (pdfData['bookmarks'] as List).map((b) => PdfBookmark.fromJson(b)),
              );
            }
            restoredCount++;
          }
        }
      }
      debugPrint('🛡️ Transitional Safety: Restored annotations for $restoredCount documents.');
      _notify();
    } catch (e) {
      debugPrint('⚠️ Error restoring annotations: $e');
    }
  }

  Future<void> _saveAnnotations(SharedPreferences prefs) async {
    try {
      final Map<String, dynamic> blob = {};
      
      for (final cls in _classes) {
        for (final pdf in cls.pdfs) {
          // Only save if there's actually something to save to keep blob lightweight
          if (pdf.highlights.isNotEmpty || pdf.comments.isNotEmpty || pdf.bookmarks.isNotEmpty) {
            blob[pdf.id] = {
              'highlights': pdf.highlights.map((h) => h.toJson()).toList(),
              'comments': pdf.comments.map((c) => c.toJson()).toList(),
              'bookmarks': pdf.bookmarks.map((b) => b.toJson()).toList(),
            };
          }
        }
      }

      if (blob.isNotEmpty) {
        await prefs.setString(_prefsKeyAnnotations, jsonEncode(blob));
      }
    } catch (e) {
      debugPrint('⚠️ Error saving transitional annotations: $e');
    }
  }
*/

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
              if (RegExp(r'_studyflowpdf_temp_\d+\.pdf$').hasMatch(path)) {
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
    if (_isSaving) {
      _needsSave = true;
      return;
    }

    _isSaving = true;
    _needsSave = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final activeClassSnapshot = _activeClassId;

      if (activeClassSnapshot != null) {
        await prefs.setString(_prefsKeyActiveClass, activeClassSnapshot);
      } else {
        await prefs.remove(_prefsKeyActiveClass);
      }

      if (_isSplitMode) {
        await prefs.setBool(_prefsKeySplitMode, true);
      } else {
        await prefs.remove(_prefsKeySplitMode);
      }

      if (_secondaryPdfId != null) {
        await prefs.setString(_prefsKeySecondaryPdf, _secondaryPdfId!);
      } else {
        await prefs.remove(_prefsKeySecondaryPdf);
      }

      await prefs.setString(
        _prefsKeyPdfSessionCodes,
        jsonEncode(_pdfSessionCodes),
      );

      if (_currentUser != null) {
        await prefs.setString(
          _prefsKeyUser,
          jsonEncode(_currentUser!.toJson()),
        );
      } else {
        await prefs.remove(_prefsKeyUser);
      }

      if (_dirtyPdfIds.isNotEmpty) {
        final idsToFlush = Set<String>.from(_dirtyPdfIds);
        _dirtyPdfIds.clear();
        debugPrint(
          '💾 [Isar Flush] Starting flush for ${idsToFlush.length} dirty PDFs...',
        );

        for (final pdfId in idsToFlush) {
          final pdf = _findPdfById(pdfId);
          if (pdf == null) continue;

          try {
            await _fileManager.saveHighlights(pdf.id, pdf.highlights);
            await _fileManager.saveComments(pdf.id, pdf.comments);
            await _fileManager.saveBookmarks(pdf.id, pdf.bookmarks);
          } catch (e) {
            debugPrint('❌ [Isar Flush] Failed for PDF: $pdfId - Error: $e');
            _dirtyPdfIds.add(pdfId);
          }
        }
        debugPrint(
          '✅ [Isar Flush] Completed flush for ${idsToFlush.length} PDFs.',
        );
      }
    } catch (e) {
      debugPrint('Error saving state: $e');
    } finally {
      _isSaving = false;
      if (_needsSave) {
        _saveState();
      }
    }
  }

  /// Writes the dirty documents to Isar, then — if an annotation edit is still
  /// inside the debounce window — pushes it to the server before returning.
  ///
  /// The viewer calls this when it is about to go away. Without the push, a
  /// shape dragged in the last second before quitting reached the disk but not
  /// the other client: the pending [performBidirectionalSync] was cancelled
  /// along with the viewer, so the edit only appeared on the next sync this
  /// device happened to run.
  Future<void> saveStateNow({String? pdfId}) async {
    if (pdfId != null && pdfId.isNotEmpty) {
      markPdfDirty(pdfId);
    }
    // Read before cancelling: after this the timer is gone and there is no way
    // to tell whether a sync was still owed.
    final hadPendingSync = _syncDebounce?.isActive ?? false;
    cancelDebouncedSync();
    await _saveState();
    if (!hadPendingSync) return;
    // The grace window exists to keep a *background* pass out of a live gesture.
    // A flush on close outranks it, and the pointer is not down any more, so the
    // stamp is cleared rather than waited out.
    _lastAnnotationEditFrame = null;
    await performBidirectionalSync();
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

  /// Hands the main content area to [folder]'s announcements, replacing the
  /// dashboard, and opens the live stream for them.
  ///
  /// Called from the university-library tree in the sidebar and nowhere else.
  /// That is what keeps the two halves of the explorer behaving differently:
  /// the local-files tree never reaches this, so opening one of its folders
  /// still only expands it.
  void showFolderAnnouncements(UniversityFolder folder) {
    if (_announcementsFolder?.id == folder.id) return;
    _announcementsFolder = folder;
    // Subscribed here rather than by the page. The page is rebuilt on every
    // provider notification, and a `snapshots()` call in a build would
    // re-subscribe on every frame — the same reason the timetable's stream is
    // owned here.
    _watchAnnouncements(folder.id);
    _notify();
  }

  /// Gives the main content area back to the dashboard and closes the stream.
  void closeFolderAnnouncements() {
    if (_announcementsFolder == null) return;
    _announcementsFolder = null;
    // The listener is not left running for a folder nobody is looking at: a
    // university-wide library is many folders, and one open listener per folder
    // visited in a session is a leak that only shows up as a bill.
    _disposeAnnouncements();
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
    if (provider != 'gemini' && provider != 'groq' && provider != 'mcp') {
      return;
    }
    _aiProvider = provider;
    if (provider == 'mcp') _warmUpMcpIfSelected();
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

  void setMcpModel(String model) {
    _mcpModel = model;
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
      await prefs.setString(_prefsKeyMcpModel, _mcpModel);
      await prefs.setString(_prefsKeyGeminiApiKey, _geminiApiKey);
      await prefs.setString(_prefsKeyGroqApiKey, _groqApiKey);
    });
  }

  // ─── AI FALLBACK & HIGH AVAILABILITY ───────────────────────────────────────

  /// Call once at the start of each user-initiated AI request.
  void resetFallbackAttempts() => _fallbackAttempts = 0;

  /// Rotates to the next available model / provider.
  /// Returns [true] if a fallback was applied and the caller should retry.
  /// Returns [false] if all options are exhausted.
  bool triggerAiFallback() {
    // Hard cap: max 5 total rotations per single request chain.
    if (_fallbackAttempts >= 5) {
      debugPrint('[AI Fallback] Hard cap reached. Giving up.');
      return false;
    }
    _fallbackAttempts++;

    if (_aiProvider == 'gemini') {
      final idx = geminiModelsList.indexOf(_geminiModel);
      if (idx != -1 && idx < geminiModelsList.length - 1) {
        // Rotate to next Gemini model
        final next = geminiModelsList[idx + 1];
        debugPrint('[AI Fallback] Gemini: $_geminiModel → $next');
        setGeminiModel(next);
        return true;
      }
      // All Gemini models exhausted → try Groq
      final groqKey = _effectiveKey(_groqApiKey, 'GROQ_API_KEY');
      if (groqKey.isNotEmpty) {
        debugPrint('[AI Fallback] Gemini exhausted → switching to Groq');
        setAiProvider('groq');
        setGroqModel(groqModelsList.first);
        return true;
      }
      // No Groq key → try MCP (personal account)
      debugPrint('[AI Fallback] Gemini exhausted → switching to MCP');
      setAiProvider('mcp');
      return true;
    } else if (_aiProvider == 'groq') {
      final idx = groqModelsList.indexOf(_groqModel);
      if (idx != -1 && idx < groqModelsList.length - 1) {
        // Rotate to next Groq model
        final next = groqModelsList[idx + 1];
        debugPrint('[AI Fallback] Groq: $_groqModel → $next');
        setGroqModel(next);
        return true;
      }
      // All Groq models exhausted → try Gemini
      final geminiKey = _effectiveKey(_geminiApiKey, 'GEMINI_API_KEY');
      if (geminiKey.isNotEmpty) {
        debugPrint('[AI Fallback] Groq exhausted → switching to Gemini');
        setAiProvider('gemini');
        setGeminiModel(geminiModelsList.first);
        return true;
      }
      // No Gemini key → try MCP (personal account)
      debugPrint('[AI Fallback] Groq exhausted → switching to MCP');
      setAiProvider('mcp');
      return true;
    } else if (_aiProvider == 'mcp') {
      // MCP has no model rotation; immediately fall to Gemini (preferred),
      // then Groq as a last resort.
      final geminiKey = _effectiveKey(_geminiApiKey, 'GEMINI_API_KEY');
      if (geminiKey.isNotEmpty) {
        debugPrint('[AI Fallback] MCP exhausted → switching to Gemini');
        setAiProvider('gemini');
        setGeminiModel(geminiModelsList.first);
        return true;
      }
      final groqKey = _effectiveKey(_groqApiKey, 'GROQ_API_KEY');
      if (groqKey.isNotEmpty) {
        debugPrint('[AI Fallback] MCP exhausted → switching to Groq');
        setAiProvider('groq');
        setGroqModel(groqModelsList.first);
        return true;
      }
    }

    debugPrint('[AI Fallback] No more options available.');
    return false;
  }

  /// Resolves a provider API key: settings-prefs value first, then the
  /// `.env` value (loaded by flutter_dotenv), then compile-time defines.
  String _effectiveKey(String prefsValue, String envKey) {
    final settingsKey = prefsValue.trim();
    if (settingsKey.isNotEmpty) return settingsKey;
    final dotenvKey = (dotenv.env[envKey] ?? '').trim();
    if (dotenvKey.isNotEmpty) return dotenvKey;
    return String.fromEnvironment(envKey).trim();
  }

  void setActiveClass(String id) {
    _activeClassId = id;
    _clearEphemeralPdf();

    // In split mode, preserve the current primary PDF and only refresh the secondary pane.
    final cls = _classes.firstWhere(
      (c) => c.id == id,
      orElse: () => _classes.isNotEmpty
          ? _classes.first
          : ClassItem(id: '', name: '', pdfs: []),
    );

    if (_isSplitMode && _activePdfId != null) {
      final hasPrimaryInClass = cls.pdfs.any((p) => p.id == _activePdfId);
      if (!hasPrimaryInClass) {
        _secondaryPdfId = cls.lastActivePdfId;
        if (_secondaryPdfId == null ||
            !cls.pdfs.any((p) => p.id == _secondaryPdfId)) {
          _secondaryPdfId = _fallbackSecondaryPdfId(primaryPdfId: _activePdfId);
        }
      }
    } else if (cls.id == id && cls.lastActivePdfId != null) {
      if (cls.pdfs.any((p) => p.id == cls.lastActivePdfId)) {
        _activePdfId = cls.lastActivePdfId;
      } else {
        _activePdfId = null;
      }
    } else {
      _activePdfId = null;
    }

    _normalizeSplitSelection();

    _saveState();
    _updateImageCacheGovernance();
    _notify();
  }

  void setActivePdf(String id) {
    // Switching to a real, folder-managed PDF: drop any ephemeral viewer.
    if (_ephemeralPdf != null && id != _ephemeralPdf!.id) {
      _clearEphemeralPdf();
    }
    // Reset listener hash when switching to a different PDF
    // so the listener restarts properly for the new file
    if (_activePdfId != id) {
      _lastMutationListenerHash = null;
      // A sync in flight belongs to the file being left behind.
      _syncGeneration++;
    }
    _activePdfId = id;
    _isMobileOpen = false;

    if (_isSplitMode) {
      if (_secondaryPdfId == id) {
        _secondaryPdfId = null;
      }
      _normalizeSplitSelection();
    } else {
      _secondaryPdfId = null;
    }

    // Update last active PDF for the class
    if (_activeClassId != null) {
      final index = _classes.indexWhere((c) => c.id == _activeClassId);
      if (index != -1) {
        _classes[index].lastActivePdfId = id;
        // Persist to Isar
        FileManagerService().updateFolderSelection(_activeClassId!, id);
      }
    }

    _saveState();
    _updateImageCacheGovernance();
    _notify();

    // 🚀 NEW: Wire up the structural mutation listener (Add/Delete Page sync)
    final pdfItem = activePdf;
    if (pdfItem != null && pdfItem.fileHash != null) {
      if (_lastMutationListenerHash != pdfItem.fileHash) {
        _lastMutationListenerHash = pdfItem.fileHash;
        debugPrint(
          '🎧 [APP_STATE] Starting mutation listener for hash: ${pdfItem.fileHash}',
        );
        _syncService.listenToMutations(pdfItem.fileHash!, id, this);
      }
    }

    // AUTO-JOIN: If lecturer opens a PDF, look for an active session immediately. (Removed 2.5s delay)
    final hash = activePdf?.fileHash;
    final username = _currentUser?.username;
    if (_currentUser?.isLecturer == true && hash != null && username != null) {
      _syncService.findExistingSession(username, hash).then((existingCode) {
        if (existingCode != null) {
          setSessionCode(existingCode);
          debugPrint(
            'DEBUG: Auto-joined existing session ($existingCode) for $hash.',
          );
        }
      });
    }

    // PHASE 13: STUDENT AUTO-CONNECT (Master Bundle)
    if (_currentUser?.role != 'lecturer' &&
        hash != null &&
        username != null &&
        _currentUser?.uid != null) {
      final savedCode = _pdfSessionCodes[hash];
      if (savedCode != null && savedCode.isNotEmpty) {
        // Automatically join the session right away to restore real-time connection
        _syncService
            .joinSession(
              code: savedCode,
              uid: _currentUser!.uid,
              username: username,
              studentFileHash: hash,
              studentPageCount: activePdf?.pageCount ?? 0,
            )
            .then((error) {
              if (error == null) {
                setSessionCode(savedCode);
                debugPrint(
                  'DEBUG: Passive Master Bundle Auto-Join Success ($savedCode) for $hash.',
                );
              } else {
                debugPrint('DEBUG: Passive Auto-Join Failed: $error');
              }
            });
      }
    }

    // UNIVERSITY LIBRARY AUTO-LINK: a library file carries its own sync code,
    // so neither the lecturer lookup (which filters on createdBy) nor the
    // student lookup (which needs a locally remembered code) can find it. This
    // resolves the code from the library metadata instead, so both roles join
    // the same session with no manual code entry.
    if (hash != null && hash.isNotEmpty) {
      _autoLinkLibrarySession(hash);
    } else {
      debugPrint(
        '📚 [LIBRARY] skip: the opened file has no content hash, so it cannot '
        'be matched against the university library.',
      );
    }
  }

  /// Joins the shared session for a university library file, creating the
  /// Firestore session document on first open. No-ops for PDFs that are not in
  /// the library, leaving the existing lecturer/student flows untouched.
  Future<void> _autoLinkLibrarySession(String hash) async {
    final user = _currentUser;
    if (user == null) {
      debugPrint('📚 [LIBRARY] skip: nobody is signed in (hash $hash).');
      return;
    }

    try {
      final service = UniversityService();
      // isReady also requires a universityId, so a user without one simply
      // falls through and the normal session flows apply.
      if (!service.isReady) await service.init(user);
      if (!service.isReady) {
        debugPrint(
          '📚 [LIBRARY] skip: university service is not ready for '
          '${user.username} (hash $hash).',
        );
        return;
      }

      final file = await service.findUniversityFileByHash(hash);
      if (file == null) {
        // Not a library file, which is the normal case for a local PDF.
        debugPrint(
          '📚 [LIBRARY] skip: $hash is not in the university library.',
        );
        return;
      }

      // syncCode is generated at upload time; the deterministic hash fallback
      // keeps pre-backfill files working with a stable code.
      final code =
          file.syncCode ?? LibrarySyncService.codeFromHash(file.fileHash);

      final ensured = await _syncService.ensureLibrarySession(
        code: code,
        fileHash: file.fileHash,
        fileName: file.name,
        pageCount: activePdf?.pageCount ?? file.totalPages ?? 0,
        uploaderUid: file.uploadedBy,
      );
      if (ensured == null) {
        debugPrint('📚 [LIBRARY] failed: session $code could not be opened.');
        return;
      }
      _libraryLinkedHashes.add(hash);

      // An explicit code already chosen for this PDF wins over the library one.
      final existing = _pdfSessionCodes[hash];
      if (existing != null) {
        if (existing != ensured) {
          debugPrint(
            '📚 [LIBRARY] $hash is on session $existing, so the library code '
            '$ensured was not applied.',
          );
        }
        return;
      }

      // A library session belongs to whoever uploaded the file, not to whoever
      // opens it, so a lecturer or admin gets no ownership immunity here. Every
      // opener has to register as a participant, otherwise the membership
      // check in the kick listener reads an empty participants list and drops
      // them the moment the file opens.
      final error = await _syncService.joinSession(
        code: ensured,
        uid: user.uid,
        username: user.username,
        studentFileHash: hash,
        studentPageCount: activePdf?.pageCount ?? file.totalPages ?? 0,
      );
      if (error == null) {
        setSessionCode(ensured);
        debugPrint('📚 [LIBRARY] Linked to session $ensured.');
      } else {
        debugPrint('📚 [LIBRARY] Auto-join failed for $ensured: $error');
      }
    } catch (e) {
      // Never block opening a PDF on this; manual code entry still works.
      debugPrint('📚 [LIBRARY] auto-link skipped: $e');
    }
  }

  void _updateImageCacheGovernance() {
    // 🚀 PERFORMANCE GOVERNANCE: Dynamic Image Cache Expansion
    // Dashboard only needs ~2MB. PDF Viewer needs ~50MB for smooth tiling.
    if (_activePdfId != null) {
      PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
      PaintingBinding.instance.imageCache.maximumSize = 25;
      debugPrint('🚀 ImageCache Expanded: 50MB (PDF Active)');
    } else {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      PaintingBinding.instance.imageCache.maximumSizeBytes = 2 * 1024 * 1024;
      PaintingBinding.instance.imageCache.maximumSize = 5;
      debugPrint('🛡️ ImageCache Throttled: 2MB (Dashboard Mode)');
    }
  }

  /// Student-facing manual join: Fetches session metadata by [code],
  /// searches local classes for the required fileHash, activates it,
  /// and connects to the sync session.
  Future<String?> joinSession(String code) async {
    if (code.isEmpty) return 'يرجى إدخال كود الدرس.';
    if (_currentUser == null) return 'يرجى تسجيل الدخول أولاً.';

    _isJoiningSession = true;
    _notify();

    try {
      // 1. Fetch session security/metadata to get the fileHash
      final sessionDoc = await _syncService
          .watchSessionSecurity(code.trim().toUpperCase())
          .first;

      if (sessionDoc['exists'] == false) {
        return 'الكود غير صحيح أو الجلسة منتهية.';
      }

      final targetHash = sessionDoc['fileHash'] as String?;
      // Note: pageCount might differ even if files are identical, so we'll use the local one
      final serverPageCount = (sessionDoc['pageCount'] as num?)?.toInt();

      if (targetHash == null) {
        return 'بيانات الجلسة غير مكتملة على الخادم.';
      }

      // 2. Search local classes for this hash (exact match first)
      PdfItem? matchingPdf;
      String? matchingClassId;

      for (final cls in _classes) {
        for (final p in cls.pdfs) {
          if (p.fileHash == targetHash) {
            matchingPdf = p;
            matchingClassId = cls.id;
            break;
          }
        }
        if (matchingPdf != null) break;
      }

      // 3. If exact hash not found, try fallback: match by filename + size
      if (matchingPdf == null) {
        debugPrint(
          '⚠️ [AppProvider] Exact hash not found in local PDFs. Trying fallback matching...',
        );

        // Extract expected filename and size from the remote session
        // (The fileHash is based on filename_size, so we need to find it locally)
        // For now, we'll search by comparing file size and name similarity
        for (final cls in _classes) {
          for (final p in cls.pdfs) {
            try {
              final localFile = File(p.path);
              if (await localFile.exists()) {
                final localMetadata = await FileHashService.getFileMetadata(
                  p.path,
                );

                // Try to match based on metadata similarity
                // Note: This is a heuristic; exact matching would require storing metadata in DB
                debugPrint(
                  '   - Checking local PDF: ${p.name} (Size: ${localMetadata['size']})',
                );

                // For now, accept the first matching PDF by name similarity or wait for better metadata
                // TODO: Ideally, store filename+size in the PDF document for reliable fallback matching
              }
            } catch (e) {
              debugPrint('   - Error checking local file: $e');
            }
          }
        }
      }

      if (matchingPdf == null) {
        return 'الملف المطلوب غير موجود في مجلداتك. يرجى التأكد من إضافة الملف أولاً.';
      }

      // 4. Activate the PDF
      setActiveClass(matchingClassId!);
      setActivePdf(matchingPdf.id);

      // 5. Use local page count (more reliable than server value which might differ)
      final localPageCount = matchingPdf.pageCount ?? serverPageCount ?? 0;

      if (localPageCount == 0) {
        debugPrint(
          '⚠️ [AppProvider] Warning: Could not determine page count for matched PDF',
        );
      }

      // 6. Perform the actual join with local page count
      final error = await _syncService.joinSession(
        code: code.trim().toUpperCase(),
        uid: _currentUser!.uid,
        username: _currentUser!.username,
        studentFileHash: targetHash,
        studentPageCount: localPageCount,
      );

      if (error == null) {
        setSessionCode(code.trim().toUpperCase());
        debugPrint(
          'DEBUG: Manual Join Success ($code) for ${matchingPdf.name}.',
        );
        return null; // Success
      } else {
        return error;
      }
    } catch (e) {
      debugPrint('ERROR: joinSession failed: $e');
      return 'حدث خطأ أثناء الاتصال بالخادم: $e';
    } finally {
      _isJoiningSession = false;
      _notify();
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

      // Ensure "Quick Access" exists in Isar, then always import into that real folder id.
      final fileManager = FileManagerService();
      if (!fileManager.isInitialized) {
        await fileManager.init();
      }
      final quickAccessFolder = await fileManager
          .getOrCreateQuickAccessFolder();

      final doc = await fileManager.importAndOpenPdf(
        filePath,
        classId: quickAccessFolder.uuid,
      );

      // Hydrate state to update UI
      await _hydrateClassesFromIsar();

      // Set active.
      // This must go through setActivePdf, not a direct assignment. Everything
      // that makes an opened file live lives in there: the mutation listener,
      // the lecturer session lookup, the student saved-code rejoin, and the
      // university library auto-link. Assigning _activePdfId here bypassed all
      // of them, so a file opened this way never received a sync code and the
      // right panel showed an empty session card with no error anywhere.
      _activeClassId = doc.classId;
      setActivePdf(doc.uuid);
    } catch (e) {
      debugPrint('Error loading PDF from path: $e');
    }
  }

  /// Opens a PDF in the viewer without saving it into any folder.
  /// The PDF is displayed ad-hoc (ephemeral) and is NOT persisted to Isar,
  /// so it never appears in Quick Access, class lists, or the sidebar.
  Future<void> openEphemeralPdf(String filePath, {String? name}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return;
      }

      final displayName = name ?? filePath.split(Platform.pathSeparator).last;

      String? fileHash;
      int? pageCount;
      try {
        fileHash = await FileHashService.calculateFileHash(filePath);
        final pdfDoc = await pdfrx.PdfDocument.openFile(filePath);
        pageCount = pdfDoc.pages.length;
        await pdfDoc.dispose();
      } catch (e) {
        debugPrint('Ephemeral PDF metadata skipped: $e');
      }

      _ephemeralPdf = PdfItem(
        id: 'ephemeral_${DateTime.now().millisecondsSinceEpoch}',
        name: displayName,
        path: filePath,
        fileHash: fileHash,
        pageCount: pageCount,
      );
      _activeClassId = null;
      _activePdfId = _ephemeralPdf!.id;
      _secondaryPdfId = null;
      _isSplitMode = false;

      // Intentionally NOT persisted: ephemeral view-only open.
      _notify();
    } catch (e) {
      debugPrint('Error opening ephemeral PDF from path: $e');
    }
  }

  /// Clears the ephemeral (non-folder) PDF once the user navigates to a
  /// real, folder-managed PDF.
  void _clearEphemeralPdf() {
    if (_ephemeralPdf != null) {
      _ephemeralPdf = null;
    }
  }

  Future<void> addClass(String name) async {
    final fileManager = FileManagerService();
    await fileManager.createFolder(name: name);

    // Re-hydrate state from Isar
    await _hydrateClassesFromIsar();

    // Set as active if needed
    if (_activeClassId == null && _classes.isNotEmpty) {
      _activeClassId = _classes.last.id;
    }

    _saveState();
    _notify();
  }

  // _syncFoldersWithIsar logic was neutralized and replaced by migration + hydration in Phase 1.

  Future<void> reorderClasses(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _classes.length) return;
    if (newIndex < 0 || newIndex > _classes.length) return;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final moved = _classes.removeAt(oldIndex);
    _classes.insert(newIndex, moved);

    // Refresh list identity so Selector listeners detect reorder immediately.
    _classes = List<ClassItem>.from(_classes);

    // Persist to Isar
    final uuids = _classes.map((c) => c.id).toList();
    await FileManagerService().updateFolderOrder(uuids);

    _notify();
  }

  /// Finalizes an already-imported PDF (by [FileManagerService.importAndOpenPdf])
  /// into the app state: hydrates classes, activates the target folder/PDF.
  /// Used by the college collection install pipeline.
  Future<void> importPdfFromPath(String pdfUuid, String classId) async {
    // Re-hydrate state
    await _hydrateClassesFromIsar();

    // Set active. Through setActivePdf, which is where a file receives its
    // mutation listener and its sync session.
    _activeClassId = classId;
    setActivePdf(pdfUuid);
  }

  /// Ensures the "Quick Access" folder exists and is hydrated into the
  /// sidebar so it always appears in the folder picker/install targets.
  Future<void> ensureQuickAccessExists() async {
    final fileManager = FileManagerService();
    if (!fileManager.isInitialized) await fileManager.init();
    await fileManager.getOrCreateQuickAccessFolder();
    if (_classes.every((c) => c.name != 'Quick Access')) {
      await _hydrateClassesFromIsar();
    }
  }

  Future<void> uploadPdf(String classId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;

      final fileManager = FileManagerService();
      final doc = await fileManager.importAndOpenPdf(
        filePath,
        classId: classId,
      );

      // Re-hydrate state
      await _hydrateClassesFromIsar();

      // Set active. Through setActivePdf, which is where a file receives its
      // mutation listener and its sync session.
      _activeClassId = classId;
      setActivePdf(doc.uuid);
    }
  }

  void addHighlight(String pdfId, Highlight highlight) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        final highlightWithAuthor = highlight.copyWith(
          createdBy: _currentUser?.username,
        );
        final newH = highlightWithAuthor.copyWith(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          isSynced: false,
        );
        cls.pdfs[pdfIndex].highlights.add(newH);
        if (isLockedDrawingForCurrentUser) {
          _markLockedLocalOnlyHighlight(cls.pdfs[pdfIndex].fileHash, newH.id);
        }
        // سجل الإضافة في سجل العمليات
        _actionHistory.add(
          ActionRecord(
            pdfId: pdfId,
            actionType: ActionTypes.ACTION_ADD_HIGHLIGHT,
            itemId: newH.id,
            newState: newH.toJson(),
          ),
        );
        debugPrint('📝 Action recorded: highlight ${newH.id}');
        _redoHistory.clear();
        _notify();
        markPdfDirty(pdfId);
        _markUnsavedChanges();
        triggerSync();
        return;
      }
    }
  }

  Timer? _saveTimer;

  void updatePdfScroll(
    String pdfId, {
    double? scrollTop,
    int? pageNumber,
    double? zoom,
  }) {
    for (var cls in _classes) {
      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex == -1) continue;

      if (scrollTop != null) cls.pdfs[pdfIndex].scrollTop = scrollTop;
      if (pageNumber != null) cls.pdfs[pdfIndex].lastPage = pageNumber;

      // This is the only place the viewer reports that the reader is present
      // and where they are, which is exactly what the reading statistics need.
      _noteReadingInteraction(pdfId);
      _creditPageAdvance(pdfId, pageNumber);

      final libraryHash = cls.pdfs[pdfIndex].fileHash;

      _readingStateTimer?.cancel();
      _readingStateTimer = Timer(const Duration(milliseconds: 600), () {
        FileManagerService().updateReadingState(
          pdfId,
          page: pageNumber,
          scroll: scrollTop,
          zoom: zoom,
        );
        debugPrint(
          '📍 [ReadingState] Saved for PDF: $pdfId page=$pageNumber scroll=$scrollTop zoom=$zoom',
        );
        _pushUniversityReadingProgress(libraryHash, pageNumber, scrollTop);
      });

      return;
    }
  }

  /// Mirrors the reading position of a library booklet to Firestore so the same
  /// file reopens where it was left on any device. Local-only PDFs are skipped
  /// to avoid a network write per scroll event.
  void _pushUniversityReadingProgress(
    String? fileHash,
    int? page,
    double? scroll,
  ) {
    if (fileHash == null || fileHash.isEmpty) return;
    if (!_libraryLinkedHashes.contains(fileHash)) return;
    if (page == null && scroll == null) return;
    if (_currentUser == null) return;

    final now = DateTime.now();
    final last = _lastProgressPush[fileHash];
    if (last != null && now.difference(last) < _progressPushInterval) return;
    _lastProgressPush[fileHash] = now;

    final service = UniversityService();
    if (!service.isReady) return;

    unawaited(
      service.saveReadingProgress(
        fileHash: fileHash,
        lastPage: page ?? 1,
        scrollTop: scroll ?? 0.0,
      ),
    );
  }

  void removeHighlight(String pdfId, Highlight highlight) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.highlights.remove(highlight);
      _clearLockedLocalOnlyHighlight(pdf.fileHash, highlight.id);

      // NEW: SOFT DELETE (TRASH)
      final type = highlight.type;
      final itemType =
          (type == HighlightType.pen ||
              type == HighlightType.arrow ||
              type == HighlightType.rectangle ||
              type == HighlightType.circle)
          ? 'drawing'
          : 'highlight';

      FileManagerService().saveDeletedAnnotation(
        DeletedAnnotation()
          ..originalId = highlight.id
          ..pdfId = pdfId
          ..itemType = itemType
          ..pageNumber = highlight.page
          ..deletedBy = _currentUser?.username ?? 'user'
          ..deletedAt = DateTime.now()
          ..contentSnapshot = jsonEncode(highlight.toJson()),
      );

      // Track deletion for Sync Reconciliation (Anti-Resurrection)
      if (pdf.fileHash != null) {
        _locallyDeletedIds
            .putIfAbsent(pdf.fileHash!, () => <String>{})
            .add(highlight.id);
      }

      // Record deletion in action history for Ctrl+Z
      _actionHistory.add(
        ActionRecord(
          pdfId: pdfId,
          actionType: ActionTypes.ACTION_DELETE_HIGHLIGHT,
          itemId: highlight.id,
          newState: highlight.toJson(),
        ),
      );
      _redoHistory.clear();

      _notify();
      markPdfDirty(pdfId);

      // DEBOUNCED SYNC: Rely entirely on batching. No immediate deleteAnnotation call.
      _markUnsavedChanges();
      triggerDebouncedSync(silent: true);
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
      triggerSync();
      return;
    }
  }

  Future<void> restoreAnnotation(DeletedAnnotation deleted) async {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == deleted.pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      final data = jsonDecode(deleted.contentSnapshot);

      if (deleted.itemType == 'comment' || deleted.itemType == 'math') {
        final comment = PdfComment.fromJson(data);
        pdf.comments.add(comment);
      } else {
        final highlight = Highlight.fromJson(data);
        pdf.highlights.add(highlight);
      }

      // Remove from Trash
      await FileManagerService().isar.writeTxn(() async {
        await FileManagerService().isar.deletedAnnotations.delete(deleted.id);
      });

      // Collaborative Restore: Remove from remote trash
      if (currentSessionCode != null) {
        try {
          await _syncService.removeAnnotationFromRemoteTrash(
            currentSessionCode!,
            deleted.originalId,
          );
        } catch (e) {
          debugPrint('⚠️ Failed to remove from remote trash: $e');
        }
      }

      // Clear from locallyDeletedIds so it doesn't get re-deleted on next sync
      if (pdf.fileHash != null) {
        _locallyDeletedIds[pdf.fileHash!]?.remove(deleted.originalId);
      }

      _notify();
      markPdfDirty(deleted.pdfId);
      _markUnsavedChanges();
      triggerSync(); // Trigger immediate sync to propagate the restoration
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

      final normalizedUsername = _currentUser?.username.trim();
      final effectiveAuthor =
          (normalizedUsername != null && normalizedUsername.isNotEmpty)
          ? normalizedUsername
          : comment.createdBy;

      final newC = comment.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false,
        createdBy: effectiveAuthor,
      );
      pdf.comments.add(newC);
      // سجل الإضافة في سجل العمليات
      _actionHistory.add(
        ActionRecord(
          pdfId: pdfId,
          actionType: ActionTypes.ACTION_ADD_COMMENT,
          itemId: newC.id,
          newState: newC.toJson(),
        ),
      );
      debugPrint('📝 Action recorded: comment ${newC.id}');
      _redoHistory.clear();
      _notify();
      markPdfDirty(pdfId);

      _markUnsavedChanges();
      triggerSync();
      return;
    }
  }

  void purgeForeignCommentsLocally(String username) {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return;

    var changed = false;
    for (final cls in _classes) {
      for (final pdf in cls.pdfs) {
        final beforeC = pdf.comments.length;
        pdf.comments.removeWhere((comment) {
          final author = comment.createdBy?.trim().toLowerCase();
          return author != null && author.isNotEmpty && author != normalized;
        });
        if (pdf.comments.length != beforeC) {
          changed = true;
          markPdfDirty(pdf.id);
        }

        final beforeH = pdf.highlights.length;
        pdf.highlights.removeWhere((highlight) {
          final author = highlight.createdBy?.trim().toLowerCase();
          return author != null && author.isNotEmpty && author != normalized;
        });
        if (pdf.highlights.length != beforeH) {
          changed = true;
          markPdfDirty(pdf.id);
        }
      }
    }

    if (!changed) return;

    _syncDebounce?.cancel();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), _saveState);
    _notify();
  }

  void removeComment(String pdfId, PdfComment comment) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.comments.removeWhere((c) => c.id == comment.id);

      // NEW: SOFT DELETE (TRASH)
      FileManagerService().saveDeletedAnnotation(
        DeletedAnnotation()
          ..originalId = comment.id
          ..pdfId = pdfId
          ..itemType = comment.isLatex ? 'math' : 'comment'
          ..pageNumber = comment.page
          ..deletedBy = _currentUser?.username ?? 'user'
          ..deletedAt = DateTime.now()
          ..contentSnapshot = jsonEncode(comment.toJson()),
      );

      // Track deletion for Sync Reconciliation
      if (pdf.fileHash != null) {
        _locallyDeletedIds
            .putIfAbsent(pdf.fileHash!, () => <String>{})
            .add(comment.id);
      }

      // Record deletion in action history for Ctrl+Z
      _actionHistory.add(
        ActionRecord(
          pdfId: pdfId,
          actionType: ActionTypes.ACTION_DELETE_COMMENT,
          itemId: comment.id,
          newState: comment.toJson(),
        ),
      );
      _redoHistory.clear();

      _notify();
      markPdfDirty(pdfId);

      // DEBOUNCED SYNC: Batching all mutations (including deletions tracked in _locallyDeletedIds)
      _markUnsavedChanges();
      triggerDebouncedSync(silent: true);
      return;
    }
  }

  /// Removes a comment by its string [id] — used during bidirectional sync cleanup.
  void removeCommentById(String pdfId, String commentId) {
    for (var cls in _classes) {
      var pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      pdf.comments.removeWhere((c) => c.id == commentId);
      _notify();
      markPdfDirty(pdfId);
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

      _intentionallyDeletedIds.addAll(pdf.highlights.map((h) => h.id));
      _intentionallyDeletedIds.addAll(pdf.comments.map((c) => c.id));

      pdf.highlights.clear();
      pdf.comments.clear();

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _locallyDeletedIds[pdf.fileHash!]?.clear();
      _lockedLocalOnlyHighlightIds.remove(pdf.fileHash);
      _notify();
      markPdfDirty(pdfId);

      // Standard debounced sync: will push the empty state after 3s
      _markUnsavedChanges();
      triggerDebouncedSync(silent: true);
      if (currentSessionCode != null && activePdf?.fileHash != null) {
        _syncService
            .clearAnnotationsForHash(currentSessionCode!, activePdf!.fileHash!)
            .then((_) => clearDeletionIntent(pdfId));
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

    // Mark every active PDF dirty to ensure global clear persists
    for (var cls in _classes) {
      for (var pdf in cls.pdfs) {
        markPdfDirty(pdf.id);
      }
    }
  }

  void clearAllHighlightsOnly(String pdfId) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      _intentionallyDeletedIds.addAll(
        pdf.highlights
            .where((h) => h.type == HighlightType.highlight)
            .map((h) => h.id),
      );

      pdf.highlights.removeWhere((h) => h.type == HighlightType.highlight);
      _lockedLocalOnlyHighlightIds.remove(pdf.fileHash);

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _notify();
      markPdfDirty(pdfId);
      _markUnsavedChanges();
      triggerDebouncedSync(silent: true);
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

      _intentionallyDeletedIds.addAll(
        pdf.highlights
            .where(
              (h) =>
                  h.type == HighlightType.pen ||
                  h.type == HighlightType.arrow ||
                  h.type == HighlightType.rectangle ||
                  h.type == HighlightType.circle,
            )
            .map((h) => h.id),
      );

      pdf.highlights.removeWhere(
        (h) =>
            h.type == HighlightType.pen ||
            h.type == HighlightType.arrow ||
            h.type == HighlightType.rectangle ||
            h.type == HighlightType.circle,
      );
      _lockedLocalOnlyHighlightIds.remove(pdf.fileHash);

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _notify();
      markPdfDirty(pdfId);
      _markUnsavedChanges();
      triggerDebouncedSync(silent: true);
      if (currentSessionCode != null && activePdf?.fileHash != null) {
        _syncService
            .clearAnnotationsForHash(currentSessionCode!, activePdf!.fileHash!)
            .then((_) => clearDeletionIntent(pdfId));
      }
      return;
    }
  }

  void clearDrawingsOnPage(String pdfId, int pageNumber) {
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );
      if (pdf.id.isEmpty) continue;

      final drawingIds = pdf.highlights
          .where(
            (h) =>
                h.page == pageNumber &&
                (h.type == HighlightType.pen ||
                    h.type == HighlightType.arrow ||
                    h.type == HighlightType.rectangle ||
                    h.type == HighlightType.circle),
          )
          .map((h) => h.id)
          .toList();

      if (drawingIds.isEmpty) return;

      _intentionallyDeletedIds.addAll(drawingIds);

      pdf.highlights.removeWhere(
        (h) =>
            h.page == pageNumber &&
            (h.type == HighlightType.pen ||
                h.type == HighlightType.arrow ||
                h.type == HighlightType.rectangle ||
                h.type == HighlightType.circle),
      );

      _lockedLocalOnlyHighlightIds.remove(pdf.fileHash);
      _actionHistory.removeWhere(
        (a) => a.pdfId == pdfId && drawingIds.contains(a.itemId),
      );
      _redoHistory.removeWhere(
        (a) => a.pdfId == pdfId && drawingIds.contains(a.itemId),
      );

      _notify();
      markPdfDirty(pdfId);
      _markUnsavedChanges();
      triggerDebouncedSync(silent: true);
      if (currentSessionCode != null && activePdf?.fileHash != null) {
        _syncService
            .clearAnnotationsForHash(currentSessionCode!, activePdf!.fileHash!)
            .then((_) => clearDeletionIntent(pdfId));
      }
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
      markPdfDirty(pdfId);
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

      _intentionallyDeletedIds.addAll(pdf.comments.map((c) => c.id));

      pdf.comments.clear();

      _actionHistory.removeWhere((a) => a.pdfId == pdfId);
      _redoHistory.removeWhere((a) => a.pdfId == pdfId);

      _notify();
      markPdfDirty(pdfId);
      _markUnsavedChanges();
      triggerDebouncedSync(silent: true);
      if (currentSessionCode != null && activePdf?.fileHash != null) {
        _syncService
            .clearAnnotationsForHash(currentSessionCode!, activePdf!.fileHash!)
            .then((_) => clearDeletionIntent(pdfId));
      }
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
        final updated = newComment.copyWith(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          isSynced: false,
        );
        pdf.comments[index] = updated;
        // Record the update in the action history using full toJson() snapshots.
        // This ensures PdfComment.fromJson() can correctly restore the comment
        // (including attachedMediaUrl) during Undo/Redo.
        recordUpdate(
          pdfId: pdfId,
          itemId: updated.id,
          actionType: ActionTypes.ACTION_UPDATE_COMMENT,
          notify:
              false, // Avoid double notify — _notify() is called explicitly below.
          oldState: oldComment.toJson(),
          newState: updated.toJson(),
        );
        _notify(); // Single notify
        // Same reason as updateHighlight: text is dragged and retyped across many
        // frames, and an in-flight sync must not land in the middle of that.
        _lastAnnotationEditFrame = DateTime.now();
        markPdfDirty(pdfId);
        _markUnsavedChanges();
        triggerDebouncedSync(silent: true);
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
          _clearLockedLocalOnlyHighlight(pdf.fileHash, action.itemId);
          if (pdf.fileHash != null) {
            _locallyDeletedIds
                .putIfAbsent(pdf.fileHash!, () => <String>{})
                .add(action.itemId);
          }
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
          if (pdf.fileHash != null) {
            _locallyDeletedIds
                .putIfAbsent(pdf.fileHash!, () => <String>{})
                .add(action.itemId);
          }
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
            final restored = Highlight.fromJson(action.oldState!).copyWith(
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              isSynced: false,
            );
            pdf.highlights[idx] = restored;
            _clearLockedLocalOnlyHighlight(pdf.fileHash, action.itemId);
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
            final restored = PdfComment.fromJson(action.oldState!).copyWith(
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              isSynced: false,
            );
            pdf.comments[idx] = restored;
            debugPrint('🔙 Undo: Restored comment ${action.itemId}');
          }
        }
        break;
      case ActionTypes.ACTION_DELETE_HIGHLIGHT:
        if (action.newState != null) {
          final restored = Highlight.fromJson(action.newState!).copyWith(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            isSynced: false,
          );
          pdf.highlights.add(restored);
          if (pdf.fileHash != null) {
            _locallyDeletedIds[pdf.fileHash!]?.remove(action.itemId);
          }
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
          final restored = PdfComment.fromJson(action.newState!).copyWith(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            isSynced: false,
          );
          pdf.comments.add(restored);
          if (pdf.fileHash != null) {
            _locallyDeletedIds[pdf.fileHash!]?.remove(action.itemId);
          }
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

    _notify();
    markPdfDirty(action.pdfId);
    _markUnsavedChanges();
    triggerDebouncedSync(silent: true);
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
          final restored = Highlight.fromJson(action.newState!).copyWith(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            isSynced: false,
          );
          pdf.highlights.add(restored);
          if (pdf.fileHash != null) {
            _locallyDeletedIds[pdf.fileHash!]?.remove(action.itemId);
          }
          _actionHistory.add(action);
          debugPrint('↪️ Redo: Restored highlight ${action.itemId}');
        }
        break;
      case ActionTypes.ACTION_ADD_COMMENT:
        if (action.newState != null) {
          final restored = PdfComment.fromJson(action.newState!).copyWith(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            isSynced: false,
          );
          pdf.comments.add(restored);
          if (pdf.fileHash != null) {
            _locallyDeletedIds[pdf.fileHash!]?.remove(action.itemId);
          }
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
            final restored = Highlight.fromJson(action.oldState!).copyWith(
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              isSynced: false,
            );
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
            final restored = PdfComment.fromJson(action.oldState!).copyWith(
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              isSynced: false,
            );
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
            if (pdf.fileHash != null) {
              _locallyDeletedIds
                  .putIfAbsent(pdf.fileHash!, () => <String>{})
                  .add(action.itemId);
            }
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
            if (pdf.fileHash != null) {
              _locallyDeletedIds
                  .putIfAbsent(pdf.fileHash!, () => <String>{})
                  .add(action.itemId);
            }
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

    _notify();
    markPdfDirty(action.pdfId);
    _markUnsavedChanges();
    triggerDebouncedSync(silent: true);
  }

  void clearActionHistory() {
    _actionHistory.clear();
    _redoHistory.clear();
    debugPrint('🧹 Action history cleared');
  }

  // Active editing state
  String? _activeEditingCommentId;
  String? get activeEditingCommentId => _activeEditingCommentId;
  String? _lastEditedCommentId;
  String? get lastEditedCommentId => _lastEditedCommentId;

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
        markPdfDirty(pdf.id);
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
    _lastEditedCommentId = commentId;
    _tempStyles[commentId] = {
      'color': comment.color.value,
      'fontSize': comment.fontSize,
      'isBold': comment.isBold,
      'isLatex': comment.isLatex,
      'fontFamily': comment.fontFamily,
      'showBorder': comment.showBorder,
      'borderColor': comment.borderColor.value,
      'bgColor': comment.bgColor.value,
      'attachedMediaUrl': comment.attachedMediaUrl,
      'mediaHeight': comment.mediaHeight ?? 150.0,
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

  /// Applies text style updates to either:
  /// 1) live temp editing styles (when comment is currently being edited), or
  /// 2) persisted comment model (after focus loss / edit end).
  /// Returns true when a target comment was found and updated.
  bool applyTextStyleToTarget({
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
    _lastEditedCommentId = commentId;

    if (_tempStyles.containsKey(commentId)) {
      updateEditingStyle(
        commentId: commentId,
        color: color,
        fontSize: fontSize,
        isBold: isBold,
        isLatex: isLatex,
        fontFamily: fontFamily,
        showBorder: showBorder,
        borderColor: borderColor,
        bgColor: bgColor,
      );
      return true;
    }

    for (final cls in _classes) {
      for (final pdf in cls.pdfs) {
        final idx = pdf.comments.indexWhere((c) => c.id == commentId);
        if (idx == -1) continue;
        final old = pdf.comments[idx];
        pdf.comments[idx] = old.copyWith(
          color: color ?? old.color,
          fontSize: fontSize ?? old.fontSize,
          isBold: isBold ?? old.isBold,
          isLatex: isLatex ?? old.isLatex,
          fontFamily: fontFamily ?? old.fontFamily,
          showBorder: showBorder ?? old.showBorder,
          borderColor: borderColor ?? old.borderColor,
          bgColor: bgColor ?? old.bgColor,
        );
        _notify();
        markPdfDirty(pdf.id);
        return true;
      }
    }

    return false;
  }

  // Get current temporary styles (or null if not editing)
  Map<String, dynamic>? getEditingStyles(String commentId) {
    return _tempStyles[commentId];
  }

  // End editing and save final comment
  Future<void> endEditing(
    String commentId,
    String finalContent, {
    String? attachedMediaUrl,
    double? mediaHeight,
  }) async {
    final styles = _tempStyles[commentId];
    if (styles == null) return;

    // Find the original comment
    final pdf = activePdf;
    if (pdf == null) return;

    try {
      final originalComment = pdf.comments.firstWhere((c) => c.id == commentId);

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
        // Explicitly prioritize the attachedMediaUrl and mediaHeight passed from the UI layer.
        attachedMediaUrl: attachedMediaUrl ?? originalComment.attachedMediaUrl,
        mediaHeight: mediaHeight ?? originalComment.mediaHeight,
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

    if (!await file.exists() || pageIndex < 0) return;

    try {
      // 1. Mutate locally using the hardened rolling-file service
      final newFile = await PdfMutationService.deletePageLocally(
        file,
        pageIndex,
      );

      // 2. Shift Annotations
      shiftAnnotationsOnPageDelete(pdfId, pageIndex);

      // 3. Update paths and page count
      final newPageCount = (pdfItem.pageCount ?? 1) - 1;
      final updatedPdf = pdfItem.copyWith(
        path: newFile.path,
        pageCount: newPageCount,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex] = updatedPdf;
      }
      _notify();

      // 4. Persist to Isar so the structural change survives restart
      final fm = FileManagerService();
      // CRITICAL: Must use writeTxn for writes — txn is read-only in Isar 3.x
      final doc = await fm.isar.txn(
        () => fm.isar.pdfDocuments.filter().uuidEqualTo(pdfId).findFirst(),
      );
      if (doc != null) {
        doc.workingPath = newFile.path;
        doc.totalPages = newPageCount;
        await fm.isar.writeTxn(() async {
          await fm.isar.pdfDocuments.put(doc);
        });
        debugPrint(
          '✅ [deletePage] Persisted workingPath to Isar: ${newFile.path}',
        );
      } else {
        debugPrint(
          '⚠️ [deletePage] PdfDocument not found in Isar for id: $pdfId',
        );
      }
    } catch (e) {
      debugPrint('❌ [AppProvider] Error during deletePage: $e');
    }
  }

  Future<void> addPage(String pdfId, {int? insertAtIndex}) async {
    try {
      final cls = _classes.firstWhere((c) => c.pdfs.any((p) => p.id == pdfId));
      final pdfItem = cls.pdfs.firstWhere((p) => p.id == pdfId);
      final file = File(pdfItem.path);

      if (!await file.exists()) return;

      final targetIndex = insertAtIndex ?? pdfItem.pageCount ?? 0;

      // 1. Mutate locally using the hardened rolling-file service
      final newFile = await PdfMutationService.insertPageLocally(
        file,
        targetIndex,
      );

      // 2. Shift Annotations
      shiftAnnotationsOnPageInsert(pdfId, targetIndex);

      // 3. Update paths and page count
      final newPageCount = (pdfItem.pageCount ?? 0) + 1;
      final updatedPdf = pdfItem.copyWith(
        path: newFile.path,
        pageCount: newPageCount,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex] = updatedPdf;
      }
      _notify();

      // 4. Persist to Isar so the structural change survives restart
      final fm = FileManagerService();
      // CRITICAL: Must use writeTxn for writes — txn is read-only in Isar 3.x
      final doc = await fm.isar.txn(
        () => fm.isar.pdfDocuments.filter().uuidEqualTo(pdfId).findFirst(),
      );
      if (doc != null) {
        doc.workingPath = newFile.path;
        doc.totalPages = newPageCount;
        await fm.isar.writeTxn(() async {
          await fm.isar.pdfDocuments.put(doc);
        });
        debugPrint(
          '✅ [addPage] Persisted workingPath to Isar: ${newFile.path}',
        );
      } else {
        debugPrint('⚠️ [addPage] PdfDocument not found in Isar for id: $pdfId');
      }
    } catch (e) {
      debugPrint('❌ [AppProvider] Error during addPage: $e');
    }
  }

  void shiftAnnotationsOnPageInsert(String pdfId, int insertedPageIndex) {
    final pdf = getPdf(pdfId);
    if (pdf == null) return;
    bool changed = false;
    final int targetPage = insertedPageIndex + 1;

    for (int i = 0; i < pdf.comments.length; i++) {
      if (pdf.comments[i].page >= targetPage) {
        pdf.comments[i] = pdf.comments[i].copyWith(
          page: pdf.comments[i].page + 1,
        );
        changed = true;
      }
    }
    for (int i = 0; i < pdf.highlights.length; i++) {
      if (pdf.highlights[i].page >= targetPage) {
        pdf.highlights[i] = pdf.highlights[i].copyWith(
          page: pdf.highlights[i].page + 1,
        );
        changed = true;
      }
    }
    if (changed) {
      markPdfDirty(pdfId);
      _notify();
    }
  }

  // Management Methods
  void closeActivePdf() {
    _activePdfId = null;
    _secondaryPdfId = null;
    _isSplitMode = false;
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
    // 1. Persist to Isar
    await FileManagerService().deleteFolder(classId);

    // 2. Re-hydrate projection
    await _hydrateClassesFromIsar();

    if (_activeClassId == classId) {
      _activeClassId = _classes.isNotEmpty ? _classes.first.id : null;
      _activePdfId = null;
      _secondaryPdfId = null;
      _isSplitMode = false;
    }

    if (_secondaryPdfId != null && _findPdfById(_secondaryPdfId!) == null) {
      _secondaryPdfId = null;
      _isSplitMode = false;
    }

    _notify();
  }

  Future<void> deletePdf(String classId, String pdfId) async {
    // 1. Logical Delete in Isar (handles folder list cleanup)
    await FileManagerService().deleteDocument(pdfId);

    // 2. Re-hydrate
    await _hydrateClassesFromIsar();

    if (_activePdfId == pdfId) {
      _activePdfId = null;
    }

    if (_secondaryPdfId == pdfId) {
      _secondaryPdfId = null;
      _isSplitMode = false;
    }

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
        markPdfDirty(pdfId);
        _notify();
      }
    }
  }

  void deleteBookmark(String pdfId, String bookmarkId) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex].bookmarks.removeWhere((b) => b.id == bookmarkId);
        markPdfDirty(pdfId);
        _notify();
        return;
      }
    }
  }

  Future<void> movePdf(
    String pdfId,
    String sourceClassId,
    String targetClassId,
  ) async {
    if (sourceClassId == targetClassId) return;

    // 1. Optimistic UI update so sidebar reflects move instantly.
    final sourceIndex = _classes.indexWhere((c) => c.id == sourceClassId);
    final targetIndex = _classes.indexWhere((c) => c.id == targetClassId);
    if (sourceIndex != -1 && targetIndex != -1) {
      final pdfIndex = _classes[sourceIndex].pdfs.indexWhere(
        (p) => p.id == pdfId,
      );
      if (pdfIndex != -1) {
        final movedPdf = _classes[sourceIndex].pdfs.removeAt(pdfIndex);
        _classes[targetIndex].pdfs.add(movedPdf);
        _classes = List<ClassItem>.from(_classes);
      }
    }

    _activeClassId = targetClassId;
    _activePdfId = pdfId;
    _notify();

    try {
      // 2. Persist to Isar.
      await FileManagerService().movePdf(pdfId, sourceClassId, targetClassId);

      // 3. Re-hydrate to guarantee consistency/order from database.
      await _hydrateClassesFromIsar();
    } catch (e) {
      debugPrint('❌ movePdf failed: $e');
    }
  }

  Future<void> reorderPdfWithinClass(
    String classId,
    String draggedPdfId,
    String targetPdfId,
  ) async {
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

    // Refresh list identity so Selector listeners detect reorder immediately.
    _classes = List<ClassItem>.from(_classes);

    // Persist to Isar
    final pdfUuids = cls.pdfs.map((p) => p.id).toList();
    await FileManagerService().updatePdfOrder(classId, pdfUuids);

    _notify();
  }

  PdfItem? getPdf(String pdfId) {
    for (final cls in _classes) {
      final index = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (index != -1) {
        return cls.pdfs[index];
      }
    }
    return null;
  }

  void updatePdfLocalPath(String pdfId, String newPath) {
    for (int i = 0; i < _classes.length; i++) {
      final cls = _classes[i];
      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex] = cls.pdfs[pdfIndex].copyWith(
          path: newPath,
          lastModified: DateTime.now().millisecondsSinceEpoch,
        );
        _notify();

        // 🔥 CRITICAL: Persist the new path to Isar so it survives app restarts.
        // Look up the PdfDocument by UUID and update its workingPath.
        final fm = FileManagerService();
        fm.isar
            .txn(
              () =>
                  fm.isar.pdfDocuments.filter().uuidEqualTo(pdfId).findFirst(),
            )
            .then((doc) async {
              if (doc == null) {
                debugPrint(
                  '⚠️ [AppProvider] updatePdfLocalPath: doc not found in Isar for $pdfId',
                );
                return;
              }
              doc.workingPath = newPath;
              await fm.isar.writeTxn(() async {
                await fm.isar.pdfDocuments.put(doc);
              });
              debugPrint(
                '✅ [AppProvider] Persisted new path to Isar for $pdfId → $newPath',
              );
            })
            .catchError((e) {
              debugPrint('❌ [AppProvider] Failed to persist path to Isar: $e');
            });

        break;
      }
    }
  }

  void shiftAnnotationsOnPageDelete(String pdfId, int deletedPageIndex) {
    final pdf = getPdf(pdfId);
    if (pdf == null) return;
    final int targetPage = deletedPageIndex + 1;

    // 1. Formally delete items on the deleted page (sends them to Trash/Firestore)
    // We create copies of the lists to avoid ConcurrentModificationError while iterating
    final commentsToDelete = pdf.comments
        .where((c) => c.page == targetPage)
        .toList();
    for (var c in commentsToDelete) {
      removeComment(
        pdfId,
        c,
      ); // Leverages formal deletion & sync reconciliation
    }

    final highlightsToDelete = pdf.highlights
        .where((h) => h.page == targetPage)
        .toList();
    for (var h in highlightsToDelete) {
      removeHighlight(pdfId, h);
    }

    // 2. Shift the remaining annotations down
    bool changed = false;
    for (int i = 0; i < pdf.comments.length; i++) {
      if (pdf.comments[i].page > targetPage) {
        pdf.comments[i] = pdf.comments[i].copyWith(
          page: pdf.comments[i].page - 1,
          isSynced: false,
        );
        changed = true;
      }
    }
    for (int i = 0; i < pdf.highlights.length; i++) {
      if (pdf.highlights[i].page > targetPage) {
        pdf.highlights[i] = pdf.highlights[i].copyWith(
          page: pdf.highlights[i].page - 1,
          isSynced: false,
        );
        changed = true;
      }
    }

    if (changed) {
      markPdfDirty(pdfId);
      _notify();
    }
  }

  // ─── STUDY TASKS ───────────────────────────────────────────────────────────
  List<StudyTask> _tasks = [];
  List<StudyTask> get tasks => _tasks;

  Future<void> _loadTasks() async {
    final fileService = FileManagerService();
    try {
      _tasks = await fileService.getAllTasks();
      _notify();
    } catch (e) {
      debugPrint('Error loading state: $e');
    }
  }

  Future<void> addTask(String title) async {
    final newTask = StudyTask.create(title: title);
    _tasks.add(newTask);
    _notify();
    await FileManagerService().saveTask(newTask);
  }

  Future<void> toggleTask(String uuid) async {
    final index = _tasks.indexWhere((t) => t.uuid == uuid);
    if (index != -1) {
      _tasks[index].isDone = !_tasks[index].isDone;
      _notify();
      await FileManagerService().saveTask(_tasks[index]);
    }
  }

  Future<void> deleteTask(String uuid) async {
    _tasks.removeWhere((t) => t.uuid == uuid);
    _notify();
    await FileManagerService().deleteTaskByUuid(uuid);
  }

  /// Renames a task in place. The task row's 3-dots menu offers Edit, and the
  /// list holds the objects themselves, so the write is the same shape as
  /// [toggleTask]: mutate, notify, persist.
  Future<void> updateTask(String uuid, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final index = _tasks.indexWhere((t) => t.uuid == uuid);
    if (index != -1) {
      _tasks[index].title = trimmed;
      _notify();
      await FileManagerService().saveTask(_tasks[index]);
    }
  }

  // ─── SCHEDULE ──────────────────────────────────────────────────────────────
  //
  // The dashboard's schedule column, backed by the shared `timetable_entries`
  // table in Firestore (see `TimetableService`). Admins write it; everyone reads
  // it. The reading figures and this column now share one rule: nothing here is
  // invented, so an empty table renders the empty state rather than sample rows
  // under real Arabic course names.
  //
  // The list is held in memory and refreshed by a stream rather than queried per
  // build, for the same reason the tasks are: `watchEntries` is a `snapshots()`
  // subscription, and calling it inside `build` would re-subscribe the dashboard
  // on every frame.

  final TimetableService _timetableService = TimetableService();
  TimetableService get timetableService => _timetableService;

  StreamSubscription<List<TimetableEntry>>? _timetableSubscription;
  List<TimetableEntry> _timetableEntries = const [];
  List<TimetableEntry> get timetableEntries => _timetableEntries;

  /// True once a subscription is live. The schedule card uses this to tell "the
  /// table is empty" apart from "we have not asked yet" — showing "no lectures"
  /// before the first snapshot arrives would flash a wrong answer on every launch.
  bool _timetableLoaded = false;
  bool get isTimetableLoaded => _timetableLoaded;

  /// True when the live subscription has reported an error: a rule that is not
  /// deployed, a denied read, a dead network.
  ///
  /// Exists so the schedule card can tell "the table is empty" apart from "we
  /// could not read the table" — without it a denied read draws an empty schedule,
  /// which is a wrong answer wearing the same clothes as a right one.
  bool _timetableFailed = false;
  bool get isTimetableFailed => _timetableFailed;

  /// Hands [user] to the service and starts the shared stream.
  ///
  /// One method because there are two auth paths that must run it — a fresh
  /// login through [setCurrentUser] and the auto-login restore that assigns
  /// `_currentUser` directly — and inlining it in both was exactly what let the
  /// second one ship without it. It cannot be moved into `setCurrentUser`
  /// wholesale, since that also saves state and starts the user monitor, neither
  /// of which a restore that just read that state should repeat.
  void _beginTimetableSession(AppUser user) {
    _timetableService.currentUser = user;
    initTimetable();
  }

  /// Subscribes to the shared table. Idempotent: calling it again after a login
  /// replaces the old subscription rather than stacking a second one, which is
  /// the failure mode that makes a `ChangeNotifier` fire N times per write.
  void initTimetable() {
    // Asking again is a fresh attempt, so the failure this subscription
    // reported last time no longer describes the one being opened. Without this
    // a retry would re-render its own failure button on the next frame — the
    // resubscribe would have happened and looked exactly like nothing did.
    _timetableFailed = false;
    _timetableSubscription?.cancel();
    _timetableSubscription = _timetableService.watchEntries().listen(
      (entries) {
        _timetableEntries = entries;
        _timetableLoaded = true;
        _timetableFailed = false;
        _notify();
      },
      // A failed read leaves the previous rows on screen and logs, rather than
      // blanking a table the user was in the middle of reading. The subscription
      // is not restarted: Firestore's own retry already covers the transient
      // cases, and an endless resubscribe loop against a revoked rule is worse
      // than one honest failure.
      //
      // The flag is what stops that honesty from ending at the log. A denied read
      // — the rules not deployed, a role not granted — would otherwise render as
      // "لا توجد محاضرات", which is not a lesser answer but a false one: the table
      // may be full and the reader is told it is empty. Set here and cleared by the
      // next successful snapshot, so a recovery clears the warning by itself.
      onError: (Object e) {
        debugPrint('⚠️ [AppProvider] Timetable stream error: $e');
        _timetableFailed = true;
        _notify();
      },
    );
  }

  /// Starts the stream when nothing has started it yet.
  ///
  /// Not a replacement for [_beginTimetableSession]: it cannot invent a user, so
  /// it answers "the dialog is waiting on a subscription nobody opened" and not
  /// "this write has no author". Paid at the manager's front door rather than in
  /// a `build`, because it is idempotent but still a side effect, and a side
  /// effect in a build is one refactor away from running per frame.
  void ensureTimetableWatched() {
    if (_timetableSubscription != null) return;
    initTimetable();
  }

  void _disposeTimetable() {
    _timetableSubscription?.cancel();
    _timetableSubscription = null;
  }

  /// Puts this provider's user back into the service immediately before a write.
  ///
  /// The service holds a *copy* of the user because reaching back into this
  /// provider would close an import cycle, which quietly made two things into
  /// two separate obligations: "is the user signed in" and "did the handover run
  /// in whichever auth path led here". Re-asserting at the point of use collapses
  /// them, so a write can now only be refused for a role — never for a handshake
  /// that a third auth path forgot to perform.
  void _authorTimetableWrite() {
    _timetableService.currentUser = _currentUser;
  }

  /// Saves an entry and mirrors the result locally.
  ///
  /// The local write is what makes the card update instantly: the stream will
  /// echo the same document back a moment later, and without this the admin's
  /// own edit would appear to do nothing until the round trip completed.
  Future<void> saveTimetableEntry(TimetableEntry entry) async {
    _authorTimetableWrite();
    final before = _timetableEntries;
    final next = before.any((e) => e.id == entry.id && entry.id.isNotEmpty)
        ? before.map((e) => e.id == entry.id ? entry : e).toList()
        : [...before, entry];
    _timetableEntries = _sorted(next);
    _notify();
    try {
      await _timetableService.saveEntry(entry);
    } catch (e) {
      // Put it back, so a rejected write does not leave a row on screen that no
      // other user will ever see.
      _timetableEntries = before;
      _notify();
      rethrow;
    }
  }

  Future<void> deleteTimetableEntry(String id) async {
    _authorTimetableWrite();
    final before = _timetableEntries;
    _timetableEntries = _sorted(before.where((e) => e.id != id).toList());
    _notify();
    try {
      await _timetableService.deleteEntry(id);
    } catch (e) {
      _timetableEntries = before;
      _notify();
      rethrow;
    }
  }

  static List<TimetableEntry> _sorted(List<TimetableEntry> entries) {
    final copy = [...entries];
    copy.sort((a, b) {
      final byDay = a.weekday.compareTo(b.weekday);
      if (byDay != 0) return byDay;
      return a.startMinutes.compareTo(b.startMinutes);
    });
    return copy;
  }

  /// Tomorrow's lectures, and only tomorrow's.
  ///
  /// The card shows one day because that is the shape it was asked for; the full
  /// week lives in `ScheduleManagerDialog`. Which day is chosen here rather than
  /// in the card, so the column cannot disagree with the admin's list about what
  /// counts as tomorrow.
  ///
  /// Recomputed on read rather than stored: a date rolls over at midnight, and a
  /// cached list computed before that would keep showing the wrong day until
  /// something else happened to trigger a rebuild.
  List<LectureSlot> get lectures {
    final now = DateTime.now();
    final tomorrow = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final slots = <LectureSlot>[];
    for (final entry in _timetableEntries) {
      final slot = entry.lectureOn(tomorrow);
      if (slot != null) slots.add(slot);
    }
    slots.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return slots;
  }

  // ───────────────────────────────────────────────────────────────────────
  // FOLDER ANNOUNCEMENTS (university library)
  //
  // The notes a professor posts to one folder under "المكتبة الجامعية".
  // Firestore path: `university_folders/{folderId}/announcements/{id}`.
  //
  // The list is held here and refreshed by a stream rather than queried per
  // build, for the same reason the timetable is: `watchAnnouncements` is a
  // `snapshots()` subscription, and calling it inside `build` would
  // re-subscribe the page on every frame.
  //
  // One subscription at a time, owned by whichever folder is open. Opening a
  // different folder replaces it; closing the announcements page cancels it.
  // ───────────────────────────────────────────────────────────────────────

  final FolderAnnouncementService _announcementService =
      FolderAnnouncementService();
  FolderAnnouncementService get announcementService => _announcementService;

  StreamSubscription<List<FolderAnnouncement>>? _announcementsSubscription;
  List<FolderAnnouncement> _announcements = const [];
  List<FolderAnnouncement> get folderAnnouncements => _announcements;

  /// True once a snapshot has arrived. What lets the page tell "this folder has
  /// no notes" apart from "we have not asked yet".
  bool _announcementsLoaded = false;
  bool get isAnnouncementsLoaded => _announcementsLoaded;

  /// True when the live subscription reported an error: a rule that is not
  /// deployed, a denied read, a dead network.
  bool _announcementsFailed = false;
  bool get isAnnouncementsFailed => _announcementsFailed;

  /// True while a publish is in flight, so the composer can disable its button.
  bool _publishingAnnouncement = false;
  bool get isPublishingAnnouncement => _publishingAnnouncement;

  /// Whether the signed-in user may post to a folder at all.
  ///
  /// The same `AppUser.isLecturer` the Firestore rules check. Read through the
  /// getter rather than the raw role so `admin` and `developer` are included:
  /// the note is the professor's, and the admin runs the library.
  bool get canPublishAnnouncement => _currentUser?.isLecturer ?? false;

  /// Whether the signed-in user may remove a note somebody else wrote.
  bool get canModerateAnnouncements => _currentUser?.isAdmin ?? false;

  /// Opens the stream for [folderId], replacing whatever was being watched.
  void _watchAnnouncements(String folderId) {
    _announcementsSubscription?.cancel();
    // Cleared before the new subscription: leaving the previous folder's notes
    // on screen while the next folder's listing comes back is how a note from
    // physics shows up under mathematics.
    _announcements = const [];
    _announcementsLoaded = false;
    _announcementsFailed = false;

    _announcementsSubscription = _announcementService
        .watchAnnouncements(folderId)
        .listen(
          (items) {
            _announcements = items;
            _announcementsLoaded = true;
            _announcementsFailed = false;
            _notify();
          },
          // Reported rather than swallowed, and it stops the spinner too:
          // without the flag a refused read would render as an empty folder,
          // which is a false answer rather than a lesser one.
          onError: (Object e) {
            debugPrint('⚠️ [AppProvider] Announcements stream error: $e');
            _announcementsFailed = true;
            _announcementsLoaded = true;
            _notify();
          },
        );
  }

  /// Re-opens the stream for the folder on screen. What the error state's retry
  /// button calls.
  void retryFolderAnnouncements() {
    final folder = _announcementsFolder;
    if (folder == null) return;
    _watchAnnouncements(folder.id);
    _notify();
  }

  void _disposeAnnouncements() {
    _announcementsSubscription?.cancel();
    _announcementsSubscription = null;
    _announcements = const [];
    _announcementsLoaded = false;
    _announcementsFailed = false;
    _publishingAnnouncement = false;
  }

  /// Puts this provider's user back into the service immediately before a
  /// write.
  ///
  /// The service holds a *copy* of the user because reaching back into this
  /// provider would close an import cycle. Re-asserting at the point of use
  /// means a write can only be refused for a role — never for a handshake that
  /// another auth path forgot to perform.
  void _authorAnnouncementWrite() {
    _announcementService.currentUser = _currentUser;
  }

  /// Publishes to the folder on screen.
  ///
  /// [imageUrl] arrives as a link the composer already produced by uploading to
  /// Supabase Storage. Nothing is uploaded here: this layer writes documents,
  /// and a note that reached Firestore with an image that failed to upload
  /// would be a card promising a photo that does not exist.
  ///
  /// No optimistic insert: `snapshots()` echoes a pending write back locally
  /// with its fields already filled in, so the card is on screen a frame later
  /// without a second copy for the server's echo to replace.
  Future<void> publishFolderAnnouncement({
    required String title,
    required String body,
    String? imageUrl,
  }) async {
    final folder = _announcementsFolder;
    if (folder == null) {
      throw StateError('لا يوجد مجلد مفتوح');
    }
    _authorAnnouncementWrite();
    _publishingAnnouncement = true;
    _notify();
    try {
      await _announcementService.publish(
        folderId: folder.id,
        title: title,
        body: body,
        imageUrl: imageUrl,
      );
    } finally {
      _publishingAnnouncement = false;
      _notify();
    }
  }

  /// Removes a note, mirroring the removal locally so the card leaves the list
  /// on the tap rather than after the round trip.
  Future<void> deleteFolderAnnouncement(String id) async {
    final folder = _announcementsFolder;
    if (folder == null || id.isEmpty) return;
    _authorAnnouncementWrite();
    final before = _announcements;
    _announcements = before.where((a) => a.id != id).toList();
    _notify();
    try {
      await _announcementService.delete(folderId: folder.id, id: id);
    } catch (e) {
      // Put it back: a refused delete must not leave a card missing here that
      // every other reader can still see.
      _announcements = before;
      _notify();
      rethrow;
    }
  }
}

extension ClassIdHelper on ClassItem {
  bool classIdCheck(String id) => this.id == id;
}
