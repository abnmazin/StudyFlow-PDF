# 📄 تقرير مفصل: مشكلة لوحة المفاتيح في حقل إدراج الملاحظات النصية

**التاريخ:** 2026-05-12  
**الموضوع:** TextField في `DraggableTextWidget` يتعارض مع التنقل في PDF  
**الحالة:** تم التحليل (بدون حل)

---

## 1. وصف المشكلة

عند استخدام **ميزة إدراج ملاحظة نصية** (Text Note) داخل تطبيق StudyFlow، تظهر المشكلات التالية في حقل الكتابة:

1. **الضغط على Space** يقفز إلى الصفحة التالية في PDF بدلاً من إدخال مسافة في النص
2. **الأسهم (Arrow Keys)** تحرك الصفحة بدلاً من تحريك المؤشر داخل النص
3. **مفاتيح Backspace و Delete** قد لا تعمل بشكل صحيح

هذه المشكلة تجعل إدراج الملاحظات النصية شبه مستحيل لأن أي محاولة للكتابة تسبب تنقل غير مرغوب في PDF.

---

## 2. تحليل السبب الجذري

### 2.1. مشكلة التركيز المزدوج (Focus War)

يوجد **صراع بين طبقتين من التركيز** في الكود:

```
طبقة 1: CallbackShortcuts (على مستوى PDFViewerWidget)
  └── تعترض المفاتيح H, E, P, T, V (تم إصلاحها سابقاً بإضافة Ctrl)
  
طبقة 2: Focus with onKeyEvent (على مستوى PdfViewerCore)
  └── تتعامل مع Space عندما يكون keyboardLocked = true
  
طبقة 3: FocusNode + Focus wrapper (على مستوى DraggableTextWidget)
  └── المشكلة هنا: تعترض الأحداث قبل وصولها إلى TextField
```

### 2.2. الكود المسبب للمشكلة

الملف: `lib/widgets/draggable_text_widget.dart`

**المشكلة 1 - FocusNode مع onKeyEvent (سطر 148-166):**
```dart
_focusNode = FocusNode(
  onKeyEvent: (node, event) {
    // Only trap the Space key to prevent PDF scrolling
    if (event.logicalKey == LogicalKeyboardKey.space) {
      return KeyEventResult.skipRemainingHandlers;
    }
    // Let all other keys pass through normally
    return KeyEventResult.ignored;
  },
);
```
هذا الكود يقول لـ Flutter "إذا كان المفتاح Space، فتجاوز المعالجة الافتراضية". ولكن `skipRemainingHandlers` يمنع `TextField` من استقبال الحدث أصلاً.

**المشكلة 2 - Focus wrapper حول TextField (سطر 665-669):**
```dart
child: Focus(
  onKeyEvent: (node, event) {
    return KeyEventResult.skipRemainingHandlers;
  },
  child: TextField(...),
),
```
هذا الغلاف `Focus` يعترض **جميع** أحداث لوحة المفاتيح (`skipRemainingHandlers`) ويمنعها من الوصول إلى `TextField`. حتى الأسهم و Backspace و Delete لا تصل.

**المشكلة 3 - EnableKeyboardNavigation في PdfViewer (سطر 1712-1715):**
```dart
enableKeyboardNavigation:
    showOverlays &&
    _editingCommentId == null &&
    !_isSearchVisible,
```
عندما يكون `_editingCommentId != null` (أي في وضع التعديل)، يتم تعطيل التنقل بلوحة المفاتيح. ولكن هذا لا يكفي لأن `enableKeyboardNavigation` يتحكم فقط بالأسهم في PDF Viewer نفسه، ولا يمنع Space.

**المشكلة 4 - setKeyboardLock فقط للـ Space (سطر 1686-1693):**
```dart
onKeyEvent: (node, event) {
  if (app.isKeyboardLocked && 
      event.logicalKey == LogicalKeyboardKey.space) {
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
},
```
هذا يتعامل مع Space فقط ولا يغطي الأسهم.

---

## 3. هيكل تدفق الأحداث الحالي

```
ضغط زر Space:
  └── CallbackShortcuts يتحقق من الاختصارات (لا يوجد تطابق)
  └── Focus (PDFViewer Widget Level)
      └── isKeyboardLocked == true && Space → Handled (يمنع PDF من التمرير)
  └── Focus (PdfViewerCore Level) 
      └── isKeyboardLocked == true && Space → Handled (يمنع PDF من التمرير)
  └── FocusNode (DraggableTextWidget Level)
      └── skipRemainingHandlers (يمنع TextField من رؤيته)
  ➡️ Space لا يصل إلى TextField أبداً!

ضغط سهم (Arrow):
  └── CallbackShortcuts يتحقق من الاختصارات (لا يوجد تطابق)
  └── Focus (PDFViewer Widget Level)
      └── isKeyboardLocked == true → Ignored (يمر للأعلى)
  └── Focus (PdfViewerCore Level)
      └── isKeyboardLocked == true → Ignored (يمر للأعلى)
  └── FocusNode (DraggableTextWidget Level)
      └── ignored (يمر للأعلى)
  └── PdfViewer.enableKeyboardNavigation == true
      └── ← السهم يغير الصفحة بدلاً من تحريك المؤشر!
```

---

## 4. الكود الكامل المعني بالمشكلة

### 4.1. DraggableTextWidget (ملف النص الأساسي)

```dart
// lib/widgets/draggable_text_widget.dart

// ─── FocusNode في initState (سطر 148-166) ───
_focusNode = FocusNode(
  onKeyEvent: (node, event) {
    // فقط Space محجوز
    if (event.logicalKey == LogicalKeyboardKey.space) {
      return KeyEventResult.skipRemainingHandlers;
    }
    return KeyEventResult.ignored;
  },
);

// يرتبط keyboardLock مع حالة التركيز
_focusNode.addListener(() {
  if (mounted) {
    context.read<AppProvider>().setKeyboardLock(_focusNode.hasFocus);
  }
});

// ─── Focus wrapper حول TextField في build (سطر 665-669) ───
child: Focus(
  onKeyEvent: (node, event) {
    return KeyEventResult.skipRemainingHandlers; // ← يمنع كل الأحداث!
  },
  child: TextField(
    controller: _textController,
    focusNode: _focusNode,
    ...
  ),
),
```

### 4.2. PdfViewerWidget (ملف المشاهد)

```dart
// lib/widgets/pdf_viewer_widget_w.dart

// ─── Focus على مستوى PDFViewerWidget (سطر ~1100) ───
onKeyEvent: (node, event) {
  if (app.isKeyboardLocked) return KeyEventResult.ignored;
  return KeyEventResult.ignored;
},

// ─── Focus على مستوى PdfViewerCore (سطر 1686-1693) ───
onKeyEvent: (node, event) {
  if (app.isKeyboardLocked && 
      event.logicalKey == LogicalKeyboardKey.space) {
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
},

// ─── enableKeyboardNavigation (سطر 1712-1715) ───
enableKeyboardNavigation:
    showOverlays &&
    _editingCommentId == null &&
    !_isSearchVisible,
```

### 4.3. AppProvider (ملف الحالة)

```dart
// lib/providers/app_state.dart

bool _isKeyboardLocked = false;
bool get isKeyboardLocked => _isKeyboardLocked;

void setKeyboardLock(bool isLocked) {
  if (_isKeyboardLocked != isLocked) {
    _isKeyboardLocked = isLocked;
    notifyListeners();
  }
}
```

---

## 5. تحليل الطبقات المتداخلة

```
PDFViewerWidget
  └── AnimatedBuilder
      └── CallbackShortcuts (اختصارات H, E, P, T, V مع Ctrl)
          └── Focus (1)
              ├── onKeyEvent: يعيد ignored عندما keyboardLocked=true
              │
              └── Column
                  ├── Toolbar
                  └── Expanded
                      └── Row
                          └── Viewer Area
                              └── Stack
                                  └── PdfViewerCore
                                      └── Listener
                                          └── Focus (2)
                                              ├── onKeyEvent: Space → handled
                                              │   (عند keyboardLocked=true)
                                              └── PdfViewer.file
                                                  └── pageOverlaysBuilder
                                                      └── DraggableTextWidget
                                                          └── GestureDetector
                                                              └── TapRegion
                                                                  └── Column
                                                                      └── ConstrainedBox
                                                                          └── IntrinsicWidth
                                                                              └── Focus (3) <--- المشكلة هنا
                                                                                  └── onKeyEvent: skipRemainingHandlers
                                                                                  └── TextField
                                                                                      └── focusNode: FocusNode (مع onKeyEvent)
```

## 6. ملخص المشاكل

| المشكلة | المكان | التأثير |
|---------|--------|---------|
| `Focus` حول `TextField` يمنع كل الأحداث | سطر 665-669 | الأسهم، Backspace، Delete، Space لا تعمل |
| `FocusNode` يحجز Space ولا يمرره | سطر 151-155 | Space لا يصل إلى TextField أبداً |
| PdfViewer Core يمسك Space عندما keyboardLocked | سطر 1689-1690 | صحيح، هذا مطلوب لمنع PDF من التمرير |
| PdfViewer ما يمسك الأسهم عندما keyboardLocked | سطر 1692 | الأسهم تفلت وتصل إلى PDF Viewer فتغير الصفحة |

## 7. خريطة تدفق الحل

```
الحل المثالي:
  Focus (1) level: keyboardLocked → ignore ALL events (Space + Arrows)
  Focus (2) level: keyboardLocked → ignore ALL events (Space + Arrows)  
  Focus (3) level: يجب إزالة هذا الغلاف بالكامل
  FocusNode: يجب إزالة onKeyEvent (space trap)
  
  بهذا يصبح TextField طبيعياً 100%:
  - Space يكتب مسافة ✓
  - الأسهم تحرك المؤشر ✓
  - Backspace يمسح ✓
  - PDF لا يتأثر لأن keyboardLocked يمنع الأحداث من الوصول إليه ✓
```

---

## 8. المواقع المتأثرة

- `lib/widgets/draggable_text_widget.dart` (الملف الرئيسي)
- `lib/widgets/pdf_viewer_widget_w.dart` (يحتوي على Focus للـ PDF)
- `lib/providers/app_state.dart` (يدير حالة keyboardLocked)
- `lib/services/hardware_service.dart` (غير مرتبط)
- `lib/services/university_service.dart` (غير مرتبط)

---

## 9. الخلاصة

المشكلة الأساسية هي وجود **طبقة Focus زائدة** حول `TextField` في `DraggableTextWidget` تمنع وصول أحداث لوحة المفاتيح إلى النص. هذه الطبقة كانت مخصصة لمنع Space من تحريك PDF، ولكن بما أن `keyboardLocked` (الذي يتحكم فيه `AppProvider`) يقوم أصلاً بهذه المهمة على مستوى أعلى، فإن هذه الطبقة الإضافية تصبح غير ضرورية وتسبب أعطالاً في الكتابة.

بالإضافة إلى ذلك، مستوى `PdfViewerCore` لا يتعامل إلا مع Space عند `keyboardLocked=true` ويتجاهل الأسهم، مما يسمح للأسهم بالوصول إلى `PdfViewer` وتغيير الصفحة.

**الحل المقترح:** إزالة `Focus` الزائد حول `TextField` وإزالة `onKeyEvent` من `FocusNode`، مع ضمان أن `PdfViewerCore` يتجاهل جميع الأحداث (وليس فقط Space) عندما يكون `keyboardLocked=true`.

---

## End of Report