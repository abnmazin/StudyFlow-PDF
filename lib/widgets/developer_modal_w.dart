import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/responsive_utils.dart';

class DeveloperModal extends StatefulWidget {
  final bool isVisible;
  final VoidCallback? onClose;
  final bool isForceUpdate;
  final String currentVersion;
  final String requiredVersion;

  const DeveloperModal({
    super.key,
    bool? isVisible,
    bool? isOpen,
    this.onClose,
    this.isForceUpdate = false,
    this.currentVersion = '',
    this.requiredVersion = '',
  }) : isVisible = isVisible ?? isOpen ?? false;

  @override
  State<DeveloperModal> createState() => _DeveloperModalState();
}

class _DeveloperModalState extends State<DeveloperModal>
    with SingleTickerProviderStateMixin {
  String _appVersion = '';
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _blurAnimation;

  @override
  void initState() {
    super.initState();

    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.isVisible ? 1.0 : 0.0,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _blurAnimation = Tween<double>(
      begin: 0.0,
      end: 12.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant DeveloperModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _controller.forward();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Helper to close modal with animation
  void _handleClose() {
    if (widget.isForceUpdate) return;
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onClose?.call();
      }
    });
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 1. Completely remove from render tree when animation finishes
        if (!widget.isVisible && _controller.isDismissed) {
          return const SizedBox.shrink();
        }

        // 2. Immediately drop all touch events when closing begins
        return IgnorePointer(
          ignoring: !widget.isVisible,
          child: Stack(
            children: [
              // Backdrop with dark blue blur
              GestureDetector(
                onTap: widget.isForceUpdate ? null : _handleClose,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _blurAnimation.value,
                    sigmaY: _blurAnimation.value,
                  ),
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: Container(
                      color: const Color(0xFF0F172A).withOpacity(0.8),
                    ),
                  ),
                ),
              ),

              // Modal Body
              Center(
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: _buildGlassContainer(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlassContainer() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = ResponsiveBreakpoints.dialogWidth(screenWidth, max: 380);
    final horizontalMargin = screenWidth < 420 ? 16.0 : 24.0;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: dialogWidth),
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.95),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: const Color(0xFF38BDF8).withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withOpacity(0.15),
            blurRadius: 30,
            spreadRadius: -5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildAestheticHeader(), _buildSocialBody()],
      ),
    );
  }

  Widget _buildAestheticHeader() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final headerPadding = screenWidth < 420 ? 20.0 : 30.0;

    return Container(
      padding: EdgeInsets.all(headerPadding),
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: Column(
        children: [
          // Profile Picture with glow
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const CircleAvatar(
              radius: 42,
              backgroundColor: Color(0xFF0F172A),
              child: Icon(LucideIcons.user, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Hassan Mazin',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          // "Designed for Al-Bayt" badge - Updated to RTL
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF38BDF8).withOpacity(0.2),
              ),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'تطبيق مصمم خصيصاً للبيت',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE2E8F0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(LucideIcons.heart, size: 14, color: Color(0xFF38BDF8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialBody() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 10, 25, 30),
      child: Column(
        children: [
          // Force update banner — shown only when app is blocked
          if (widget.isForceUpdate) _buildForceUpdateBanner(),

          _buildElegantRow(
            icon: LucideIcons.send,
            color: const Color(0xFF38BDF8),
            value: '@FFFF_6',
            onTap: () => _launchUrl('https://t.me/FFFF_6'),
          ),
          const SizedBox(height: 12),
          _buildElegantRow(
            icon: LucideIcons.tv,
            color: const Color(0xFF818CF8),
            value: '@AnyDesire',
            onTap: () => _launchUrl('https://t.me/AnyDesire'),
          ),
          const SizedBox(height: 12),
          _buildElegantRow(
            icon: LucideIcons.messageCircle,
            color: const Color(0xFF25D366),
            value: '07710529693',
            onTap: () => _launchUrl('https://wa.me/9647710529693'),
          ),
          const SizedBox(height: 20),
          // App version display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.info,
                  size: 13,
                  color: Colors.white.withOpacity(0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  _appVersion.isEmpty ? 'الإصدار ...' : 'الإصدار $_appVersion',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Hide close button when force update is active
          if (!widget.isForceUpdate) _buildActionButtons(),
        ],
      ),
    );
  }

  Future<void> _clearForceUpdateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('force_update_active');
      await prefs.remove('force_update_min_version');
      await prefs.remove('force_update_latest_version');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم مسح البلوك بنجاح — أعد تشغيل التطبيق الآن'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildForceUpdateBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.warning_rounded, color: Color(0xFFEF4444), size: 18),
              SizedBox(width: 8),
              Text(
                'يجب تحديث التطبيق للمتابعة',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (widget.currentVersion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'إصدارك الحالي: ${widget.currentVersion}',
              style: TextStyle(
                color: const Color(0xFFEF4444).withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
          if (widget.requiredVersion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'الإصدار المطلوب: ${widget.requiredVersion}',
              style: TextStyle(
                color: const Color(0xFFEF4444).withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _launchUrl('https://t.me/AnyDesire'),
              icon: const Icon(
                Icons.download_rounded,
                size: 16,
                color: Colors.white,
              ),
              label: const Text(
                'تحديث الآن',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _clearForceUpdateCache,
              icon: const Icon(
                Icons.clear_rounded,
                size: 16,
                color: Color(0xFFEF4444),
              ),
              label: const Text(
                'مسح البلوك (للمطورين)',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFEF4444)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElegantRow({
    required IconData icon,
    required Color color,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withOpacity(0.02),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr, // Explicit LTR for contact rows
            child: Row(
              children: [
                // 1. Icon on the left
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 15),
                // 2. The ID/Value in the center (starting from left)
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // 3. Arrow on the right end
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: Colors.white.withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),            child: ElevatedButton(
              onPressed: _handleClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
