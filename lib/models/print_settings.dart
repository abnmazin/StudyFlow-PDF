enum PrintDestination { printer, pdfFile }

enum PrintOrientation { portrait, landscape }

enum PrintColorMode { color, grayscale }

class PrintSettings {
  final PrintDestination destination;
  final String? outputPath; // Required if destination == pdfFile
  final String pageRange; // 'all' | 'current' | 'odd' | 'even' | '1-5,7'
  final String parity; // 'all' | 'odd' | 'even'
  final bool reverse;
  final int copies;
  final PrintOrientation orientation;
  final PrintColorMode colorMode;

  const PrintSettings({
    this.destination = PrintDestination.printer,
    this.outputPath,
    this.pageRange = 'all',
    this.parity = 'all',
    this.reverse = false,
    this.copies = 1,
    this.orientation = PrintOrientation.portrait,
    this.colorMode = PrintColorMode.color,
  });
}
