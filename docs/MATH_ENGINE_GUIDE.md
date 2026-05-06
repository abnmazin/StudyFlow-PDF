# MathEngine Documentation

## Overview

`MathEngine` is a unified mathematical computation engine for StudyFlow that combines:
- **texpr**: LaTeX-aware expression parser, evaluator, and symbolic calculator
- **equations**: Polynomial equation solver for cubic, quartic, and higher-degree polynomials
- **Native Dart**: Zero external dependencies (no Python required)

## Architecture

### Core Classes

#### `MathEngine` (Singleton)
Main entry point for all mathematical operations.

```dart
final engine = MathEngine();
```

#### `MathResult`
Wrapper for mathematical results supporting real and complex outputs.

```dart
class MathResult {
  final bool isSuccess;
  final String? error;
  final double? realValue;
  final ({double real, double imag})? complexValue;
  final String? symbolicResult;
  
  String toDisplayString() { ... }
}
```

## Usage Examples

### 1. Basic Evaluation

```dart
final engine = MathEngine();

// Simple arithmetic
var result = engine.evaluate('2 + 3 * 4');
print(result.toDisplayString()); // 14

// With variables
result = engine.evaluate(r'\sin(x)', {'x': 1.5708});
print(result.toDisplayString()); // ~1.0

// Complex numbers (supported!)
result = engine.evaluate('(3 + 4i) * (1 - 2i)');
print(result.toDisplayString()); // 11 - 2i
```

### 2. Symbolic Differentiation

Supports derivatives of polynomials, trigonometric, exponential, and logarithmic functions.

```dart
// Basic polynomial
var derivative = engine.differentiate(r'x^3 + 2x^2 + x', 'x');
// Result: "3x^2 + 4x + 1"

// Trigonometric
derivative = engine.differentiate(r'\sin(x)', 'x');
// Result: "\cos(x)"

// Complex function (product rule)
derivative = engine.differentiate(r'x * \exp(x)', 'x');
// Result: "x*exp(x) + exp(x)"
```

### 3. Integration

Both symbolic (for basic patterns) and numerical (Simpson's rule).

```dart
// Indefinite integral
var integral = engine.integrate(r'x^2', 'x');
// Result: "x^3/3 + C"

// Definite integral (numerical)
var result = engine.evaluate(r'\int_0^1 x^2 dx');
// Result: 0.333...

// Or explicitly:
var numIntegral = double.parse(engine.integrate('x^2', 'x', 0.0, 1.0));
// Result: 0.333...
```

### 4. Equation Solving

Supports linear, quadratic, and cubic equations. Falls back to numerical methods for higher degrees.

```dart
// Linear equation
var solution = engine.solveEquation('2x + 3 = 0');
// Result: "x = -1.5"

// Quadratic
solution = engine.solveEquation('x^2 - 5x + 6 = 0');
// Result: "x ∈ {2, 3}"

// Complex coefficients
solution = engine.solveEquation('(1+i)x + 2 = 0');
// Result: "x = ..."
```

### 5. Numerical Operations

```dart
// Derivative at point
var deriv = engine.numericalDerivative(r'\sin(x)', 'x', 1.5708);
// Result: ~0.0 (cos(π/2))

// Integral over range
var integral = engine.numericalIntegral(r'x^3', 'x', 0.0, 2.0);
// Result: 4.0
```

### 6. LaTeX Conversion

```dart
// Convert expression to LaTeX
var latex = engine.toLatex('2*pi*r^2');
// Result: "2\pi r^2"
```

## Supported Functions

### Arithmetic & Algebra
- Basic operators: `+`, `-`, `*`, `/`, `^`, `%`
- Parentheses: `(`, `)`
- Implicit multiplication: `2x`, `2(3+4)`, `sin x`

### Trigonometric (Radians by default)
- `sin(x)`, `cos(x)`, `tan(x)`
- `asin(x)`, `acos(x)`, `atan(x)`
- `sinh(x)`, `cosh(x)`, `tanh(x)`

### Exponential & Logarithmic
- `exp(x)` or `e^x`
- `log(x)` (natural logarithm)
- `log10(x)` (base-10 logarithm)
- `log(x, base)` (arbitrary base)

### Roots
- `sqrt(x)` or `√(x)`
- `cbrt(x)` (cube root)
- `root(x, n)` (nth root)

### Other
- `abs(x)` (absolute value)
- `floor(x)`, `ceil(x)`, `round(x)`
- `max(a, b)`, `min(a, b)`
- `factorial(n)` or `n!`

### Special Constants
- `pi` or `π`
- `e` (Euler's number)
- `i` (imaginary unit)

## Degree/Radian Mode

The mini calculator widget manages degree/radian conversion. For the engine:
- Always use **radians** in direct engine calls
- The widget handles the conversion before calling the engine

```dart
// In widget code (pseudo):
if (_isDegreeMode) {
  angle = angle * pi / 180;  // Convert to radians before engine call
}
var result = engine.evaluate(r'\sin(x)', {'x': angle});
```

## Complex Number Support

The engine fully supports complex arithmetic:

```dart
// Complex arithmetic
var result = engine.evaluate('(3+4i) + (1-2i)');
// Result: 4+2i

// Complex functions
result = engine.evaluate('exp(i*pi)');
// Result: -1 (Euler's formula)

// Access complex parts
if (result.complexValue != null) {
  print(result.complexValue!.real);    // Real part
  print(result.complexValue!.imag);    // Imaginary part
}
```

## Error Handling

All methods return descriptive error messages:

```dart
var result = engine.evaluate('1/0');
if (!result.isSuccess) {
  print(result.error);  // "Division by zero"
}

var solution = engine.solveEquation('x^5 + 2x - 1 = 0');
// For equations texpr can't solve, it returns: "Higher-degree polynomial solving not yet supported..."
```

## Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| Simple eval | <1ms | e.g., `2+3*4` |
| Polynomial eval | 1-5ms | Depends on degree |
| Symbolic differentiation | 2-10ms | Constant rule applications |
| Numerical integration | 5-20ms | Simpson's rule, 200 steps |
| Equation solving (quadratic) | <5ms | Direct formula |
| Equation solving (Newton-Raphson) | 10-50ms | Iterative, up to 60 iterations |

## Integration with Flutter UI

### In MiniCalculatorWidget

```dart
final _mathEngine = MathEngine();

void _calculateResult() async {
  // Evaluate
  final result = _mathEngine.evaluate(_expression, {'y': _yValue});
  if (result.isSuccess) {
    setState(() => _expression = result.toDisplayString());
  } else {
    setState(() => _errorType = result.error ?? 'Error');
  }
}
```

### With flutter_math_fork

```dart
// Display symbolic result
Math.tex(
  engine.differentiate(r'x^3', 'x'),
  textStyle: TextStyle(fontSize: 24),
)
```

## Future Extensions

1. **Degree/Radian Toggle**: Pass mode to engine for automatic conversion
2. **Matrix Operations**: Determinant, inverse, rank (planned)
3. **Multi-variable Optimization**: Lagrange multipliers, gradient descent
4. **ODE Solver**: Runge-Kutta integration
5. **Statistics**: Mean, variance, regression (planned)

## Migration Notes (from old system)

### Removed
- `PythonEquationService` (no longer needed)
- `math_expressions` dependency
- Manual polynomial differentiation/integration
- Custom Newton-Raphson implementation

### Benefits
- **Independence**: No external runtime dependencies
- **Speed**: Faster execution (Dart VM)
- **Coverage**: Complex number support
- **Reliability**: Tested against 1,800+ test cases (texpr)
- **Compatibility**: First-class LaTeX support

## See Also

- [texpr Documentation](https://pub.dev/packages/texpr)
- [equations Package](https://pub.dev/packages/equations)
- Mini Calculator Widget: `lib/widgets/viewer_components/mini_calculator_widget.dart`
