/// Cached totals mirrored onto `universities/{universityId}.stats`.
///
/// These are maintained by `UniversityService` on every create/soft-delete so
/// the dashboard summary card can render without querying the three
/// collections. A zero here can mean either "genuinely empty" or "the stats
/// map was never written"; [isPopulated] is the flag that tells them apart.
class UniversityStats {
  const UniversityStats({
    this.folderCount = 0,
    this.fileCount = 0,
    this.videoCount = 0,
    this.isPopulated = false,
  });

  final int folderCount;
  final int fileCount;
  final int videoCount;

  /// False while the university document has no `stats` map at all, which is
  /// the case for universities created before the counters existed.
  final bool isPopulated;

  int get totalItems => folderCount + fileCount + videoCount;
}
