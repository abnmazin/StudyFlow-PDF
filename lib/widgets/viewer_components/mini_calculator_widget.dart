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
  String _errorType = '';

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
      latex = latex.substring(0, startNum) + fraction + latex.substring(endNum + 1);
    }

    return latex;
  }

  void _onButtonPressed(String buttonText) {
    setState(() {
      _errorType = '';

      if (buttonText == 'AC') {
        _expression = '';
        _history = '';
      } else if (buttonText == 'DEL') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (buttonText == 'DEG\nRAD') {
        _isDegreeMode = !_isDegreeMode;
      } else if (buttonText == '=') {
        _calculateResult();
      } else if (['sin', 'cos', 'tan', 'asin', 'acos', 'atan']
          .contains(buttonText)) {
        _expression += '$buttonText(';
      } else if (buttonText == '√') {
        _expression += '√(';
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
        _errorType =
            e.toString().contains('Math Error') ? 'Math ERROR' : 'Syntax ERROR';
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
        child: Row(
          textDirection: TextDirection.ltr,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<AppProvider>().isDarkMode;

    final primaryColor = const Color(0xFF3B82F6);
    final scientificBg =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final scientificText = isDark ? Colors.grey[300] : Colors.grey[800];
    final actionBg =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0);
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

            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Column(
                  children: [
                    _buildKeyRow([
                      _buildButton('asin',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('acos',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('atan',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('AC',
                          bgColor: dangerColor,
                          textColor: Colors.white,
                          isPrimary: true),
                    ]),
                    _buildKeyRow([
                      _buildButton('sin',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('cos',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('tan',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('DEL',
                          bgColor: warningColor,
                          textColor: Colors.white,
                          isPrimary: true),
                    ]),
                    _buildKeyRow([
                      _buildButton('a/b',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('√',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton('(',
                          bgColor: scientificBg, textColor: scientificText),
                      _buildButton(')',
                          bgColor: scientificBg, textColor: scientificText),
                    ]),
                    _buildKeyRow([
                      _buildButton('7'),
                      _buildButton('8'),
                      _buildButton('9'),
                      _buildButton('/',
                          bgColor: actionBg, textColor: primaryColor),
                    ]),
                    _buildKeyRow([
                      _buildButton('4'),
                      _buildButton('5'),
                      _buildButton('6'),
                      _buildButton('*',
                          bgColor: actionBg, textColor: primaryColor),
                    ]),
                    _buildKeyRow([
                      _buildButton('1'),
                      _buildButton('2'),
                      _buildButton('3'),
                      _buildButton('-',
                          bgColor: actionBg, textColor: primaryColor),
                    ]),
                    _buildKeyRow([
                      _buildButton(
                        'DEG\nRAD',
                        bgColor:
                            _isDegreeMode ? const Color(0xFF10B981) : actionBg,
                        textColor:
                            _isDegreeMode ? Colors.white : scientificText,
                      ),
                      _buildButton('0'),
                      _buildButton('.'),
                      _buildButton('+',
                          bgColor: actionBg, textColor: primaryColor),
                    ]),
                    _buildKeyRow([
                      _buildButton('=',
                          bgColor: primaryColor,
                          textColor: Colors.white,
                          isPrimary: true),
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