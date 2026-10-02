/// Compares the version strings this app has to compare.
///
/// `1.2.0` < `1.2.1`, and `1.10.0` > `1.9.0` — the second is the pair a
/// comparison written by eye gets wrong, and it is the one that decides whether
/// a reader is offered an update or told they are current.
///
/// A leading `v` (what a git tag carries) is ignored, `+build` metadata and a
/// `-beta` suffix are not part of the order, and anything that is not a number
/// reads as zero instead of throwing: the input on one side is a tag typed by
/// hand in a release, and a typo there must not end the launch.
///
/// It lives in one place because two very different paths ask the same question
/// — the launch gate (`services/version_check_service.dart`) and the updater
/// (`services/update_service.dart`) — and a second copy of this rule is how one
/// of them ends up disagreeing with the other about which build is newer.
int compareVersions(String a, String b) {
  final left = _segments(a);
  final right = _segments(b);
  final length = left.length > right.length ? left.length : right.length;

  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

/// True when [a] is an older build than [b].
bool isVersionLessThan(String a, String b) => compareVersions(a, b) < 0;

/// The numbers of [version], left to right; `v1.10.2+3` → `[1, 10, 2]`.
///
/// Four segments at most, because that is what both Windows' own version
/// resource (`windows/runner/Runner.rc`) and a release tag here use — a fifth
/// would be a mistake rather than a convention.
List<int> _segments(String version) {
  var text = version.trim();
  if (text.startsWith('v') || text.startsWith('V')) {
    text = text.substring(1);
  }
  // Build metadata (`+3`) and a pre-release suffix (`-beta.1`) do not order two
  // builds for the reader: what they are offered is the release.
  for (final cut in const ['+', '-']) {
    final at = text.indexOf(cut);
    if (at >= 0) text = text.substring(0, at);
  }
  if (text.isEmpty) return const [0];

  return text
      .split('.')
      .take(4)
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList(growable: false);
}
