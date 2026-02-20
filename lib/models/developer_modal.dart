import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
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

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen && _controller.isDismissed)
      return const SizedBox.shrink();

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
                  color: Colors.black.withOpacity(0.6),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
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
                    constraints: const BoxConstraints(
                      maxHeight: 700,
                      maxWidth: 380,
                    ),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        _buildHeader(),
                        // Info List
                        _buildInfoList(),
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
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // slate-900
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.5,
                  colors: [Colors.blue.withOpacity(0.1), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E293B), // slate-800
                  border: Border.all(color: const Color(0xFF1E293B), width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [Colors.blue, Colors.purple],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.user,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'حسن مازن',
                style: TextStyle(
                  fontFamily: 'Segoe UI', // Fallback
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'مطور برمجيات',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF60A5FA), // blue-400
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoList() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildInfoItem(
            icon: LucideIcons.send,
            iconColor: Colors.blue,
            bgColor: Colors.blue.withOpacity(0.1),
            label: 'معرف التليجرام',
            value: 'EEE_IE',
            hoverColor: Colors.blue.withOpacity(0.05),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            icon: LucideIcons.code,
            iconColor: Colors.indigo,
            bgColor: Colors.indigo.withOpacity(0.1),
            label: 'قناة البرمجة',
            value: 'ANYDESYRE',
            hoverColor: Colors.indigo.withOpacity(0.05),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            icon: LucideIcons.camera,
            iconColor: Colors.pink,
            bgColor: Colors.pink.withOpacity(0.1),
            label: 'انستقرام',
            value: '60K5',
            hoverColor: Colors.pink.withOpacity(0.05),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            icon: LucideIcons.phone,
            iconColor: Colors.green,
            bgColor: Colors.green.withOpacity(0.1),
            label: 'رقم الهاتف',
            value: '07710529693',
            hoverColor: Colors.green.withOpacity(0.05),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A), // slate-900
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: const Text(
                'إغلاق',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required String value,
    required Color hoverColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), // slate-50
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)), // slate-100
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF64748B), // slate-500
                    ),
                  ),
                  SelectableText(
                    value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B), // slate-800
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
