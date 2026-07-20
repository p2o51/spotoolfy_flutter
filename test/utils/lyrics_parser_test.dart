import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/utils/lyrics_parser.dart';
import 'package:spotoolfy_flutter/models/lyric_line.dart';

void main() {
  group('LyricsParser.getCurrentLineIndex', () {
    test('returns -1 for empty lyrics list', () {
      expect(LyricsParser.getCurrentLineIndex([], Duration.zero), -1);
    });

    test('returns -1 if current position is before the first lyric line', () {
      final lyrics = [
        LyricLine(const Duration(seconds: 10), 'First line'),
        LyricLine(const Duration(seconds: 20), 'Second line'),
      ];
      expect(LyricsParser.getCurrentLineIndex(lyrics, const Duration(seconds: 5)), -1);
    });

    test('returns correct index when position is exactly on a lyric line', () {
      final lyrics = [
        LyricLine(const Duration(seconds: 10), 'First line'),
        LyricLine(const Duration(seconds: 20), 'Second line'),
        LyricLine(const Duration(seconds: 30), 'Third line'),
      ];
      expect(LyricsParser.getCurrentLineIndex(lyrics, const Duration(seconds: 20)), 1);
    });

    test('returns correct index when position is between two lyric lines', () {
      final lyrics = [
        LyricLine(const Duration(seconds: 10), 'First line'),
        LyricLine(const Duration(seconds: 20), 'Second line'),
        LyricLine(const Duration(seconds: 30), 'Third line'),
      ];
      expect(LyricsParser.getCurrentLineIndex(lyrics, const Duration(seconds: 25)), 1);
    });

    test('returns last index when position is after the last lyric line', () {
      final lyrics = [
        LyricLine(const Duration(seconds: 10), 'First line'),
        LyricLine(const Duration(seconds: 20), 'Second line'),
      ];
      expect(LyricsParser.getCurrentLineIndex(lyrics, const Duration(seconds: 30)), 1);
    });

    test('handles consecutive lines with identical timestamps', () {
      final lyrics = [
        LyricLine(const Duration(seconds: 10), 'First line'),
        LyricLine(const Duration(seconds: 10), 'Same time line'),
        LyricLine(const Duration(seconds: 20), 'Second line'),
      ];
      // According to the binary search logic, if there are multiple identical timestamps,
      // and we search for exactly that timestamp, it should return the last matching index
      // where the next timestamp is > currentPosition, OR it's the end of the array.
      // In this specific implementation, it returns 1.
      expect(LyricsParser.getCurrentLineIndex(lyrics, const Duration(seconds: 10)), 1);
      expect(LyricsParser.getCurrentLineIndex(lyrics, const Duration(seconds: 15)), 1);
    });
  });
}
