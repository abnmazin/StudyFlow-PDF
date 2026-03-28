# دراسة استخراج تحسينات RAM والتفريغ في المشروع

تاريخ الاستخراج: 2026-03-28

## الهدف
هذا الملف يجمع كل ما يرتبط باستهلاك الذاكرة، التحسين، التفريغ، وتقليل الضغط أثناء الاستخدام.

تركيز خاص: ميزة التفريغ المرتبطة بالتمرير بين صفحات PDF.

---

## 1) ضبط كاش Flutter العام (Global Image Cache)
المصدر: `lib/main.dart`

```dart
// 🚀 OPTIMIZATION: منع استهلاك الرام العالي (ت    حديد الذاكرة بـ 50 ميجا)
PaintingBinding.instance.imageCache.maximumSizeBytes = 10 * 1024 * 1024;
PaintingBinding.instance.imageCache.maximumSize = 20;
```

الفائدة:
- وضع حد أعلى للصور المخزنة بالذاكرة لمنع التضخم.
- يخفف الذروة في RAM عند التنقل السريع بين الشاشات/العناصر المصورة.

---

## 2) ضبط كاش محرك PDF نفسه
المصدر: `lib/widgets/pdf_viewer_widget_w.dart`

```dart
params: PdfViewerParams(
  maxImageBytesCachedOnMemory: 40 * 1024 * 1024,
  maxScale: 4.0,
  minScale: 0.5,
  scrollByMouseWheel: 0.8,
  ...
)
```

الفائدة:
- تحديد سقف كاش صور الصفحات داخل pdfrx.
- يمنع نمو الذاكرة بشكل مفتوح مع الصفحات الثقيلة أو التكبير.

---

## 3) آلية التفريغ عند/بعد التمرير بين الصفحات (الأهم)
المصدر الأساسي: `lib/widgets/pdf_viewer_widget_w.dart` + `lib/widgets/pdf_viewer_widget_actions.dart`

### 3.1 تتبع التمرير وتراكم الصفحات
```dart
int _pagesSinceLastFlush = 0;
int _lastMemoryTrimAt = 0;
Timer? _scrollDebounce;
Timer? _scrollMaintenanceDebounce;
```

### 3.2 منطق onPageChanged
```dart
onPageChanged: (page) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final timeDiff = now - _lastTimestamp;
  final currentPage = page ?? _lastReportedPage;
  final int pagesPassed = (currentPage - _lastReportedPage).abs();

  if (pagesPassed > 0 && timeDiff > 0) {
    _pagesSinceLastFlush += pagesPassed;
  }

  _lastTimestamp = now;
  _lastReportedPage = currentPage;

  if (_scrollDebounce?.isActive ?? false) {
    _scrollDebounce!.cancel();
  }

  _scrollDebounce = Timer(const Duration(milliseconds: 300), () {
    if (mounted) {
      context.read<AppProvider>().updatePdfScroll(
        pdf.id,
        pageNumber: currentPage,
      );
    }
  });

  _schedulePostScrollMaintenance();
},
```

### 3.3 صيانة ما بعد التمرير (Debounced Maintenance)
```dart
void _schedulePostScrollMaintenance() {
  _scrollMaintenanceDebounce?.cancel();
  _scrollMaintenanceDebounce = Timer(const Duration(milliseconds: 900), () {
    if (!mounted) return;

    // Keep this conservative to prioritize smoothness over aggressive trimming.
    _maybeTrimWindowsMemory(minIntervalMs: 6000);
    _pagesSinceLastFlush = 0;
  });
}
```

### 3.4 Gate لمنع التفريغ المبالغ فيه
```dart
void _maybeTrimWindowsMemory({bool force = false, int minIntervalMs = 1800}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  if (!force && now - _lastMemoryTrimAt < minIntervalMs) {
    return;
  }
  _lastMemoryTrimAt = now;
  _trimWindowsMemory();
}
```

### 3.5 التفريغ الفعلي على Windows عبر FFI
المصدر: `lib/widgets/pdf_viewer_widget_actions.dart`

```dart
void _trimWindowsMemory() {
  if (!Platform.isWindows) return;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess = kernel32
        .lookupFunction<IntPtr Function(), int Function()>(
          'GetCurrentProcess',
        );
    final emptyWorkingSet = kernel32
        .lookupFunction<Bool Function(IntPtr), bool Function(int)>(
          'K32EmptyWorkingSet',
        );
    final handle = getCurrentProcess();
    emptyWorkingSet(handle);
  } catch (e) {
    debugPrint('Memory trim skipped: $e');
  }
}
```

### 3.6 كيف تعمل ميزة التفريغ أثناء التمرير (Flow)
1. المستخدم يتنقل بين الصفحات.
2. `onPageChanged` يجمع الإحصاء ويؤجل تحديث الحالة 300ms (Debounce).
3. بعد توقف/هدوء التمرير، `_schedulePostScrollMaintenance` يعمل بعد 900ms.
4. تُستدعى `_maybeTrimWindowsMemory` مع حد 6000ms لمنع التكرار العنيف.
5. على Windows يتم استدعاء `K32EmptyWorkingSet` لتقليل الـ Working Set.

الناتج:
- تجربة تمرير أنعم.
- تقليل ضغط RAM بعد موجات تمرير سريعة.
- منع التقطيع الناتج عن تنظيف عدواني متكرر.

---

## 4) إصلاح تسريب ذاكرة معروف في المستمعات (Listeners/Rebuild)
المصدر: `lib/widgets/pdf_viewer_widget_w.dart`

```dart
void _onControllerChanged() {
  // MEMORY FIX: Removed blind setState(() {}).
  // Firing setState on every scroll pixel causes a 1.5GB native memory leak.
}
```

الفكرة:
- تم إزالة `setState` على كل بيكسل تمرير (كان يسبب تضخمًا كبيرًا).

---

## 5) تنظيف الموارد عند الإغلاق (Dispose Hygiene)

### 5.1 في PDF Viewer
```dart
@override
void dispose() {
  _pdfController.removeListener(_onControllerChanged);
  _scrollDebounce?.cancel();
  _scrollMaintenanceDebounce?.cancel();
  _autoFitDebounce?.cancel();
  _searchFocusNode.dispose();
  _textSearcher?.dispose();
  _sessionSub?.cancel();
  _annotationsSub?.cancel();
  super.dispose();
}
```

### 5.2 في AI Chat داخل Right Panel
```dart
@override
void dispose() {
  _aiConversationRevision.removeListener(_onConversationRevisionChanged);
  _controller.dispose();
  _scrollController.dispose();
  super.dispose();
}
```

### 5.3 في خدمة الطباعة (تحرير مستندات PDF)
المصدر: `lib/services/print_service.dart`

```dart
source.dispose();
output.dispose();
```

الفائدة:
- منع تسرب الموارد الطويل الأمد من Controllers/Streams/PDF docs.

---

## 6) Debounce إضافي لتقليل الضغط (I/O + Sync)
المصدر: `lib/providers/app_state.dart`

```dart
void triggerDebouncedSync({bool silent = true}) {
  _syncDebounce?.cancel();
  _syncDebounce = Timer(const Duration(milliseconds: 1800), () {
    performBidirectionalSync(silent: silent);
  });
}
```

الفائدة:
- تقليل عمليات المزامنة المتكررة أثناء التفاعل السريع.
- تخفيف ضغط CPU/Network وبالتالي تقليل الضغط غير المباشر على RAM.

---

## 7) مراجع داخل المشروع مرتبطة بموضوع RAM
- `RAM_NAVIGATION_RESEARCH.md`
- `PRINT_ISSUE_REPORT.md`
- `GESTURE_PROBLEM_FOR_EXPERTS.md`

---

## 8) ملخص عملي سريع (Actionable)
1. أهم ميزة تفريغ الآن: `onPageChanged -> _schedulePostScrollMaintenance -> _maybeTrimWindowsMemory -> _trimWindowsMemory`.
2. الكاش مضبوط على مستويين: Flutter imageCache + pdfrx cache.
3. أقوى حماية من التسريب: إزالة setState لكل بيكسل + dispose/cancel شامل.
4. عند اختبار الأداء، راقب:
   - Working Set بعد تمرير سريع 20-50 صفحة.
   - زمن استجابة الصفحة بعد التوقف عن التمرير.
   - تكرار استدعاء trim (يجب أن يبقى محافظًا بسبب minInterval).

---

## 9) اقتراحات تطوير لاحقة
1. إضافة عداد Telemetry بسيط (debug only) لعدد مرات `K32EmptyWorkingSet`.
2. تفعيل trim استثنائي فقط عند تجاوز عتبة صفحات/ذاكرة معينة.
3. إضافة إعداد داخل Developer Mode للتحكم بـ:
   - `scrollMaintenanceDebounce`
   - `minIntervalMs`
   - `maxImageBytesCachedOnMemory`

هذا يساعد على ضبط التوازن بين السلاسة واستهلاك الذاكرة حسب الأجهزة.
