import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/app_user.dart';
import '../services/university_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UniversityVideoDialog
// Admin-only dialog to add a YouTube video link to a university folder.
// Validates the URL in real time and only enables the button for a valid
// YouTube watch link.
// ─────────────────────────────────────────────────────────────────────────────

class UniversityVideoDialog extends StatefulWidget {
  final String folderId;
  final AppUser user;

  const UniversityVideoDialog({
    super.key,
    required this.folderId,
    required this.user,
  });

  @override
  State<UniversityVideoDialog> createState() => _UniversityVideoDialogState();
}

class _UniversityVideoDialogState extends State<UniversityVideoDialog> {
  final UniversityService _universityService = UniversityService();
  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  bool _isAdding = false;
  String? _error;

  String? get _videoId => UniversityService.videoIdFromUrl(_urlController.text);

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final id = _videoId;
    if (id == null) {
      setState(() => _error = 'الرابط غير صالح. تأكد من رابط فيديو يوتيوب.');
      return;
    }

    setState(() {
      _isAdding = true;
      _error = null;
    });

    try {
      await _universityService.addVideo(
        folderId: widget.folderId,
        title: _titleController.text.trim().isEmpty
            ? 'درس فيديو'
            : _titleController.text.trim(),
        videoUrl: _urlController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎬 تم إضافة الفيديو'),
            backgroundColor: Colors.indigo,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isAdding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final valid = _videoId != null;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.youtube,
                      color: Color(0xFFEF4444),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'إضافة درس فيديو (يوتيوب)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                    ),
                    onPressed: _isAdding ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Video URL ───────────────────────────────────────────
              TextField(
                controller: _urlController,
                enabled: !_isAdding,
                onChanged: (_) => setState(() => _error = null),
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: 'رابط الفيديو *',
                  hintText: 'https://www.youtube.com/watch?v=...',
                  prefixIcon: const Icon(LucideIcons.link2, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: valid
                      ? const Icon(
                          LucideIcons.checkCircle2,
                          color: Colors.green,
                          size: 18,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // ── Title (optional) ────────────────────────────────────
              TextField(
                controller: _titleController,
                enabled: !_isAdding,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: 'العنوان (اختياري)',
                  hintText: 'اسم الدرس...',
                  prefixIcon: const Icon(LucideIcons.type, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'سيوافق الرابط تلقائياً. منذ الدعم: youtube.com، youtu.be، '
                'shorts، و embed.',
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),

              // ── Error ───────────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        color: Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Add Button ──────────────────────────────────────────
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_videoId == null || _isAdding) ? null : _add,
                  icon: _isAdding
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.youtube, size: 20),
                  label: Text(
                    _isAdding ? 'جاري الإضافة...' : 'إضافة الفيديو',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.withValues(alpha: 0.2),
                    disabledForegroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
