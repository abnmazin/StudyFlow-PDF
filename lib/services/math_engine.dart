import 'dart:math' as math;
import 'package:texpr/texpr.dart';

/// Math result wrapper supporting real and complex outputs
class MathResult {
  final bool isSuccess;
  final String? error;
  final double? realValue;
  final ({double real, double imag})? complexValue;
  final String? symbolicResult;

  MathResult({
    required this.isSuccess,
    this.error,
    this.realValue,
    this.complexValue,
    this.symbolicResult,
  });

  /// Get display-friendly string for UI
  String toDisplayString() {
    if (!isSuccess) return 'Error: $error';
    if (symbolicResult != null) return symbolicResult!;
    if (complexValue != null) {
      final real = complexValue!.real;
      final imag = complexValue!.imag;
      if (imag == 0) return _formatNumber(real);
      if (real == 0) return '${_formatNumber(imag)}i';
      final sign = imag > 0 ? '+' : '';
      return '${_formatNumber(real)}${sign}${_formatNumber(imag)}i';
    }
    if (realValue != null) return _formatNumber(realValue!);
    return 'No result';
  }

  /// Format number with smart fraction display
  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsPrecision(10)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Approximate fraction (up to denominator 16)
  static ({int numerator, int denominator}) approximateFraction(
    double value, {
    int maxDenominator = 16,
  }) {
    int bestNum = value.round(), bestDen = 1;
    double bestErr = (value - bestNum).abs();
    for (int d = 1; d <= maxDenominator; d++) {
      final n = (value * d).round();
      final err = (value - n / d).abs();
      if (err < bestErr) {
        bestErr = err;
        bestNum = n;
        bestDen = d;
      }
    }
    int a = bestNum.abs(), b = bestDen;
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    final gcd = a == 0 ? 1 : a;
    return (numerator: bestNum ~/ gcd, denominator: bestDen ~/ gcd);
  }
}

/// Unified math engine for StudyFlow calculator
/// Uses texpr for expression parsing and numerical methods for calculus
class MathEngine {
  static final MathEngine _instance = MathEngine._internal();

  factory MathEngine() => _instance;

  MathEngine._internal();

  /// Normalizes UI-friendly mathematical expressions into texpr-compatible strings
  String _normalizeForTexpr(String expr) {
    String s = expr;

    // Implicit multiplication
    s = s.replaceAllMapped(
      RegExp(r'(\d)([a-zA-Z(])'),
      (m) => '${m[1]}*${m[2]}',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\))([a-zA-Z0-9(])'),
      (m) => '${m[1]}*${m[2]}',
    );

    // 1. Map natural log
    s = s.replaceAll('ln(', 'log(');

    // 2. Convert square root to power: √(x) -> ((x)^(1/2))
    while (s.contains('√(')) {
      final idx = s.indexOf('√(');
      int depth = 1, end = idx + 2;
      while (depth > 0 && end < s.length) {
        if (s[end] == '(') depth++;
        if (s[end] == ')') depth--;
        end++;
      }
      if (depth != 0) break; // Malformed
      final inner = s.substring(idx + 2, end - 1);
      s = '${s.substring(0, idx)}(($inner)^(1/2))${s.substring(end)}';
    }

    // 3. Convert cube root to power: cbrt(x) -> ((x)^(1/3))
    while (s.contains('cbrt(')) {
      final idx = s.indexOf('cbrt(');
      int depth = 1, end = idx + 5;
      while (depth > 0 && end < s.length) {
        if (s[end] == '(') depth++;
        if (s[end] == ')') depth--;
        end++;
      }
      if (depth != 0) break; // Malformed
      final inner = s.substring(idx + 5, end - 1);
      s = '${s.substring(0, idx)}(($inner)^(1/3))${s.substring(end)}';
    }

    // 4. Expand log10(x) -> (log(x)/log(10))
    while (s.contains('log10(')) {
      final idx = s.indexOf('log10(');
      int depth = 1, end = idx + 6;
      while (depth > 0 && end < s.length) {
        if (s[end] == '(') depth++;
        if (s[end] == ')') depth--;
        end++;
      }
      if (depth != 0) break; // Malformed
      final inner = s.substring(idx + 6, end - 1);
      s = '${s.substring(0, idx)}(log($inner)/log(10))${s.substring(end)}';
    }

    return s;
  }

  /// Evaluate mathematical expression with variable substitution
  MathResult evaluate(String expression, [Map<String, double>? variables]) {
    try {
      final vars = Map<String, double>.from(variables ?? <String, double>{});
      vars['pi'] = math.pi;
      vars['e'] = math.e;
      expression = _normalizeForTexpr(expression);
      final texpr = Texpr();

      try {
        // Use texpr's evaluateNumeric method (correct API)
        final result = texpr.evaluateNumeric(expression, vars);

        if (result.isNaN || result.isInfinite) {
          return MathResult(isSuccess: false, error: 'Math Error');
        }
        return MathResult(isSuccess: true, realValue: result);
      } catch (texprError) {
        // Fallback to basic evaluation
        return _evaluateFallback(expression, vars);
      }
    } catch (e) {
      return MathResult(isSuccess: false, error: e.toString());
    }
  }

  /// Fallback evaluation using basic math functions
  MathResult _evaluateFallback(
    String expression,
    Map<String, double> variables,
  ) {
    try {
      // Replace variables with values
      String expr = expression;
      for (final entry in variables.entries) {
        expr = expr.replaceAll(entry.key, entry.value.toString());
      }

      // Replace constants
      expr = expr.replaceAll('pi', math.pi.toString());
      expr = expr.replaceAll('e', math.e.toString());

      // For now, return error - real implementation would need a parser
      return MathResult(
        isSuccess: false,
        error: 'Evaluation requires texpr package',
      );
    } catch (e) {
      return MathResult(
        isSuccess: false,
        error: 'Fallback evaluation failed: $e',
      );
    }
  }

  /// Symbolic differentiation
  String differentiate(String expression, String variable) {
    try {
      expression = _normalizeForTexpr(expression);
      final texpr = Texpr();
      // differentiate returns an Expression (AST)
      final derivative = texpr.differentiate(expression, variable);

      // Try to get a readable representation
      String result = _formatExpressionAst(derivative);

      return result;
    } catch (e) {
      return 'Differentiation error: ${e.toString()}';
    }
  }

  /// Format texpr Expression AST to human-readable string
  String _formatExpressionAst(dynamic expr) {
    if (expr == null) return '0';

    final exprStr = expr.toString();

    // Fallback: use regex-based parsing of common AST patterns
    return _simplifyAstString(exprStr);
  }

  /// Simplify AST string representation to readable math
  String _simplifyAstString(String astStr) {
    // Recursively process nested BinaryOp structures
    var result = astStr;

    // Keep processing until no more BinaryOp patterns exist
    int iterations = 0;
    while (result.contains('BinaryOp(') && iterations < 20) {
      iterations++;
      result = _processBinaryOp(result);
    }

    // Clean up remaining artifacts
    result = result.replaceAllMapped(
      RegExp(r'NumberLiteral\(([\d.]+)\)'),
      (match) => match[1]!,
    );
    result = result.replaceAllMapped(
      RegExp(r'Variable\((\w+)\)'),
      (match) => match[1]!,
    );
    result = result.replaceAllMapped(
      RegExp(r'FunctionCall\((\w+)'),
      (match) => match[1]!,
    );
    result = result.replaceAll(RegExp(r'[\[\]]'), '');
    result = result.replaceAll(RegExp(r'\.0(?![0-9])'), '');
    result = _simplifyReadablePowers(result);

    // Clean up redundant calculus exponents and multipliers
    result = result.replaceAllMapped(
      RegExp(r'\^\(([0-9]+(?:\.[0-9]+)?)\-1\)'),
      (m) {
        final val = double.parse(m[1]!) - 1;
        if (val == 0) return '^0';
        if (val == 1) return '';
        return '^${val == val.toInt() ? val.toInt() : val}';
      },
    );
    result = result.replaceAll(RegExp(r'[a-zA-Z]+\^0|\([^\)]+\)\^0'), '1');
    result = result.replaceAllMapped(RegExp(r'\(([a-zA-Z])\)'), (m) => m[1]!);
    result = result.replaceAll(RegExp(r'\*1(?!\d)'), '');
    result = result.replaceAll(RegExp(r'(?<!\d)1\*'), '');

    result = result.trim();
    // Remove fully wrapping outer parentheses to make it cleaner
    while (result.startsWith('(') && result.endsWith(')')) {
      int depth = 0;
      bool fullyWrapped = true;
      for (int i = 0; i < result.length - 1; i++) {
        if (result[i] == '(') depth++;
        if (result[i] == ')') depth--;
        if (depth == 0) {
          fullyWrapped = false;
          break;
        }
      }
      if (fullyWrapped) {
        result = result.substring(1, result.length - 1).trim();
      } else {
        break;
      }
    }

    return result;
  }

  /// Process one level of BinaryOp: BinaryOp(left, BinaryOperator.op, right) -> left op right
  String _processBinaryOp(String str) {
    // Find the first BinaryOp and extract its components
    final startIdx = str.indexOf('BinaryOp(');
    if (startIdx == -1) return str;

    // Find matching closing parenthesis for BinaryOp(
    int parenDepth = 0;
    int endIdx = -1;

    for (int i = startIdx + 9; i < str.length; i++) {
      // 9 = length of 'BinaryOp('
      if (str[i] == '(') parenDepth++;
      if (str[i] == ')') {
        if (parenDepth == 0) {
          endIdx = i;
          break;
        }
        parenDepth--;
      }
    }

    if (endIdx == -1) return str;

    // Extract the content between BinaryOp( and )
    final content = str.substring(startIdx + 9, endIdx);

    // Split on ', BinaryOperator.' to separate left, operator, right
    final parts = _splitBinaryOp(content);
    if (parts.length != 3) return str;

    final left = parts[0].trim();
    final opName = parts[1].trim();
    final right = parts[2].trim();

    final op = _operatorSymbol(opName);
    final replacement = '($left$op$right)';

    return str.substring(0, startIdx) + replacement + str.substring(endIdx + 1);
  }

  /// Split BinaryOp content respecting nested parentheses
  /// Returns [left, operator, right]
  List<String> _splitBinaryOp(String content) {
    // Find ', BinaryOperator.' which separates the parts
    int parenDepth = 0;
    int bracketDepth = 0;

    for (int i = 0; i < content.length - 15; i++) {
      // 15 = min length of ', BinaryOperator.'
      if (content[i] == '(') parenDepth++;
      if (content[i] == ')') parenDepth--;
      if (content[i] == '[') bracketDepth++;
      if (content[i] == ']') bracketDepth--;

      if (parenDepth == 0 &&
          bracketDepth == 0 &&
          content.startsWith(', BinaryOperator.', i)) {
        // Found the separator
        final left = content.substring(0, i);

        // Extract operator name
        int opStart = i + 17; // 17 = length of ', BinaryOperator.'
        int opEnd = opStart;
        while (opEnd < content.length) {
          final code = content.codeUnitAt(opEnd);
          final isAlphaNumeric =
              (code >= 48 && code <= 57) ||
              (code >= 65 && code <= 90) ||
              (code >= 97 && code <= 122);
          if (!isAlphaNumeric && content[opEnd] != '_') {
            break;
          }
          opEnd++;
        }
        final op = content.substring(opStart, opEnd);

        // Find the right side: should start with ', '
        int rightStart = opEnd + 2; // skip ', '
        final right = content.substring(rightStart);

        return [left, op, right];
      }
    }

    return [];
  }

  /// Map texpr operator names to math symbols
  String _operatorSymbol(String opName) {
    switch (opName) {
      case 'multiply':
        return '';
      case 'plus':
        return '+';
      case 'subtract':
        return '-';
      case 'divide':
        return '/';
      case 'power':
        return '^';
      default:
        return opName;
    }
  }

  /// Simplify common readable power patterns after AST flattening.
  String _simplifyReadablePowers(String input) {
    var result = input;

    // x^1 -> x, (x)^1 -> x
    result = result.replaceAllMapped(
      RegExp(r'\(([^()]+)\)\^1(?![0-9])'),
      (match) => match[1]!,
    );
    result = result.replaceAllMapped(
      RegExp(r'([A-Za-z0-9]+)\^1(?![0-9])'),
      (match) => match[1]!,
    );

    // x^0 -> 1, (x)^0 -> 1
    result = result.replaceAllMapped(
      RegExp(r'\(([^()]+)\)\^0(?![0-9])'),
      (_) => '1',
    );
    result = result.replaceAllMapped(
      RegExp(r'([A-Za-z0-9]+)\^0(?![0-9])'),
      (_) => '1',
    );

    return result;
  }

  /// Integration - symbolic for basic patterns, numerical for definite integrals
  String integrate(
    String expression,
    String variable, [
    double? lowerBound,
    double? upperBound,
  ]) {
    try {
      expression = _normalizeForTexpr(expression);
      if (lowerBound != null && upperBound != null) {
        // Definite integral (numerical using Simpson's rule)
        final result = numericalIntegral(
          expression,
          variable,
          lowerBound,
          upperBound,
        );
        if (result.isNaN) return 'Integration failed';
        return MathResult._formatNumber(result);
      } else {
        // Indefinite integral (symbolic for basic patterns)
        return _symbolicIntegrate(expression, variable);
      }
    } catch (e) {
      return 'Integration error: ${e.toString()}';
    }
  }

  /// Symbolic integration for common patterns
  /// Supports: polynomials, trig, exponential, logarithmic
  String _symbolicIntegrate(String expr, String variable) {
    try {
      expr = expr.trim();

      // Handle simple power: x^n or x (where n is constant)
      final powerMatch = RegExp(
        '$variable\\^\\(([^)]+)\\)|$variable\\^([0-9.]+)|^$variable\$',
      ).firstMatch(expr);
      if (powerMatch != null) {
        final expStr = powerMatch.group(1) ?? powerMatch.group(2) ?? '1';
        final exponent = double.tryParse(expStr) ?? 1.0;

        if (exponent == -1) {
          return 'ln($variable) + C';
        }

        final newExp = exponent + 1;
        final coeff = 1 / newExp;
        final frac = MathResult.approximateFraction(coeff);
        final coeffStr = frac.denominator == 1
            ? frac.numerator.toString()
            : '${frac.numerator}/${frac.denominator}';

        if (newExp == 0) {
          return '1 + C';
        } else if (newExp == 1) {
          return '$variable + C';
        } else {
          return '$coeffStr*$variable^${newExp.toInt()} + C';
        }
      }

      // Handle coefficient * x^n: e.g., "3*x^2"
      final coeffPowerMatch = RegExp(
        r'([0-9.]+)\s*\*?\s*' + variable + r'(?:\^([0-9.]+))?',
      ).firstMatch(expr);
      if (coeffPowerMatch != null) {
        final coeff = double.parse(coeffPowerMatch.group(1)!);
        final expStr = coeffPowerMatch.group(2) ?? '1';
        final exponent = double.tryParse(expStr) ?? 1.0;

        if (exponent == -1) {
          final frac = MathResult.approximateFraction(coeff);
          final coeffStr = frac.denominator == 1
              ? frac.numerator.toString()
              : '${frac.numerator}/${frac.denominator}';
          return '$coeffStr*ln($variable) + C';
        }

        final newExp = exponent + 1;
        final newCoeff = coeff / newExp;
        final frac = MathResult.approximateFraction(newCoeff);
        final coeffStr = frac.denominator == 1
            ? frac.numerator.toString()
            : '${frac.numerator}/${frac.denominator}';

        if (newExp == 1) {
          return '$coeffStr*$variable + C';
        } else {
          return '$coeffStr*$variable^${newExp.toInt()} + C';
        }
      }

      // Handle sin(x)
      if (expr.contains('sin($variable)') || expr == 'sin($variable)') {
        return '-cos($variable) + C';
      }

      // Handle cos(x)
      if (expr.contains('cos($variable)') || expr == 'cos($variable)') {
        return 'sin($variable) + C';
      }

      // Handle e^x
      if (expr.contains('e^$variable') ||
          expr == 'e^$variable' ||
          expr == 'e^($variable)') {
        return 'e^$variable + C';
      }

      // Handle ln(x)
      if (expr.contains('ln($variable)') || expr == 'ln($variable)') {
        return '$variable*ln($variable) - $variable + C';
      }

      // Fallback
      return 'Symbolic integration not supported for this pattern';
    } catch (e) {
      return 'Symbolic integration error: ${e.toString()}';
    }
  }

  /// Solve equations numerically
  String solveEquation(String equation) {
    try {
      final parts = equation.split('=');
      if (parts.length != 2) {
        return 'Invalid equation format (must contain "=")';
      }

      final lhs = parts[0].trim();
      final rhs = parts[1].trim();

      // Detect which variable to solve for (x, y, or other)
      final variable = _detectVariable('$lhs=$rhs');

      return _solveNumerically(lhs, rhs, variable);
    } catch (e) {
      return 'Solver error: ${e.toString()}';
    }
  }

  /// Detect the variable in an equation (x, y, or first alphabetic character)
  String _detectVariable(String equation) {
    // Look for x or y first
    if (equation.contains('x')) return 'x';
    if (equation.contains('y')) return 'y';

    // Find first single-letter variable (a-z, excluding known functions)
    final reserved = {
      'sin',
      'cos',
      'tan',
      'asin',
      'acos',
      'atan',
      'log',
      'ln',
      'sqrt',
      'abs',
      'cbrt',
      'e',
      'pi',
      'i',
    };
    for (final match in RegExp(r'\b([a-z])\b').allMatches(equation)) {
      final char = match.group(1)!;
      if (!reserved.contains(char)) return char;
    }

    // Default to x
    return 'x';
  }

  /// Solve lhs = rhs using Newton-Raphson method, solving for the given variable
  String _solveNumerically(String lhs, String rhs, String variable) {
    try {
      lhs = _normalizeForTexpr(lhs);
      rhs = _normalizeForTexpr(rhs);
      const maxIter = 100;
      const tol = 1e-10;
      final solutions = <double>[];

      for (final start in [0.0, 1.0, -1.0, 2.0, -2.0, 5.0, -5.0, 10.0]) {
        double x = start;

        for (int i = 0; i < maxIter; i++) {
          final fxResult = evaluate('($lhs) - ($rhs)', {variable: x});
          if (!fxResult.isSuccess || fxResult.realValue == null) break;
          final fx = fxResult.realValue!;

          if (fx.abs() < tol) {
            // Found solution
            bool isDuplicate = solutions.any((sol) => (sol - x).abs() < tol);
            if (!isDuplicate) {
              solutions.add(x);
            }
            break;
          }

          // Numerical derivative
          final h = 1e-7;
          final fxPlus = evaluate('($lhs) - ($rhs)', {variable: x + h});
          final fxMinus = evaluate('($lhs) - ($rhs)', {variable: x - h});

          if (!fxPlus.isSuccess || !fxMinus.isSuccess) break;

          final dfx = (fxPlus.realValue! - fxMinus.realValue!) / (2 * h);

          if (dfx.abs() < 1e-15) break;

          final xn = x - fx / dfx;
          if ((xn - x).abs() < tol) break;

          x = xn;
        }
      }

      if (solutions.isEmpty) {
        return 'No solution found';
      }

      final formatted = solutions
          .map((sol) => '$variable = ${MathResult._formatNumber(sol)}')
          .toList();
      return formatted.join(', ');
    } catch (e) {
      return 'Solver error: ${e.toString()}';
    }
  }

  /// Convert expression to LaTeX format
  String toLatex(String expression) {
    try {
      String latex = expression;

      latex = latex.replaceAll('pi', r'\pi');
      latex = latex.replaceAll('sin(', r'\sin(');
      latex = latex.replaceAll('cos(', r'\cos(');
      latex = latex.replaceAll('tan(', r'\tan(');
      latex = latex.replaceAll('sqrt(', r'\sqrt{');
      latex = latex.replaceAll('*', r'\times');

      return latex;
    } catch (e) {
      return expression;
    }
  }

  /// Numerical derivative at point using central difference
  double numericalDerivative(
    String expression,
    String variable,
    double atPoint, {
    double step = 1e-5,
  }) {
    try {
      final h = step;

      final fPlus = evaluate(expression, {variable: atPoint + h});
      final fMinus = evaluate(expression, {variable: atPoint - h});

      if (!fPlus.isSuccess || !fMinus.isSuccess) {
        return double.nan;
      }

      return (fPlus.realValue! - fMinus.realValue!) / (2 * h);
    } catch (e) {
      return double.nan;
    }
  }

  /// Numerical integration using Simpson's rule
  double numericalIntegral(
    String expression,
    String variable,
    double from,
    double to, {
    int steps = 200,
  }) {
    try {
      final h = (to - from) / steps;

      final fFrom = evaluate(expression, {variable: from});
      final fTo = evaluate(expression, {variable: to});

      if (!fFrom.isSuccess || !fTo.isSuccess) {
        return double.nan;
      }

      double sum = (fFrom.realValue ?? 0.0) + (fTo.realValue ?? 0.0);

      for (int i = 1; i < steps; i++) {
        final x = from + i * h;
        final fX = evaluate(expression, {variable: x});

        if (fX.isSuccess && fX.realValue != null) {
          final weight = (i % 2 == 0) ? 2.0 : 4.0;
          sum += weight * fX.realValue!;
        }
      }

      return (h / 3.0) * sum;
    } catch (e) {
      return double.nan;
    }
  }

  /// Split comma-separated arguments respecting parentheses
  List<String> splitTopLevelArgs(String input) {
    final parts = <String>[];
    final buf = StringBuffer();
    int depth = 0;
    for (final ch in input.runes) {
      final c = String.fromCharCode(ch);
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == ',' && depth == 0) {
        parts.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    if (buf.isNotEmpty) parts.add(buf.toString().trim());
    return parts;
  }
}
