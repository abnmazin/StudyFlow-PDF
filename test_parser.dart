void main() {
  String currentText = r'\frac{\left(100*10^{-6}\right)^2} {3.2*10^{-14}}=';
  String rawEquation = currentText.substring(0, currentText.length - 1).trim();

  String cleanEq = rawEquation;
  
  // 1. Clean brackets first
  cleanEq = cleanEq.replaceAll(RegExp(r'\\left\('), '(');
  cleanEq = cleanEq.replaceAll(RegExp(r'\\right\)'), ')');
  
  // 2. Convert ^{...} to ^(...)
  cleanEq = cleanEq.replaceAllMapped(RegExp(r'\^\{([^}]+)\}'), (m) => '^(${m[1]})');
  
  // 3. Fraction
  cleanEq = cleanEq.replaceAllMapped(
    RegExp(r'\\frac{([^}]+)}{([^}]+)}'),
    (m) => '(${m[1]})/(${m[2]})',
  );
  
  cleanEq = cleanEq.replaceAll(RegExp(r'\\times'), '*');
  cleanEq = cleanEq.replaceAll(RegExp(r'\\div'), '/');
  cleanEq = cleanEq.replaceAllMapped(
    RegExp(r'\\sqrt{([^}]+)}'),
    (m) => 'sqrt(${m[1]})',
  );
  cleanEq = cleanEq.replaceAll(' ', ''); // remove spaces
  
  print(cleanEq);
}
