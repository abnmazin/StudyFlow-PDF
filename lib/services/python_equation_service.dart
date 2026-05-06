import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class PythonEquationResult {
  final bool bridgeAvailable;
  final bool success;
  final String? result;
  final String? error;

  const PythonEquationResult._({
    required this.bridgeAvailable,
    required this.success,
    this.result,
    this.error,
  });

  const PythonEquationResult.success(String result)
      : this._(bridgeAvailable: true, success: true, result: result);

  const PythonEquationResult.failure(String error)
      : this._(bridgeAvailable: true, success: false, error: error);

  const PythonEquationResult.unavailable(String error)
      : this._(bridgeAvailable: false, success: false, error: error);
}

class PythonEquationService {
  static const String _bridgeCode = r'''
import json
import sys

import sympy as sp


def normalize(expr: str) -> str:
    return (
        expr.replace('×', '*')
        .replace('÷', '/')
        .replace('π', 'pi')
        .replace('^', '**')
        .replace('√', 'sqrt')
    )


def solve_equation(equation_str: str):
    try:
        if '=' not in equation_str:
            return {'ok': False, 'error': 'Syntax Error'}

        left_side, right_side = equation_str.split('=', 1)
        local_symbols = {
            'x': sp.symbols('x'),
            'y': sp.symbols('y'),
            'z': sp.symbols('z'),
            'pi': sp.pi,
            'e': sp.E,
            'sqrt': sp.sqrt,
            'sin': sp.sin,
            'cos': sp.cos,
            'tan': sp.tan,
            'asin': sp.asin,
            'acos': sp.acos,
            'atan': sp.atan,
            'log': sp.log,
            'ln': sp.log,
            'exp': sp.exp,
        }

        left_expr = sp.sympify(normalize(left_side.strip()), locals=local_symbols)
        right_expr = sp.sympify(normalize(right_side.strip()), locals=local_symbols)

        equation = sp.Eq(left_expr, right_expr)
        variables = sorted(list(equation.free_symbols), key=lambda s: s.name)

        if not variables:
            return {'ok': False, 'error': 'No variable found'}

        symbol = next((item for item in variables if item.name == 'x'), variables[0])
        solutions = sp.solve(equation, symbol)

        if not solutions:
            return {'ok': False, 'error': 'No Solution'}

        formatted = ', '.join(str(solution) for solution in solutions)
        return {'ok': True, 'result': f'{symbol} = {formatted}'}
    except Exception as exc:
        return {'ok': False, 'error': str(exc)}


payload = sys.argv[1] if len(sys.argv) > 1 else ''
print(json.dumps(solve_equation(payload), ensure_ascii=False))
''';

  Future<PythonEquationResult> solve(String equation) async {
    if (kIsWeb) {
      return const PythonEquationResult.unavailable(
        'Python bridge is unavailable on web.',
      );
    }

    for (final invocation in <_PythonInvocation>[
      const _PythonInvocation('py', ['-3']),
      const _PythonInvocation('python', []),
      const _PythonInvocation('python3', []),
    ]) {
      try {
        final processResult = await Process.run(
          invocation.executable,
          [...invocation.args, '-c', _bridgeCode, equation],
          runInShell: false,
        );

        if (processResult.exitCode != 0) {
          final stderrText = processResult.stderr.toString().trim();
          if (stderrText.isNotEmpty &&
              (stderrText.contains('No module named sympy') ||
                  stderrText.contains('ModuleNotFoundError') ||
                  stderrText.contains('is not recognized'))) {
            continue;
          }
          final stdoutText = processResult.stdout.toString().trim();
          final fallbackMessage = stderrText.isNotEmpty
              ? stderrText
              : stdoutText.isNotEmpty
                  ? stdoutText
                  : 'Python bridge failed.';
          return PythonEquationResult.failure(fallbackMessage);
        }

        final stdoutText = processResult.stdout.toString().trim();
        if (stdoutText.isEmpty) {
          return const PythonEquationResult.failure('Empty Python response.');
        }

        final decoded = jsonDecode(stdoutText);
        if (decoded is! Map<String, dynamic>) {
          return const PythonEquationResult.failure('Invalid Python response.');
        }

        final ok = decoded['ok'] == true;
        if (ok) {
          final result = decoded['result']?.toString().trim() ?? '';
          if (result.isEmpty) {
            return const PythonEquationResult.failure('Empty solver result.');
          }
          return PythonEquationResult.success(result);
        }

        final error = decoded['error']?.toString().trim() ?? 'Python solver error.';
        return PythonEquationResult.failure(error);
      } catch (e) {
        final message = e.toString();
        if (message.contains('ProcessException') ||
            message.contains('No such file or directory') ||
            message.contains('The system cannot find the file specified')) {
          continue;
        }
        return PythonEquationResult.unavailable(message);
      }
    }

    return const PythonEquationResult.unavailable(
      'Python executable was not found on this device.',
    );
  }
}

class _PythonInvocation {
  final String executable;
  final List<String> args;

  const _PythonInvocation(this.executable, this.args);
}