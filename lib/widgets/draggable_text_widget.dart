import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:math_expressions/math_expressions.dart' as me;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/annotations.dart';
import '../providers/app_state.dart';
import '../services/supabase_storage_service.dart';

class DraggableTextWidget extends StatefulWidget {
  final String commentId;
  final String content;
  final String? attachedMediaUrl;
  final double? mediaHeight;
  final Color color;
  final double fontSize;
  final bool isBold;
  final bool isLatex;
  final String fontFamily;
  final bool showBorder;
  final Color borderColor;
  final Color bgColor;
  final double scale;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragEnd;
  final bool enableDrag;
  final bool isEditing;
  final void Function(
    String text,
    String? mediaUrl,
    double mediaHeight,
    PointerDownEvent? event,
  ) onEditComplete;
  final VoidCallback? onIncreaseSize;
  final VoidCallback? onDecreaseSize;
  final VoidCallback? onToggleBorder;
  final VoidCallback? onToggleLatex;

  const DraggableTextWidget({
    super.key,
    required this.commentId,
    required this.content,
    this.attachedMediaUrl,
    this.mediaHeight,
    required this.color,
    required this.fontSize,
    required this.isBold,
    required this.isLatex,
    required this.fontFamily,
    required this.showBorder,
    required this.borderColor,
    required this.bgColor,
    required this.scale,
    required this.onTap,
    required this.onDragEnd,
    required this.enableDrag,
    this.isEditing = false,
    required this.onEditComplete,
    this.onIncreaseSize,
    this.onDecreaseSize,
    this.onToggleBorder,
    this.onToggleLatex,
  });

  @override
  State<DraggableTextWidget> createState() => _DraggableTextWidgetState();
}

class _DraggableTextWidgetState extends State<DraggableTextWidget> {
  Offset _dragOffset = Offset.zero;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  bool _isUploadingMedia = false;
  String? _attachedMediaUrl;
  double _mediaHeight = 150.0;
  int _imageRetryCount = 0;

  bool _containsArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  TextDirection _plainTextDirection(String text) {
    return _containsArabic(text) ? TextDirection.rtl : TextDirection.ltr;
  }

  String _normalizeFontFamily(String family) {
    // Map legacy/display label to the bundled pubspec family name.
    if (family.trim() == 'Noto Naskh Arabic') {
      return 'NotoNaskhArabic';
    }
    return family;
  }

  bool _isArabicSafeFont(String family) {
    final normalized = _normalizeFontFamily(family).trim().toLowerCase();
    const arabicSafeFamilies = {
      'notonaskharabic',
      'noto sans arabic',
      'amiri',
      'times new roman',
      'segoe ui',
      'tahoma',
      'arial',
    };
    return arabicSafeFamilies.contains(normalized);
  }

  String? _plainTextFontFamily(String text) {
    final selected = _normalizeFontFamily(widget.fontFamily);
    if (_containsArabic(text)) {
      // Arabic must use a shaping-safe family to avoid disconnected letters.
      if (selected.isEmpty) return 'NotoNaskhArabic';
      return _isArabicSafeFont(selected) ? selected : 'NotoNaskhArabic';
    }
    return selected;
  }

  String _prepareDisplayText(String text, {required bool isArabic}) {
    if (!isArabic || text.isEmpty) return text;

    // Bracketed snippets like (6) are safer without wrapping.
    if (RegExp(r'[\(\)\[\]\{\}]').hasMatch(text)) {
      return text;
    }

    // Use Unicode bidi isolates for LTR technical segments in Arabic context.
    const fsi = '\u2068';
    const pdi = '\u2069';
    final latinOrMathSegment = RegExp(
      r'([A-Za-z0-9][A-Za-z0-9\s/\\+\-*=.,:;_%^<>]*)',
    );

    return text.replaceAllMapped(
      latinOrMathSegment,
      (m) => '$fsi${m.group(1)}$pdi',
    );
  }

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content);
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyV) {
          final isControlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
          if (isControlPressed) {
            // Intercept and handle manually to prevent Windows clipboard locking
            _handleClipboardPasteManually();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _attachedMediaUrl = widget.attachedMediaUrl;
    // When a brand-new widget is built already in editing mode (e.g. _addTextAt),
    // didUpdateWidget never fires, so we must request focus here.
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          if (widget.isLatex) _showOverlay();
        }
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _persistAttachmentUrl(String? url) {
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    PdfComment? existingComment;
    for (final comment in pdf.comments) {
      if (comment.id == widget.commentId) {
        existingComment = comment;
        break;
      }
    }

    if (existingComment != null) {
      final updatedComment = existingComment.copyWith(attachedMediaUrl: url);
      app.updateComment(pdf.id, existingComment, updatedComment);
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_isUploadingMedia) return;

    String? filePath;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      filePath = result?.files.single.path;
    } else {
      // Keep image_picker available for mobile targets.
      // On desktop we avoid the plugin path that was failing in the Windows runner.
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      filePath = pickedFile?.path;
    }

    if (filePath == null || filePath.isEmpty) return;

    setState(() => _isUploadingMedia = true);
    try {
      final storage = SupabaseStorageService();
      final url = await storage.uploadFile(
        File(filePath),
        isAudio: false,
      );
      if (url == null) return;

      _persistAttachmentUrl(url);

      if (mounted) {
        setState(() => _attachedMediaUrl = url);
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingMedia = false);
      }
    }
  }

  Future<void> _handleClipboardPasteManually() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        setState(() => _isUploadingMedia = true);
        final storage = SupabaseStorageService();
        final url = await storage.uploadBytes(imageBytes, '.png');
        if (url != null) {
          _persistAttachmentUrl(url);
          if (mounted) setState(() => _attachedMediaUrl = url);
        }
        if (mounted) setState(() => _isUploadingMedia = false);
        return; // Image handled, stop here
      }
    } catch (e) {
      print('❌ [Pasteboard] failed to read image: $e');
      if (mounted) setState(() => _isUploadingMedia = false);
    }

    // Fallback: Manually paste text if no image was found
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        final text = data.text!;
        final currentSelection = _textController.selection;
        if (currentSelection.isValid) {
          final newText = _textController.text.replaceRange(
            currentSelection.start,
            currentSelection.end,
            text,
          );
          _textController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(
              offset: currentSelection.start + text.length,
            ),
          );
        } else {
          _textController.text += text;
        }
        // Trigger onChanged manually to update LaTeX sizing
        _tryAutoSolveLatex(_textController.text);
        if (mounted) setState(() {});
      }
    } catch (e) {
      print('❌ [Clipboard] failed to read text: $e');
    }
  }

  void _tryAutoSolveLatex(String currentText) {
    if (!widget.isLatex) return;
    if (!currentText.endsWith('=')) return;

    // Extract the equation before the '='
    String rawEquation = currentText
        .substring(0, currentText.length - 1)
        .trim();

    // Clean LaTeX formatting into a standard math expression using Regex
    String cleanEq = rawEquation;

    // 1. تحويل الأقواس الخاصة باللاتكس
    cleanEq = cleanEq.replaceAll(RegExp(r'\\left\('), '(');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\right\)'), ')');

    // 2. معالجة الأسس للتخلص من الأقواس المعكوفة {} قبل الوصول للكسور
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\^\{([^}]+)\}'), (m) => '^(${m[1]})');
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'_\{([^}]+)\}'), (m) => '_(${m[1]})');

    // 3. معالجة الجذور والكسور
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\\sqrt{([^}]+)}'), (m) => 'sqrt(${m[1]})');
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\\frac{([^}]+)}{([^}]+)}'), (m) => '(${m[1]})/(${m[2]})');

    // 4. العمليات الأساسية
    cleanEq = cleanEq.replaceAll(RegExp(r'\\times'), '*');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\div'), '/');
    
    cleanEq = cleanEq.replaceAll(' ', ''); // remove spaces

    try {
      me.Parser p = me.Parser();
      me.Expression exp = p.parse(cleanEq);
      me.ContextModel cm = me.ContextModel();
      double eval = exp.evaluate(me.EvaluationType.REAL, cm);

      String resultStr;
      
      // تقريب الأرقام الكبيرة جداً أو الصغيرة جداً إلى صيغة علمية احترافية
      if (eval.abs() >= 100000 || (eval.abs() < 0.001 && eval != 0)) {
        String expStr = eval.toStringAsExponential(4); // e.g., "3.1250e9"
        expStr = expStr.replaceAll(RegExp(r'0+e'), 'e'); // remove trailing zeros in base
        expStr = expStr.replaceAll(RegExp(r'\.e'), 'e'); // clean dangling dot
        
        List<String> parts = expStr.split('e');
        if (parts.length == 2) {
          String base = parts[0];
          String exponent = parts[1];
          if (exponent.startsWith('+')) exponent = exponent.substring(1);
          resultStr = '$base \\times 10^{$exponent}';
        } else {
          resultStr = expStr;
        }
      } else {
        // الأرقام العادية: نحدد 4 مراتب عشرية كحد أقصى ثم نزيل الأصفار الزائدة
        resultStr = eval.toStringAsFixed(4);
        resultStr = resultStr.replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
      }

      // Auto-append the result to the controller
      final newText = '$currentText $resultStr';
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    } catch (e) {
      // Not a mathematically solvable equation (e.g., contains variables or text)
      // Do nothing, just leave the '=' there.
      return;
    }
  }

  void _insertAtCursor(String code, {int? cursorOffset}) {
    final ctrl = _textController;
    final selection = ctrl.selection;

    // إذا لم يكن هناك cursor، أضف للنهاية
    final base = selection.baseOffset < 0
        ? ctrl.text.length
        : selection.baseOffset.clamp(0, ctrl.text.length);
    final extent = selection.extentOffset < 0
        ? ctrl.text.length
        : selection.extentOffset.clamp(0, ctrl.text.length);

    final newText = ctrl.text.replaceRange(base, extent, code);

    final finalOffset = cursorOffset != null 
        ? base + cursorOffset 
        : base + code.length;

    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: finalOffset),
    );
  }

  OverlayEntry? _overlayEntry;

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _MathOverlayWidget(
          textController: _textController,
          onInsert: (code, [cursorOffset]) {
            _insertAtCursor(code, cursorOffset: cursorOffset);
            _focusNode.requestFocus();
          },
          onIncreaseSize: widget.onIncreaseSize,
          onDecreaseSize: widget.onDecreaseSize,
          onToggleBorder: widget.onToggleBorder,
          onToggleLatex: widget.onToggleLatex,
          showBorder: widget.showBorder,
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ✅ هذا هو الإصلاح: تصفير الإزاحة عند تحديث الودجت من الخارج
  @override
  void didUpdateWidget(DraggableTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // KEEP THE EXISTING DRAG OFFSET FIX:
    if (_dragOffset != Offset.zero) {
      _dragOffset = Offset.zero;
    }

    // NEW LOGIC FOR TEXT EDITING:
    if (widget.isEditing && !oldWidget.isEditing) {
      // Transitioning INTO editing mode
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_textController.text != widget.content) {
          _textController.text = widget.content;
        }
        // Move cursor to end
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        _focusNode.requestFocus();
        if (widget.isLatex) {
          _showOverlay();
        }
      });
    } else if (!widget.isEditing && oldWidget.isEditing) {
      // Transitioning OUT of editing mode — sync read-only display
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _removeOverlay();
        if (_textController.text != widget.content) {
          _textController.text = widget.content;
        }
      });
    } else if (!widget.isEditing && widget.content != oldWidget.content) {
      // Content updated from outside while not editing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_textController.text != widget.content) {
          _textController.text = widget.content;
        }
      });
    }

    if (widget.isEditing && oldWidget.isEditing) {
      if (widget.isLatex && !oldWidget.isLatex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showOverlay();
        });
      } else if (!widget.isLatex && oldWidget.isLatex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _removeOverlay();
        });
      } else if (widget.isLatex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _overlayEntry?.markNeedsBuild();
        });
      }
    }

    if (widget.attachedMediaUrl != oldWidget.attachedMediaUrl &&
        widget.attachedMediaUrl != _attachedMediaUrl) {
      _attachedMediaUrl = widget.attachedMediaUrl;
    }

    if (widget.mediaHeight != oldWidget.mediaHeight &&
        widget.mediaHeight != _mediaHeight) {
      _mediaHeight = widget.mediaHeight ?? 150.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // تحديد لون الخلفية والإطار
    final effectiveBgColor = widget.bgColor;
    final effectiveBorderColor = widget.showBorder
        ? widget.borderColor
        : Colors.transparent;
    final effectiveShowBorder = widget.showBorder;

    // تحديد الـ TextStyle المشترك
    final displayIsArabic = _containsArabic(widget.content);
    final editingDirection = widget.isLatex
        ? TextDirection.ltr
        : _plainTextDirection(_textController.text);
    final displayDirection = widget.isLatex
        ? TextDirection.ltr
        : _plainTextDirection(widget.content);

    final sharedStyle = TextStyle(
      color: widget.color,
      fontSize: widget.fontSize * widget.scale,
      fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
      fontFamilyFallback: const [
        'NotoNaskhArabic',
        'Noto Naskh Arabic',
        'Noto Sans Arabic',
        'Amiri',
        'Segoe UI',
        'Tahoma',
        'Arial',
      ],
    );

    final editingStyle = sharedStyle.copyWith(
      fontFamily: widget.isLatex
          ? widget.fontFamily
          : _plainTextFontFamily(_textController.text),
    );
    final displayStyle = sharedStyle.copyWith(
      fontFamily: widget.isLatex
          ? widget.fontFamily
          : _plainTextFontFamily(widget.content),
    );

    // تجهيز قلب المحتوى (حقل تعديل أو نص عرض)
    Widget coreContent;

    Widget buildAttachmentPreview({required bool editable}) {
      final url = _attachedMediaUrl;
      if (url == null || url.isEmpty) return const SizedBox.shrink();

      // 1. Fix Caching: Strip dynamic tokens for a stable cache key
      final String stableCacheKey =
          url.contains('?') ? url.split('?').first : url;

      // 2. Fix Scaling: Multiply dimensions by widget.scale
      final double scaledHeight = _mediaHeight * widget.scale;
      final double scaledMinWidth = 220 * widget.scale;
      final double scaledMaxWidth =
          (MediaQuery.of(context).size.width * 0.8) * widget.scale;
      final double scaledBorderRadius = 10 * widget.scale;

      return Padding(
        padding: EdgeInsets.only(bottom: 8 * widget.scale),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(scaledBorderRadius),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: scaledMinWidth,
                  maxWidth: scaledMaxWidth,
                  maxHeight: scaledHeight,
                ),
                child: CachedNetworkImage(
                  imageUrl: url,
                  cacheKey: stableCacheKey, // Force stable disk cache
                  key: ValueKey('${stableCacheKey}_$_imageRetryCount'),
                  height: scaledHeight,
                  fit: BoxFit.contain,
                  placeholder:
                      (context, url) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                  errorWidget: (context, url, error) {
                    print('❌ [CachedNetworkImage] rendering failed: $error');
                    return Container(
                      height: 150 * widget.scale,
                      width: double.infinity,
                      color: Colors.grey.withOpacity(0.2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            color: Colors.redAccent,
                            size: 40 * widget.scale,
                          ),
                          SizedBox(height: 8 * widget.scale),
                          Text(
                            'فشل تحميل الصورة',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14 * widget.scale,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _imageRetryCount++),
                            icon: Icon(Icons.refresh, size: 16 * widget.scale),
                            label: Text(
                              'إعادة المحاولة',
                              style: TextStyle(fontSize: 12 * widget.scale),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            if (editable)
              Positioned(
                top: 6 * widget.scale,
                right: 6 * widget.scale,
                child: IconButton(
                  tooltip: 'إزالة الصورة',
                  icon: Icon(
                    Icons.cancel,
                    color: Colors.red,
                    size: 24 * widget.scale,
                  ),
                  onPressed: () {
                    _persistAttachmentUrl(null);
                    if (mounted) {
                      setState(() => _attachedMediaUrl = null);
                    }
                  },
                ),
              ),
          ],
        ),
      );
    }

    if (widget.isEditing) {
      // ── وضع التعديل: حقل نص مضمّن ──────────────────────────────────────
      coreContent = Directionality(
        textDirection: editingDirection,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              child: IntrinsicWidth(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  autofocus: true,
                  maxLines: null,
                  minLines: 1,
                  style: editingStyle,
                  textDirection: editingDirection,
                  textAlign: editingDirection == TextDirection.rtl
                      ? TextAlign.right
                      : TextAlign.left,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  contentInsertionConfiguration: ContentInsertionConfiguration(
                    allowedMimeTypes: const <String>['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
                    onContentInserted: (KeyboardInsertedContent content) async {
                      if (content.hasData) {
                        final bytes = content.data!;
                        setState(() => _isUploadingMedia = true);
                        try {
                          final storage = SupabaseStorageService();
                          String ext = '.png'; // Default
                          if (content.mimeType == 'image/jpeg') ext = '.jpg';
                          if (content.mimeType == 'image/gif') ext = '.gif';
                          if (content.mimeType == 'image/webp') ext = '.webp';
                          
                          final url = await storage.uploadBytes(bytes, ext);
                          if (url != null) {
                            _persistAttachmentUrl(url);
                            if (mounted) setState(() => _attachedMediaUrl = url);
                          }
                        } finally {
                          if (mounted) setState(() => _isUploadingMedia = false);
                        }
                      }
                    },
                  ),
                  onChanged: (val) {
                    _tryAutoSolveLatex(val);
                    // Re-evaluate direction while typing so mixed-language text feels natural.
                    setState(() {});
                  },
                  onSubmitted: (value) {
                    widget.onEditComplete(
                      value,
                      _attachedMediaUrl,
                      _mediaHeight,
                      null,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isUploadingMedia)
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'إرفاق صورة',
                    icon: const Icon(Icons.image_outlined, size: 20),
                    onPressed: _pickAndUploadImage,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    color: Colors.blueAccent,
                  ),
                IconButton(
                  tooltip: 'حفظ الملاحظة',
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  onPressed:
                      () => widget.onEditComplete(
                        _textController.text,
                        _attachedMediaUrl,
                        _mediaHeight,
                        null,
                      ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
            if (_attachedMediaUrl != null && _attachedMediaUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                "حجم الصورة",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              Slider(
                value: _mediaHeight,
                min: 50.0,
                max: 500.0,
                onChanged: (val) {
                  setState(() {
                    _mediaHeight = val;
                  });
                },
              ),
            ],
          ],
        ),
      );
    } else if (widget.isLatex) {
      // ── وضع العرض: لاتيكس ────────────────────────────────────────────────
      coreContent = Directionality(
        textDirection: TextDirection.ltr,
        child: Math.tex(
          widget.content,
          textStyle: sharedStyle.copyWith(fontFamily: widget.fontFamily),
        ),
      );
    } else {
      // ── وضع العرض: نص عادي ───────────────────────────────────────────────
      final displayText = _prepareDisplayText(
        widget.content,
        isArabic: displayIsArabic,
      );

      coreContent = Directionality(
        textDirection: displayDirection,
        child: Text(
          displayText,
          style: displayStyle,
          textDirection: displayDirection,
          textAlign: displayDirection == TextDirection.rtl
              ? TextAlign.right
              : TextAlign.left,
          locale: displayIsArabic ? const Locale('ar') : null,
          softWrap: true,
        ),
      );
    }

    // تغليف المحتوى الأساسي بالمربع ذو الحدود والخلفية
    final isDarkContext = Theme.of(context).brightness == Brightness.dark;

    final hasTextBubble = widget.isEditing || widget.content.trim().isNotEmpty;

    Widget boxedContent = hasTextBubble
        ? Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: widget.isEditing
                  ? (isDarkContext
                        ? const Color.fromARGB(255, 255, 255, 255)
                              .withOpacity(0.9)
                        : Colors.white.withOpacity(0.9))
                  : (effectiveBgColor == Colors.transparent
                        ? null
                        : effectiveBgColor),
              border: Border.all(
                color: widget.isEditing
                    ? Colors.blue.withOpacity(0.5) // إطار أزرق عند التعديل
                    : (effectiveShowBorder
                          ? effectiveBorderColor
                          : Colors.transparent),
                width: widget.isEditing ? 1.5 : (effectiveShowBorder ? 2 : 0),
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: widget.isEditing
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDarkContext ? 0.3 : 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: coreContent,
          )
        : const SizedBox.shrink();

    final bubbleChildren = <Widget>[];
    if ((_attachedMediaUrl ?? '').isNotEmpty) {
      bubbleChildren.add(buildAttachmentPreview(editable: widget.isEditing));
    }
    if (hasTextBubble) {
      bubbleChildren.add(boxedContent);
    }

    Widget finalContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: bubbleChildren,
    );

    if (widget.isEditing) {
      finalContent = TapRegion(
        groupId: 'text_editing_region',
        onTapOutside: (event) {
          widget.onEditComplete(
            _textController.text,
            _attachedMediaUrl,
            _mediaHeight,
            event,
          );
        },
        child: finalContent,
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      // التحديث أثناء السحب (Visual Feedback)
      onPanUpdate: widget.enableDrag
          ? (details) {
              setState(() {
                _dragOffset += details.delta;
              });
            }
          : null,
      // عند انتهاء السحب، نرسل القيمة النهائية
      onPanEnd: widget.enableDrag
          ? (details) {
              widget.onDragEnd(_dragOffset);
              // ⚠️ ملاحظة مهمة: لا نصفر _dragOffset هنا يدوياً
              // لأننا نعتمد على didUpdateWidget لتقوم بذلك بعد تحديث الأب
            }
          : null,
      child: Transform.translate(offset: _dragOffset, child: finalContent),
    );
  }
}

class _MathOverlayWidget extends StatelessWidget {
  final TextEditingController textController;
  final void Function(String code, [int? cursorOffset]) onInsert;
  final VoidCallback? onIncreaseSize;
  final VoidCallback? onDecreaseSize;
  final VoidCallback? onToggleBorder;
  final VoidCallback? onToggleLatex;
  final bool showBorder;

  const _MathOverlayWidget({
    required this.textController,
    required this.onInsert,
    this.onIncreaseSize,
    this.onDecreaseSize,
    this.onToggleBorder,
    this.onToggleLatex,
    required this.showBorder,
  });

  Widget _buildMathButton(BuildContext context, String tooltip, String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      left: 16,
      right: 16,
      child: SafeArea(
        child: TapRegion(
          groupId: 'text_editing_region',
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                    maxHeight: 220, // HARD CAP — prevents vertical explosion no matter what Math.tex does
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ─── 1. LIVE PREVIEW AREA (Top Section) ───
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: textController,
                        builder: (context, value, child) {
                          if (value.text.trim().isEmpty) return const SizedBox.shrink();
                          return Container(
                            constraints: const BoxConstraints(
                              minWidth: 150,
                              maxHeight: 80, // 🛡️ Absolute vertical cap. No explosions allowed.
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                                ),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: FittedBox( // 🪄 Prevents infinite constraint crashes & scales down long equations
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Math.tex(
                                  value.text,
                                  textStyle: TextStyle(
                                    fontSize: 28,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  onErrorFallback: (err) => Text(
                                    value.text,
                                    style: TextStyle(
                                      color: Colors.redAccent.withOpacity(0.8),
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      // ─── 2. BOTTOM AREA (Formatting + Math Tools) ───
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min, // SHRINK-WRAP THE ROW
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // COMPACT 2x2 FORMATTING GRID
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(LucideIcons.zoomIn, size: 18), onPressed: onIncreaseSize, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: Colors.blueAccent),
                                    IconButton(icon: const Icon(LucideIcons.zoomOut, size: 18), onPressed: onDecreaseSize, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: Colors.blueAccent),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: Icon(showBorder ? LucideIcons.checkSquare : LucideIcons.square, size: 18), onPressed: onToggleBorder, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: showBorder ? const Color(0xFF10B981) : Colors.blueAccent),
                                    IconButton(icon: const Icon(LucideIcons.messageSquare, size: 18), onPressed: onToggleLatex, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: const Color(0xFFEF4444)),
                                  ],
                                ),
                              ],
                            ),
                            
                            // SEPARATOR
                            Container(
                              width: 1,
                              height: 40,
                              color: isDark ? Colors.white24 : Colors.black12,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                            ),

                            // MATH BUTTONS
                            Flexible( // Allows scrolling only if it overflows
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min, // SHRINK-WRAP THE MATH BUTTONS
                                  children: [
                                    _buildMathButton(context, 'مالانهاية', '∞', () => onInsert('\\infty ', 7)),
                                    _buildMathButton(context, 'قوسين', '( )', () => onInsert('\\left(  \\right)', 7)),
                                    _buildMathButton(context, 'مجموع', '∑', () => onInsert('\\sum_{}^{} ', 6)),
                                    _buildMathButton(context, 'تكامل', '∫', () => onInsert('\\int_{}^{} ', 6)),
                                    _buildMathButton(context, 'أساس', 'x₂', () => onInsert('_{ }', 2)),
                                    _buildMathButton(context, 'أس', 'x²', () => onInsert('^{ }', 2)),
                                    _buildMathButton(context, 'جذر', '√', () => onInsert('\\sqrt{ }', 6)),
                                    _buildMathButton(context, 'كسر', 'x/y', () => onInsert('\\frac{ }{ }', 6)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
