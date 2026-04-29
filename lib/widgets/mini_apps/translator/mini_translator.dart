import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/app_state.dart';
import '../../../services/translation_service.dart';

class MiniTranslatorWidget extends StatefulWidget {
  const MiniTranslatorWidget({super.key});

  @override
  State<MiniTranslatorWidget> createState() => _MiniTranslatorWidgetState();
}

class _MiniTranslatorWidgetState extends State<MiniTranslatorWidget> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  bool _isLoading = false;
  bool _useAI = true; // Toggle between AI and fast translation
  String _errorText = '';

  Future<void> _translateText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorText = '';
      _outputController.clear();
    });

    try {
      String result;
      if (_useAI) {
        // Use AI translation
        final appProvider = context.read<AppProvider>();
        result = await TranslationService().translate(text, appProvider);
      } else {
        // Use fast translation (Google Translate)
        result = await TranslationService().translateFast(text);
      }

      setState(() {
        _outputController.text = result;
      });
    } catch (e) {
      setState(() {
        _errorText = 'خطأ: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final inputBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // MODE TOGGLE
          Container(
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _useAI = true),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _useAI
                            ? const Color(0xFF8B5CF6)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.psychology,
                            size: 16,
                            color: _useAI ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ذكاء',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _useAI ? Colors.white : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _useAI = false),
                    child: Container(
                      decoration: BoxDecoration(
                        color: !_useAI
                            ? const Color(0xFF10B981)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bolt,
                            size: 16,
                            color: !_useAI ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'سريع',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !_useAI ? Colors.white : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // INPUT AREA
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _inputController,
                maxLines: null,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'أدخل النص للترجمة...',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ACTION BUTTON
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _translateText,
            style: ElevatedButton.styleFrom(
              backgroundColor: _useAI
                  ? const Color(0xFF8B5CF6)
                  : const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: (_useAI
                      ? const Color(0xFF8B5CF6)
                      : const Color(0xFF10B981))
                  .withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.translate),
            label: Text(
              _isLoading
                  ? (_useAI ? 'جاري الترجمة بالذكاء...' : 'جاري الترجمة السريعة...')
                  : 'ترجم الآن',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),

          if (_errorText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _errorText,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 12),

          // OUTPUT AREA
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              padding: const EdgeInsets.all(12),
              child: Stack(
                children: [
                  SingleChildScrollView(
                    child: SelectableText(
                      _outputController.text.isEmpty
                          ? 'الترجمة ستظهر هنا...'
                          : _outputController.text,
                      style: TextStyle(
                        color: _outputController.text.isEmpty
                            ? (isDark ? Colors.white38 : Colors.black38)
                            : textColor,
                        fontSize: 16,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                  if (_outputController.text.isNotEmpty)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        color: Colors.blueAccent,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _outputController.text),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ الترجمة'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
