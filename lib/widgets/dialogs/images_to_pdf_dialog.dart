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
  bool _fitToPage = true;

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
        const SnackBar(content: Text('Please select at least one image.')),
      );
      return;
    }

    // Pick save location
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save PDF',
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
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Images converted to PDF successfully at $outputPath',
            ),
            action: SnackBarAction(
              label: 'Open',
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
        ).showSnackBar(SnackBar(content: Text('Error converting images: $e')));
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
                  'Images to PDF',
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
              'Select images to convert. They will be added as pages in the PDF.',
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
                const Text('Fit images to A4 page'),
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
                              'No images selected',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _pickImages,
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('Add Images'),
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
                  label: const Text('Add More Images'),
                ),
              ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
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
                  label: Text(_isProcessing ? 'Converting...' : 'Create PDF'),
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
