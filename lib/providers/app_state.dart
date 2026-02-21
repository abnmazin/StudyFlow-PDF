import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncfusion_flutter_pdf/pdf.dart' hide PdfBookmark;
import '../models/models.dart';

class AppProvider extends ChangeNotifier {
  List<ClassItem> _classes = [];
  String? _activeClassId;
  String? _activePdfId;

  // UI State
  bool _isMobileOpen = false;
  bool _showDevInfo = false;
  bool _isSidebarCollapsed = false;
  bool _isDarkMode = false; // Default light mode

  // Concurrency Locks
  bool _isSaving = false;
  bool _needsSave = false;

  // ─── UNDO SYSTEM ───────────────────────────────────────────────────────────
  /// Global action history stack. Each action (highlight, comment) is recorded.
  /// Format: "{pdfId}:{actionType}:{actionId}"
  /// actionType can be 'highlight' or 'comment'
  final List<String> _actionHistory = [];

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

  final Completer<void> _initCompleter = Completer<void>();

  // Use this Future to wait for app state to be fully loaded
  Future<void> get initialized => _initCompleter.future;

  AppProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadState();
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

      // CRITICAL SYSTEM CLEANUP: Drop orphaned temp files
      await _cleanupTempFiles();
    } catch (e) {
      debugPrint('Critical error during state initialization: $e');
    }

    notifyListeners();
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
    notifyListeners();
  }

  void toggleDevInfo(bool show) {
    _showDevInfo = show;
    notifyListeners();
  }

  void toggleSidebar() {
    _isSidebarCollapsed = !_isSidebarCollapsed;
    notifyListeners();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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
        final newPdf = PdfItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: fileName,
          path: filePath,
          originalPath: filePath,
        );
        quickAccessClass.pdfs.add(newPdf);

        // Set as active
        _activeClassId = quickAccessClass.id;
        _activePdfId = newPdf.id;
        quickAccessClass.lastActivePdfId = newPdf.id;
      }

      await _saveState();
      notifyListeners();
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
    notifyListeners();
  }

  Future<void> uploadPdf(String classId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final newPdf = PdfItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result.files.single.name,
        path: file.path,
        highlights: [],
      );

      final classIndex = _classes.indexWhere((c) => c.id == classId);
      if (classIndex != -1) {
        _classes[classIndex].pdfs.add(newPdf);
        _activeClassId = classId;
        _activePdfId = newPdf.id;
        _classes[classIndex].lastActivePdfId = newPdf.id; // Set as active
        _saveState();
        notifyListeners();
      }
    }
  }

  void addHighlight(String pdfId, Highlight highlight) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex].highlights.add(highlight);
        
        // ─── RECORD ACTION IN HISTORY ───────────────────────────────────
        _actionHistory.add('$pdfId:highlight:${highlight.id}');
        debugPrint('📝 Action recorded: highlight ${highlight.id}');
        
        _saveState(); // Save on highlight
        notifyListeners();
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
      notifyListeners();
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
      
      // ─── RECORD ACTION IN HISTORY ───────────────────────────────────
      _actionHistory.add('$pdfId:comment:${comment.id}');
      debugPrint('📝 Action recorded: comment ${comment.id}');
      
      notifyListeners();
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
      notifyListeners();
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
        notifyListeners();
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
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
      debugPrint('⚠️  Undo: No actions to undo');
      return;
    }

    // Pop the last action from history
    final actionRecord = _actionHistory.removeLast();
    final parts = actionRecord.split(':');
    
    if (parts.length != 3) {
      debugPrint('⚠️  Undo: Invalid action record format');
      return;
    }

    final pdfId = parts[0];
    final actionType = parts[1];
    final actionId = parts[2];

    // Find the PDF and remove the action
    for (var cls in _classes) {
      final pdf = cls.pdfs.firstWhere(
        (p) => p.id == pdfId,
        orElse: () => PdfItem(id: '', name: '', path: ''),
      );

      if (pdf.id.isEmpty) continue;

      if (actionType == 'highlight') {
        // Remove the highlight with matching ID
        pdf.highlights.removeWhere((h) => h.id == actionId);
        debugPrint('🔙 Undo: Removed highlight $actionId');
      } else if (actionType == 'comment') {
        // Remove the comment with matching ID
        pdf.comments.removeWhere((c) => c.id == actionId);
        debugPrint('🔙 Undo: Removed comment $actionId');
      }

      // Save state and notify UI
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      notifyListeners();
      return;
    }
  }

  void clearActionHistory() {
    _actionHistory.clear();
    debugPrint('🧹 Action history cleared');
  }

  // Active editing state
  String? _activeEditingCommentId;
  String? get activeEditingCommentId => _activeEditingCommentId;

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
      'showBorder': comment.showBorder,
      'borderColor': comment.borderColor.value,
      'bgColor': comment.bgColor.value,
    };
    notifyListeners();
  }

  // Update style during editing (called from right panel)
  void updateEditingStyle({
    required String commentId,
    Color? color,
    double? fontSize,
    bool? isBold,
    bool? isLatex,
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
    if (showBorder != null) styles['showBorder'] = showBorder;
    if (borderColor != null) styles['borderColor'] = borderColor.value;
    if (bgColor != null) styles['bgColor'] = bgColor.value;

    notifyListeners(); // Triggers rebuild of DraggableTextWidget with new styles
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
    notifyListeners();
  }

  // Cancel editing without saving
  void cancelEditing(String commentId) {
    _tempStyles.remove(commentId);
    if (_activeEditingCommentId == commentId) {
      _activeEditingCommentId = null;
    }
    notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
  }

  Future<void> deleteClass(String classId) async {
    _classes.removeWhere((c) => c.id == classId);

    if (_activeClassId == classId) {
      _activeClassId = _classes.isNotEmpty ? _classes.first.id : null;
      _activePdfId = null;
    }

    _saveState();
    notifyListeners();
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
    notifyListeners();
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
        notifyListeners();
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
        notifyListeners();
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
    notifyListeners();
  }

  @override
  void dispose() {
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
