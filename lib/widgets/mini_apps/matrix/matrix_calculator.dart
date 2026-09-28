import 'dart:ui';

import 'package:flutter/material.dart';

class MatrixCalculatorWidget extends StatefulWidget {
  const MatrixCalculatorWidget({super.key});

  @override
  State<MatrixCalculatorWidget> createState() => _MatrixCalculatorWidgetState();
}

class _MatrixCalculatorWidgetState extends State<MatrixCalculatorWidget> {
  int _rowsA = 3;
  int _colsA = 3;
  int _rowsB = 3;
  int _colsB = 3;

  // Controllers for Matrix A and B
  late List<List<TextEditingController>> _matrixA = [];
  late List<List<TextEditingController>> _matrixB = [];
  late List<FocusNode> _focusNodesA = [];
  late List<FocusNode> _focusNodesB = [];

  String _resultText = 'Enter values and choose an operation';
  List<List<double>>? _resultMatrix;
  int? _resultRows;
  int? _resultCols;

  @override
  void initState() {
    super.initState();
    _initMatrices();
  }

  void _initMatrices() {
    for (var row in _matrixA) {
      for (var c in row) {
        c.dispose();
      }
    }
    for (var row in _matrixB) {
      for (var c in row) {
        c.dispose();
      }
    }
    for (var focus in _focusNodesA) {
      focus.dispose();
    }
    for (var focus in _focusNodesB) {
      focus.dispose();
    }

    _matrixA = List.generate(
      _rowsA,
      (_) => List.generate(_colsA, (_) => TextEditingController()),
    );
    _matrixB = List.generate(
      _rowsB,
      (_) => List.generate(_colsB, (_) => TextEditingController()),
    );

    _focusNodesA = List.generate(
      _rowsA,
      (_) => List.generate(_colsA, (_) => FocusNode()),
    ).expand((x) => x).toList();
    _focusNodesB = List.generate(
      _rowsB,
      (_) => List.generate(_colsB, (_) => FocusNode()),
    ).expand((x) => x).toList();

    _resultMatrix = null;
    _resultText = 'Enter values and choose an operation';
  }

  void _changeDimensions(int rows, int cols, {bool isMatrixB = false}) {
    setState(() {
      if (isMatrixB) {
        _rowsB = rows.clamp(1, 10);
        _colsB = cols.clamp(1, 10);
      } else {
        _rowsA = rows.clamp(1, 10);
        _colsA = cols.clamp(1, 10);
      }
      _initMatrices();
    });
  }

  List<List<double>> _parseMatrix(
    List<List<TextEditingController>> controllers,
    int rows,
    int cols,
  ) {
    return List.generate(rows, (i) {
      return List.generate(cols, (j) {
        if (i < controllers.length && j < controllers[i].length) {
          return double.tryParse(controllers[i][j].text) ?? 0.0;
        }
        return 0.0;
      });
    });
  }

  void _add() {
    if (_rowsA != _rowsB || _colsA != _colsB) {
      setState(() {
        _resultText = '❌ Error: dimensions must match for addition!';
        _resultMatrix = null;
      });
      return;
    }
    var a = _parseMatrix(_matrixA, _rowsA, _colsA);
    var b = _parseMatrix(_matrixB, _rowsB, _colsB);
    var res = List.generate(
      _rowsA,
      (i) => List.generate(_colsA, (j) => a[i][j] + b[i][j]),
    );
    _showMatrixResult(res, 'A + B', _rowsA, _colsA);
  }

  void _subtract() {
    if (_rowsA != _rowsB || _colsA != _colsB) {
      setState(() {
        _resultText = '❌ Error: dimensions must match for subtraction!';
        _resultMatrix = null;
      });
      return;
    }
    var a = _parseMatrix(_matrixA, _rowsA, _colsA);
    var b = _parseMatrix(_matrixB, _rowsB, _colsB);
    var res = List.generate(
      _rowsA,
      (i) => List.generate(_colsA, (j) => a[i][j] - b[i][j]),
    );
    _showMatrixResult(res, 'A - B', _rowsA, _colsA);
  }

  void _multiply() {
    if (_colsA != _rowsB) {
      setState(() {
        _resultText = '❌ Error: columns of A must match rows of B!';
        _resultMatrix = null;
      });
      return;
    }
    var a = _parseMatrix(_matrixA, _rowsA, _colsA);
    var b = _parseMatrix(_matrixB, _rowsB, _colsB);
    var res = List.generate(
      _rowsA,
      (i) => List.generate(_colsB, (j) {
        double sum = 0;
        for (int k = 0; k < _colsA; k++) {
          sum += a[i][k] * b[k][j];
        }
        return sum;
      }),
    );
    _showMatrixResult(res, 'A × B', _rowsA, _colsB);
  }

  double _calcDeterminant(List<List<double>> m) {
    int n = m.length;
    if (n == 1) {
      return m[0][0];
    }
    if (n == 2) {
      return (m[0][0] * m[1][1]) - (m[0][1] * m[1][0]);
    }
    if (n == 3) {
      return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
          m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
          m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    }
    double det = 0;
    for (int i = 0; i < n; i++) {
      det += m[0][i] * _calcCofactor(m, 0, i);
    }
    return det;
  }

  double _calcCofactor(List<List<double>> m, int row, int col) {
    List<List<double>> submatrix = [];
    for (int i = 0; i < m.length; i++) {
      if (i != row) {
        List<double> newRow = [];
        for (int j = 0; j < m[i].length; j++) {
          if (j != col) {
            newRow.add(m[i][j]);
          }
        }
        submatrix.add(newRow);
      }
    }
    double cofactor = _calcDeterminant(submatrix);
    return ((row + col) % 2 == 0 ? 1 : -1) * cofactor;
  }

  void _determinant() {
    if (_rowsA != _colsA) {
      setState(() {
        _resultText =
            '❌ Error: matrix A must be square to find the determinant!';
        _resultMatrix = null;
      });
      return;
    }
    var a = _parseMatrix(_matrixA, _rowsA, _colsA);
    double det = _calcDeterminant(a);
    setState(() {
      _resultMatrix = null;
      _resultText =
          '|A| = ${det.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}';
    });
  }

  void _transpose() {
    if (_rowsA == 0 || _colsA == 0) {
      setState(() {
        _resultText = '❌ Error: enter matrix values first!';
        _resultMatrix = null;
      });
      return;
    }
    var a = _parseMatrix(_matrixA, _rowsA, _colsA);
    var res = List.generate(
      _colsA,
      (i) => List.generate(_rowsA, (j) => a[j][i]),
    );
    _showMatrixResult(res, 'A^T (Transpose)', _colsA, _rowsA);
  }

  void _inverse() {
    if (_rowsA != _colsA) {
      setState(() {
        _resultText = '❌ Error: matrix A must be square for the inverse!';
        _resultMatrix = null;
      });
      return;
    }

    var a = _parseMatrix(_matrixA, _rowsA, _colsA);
    double det = _calcDeterminant(a);

    if (det.abs() < 1e-10) {
      setState(() {
        _resultMatrix = null;
        _resultText =
            '❌ Error: matrix is singular (|A| = 0) - no inverse exists!';
      });
      return;
    }

    int n = _rowsA;
    List<List<double>> adjugate = List.generate(n, (_) => List.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        adjugate[j][i] = _calcCofactor(a, i, j);
      }
    }

    var res = List.generate(
      n,
      (i) => List.generate(n, (j) => adjugate[i][j] / det),
    );
    _showMatrixResult(res, 'A^{-1} (Inverse)', n, n);
  }

  void _showMatrixResult(
    List<List<double>> matrix,
    String title,
    int rows,
    int cols,
  ) {
    setState(() {
      _resultMatrix = matrix;
      _resultRows = rows;
      _resultCols = cols;
      _resultText = title;
    });
  }

  void _clear() {
    for (var row in _matrixA) {
      for (var c in row) {
        c.clear();
      }
    }
    for (var row in _matrixB) {
      for (var c in row) {
        c.clear();
      }
    }
    setState(() {
      _resultMatrix = null;
      _resultText = 'Cleared';
    });
  }

  Widget _buildMatrixInput(
    String label,
    List<List<TextEditingController>> matrix,
    int rows,
    int cols,
    bool isDark,
    bool isMatrixB,
  ) {
    final rowsCtrl = TextEditingController(text: rows.toString());
    final colsCtrl = TextEditingController(text: cols.toString());

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.14)
                  : Colors.white.withOpacity(0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 42,
                        height: 32,
                        child: TextField(
                          controller: rowsCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            hintText: 'Rows',
                            hintStyle: const TextStyle(fontSize: 9),
                          ),
                          onChanged: (_) {
                            int r = int.tryParse(rowsCtrl.text) ?? rows;
                            r = r.clamp(1, 10);
                            rowsCtrl.text = r.toString();
                            rowsCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: rowsCtrl.text.length),
                            );
                            _changeDimensions(
                              r,
                              colsCtrl.text.isNotEmpty
                                  ? int.parse(colsCtrl.text)
                                  : cols,
                              isMatrixB: isMatrixB,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '×',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 42,
                        height: 32,
                        child: TextField(
                          controller: colsCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            hintText: 'Cols',
                            hintStyle: const TextStyle(fontSize: 9),
                          ),
                          onChanged: (_) {
                            int c = int.tryParse(colsCtrl.text) ?? cols;
                            c = c.clamp(1, 10);
                            colsCtrl.text = c.toString();
                            colsCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: colsCtrl.text.length),
                            );
                            _changeDimensions(
                              rowsCtrl.text.isNotEmpty
                                  ? int.parse(rowsCtrl.text)
                                  : rows,
                              c,
                              isMatrixB: isMatrixB,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Matrix Grid with CSS-style brackets (NO STACK)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: isDark ? Colors.white30 : Colors.black26,
                      width: 2.5,
                    ),
                    right: BorderSide(
                      color: isDark ? Colors.white30 : Colors.black26,
                      width: 2.5,
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: List.generate(rows, (i) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(cols, (j) {
                          int focusIndex = i * cols + j;
                          FocusNode focusNode = isMatrixB
                              ? _focusNodesB[focusIndex]
                              : _focusNodesA[focusIndex];
                          return Container(
                            width: 50,
                            height: 38,
                            margin: const EdgeInsets.all(3),
                            child: TextField(
                              controller: matrix[i][j],
                              focusNode: focusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.next,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.black.withOpacity(0.05),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Colors.blueAccent,
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 0,
                                ),
                                isDense: true,
                              ),
                              onSubmitted: (_) {
                                if (j < cols - 1) {
                                  if (isMatrixB) {
                                    _focusNodesB[i * cols + j + 1]
                                        .requestFocus();
                                  } else {
                                    _focusNodesA[i * cols + j + 1]
                                        .requestFocus();
                                  }
                                } else if (i < rows - 1) {
                                  if (isMatrixB) {
                                    _focusNodesB[(i + 1) * cols].requestFocus();
                                  } else {
                                    _focusNodesA[(i + 1) * cols].requestFocus();
                                  }
                                }
                              },
                            ),
                          );
                        }),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultGrid(bool isDark) {
    if (_resultMatrix == null || _resultRows == null || _resultCols == null) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.white.withOpacity(0.60),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.35),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: List.generate(_resultRows!, (i) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_resultCols!, (j) {
                    double val = _resultMatrix![i][j];
                    String strVal = val
                        .toStringAsFixed(3)
                        .replaceAll(RegExp(r'0+$'), '')
                        .replaceAll(RegExp(r'\.$'), '');
                    return Container(
                      width: 45,
                      height: 45,
                      margin: const EdgeInsets.all(3),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(isDark ? 0.06 : 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.10)
                              : Colors.blueGrey.withOpacity(0.16),
                        ),
                      ),
                      child: Text(
                        strVal,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.blue[200] : Colors.blue[800],
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperationButton(
    String label,
    VoidCallback onPressed, {
    required bool primary,
    required bool isDark,
  }) {
    if (primary) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          backgroundColor: const Color(0xFF22C55E),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          shadowColor: Colors.cyanAccent.withOpacity(0.35),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
        side: BorderSide(
          color: isDark
              ? Colors.white.withOpacity(0.16)
              : Colors.blueGrey.withOpacity(0.22),
        ),
        backgroundColor: Colors.white.withOpacity(isDark ? 0.04 : 0.30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1D4ED8), const Color(0xFF7C3AED)]
                    : [const Color(0xFF3B82F6), const Color(0xFF8B5CF6)],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.grid_4x4, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Matrix Calculator',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${_rowsA}×${_colsA}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildMatrixInput(
                            'Matrix A',
                            _matrixA,
                            _rowsA,
                            _colsA,
                            isDark,
                            false,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMatrixInput(
                            'Matrix B',
                            _matrixB,
                            _rowsB,
                            _colsB,
                            isDark,
                            true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.12)
                            : Colors.white.withOpacity(0.35),
                      ),
                    ),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Binary Operations',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildOperationButton(
                              'A + B',
                              _add,
                              primary: false,
                              isDark: isDark,
                            ),
                            _buildOperationButton(
                              'A - B',
                              _subtract,
                              primary: false,
                              isDark: isDark,
                            ),
                            _buildOperationButton(
                              'A × B',
                              _multiply,
                              primary: true,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.12)
                            : Colors.white.withOpacity(0.35),
                      ),
                    ),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Matrix Tools',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildOperationButton(
                              '|A|',
                              _determinant,
                              primary: false,
                              isDark: isDark,
                            ),
                            _buildOperationButton(
                              'A⁻¹',
                              _inverse,
                              primary: false,
                              isDark: isDark,
                            ),
                            _buildOperationButton(
                              'A^T',
                              _transpose,
                              primary: true,
                              isDark: isDark,
                            ),
                            IconButton(
                              onPressed: _clear,
                              icon: const Icon(Icons.delete_outline),
                              style: IconButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                backgroundColor: Colors.redAccent.withOpacity(
                                  0.08,
                                ),
                              ),
                              tooltip: 'Clear all',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF0F4F8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.blue.withOpacity(0.3)
                            : Colors.blue.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _resultText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.blue[300] : Colors.blue[800],
                          ),
                        ),
                        _buildResultGrid(isDark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (var row in _matrixA) {
      for (var c in row) {
        c.dispose();
      }
    }
    for (var row in _matrixB) {
      for (var c in row) {
        c.dispose();
      }
    }
    for (var focus in _focusNodesA) {
      focus.dispose();
    }
    for (var focus in _focusNodesB) {
      focus.dispose();
    }
    super.dispose();
  }
}
