import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../services/pdf_tools_service.dart';

class ImagesToPdfDialog extends StatefulWidget {
  const ImagesToPdfDialog({super.key});

  @override
  State<ImagesToPdfDialog> createState() => _ImagesToPdfDialogState();
}

class _ImagesToPdfDialogState extends State<ImagesToPdfDialog> {
  final List<File> _selectedImages = [];
  bool _isProcessing = false;
  bool _fitToPage = false;
  double _jpegQuality = 78;
  int _maxImageDimension = 0;

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        _selectedImages.addAll(result.paths.map((path) => File(path!)));
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _convertImages() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار صورة واحدة على الأقل.')),
      );
      return;
    }

    // Pick save location
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ PDF',
      fileName: 'images_to_pdf.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (outputPath == null) return;

    setState(() => _isProcessing = true);

    try {
      await PdfToolsService.imagesToPdf(
        _selectedImages.map((f) => f.path).toList(),
        outputPath,
        fitToPage: _fitToPage,
        jpegQuality: _jpegQuality.round(),
        maxImageDimension: _maxImageDimension,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحويل الصور إلى PDF بنجاح في $outputPath'),
            action: SnackBarAction(
              label: 'فتح',
              onPressed: () {
                // TODO: Open the file
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ أثناء تحويل الصور: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.image,
                  color: Color(0xFF10B981),
                ), // Green
                const SizedBox(width: 12),
                const Text(
                  'تحويل الصور إلى PDF',
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
              'اختر الصور لتحويلها، وستُضاف كصفحات داخل ملف PDF.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Options
            Row(
              children: [
                Switch(
                  value: _fitToPage,
                  onChanged: (val) => setState(() => _fitToPage = val),
                  activeColor: const Color(0xFF10B981),
                ),
                const Text('ملاءمة الصور مع صفحة A4 (إيقاف = الحجم الأصلي)'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 120, child: Text('جودة JPEG')),
                Expanded(
                  child: Slider(
                    value: _jpegQuality,
                    min: 40,
                    max: 95,
                    divisions: 11,
                    label: _jpegQuality.round().toString(),
                    onChanged: (val) => setState(() => _jpegQuality = val),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${_jpegQuality.round()}',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 120, child: Text('أقصى ضلع')),
                DropdownButton<int>(
                  value: _maxImageDimension,
                  items: const [
                    DropdownMenuItem(
                      value: 0,
                      child: Text('أصلي (بدون تغيير حجم)'),
                    ),
                    DropdownMenuItem(value: 1280, child: Text('1280 px')),
                    DropdownMenuItem(value: 1600, child: Text('1600 px')),
                    DropdownMenuItem(value: 1920, child: Text('1920 px')),
                    DropdownMenuItem(value: 2560, child: Text('2560 px')),
                    DropdownMenuItem(value: 4096, child: Text('4096 px')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _maxImageDimension = val);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Image Grid
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.withOpacity(0.05),
                ),
                child: _selectedImages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.imagePlus,
                              size: 48,
                              color: Colors.grey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لم يتم اختيار صور',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _pickImages,
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('إضافة صور'),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1,
                            ),
                        itemCount: _selectedImages.length,
                        itemBuilder: (context, index) {
                          final file = _selectedImages[index];
                          return Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    image: FileImage(file),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: InkWell(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      LucideIcons.x,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),

            const SizedBox(height: 16),
            if (_selectedImages.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('إضافة صور أخرى'),
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
                  onPressed: _isProcessing ? null : _convertImages,
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
                  label: Text(_isProcessing ? 'جارٍ التحويل...' : 'إنشاء PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981), // Green
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
