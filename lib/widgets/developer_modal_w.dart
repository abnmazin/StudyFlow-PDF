import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class DeveloperModal extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;

  const DeveloperModal({
    super.key,
    required this.isOpen,
    required this.onClose,
  });

  @override
  State<DeveloperModal> createState() => _DeveloperModalState();
}

class _DeveloperModalState extends State<DeveloperModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant DeveloperModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _controller.forward();
    } else if (!widget.isOpen && oldWidget.isOpen) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen && _controller.isDismissed) {
      return const SizedBox.shrink();
    }

    final modalMaxHeight =
        (MediaQuery.of(context).size.height - 40).clamp(320.0, 600.0) as double;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            // Backdrop
            GestureDetector(
              onTap: widget.onClose,
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),
            // Modal
            Center(
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxWidth: 400,
                      maxHeight: modalMaxHeight,
                    ),
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        _buildHeader(),
                        Flexible(
                          child: SingleChildScrollView(child: _buildInfoList()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Slate 900
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF334155), width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF1E293B),
              child: Icon(LucideIcons.user, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'حسن مازن',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'مطور برمجيات',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF94A3B8), // Slate 400
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoList() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Column(
        children: [
          _buildClickableRow(
            icon: LucideIcons.send,
            color: const Color(0xFF3B82F6), // Blue 500
            label: 'تيليجرام',
            value: '@FFFF_6',
            onTap: () => _launchUrl('https://t.me/FFFF_6'),
          ),
          const SizedBox(height: 16),
          _buildClickableRow(
            icon: LucideIcons.tv,
            color: const Color(0xFF8B5CF6), // Violet 500
            label: 'القناة',
            value: '@AnyDesire',
            onTap: () => _launchUrl('https://t.me/AnyDesire'),
          ),
          const SizedBox(height: 16),
          _buildClickableRow(
            icon: LucideIcons.phone,
            color: const Color(0xFF10B981), // Emerald 500
            label: 'الهاتف',
            value: '07710529693',
            onTap: () => _launchUrl('tel:07710529693'),
          ),
          const SizedBox(height: 16),
          _buildClickableRow(
            icon: LucideIcons.webcam,
            color: const Color(0xFF10B981), // Emerald 500
            label: 'الموقع الإلكتروني',
            value: 'AbnMazin.engineer',
            onTap: () => _launchUrl('https://AbnMazin.engineer'),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F9), // Slate 100
                foregroundColor: const Color(0xFF0F172A), // Slate 900
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'إغلاق',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClickableRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC), // Slate 50
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)), // Slate 200
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B), // Slate 500
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF1E293B), // Slate 800
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.externalLink, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
