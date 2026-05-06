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
      childAspectRatio: 0.88,
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
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.withOpacity(isDark ? 0.05 : 0.02),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 105;
            final iconSize = compact ? 38.0 : 46.0;
            final topPad = compact ? 12.0 : 20.0;
            final gap = compact ? 8.0 : 14.0;
            final textSize = compact ? 12.5 : 14.0;

            return Padding(
              padding: EdgeInsets.only(top: topPad),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: iconSize, color: const Color(0xFF3B82F6)),
                  SizedBox(height: gap),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: textSize,
                            height: 1.2,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}