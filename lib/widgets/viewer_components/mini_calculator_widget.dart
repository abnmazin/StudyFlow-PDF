import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/math_engine.dart';
import 'dart:ui';

class MiniCalculatorWidget extends StatefulWidget {
  const MiniCalculatorWidget({super.key});

  @override
  State<MiniCalculatorWidget> createState() => _MiniCalculatorWidgetState();
}

class _MiniCalculatorWidgetState extends State<MiniCalculatorWidget> {
  String _expression = '';
  String _history = '';
  String _lastAns = '0';
  final List<String> _undoStack = [];
  double _yValue = 0.0;
  bool _isDegreeMode = true;
  bool _isShiftMode = false;
  bool _showCommonFractions = true;
  String _errorType = '';
  int _cursorIndex = 0;
  final MathEngine _mathEngine = MathEngine();
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'mini_calculator_keyboard',
  );

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // ─── Undo ─────────────────────────────────────────────────────────────────

  void _pushUndo() {
    if (_expression.isNotEmpty) {
      _undoStack.add(_expression);
      if (_undoStack.length > 20) _undoStack.removeAt(0);
    }
  }

  // ─── Cursor ───────────────────────────────────────────────────────────────

  void _clampCursor() {
    _cursorIndex = _cursorIndex.clamp(0, _expression.length);
  }

  void _insertAtCursor(String value) {
    _clampCursor();
    _expression = _expression.substring(0, _cursorIndex) +
        value +
        _expression.substring(_cursorIndex);
    _cursorIndex += value.length;
  }

  void _deleteBeforeCursor() {
    _clampCursor();
    if (_cursorIndex <= 0 || _expression.isEmpty) return;
    _expression = _expression.substring(0, _cursorIndex - 1) +
        _expression.substring(_cursorIndex);
    _cursorIndex -= 1;
  }

  void _deleteAtCursor() {
    _clampCursor();
    if (_cursorIndex >= _expression.length || _expression.isEmpty) return;
    _expression = _expression.substring(0, _cursorIndex) +
        _expression.substring(_cursorIndex + 1);
  }

  // ─── Keyboard ─────────────────────────────────────────────────────────────

  KeyEventResult _handleKeyboard(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _cursorIndex = (_cursorIndex - 1).clamp(0, _expression.length));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _cursorIndex = (_cursorIndex + 1).clamp(0, _expression.length));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      setState(() => _deleteBeforeCursor());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      setState(() => _deleteAtCursor());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _calculateResult();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      setState(() => _isShiftMode = !_isShiftMode);
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char == null) return KeyEventResult.ignored;
    if (RegExp(r'^[0-9xy+\-*/().^,!=]$').hasMatch(char)) {
      setState(() => _insertAtCursor(char));
      return KeyEventResult.handled;
    }
    if (char.toLowerCase() == 'p') { setState(() => _insertAtCursor('pi')); return KeyEventResult.handled; }
    if (char.toLowerCase() == 'e') { setState(() => _insertAtCursor('e')); return KeyEventResult.handled; }
    if (char.toLowerCase() == 'i') { setState(() => _insertAtCursor('i')); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  // ─── Number formatting (now delegated to MathEngine) ────────────────────

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsPrecision(10)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  ({int numerator, int denominator}) _approximateFraction(double value,
      {int maxDenominator = 16}) {
    return MathResult.approximateFraction(value, maxDenominator: maxDenominator);
  }

  // ─── Arg splitter (delegated to MathEngine) ──────────────────────────────

  List<String> _splitTopLevelArgs(String input) {
    return _mathEngine.splitTopLevelArgs(input);
  }

  // ─── Eval preprocessing ───────────────────────────────────────────────────

  String _expandLog10(String s) {
    s = s.replaceAll('log10(', '__LOG10__(');
    while (s.contains('__LOG10__(')) {
      final idx = s.indexOf('__LOG10__(');
      int depth = 1, end = idx + 10;
      while (depth > 0 && end < s.length) {
        if (s[end] == '(') depth++;
        if (s[end] == ')') depth--;
        end++;
      }
      final inner = s.substring(idx + 10, end - 1);
      s = '${s.substring(0, idx)}(log($inner)/log(10))${s.substring(end)}';
    }
    return s;
  }

  // ─── Eval preprocessing (now handled by MathEngine/texpr) ───────────────────

  // Note: texpr handles implicit multiplication, degree/radian conversion, and
  // degree/radian conversion is handled via variables in MathEngine

  double _evaluateAtX(String expr, double xValue) {
    final result = _mathEngine.evaluate(expr, {'x': xValue, 'y': _yValue});
    if (!result.isSuccess) throw Exception(result.error);
    if (result.realValue != null) return result.realValue!;
    if (result.complexValue != null) {
      // If user wants complex result but we need real for numerical methods,
      // return the real part as fallback
      return result.complexValue!.real;
    }
    throw Exception('Math Error');
  }

  double _calcDerivative(String fx, double x0) {
    return _mathEngine.numericalDerivative(fx, 'x', x0);
  }

  double _calcIntegral(String fx, double a, double b) {
    return _mathEngine.numericalIntegral(fx, 'x', a, b, steps: 200);
  }

  // ─── LaTeX renderer ───────────────────────────────────────────────────────

  String _getLatexExpression(String rawExp) {
    if (rawExp.isEmpty) return r'\text{...}';
    String s = rawExp;

    const cur = '❙CURSOR❙';
    s = s.replaceAll('|', cur);
    s = s.replaceAll('pi', r'\pi ');
    s = s.replaceAll('*', r'\times ');
    s = s.replaceAll('log10(', r'\log_{10}(');
    s = s.replaceAll('ln(', r'\ln(');
    s = s.replaceAll('asin(', r'\arcsin(');
    s = s.replaceAll('acos(', r'\arccos(');
    s = s.replaceAll('atan(', r'\arctan(');
    s = s.replaceAll('sin(', r'\sin(');
    s = s.replaceAll('cos(', r'\cos(');
    s = s.replaceAll('tan(', r'\tan(');
    s = s.replaceAll('d/dx(', r'\frac{d}{dx}(');
    s = s.replaceAll('d/dy(', r'\frac{d}{dy}(');
    s = s.replaceAll('∫(', r'\int(');
    s = s.replaceAllMapped(RegExp(r'\^\(([^)]+)\)'), (m) => '^{${m[1]}}');
    s = s.replaceAllMapped(RegExp(r'\^([0-9a-zA-Z.]+)'), (m) => '^{${m[1]}}');
    s = _convertFn(s, '√(', r'\sqrt{');
    s = _convertFn(s, '∛(', r'\sqrt[3]{');
    s = _convertFn(s, 'sqrt(', r'\sqrt{');
    s = _convertFn(s, 'cbrt(', r'\sqrt[3]{');
    // Fallbacks for standalone unicode root symbols (without parentheses).
    s = s.replaceAll('∛', r'\sqrt[3]{}');
    s = s.replaceAll('√', r'\sqrt{}');
    s = _convertFractions(s);
    s = s.replaceAll(cur, r'\textbf{|}');
    return s;
  }

  String _convertFn(String s, String fn, String tex) {
    while (s.contains(fn)) {
      final idx = s.indexOf(fn);
      final openIdx = idx + fn.length - 1;
      if (openIdx >= s.length || s[openIdx] != '(') break;
      int depth = 1, end = openIdx + 1;
      while (depth > 0 && end < s.length) {
        if (s[end] == '(') depth++;
        if (s[end] == ')') depth--;
        end++;
      }
      if (depth != 0) break;
      final inner = s.substring(openIdx + 1, end - 1);
      s = '${s.substring(0, idx)}$tex$inner}${s.substring(end)}';
    }
    return s;
  }

  String _convertFractions(String s) {
    while (s.contains('/')) {
      final si = s.indexOf('/');
      int startNum = si - 1, op = 0;
      while (startNum >= 0) {
        if (s[startNum] == ')') op++;
        else if (s[startNum] == '(') op--;
        if (op < 0) { startNum++; break; }
        if (op == 0 && '+-/=,*'.contains(s[startNum])) { startNum++; break; }
        startNum--;
      }
      if (startNum < 0) startNum = 0;
      int endNum = si + 1; op = 0;
      while (endNum < s.length) {
        if (s[endNum] == '(') op++;
        else if (s[endNum] == ')') op--;
        if (op < 0) { endNum--; break; }
        if (op == 0 && '+-/=,*'.contains(s[endNum])) { endNum--; break; }
        endNum++;
      }
      if (endNum >= s.length) endNum = s.length - 1;
      String num = s.substring(startNum, si);
      String den = s.substring(si + 1, endNum + 1);
      if (num.startsWith('(') && num.endsWith(')')) num = num.substring(1, num.length - 1);
      if (den.startsWith('(') && den.endsWith(')')) den = den.substring(1, den.length - 1);
      s = '${s.substring(0, startNum)}\\frac{$num}{$den}${s.substring(endNum + 1)}';
    }
    return s;
  }

  // ─── Button handler ───────────────────────────────────────────────────────

  void _onButtonPressed(String btn) {
    if (btn == '=' || btn == 'CALC') {
      _calculateResult();
      return;
    }

    setState(() {
      _errorType = '';
      switch (btn) {
        case 'AC':
          _undoStack.clear(); _expression = ''; _history = ''; _lastAns = '0'; _cursorIndex = 0;
        case 'DEL':
          if (_expression.isNotEmpty) { _pushUndo(); _deleteBeforeCursor(); }
        case 'UNDO':
          if (_undoStack.isNotEmpty) {
            _expression = _undoStack.removeLast();
          } else if (_history.isNotEmpty) {
            _expression = _history;
          }
          _errorType = '';
          _cursorIndex = _expression.length;
        case 'SHIFT': _isShiftMode = !_isShiftMode;
        case 'DEG\nRAD': _isDegreeMode = !_isDegreeMode;
        case 'Frac' || 'Frac✓': _showCommonFractions = !_showCommonFractions;
        case 'Eq': _insertAtCursor('=');
        case 'π': _insertAtCursor('pi');
        case 'e': _insertAtCursor('e');
        case 'ans': _insertAtCursor(_lastAns);
        case 'i': _insertAtCursor('i');
        case 'x': _insertAtCursor('x');
        case 'y': _insertAtCursor('y');
        case 'x²':
          if (_isShiftMode) { _insertAtCursor('^(-1)'); _isShiftMode = false; }
          else if (_expression.isEmpty) { _insertAtCursor('x^2'); }
          else { _expression = '($_expression)^2'; _cursorIndex = _expression.length; }
        case '^' || 'xʸ': _insertAtCursor('^');
        case '√':
          if (_isShiftMode) { _insertAtCursor(_expression.isEmpty ? 'cbrt(x)' : 'cbrt('); _isShiftMode = false; }
          else { _insertAtCursor(_expression.isEmpty ? '√(9)' : '√('); }
        case '!': _insertAtCursor('!');
        case 'sin': _insertAtCursor(_isShiftMode ? 'asin(' : 'sin('); if (_isShiftMode) _isShiftMode = false;
        case 'cos': _insertAtCursor(_isShiftMode ? 'acos(' : 'cos('); if (_isShiftMode) _isShiftMode = false;
        case 'tan': _insertAtCursor(_isShiftMode ? 'atan(' : 'tan('); if (_isShiftMode) _isShiftMode = false;
        case 'asin': _insertAtCursor('asin(');
        case 'acos': _insertAtCursor('acos(');
        case 'atan': _insertAtCursor('atan(');
        case 'log':
          if (_isShiftMode) { _insertAtCursor('10^('); _isShiftMode = false; }
          else { _insertAtCursor('log10('); }
        case 'ln':
          if (_isShiftMode) { _insertAtCursor('e^('); _isShiftMode = false; }
          else { _insertAtCursor('ln('); }
        case 'd/dx': _insertAtCursor(_expression.isEmpty ? 'd/dx(' : 'd/dx(');
        case '∫': _insertAtCursor(_expression.isEmpty ? '∫(' : '∫(');
        case '(':
          _insertAtCursor(_isShiftMode ? 'abs(' : '(');
          if (_isShiftMode) _isShiftMode = false;
        case ',': _insertAtCursor(',');
        case 'a/b': _insertAtCursor('/');
        default: _insertAtCursor(btn);
      }
      _clampCursor();
    });
  }

  // ─── Calculate ────────────────────────────────────────────────────────────

  Future<void> _calculateResult() async {
    if (_expression.isEmpty) return;
    String resultStr = '';

    _pushUndo();

    try {
      if (_expression.startsWith('d/dx(') && _expression.endsWith(')')) {
        // Symbolic or numerical derivative
        final inner = _expression.substring(5, _expression.length - 1);
        final args = _splitTopLevelArgs(inner);
        if (args.length == 1) {
          // Symbolic derivative
          resultStr = _mathEngine.differentiate(args[0], 'x');
        } else if (args.length == 2) {
          // Numerical derivative at point
          resultStr = _trimNumber(_calcDerivative(args[0], double.parse(args[1])));
        } else {
          throw Exception('Syntax Error: d/dx expects 1 or 2 arguments');
        }

      } else if (_expression.startsWith('∫(') && _expression.endsWith(')')) {
        // Symbolic or numerical integral
        final inner = _expression.substring(2, _expression.length - 1);
        final args = _splitTopLevelArgs(inner);
        if (args.length == 1) {
          // Symbolic integral
          resultStr = _mathEngine.integrate(args[0], 'x');
        } else if (args.length == 3) {
          // Definite integral
          resultStr = _mathEngine.integrate(args[0], 'x', double.parse(args[1]), double.parse(args[2]));
        } else {
          throw Exception('Syntax Error: ∫ expects 1 or 3 arguments');
        }

      } else if (_expression.contains('=')) {
        // Equation solver (uses MathEngine + equations package fallback)
        resultStr = _mathEngine.solveEquation(_expression);

      } else {
        // Regular expression evaluation
        final result = _mathEngine.evaluate(_expression, {'y': _yValue});
        if (!result.isSuccess) {
          throw Exception(result.error ?? 'Math Error');
        }

        // Format result based on user preferences
        if (result.realValue != null) {
          final val = result.realValue!;
          if (_showCommonFractions && val != val.roundToDouble()) {
            final frac = _approximateFraction(val);
            resultStr =
                frac.denominator == 1 ? _trimNumber(val) : '${frac.numerator}/${frac.denominator}';
          } else {
            resultStr = _trimNumber(val);
          }
        } else if (result.complexValue != null) {
          // Complex result
          final real = result.complexValue!.real;
          final imag = result.complexValue!.imag;
          if (imag == 0) {
            resultStr = _trimNumber(real);
          } else if (real == 0) {
            resultStr = '${_trimNumber(imag)}i';
          } else {
            final sign = imag > 0 ? '+' : '';
            resultStr = '${_trimNumber(real)}${sign}${_trimNumber(imag)}i';
          }
        } else {
          resultStr = result.toDisplayString();
        }
      }

      setState(() {
        _history = _expression;
        _lastAns = resultStr;
        _expression = resultStr;
        _errorType = '';
        _cursorIndex = _expression.length;
      });
    } catch (e) {
      setState(() {
        _history = _expression;
        final msg = e.toString();
        _errorType = msg.contains('Math Error')
            ? 'Math ERROR'
            : msg.contains('No Real')
                ? 'No Real Solution'
                : msg.contains('No Solution')
                    ? 'No Solution'
                    : 'Syntax ERROR';
      });
    }
  }

  // ─── Widget builders ──────────────────────────────────────────────────────

  Widget _buildButton(
    String label, {
    Color? bgColor,
    Color? textColor,
    bool isPrimary = false,
    required bool isDark,
    int flex = 1,
    double? fontSize,
  }) {
    final defaultBg = isDark ? const Color(0xFF334155) : Colors.white;
    final defaultText = isDark ? Colors.white : const Color(0xFF1E293B);

    // Adaptive font size: long labels shrink gracefully
    final autoSize = fontSize ??
        (label.length >= 5 ? 11.5
            : label.length == 4 ? 13.5
            : label.length == 3 ? 15.5
            : 19.0);

    return Expanded(
      flex: flex,
      child: Padding(
        // Tighter padding = taller buttons = better proportions
        padding: const EdgeInsets.all(2.5),
        child: Material(
          color: bgColor ?? defaultBg,
          borderRadius: BorderRadius.circular(9),
          elevation: isDark ? 0 : 1,
          child: InkWell(
            onTap: () => _onButtonPressed(label),
            borderRadius: BorderRadius.circular(9),
            splashColor: Colors.blue.withValues(alpha: 0.2),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
              // FittedBox prevents text overflow on any screen size
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: autoSize,
                    fontWeight: isPrimary ? FontWeight.bold : FontWeight.w600,
                    color: textColor ?? defaultText,
                    fontFamily: 'Roboto',
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<Widget> children) {
    return Expanded(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          textDirection: TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<AppProvider, bool>((p) => p.isDarkMode);
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive display height: shorter on small screens
    final displayHeight = (screenHeight * 0.15).clamp(108.0, 140.0);

    const primaryColor = Color(0xFF3B82F6);
    final scientificBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final scientificText = isDark ? Colors.grey[300] : Colors.grey[800];
    final actionBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0);
    const tealBg = Color(0xFF0F766E);
    const dangerColor = Color(0xFFEF4444);
    const warningColor = Color(0xFFF59E0B);

    // Shift-aware labels
    final sinLabel = _isShiftMode ? 'sin⁻¹' : 'sin';
    final cosLabel = _isShiftMode ? 'cos⁻¹' : 'cos';
    final tanLabel = _isShiftMode ? 'tan⁻¹' : 'tan';
    final logLabel = _isShiftMode ? '10^x' : 'log';
    final lnLabel = _isShiftMode ? 'eˣ' : 'ln';
    final sqrtLabel = _isShiftMode ? '∛' : '√';
    final powLabel = _isShiftMode ? 'x⁻¹' : 'x²';
    final parenLabel = _isShiftMode ? 'abs(' : '(';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        autofocus: true,
        focusNode: _keyboardFocusNode,
        onKeyEvent: (_, event) => _handleKeyboard(event),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _keyboardFocusNode.requestFocus(),
          child: Container(
            color: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
            child: Column(
              children: [

                // ── Display ────────────────────────────────────────────────
                GestureDetector(
                  onTap: () {
                    final text = _expression.isNotEmpty ? _expression : _history;
                    if (text.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Copied!'),
                        duration: Duration(milliseconds: 1000),
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  },
                  child: Container(
                    height: displayHeight,
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF020617) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                        width: 2,
                      ),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                        blurRadius: 10,
                      )],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _history,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'Courier',
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_errorType.isNotEmpty)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _errorType,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    color: Colors.redAccent,
                                    fontFamily: 'Courier',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context).copyWith(
                                  dragDevices: {
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.trackpad,
                                  },
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  reverse: true,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 4, top: 6),
                                    child: Math.tex(
                                      _getLatexExpression(
                                        _expression.substring(0, _cursorIndex) +
                                            '|' +
                                            _expression.substring(_cursorIndex),
                                      ),
                                      mathStyle: MathStyle.display,
                                      textStyle: TextStyle(
                                        fontSize: _expression.length > 20 ? 21 : 27,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      onErrorFallback: (_) => Text(
                                        _expression.isEmpty ? '...' : _expression,
                                        style: TextStyle(
                                          fontSize: 25,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── Keypad ─────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(5, 0, 5, 5),
                    child: Column(
                      children: [
                        // Row 1: SHIFT  DEG/RAD  Frac  UNDO  Eq
                        _buildKeyRow([
                          _buildButton('SHIFT',
                              bgColor: _isShiftMode ? const Color(0xFF8B5CF6) : scientificBg,
                              textColor: _isShiftMode ? Colors.white : scientificText,
                              isPrimary: _isShiftMode, isDark: isDark),
                          _buildButton('DEG\nRAD',
                              bgColor: _isDegreeMode ? const Color(0xFF10B981) : actionBg,
                              textColor: _isDegreeMode ? Colors.white : scientificText,
                              isDark: isDark),
                          _buildButton(_showCommonFractions ? 'Frac✓' : 'Frac',
                              bgColor: scientificBg, textColor: scientificText, isDark: isDark),
  _buildButton('DEL', bgColor: warningColor, textColor: Colors.white, isPrimary: true, isDark: isDark),
                          _buildButton('AC', bgColor: dangerColor, textColor: Colors.white, isPrimary: true, isDark: isDark),

                        ]),

                        // Row 2: d/dx  ∫  ,  π  e
                        _buildKeyRow([
                          _buildButton('d/dx', bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton('∫', bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 21),
                          _buildButton(',', bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 20),
                          _buildButton('π', bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 21),
                          _buildButton('e', bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 20),
                        ]),

                        // Row 3: sin  cos  tan  log  ln
                        _buildKeyRow([
                          _buildButton(sinLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton(cosLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton(tanLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton(logLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton(lnLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                        ]),

                        // Row 4: x²  ^  √  !  i
                        _buildKeyRow([
                          _buildButton(powLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton('^', bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 22),
                          _buildButton(sqrtLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 21),
                          _buildButton('!', bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 21),
                          _buildButton('i', bgColor: scientificBg, textColor: scientificText, isDark: isDark, fontSize: 21),
                        ]),

                        // Row 5: (  )  x  y  ans
                        _buildKeyRow([
                          _buildButton(parenLabel, bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton(')', bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                          _buildButton('x', bgColor: tealBg, textColor: Colors.white, isDark: isDark),
                          _buildButton('y', bgColor: tealBg, textColor: Colors.white, isDark: isDark),
                          _buildButton('ans', bgColor: scientificBg, textColor: scientificText, isDark: isDark),
                        ]),

                        // Row 6: 7  8  9  DEL  AC
                        _buildKeyRow([
                          _buildButton('7', isDark: isDark),
                          _buildButton('8', isDark: isDark),
                          _buildButton('9', isDark: isDark),
                                                    _buildButton('UNDO',
                              bgColor: scientificBg, textColor: warningColor, isDark: isDark),
                          _buildButton('Eq',
                              bgColor: tealBg, textColor: Colors.white, isPrimary: true, isDark: isDark),
                                                ]),

                        // Row 7: 4  5  6  ×  ÷
                        _buildKeyRow([
                          _buildButton('4', isDark: isDark),
                          _buildButton('5', isDark: isDark),
                          _buildButton('6', isDark: isDark),
                          _buildButton('*', bgColor: actionBg, textColor: primaryColor, isDark: isDark, fontSize: 23),
                          _buildButton('/', bgColor: actionBg, textColor: primaryColor, isDark: isDark, fontSize: 23),
                        ]),

                        // Row 8: 1  2  3  +  -
                        _buildKeyRow([
                          _buildButton('1', isDark: isDark),
                          _buildButton('2', isDark: isDark),
                          _buildButton('3', isDark: isDark),
                          _buildButton('+', bgColor: actionBg, textColor: primaryColor, isDark: isDark, fontSize: 25),
                          _buildButton('-', bgColor: actionBg, textColor: primaryColor, isDark: isDark, fontSize: 25),
                        ]),

                        // Row 9: 0 (×2)  .  CALC (×2)
                        _buildKeyRow([
                          _buildButton('0', flex: 2, isDark: isDark),
                          _buildButton('.', isDark: isDark, fontSize: 25),
                          _buildButton('CALC', flex: 2, bgColor: primaryColor, textColor: Colors.white, isPrimary: true, isDark: isDark),
                        ]),
                      ],
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