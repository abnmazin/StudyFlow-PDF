/// One lecture in a day, as the dashboard's schedule column shows it.
///
/// Deliberately not an Isar collection. It is the *rendered* shape of a lecture
/// rather than the stored one: the table itself lives in Firestore as
/// `TimetableEntry` (see `TimetableService`), authored once by an admin and read
/// by everyone, so an Isar copy here would be a shared schedule that exists only
/// on the disk of whoever typed it.
///
/// A plain value object holding the four fields the column renders. It is built
/// on demand by `TimetableEntry.lectureOn` and read through `AppProvider.lectures`.
///
/// That split is what keeps the widget layer unchanged when the source moves: a
/// different feed has to supply these four values and nothing else, and the row
/// needs no edit.
class LectureSlot {
  const LectureSlot({
    required this.title,
    required this.time,
    required this.room,
    required this.startsAt,
  });

  /// Course or session name. Long names are the case the schedule row is built
  /// to survive: the row keeps its time and room on their own baseline however
  /// far this runs.
  final String title;

  /// Start time as shown, e.g. `10:30`.
  final String time;

  /// Room or hall, e.g. `قاعة 204`.
  final String room;

  /// When the lecture starts. The column buckets by calendar day relative to
  /// now, so this is what decides "Today" versus "Tomorrow".
  final DateTime startsAt;
}
