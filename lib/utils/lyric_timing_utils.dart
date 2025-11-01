/// Utility helpers for inspecting whether lyric strings include synchronized
/// timestamps (LRC-style `[mm:ss.xx]` tags) and for gathering quick stats that
/// aid debugging provider responses.
class LyricTimingUtils {
  /// Matches standard LRC time tags such as `[00:12.34]` or `[1:02.345]`.
  static final RegExp _timestampPattern =
      RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{2,3}))?\]');

  /// Returns `true` when the provided [lyric] contains at least one LRC
  /// timestamp marker.
  static bool hasTimestamps(String lyric) {
    return _timestampPattern.hasMatch(lyric);
  }

  /// Counts how many lines in [lyric] contain at least one timestamp marker.
  static int countTimestampedLines(String lyric) {
    return _splitLyricLines(lyric)
        .where((line) => _timestampPattern.hasMatch(line))
        .length;
  }

  /// Counts text-bearing lines irrespective of timestamps.
  static int countContentLines(String lyric) {
    return _splitLyricLines(lyric).length;
  }

  /// Returns a short preview of the first few lines in [lyric]. When
  /// [timestampedOnly] is `true`, only lines containing timestamps are kept.
  static List<String> previewLines(
    String lyric, {
    int maxLines = 5,
    bool timestampedOnly = false,
  }) {
    final lines = _splitLyricLines(lyric)
        .where((line) {
          if (!timestampedOnly) return true;
          return _timestampPattern.hasMatch(line);
        })
        .take(maxLines)
        .toList();
    return lines;
  }

  /// Convenience helper that returns statistics for debugging purposes.
  static LyricTimingSummary summarize(String lyric) {
    final containsTimestamps = hasTimestamps(lyric);
    final totalLines = countContentLines(lyric);
    final timestampLines = countTimestampedLines(lyric);
    final sampleTimestamped =
        previewLines(lyric, timestampedOnly: true, maxLines: 3);
    final samplePlain = previewLines(
      lyric,
      timestampedOnly: false,
      maxLines: 3,
    ).where((line) => !_timestampPattern.hasMatch(line)).toList();

    return LyricTimingSummary(
      hasTimestamps: containsTimestamps,
      totalContentLines: totalLines,
      timestampedLineCount: timestampLines,
      sampleTimestampedLines: sampleTimestamped,
      samplePlainLines: samplePlain,
    );
  }

  static Iterable<String> _splitLyricLines(String lyric) {
    return lyric
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
  }
}

/// Structured output describing the presence of timestamps inside a lyric.
class LyricTimingSummary {
  final bool hasTimestamps;
  final int totalContentLines;
  final int timestampedLineCount;
  final List<String> sampleTimestampedLines;
  final List<String> samplePlainLines;

  const LyricTimingSummary({
    required this.hasTimestamps,
    required this.totalContentLines,
    required this.timestampedLineCount,
    required this.sampleTimestampedLines,
    required this.samplePlainLines,
  });
}
