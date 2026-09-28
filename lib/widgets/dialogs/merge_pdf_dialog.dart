import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import '../../services/pdf_tools_service.dart';
import '../../utils/responsive_utils.dart';

class MergePdfDialog extends StatefulWidget {
  const MergePdfDialog({super.key});

  @override
  State<MergePdfDialog> createState() => _MergePdfDialogState();
}

class _MergePdfDialogState extends State<MergePdfDialog> {
  final List<File> _selectedFiles = [];
  bool _isProcessing = false;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.paths.map((path) => File(path!)));
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _mergeFiles() async {
    if (_selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار ملفي PDF على الأقل لدمجهما.'),
        ),
      );
      return;
    }

    // Pick save location
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ ملف PDF المدمج',
      fileName: 'merged_document.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (outputPath == null) return;

    setState(() => _isProcessing = true);

    try {
      await PdfToolsService.mergePdfs(
        _selectedFiles.map((f) => f.path).toList(),
        outputPath,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم دمج ملفات PDF بنجاح في $outputPath'),
            action: SnackBarAction(
              label: 'فتح',
              onPressed: () {
                // TODO: Open the file using FileManagerService or platform channel
                // For now, we just notify success
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ أثناء دمج ملفات PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = ResponsiveBreakpoints.dialogWidth(
      screen.width,
      max: 520,
    );
    final listHeight = (screen.height * 0.45).clamp(220.0, 360.0).toDouble();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.combine,
                  color: Color(0xFF8B5CF6),
                ), // Purple
                const SizedBox(width: 12),
                const Text(
                  'دمج ملفات PDF',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'اسحب وأفلت لإعادة ترتيب الملفات. سيتم دمج PDF حسب هذا الترتيب.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // File List
            Container(
              height: listHeight,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.withOpacity(0.05),
              ),
              child: _selectedFiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.filePlus,
                            size: 48,
                            color: Colors.grey.withOpacity(0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'لم يتم اختيار أي مستند',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _pickFiles,
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: const Text('إضافة ملفات PDF'),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _selectedFiles.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final File item = _selectedFiles.removeAt(oldIndex);
                          _selectedFiles.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final file = _selectedFiles[index];
                        return Card(
                          key: ValueKey(file.path),
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(
                              LucideIcons.fileText,
                              color: Colors.redAccent,
                            ),
                            title: Text(
                              p.basename(file.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                LucideIcons.trash2,
                                size: 18,
                                color: Colors.grey,
                              ),
                              onPressed: () => _removeFile(index),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 16),
            if (_selectedFiles.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('إضافة ملفات أخرى'),
                ),
              ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isProcessing ? null : _mergeFiles,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.check),
                  label: Text(
                    _isProcessing ? 'جارٍ الدمج...' : 'دمج المستندات',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6), // Purple
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
