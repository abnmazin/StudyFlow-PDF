<div align="center">
  <img src="https://img.shields.io/badge/Flutter-3.10+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.10-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" alt="Firebase" />
  <img src="https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/Isar_DB-4A90D9?style=for-the-badge&logo=database&logoColor=white" alt="Isar DB" />
  <img src="https://img.shields.io/badge/Gemini_AI-8E75FF?style=for-the-badge&logo=google&logoColor=white" alt="Gemini AI" />
</div>

<br />

<h1 align="center">📚 StudyFlow PDF</h1>
<p align="center">
  <b>منصة دراسية ذكية متكاملة لإدارة وقراءة وتحليل ملفات PDF مع أدوات تعليمية وتواصل لحظي</b>
</p>

<p align="center">
  <i>An intelligent, all-in-one study platform for PDF management, reading, analysis, and real-time collaboration.</i>
</p>

---

## 📖 About The Project

**StudyFlow PDF** هو تطبيق متعدد المنصات (Windows, macOS, Linux, Android, iOS, Web) صُمم لإعادة تعريف تجربة الدراسة الأكاديمية. يدمج التطبيق بين **قارئ PDF احترافي** مع أدوات تعليق توضيحي متقدمة، ومحرك **رياضيات ذكي** (تفاضل، تكامل، معادلات)، و**مترجم فوري مدعوم بالذكاء الاصطناعي**، ونظام **مكتبة سحابية جامعية**، وجلسات **مزامنة تفاعلية** بين الطلاب.

المشكلة التي يحلها التطبيق هي **تشتت الأدوات** التي يحتاجها الطالب أثناء الدراسة بين قارئ PDF، وآلة حاسبة، ومترجم، ودفتر ملاحظات، ونظام إدارة ملفات. StudyFlow يجمّع كل هذا في **منصة واحدة متماسكة** مع تجربة مستخدم عربية متكاملة وتصميم أنيق.

---

## ✨ Key Features

- **📄 قارئ PDF متقدم** — عرض سريع للصفحات، دعم البحث، التكبير والتصغير، وعرض بنية المستند مع فهرسة تلقائية للمحتويات
- **🖍️ أدوات التعليق والتظليل** — تظليل النصوص بألوان متعددة، إضافة تعليقات وإشارات مرجعية (Bookmarks) مع حفظ تلقائي عبر Isar DB
- **🧮 محرك رياضيات ذكي** — حل التفاضل والتكامل والمعادلات خطوة بخطوة باستخدام محرك Dart خاص مع دعم Python/SymPy كخيار إضافي
- **🤖 ترجمة ذكية فورية** — ترجمة النصوص داخل PDF باستخدام Gemini AI (مع fallback لـ Groq و Google Translate)
- **☁️ المكتبة الجامعية السحابية** — مستودع مركزي للملفات الدراسية مع رفع وتصنيف حسب الجامعة/المادة، وتفادي التكرار عبر SHA‑256
- **👥 جلسات الدراسة التفاعلية** — مزامنة لحظية عبر Firestore لتجربة دراسة جماعية مع تحديث آني للصفحات والملاحظات
- **🖨️ طباعة احترافية** — طباعة كاملة مع دمج التعليقات والتظليل في المخرجات، وتحكم بتنسيق الصفحات
- **🔐 نظام مصادقة صارم** — تسجيل دخول مقيد بالجهاز عبر بصمة أجهزة متعددة المستويات (Hardware Fingerprinting) مع حظر الحسابات المخالفة
- **🧩 تطبيقات مصغرة (Mini Apps)** — آلة حاسبة علمية، مترجم، محول طاقة، حاسبة مصفوفات — كلها داخل المشروع نفسه
- **📂 إدارة ذكية للملفات** — تنظيم تلقائي في مجلدات حسب المادة، حفظ الصفحات المفتوحة، وعرض مصغر (Thumbnails) بفضل Isar DB

---

## 🛠️ Tech Stack

| الطبقة | التقنيات |
|--------|----------|
| **Frontend** | ![Flutter](https://img.shields.io/badge/Flutter-3.10-02569B?logo=flutter) ![Dart](https://img.shields.io/badge/Dart-3.10-0175C2?logo=dart) |
| **State Management** | ![Provider](https://img.shields.io/badge/Provider-6.x-764ABC?logo=flutter) |
| **Local Database** | ![Isar DB](https://img.shields.io/badge/Isar_DB-3.x-4A90D9?logo=database) |
| **Authentication** | ![Firebase Auth](https://img.shields.io/badge/Firebase_Auth-FFCA28?logo=firebase) |
| **Cloud Database** | ![Cloud Firestore](https://img.shields.io/badge/Firestore-FFCA28?logo=firebase) |
| **Cloud Storage** | ![Supabase Storage](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase) |
| **AI / Translation** | ![Gemini](https://img.shields.io/badge/Gemini_AI-8E75FF?logo=google) ![Groq](https://img.shields.io/badge/Groq_(Llama)-F97316?logo=llama) |
| **PDF Engine** | ![pdfrx](https://img.shields.io/badge/pdfrx-2.x-lightgrey) ![Syncfusion](https://img.shields.io/badge/Syncfusion_PDF-B71C1C) |
| **Additional** | ![printing](https://img.shields.io/badge/printing-5.x-blue) ![file_picker](https://img.shields.io/badge/file__picker-10.x-success) ![flutter_math_fork](https://img.shields.io/badge/flutter__math__fork-0.7-important) |

---

## 🏗️ System Architecture / How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                       UI Layer (Flutter)                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐ │
│  │ PDF       │  │ Mini     │  │ Auth /   │  │ University │ │
│  │ Viewer    │  │ Apps     │  │ Profile  │  │ Library    │ │
│  └─────┬─────┘  └──────────┘  └────┬─────┘  └──────┬──────┘ │
└────────┼────────────────────────────┼───────────────┼────────┘
         │                            │               │
┌────────▼────────────────────────────▼───────────────▼────────┐
│                    State Management (Provider)                │
│  ┌──────────────────────── AppProvider ─────────────────────┐ │
│  │  PDF State  │  Auth State  │  Sync State  │  File State │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────┬────────────────────────────┬───────────────┬────────┘
         │                            │               │
┌────────▼──────────┐  ┌─────────────▼──────────┐ ┌──▼────────┐
│   Services Layer  │  │   Cloud Layer           │ │   Local   │
│  ┌──────────────┐ │  │  ┌───────────────────┐  │ │   Layer   │
│  │ Math Engine  │ │  │  │ Firebase Auth     │  │ │ ┌───────┐ │
│  │ Translation  │ │  │  │ Firestore (Sync)  │  │ │ │Isar  │ │
│  │ File Manager │ │  │  │ Supabase Storage  │  │ │ │  DB  │ │
│  │ Print Engine │ │  │  │ Gemini / Groq AI  │  │ │ └───────┘ │
│  │ PDF Mutation │ │  │  └───────────────────┘  │ │         │
│  └──────────────┘ │  └─────────────────────────┘ │         │
└───────────────────┘                              └─────────┘
```

### آلية العمل الأساسية

1. **المصادقة** — يتم تسجيل الدخول عبر Firebase Auth مع ربط الجهاز ببصمة فريدة (CPU, GPU, MAC, Disk, BIOS) لمنع الاختراق.
2. **إدارة الملفات** — الملفات تُخزّن محلياً في Isar DB مع فهرسة كاملة، ويتم رفعها إلى Supabase عند الحاجة للمشاركة أو السحابة الجامعية.
3. **قراءة PDF** — يُعرض PDF عبر `pdfrx` مع طبقة CustomPainter للتعليقات، وتُحفظ التعديلات لحظياً في Isar.
4. **المزامنة** — عند الدخول في جلسة دراسية، تتم مزامنة الصفحة الحالية، التعليقات، والتظليل عبر Firestore في الوقت الفعلي.
5. **الذكاء الاصطناعي** — الترجمة تتم عبر Gemini API مع نظام fallback ذكي ينتقل تلقائياً لـ Groq ثم Google Translate عند انقطاع الخدمة.
6. **محرك الرياضيات** — يحل المعادلات والتعابير الرياضية محلياً دون اتصال بالإنترنت باستخدام Dart pure.

---

## 📸 Screenshots / Demo

> *(قم باستبدال عناصر placeholder هذه بصور حقيقية)*

| الواجهة | المعاينة |
|---------|----------|
| **شاشة تسجيل الدخول** | `[📱 صورة شاشة تسجيل الدخول]` |
| **عارض PDF مع التعليقات** | `[📄 صورة واجهة قراءة PDF مع تظليل وتعليقات]` |
| **الشريط الجانبي للمجلدات** | `[📂 صورة الشريط الجانبي مع تصنيف المواد]` |
| **المكتبة الجامعية السحابية** | `[☁️ صورة المكتبة الجامعية مع الملفات]` |
| **جلسة الدراسة التفاعلية** | `[👥 صورة جلسة مزامنة مع مستخدمين متعددين]` |
| **الآلة الحاسبة العلمية** | `[🧮 صورة الحاسبة مع تفاضل وتكامل]` |
| **مترجم الذكاء الاصطناعي** | `[🤖 صورة واجهة الترجمة مع النتائج]` |
| **نافذة الإعدادات** | `[⚙️ صورة الإعدادات العامة]` |

---

## 🔗 Links

| الرابط | الوصف |
|--------|-------|
| `[🎨 رابط تصميم Figma]` | النماذج الأولية وتصميم واجهات المستخدم |
| `[🌐 رابط المنصة المباشرة]` | الإصدار التجريبي من التطبيق (إن وجد) |
| `[📹 فيديو توضيحي]` | شرح مختصر لميزات التطبيق |

---

<div align="center">
  <sub>بُني بـ ❤️ باستخدام Flutter و Dart | <b>StudyFlow PDF</b> © 2026</sub>
  <br />
  <sub>Built with ❤️ using Flutter & Dart | <b>StudyFlow PDF</b> © 2026</sub>
</div>
