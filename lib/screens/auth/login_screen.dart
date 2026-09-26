import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_user.dart';
import '../../providers/app_state.dart';
import '../../services/hardware_service.dart';
import '../../services/auth_service.dart';
import '../../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final HardwareService _hardwareService = HardwareService();
  final AuthService _authService = AuthService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String _deviceId = 'جاري التحميل...';
  bool _isLoading = false;
  String? _errorMessage;
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    try {
      final id = await _hardwareService.getDeviceFingerprint();
      if (!mounted) return;
      setState(() {
        _deviceId = id;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _deviceId = 'خطأ في توليد المعرف';
        });
      }
    }
  }

  Future<void> _goToSystem() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'الرجاء إدخال اسم المستخدم';
      });
      return;
    }

    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'الرجاء إدخال كلمة المرور';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // MANDATORY SECURE LOGIN: No bypasses allowed
      final user = await _authService.secureLogin(username, password);
      _currentUser = user;

      debugPrint('🛡️ [Security] Login Success: ${user.username}');
      debugPrint(
        '🛡️ [Security] Bound Fingerprint: ${user.primaryDeviceFingerprint}',
      );

      if (!mounted) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AppProvider>().setCurrentUser(user);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainLayout()),
        );
      });
    } catch (e) {
      debugPrint('🛡️ [Security] Login Failed: $e');
      if (!mounted) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      });
    } finally {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        });
      }
    }
  }

  Future<void> _openTelegram() async {
    final uri = Uri.parse('https://t.me/ffff_6');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<AppProvider>().isDarkMode;

    // ألوان التصميم المتوهج (Glowing Modern Theme)
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final cardColor = isDark
        ? const Color(0xFF1E293B).withOpacity(0.9)
        : Colors.white.withOpacity(0.9);
    final border = isDark
        ? const Color(0xFF38BDF8).withOpacity(0.3)
        : Colors.blue.withOpacity(0.2);
    final shadow = isDark
        ? const Color(0xFF38BDF8).withOpacity(0.15)
        : Colors.blue.withOpacity(0.1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // ─── الخلفية الجمالية المتوهجة ─────────────────────────────────────────
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF38BDF8).withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withOpacity(0.2),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1D4ED8).withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1D4ED8).withOpacity(0.2),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),

          // ─── بطاقة تسجيل الدخول المركزية ───────────────────────────────────────
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: border, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: shadow,
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Directionality(
                      textDirection: TextDirection.rtl, // تعريب الاتجاه بالكامل
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // الأيقونة المتوهجة
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF38BDF8,
                                  ).withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 36,
                              backgroundColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              child: const Icon(
                                LucideIcons.shieldCheck,
                                size: 36,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          Text(
                            'تسجيل الدخول',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'أهلاً بك، يرجى إدخال بياناتك للمتابعة',
                            style: TextStyle(color: textMuted, fontSize: 13),
                          ),
                          const SizedBox(height: 32),

                          // ─── حقل اسم المستخدم ──────────────────────────────────
                          TextField(
                            controller: _usernameController,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              labelText: 'اسم المستخدم',
                              labelStyle: TextStyle(
                                color: textMuted,
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                LucideIcons.user,
                                color: textMuted,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.black26
                                  : Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF38BDF8),
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ─── حقل كلمة المرور ───────────────────────────────────
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              labelStyle: TextStyle(
                                color: textMuted,
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                LucideIcons.lock,
                                color: textMuted,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? LucideIcons.eye
                                      : LucideIcons.eyeOff,
                                  color: textMuted,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.black26
                                  : Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF38BDF8),
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                            ),
                            onSubmitted: (_) => _goToSystem(),
                          ),
                          const SizedBox(height: 16),

                          // ─── حقل الآيدي المخفي ظاهرياً (موجود برمجياً) ──────────
                          Visibility(
                            visible: false, // مخفي عن المستخدم
                            maintainState: true, // الحفاظ على حالته
                            child: Text('Device ID: $_deviceId'),
                          ),

                          // ─── صندوق التنبيه الأمني ──────────────────────────────
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  LucideIcons.alertTriangle,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'تنبيه أمني: سيتم حظر جهازك الحالي وأي جهاز جديد بشكل نهائي في حال محاولة تسجيل الدخول من جهاز آخر بنفس الحساب.',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.orange[300]
                                          : Colors.orange[800],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ─── رسائل الخطأ ───────────────────────────────────────
                          if (_errorMessage != null ||
                              context.watch<AppProvider>().forcedLogoutReason !=
                                  null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _errorMessage ??
                                    context
                                        .watch<AppProvider>()
                                        .forcedLogoutReason!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],

                          // ─── زر تسجيل الدخول المتوهج ───────────────────────────
                          Container(
                            width: double.infinity,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF38BDF8,
                                  ).withOpacity(0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _goToSystem,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'دخول',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 1,
                                      ),
                                    ),
                            ),
                          ),

                          if (_currentUser != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'الصلاحية: ${_currentUser!.role}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: textMuted, fontSize: 11),
                            ),
                          ],

                          const SizedBox(height: 14),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: _openTelegram,
                              child: Text(
                                '2026 AbnMazin©',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textMuted.withOpacity(0.85),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.underline,
                                  decorationColor: textMuted.withOpacity(0.55),
                                  decorationThickness: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
