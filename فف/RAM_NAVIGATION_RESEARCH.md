# بحث: استخدام الذاكرة RAM عند الانتقال بين الصفحات

تاريخ الفحص: 2026-03-27

## النتيجة المختصرة

نعم، المشروع يستفيد من الذاكرة RAM أثناء التنقل، ولكن ليس عبر `PageStorage` أو `AutomaticKeepAliveClientMixin`.

الاستفادة الأساسية تتم عبر:

- حالة عامة في الذاكرة باستخدام `Provider` (`AppProvider`) على مستوى التطبيق.
- إبقاء Widgets حيّة داخل نفس الشاشة عبر `IndexedStack`.
- كاش الصور `imageCache` (مع حدود مضبوطة لتقليل استهلاك RAM).
- دعم إضافي عبر `SharedPreferences` لحفظ الحالة عند إعادة تشغيل التطبيق (ليس RAM فقط، بل تخزين محلي دائم).

## أدلة من الكود

1. مزود حالة عام (In-Memory State)
- في `main.dart` يتم إنشاء `ChangeNotifierProvider(create: (_) => AppProvider())` داخل `MultiProvider`.
- هذا يعني أن حالة `AppProvider` تبقى موجودة في RAM طوال عمر التطبيق، ولا تضيع عند `pushReplacement` بين `LoginScreen` و `MainLayout`.

2. التنقل بين الشاشات
- من شاشة الدخول يتم `pushReplacement` إلى `MainLayout`.
- عند تسجيل الخروج/الحذف يتم `pushAndRemoveUntil` إلى `LoginScreen`.
- لأن `AppProvider` موجود أعلى الشجرة (تحت `MaterialApp` مباشرة)، الحالة المشتركة تستمر غالبًا أثناء التنقل العادي.

3. حفظ التبويبات داخليًا عبر `IndexedStack`
- في اللوحة اليمنى (`viewer_right_panel.dart`) يوجد `IndexedStack` للتبويبات.
- هذا يحافظ على حالة كل تبويب في RAM بدل إعادة بنائه كل مرة عند تغيير التبويب.

4. كاش الصور في RAM
- في `main.dart`:
	- `PaintingBinding.instance.imageCache.maximumSizeBytes = 10 * 1024 * 1024;`
	- `PaintingBinding.instance.imageCache.maximumSize = 20;`
- هذا كاش RAM مقصود لتحسين الأداء مع حد أقصى لمنع التضخم.

5. تكامل RAM + تخزين دائم
- `AppProvider` يحمل بيانات مثل `classes`, `activeClassId`, `activePdfId` داخل الذاكرة.
- نفس الحالة يتم تحميلها/حفظها عبر `SharedPreferences` في `_loadState()` و `_saveState()`.
- النتيجة: سرعة أثناء التشغيل (RAM) + استمرارية بعد إغلاق التطبيق (Disk).

## ما لم أجده

- لا يوجد استخدام لـ `PageStorage`.
- لا يوجد استخدام لـ `AutomaticKeepAliveClientMixin`.
- لا يوجد استخدام لـ `RestorationMixin` في ملفات `app/lib`.

## تقييم عملي

التصميم الحالي جيد لفكرة "الاستفادة من RAM أثناء الانتقال بين الصفحات" لأنه يعتمد على `Provider` + `IndexedStack`.

لكن لو الهدف هو الحفاظ على حالة صفحات منفصلة في Navigator عميق (مثلا Tabs مستقلة لكل route)، يمكن إضافة:

- `PageStorageKey` لبعض القوائم/التمرير.
- `AutomaticKeepAliveClientMixin` لبعض الشاشات الثقيلة داخل `TabBarView`.
- أو `RestorationMixin` إذا أردت استرجاعًا أدق بعد قتل التطبيق من النظام.

