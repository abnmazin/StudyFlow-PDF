import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'floating_window_manager.dart';
import 'mini_apps/calculator/scientific_calculator.dart';
import 'mini_apps/translator/translator.dart';
import 'mini_apps/power/power.dart';
import 'mini_apps/matrix/matrix.dart';
class MiniAppsTabWidget extends StatelessWidget {
  const MiniAppsTabWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.read<WindowManagerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: [
        _buildAppCard(
          context,
          isDark,
          'حاسبة علمية',
          LucideIcons.calculator,
          () => manager.openWindow(
            FloatingApp(
              id: 'mini_calc',
              title: 'حاسبة علمية',
              icon: LucideIcons.calculator,
              child: const MiniCalculatorWidget(),
            ),
          ),
        ),
        _buildAppCard(
          context,
          isDark,
          'حاسبة المصفوفات',
          Icons.grid_4x4,
          () => manager.openWindow(
            FloatingApp(
              id: 'matrix_calc_1',
              title: 'حاسبة المصفوفات',
              icon: Icons.grid_4x4,
              child: const MatrixCalculatorWidget(),
              size: const Size(400, 550),
            ),
          ),
        ),
        _buildAppCard(
          context,
          isDark,
          'مترجم ذكي',
          LucideIcons.languages,
          () => manager.openWindow(
            FloatingApp(
              id: 'translator_1',
              title: 'المترجم الذكي (AI)',
              icon: LucideIcons.languages,
              child: const MiniTranslatorWidget(),
              size: const Size(350, 450),
            ),
          ),
        ),
        _buildAppCard(
          context,
          isDark,
          'هندسة القدرة',
          Icons.electric_bolt,
          () => manager.openWindow(
            FloatingApp(
              id: 'power_calc_1',
              title: 'حاسبة أنظمة القدرة',
              icon: Icons.electric_bolt,
              child: const PowerCalculatorWidget(),
              size: const Size(320, 550),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppCard(
    BuildContext context,
    bool isDark,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF111827).withValues(alpha: 0.92)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 46, color: const Color(0xFF3B82F6)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}