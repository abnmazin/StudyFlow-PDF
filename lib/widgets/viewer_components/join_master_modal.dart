import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../providers/app_state.dart';

class JoinMasterModal extends StatefulWidget {
  const JoinMasterModal({Key? key}) : super(key: key);

  @override
  State<JoinMasterModal> createState() => _JoinMasterModalState();
}

class _JoinMasterModalState extends State<JoinMasterModal> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _joinMasterClass() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال كود الحزمة')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final app = Provider.of<AppProvider>(context, listen: false);

      // Fetch the bundle
      final bundleDoc = await app.syncService.getMasterBundle(code);
      if (bundleDoc == null) {
        throw Exception('كود الحزمة غير صحيح أو لا يوجد');
      }

      final bundleList = bundleDoc['bundle'] as List<dynamic>? ?? [];
      final bool isLocked = bundleDoc['isLocked'] as bool? ?? false;
      final List bannedUsernames = bundleDoc['bannedUsernames'] as List? ?? [];
      final String? currentUsername = app.currentUser?.username;

      if (isLocked) {
        throw Exception('هذه الحزمة مغلقة حالياً من قبل المحاضر.');
      }

      if (currentUsername != null && bannedUsernames.contains(currentUsername)) {
        throw Exception('لقد تم حظرك من الوصول إلى محتويات هذه الحزمة.');
      }

      // Register activation if not already registered (optional, registerMasterBundleActivation is idempotent in logic)
      if (currentUsername != null) {
        await app.syncService.registerMasterBundleActivation(code, currentUsername);
      }
      
      // Perform the mapping check
      final result = app.linkMasterBundle(bundleList);
      final int successCount = result['successCount'] ?? 0;
      final List<String> missingFiles = List<String>.from(result['missingFiles'] ?? []);

      if (mounted) {
        Navigator.pop(context); // Close the entry modal
        _showSummaryDialog(context, successCount, missingFiles);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${e.toString().replaceAll("Exception:", "").trim()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSummaryDialog(BuildContext context, int successCount, List<String> missingFiles) {
     showDialog(
       context: context,
       builder: (ctx) {
         final isDark = Theme.of(context).brightness == Brightness.dark;
         return AlertDialog(
           backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
           title: const Row(
             children: [
               Icon(LucideIcons.checkCircle, color: Colors.green),
               SizedBox(width: 8),
               Text('نتيجة الربط', style: TextStyle(fontFamily: 'Cairo')),
             ],
           ),
           content: SizedBox(
             width: 320,
             child: Column(
               mainAxisSize: MainAxisSize.min,
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   'تم ربط ($successCount) ملفات بنجاح. 🔗',
                   style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold),
                 ),
                 if (missingFiles.isNotEmpty) ...[
                   const SizedBox(height: 16),
                   const Row(
                     children: [
                       Icon(LucideIcons.alertTriangle, color: Colors.orange, size: 20),
                       SizedBox(width: 8),
                       Expanded(
                         child: Text(
                           'تنبيه: الملفات التالية غير متوفرة بجهازك:',
                           style: TextStyle(fontFamily: 'Cairo', color: Colors.orange, fontWeight: FontWeight.bold),
                         ),
                       ),
                     ],
                   ),
                   const SizedBox(height: 8),
                   Container(
                     constraints: const BoxConstraints(maxHeight: 150),
                     padding: const EdgeInsets.all(8),
                     decoration: BoxDecoration(
                       color: isDark ? Colors.black12 : Colors.grey.shade100,
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: ListView.builder(
                       shrinkWrap: true,
                       itemCount: missingFiles.length,
                       itemBuilder: (context, index) {
                         return Padding(
                           padding: const EdgeInsets.symmetric(vertical: 4),
                           child: Text(
                             '- ${missingFiles[index]}',
                             style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white70 : Colors.black87),
                           ),
                         );
                       },
                     ),
                   ),
                 ],
               ],
             ),
           ),
           actions: [
             TextButton(
               onPressed: () => Navigator.pop(ctx),
               child: const Text('موافق', style: TextStyle(fontFamily: 'Cairo')),
             ),
           ],
         );
       },
     );
   }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.link, color: Colors.blue),
                const SizedBox(width: 12),
                Text(
                  'ربط حزمة دراسية',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'أدخل الكود الرئيسي (Master Code) المقدم من المحاضر لربط جميع ملفات المقرر بجلسات المزامنة التلقائية دفعة واحدة.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
              decoration: InputDecoration(
                hintText: 'أدخل الكود هنا',
                hintStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  letterSpacing: 0,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _joinMasterClass,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('ربط الحزمة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
