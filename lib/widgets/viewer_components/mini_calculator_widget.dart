import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import 'dart:math' as math;
import 'dart:ui';

class MiniCalculatorWidget extends StatefulWidget {
  const MiniCalculatorWidget({super.key});

  @override
  State<MiniCalculatorWidget> createState() => _MiniCalculatorWidgetState();
}

class _MiniCalculatorWidgetState extends State<MiniCalculatorWidget> {
  String _expression = '';
  String _history = '';
  final List<String> _undoStack = [];
  double _yValue = 0.0;
  bool _isEditingY = false;
  String _yInput = '0';
  bool _isDegreeMode = true;
  bool _isShiftMode = false;
  bool _showCommonFractions = true;
  String _errorType = '';
  int _cursorIndex = 0;
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'mini_calculator_keyboard',
  );

  void _pushUndo() {
    if (_expression.isNotEmpty) {
      _undoStack.add(_expression);
      if (_undoStack.length > 20) _undoStack.removeAt(0);
    }
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _clampCursor() {
    if (_cursorIndex < 0) _cursorIndex = 0;
    if (_cursorIndex > _expression.length) _cursorIndex = _expression.length;
  }

  String _expressionWithCaret() {
    _clampCursor();
    final raw = _expression;
    final left = raw.substring(0, _cursorIndex);
    final right = raw.substring(_cursorIndex);
    return '$left|$right';
  }

  void _insertAtCursor(String value) {
    _clampCursor();
    _expression =
        _expression.substring(0, _cursorIndex) +
        value +
        _expression.substring(_cursorIndex);
    _cursorIndex += value.length;
  }

  void _deleteBeforeCursor() {
    _clampCursor();
    if (_cursorIndex <= 0 || _expression.isEmpty) return;
    _expression =
        _expression.substring(0, _cursorIndex - 1) +
        _expression.substring(_cursorIndex);
    _cursorIndex -= 1;
  }

  void _deleteAtCursor() {
    _clampCursor();
    if (_cursorIndex >= _expression.length || _expression.isEmpty) return;
    _expression =
        _expression.substring(0, _cursorIndex) +
        _expression.substring(_cursorIndex + 1);
  }

  KeyEventResult _handleKeyboard(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        _cursorIndex = (_cursorIndex - 1).clamp(0, _expression.length);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() {
        _cursorIndex = (_cursorIndex + 1).clamp(0, _expression.length);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      setState(() => _deleteBeforeCursor());
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete) {
      setState(() => _deleteAtCursor());
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _calculateResult();
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null && RegExp(r'^[0-9x+\-*/().^]$').hasMatch(char)) {
      setState(() => _insertAtCursor(char));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsPrecision(10)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  ({int numerator, int denominator}) _approximateFraction(
    double value, {
    int maxDenominator = 16,
  }) {
    int bestNumerator = value.round();
    int bestDenominator = 1;
    double bestError = (value - bestNumerator).abs();

    for (int d = 1; d <= maxDenominator; d++) {
      final n = (value * d).round();
      final err = (value - (n / d)).abs();
      if (err < bestError) {
        bestError = err;
        bestNumerator = n;
        bestDenominator = d;
      }
    }

    int a = bestNumerator.abs();
    int b = bestDenominator;
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    final gcd = a == 0 ? 1 : a;

    final finalNum = bestNumerator ~/ gcd;
    final finalDen = bestDenominator ~/ gcd;

    // لو الخطأ كبير جداً، ارجع الرقم العشري بدل الكسر
    final checkError = (value - (finalNum / finalDen)).abs();
    if (checkError > 0.001) {
      return (numerator: value.round(), denominator: 1);
    }

    return (
      numerator: finalNum,
      denominator: finalDen,
    );
  }

  String _formatCoefficientValue(double value) {
    if (!_showCommonFractions) return _trimNumber(value);
    if (value == value.roundToDouble()) return value.toInt().toString();

    final sign = value < 0 ? '-' : '';
    final absValue = value.abs();
    final frac = _approximateFraction(absValue);

    if (frac.denominator == 1) {
      return '$sign${frac.numerator}';
    }
    return '$sign${frac.numerator}/${frac.denominator}';
  }

  String _formatSymbolicTerm(double coefficient, int power) {
    if (coefficient == 0) return '';

    final sign = coefficient < 0 ? '-' : '';
    final absCoef = coefficient.abs();

    if (power == 0) {
      return '$sign${_formatCoefficientValue(absCoef)}';
    }

    final coefPart = (absCoef == 1) ? '' : _formatCoefficientValue(absCoef);
    final varPart = power == 1 ? 'x' : 'x^$power';

    if (coefPart.contains('/')) {
      return '$sign($coefPart)*$varPart';
    }

    return '$sign$coefPart$varPart';
  }

  List<String> _splitPolynomialTerms(String expr) {
    final normalized = expr.replaceAll(' ', '').replaceAll('-', '+-');
    return normalized.split('+').where((t) => t.isNotEmpty).toList();
  }

  ({double coefficient, int power}) _parsePolynomialTerm(String term) {
    final clean = term.replaceAll('*', '');

    if (!clean.contains('x')) {
      final constant = double.parse(clean);
      return (coefficient: constant, power: 0);
    }

    final xIndex = clean.indexOf('x');
    final coefRaw = clean.substring(0, xIndex);
    final afterX = clean.substring(xIndex + 1);

    double coefficient;
    if (coefRaw.isEmpty || coefRaw == '+') {
      coefficient = 1;
    } else if (coefRaw == '-') {
      coefficient = -1;
    } else {
      coefficient = double.parse(coefRaw);
    }

    int power = 1;
    if (afterX.startsWith('^')) {
      power = int.parse(afterX.substring(1));
    }

    return (coefficient: coefficient, power: power);
  }

  String _symbolicDerivative(String expr) {
    final terms = _splitPolynomialTerms(expr);
    final out = <String>[];

    for (final term in terms) {
      final parsed = _parsePolynomialTerm(term);
      if (parsed.power == 0) {
        continue;
      }

      final newCoef = parsed.coefficient * parsed.power;
      final newPower = parsed.power - 1;
      final symbolic = _formatSymbolicTerm(newCoef, newPower);
      if (symbolic.isNotEmpty) {
        out.add(symbolic);
      }
    }

    if (out.isEmpty) return '0';
    return out.join('+').replaceAll('+-', '-');
  }

  String _symbolicIntegral(String expr) {
    final terms = _splitPolynomialTerms(expr);
    final out = <String>[];

    for (final term in terms) {
      final parsed = _parsePolynomialTerm(term);

      if (parsed.power == -1) {
        // ∫(a/x)dx = a ln|x|
        final a = parsed.coefficient;
        if (a == 1) {
          out.add('ln|x|');
        } else if (a == -1) {
          out.add('-ln|x|');
        } else {
          out.add('${_trimNumber(a)}ln|x|');
        }
        continue;
      }

      final newPower = parsed.power + 1;
      final newCoef = parsed.coefficient / newPower;
      final symbolic = _formatSymbolicTerm(newCoef, newPower);
      if (symbolic.isNotEmpty) {
        out.add(symbolic);
      }
    }

    if (out.isEmpty) return 'C';
    return '${out.join('+').replaceAll('+-', '-')}+C';
  }

  List<String> _splitTopLevelArgs(String input) {
    final parts = <String>[];
    final buffer = StringBuffer();
    int depth = 0;

    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;

      if (ch == ',' && depth == 0) {
        parts.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }

    if (buffer.isNotEmpty) {
      parts.add(buffer.toString().trim());
    }

    return parts;
  }

  double _evaluateAtX(String exp, double xValue) {
    String evalStr = exp;
    evalStr = evalStr.replaceAll('√', 'sqrt');
    // تحويل دائم لأسماء math_expressions بغض النظر عن الـ mode
    evalStr = evalStr.replaceAll('asin(', '__ASIN__(');
    evalStr = evalStr.replaceAll('acos(', '__ACOS__(');
    evalStr = evalStr.replaceAll('atan(', '__ATAN__(');

    if (_isDegreeMode) {
      // تطبيق تحويل الدرجات على الدوال المباشرة فقط
      evalStr = evalStr.replaceAll('sin(', 'sin((pi/180)*');
      evalStr = evalStr.replaceAll('cos(', 'cos((pi/180)*');
      evalStr = evalStr.replaceAll('tan(', 'tan((pi/180)*');
      // إرجاع الدوال العكسية مع تحويل النتيجة من راديان لدرجات
      evalStr = evalStr.replaceAll('__ASIN__(', '(180/pi)*arcsin(');
      evalStr = evalStr.replaceAll('__ACOS__(', '(180/pi)*arccos(');
      evalStr = evalStr.replaceAll('__ATAN__(', '(180/pi)*arctan(');
    }

    // في Rad mode نحول للأسماء الصحيحة بدون تعديل
    if (!_isDegreeMode) {
      evalStr = evalStr.replaceAll('__ASIN__(', 'arcsin(');
      evalStr = evalStr.replaceAll('__ACOS__(', 'arccos(');
      evalStr = evalStr.replaceAll('__ATAN__(', 'arctan(');
    }

    final parser = Parser();
    final parsed = parser.parse(evalStr);
    final cm = ContextModel();
    cm.bindVariable(Variable('pi'), Number(math.pi));
    cm.bindVariable(Variable('e'), Number(math.e));
    cm.bindVariable(Variable('x'), Number(xValue));
    cm.bindVariable(Variable('y'), Number(_yValue));

    final value = parsed.evaluate(EvaluationType.REAL, cm);
    if (value.isNaN || value.isInfinite) {
      throw Exception('Math Error');
    }
    return value;
  }

  double _calculateDerivative(String fx, double x0) {
    const h = 1e-5;
    final right = _evaluateAtX(fx, x0 + h);
    final left = _evaluateAtX(fx, x0 - h);
    return (right - left) / (2 * h);
  }

  double _calculateIntegral(String fx, double a, double b) {
    // Simpson's rule with fixed even segment count for smooth UI performance.
    const n = 200;
    final h = (b - a) / n;
    double sum = _evaluateAtX(fx, a) + _evaluateAtX(fx, b);

    for (int i = 1; i < n; i++) {
      final x = a + i * h;
      sum += (i % 2 == 0 ? 2.0 : 4.0) * _evaluateAtX(fx, x);
    }

    return (h / 3.0) * sum;
  }

  String _getLatexExpression(String rawExp) {
    if (rawExp.isEmpty) return r'\text{...}';

    String latex = rawExp;

    latex = latex.replaceAll('pi', r'\pi ');
    latex = latex.replaceAll('*', r'\times ');
    latex = latex.replaceAll('sin(', r'\sin(');
    latex = latex.replaceAll('cos(', r'\cos(');
    latex = latex.replaceAll('tan(', r'\tan(');
    latex = latex.replaceAll('asin(', r'\arcsin(');
    latex = latex.replaceAll('acos(', r'\arccos(');
    latex = latex.replaceAll('atan(', r'\arctan(');
    latex = latex.replaceAll('√(', r'\sqrt(');

    while (latex.contains('/')) {
      final slashIndex = latex.indexOf('/');

      int startNum = slashIndex - 1;
      int openParens = 0;

      while (startNum >= 0) {
        if (latex[startNum] == ')') {
          openParens++;
        } else if (latex[startNum] == '(') {
          openParens--;
        }

        if (openParens < 0) {
          startNum++;
          break;
        }

        if (openParens == 0 &&
            (latex[startNum] == '+' ||
                latex[startNum] == '-' ||
                latex[startNum] == '/')) {
          startNum++;
          break;
        }

        startNum--;
      }

      if (startNum < 0) startNum = 0;

      int endNum = slashIndex + 1;
      openParens = 0;

      while (endNum < latex.length) {
        if (latex[endNum] == '(') {
          openParens++;
        } else if (latex[endNum] == ')') {
          openParens--;
        }

        if (openParens < 0) {
          endNum--;
          break;
        }

        if (openParens == 0 &&
            (latex[endNum] == '+' ||
                latex[endNum] == '-' ||
                latex[endNum] == '/')) {
          endNum--;
          break;
        }

        endNum++;
      }

      if (endNum >= latex.length) endNum = latex.length - 1;

      String num = latex.substring(startNum, slashIndex);
      String den = latex.substring(slashIndex + 1, endNum + 1);

      if (num.startsWith('(') && num.endsWith(')')) {
        num = num.substring(1, num.length - 1);
      }

      if (den.startsWith('(') && den.endsWith(')')) {
        den = den.substring(1, den.length - 1);
      }

      final fraction = r'\frac{' + num + r'}{' + den + r'}';
      latex =
          latex.substring(0, startNum) + fraction + latex.substring(endNum + 1);
    }

    return latex;
  }

  void _onButtonPressed(String buttonText) {
    setState(() {
      _errorType = '';

      if (buttonText == 'AC') {
        _undoStack.clear();
        _expression = '';
        _history = '';
        _cursorIndex = 0;
      } else if (buttonText == 'Frac' || buttonText == 'Frac✓') {
        _showCommonFractions = !_showCommonFractions;
      } else if (buttonText == 'SHIFT') {
        _isShiftMode = !_isShiftMode;
      } else if (buttonText == 'DEL') {
        if (_expression.isNotEmpty) {
          _pushUndo();
          _deleteBeforeCursor();
        }
      } else if (buttonText == 'DEG\nRAD') {
        _isDegreeMode = !_isDegreeMode;
      } else if (buttonText == 'UNDO') {
        if (_undoStack.isNotEmpty) {
          _expression = _undoStack.removeLast();
          _errorType = '';
          _cursorIndex = _expression.length;
        }
      } else if (buttonText == '=') {
        _calculateResult();
      } else if (buttonText == 'π') {
        _insertAtCursor('pi');
      } else if (buttonText == 'e') {
        _insertAtCursor('2.718281828459045');
      } else if (buttonText == 'y') {
        _insertAtCursor('y');
      } else if (buttonText == 'ans') {
        _insertAtCursor(_history.isNotEmpty ? _history : '0');
      } else if (buttonText == 'x²') {
        if (_expression.isEmpty) {
          _insertAtCursor('x^2');
        } else {
          _expression = '($_expression)^2';
          _cursorIndex = _expression.length;
        }
      } else if (buttonText == 'xʸ') {
        _insertAtCursor('^');
      } else if ([
        'sin',
        'cos',
        'tan',
        'asin',
        'acos',
        'atan',
      ].contains(buttonText)) {
        _insertAtCursor('$buttonText(');
      } else if (buttonText == 'log') {
        _expression = _expression.isEmpty
            ? 'log(100)/log(10)'
            : 'log($_expression)/log(10)';
        _cursorIndex = _expression.length;
      } else if (buttonText == 'd/dx') {
        if (_expression.isEmpty) {
          _insertAtCursor('d/dx(x^2)');
        } else {
          _insertAtCursor('d/dx(');
        }
      } else if (buttonText == '∫') {
        if (_expression.isEmpty) {
          _insertAtCursor('∫(x^2)');
        } else {
          _insertAtCursor('∫(');
        }
      } else if (buttonText == '√') {
        if (_expression.isEmpty) {
          _insertAtCursor('√(9)');
        } else {
          _insertAtCursor('√(');
        }
      } else if (buttonText == 'a/b') {
        _insertAtCursor('/');
      } else {
        _insertAtCursor(buttonText);
      }

      _clampCursor();
    });
  }

  void _calculateResult() {
    if (_expression.isEmpty) return;
    try {
      if (_expression.startsWith('d/dx(') && _expression.endsWith(')')) {
        final inner = _expression.substring(5, _expression.length - 1);
        final args = _splitTopLevelArgs(inner);
        if (args.length == 1) {
          final result = _symbolicDerivative(args[0]);
          setState(() {
            _history = _expression;
            _expression = result;
            _errorType = '';
            _cursorIndex = _expression.length;
          });
          return;
        }

        if (args.length != 2) {
          throw Exception('Syntax Error');
        }

        final x0 = double.parse(args[1]);
        final result = _calculateDerivative(args[0], x0);
        String resultStr = result.toStringAsPrecision(10);
        if (resultStr.contains('.') && resultStr.endsWith('0')) {
          resultStr = result.toString();
        }

        setState(() {
          _history = _expression;
          _expression = resultStr;
          _errorType = '';
          _cursorIndex = _expression.length;
        });
        return;
      }

      if (_expression.startsWith('∫(') && _expression.endsWith(')')) {
        final inner = _expression.substring(2, _expression.length - 1);
        final args = _splitTopLevelArgs(inner);
        if (args.length == 1) {
          final result = _symbolicIntegral(args[0]);
          setState(() {
            _history = _expression;
            _expression = result;
            _errorType = '';
            _cursorIndex = _expression.length;
          });
          return;
        }

        if (args.length != 3) {
          throw Exception('Syntax Error');
        }

        final a = double.parse(args[1]);
        final b = double.parse(args[2]);
        final result = _calculateIntegral(args[0], a, b);
        String resultStr = result.toStringAsPrecision(10);
        if (resultStr.contains('.') && resultStr.endsWith('0')) {
          resultStr = result.toString();
        }

        setState(() {
          _history = _expression;
          _expression = resultStr;
          _errorType = '';
          _cursorIndex = _expression.length;
        });
        return;
      }

      String evalStr = _expression;

      final openCount = '('.allMatches(evalStr).length;
      final closeCount = ')'.allMatches(evalStr).length;

      if (openCount > closeCount) {
        evalStr += ')' * (openCount - closeCount);
      }

      evalStr = evalStr.replaceAll('√', 'sqrt');
      // تحويل دائم لأسماء math_expressions
      evalStr = evalStr.replaceAll('asin(', '__ASIN__(');
      evalStr = evalStr.replaceAll('acos(', '__ACOS__(');
      evalStr = evalStr.replaceAll('atan(', '__ATAN__(');

      if (_isDegreeMode) {
        // تطبيق تحويل الدرجات على الدوال المباشرة فقط
        evalStr = evalStr.replaceAll('sin(', 'sin((pi/180)*');
        evalStr = evalStr.replaceAll('cos(', 'cos((pi/180)*');
        evalStr = evalStr.replaceAll('tan(', 'tan((pi/180)*');
        // إرجاع الدوال العكسية مع تحويل النتيجة من راديان لدرجات
        evalStr = evalStr.replaceAll('__ASIN__(', '(180/pi)*arcsin(');
        evalStr = evalStr.replaceAll('__ACOS__(', '(180/pi)*arccos(');
        evalStr = evalStr.replaceAll('__ATAN__(', '(180/pi)*arctan(');
      }

      if (!_isDegreeMode) {
        evalStr = evalStr.replaceAll('__ASIN__(', 'arcsin(');
        evalStr = evalStr.replaceAll('__ACOS__(', 'arccos(');
        evalStr = evalStr.replaceAll('__ATAN__(', 'arctan(');
      }

      final parser = Parser();
      final exp = parser.parse(evalStr);
      final cm = ContextModel();

      cm.bindVariable(Variable('pi'), Number(math.pi));
      cm.bindVariable(Variable('e'), Number(math.e));
      cm.bindVariable(Variable('y'), Number(_yValue));

      final eval = exp.evaluate(EvaluationType.REAL, cm);

      if (eval.isNaN || eval.isInfinite) {
        throw Exception('Math Error');
      }

      String resultStr = eval.toString();
      if (resultStr.endsWith('.0')) {
        resultStr = resultStr.substring(0, resultStr.length - 2);
      }

      setState(() {
        _history = _expression;
        _expression = resultStr;
        _errorType = '';
        _cursorIndex = _expression.length;
      });
    } catch (e) {
      setState(() {
        _history = _expression;
        _errorType = e.toString().contains('Math Error')
            ? 'Math ERROR'
            : 'Syntax ERROR';
      });
    }
  }

  Widget _buildButton(
    String text, {
    Color? bgColor,
    Color? textColor,
    bool isPrimary = false,
    required bool isDark,
  }) {
    final defaultBg = isDark ? const Color(0xFF334155) : Colors.white;
    final defaultText = isDark ? Colors.white : const Color(0xFF1E293B);

    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4.0),
        child: Material(
          color: bgColor ?? defaultBg,
          borderRadius: BorderRadius.circular(8),
          elevation: isDark ? 0 : 1,
          child: InkWell(
            onTap: () => _onButtonPressed(text),
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.blue.withOpacity(0.2),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05),
                  width: 1,
                ),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: text.length > 3 ? 13 : 18,
                  fontWeight: isPrimary ? FontWeight.bold : FontWeight.w600,
                  color: textColor ?? defaultText,
                  fontFamily: 'Roboto',
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
        child: Row(textDirection: TextDirection.ltr, children: children),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<AppProvider, bool>((p) => p.isDarkMode);

    final primaryColor = const Color(0xFF3B82F6);
    final scientificBg = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final scientificText = isDark ? Colors.grey[300] : Colors.grey[800];
    final actionBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0);
    final dangerColor = const Color(0xFFEF4444);
    final warningColor = const Color(0xFFF59E0B);

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
                // Y Variable Input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'y =',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 14,
                      fontFamily: 'Courier',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontFamily: 'Courier',
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        hintText: '0',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _isEditingY = true;
                        });
                      },
                      onChanged: (val) {
                        _yInput = val;
                        final parsed = double.tryParse(val);
                        if (parsed != null) {
                          setState(() => _yValue = parsed);
                        }
                      },
                      onEditingComplete: () {
                        setState(() {
                          _isEditingY = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 140,
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF020617)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : Colors.grey.shade300,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _history,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Courier',
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_errorType.isNotEmpty)
                    Text(
                      _errorType,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontSize: 24,
                        color: Colors.redAccent,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(
                                  context,
                                ).copyWith(
                                  dragDevices: {
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.trackpad,
                                  },
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  reverse: false,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    reverse: false,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8.0,
                                        bottom: 8.0,
                                        top: 16.0,
                                      ),
                                      child: Math.tex(
                                        _getLatexExpression(_expression),
                                        mathStyle: MathStyle.display,
                                        textStyle: TextStyle(
                                          fontSize: 36,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                        onErrorFallback: (err) {
                                          // During live typing, expressions can be temporarily incomplete
                                          // (for example trailing '^'). Show raw text instead of a red error.
                                          return Text(
                                            _expression.isEmpty
                                                ? '...'
                                                : _expression,
                                            textAlign: TextAlign.left,
                                            style: TextStyle(
                                              fontSize: 36,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              _expressionWithCaret(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'Courier',
                                color: isDark
                                    ? const Color(0xFF93C5FD)
                                    : const Color(0xFF1D4ED8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Column(
                  children: [
                    // صف 1: SHIFT, asin/log, acos/d/dx, atan/∫, AC
                    _buildKeyRow([
                      _buildButton(
                        'SHIFT',
                        bgColor: _isShiftMode
                            ? const Color(0xFF8B5CF6)
                            : scientificBg,
                        textColor: _isShiftMode ? Colors.white : scientificText,
                        isPrimary: _isShiftMode,
                        isDark: isDark,
                      ),
                      _buildButton(
                        _isShiftMode ? 'log' : 'asin',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        _isShiftMode ? 'd/dx' : 'acos',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        _isShiftMode ? '∫' : 'atan',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        'AC',
                        bgColor: dangerColor,
                        textColor: Colors.white,
                        isPrimary: true,
                        isDark: isDark,
                      ),
                    ]),
                    // صف 2: sin, cos, tan, xʸ/x², DEL
                    _buildKeyRow([
                      _buildButton(
                        'sin',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        'cos',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        'tan',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        _isShiftMode ? 'x²' : 'xʸ',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        'DEL',
                        bgColor: warningColor,
                        textColor: Colors.white,
                        isPrimary: true,
                        isDark: isDark,
                      ),
                    ]),
                    // صف 3: a/b, √, π, e/ans, UNDO
                    _buildKeyRow([
                      _buildButton(
                        _isShiftMode
                            ? (_showCommonFractions ? 'Frac✓' : 'Frac')
                            : 'a/b',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        '√',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        'π',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        _isShiftMode ? 'ans' : 'e',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        'UNDO',
                        bgColor: scientificBg,
                        textColor: warningColor,
                        isDark: isDark,
                      ),
                    ]),
                    // صف 4: y, (, )
                    _buildKeyRow([
                      _buildButton(
                        'y',
                        bgColor: const Color(0xFF0F766E),
                        textColor: Colors.white,
                        isDark: isDark,
                      ),
                      _buildButton(
                        '(',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                      _buildButton(
                        ')',
                        bgColor: scientificBg,
                        textColor: scientificText,
                        isDark: isDark,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton('7', isDark: isDark),
                      _buildButton('8', isDark: isDark),
                      _buildButton('9', isDark: isDark),
                      _buildButton(
                        '/',
                        bgColor: actionBg,
                        textColor: primaryColor,
                        isDark: isDark,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton('4', isDark: isDark),
                      _buildButton('5', isDark: isDark),
                      _buildButton('6', isDark: isDark),
                      _buildButton(
                        '*',
                        bgColor: actionBg,
                        textColor: primaryColor,
                        isDark: isDark,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton('1', isDark: isDark),
                      _buildButton('2', isDark: isDark),
                      _buildButton('3', isDark: isDark),
                      _buildButton(
                        '-',
                        bgColor: actionBg,
                        textColor: primaryColor,
                        isDark: isDark,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton(
                        'DEG\nRAD',
                        bgColor: _isDegreeMode
                            ? const Color(0xFF10B981)
                            : actionBg,
                        textColor: _isDegreeMode
                            ? Colors.white
                            : scientificText,
                        isDark: isDark,
                      ),
                      _buildButton('0', isDark: isDark),
                      _buildButton('.', isDark: isDark),
                      _buildButton(
                        '+',
                        bgColor: actionBg,
                        textColor: primaryColor,
                        isDark: isDark,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton(
                        '=',
                        bgColor: primaryColor,
                        textColor: Colors.white,
                        isPrimary: true,
                        isDark: isDark,
                      ),
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
