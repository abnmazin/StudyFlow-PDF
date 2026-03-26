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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _participants = [];

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
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _generateCode() async {
    final hardwareId = widget.app.currentUser?.hardwareId ?? '';
    if (hardwareId.isEmpty) return;
    
    final activePdfId = widget.app.activePdfId;
    if (activePdfId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please open a PDF first.')),
        );
        return;
    }

    setState(() {
      _generating = true;
      _syncStatus = 'جاري توليد الكود...';
    });

    try {
      final activePdf = widget.app.activePdf!;
      final code = await widget.syncService.generateSessionCode(
        hostHardwareId: hardwareId,
        fileHash: activePdf.fileHash ?? '',
        pageCount: activePdf.pageCount ?? 0,
      );
      
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
              SnackBar(content: Text('Error: $e')),
            );
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
              const SnackBar(content: Text('All student annotations cleared.')),
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

  Future<void> _kick(String hardwareId) async {
    final code = widget.app.currentSessionCode;
    if (code == null) return;
    try {
      await widget.syncService.kickParticipant(code, hardwareId);
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Participant kicked.')),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Kick failed: $e')),
            );
          }
        });
      }
    }
  }

  Future<void> _syncNow() async {
    final code = widget.app.currentSessionCode;
    final activePdf = widget.app.activePdf;
    if (code == null || activePdf == null) return;
    
    setState(() => _syncingNow = true);
    
    try {
      await widget.syncService.syncExistingAnnotations(
        code: code,
        fileHash: activePdf.fileHash ?? '',
        highlights: activePdf.highlights,
        comments: activePdf.comments,
      );
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم رفع التغييرات بنجاح!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to sync: $e')),
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
                  const CircularProgressIndicator(strokeWidth: 2),
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
              label: const Text('Generate Sync Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
                    'Code: $code',
                    style: const TextStyle(
                      color: Color(0xFF93C5FD),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'tap to copy',
                    style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Sync Now Button
          ElevatedButton.icon(
            onPressed: _syncingNow ? null : _syncNow,
            icon: _syncingNow
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('رفع التغييرات الآن - Sync Now'),
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
                    locked ? 'Drawing Locked' : 'Lock Student Drawing',
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: locked,
                      onChanged: (_) => _toggleLock(),
                      activeTrackColor: const Color(0xFFF87171),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.trash2, size: 14, color: Color(0xFFF87171)),
            label: const Text(
              'Clear All Student Annotations',
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
                'Live Participants (${_participants.length})',
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
              'No participants yet.',
              style: TextStyle(color: widget.textMuted, fontSize: 12),
            )
          else
            ..._participants.map((p) {
              final username = p['username']?.toString() ?? 'Unknown';
              final hid = p['hardwareId']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.user,
                      size: 14,
                      color: Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        username,
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => _kick(hid),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: const [
                            Icon(LucideIcons.userX, size: 14, color: Color(0xFFF87171)),
                            SizedBox(width: 4),
                            Text(
                              'Kick',
                              style: TextStyle(
                                color: Color(0xFFF87171),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _sub?.cancel();
              app.setSessionCode(null);
              setState(() => _participants = []);
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              'End Session',
              style: TextStyle(color: widget.textMuted, fontSize: 12),
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
      setState(() => _error = 'Enter a session code.');
      return;
    }
    final user = widget.app.currentUser;
    if (user == null) {
      setState(() => _error = 'Please log in first.');
      return;
    }

    final activePdf = widget.app.activePdf;
    if (activePdf == null) {
      setState(() => _error = 'Please open a PDF file to join.');
      return;
    }

    setState(() {
      _joining = true;
      _error = 'Verifying File Identity...';
    });

    try {
      final errorMsg = await widget.syncService.joinSession(
        code: code,
        hardwareId: user.hardwareId,
        username: user.username,
        studentFileHash: activePdf.fileHash ?? '',
        studentPageCount: activePdf.pageCount ?? 0,
      );
      
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (errorMsg != null) {
          setState(() => _error = errorMsg);
        } else {
          widget.app.setSessionCode(code);
          _codeCtrl.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Joined session $code')),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF14532D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF16A34A)),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle,
                  size: 14,
                  color: Color(0xFF4ADE80),
                ),
                const SizedBox(width: 8),
                Text(
                  'In session: $activeCode',
                  style: const TextStyle(
                    color: Color(0xFF4ADE80),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
              'Leave Session',
              style: TextStyle(color: widget.textMuted, fontSize: 12),
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
            hintText: 'Enter sync code (e.g. XK7P2Q)',
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.logIn, size: 16),
          label: const Text('Join Session'),
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
