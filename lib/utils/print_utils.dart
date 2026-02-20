class PrintUtils {
  /// Parse a page range string such as "1-5, 7, 9-12" into a sorted,
  /// de-duplicated list of 1-indexed page numbers clamped to [1, totalPages].
  static List<int> parsePageRange(String input, int totalPages) {
    if (input.trim().isEmpty) return [];
    final Set<int> pages = {};
    final parts = input.replaceAll(' ', '').split(',');

    for (final part in parts) {
      if (part.contains('-')) {
        final bounds = part.split('-');
        if (bounds.length == 2) {
          final start = int.tryParse(bounds[0]) ?? 1;
          final end = int.tryParse(bounds[1]) ?? totalPages;
          // Handle reverse range input like "5-1" by swapping?
          // For now, assume user means min-max or max-min inclusion.
          final low = start < end ? start : end;
          final high = start < end ? end : start;

          for (int i = low; i <= high; i++) {
            pages.add(i);
          }
        }
      } else {
        final page = int.tryParse(part);
        if (page != null) pages.add(page);
      }
    }

    return pages.where((p) => p >= 1 && p <= totalPages).toList()..sort();
  }

  /// Applies odd/even filtering and reversal to a list of pages.
  static List<int> applyParityAndReverse(
    List<int> pages,
    String parity,
    bool reverse,
  ) {
    List<int> result;

    if (parity == 'odd') {
      result = pages.where((p) => p.isOdd).toList();
    } else if (parity == 'even') {
      result = pages.where((p) => p.isEven).toList();
    } else {
      result = List.from(pages);
    }

    if (reverse) {
      result = result.reversed.toList();
    }

    return result;
  }
}
