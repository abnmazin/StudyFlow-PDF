import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/sync_service.dart';

// ─────────────────────────────────────────────────────────────
// LECTURER SESSION CARD
// ─────────────────────────────────────────────────────────────

class LecturerSessionCard extends StatefulWidget {
  final AppProvider app;
  final Color surfaceAlt;
  final Color panelBorder;
  final Color textPrimary;
  final Color textMuted;
  final SyncService syncService;

  const LecturerSessionCard({
    super.key,
    required this.app,
    required this.surfaceAlt,
    required this.panelBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.syncService,
  });

  @override
  State<LecturerSessionCard> createState() => _LecturerSessionCardState();
}

class _LecturerSessionCardState extends State<LecturerSessionCard> {
  bool _generating = false;
  String _syncStatus = ''; // NEW: for loading messages
  bool _locking = false;
  bool _clearing = false;
  bool _syncingNow = false;
  bool _joinLocking = false; // NEW
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _participants = [];
  String? _error; // Added for error handling in generateCode

  @override
  void initState() {
    super.initState();
    final code = widget.app.currentSessionCode;
    if (code != null) _startListening(code);
  }

  @override
  void didUpdateWidget(covariant LecturerSessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.currentSessionCode != widget.app.currentSessionCode) {
      _sub?.cancel();
      final code = widget.app.currentSessionCode;
      if (code != null) _startListening(code);
    }
  }

  void _startListening(String code) {
    _sub?.cancel();
    _sub = widget.syncService.watchSession(code).listen((snap) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !snap.exists) return;
        final data = snap.data()!;
        final raw = data['participants'] ?? [];
        if (raw is List) {
          setState(() {
            _participants = raw
                .whereType<Map>()
                .map((p) => Map<String, dynamic>.from(p))
                .toList();
          });
        }
        final locked = data['isLocked'] as bool? ?? false;
        widget.app.setSessionLocked(locked);
        final joinLocked = data['joinLocked'] as bool? ?? false;
        widget.app.setSessionJoinLocked(joinLocked);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _generateCode() async {
    // Removed hardwareId empty check because it silently blocked session creation
    // and hostHardwareId is no longer strictly required by sync_service's generateSessionCode.
    final hardwareId = widget.app.currentUser?.hardwareId ?? '';
    
    final activePdfId = widget.app.activePdfId;
    if (activePdfId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى فتح ملف PDF أولاً.')),
        );
        return;
    }

    setState(() {
      _generating = true;
      _syncStatus = 'جاري توليد الكود...';
      _error = null; // Clear previous errors
    });

    try {
      final activePdf = widget.app.activePdf!;
      final code = await widget.syncService.generateSessionCode(
        activePdf.fileHash ?? '',
        activePdf.name,
        activePdf.pageCount ?? 0,
        hardwareId,
        widget.app.currentUser?.username ?? 'محاضر مجهول',
        widget.app.currentUser?.uid ?? '',
      );
      
      if (code == null) {
        if (mounted) setState(() => _error = 'فشل توليد كود الجلسة.');
        return;
      }
      
      // 🚀 BULK SYNC EXISTING NOTES
      final hasNotes = activePdf.highlights.isNotEmpty || activePdf.comments.isNotEmpty;
      
      if (hasNotes) {
        setState(() => _syncStatus = 'جاري رفع الملاحظات الحالية...');
        
        // Check for "Resume" duplication prevention
        final alreadyExists = await widget.syncService.hasAnnotations(code, activePdf.fileHash ?? '');
        if (!alreadyExists) {
            await widget.syncService.syncExistingAnnotations(
              code: code,
              fileHash: activePdf.fileHash ?? '',
              highlights: activePdf.highlights,
              comments: activePdf.comments,
            );
        }
      }

      widget.app.setSessionCode(code);
      _startListening(code);
    } catch (e) {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطأ: $e')),
            );
            setState(() => _error = 'خطأ: $e');
          }
        });
      }
    } finally {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _generating = false;
              _syncStatus = '';
            });
          }
        });
      }
    }
  }

  Future<void> _toggleLock() async {
    final code = widget.app.currentSessionCode;
    if (code == null) return;
    setState(() => _locking = true);
    try {
      await widget.syncService.setLocked(code, locked: !widget.app.sessionLocked);
    } finally {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _locking = false);
        });
      }
    }
  }

  Future<void> _toggleJoinLock() async {
    final code = widget.app.currentSessionCode;
    if (code == null) return;
    setState(() => _joinLocking = true);
    try {
      await widget.syncService.setJoinLocked(code, locked: !widget.app.sessionJoinLocked);
    } finally {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _joinLocking = false);
        });
      }
    }
  }

  Future<void> _clearAnnotations() async {
    final code = widget.app.currentSessionCode;
    if (code == null) return;
    setState(() => _clearing = true);
    try {
      await widget.syncService.clearAllAnnotations(code);
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم مسح كل رسومات الطلاب.')),
            );
          }
        });
      }
    } finally {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _clearing = false);
        });
      }
    }
  }

  Future<void> _kick(String uid) async {
    final code = widget.app.currentSessionCode;
    if (code == null) return;
    try {
      await widget.syncService.kickParticipant(code, uid);
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم طرد المشارك.')),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل الطرد: $e')),
            );
          }
        });
      }
    }
  }

  Future<void> _unkick(String uid) async {
    final code = widget.app.currentSessionCode;
    if (code == null) return;
    try {
      await widget.syncService.unkickParticipant(code, uid);
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم إلغاء الحظر بنجاح.')),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل إلغاء الحظر: $e')),
            );
          }
        });
      }
    }
  }

  Future<void> _syncNow() async {
    if (widget.app.isSyncing) return; // cooldown guard
    if (widget.app.currentSessionCode == null || widget.app.activePdf == null) return;

    setState(() => _syncingNow = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري مطابقة البيانات مع السيرفر...'),
          duration: Duration(seconds: 60),
        ),
      );
    }

    try {
      await widget.app.performBidirectionalSync();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تمت المزامنة بنجاح. تم تحديث وحذف العناصر غير المتطابقة.'),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل التزامن: $e')),
            );
          }
        });
      }
    } finally {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _syncingNow = false);
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final code = app.currentSessionCode;
    final locked = app.sessionLocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (code == null) ...[
          if (_generating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  const RepaintBoundary(child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(height: 8),
                  Text(
                    _syncStatus,
                    style: TextStyle(color: widget.textMuted, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _generateCode,
              icon: const Icon(LucideIcons.zap, size: 16),
              label: const Text('بدء بث الدرس'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
        ] else ...[
          // Code chip
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: code)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3B82F6)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.copy, size: 14, color: Color(0xFF93C5FD)),
                  const SizedBox(width: 8),
                  Text(
                    'الكود: $code',
                    style: const TextStyle(
                      color: Color(0xFF93C5FD),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'إضغط للنسخ',
                    style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          if (app.drawingSyncStrategy == DrawingSyncStrategy.buffered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                   Icon(LucideIcons.checkCircle2, size: 14, color: Color(0xFF16A34A)),
                   SizedBox(width: 6),
                   Text(
                    'مزامنة تلقائية نشطة (${app.drawingSyncStrategy == DrawingSyncStrategy.buffered ? 'خلفية 5ث' : 'لحظية'})',
                    style: TextStyle(color: Color(0xFF16A34A), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          // Sync Now Button
          ElevatedButton.icon(
            onPressed: _syncingNow ? null : _syncNow,
            icon: _syncingNow
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: const RepaintBoundary(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  )
                : const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('مزامنة التغييرات الآن'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A), // Green
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Lock Drawing toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    locked ? LucideIcons.lock : LucideIcons.unlock,
                    size: 16,
                    color: locked ? const Color(0xFFF87171) : widget.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    locked ? 'رسم الطلاب مقفل' : 'قفل رسم الطلاب',
                    style: TextStyle(
                      color: locked ? const Color(0xFFF87171) : widget.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              _locking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: const RepaintBoundary(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Switch(
                      value: locked,
                      onChanged: (_) => _toggleLock(),
                      activeTrackColor: const Color(0xFFF87171),
                    ),
            ],
          ),
          const SizedBox(height: 6),

          // Join Lock toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    app.sessionJoinLocked ? LucideIcons.userX : LucideIcons.userPlus,
                    size: 16,
                    color: app.sessionJoinLocked ? const Color(0xFFFACC15) : widget.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    app.sessionJoinLocked ? 'الدخول مغلق (Join Locked)' : 'قفل دخول الطلاب الجدد',
                    style: TextStyle(
                      color: app.sessionJoinLocked ? const Color(0xFFFACC15) : widget.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              _joinLocking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: const RepaintBoundary(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Switch(
                      value: app.sessionJoinLocked,
                      onChanged: (_) => _toggleJoinLock(),
                      activeTrackColor: const Color(0xFFFACC15),
                    ),
            ],
          ),
          const SizedBox(height: 6),

          // Clear Annotations
          TextButton.icon(
            onPressed: _clearing ? null : _clearAnnotations,
            icon: _clearing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: const RepaintBoundary(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : const Icon(LucideIcons.trash2, size: 14, color: Color(0xFFF87171)),
            label: const Text(
              'مسح كل رسومات الطلاب من السيرفر',
              style: TextStyle(color: Color(0xFFF87171), fontSize: 13),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 10),

          // Live Participants header
          Row(
            children: [
              Icon(LucideIcons.users, size: 14, color: widget.textMuted),
              const SizedBox(width: 6),
              Text(
                'المشاركون النشطون (${_participants.length})',
                style: TextStyle(
                  color: widget.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (_participants.isEmpty)
            Text(
              'لا يوجد مشاركين بعد.',
              style: TextStyle(color: widget.textMuted, fontSize: 13),
            )
          else
            ..._participants.map((p) {
              final username = p['username']?.toString() ?? 'Unknown';
              final uid = p['uid']?.toString() ?? '';
              final isKicked = p['isKicked'] == true;

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                     Icon(
                      isKicked ? LucideIcons.userX : LucideIcons.user,
                      size: 14,
                      color: isKicked ? const Color(0xFFF87171) : const Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isKicked ? '$username (مطرود)' : username,
                        style: TextStyle(
                          color: isKicked ? widget.textMuted : widget.textPrimary,
                          fontSize: 13,
                          decoration: isKicked ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isKicked)
                      InkWell(
                        onTap: () => _unkick(uid),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: const [
                              Icon(LucideIcons.userCheck, size: 14, color: Color(0xFF16A34A)),
                              SizedBox(width: 4),
                              Text(
                                'إلغاء الحظر',
                                style: TextStyle(
                                  color: Color(0xFF16A34A),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () => _kick(uid),
                        child: const Text(
                          'طرد',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              // 1. Permanently delete the session from the server (Phase 12.2)
              final code = widget.app.currentSessionCode;
              if (code != null) {
                await widget.syncService.deleteSession(code);
              }
              // 2. Clear local HUD state
              _sub?.cancel();
              widget.app.setSessionCode(null);
              setState(() => _participants = []);
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              'إنهاء الجلسة',
              style: TextStyle(color: widget.textMuted, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MEMBER SESSION CARD
// ─────────────────────────────────────────────────────────────

class MemberSessionCard extends StatefulWidget {
  final AppProvider app;
  final Color surfaceAlt;
  final Color panelBorder;
  final Color textPrimary;
  final Color textMuted;
  final SyncService syncService;

  const MemberSessionCard({
    super.key,
    required this.app,
    required this.surfaceAlt,
    required this.panelBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.syncService,
  });

  @override
  State<MemberSessionCard> createState() => _MemberSessionCardState();
}

class _MemberSessionCardState extends State<MemberSessionCard> {
  final TextEditingController _codeCtrl = TextEditingController();
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'أدخل كود الجلسة (مثال: XK7P2Q).');
      return;
    }
    final user = widget.app.currentUser;
    if (user == null) {
      setState(() => _error = 'يرجى تسجيل الدخول أولاً.');
      return;
    }

    final activePdf = widget.app.activePdf;
    if (activePdf == null) {
      setState(() => _error = 'يرجى فتح ملف PDF للانضمام.');
      return;
    }

    setState(() {
      _joining = true;
      _error = 'جارِ التحقق من هوية الملف...';
    });

    try {
      final res = await widget.syncService.joinSession(
        code: code,
        uid: widget.app.currentUser?.uid ?? '',
        username: widget.app.currentUser?.username ?? 'طالب',
        studentFileHash: activePdf.fileHash ?? '',
        studentPageCount: activePdf.pageCount ?? 0,
      );
      
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (res != null) {
          setState(() => _error = res);
        } else {
          widget.app.setSessionCode(code);
          _codeCtrl.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم الانضمام للدرس: $code')),
          );
        }
      });
    } catch (e) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _error = 'Error: $e');
      });
    } finally {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _joining = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final activeCode = app.currentSessionCode;

    if (activeCode != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<Map<String, dynamic>>(
            stream: widget.syncService.watchSessionSecurity(activeCode),
            builder: (context, snapshot) {
              final ownerName = snapshot.data?['ownerName'] ?? '...';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF14532D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF16A34A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.checkCircle, size: 14, color: Color(0xFF4ADE80)),
                        const SizedBox(width: 8),
                        Text(
                          'متصل بالدرس: $activeCode',
                          style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'المحاضر: $ownerName',
                      style: const TextStyle(color: Color(0xFFBCF5D4), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () {
              // Resetting the active code forces the PDFViewerWidget listener to restart
              app.setSessionCode(activeCode);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تحديث البيانات بنجاح')),
              );
            },
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('تحديث البيانات'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => app.setSessionCode(null),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              'مغادرة الجلسة',
              style: TextStyle(color: widget.textMuted, fontSize: 13),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'أدخل كود المزامنة (مثال: XK7P2Q)',
            hintStyle: TextStyle(color: widget.textMuted, fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: widget.surfaceAlt,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: widget.panelBorder),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide(color: Color(0xFF3B82F6), width: 1.4),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          style: TextStyle(color: widget.textPrimary, fontSize: 14),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _joining ? null : _join,
          icon: _joining
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: const RepaintBoundary(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const Icon(LucideIcons.logIn, size: 16),
          label: const Text('الانضمام إلى درس'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
