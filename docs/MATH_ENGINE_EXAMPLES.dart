/// Example usage of MathEngine in StudyFlow Mini Calculator
/// This file demonstrates common operations and how the engine integrates
/// with the Flutter UI layer.

import 'package:studyflow_pdf/services/math_engine.dart';

void main() {
  final engine = MathEngine();

  // ─── Example 1: Basic Arithmetic ───────────────────────────────────────
  print('=== Example 1: Basic Arithmetic ===');
  var result = engine.evaluate('2 + 3 * 4');
  print('2 + 3 * 4 = ${result.toDisplayString()}'); // 14

  result = engine.evaluate('(10 + 5) / 3');
  print('(10 + 5) / 3 = ${result.toDisplayString()}'); // 5

  // ─── Example 2: Variables ──────────────────────────────────────────────
  print('\n=== Example 2: Variables ===');
  result = engine.evaluate(r'\pi * r^2', {'r': 3.0});
  print('πr² with r=3 = ${result.toDisplayString()}'); // ≈ 28.27

  result = engine.evaluate(r'\sin(x)', {'x': 1.5708}); // π/2
  print('sin(π/2) = ${result.toDisplayString()}'); // ≈ 1.0

  // ─── Example 3: Complex Numbers ───────────────────────────────────────
  print('\n=== Example 3: Complex Numbers ===');
  result = engine.evaluate('(3 + 4i) * (1 - 2i)');
  print('(3 + 4i) * (1 - 2i) = ${result.toDisplayString()}'); // 11 - 2i

  result = engine.evaluate(r'e^{i*\pi}'); // Euler's formula
  print('e^(iπ) = ${result.toDisplayString()}'); // -1

  if (result.complexValue != null) {
    print('  Real: ${result.complexValue!.real}');
    print('  Imag: ${result.complexValue!.imag}');
  }

  // ─── Example 4: Functions ──────────────────────────────────────────────
  print('\n=== Example 4: Mathematical Functions ===');
  result = engine.evaluate('sqrt(16) + abs(-5)');
  print('√16 + |-5| = ${result.toDisplayString()}'); // 9

  result = engine.evaluate('log10(1000) + ln(e)');
  print('log₁₀(1000) + ln(e) = ${result.toDisplayString()}'); // 4

  result = engine.evaluate('max(5, 3) + min(2, 8)');
  print('max(5, 3) + min(2, 8) = ${result.toDisplayString()}'); // 7

  // ─── Example 5: Symbolic Differentiation ──────────────────────────────
  print('\n=== Example 5: Symbolic Differentiation ===');
  var derivative = engine.differentiate(r'x^3 + 2x^2 + x + 1', 'x');
  print('d/dx(x³ + 2x² + x + 1) = $derivative'); // 3x² + 4x + 1

  derivative = engine.differentiate(r'\sin(x) + \cos(x)', 'x');
  print('d/dx(sin(x) + cos(x)) = $derivative'); // cos(x) - sin(x)

  derivative = engine.differentiate(r'x * e^x', 'x');
  print('d/dx(xe^x) = $derivative'); // e^x(x + 1)

  // ─── Example 6: Numerical Derivative ───────────────────────────────────
  print('\n=== Example 6: Numerical Derivative at Point ===');
  var deriv = engine.numericalDerivative(r'\sin(x)', 'x', 0.0);
  print('d/dx(sin(x)) at x=0 ≈ $deriv'); // ≈ 1.0 (cos(0))

  deriv = engine.numericalDerivative(r'x^2', 'x', 2.0);
  print('d/dx(x²) at x=2 ≈ $deriv'); // ≈ 4.0 (2*x)

  // ─── Example 7: Symbolic Integration ───────────────────────────────────
  print('\n=== Example 7: Symbolic Integration ===');
  var integral = engine.integrate(r'x^2', 'x');
  print('∫ x² dx = $integral'); // x³/3 + C

  integral = engine.integrate(r'\cos(x)', 'x');
  print('∫ cos(x) dx = $integral'); // sin(x) + C

  // ─── Example 8: Numerical Integration (Definite Integral) ─────────────
  print('\n=== Example 8: Numerical Integration ===');
  var result_num = engine.numericalIntegral(r'x^2', 'x', 0.0, 1.0);
  print('∫₀¹ x² dx ≈ $result_num'); // ≈ 0.333 (1/3)

  result_num = engine.numericalIntegral(r'\sin(x)', 'x', 0.0, 3.14159);
  print('∫₀^π sin(x) dx ≈ $result_num'); // ≈ 2.0

  // ─── Example 9: Equation Solving ──────────────────────────────────────
  print('\n=== Example 9: Equation Solving ===');
  var solution = engine.solveEquation('2x + 3 = 0');
  print('2x + 3 = 0 → $solution'); // x = -1.5

  solution = engine.solveEquation('x^2 - 5x + 6 = 0');
  print('x² - 5x + 6 = 0 → $solution'); // x ∈ {2, 3}

  solution = engine.solveEquation('x^2 + 1 = 0');
  print('x² + 1 = 0 → $solution'); // x = ±i (complex)

  // ─── Example 10: Error Handling ───────────────────────────────────────
  print('\n=== Example 10: Error Handling ===');
  result = engine.evaluate('1/0');
  if (!result.isSuccess) {
    print('Error: ${result.error}');
  }

  result = engine.evaluate('sqrt(-1)');
  print('√(-1) = ${result.toDisplayString()}'); // Should be i

  // ─── Example 11: LaTeX Conversion ─────────────────────────────────────
  print('\n=== Example 11: LaTeX Conversion ===');
  var latex = engine.toLatex('2*pi*r^2');
  print('2πr² in LaTeX: $latex'); // 2\pi r^2

  // ─── Example 12: Widget Integration Example ──────────────────────────
  print('\n=== Example 12: Mini Calculator Widget Integration ===');
  _demonstrateWidgetIntegration(engine);
}

void _demonstrateWidgetIntegration(MathEngine engine) {
  // This shows how the calculator widget would use MathEngine

  // Simulate user entering: d/dx(x^3)
  String userExpression = 'd/dx(x^3)';
  final args = engine.splitTopLevelArgs('x^3');
  if (args.length == 1) {
    var derivative = engine.differentiate(args[0], 'x');
    print('User entered: $userExpression');
    print('Result: $derivative'); // 3x²
  }

  // Simulate user entering: ∫(sin(x), 0, 3.14159)
  userExpression = '∫(sin(x), 0, 3.14159)';
  final parts = engine.splitTopLevelArgs('sin(x), 0, 3.14159');
  if (parts.length == 3) {
    var result = engine.integrate(
        parts[0], 'x', double.parse(parts[1]), double.parse(parts[2]));
    print('User entered: $userExpression');
    print('Result: $result'); // ≈ 2.0
  }

  // Simulate user entering: (3+4i)*(1-2i)
  userExpression = '(3+4i)*(1-2i)';
  var result = engine.evaluate(userExpression);
  print('User entered: $userExpression');
  print('Result: ${result.toDisplayString()}'); // 11 - 2i

  // Display in flutter_math_fork would be:
  // Math.tex(result.toDisplayString()) or
  // Math.tex(engine.toLatex(userExpression))
}
