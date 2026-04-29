import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FloatingApp {
  final String id;
  final String title;
  final IconData icon;
  final Widget child;
  Offset position;
  Size size;

  FloatingApp({
    required this.id,
    required this.title,
    required this.icon,
    required this.child,
    this.position = const Offset(100, 100),
    this.size = const Size(350, 500),
  });
}

class WindowManagerProvider extends ChangeNotifier {
  final List<FloatingApp> _windows = [];

  List<FloatingApp> get windows => List.unmodifiable(_windows);

  void openWindow(FloatingApp app) {
    final existingIndex = _windows.indexWhere((window) => window.id == app.id);
    if (existingIndex == -1) {
      _windows.add(app);
      notifyListeners();
      return;
    }

    bringToFront(app.id);
  }

  void closeWindow(String id) {
    _windows.removeWhere((window) => window.id == id);
    notifyListeners();
  }

  void bringToFront(String id) {
    final index = _windows.indexWhere((window) => window.id == id);
    if (index == -1 || index == _windows.length - 1) return;

    final window = _windows.removeAt(index);
    _windows.add(window);
    notifyListeners();
  }

  void updatePosition(String id, Offset delta) {
    final index = _windows.indexWhere((window) => window.id == id);
    if (index == -1) return;

    _windows[index].position += delta;
    notifyListeners();
  }
}

class FloatingWindowLayer extends StatelessWidget {
  const FloatingWindowLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<WindowManagerProvider>();

    return Stack(
      children: [
        for (final window in manager.windows)
          Positioned(
            left: window.position.dx,
            top: window.position.dy,
            child: _FloatingWindowCard(
              window: window,
              onBringToFront: () => manager.bringToFront(window.id),
              onDrag: (delta) => manager.updatePosition(window.id, delta),
              onClose: () => manager.closeWindow(window.id),
            ),
          ),
      ],
    );
  }
}

class _FloatingWindowCard extends StatelessWidget {
  final FloatingApp window;
  final VoidCallback onBringToFront;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onClose;

  const _FloatingWindowCard({
    required this.window,
    required this.onBringToFront,
    required this.onDrag,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF0F172A).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.88);
    final headerTint = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return GestureDetector(
      onTapDown: (_) => onBringToFront(),
      child: Container(
        width: window.size.width,
        height: window.size.height,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Column(
              children: [
                GestureDetector(
                  onPanStart: (_) => onBringToFront(),
                  onPanUpdate: (details) => onDrag(details.delta),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: headerTint,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          window.icon,
                          size: 17,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            window.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: onClose,
                          borderRadius: BorderRadius.circular(999),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: window.child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}