import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class PowerCalculatorWidget extends StatefulWidget {
  const PowerCalculatorWidget({super.key});

  @override
  State<PowerCalculatorWidget> createState() => _PowerCalculatorWidgetState();
}

class _PowerCalculatorWidgetState extends State<PowerCalculatorWidget> {
  // ===== BOOLEAN STATE (TOGGLES) =====
  bool _isStar = true;       // true = Star (Y),    false = Delta (Δ)
  bool _isVoltageLine = true; // true = V_line,      false = V_phase
  bool _isCurrentLine = true; // true = I_line,      false = I_phase
  bool _isLagging = true;    // true = Lagging,     false = Leading
  bool _calcXFromL = false;  // NEW: true = compute X from L & f

  // ===== INPUT CONTROLLERS =====
  late final TextEditingController _vCtrl;
  late final TextEditingController _iCtrl;
  late final TextEditingController _pfCtrl;
  late final TextEditingController _rCtrl;
  late final TextEditingController _xCtrl;
  late final TextEditingController _fCtrl;  // NEW: frequency (Hz)
  late final TextEditingController _lCtrl;  // NEW: inductance (mH)

  // ===== OUTPUT STATE =====
  double resVL = 0;
  double resVph = 0;
  double resIL = 0;
  double resIph = 0;
  double resS = 0;
  double resP = 0;
  double resQ = 0;
  double resZph = 0;
  double resPLoss = 0;
  double resQLoss = 0;
  double resVDrop = 0;   // NEW: line voltage drop
  double resVsL = 0;
  double resPs = 0;      // NEW: source active power
  double resSs = 0;      // NEW: source apparent power
  double resPFs = 0;     // NEW: source power factor
  double resEff = 0;
  double resReg = 0;
  double resCalcX = 0;   // NEW: computed XL (for display)

  @override
  void initState() {
    super.initState();
    _vCtrl  = TextEditingController();
    _iCtrl  = TextEditingController();
    _pfCtrl = TextEditingController(text: '0.85');
    _rCtrl  = TextEditingController();
    _xCtrl  = TextEditingController();
    _fCtrl  = TextEditingController(text: '50');
    _lCtrl  = TextEditingController();

    for (final c in [_vCtrl, _iCtrl, _pfCtrl, _rCtrl, _xCtrl, _fCtrl, _lCtrl]) {
      c.addListener(_calculateAll);
    }
  }

  @override
  void dispose() {
    for (final c in [_vCtrl, _iCtrl, _pfCtrl, _rCtrl, _xCtrl, _fCtrl, _lCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ===== HELPER METHODS =====

  double _readInput(TextEditingController ctrl) {
    try {
      return double.parse(ctrl.text.trim());
    } catch (_) {
      return 0;
    }
  }

  String _formatValue(double val) {
    if (val == 0) return '0.00';
    if (val.abs() >= 1000000) {
      return '${(val / 1000000).toStringAsFixed(2)}M';
    }
    if (val.abs() >= 1000) {
      return '${(val / 1000).toStringAsFixed(2)}k';
    }
    return val.toStringAsFixed(2);
  }

  void _calculateAll() {
    setState(() {
      // ── Read inputs ──────────────────────────────────────────────────────
      final double v  = _readInput(_vCtrl);
      final double i  = _readInput(_iCtrl);
      double pf       = _readInput(_pfCtrl).clamp(0.01, 1.0);
      final double r  = _readInput(_rCtrl);

      // FIX: compute X from L & f if toggle is on (matches React web version)
      double x;
      if (_calcXFromL) {
        final double f    = _readInput(_fCtrl);
        final double lMH  = _readInput(_lCtrl);
        x = 2 * math.pi * f * (lMH / 1000);
        resCalcX = x;
      } else {
        x = _readInput(_xCtrl);
        resCalcX = x;
      }

      // Phase angle components
      final double cosTheta = pf;
      final double sinTheta = math.sqrt(1 - pf * pf);

      // ===== 1. RECEIVING END VOLTAGE =====
      // FIX: respect _isVoltageLine toggle (was always treating input as V_line)
      if (v > 0) {
        if (_isVoltageLine) {
          resVL  = v;
          resVph = _isStar ? v / math.sqrt(3) : v;
        } else {
          // input is V_phase
          resVph = v;
          resVL  = _isStar ? v * math.sqrt(3) : v;
        }
      } else {
        resVL = resVph = 0;
      }

      // ===== 2. RECEIVING END CURRENT =====
      // FIX: respect _isCurrentLine toggle
      if (i > 0) {
        if (_isCurrentLine) {
          resIL  = i;
          resIph = _isStar ? i : i / math.sqrt(3);
        } else {
          // input is I_phase
          resIph = i;
          resIL  = _isStar ? i : i * math.sqrt(3);
        }
      } else {
        resIL = resIph = 0;
      }

      // ===== 3. 3-PHASE POWER AT RECEIVING END =====
      if (resVL > 0 && resIL > 0) {
        resS = math.sqrt(3) * resVL * resIL;
        resP = resS * cosTheta;
        resQ = resS * sinTheta;
      } else {
        resS = resP = resQ = 0;
      }

      // ===== 4. TRANSMISSION LINE IMPEDANCE & LOSSES =====
      resZph   = math.sqrt(r * r + x * x);
      resPLoss = resIph > 0 ? 3 * resIph * resIph * r : 0;
      resQLoss = resIph > 0 ? 3 * resIph * resIph * x : 0;

      // ===== 5. VOLTAGE DROP & SENDING END VOLTAGE =====
      // FIX: operator precedence bug fixed  (was: `&& r > 0 || x > 0`)
      if (resVph > 0 && resIph > 0 && (r > 0 || x > 0)) {
        // Approximate voltage drop per phase: I(R·cosθ ± X·sinθ)
        final double vDropPh =
            resIph * (r * cosTheta + (_isLagging ? x : -x) * sinTheta);
        final double vSendingPh = resVph + vDropPh;
        // Line voltage drop (for display — matches React vDrop field)
        resVDrop = vDropPh * (_isStar ? math.sqrt(3) : 1);
        resVsL   = _isStar ? vSendingPh * math.sqrt(3) : vSendingPh;
      } else {
        resVDrop = 0;
        resVsL   = resVL;
      }

      // ===== 6. SOURCE SIDE POWER (NEW — matches React resPs/resSs/resPFs) =====
      if (resP > 0) {
        resPs  = resP + resPLoss;
        // FIX: Q at source depends on leading/lagging (matches React)
        final double resQs = _isLagging
            ? (resQ + resQLoss)
            : (resQLoss - resQ);
        resSs  = math.sqrt(resPs * resPs + resQs * resQs);
        resPFs = resSs > 0 ? resPs / resSs : 0;
      } else {
        resPs = resSs = resPFs = 0;
      }

      // ===== 7. EFFICIENCY =====
      resEff = resPs > 0 ? (resP / resPs * 100).clamp(0.0, 100.0) : 0;

      // ===== 8. VOLTAGE REGULATION =====
      // FIX: removed incorrect .clamp(0,100) — VR can be negative (leading PF)
      resReg = resVL > 0 ? (resVsL - resVL) / resVL * 100 : 0;
    });
  }

  // ===== UI BUILDERS =====

  Widget _buildDualInput({
    required String label,
    required TextEditingController controller,
    required String optionA,
    required String optionB,
    required bool isA,
    required ValueChanged<bool> onToggle,
    required String unit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => onToggle(true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isA ? Colors.blue : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        optionA,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isA ? Colors.white : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => onToggle(false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: !isA ? Colors.blue : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        optionB,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: !isA ? Colors.white : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Enter value',
            suffixText: unit,
            filled: true,
            fillColor: Colors.grey.shade900,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleInput({
    required String label,
    required TextEditingController controller,
    required String unit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Enter value',
            suffixText: unit,
            filled: true,
            fillColor: Colors.grey.shade900,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(
    String latexLabel,
    double value,
    String unit,
    Color color,
  ) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Math.tex(
                latexLabel,
                textStyle: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_formatValue(value)} $unit',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ===== HEADER =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade700, Colors.purple.shade700],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.electric_bolt,
                        color: Colors.amber,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'خط النقل | Transmission Line',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _isStar ? 'Y' : 'Δ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ===== CONNECTION TYPE SELECTOR =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connection Type',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _isStar = true);
                                _calculateAll();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _isStar
                                      ? Colors.blue
                                      : Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Star (Y)',
                                  style: TextStyle(
                                    color: _isStar ? Colors.white : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _isStar = false);
                                _calculateAll();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: !_isStar
                                      ? Colors.blue
                                      : Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Delta (Δ)',
                                  style: TextStyle(
                                    color: !_isStar
                                        ? Colors.white
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ===== INPUT PANEL =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Receiving End Inputs',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDualInput(
                        label: 'Voltage',
                        controller: _vCtrl,
                        optionA: 'V_L',
                        optionB: 'V_ph',
                        isA: _isVoltageLine,
                        onToggle: (val) {
                          setState(() => _isVoltageLine = val);
                          _calculateAll();
                        },
                        unit: 'V',
                      ),
                      const SizedBox(height: 14),
                      _buildDualInput(
                        label: 'Current',
                        controller: _iCtrl,
                        optionA: 'I_L',
                        optionB: 'I_ph',
                        isA: _isCurrentLine,
                        onToggle: (val) {
                          setState(() => _isCurrentLine = val);
                          _calculateAll();
                        },
                        unit: 'A',
                      ),
                      const SizedBox(height: 14),
                      _buildSimpleInput(
                        label: 'Power Factor',
                        controller: _pfCtrl,
                        unit: '(0-1)',
                      ),
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade900
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _isLagging = true);
                                  _calculateAll();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isLagging
                                        ? Colors.blue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Lagging',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _isLagging
                                          ? Colors.white
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _isLagging = false);
                                  _calculateAll();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_isLagging
                                        ? Colors.blue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Leading',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: !_isLagging
                                          ? Colors.white
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ===== TRANSMISSION LINE PARAMETERS =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transmission Line Parameters',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSimpleInput(
                        label: 'Resistance (R) per phase',
                        controller: _rCtrl,
                        unit: 'Ω',
                      ),
                      const SizedBox(height: 14),
                      // NEW: toggle between direct X entry or computing from L & f
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () { setState(() => _calcXFromL = false); _calculateAll(); },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !_calcXFromL ? Colors.blue : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Enter X',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: !_calcXFromL ? Colors.white : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () { setState(() => _calcXFromL = true); _calculateAll(); },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _calcXFromL ? Colors.blue : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'From L & f',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _calcXFromL ? Colors.white : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!_calcXFromL)
                        _buildSimpleInput(
                          label: 'Reactance (X) per phase',
                          controller: _xCtrl,
                          unit: 'Ω',
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildSimpleInput(
                                label: 'Frequency',
                                controller: _fCtrl,
                                unit: 'Hz',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildSimpleInput(
                                label: 'Inductance',
                                controller: _lCtrl,
                                unit: 'mH',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'XL = ${resCalcX.toStringAsFixed(3)} Ω',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ===== OUTPUT PANEL: RECEIVING END =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'المعطيات الأساسية (Receiving End)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildResultRow(r'V_{L}', resVL, 'V', Colors.blue),
                      const SizedBox(height: 8),
                      _buildResultRow(r'V_{ph}', resVph, 'V', Colors.blue),
                      const SizedBox(height: 8),
                      _buildResultRow(r'I_{L}', resIL, 'A', Colors.cyan),
                      const SizedBox(height: 8),
                      _buildResultRow(r'I_{ph}', resIph, 'A', Colors.cyan),
                      const SizedBox(height: 8),
                      _buildResultRow(r'S', resS, 'VA', Colors.orange),
                      const SizedBox(height: 8),
                      _buildResultRow(r'P', resP, 'W', Colors.green),
                      const SizedBox(height: 8),
                      _buildResultRow(r'Q', resQ, 'VAR', Colors.purple),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ===== OUTPUT PANEL: TRANSMISSION LINE ANALYSIS =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تحليل خط النقل (Transmission Line Analysis)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildResultRow(r'Z_{ph}', resZph, 'Ω', Colors.amber),
                      const SizedBox(height: 8),
                      _buildResultRow(r'P_{loss}', resPLoss, 'W', Colors.red),
                      const SizedBox(height: 8),
                      _buildResultRow(
                        r'Q_{loss}',
                        resQLoss,
                        'VAR',
                        Colors.pink,
                      ),
                      const SizedBox(height: 8),
                      _buildResultRow(r'V_{s}', resVsL, 'V', Colors.indigo),
                      const SizedBox(height: 8),
                      _buildResultRow(r'\eta', resEff, '%', Colors.teal),
                      const SizedBox(height: 8),
                      _buildResultRow(r'VR', resReg, '%', Colors.deepOrange),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ===== CLEAR BUTTON =====
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _vCtrl.clear();
                      _iCtrl.clear();
                      _pfCtrl.text = '0.85';
                      _rCtrl.clear();
                      _xCtrl.clear();
                      _calculateAll();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
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