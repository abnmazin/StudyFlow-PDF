import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/print_settings.dart';
import '../../services/print_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PrintDialog — Phase 1: destination, page range, copies, orientation, color
// ─────────────────────────────────────────────────────────────────────────────

class PrintDialog extends StatefulWidget {
  final String pdfPath;
  final String pdfName;
  final int totalPages;
  final int currentPage;
  final Future<void> Function(PrintSettings settings)? onPrint; // NEW

  const PrintDialog({
    super.key,
    required this.pdfPath,
    required this.pdfName,
    required this.totalPages,
    this.currentPage = 1,
    this.onPrint, // NEW
  });

  @override
  State<PrintDialog> createState() => _PrintDialogState();
}

class _PrintDialogState extends State<PrintDialog> {
  // ── State ──────────────────────────────────────────────────────────────────
  PrintDestination _destination = PrintDestination.printer;
  String _rangeType = 'all';
  String _parity = 'all';
  bool _reverse = false;
  int _copies = 1;
  PrintOrientation _orientation = PrintOrientation.portrait;
  PrintColorMode _colorMode = PrintColorMode.color;
  String? _outputPath;
  bool _isPrinting = false;

  final TextEditingController _customRangeCtrl = TextEditingController();

  // ── Colours ────────────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFF3B82F6); // blue-500
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _labelColor = Color(0xFF374151);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDestinationSection(),
                    _buildDivider(),
                    _buildPageRangeSection(),
                    _buildDivider(),
                    _buildCopiesSection(),
                    _buildDivider(),
                    _buildOrientationSection(),
                    _buildDivider(),
                    _buildColorSection(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.printer, size: 20, color: _accent),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Print',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _labelColor,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18, color: Color(0xFF9CA3AF)),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() =>
      const Divider(height: 24, thickness: 1, color: _border);

  Widget _buildSectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7280),
        letterSpacing: 0.5,
      ),
    ),
  );

  // DESTINATION ───────────────────────────────────────────────────────────────
  Widget _buildDestinationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('DESTINATION'),
        Row(
          children: [
            Expanded(
              child: _destinationTile(
                PrintDestination.printer,
                LucideIcons.printer,
                'Printer',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _destinationTile(
                PrintDestination.pdfFile,
                LucideIcons.fileOutput,
                'Save as PDF',
              ),
            ),
          ],
        ),
        if (_destination == PrintDestination.pdfFile) ...[
          const SizedBox(height: 10),
          _buildOutputPathRow(),
        ],
      ],
    );
  }

  Widget _destinationTile(PrintDestination value, IconData icon, String label) {
    final selected = _destination == value;
    return GestureDetector(
      onTap: () => setState(() => _destination = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.08) : Colors.white,
          border: Border.all(
            color: selected ? _accent : _border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? _accent : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? _accent : _labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputPathRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _outputPath ?? 'No file selected',
              style: TextStyle(
                fontSize: 12,
                color: _outputPath != null
                    ? _labelColor
                    : const Color(0xFF9CA3AF),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _pickOutputPath,
          icon: const Icon(LucideIcons.folderOpen, size: 14),
          label: const Text('Browse'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _accent),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Future<void> _pickOutputPath() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save PDF as…',
      fileName: '${widget.pdfName.replaceAll('.pdf', '')}_printed.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) setState(() => _outputPath = result);
  }

  // PAGE RANGE ────────────────────────────────────────────────────────────────
  Widget _buildPageRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('PAGE RANGE'),
        _rangeRadio('all', 'All pages (${widget.totalPages})'),
        _rangeRadio('current', 'Current page (${widget.currentPage})'),
        _rangeRadio('odd', 'Odd pages'),
        _rangeRadio('even', 'Even pages'),
        _rangeRadio('custom', 'Custom range'),
        if (_rangeType == 'custom') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customRangeCtrl,
            decoration: InputDecoration(
              hintText: 'e.g. 1-5, 7, 9-12',
              hintStyle: const TextStyle(
                color: Color(0xFFD1D5DB),
                fontSize: 13,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: _accent),
              ),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d,\-\s]')),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Include:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _parityRadio('all', 'All'),
              _parityRadio('odd', 'Odd only'),
              _parityRadio('even', 'Even only'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _rangeRadio(String value, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        setState(() {
          _rangeType = value;
          // Sync parity based on range selection
          if (value == 'odd')
            _parity = 'odd';
          else if (value == 'even')
            _parity = 'even';
          else
            _parity = 'all'; // Default for all, current, custom
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Radio<String>(
                value: value,
                groupValue: _rangeType,
                onChanged: (_) {
                  // Handled by InkWell
                  setState(() {
                    _rangeType = value;
                    if (value == 'odd')
                      _parity = 'odd';
                    else if (value == 'even')
                      _parity = 'even';
                    else
                      _parity = 'all';
                  });
                },
                activeColor: _accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: _labelColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parityRadio(String value, String label) {
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _parity = value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Radio<String>(
                value: value,
                groupValue: _parity,
                onChanged: (v) => setState(() => _parity = v!),
                activeColor: _accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: _labelColor),
            ),
          ],
        ),
      ),
    );
  }

  // COPIES ────────────────────────────────────────────────────────────────────
  Widget _buildCopiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('COPIES'),
        Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.minus, size: 16),
              onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: _border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(6),
                minimumSize: const Size(32, 32),
              ),
            ),
            Expanded(
              child: Slider(
                value: _copies.toDouble(),
                min: 1,
                max: 99,
                divisions: 98,
                activeColor: _accent,
                onChanged: (v) => setState(() => _copies = v.round()),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.plus, size: 16),
              onPressed: _copies < 99 ? () => setState(() => _copies++) : null,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: _border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(6),
                minimumSize: const Size(32, 32),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: Text(
                '$_copies',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _labelColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Reverse order',
            style: TextStyle(fontSize: 13, color: _labelColor),
          ),
          value: _reverse,
          activeColor: _accent,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() => _reverse = v ?? false),
        ),
      ],
    );
  }

  // ORIENTATION ───────────────────────────────────────────────────────────────
  Widget _buildOrientationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ORIENTATION'),
        Row(
          children: [
            Expanded(
              child: _orientationTile(
                PrintOrientation.portrait,
                LucideIcons.arrowUp,
                'Portrait',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _orientationTile(
                PrintOrientation.landscape,
                LucideIcons.arrowRight,
                'Landscape',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _orientationTile(PrintOrientation value, IconData icon, String label) {
    final selected = _orientation == value;
    return GestureDetector(
      onTap: () => setState(() => _orientation = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.08) : Colors.white,
          border: Border.all(
            color: selected ? _accent : _border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? _accent : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? _accent : _labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // COLOR ─────────────────────────────────────────────────────────────────────
  Widget _buildColorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('COLOR MODE'),
        Row(
          children: [
            Expanded(
              child: _colorTile(
                PrintColorMode.color,
                LucideIcons.palette,
                'Color',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _colorTile(
                PrintColorMode.grayscale,
                LucideIcons.contrast,
                'Grayscale',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorTile(PrintColorMode value, IconData icon, String label) {
    final selected = _colorMode == value;
    return GestureDetector(
      onTap: () => setState(() => _colorMode = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.08) : Colors.white,
          border: Border.all(
            color: selected ? _accent : _border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? _accent : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? _accent : _labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FOOTER ────────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isPrinting ? null : () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _isPrinting ? null : _executePrint,
            icon: _isPrinting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.printer, size: 15),
            label: Text(
              _isPrinting
                  ? (_destination == PrintDestination.pdfFile
                        ? 'Saving…'
                        : 'Printing…')
                  : (_destination == PrintDestination.pdfFile
                        ? 'Save PDF'
                        : 'Print'),
            ),
            style: FilledButton.styleFrom(backgroundColor: _accent),
          ),
        ],
      ),
    );
  }

  // ── Execute ────────────────────────────────────────────────────────────────

  Future<void> _executePrint() async {
    // Validate
    if (_destination == PrintDestination.pdfFile &&
        (_outputPath == null || _outputPath!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an output location first.'),
        ),
      );
      return;
    }
    if (_rangeType == 'custom' && _customRangeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a custom page range.')),
      );
      return;
    }

    setState(() => _isPrinting = true);

    // If user chose 'odd' or 'even' in the main list, we treat it as 'all' pages
    // but filtered by the parity field (which we synced in onChanged).
    String effectiveRange = _rangeType;
    if (_rangeType == 'odd' || _rangeType == 'even') {
      effectiveRange = 'all';
    } else if (_rangeType == 'custom') {
      effectiveRange = _customRangeCtrl.text;
    }

    final settings = PrintSettings(
      destination: _destination,
      outputPath: _outputPath,
      pageRange: effectiveRange,
      parity: _parity,
      reverse: _reverse,
      copies: _copies,
      orientation: _orientation,
      colorMode: _colorMode,
    );

    try {
      if (widget.onPrint != null) {
        await widget.onPrint!(settings);
      } else {
        await PrintService.executePrint(
          widget.pdfPath,
          settings,
          currentPage: widget.currentPage,
          printJobName: widget.pdfName,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _destination == PrintDestination.printer
                  ? 'Sent to printer'
                  : 'PDF saved to $_outputPath',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPrinting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _customRangeCtrl.dispose();
    super.dispose();
  }
}
