import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/utils/lyric_timing_utils.dart';

void main() {
  group('LyricTimingUtils', () {
    const syncedLyric = '''
[00:10.12]Line with timing
[00:20.34]Another timed line
Some metadata that should be ignored

[00:30.00]Final line
''';

    const unsyncedLyric = '''
First line without timing
Second plain line
''';

    test('detects timestamps in synced lyrics', () {
      expect(LyricTimingUtils.hasTimestamps(syncedLyric), isTrue);
      expect(LyricTimingUtils.countTimestampedLines(syncedLyric), 3);
      expect(
        LyricTimingUtils.countContentLines(syncedLyric),
        greaterThanOrEqualTo(3),
      );
    });

    test('detects lack of timestamps in unsynced lyrics', () {
      expect(LyricTimingUtils.hasTimestamps(unsyncedLyric), isFalse);
      expect(LyricTimingUtils.countTimestampedLines(unsyncedLyric), 0);
      expect(LyricTimingUtils.countContentLines(unsyncedLyric), 2);
    });

    test('summarize returns sample lines with appropriate filtering', () {
      final summary = LyricTimingUtils.summarize(syncedLyric);
      expect(summary.hasTimestamps, isTrue);
      expect(summary.timestampedLineCount, 3);
      expect(summary.sampleTimestampedLines, isNotEmpty);
      expect(
        summary.samplePlainLines.every(
          (line) => !LyricTimingUtils.hasTimestamps(line),
        ),
        isTrue,
      );
    });
  });
}
