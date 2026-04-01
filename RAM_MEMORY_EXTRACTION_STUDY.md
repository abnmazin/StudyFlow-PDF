# شجرة البرنامج - فهرس الدوال (Function Tree)

> هذا الملف فهرس تنفيذي مباشر للدوال داخل سورس التطبيق (استبعاد الملفات المولدة تلقائيا).
> أي أمر تريد تنفذه: ابحث باسم الدالة، ستجد الملف + رقم السطر + وصف سريع للشغل.

## قواعد هذا الفهرس
- يشمل ملفات lib/*.dart الحقيقية فقط (بدون .g.dart و .freezed.dart).
- الوصف وظيفي سريع حسب اسم الدالة لتسريع الوصول.
- إذا تغيّر الكود، حدّث هذا الملف بإعادة توليد الفهرس.

## الشجرة حسب الملفات
### lib/firebase_options.dart
- دور الملف: وحدة عامة
- L34: _require() - وظيفة تشغيلية داخل الوحدة
- L42: _optional() - وظيفة تشغيلية داخل الوحدة

### lib/main.dart
- دور الملف: نقطة تشغيل التطبيق وتهيئة عامة
- L28: _extractPdfPathFromArgs() - وظيفة تشغيلية داخل الوحدة
- L57: _sendPdfToRunningInstance() - وظيفة تشغيلية داخل الوحدة
- L58: tryAddress() - وظيفة تشغيلية داخل الوحدة
- L106: _startSingleInstanceServer() - وظيفة تشغيلية داخل الوحدة
- L141: main() - وظيفة تشغيلية داخل الوحدة
- L187: build() - بناء واجهة المستخدم
- L242: build() - بناء واجهة المستخدم
- L304: createState() - إنشاء/بدء عملية
- L312: _handleDroppedFiles() - وظيفة تشغيلية داخل الوحدة
- L328: initState() - تهيئة/إعداد
- L360: dispose() - تحرير موارد/تنظيف
- L366: _securityListener() - وظيفة تشغيلية داخل الوحدة
- L409: build() - بناء واجهة المستخدم

### lib/models/annotations.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L43: toJson() - وظيفة تشغيلية داخل الوحدة
- L145: toJson() - وظيفة تشغيلية داخل الوحدة
- L229: toJson() - وظيفة تشغيلية داخل الوحدة

### lib/models/app_user.dart
- دور الملف: وحدة عامة
- L45: toJson() - وظيفة تشغيلية داخل الوحدة

### lib/models/enums.dart
- دور الملف: وحدة عامة
- L15: isDrawingTool() - تحقق/قرار منطقي
- L27: isSelectionTool() - تحقق/قرار منطقي
- L31: isHandTool() - تحقق/قرار منطقي

### lib/models/isar_models.dart
- دور الملف: وحدة عامة
- لا توجد دوال معرفة مباشرة أو الملف يحتوي تعريفات/ثوابت فقط.

### lib/models/models.dart
- دور الملف: وحدة عامة
- لا توجد دوال معرفة مباشرة أو الملف يحتوي تعريفات/ثوابت فقط.

### lib/models/print_settings.dart
- دور الملف: الطباعة ومعالجة الإخراج
- لا توجد دوال معرفة مباشرة أو الملف يحتوي تعريفات/ثوابت فقط.

### lib/models/structure.dart
- دور الملف: وحدة عامة
- L64: toJson() - وظيفة تشغيلية داخل الوحدة
- L116: toJson() - وظيفة تشغيلية داخل الوحدة

### lib/painters/highlight_painter.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L22: _calculateHighlightsHash() - وظيفة تشغيلية داخل الوحدة
- L29: paint() - وظيفة تشغيلية داخل الوحدة
- L109: _drawSelectedHighlightOverlay() - وظيفة تشغيلية داخل الوحدة
- L143: _boundsForHighlight() - وظيفة تشغيلية داخل الوحدة
- L291: _drawSelectionHandles() - وظيفة تشغيلية داخل الوحدة
- L315: shouldRepaint() - تحقق/قرار منطقي
- L353: _pathsAreEqual() - وظيفة تشغيلية داخل الوحدة

### lib/providers/app_state.dart
- دور الملف: وحدة عامة
- L59: toLegacyString() - وظيفة تشغيلية داخل الوحدة
- L83: _initConnectivity() - وظيفة تشغيلية داخل الوحدة
- L97: dispose() - تحرير موارد/تنظيف
- L167: isAnnouncementHidden() - تحقق/قرار منطقي
- L168: hideAnnouncementLocally() - وظيفة تشغيلية داخل الوحدة
- L176: _markPdfDirty() - وظيفة تشغيلية داخل الوحدة
- L187: setDrawingSyncStrategy() - تحديث/حفظ بيانات
- L222: triggerSync() - وظيفة تشغيلية داخل الوحدة
- L228: performBidirectionalSync() - وظيفة تشغيلية داخل الوحدة
- L393: triggerDebouncedSync() - وظيفة تشغيلية داخل الوحدة
- L402: cancelDebouncedSync() - إيقاف/إغلاق عملية
- L406: _markUnsavedChanges() - وظيفة تشغيلية داخل الوحدة
- L410: setCurrentTool() - تحديث/حفظ بيانات
- L423: _triggerSync() - وظيفة تشغيلية داخل الوحدة
- L432: _notify() - وظيفة تشغيلية داخل الوحدة
- L447: didChangeAppLifecycleState() - وظيفة تشغيلية داخل الوحدة
- L458: _pauseAllListeners() - وظيفة تشغيلية داخل الوحدة
- L466: _resumeAllListeners() - وظيفة تشغيلية داخل الوحدة
- L560: _findPdfById() - وظيفة تشغيلية داخل الوحدة
- L571: _initialize() - وظيفة تشغيلية داخل الوحدة
- L630: verifyAccountStatusSilently() - تحقق/قرار منطقي
- L667: clearForcedLogoutReason() - وظيفة تشغيلية داخل الوحدة
- L674: _startUserMonitor() - وظيفة تشغيلية داخل الوحدة
- L698: _stopUserMonitor() - وظيفة تشغيلية داخل الوحدة
- L703: toggleSettings() - وظيفة تشغيلية داخل الوحدة
- L708: setCurrentUser() - تحديث/حفظ بيانات
- L720: _preloadLecturerSessions() - وظيفة تشغيلية داخل الوحدة
- L749: setSessionCode() - تحديث/حفظ بيانات
- L771: linkMasterBundle() - وظيفة تشغيلية داخل الوحدة
- L810: logout() - إيقاف/إغلاق عملية
- L822: setSessionLocked() - تحديث/حفظ بيانات
- L827: setSessionJoinLocked() - تحديث/حفظ بيانات
- L834: _startKickListener() - وظيفة تشغيلية داخل الوحدة
- L907: _stopKickListener() - وظيفة تشغيلية داخل الوحدة
- L912: _handleForceLogout() - وظيفة تشغيلية داخل الوحدة
- L950: clearUnsyncedAnnotationsForActivePdf() - وظيفة تشغيلية داخل الوحدة
- L979: syncFromFirestore() - مزامنة/شبكة
- L1045: _loadState() - وظيفة تشغيلية داخل الوحدة
- L1151: _migrateLegacyLibraryIfNeeded() - وظيفة تشغيلية داخل الوحدة
- L1171: _hydrateClassesFromIsar() - وظيفة تشغيلية داخل الوحدة
- L1351: _migrateAnnotationsIfNeeded() - وظيفة تشغيلية داخل الوحدة
- L1378: _loadAnnotations() - وظيفة تشغيلية داخل الوحدة
- L1426: _saveAnnotations() - وظيفة تشغيلية داخل الوحدة
- L1452: _cleanupTempFiles() - وظيفة تشغيلية داخل الوحدة
- L1496: _saveState() - وظيفة تشغيلية داخل الوحدة
- L1562: toggleMobile() - وظيفة تشغيلية داخل الوحدة
- L1567: toggleDevInfo() - وظيفة تشغيلية داخل الوحدة
- L1572: toggleSidebar() - وظيفة تشغيلية داخل الوحدة
- L1577: toggleDarkMode() - وظيفة تشغيلية داخل الوحدة
- L1585: setAiProvider() - تحديث/حفظ بيانات
- L1592: setGeminiModel() - تحديث/حفظ بيانات
- L1598: setGroqModel() - تحديث/حفظ بيانات
- L1604: setGeminiApiKey() - تحديث/حفظ بيانات
- L1610: setGroqApiKey() - تحديث/حفظ بيانات
- L1616: _persistAiSettings() - وظيفة تشغيلية داخل الوحدة
- L1626: setActiveClass() - تحديث/حفظ بيانات
- L1652: setActivePdf() - تحديث/حفظ بيانات
- L1714: _updateImageCacheGovernance() - وظيفة تشغيلية داخل الوحدة
- L1733: joinSession() - إنشاء/بدء عملية
- L1808: loadPdfFromPath() - جلب/قراءة بيانات
- L1854: addClass() - إنشاء/بدء عملية
- L1872: reorderClasses() - وظيفة تشغيلية داخل الوحدة
- L1892: uploadPdf() - مزامنة/شبكة
- L1919: addHighlight() - إنشاء/بدء عملية
- L1980: removeHighlight() - حذف بيانات/عنصر
- L2008: removeHighlightById() - حذف بيانات/عنصر
- L2023: addComment() - إنشاء/بدء عملية
- L2056: removeComment() - حذف بيانات/عنصر
- L2084: removeCommentById() - حذف بيانات/عنصر
- L2099: clearAllAnnotations() - وظيفة تشغيلية داخل الوحدة
- L2125: clearAllGlobalAnnotations() - وظيفة تشغيلية داخل الوحدة
- L2144: clearAllHighlightsOnly() - وظيفة تشغيلية داخل الوحدة
- L2165: clearAllDrawingsOnly() - وظيفة تشغيلية داخل الوحدة
- L2192: clearAllBookmarks() - وظيفة تشغيلية داخل الوحدة
- L2208: clearAllComments() - وظيفة تشغيلية داخل الوحدة
- L2299: undoLastAction() - وظيفة تشغيلية داخل الوحدة
- L2460: redoLastAction() - وظيفة تشغيلية داخل الوحدة
- L2610: clearActionHistory() - وظيفة تشغيلية داخل الوحدة
- L2625: cacheTargetIdForColor() - وظيفة تشغيلية داخل الوحدة
- L2669: clearCachedTargetId() - تحرير موارد/تنظيف
- L2677: startEditing() - إنشاء/بدء عملية
- L2721: getEditingStyles() - جلب/قراءة بيانات
- L2726: endEditing() - وظيفة تشغيلية داخل الوحدة
- L2765: cancelEditing() - إيقاف/إغلاق عملية
- L2775: deletePage() - حذف بيانات/عنصر
- L2843: addPage() - إنشاء/بدء عملية
- L2914: _shiftAnnotationsAfterDelete() - وظيفة تشغيلية داخل الوحدة
- L2968: closeActivePdf() - إيقاف/إغلاق عملية
- L2980: deleteClass() - حذف بيانات/عنصر
- L2995: deletePdf() - حذف بيانات/عنصر
- L3009: addBookmark() - إنشاء/بدء عملية
- L3025: deleteBookmark() - حذف بيانات/عنصر
- L3037: movePdf() - وظيفة تشغيلية داخل الوحدة
- L3082: _loadTasks() - وظيفة تشغيلية داخل الوحدة
- L3092: addTask() - إنشاء/بدء عملية
- L3099: toggleTask() - وظيفة تشغيلية داخل الوحدة
- L3108: deleteTask() - حذف بيانات/عنصر
- L3116: classIdCheck() - وظيفة تشغيلية داخل الوحدة

### lib/screens/admin/dev_dashboard.dart
- دور الملف: وحدة عامة
- لا توجد دوال معرفة مباشرة أو الملف يحتوي تعريفات/ثوابت فقط.

### lib/screens/auth/login_screen.dart
- دور الملف: وحدة عامة
- L17: createState() - إنشاء/بدء عملية
- L30: initState() - تهيئة/إعداد
- L35: _loadDeviceId() - وظيفة تشغيلية داخل الوحدة
- L51: _goToSystem() - وظيفة تشغيلية داخل الوحدة
- L106: dispose() - تحرير موارد/تنظيف
- L112: build() - بناء واجهة المستخدم

### lib/services/auth_service.dart
- دور الملف: وحدة عامة
- L17: secureLogin() - وظيفة تشغيلية داخل الوحدة
- L88: _executeImmediateBan() - وظيفة تشغيلية داخل الوحدة
- L155: loginAndBind() - وظيفة تشغيلية داخل الوحدة

### lib/services/file_hash_service.dart
- دور الملف: وحدة عامة
- L6: calculateFileHash() - وظيفة تشغيلية داخل الوحدة

### lib/services/file_manager_service.dart
- دور الملف: وحدة عامة
- L25: FileManagerService() - وظيفة تشغيلية داخل الوحدة
- L28: _notify() - وظيفة تشغيلية داخل الوحدة
- L49: init() - تهيئة/إعداد
- L101: _copyFile() - وظيفة تشغيلية داخل الوحدة
- L196: _ensureWorkingCopy() - وظيفة تشغيلية داخل الوحدة
- L202: _createWorkingCopy() - وظيفة تشغيلية داخل الوحدة
- L219: markSaved() - وظيفة تشغيلية داخل الوحدة
- L234: updateReadingState() - تحديث/حفظ بيانات
- L295: restoreSnapshot() - وظيفة تشغيلية داخل الوحدة
- L319: getSnapshots() - جلب/قراءة بيانات
- L330: moveToTrash() - وظيفة تشغيلية داخل الوحدة
- L371: restoreFromTrash() - وظيفة تشغيلية داخل الوحدة
- L412: permanentlyDelete() - وظيفة تشغيلية داخل الوحدة
- L458: cleanUp() - تحرير موارد/تنظيف
- L482: _cleanOrphanedSessions() - وظيفة تشغيلية داخل الوحدة
- L525: getFoldersOrdered() - جلب/قراءة بيانات
- L532: getDocumentsInFolder() - جلب/قراءة بيانات
- L537: getAllDocuments() - جلب/قراءة بيانات
- L542: searchDocuments() - بحث/فلترة/تنظيم
- L555: getRecentDocuments() - جلب/قراءة بيانات
- L564: getTrashItems() - جلب/قراءة بيانات
- L573: migrateFromLegacyPrefs() - وظيفة تشغيلية داخل الوحدة
- L636: updateFolderSelection() - تحديث/حفظ بيانات
- L647: updateFolderOrder() - تحديث/حفظ بيانات
- L661: updatePdfOrder() - تحديث/حفظ بيانات
- L673: movePdf() - وظيفة تشغيلية داخل الوحدة
- L704: deleteFolder() - حذف بيانات/عنصر
- L726: deleteDocument() - حذف بيانات/عنصر
- L796: saveHighlights() - تحديث/حفظ بيانات
- L853: saveComments() - تحديث/حفظ بيانات
- L909: saveBookmarks() - تحديث/حفظ بيانات
- L966: loadHighlightsForPdf() - جلب/قراءة بيانات
- L971: loadCommentsForPdf() - جلب/قراءة بيانات
- L976: loadBookmarksForPdf() - جلب/قراءة بيانات
- L981: saveHighlightsForPdf() - تحديث/حفظ بيانات
- L1022: saveCommentsForPdf() - تحديث/حفظ بيانات
- L1059: saveBookmarksForPdf() - تحديث/حفظ بيانات
- L1097: migrateAnnotationsFromBlob() - وظيفة تشغيلية داخل الوحدة
- L1150: _toIsarHighlight() - وظيفة تشغيلية داخل الوحدة
- L1173: _toIsarComment() - وظيفة تشغيلية داخل الوحدة
- L1195: _toIsarBookmark() - وظيفة تشغيلية داخل الوحدة
- L1205: _mapJsonToIsarHighlight() - وظيفة تشغيلية داخل الوحدة
- L1227: _mapJsonToIsarComment() - وظيفة تشغيلية داخل الوحدة
- L1248: _mapJsonToIsarBookmark() - وظيفة تشغيلية داخل الوحدة
- L1257: getAllTasks() - جلب/قراءة بيانات
- L1262: saveTask() - تحديث/حفظ بيانات
- L1270: deleteTaskByUuid() - حذف بيانات/عنصر

### lib/services/hardware_service.dart
- دور الملف: وحدة عامة
- L9: getDeviceFingerprint() - جلب/قراءة بيانات
- L36: getDeviceUUID() - جلب/قراءة بيانات
- L49: _fromWmic() - وظيفة تشغيلية داخل الوحدة
- L72: _fromPowerShellCim() - وظيفة تشغيلية داخل الوحدة
- L87: _fromRegistryMachineGuid() - وظيفة تشغيلية داخل الوحدة
- L119: _normalizeId() - وظيفة تشغيلية داخل الوحدة

### lib/services/isolate_worker.dart
- دور الملف: وحدة عامة
- L9: computePdfMetadataIsolate() - وظيفة تشغيلية داخل الوحدة

### lib/services/pdf_tools_service.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- لا توجد دوال معرفة مباشرة أو الملف يحتوي تعريفات/ثوابت فقط.

### lib/services/print_service.dart
- دور الملف: الطباعة ومعالجة الإخراج
- L26: _diagWrite() - وظيفة تشغيلية داخل الوحدة
- L37: _writePendingMarker() - وظيفة تشغيلية داخل الوحدة
- L42: _clearPendingMarker() - وظيفة تشغيلية داخل الوحدة
- L48: _tryWindowsShellPrint() - وظيفة تشغيلية داخل الوحدة
- L59: _openFileInWindowsDefaultApp() - وظيفة تشغيلية داخل الوحدة
- L78: logTiming() - وظيفة تشغيلية داخل الوحدة
- L288: _processPdfIsolate() - وظيفة تشغيلية داخل الوحدة
- L564: _toDouble() - وظيفة تشغيلية داخل الوحدة
- L570: _mapX() - وظيفة تشغيلية داخل الوحدة
- L578: _mapY() - وظيفة تشغيلية داخل الوحدة
- L586: _pdfColorFromArgb() - وظيفة تشغيلية داخل الوحدة

### lib/services/sync_service.dart
- دور الملف: مزامنة الجلسات والتشارك
- L45: watchAllMasterBundles() - جلب/قراءة بيانات
- L78: getMasterBundle() - جلب/قراءة بيانات
- L98: isSessionCodeUnique() - تحقق/قرار منطقي
- L104: findExistingSession() - بحث/فلترة/تنظيم
- L186: setLocked() - تحديث/حفظ بيانات
- L194: setJoinLocked() - تحديث/حفظ بيانات
- L201: watchSessionSecurity() - جلب/قراءة بيانات
- L219: isUserKicked() - تحقق/قرار منطقي
- L233: watchUserExists() - جلب/قراءة بيانات
- L242: checkUserExists() - تحقق/قرار منطقي
- L261: isDeviceBlacklisted() - تحقق/قرار منطقي
- L274: clearAllAnnotations() - وظيفة تشغيلية داخل الوحدة
- L287: clearAnnotationsForHash() - وظيفة تشغيلية داخل الوحدة
- L298: deleteSession() - حذف بيانات/عنصر
- L330: deleteAllSessions() - حذف بيانات/عنصر
- L338: deleteAllMasterBundles() - حذف بيانات/عنصر
- L352: toggleMasterBundleLock() - وظيفة تشغيلية داخل الوحدة
- L362: banUserFromMasterBundle() - وظيفة تشغيلية داخل الوحدة
- L423: kickParticipant() - وظيفة تشغيلية داخل الوحدة
- L458: unkickParticipant() - وظيفة تشغيلية داخل الوحدة
- L482: hasAnnotations() - تحقق/قرار منطقي
- L885: watchSession() - جلب/قراءة بيانات
- L890: streamAnnotations() - جلب/قراءة بيانات
- L903: _randomCode() - وظيفة تشغيلية داخل الوحدة
- L982: deleteAnnouncement() - حذف بيانات/عنصر

### lib/utils/print_utils.dart
- دور الملف: الطباعة ومعالجة الإخراج
- L4: parsePageRange() - وظيفة تشغيلية داخل الوحدة

### lib/utils/sync_naming_utils.dart
- دور الملف: مزامنة الجلسات والتشارك
- L8: generateSmartName() - وظيفة تشغيلية داخل الوحدة
- L31: suggestCodeFromName() - وظيفة تشغيلية داخل الوحدة
- L60: isValidCode() - تحقق/قرار منطقي
- L67: generateRandomCode() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/developer_dashboard_v.dart
- دور الملف: وحدة عامة
- L14: createState() - إنشاء/بدء عملية
- L29: dispose() - تحرير موارد/تنظيف
- L36: _joinMasterBundle() - وظيفة تشغيلية داخل الوحدة
- L192: _toggleLock() - وظيفة تشغيلية داخل الوحدة
- L353: _generateMasterBundle() - وظيفة تشغيلية داخل الوحدة
- L403: build() - بناء واجهة المستخدم
- L584: _confirmLogout() - وظيفة تشغيلية داخل الوحدة
- L1027: _buildLogoutButton() - وظيفة تشغيلية داخل الوحدة
- L1052: _buildSectionHeader() - وظيفة تشغيلية داخل الوحدة
- L1068: _buildSettingsCard() - وظيفة تشغيلية داخل الوحدة
- L1241: createState() - إنشاء/بدء عملية
- L1248: build() - بناء واجهة المستخدم
- L1415: _buildClearButton() - وظيفة تشغيلية داخل الوحدة
- L1439: _buildAdminCard() - وظيفة تشغيلية داخل الوحدة
- L1454: _buildDetailedStats() - وظيفة تشغيلية داخل الوحدة
- L1614: _buildUserManagementList() - وظيفة تشغيلية داخل الوحدة
- L1740: _buildBannedDevicesList() - وظيفة تشغيلية داخل الوحدة
- L1807: _buildActiveBundlesList() - وظيفة تشغيلية داخل الوحدة
- L1906: _buildActiveSessionsList() - وظيفة تشغيلية داخل الوحدة
- L1994: _buildAnnouncementsList() - وظيفة تشغيلية داخل الوحدة
- L2061: _buildEmptyState() - وظيفة تشغيلية داخل الوحدة
- L2189: _confirmDelete() - وظيفة تشغيلية داخل الوحدة
- L2212: _confirmWipe() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/developer_modal_w.dart
- دور الملف: وحدة عامة
- L17: createState() - إنشاء/بدء عملية
- L28: initState() - تهيئة/إعداد
- L56: didUpdateWidget() - وظيفة تشغيلية داخل الوحدة
- L66: dispose() - تحرير موارد/تنظيف
- L71: _handleClose() - وظيفة تشغيلية داخل الوحدة
- L79: _launchUrl() - وظيفة تشغيلية داخل الوحدة
- L87: build() - بناء واجهة المستخدم
- L135: _buildGlassContainer() - وظيفة تشغيلية داخل الوحدة
- L164: _buildAestheticHeader() - وظيفة تشغيلية داخل الوحدة
- L244: _buildSocialBody() - وظيفة تشغيلية داخل الوحدة
- L335: _buildActionButtons() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/dialogs/images_to_pdf_dialog.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L11: createState() - إنشاء/بدء عملية
- L21: _pickImages() - وظيفة تشغيلية داخل الوحدة
- L34: _removeImage() - وظيفة تشغيلية داخل الوحدة
- L40: _convertImages() - وظيفة تشغيلية داخل الوحدة
- L95: build() - بناء واجهة المستخدم

### lib/widgets/dialogs/merge_pdf_dialog.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L12: createState() - إنشاء/بدء عملية
- L19: _pickFiles() - وظيفة تشغيلية داخل الوحدة
- L33: _removeFile() - وظيفة تشغيلية داخل الوحدة
- L39: _mergeFiles() - وظيفة تشغيلية داخل الوحدة
- L94: build() - بناء واجهة المستخدم

### lib/widgets/draggable_text_widget.dart
- دور الملف: وحدة عامة
- L44: createState() - إنشاء/بدء عملية
- L52: _resolveTextDirection() - وظيفة تشغيلية داخل الوحدة
- L62: _fixBidiBrackets() - وظيفة تشغيلية داخل الوحدة
- L81: initState() - تهيئة/إعداد
- L95: dispose() - تحرير موارد/تنظيف
- L103: didUpdateWidget() - وظيفة تشغيلية داخل الوحدة
- L130: build() - بناء واجهة المستخدم

### lib/widgets/global_settings_modal.dart
- دور الملف: وحدة عامة
- L15: createState() - إنشاء/بدء عملية
- L30: dispose() - تحرير موارد/تنظيف
- L37: _joinMasterBundle() - وظيفة تشغيلية داخل الوحدة
- L193: _toggleLock() - وظيفة تشغيلية داخل الوحدة
- L354: _showBundleNameDialog() - وظيفة تشغيلية داخل الوحدة
- L408: _generateMasterBundle() - وظيفة تشغيلية داخل الوحدة
- L459: build() - بناء واجهة المستخدم
- L640: _confirmLogout() - وظيفة تشغيلية داخل الوحدة
- L1179: _buildLogoutButton() - وظيفة تشغيلية داخل الوحدة
- L1204: _buildSectionHeader() - وظيفة تشغيلية داخل الوحدة
- L1219: _buildSettingsCard() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/pdf_viewer_widget_actions.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L6: _WinMemoryTrimmer() - وظيفة تشغيلية داخل الوحدة
- L21: trim() - تحرير موارد/تنظيف
- L46: _addPage() - وظيفة تشغيلية داخل الوحدة
- L61: _deleteCurrentPage() - وظيفة تشغيلية داخل الوحدة
- L102: _showAddBookmarkDialog() - وظيفة تشغيلية داخل الوحدة
- L164: _trimWindowsMemory() - وظيفة تشغيلية داخل الوحدة
- L192: _applyAutoFit() - وظيفة تشغيلية داخل الوحدة
- L231: _forcePdfRelayout() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/pdf_viewer_widget_dashboard.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L5: _buildDashboard() - وظيفة تشغيلية داخل الوحدة
- L44: createState() - إنشاء/بدء عملية
- L51: initState() - تهيئة/إعداد
- L59: _estimateReadingTime() - وظيفة تشغيلية داخل الوحدة
- L71: build() - بناء واجهة المستخدم
- L272: createState() - إنشاء/بدء عملية
- L284: dispose() - تحرير موارد/تنظيف
- L290: _publish() - وظيفة تشغيلية داخل الوحدة
- L325: build() - بناء واجهة المستخدم
- L462: _buildAdminAnnouncementSender() - وظيفة تشغيلية داخل الوحدة
- L473: _buildHeroSection() - وظيفة تشغيلية داخل الوحدة
- L518: createState() - إنشاء/بدء عملية
- L525: dispose() - تحرير موارد/تنظيف
- L530: _handleJoin() - وظيفة تشغيلية داخل الوحدة
- L555: build() - بناء واجهة المستخدم
- L631: _buildAnnouncementsSection() - وظيفة تشغيلية داخل الوحدة
- L870: _buildToDoListMock() - وظيفة تشغيلية داخل الوحدة
- L986: _showAddTaskDialog() - وظيفة تشغيلية داخل الوحدة
- L1027: _buildQuickActionChips() - وظيفة تشغيلية داخل الوحدة
- L1115: _showCreateFolderDialog() - وظيفة تشغيلية داخل الوحدة
- L1158: _buildRealFolderGrid() - وظيفة تشغيلية داخل الوحدة
- L1379: _buildSectionHeader() - وظيفة تشغيلية داخل الوحدة
- L1390: _buildQuickStatChip() - وظيفة تشغيلية داخل الوحدة
- L1414: _buildStatsVertical() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/pdf_viewer_widget_gestures.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L4: _handlePanStart() - وظيفة تشغيلية داخل الوحدة
- L31: _handlePanUpdate() - وظيفة تشغيلية داخل الوحدة
- L58: _handlePanEnd() - وظيفة تشغيلية داخل الوحدة
- L108: _eraseAt() - وظيفة تشغيلية داخل الوحدة
- L222: _distanceToSegment() - وظيفة تشغيلية داخل الوحدة
- L232: _addTextAt() - وظيفة تشغيلية داخل الوحدة
- L263: _updateCurrentEditingText() - وظيفة تشغيلية داخل الوحدة
- L287: _addTextHighlight() - وظيفة تشغيلية داخل الوحدة
- L333: _clearCurrentTextSelection() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/pdf_viewer_widget_overlay.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- لا توجد دوال معرفة مباشرة أو الملف يحتوي تعريفات/ثوابت فقط.

### lib/widgets/pdf_viewer_widget_print.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L13: _pageW() - وظيفة تشغيلية داخل الوحدة
- L21: _pageH() - وظيفة تشغيلية داخل الوحدة
- L83: _buildPrintLoadingScreen() - وظيفة تشغيلية داخل الوحدة
- L127: _executeSafePrint() - وظيفة تشغيلية داخل الوحدة
- L129: logStage() - وظيفة تشغيلية داخل الوحدة
- L230: _performHardReload() - وظيفة تشغيلية داخل الوحدة
- L258: _showPrintDialog() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/pdf_viewer_widget_style.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L6: _getActiveToolType() - وظيفة تشغيلية داخل الوحدة
- L90: _updateShapeTransform() - وظيفة تشغيلية داخل الوحدة
- L130: _endShapeTransform() - وظيفة تشغيلية داخل الوحدة
- L150: _resetShapeHoverCursor() - وظيفة تشغيلية داخل الوحدة
- L187: _findSelectedShape() - وظيفة تشغيلية داخل الوحدة
- L195: _highlightBounds() - وظيفة تشغيلية داخل الوحدة
- L215: _hitHandleIndex() - وظيفة تشغيلية داخل الوحدة
- L231: _resizeRectFromHandle() - وظيفة تشغيلية داخل الوحدة
- L280: _fitPathToBounds() - وظيفة تشغيلية داخل الوحدة
- L295: _highlightTypeToToolType() - وظيفة تشغيلية داخل الوحدة
- L312: _updateSelectedShapeColor() - وظيفة تشغيلية داخل الوحدة
- L328: _updateSelectedShapeStrokeWidth() - وظيفة تشغيلية داخل الوحدة
- L344: _onColorChanged() - وظيفة تشغيلية داخل الوحدة
- L366: _onStrokeWidthChanged() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/pdf_viewer_widget_w.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L41: createState() - إنشاء/بدء عملية
- L83: _colorForTool() - وظيفة تشغيلية داخل الوحدة
- L164: _handleTextSelectionChange() - وظيفة تشغيلية داخل الوحدة
- L206: initState() - تهيئة/إعداد
- L216: _onAppStatusChanged() - وظيفة تشغيلية داخل الوحدة
- L222: didChangeDependencies() - وظيفة تشغيلية داخل الوحدة
- L228: _setupSessionListener() - وظيفة تشغيلية داخل الوحدة
- L322: _onControllerChanged() - وظيفة تشغيلية داخل الوحدة
- L330: dispose() - تحرير موارد/تنظيف
- L348: _handleUndo() - وظيفة تشغيلية داخل الوحدة
- L368: _handleRedo() - وظيفة تشغيلية داخل الوحدة
- L378: _activateTool() - وظيفة تشغيلية داخل الوحدة
- L395: _maybeTrimWindowsMemory() - وظيفة تشغيلية داخل الوحدة
- L404: _schedulePostScrollMaintenance() - وظيفة تشغيلية داخل الوحدة
- L436: _selectedAnnotationTool() - وظيفة تشغيلية داخل الوحدة
- L445: _panelTool() - وظيفة تشغيلية داخل الوحدة
- L450: _isTypingInTextField() - وظيفة تشغيلية داخل الوحدة
- L472: _runShortcut() - وظيفة تشغيلية داخل الوحدة
- L478: build() - بناء واجهة المستخدم
- L531: SingleActivator() - وظيفة تشغيلية داخل الوحدة
- L533: SingleActivator() - وظيفة تشغيلية داخل الوحدة
- L535: SingleActivator() - وظيفة تشغيلية داخل الوحدة
- L537: SingleActivator() - وظيفة تشغيلية داخل الوحدة
- L539: SingleActivator() - وظيفة تشغيلية داخل الوحدة
- L541: SingleActivator() - وظيفة تشغيلية داخل الوحدة
- L1237: _buildPdfViewerCore() - وظيفة تشغيلية داخل الوحدة
- L1349: _buildNoFilePlaceholder() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/sidebar_w.dart
- دور الملف: وحدة عامة
- L11: createState() - إنشاء/بدء عملية
- L18: _handleAddClass() - وظيفة تشغيلية داخل الوحدة
- L86: build() - بناء واجهة المستخدم

### lib/widgets/viewer_components/join_master_modal.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L10: createState() - إنشاء/بدء عملية
- L17: _joinMasterClass() - وظيفة تشغيلية داخل الوحدة
- L75: _showSummaryDialog() - وظيفة تشغيلية داخل الوحدة
- L151: build() - بناء واجهة المستخدم

### lib/widgets/viewer_components/mini_calculator_widget.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L13: createState() - إنشاء/بدء عملية
- L22: _getLatexExpression() - وظيفة تشغيلية داخل الوحدة
- L113: _onButtonPressed() - وظيفة تشغيلية داخل الوحدة
- L141: _calculateResult() - وظيفة تشغيلية داخل الوحدة
- L244: _buildKeyRow() - وظيفة تشغيلية داخل الوحدة
- L257: build() - بناء واجهة المستخدم

### lib/widgets/viewer_components/print_dialog.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L26: createState() - إنشاء/بدء عملية
- L65: build() - بناء واجهة المستخدم
- L104: _buildHeader() - وظيفة تشغيلية داخل الوحدة
- L136: _buildDivider() - وظيفة تشغيلية داخل الوحدة
- L139: _buildSectionLabel() - وظيفة تشغيلية داخل الوحدة
- L153: _buildDestinationSection() - وظيفة تشغيلية داخل الوحدة
- L185: _destinationTile() - وظيفة تشغيلية داخل الوحدة
- L222: _buildOutputPathRow() - وظيفة تشغيلية داخل الوحدة
- L261: _pickOutputPath() - وظيفة تشغيلية داخل الوحدة
- L272: _buildPageRangeSection() - وظيفة تشغيلية داخل الوحدة
- L328: _rangeRadio() - وظيفة تشغيلية داخل الوحدة
- L380: _parityRadio() - وظيفة تشغيلية داخل الوحدة
- L409: _buildCopiesSection() - وظيفة تشغيلية داخل الوحدة
- L485: _buildOrientationSection() - وظيفة تشغيلية داخل الوحدة
- L513: _orientationTile() - وظيفة تشغيلية داخل الوحدة
- L552: _buildColorSection() - وظيفة تشغيلية داخل الوحدة
- L580: _colorTile() - وظيفة تشغيلية داخل الوحدة
- L619: _buildFooter() - وظيفة تشغيلية داخل الوحدة
- L666: _executePrint() - وظيفة تشغيلية داخل الوحدة
- L710: dispose() - تحرير موارد/تنظيف

### lib/widgets/viewer_components/session_cards.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L35: createState() - إنشاء/بدء عملية
- L50: initState() - تهيئة/إعداد
- L57: didUpdateWidget() - وظيفة تشغيلية داخل الوحدة
- L66: _startListening() - وظيفة تشغيلية داخل الوحدة
- L90: dispose() - تحرير موارد/تنظيف
- L95: _showCreateSessionDialog() - وظيفة تشغيلية داخل الوحدة
- L235: _generateCode() - وظيفة تشغيلية داخل الوحدة
- L295: _toggleLock() - وظيفة تشغيلية داخل الوحدة
- L310: _toggleJoinLock() - وظيفة تشغيلية داخل الوحدة
- L325: _clearAnnotations() - وظيفة تشغيلية داخل الوحدة
- L349: _kick() - وظيفة تشغيلية داخل الوحدة
- L376: _unkick() - وظيفة تشغيلية داخل الوحدة
- L403: _syncNow() - وظيفة تشغيلية داخل الوحدة
- L456: build() - بناء واجهة المستخدم
- L803: createState() - إنشاء/بدء عملية
- L812: dispose() - تحرير موارد/تنظيف
- L817: _join() - وظيفة تشغيلية داخل الوحدة
- L873: build() - بناء واجهة المستخدم

### lib/widgets/viewer_components/viewer_right_panel.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L104: build() - بناء واجهة المستخدم
- L1368: _buildSettingsDivider() - وظيفة تشغيلية داخل الوحدة
- L1418: _clearAiConversationForPdf() - وظيفة تشغيلية داخل الوحدة
- L1674: _toolNameAr() - وظيفة تشغيلية داخل الوحدة
- L1810: createState() - إنشاء/بدء عملية
- L1835: _onConversationRevisionChanged() - وظيفة تشغيلية داخل الوحدة
- L1842: _defaultMessages() - وظيفة تشغيلية داخل الوحدة
- L1851: initState() - تهيئة/إعداد
- L1858: didUpdateWidget() - وظيفة تشغيلية داخل الوحدة
- L1865: _loadConversationForCurrentPdf() - وظيفة تشغيلية داخل الوحدة
- L1907: _saveConversationForCurrentPdf() - وظيفة تشغيلية داخل الوحدة
- L1912: _getActivePageText() - وظيفة تشغيلية داخل الوحدة
- L1937: _buildSystemPrompt() - وظيفة تشغيلية داخل الوحدة
- L1958: formatChatResponseForLaTeX() - وظيفة تشغيلية داخل الوحدة
- L1966: _generateGeminiReply() - وظيفة تشغيلية داخل الوحدة
- L2001: _generateGroqReply() - وظيفة تشغيلية داخل الوحدة
- L2065: _generateAiReply() - وظيفة تشغيلية داخل الوحدة
- L2096: dispose() - تحرير موارد/تنظيف
- L2103: _scrollToBottom() - وظيفة تشغيلية داخل الوحدة
- L2114: _sendMessage() - وظيفة تشغيلية داخل الوحدة
- L2187: _buildChatBubble() - وظيفة تشغيلية داخل الوحدة
- L2281: _buildTypingIndicator() - وظيفة تشغيلية داخل الوحدة
- L2329: build() - بناء واجهة المستخدم
- L2424: onMatch() - معالجة حدث UI/تفاعل
- L2442: visitElementAfter() - وظيفة تشغيلية داخل الوحدة

### lib/widgets/viewer_components/viewer_toolbar.dart
- دور الملف: قراءة PDF والتعليقات والرسم
- L43: createState() - إنشاء/بدء عملية
- L59: initState() - تهيئة/إعداد
- L66: didUpdateWidget() - وظيفة تشغيلية داخل الوحدة
- L75: _onPdfControllerChanged() - وظيفة تشغيلية داخل الوحدة
- L82: _refreshToolbarSnapshot() - وظيفة تشغيلية داخل الوحدة
- L100: dispose() - تحرير موارد/تنظيف
- L107: _currentZoomRatio() - وظيفة تشغيلية داخل الوحدة
- L114: _currentZoomLabel() - وظيفة تشغيلية داخل الوحدة
- L118: _applyZoom() - وظيفة تشغيلية داخل الوحدة
- L132: _stepZoom() - وظيفة تشغيلية داخل الوحدة
- L140: _submitZoomText() - وظيفة تشغيلية داخل الوحدة
- L230: build() - بناء واجهة المستخدم

