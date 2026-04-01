import 'package:flutter/material.dart';
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
  bool _isDegreeMode = true;
  bool _isShiftMode = false;
  bool _showCommonFractions = true;
  String _errorType = '';

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
    int maxDenominator = 99,
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

    return (
      numerator: bestNumerator ~/ gcd,
      denominator: bestDenominator ~/ gcd,
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

    if (_isDegreeMode) {
      evalStr = evalStr.replaceAll('sin(', 'sin((pi/180)*');
      evalStr = evalStr.replaceAll('cos(', 'cos((pi/180)*');
      evalStr = evalStr.replaceAll('tan(', 'tan((pi/180)*');
    }

    final parser = Parser();
    final parsed = parser.parse(evalStr);
    final cm = ContextModel();
    cm.bindVariable(Variable('pi'), Number(math.pi));
    cm.bindVariable(Variable('e'), Number(math.e));
    cm.bindVariable(Variable('x'), Number(xValue));

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
        _expression = '';
        _history = '';
      } else if (buttonText == 'Frac' || buttonText == 'Frac✓') {
        _showCommonFractions = !_showCommonFractions;
      } else if (buttonText == 'SHIFT') {
        _isShiftMode = !_isShiftMode;
      } else if (buttonText == 'DEL') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (buttonText == 'DEG\nRAD') {
        _isDegreeMode = !_isDegreeMode;
      } else if (buttonText == '=') {
        _calculateResult();
      } else if ([
        'sin',
        'cos',
        'tan',
        'asin',
        'acos',
        'atan',
      ].contains(buttonText)) {
        _expression += '$buttonText(';
      } else if (buttonText == 'log') {
        _expression = _expression.isEmpty ? 'log(10)' : 'log($_expression)';
      } else if (buttonText == 'd/dx') {
        _expression = _expression.isEmpty ? 'd/dx(x^2)' : 'd/dx($_expression)';
      } else if (buttonText == '∫') {
        _expression = _expression.isEmpty ? '∫(x^2)' : '∫($_expression)';
      } else if (buttonText == '√') {
        _expression = _expression.isEmpty ? '√(9)' : '√($_expression)';
      } else if (buttonText == 'a/b') {
        _expression += '/';
      } else {
        _expression += buttonText;
      }
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

      if (_isDegreeMode) {
        evalStr = evalStr.replaceAll('sin(', 'sin((pi/180)*');
        evalStr = evalStr.replaceAll('cos(', 'cos((pi/180)*');
        evalStr = evalStr.replaceAll('tan(', 'tan((pi/180)*');
      }

      final parser = Parser();
      final exp = parser.parse(evalStr);
      final cm = ContextModel();

      cm.bindVariable(Variable('pi'), Number(math.pi));
      cm.bindVariable(Variable('e'), Number(math.e));

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
  }) {
    final isDark = context.watch<AppProvider>().isDarkMode;

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
    final isDark = context.watch<AppProvider>().isDarkMode;

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
      child: Container(
        color: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
        child: Column(
          children: [
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

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Column(
                  children: [
                    _buildKeyRow([
                      _buildButton(
                        'SHIFT',
                        bgColor: _isShiftMode
                            ? const Color(0xFF8B5CF6)
                            : scientificBg,
                        textColor: _isShiftMode ? Colors.white : scientificText,
                        isPrimary: _isShiftMode,
                      ),
                      _buildButton(
                        _isShiftMode ? 'log' : 'asin',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        _isShiftMode ? 'd/dx' : 'acos',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        'AC',
                        bgColor: dangerColor,
                        textColor: Colors.white,
                        isPrimary: true,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton(
                        _isShiftMode ? '∫' : 'sin',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        _isShiftMode ? 'x' : 'cos',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        _isShiftMode ? '^' : 'tan',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        'DEL',
                        bgColor: warningColor,
                        textColor: Colors.white,
                        isPrimary: true,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton(
                        _isShiftMode
                            ? (_showCommonFractions ? 'Frac✓' : 'Frac')
                            : 'a/b',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        '√',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        '(',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                      _buildButton(
                        ')',
                        bgColor: scientificBg,
                        textColor: scientificText,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton('7'),
                      _buildButton('8'),
                      _buildButton('9'),
                      _buildButton(
                        '/',
                        bgColor: actionBg,
                        textColor: primaryColor,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton('4'),
                      _buildButton('5'),
                      _buildButton('6'),
                      _buildButton(
                        '*',
                        bgColor: actionBg,
                        textColor: primaryColor,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton('1'),
                      _buildButton('2'),
                      _buildButton('3'),
                      _buildButton(
                        '-',
                        bgColor: actionBg,
                        textColor: primaryColor,
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
                      ),
                      _buildButton('0'),
                      _buildButton('.'),
                      _buildButton(
                        '+',
                        bgColor: actionBg,
                        textColor: primaryColor,
                      ),
                    ]),
                    _buildKeyRow([
                      _buildButton(
                        '=',
                        bgColor: primaryColor,
                        textColor: Colors.white,
                        isPrimary: true,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
