import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

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
  String _deviceId = 'Loading...';
  bool _isLoading = false;
  String? _errorMessage;
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final id = await _hardwareService.getDeviceUUID();
    if (!mounted) return;
    setState(() {
      _deviceId = id;
    });
  }

  Future<void> _goToSystem() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Username is required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // JOKER ACCOUNT BYPASS (abn)
    if (username == 'abn') {
      final joker = AppUser(
        uid: 'joker_abn',
        username: 'abn',
        role: 'developer',
        hardwareId: _deviceId,
      );
      context.read<AppProvider>().setCurrentUser(joker);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainLayout()),
      );
      return;
    }

    try {
      final user = await _authService.loginAndBind(username);
      _currentUser = user;
      debugPrint('Username: ${user.username}');
      debugPrint('Device UUID: ${user.hardwareId}');

      if (!mounted) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AppProvider>().setCurrentUser(user);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainLayout()),
        );
      });
    } catch (e) {
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

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            elevation: 6,
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle: const TextStyle(color: Color(0xFFBDBDBD)),
                      filled: true,
                      fillColor: const Color(0xFF151515),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF333333)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF333333)),
                    ),
                    child: Text(
                      'Device ID: $_deviceId',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFE0E0E0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_errorMessage != null || context.watch<AppProvider>().forcedLogoutReason != null) ...[
                    Text(
                      _errorMessage ?? context.watch<AppProvider>().forcedLogoutReason!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _goToSystem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'دخول إلى النظام',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  if (_currentUser != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Role: ${_currentUser!.role}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
