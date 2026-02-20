import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/models.dart';

class AppProvider extends ChangeNotifier {
  List<ClassItem> _classes = [];
  String? _activeClassId;
  String? _activePdfId;

  // UI State
  bool _isMobileOpen = false;
  bool _showDevInfo = false;
  bool _isSidebarCollapsed = false;

  AppProvider() {
    _loadState();
  }

  // Getters
  List<ClassItem> get classes => _classes;
  String? get activeClassId => _activeClassId;
  String? get activePdfId => _activePdfId;
  bool get isMobileOpen => _isMobileOpen;
  bool get showDevInfo => _showDevInfo;
  bool get isSidebarCollapsed => _isSidebarCollapsed;

  PdfItem? get activePdf {
    if (_activeClassId == null || _activePdfId == null) return null;
    try {
      final cls = _classes.firstWhere((c) => c.id == _activeClassId);
      return cls.pdfs.firstWhere((p) => p.id == _activePdfId);
    } catch (_) {
      return null;
    }
  }

  static const String _prefsKeyClasses = 'pdfreader_classes';
  static const String _prefsKeyActiveClass = 'pdfreader_active_class';

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    final classesJson = prefs.getString(_prefsKeyClasses);
    if (classesJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(classesJson);
        _classes = decoded.map((item) => ClassItem.fromJson(item)).toList();
      } catch (e) {
        debugPrint('Error loading classes: $e');
      }
    }

    final savedClassId = prefs.getString(_prefsKeyActiveClass);
    if (savedClassId != null && _classes.any((c) => c.id == savedClassId)) {
      _activeClassId = savedClassId;

      final cls = _classes.firstWhere((c) => c.id == savedClassId);
      if (cls.lastActivePdfId != null &&
          cls.pdfs.any((p) => p.id == cls.lastActivePdfId)) {
        _activePdfId = cls.lastActivePdfId;
      }
    } else if (_classes.isNotEmpty) {
      _activeClassId = _classes.first.id;
    }

    notifyListeners();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final classesJson = jsonEncode(_classes.map((c) => c.toJson()).toList());
    await prefs.setString(_prefsKeyClasses, classesJson);
    if (_activeClassId != null) {
      await prefs.setString(_prefsKeyActiveClass, _activeClassId!);
    }
  }

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

  void setActiveClass(String id) {
    _activeClassId = id;

    final cls = _classes.firstWhere(
      (c) => c.classIdCheck(id),
      orElse: () => _classes.first,
    );
    if (cls.id == id && cls.lastActivePdfId != null) {
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
    _isMobileOpen = false;

    if (_activeClassId != null) {
      final index = _classes.indexWhere((c) => c.id == _activeClassId);
      if (index != -1) {
        _classes[index].lastActivePdfId = id;
      }
    }

    _saveState();
    notifyListeners();
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
        _classes[classIndex].lastActivePdfId = newPdf.id;
        _saveState();
        notifyListeners();
      }
    }
  }

  // --- دالة النقل الآمنة لحل مشكلة السحب والإفلات ---
  void movePdf(String pdfId, String sourceClassId, String targetClassId) {
    if (sourceClassId == targetClassId) return;

    final sourceClassIndex = _classes.indexWhere((c) => c.id == sourceClassId);
    final targetClassIndex = _classes.indexWhere((c) => c.id == targetClassId);

    if (sourceClassIndex == -1 || targetClassIndex == -1) return;

    final sourceClass = _classes[sourceClassIndex];
    final targetClass = _classes[targetClassIndex];

    final pdfIndex = sourceClass.pdfs.indexWhere((p) => p.id == pdfId);
    if (pdfIndex == -1) return;

    final pdf = sourceClass.pdfs.removeAt(pdfIndex);
    targetClass.pdfs.add(pdf);

    if (sourceClass.lastActivePdfId == pdfId) {
      sourceClass.lastActivePdfId = null;
    }

    if (_activePdfId == pdfId) {
      _activeClassId = targetClassId;
      targetClass.lastActivePdfId = pdfId;
    }

    _saveState();
    notifyListeners();
  }

  void addHighlight(String pdfId, Highlight highlight) {
    for (var cls in _classes) {
      var pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex].highlights.add(highlight);
        _saveState();
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

      pdf.comments.remove(comment);
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

      final index = pdf.comments.indexOf(oldComment);
      if (index != -1) {
        pdf.comments[index] = newComment;
        notifyListeners();
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 500), _saveState);
      }
      return;
    }
  }

  Future<void> deletePage(String pdfId, int pageIndex) async {
    final cls = _classes.firstWhere((c) => c.pdfs.any((p) => p.id == pdfId));
    final pdfItem = cls.pdfs.firstWhere((p) => p.id == pdfId);
    final file = File(pdfItem.path);

    if (!await file.exists()) return;

    final List<int> bytes = await file.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);

    if (pageIndex >= 0 &&
        pageIndex < document.pages.count &&
        document.pages.count > 1) {
      _shiftAnnotationsAfterDelete(pdfItem, pageIndex);

      document.pages.removeAt(pageIndex);
      final List<int> newBytes = await document.save();

      final realPath = pdfItem.originalPath ?? pdfItem.path;
      final tempPath =
          "${realPath.replaceAll('.pdf', '')}_${DateTime.now().microsecondsSinceEpoch}.pdf";

      await File(realPath).writeAsBytes(newBytes, flush: true);
      await File(tempPath).writeAsBytes(newBytes, flush: true);

      if (pdfItem.path != realPath) {
        try {
          final oldFile = File(pdfItem.path);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          debugPrint("Error deleting old temp file: $e");
        }
      }

      await Future.delayed(const Duration(milliseconds: 200));

      final int newTimestamp = DateTime.now().millisecondsSinceEpoch;

      int? newLastPage = pdfItem.lastPage;
      final newPageCount = document.pages.count;
      if (newLastPage != null && newLastPage > newPageCount) {
        newLastPage = newPageCount;
      } else if (pageIndex >= 0) {
        int targetPage = pageIndex + 1;
        if (targetPage > newPageCount) targetPage = newPageCount;
        newLastPage = targetPage;
      }

      final updatedPdf = pdfItem.copyWith(
        path: tempPath,
        originalPath: realPath,
        lastModified: newTimestamp,
        lastPage: newLastPage,
      );
      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex] = updatedPdf;
      }

      document.dispose();
      notifyListeners();
    } else {
      document.dispose();
    }
  }

  Future<void> addPage(String pdfId, {int? insertAtIndex}) async {
    try {
      final cls = _classes.firstWhere((c) => c.pdfs.any((p) => p.id == pdfId));
      final pdfItem = cls.pdfs.firstWhere((p) => p.id == pdfId);
      final file = File(pdfItem.path);

      if (!await file.exists()) return;

      final List<int> bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      if (insertAtIndex != null &&
          insertAtIndex >= 0 &&
          insertAtIndex <= document.pages.count) {
        document.pages.insert(insertAtIndex);
      } else {
        document.pages.add();
      }

      final List<int> newBytes = await document.save();

      final realPath = pdfItem.originalPath ?? pdfItem.path;
      final tempPath =
          "${realPath.replaceAll('.pdf', '')}_${DateTime.now().microsecondsSinceEpoch}.pdf";

      await File(realPath).writeAsBytes(newBytes, flush: true);
      await File(tempPath).writeAsBytes(newBytes, flush: true);

      if (pdfItem.path != realPath) {
        try {
          final oldFile = File(pdfItem.path);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          debugPrint("Error deleting old temp file: $e");
        }
      }

      await Future.delayed(const Duration(milliseconds: 200));

      final int newTimestamp = DateTime.now().millisecondsSinceEpoch;

      int? newLastPage;
      if (insertAtIndex != null) {
        newLastPage = insertAtIndex + 1;
      } else {
        newLastPage = document.pages.count;
      }

      final updatedPdf = pdfItem.copyWith(
        path: tempPath,
        originalPath: realPath,
        lastModified: newTimestamp,
        lastPage: newLastPage,
      );
      final pdfIndex = cls.pdfs.indexWhere((p) => p.id == pdfId);
      if (pdfIndex != -1) {
        cls.pdfs[pdfIndex] = updatedPdf;
      }

      document.dispose();
      notifyListeners();
    } catch (e) {
      debugPrint("Error adding page: $e");
    }
  }

  void _shiftAnnotationsAfterDelete(PdfItem pdf, int deletedPageIndex) {
    final int deletedPageNum = deletedPageIndex + 1;

    pdf.highlights.removeWhere((h) => h.page == deletedPageNum);
    pdf.comments.removeWhere((c) => c.page == deletedPageNum);

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

    _saveState();
  }

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

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

extension ClassIdHelper on ClassItem {
  bool classIdCheck(String id) => this.id == id;
}
