/// A short, human label for a past timestamp — "اليوم 2:30 م", "أمس 9:05 ص",
/// "منذ 5 أيام", then a plain date once a week has passed.
///
/// Written here rather than pulled from `intl` because the app does not depend
/// on it, and one label does not justify a dependency whose locale data would
/// also have to be loaded at startup.
///
/// [now] is injectable so the boundaries can be tested without the test clock
/// and the machine clock disagreeing about what "today" is.
String formatRelativeDate(DateTime postedAt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  // Compared by calendar day, not by elapsed hours: a note from 23:00 yesterday
  // is "أمس" at 01:00 today, even though barely two hours have passed.
  final today = DateTime(reference.year, reference.month, reference.day);
  final posted = DateTime(postedAt.year, postedAt.month, postedAt.day);
  final days = today.difference(posted).inDays;

  if (days <= 0) return 'اليوم ${formatClock(postedAt)}';
  if (days == 1) return 'أمس ${formatClock(postedAt)}';
  if (days < 7) return 'منذ $days أيام';
  return '${postedAt.day}/${postedAt.month}/${postedAt.year}';
}

/// The wall clock as it is spoken: `9:05 ص`, `2:30 م`.
///
/// 12-hour rather than the 24-hour form this page was first written with. The
/// one who reads an announcement is told "المحاضرة 2:30 م" everywhere else, and
/// a `14:30` beside a spoken `2:30 م` is one more conversion between them and
/// the note.
///
/// No leading zero on the hour (`9`, not `09`): that zero exists to keep a
/// column of 24-hour stamps flush with each other, and there is no column here.
/// The minute keeps its pair so `2:05` cannot read as `2:5`. Midnight and noon
/// are both `12`, which is the one place a plain `hour % 12` prints `0:00`.
String formatClock(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${at.hour < 12 ? 'ص' : 'م'}';
}
