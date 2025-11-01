import 'dart:io';

import 'package:spotoolfy_flutter/services/lyrics/qq_provider.dart';
import 'package:spotoolfy_flutter/utils/lyric_timing_utils.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/qq_lyric_probe.dart "Song Title" ["Artist Name"]',
    );
    exitCode = 64;
    return;
  }

  final title = args[0];
  final artist = args.length > 1 ? args[1] : '';
  final provider = QQProvider();

  stdout.writeln('Searching QQ Music for: $title — $artist');
  final match = await provider.search(title, artist);
  if (match == null) {
    stdout.writeln('No QQ Music match found.');
    return;
  }

  stdout.writeln(
    'Match found: ${match.title} — ${match.artist} (songId: ${match.songId})',
  );

  final payload = await provider.fetchLyricPayload(match.songId);
  if (payload == null || !payload.hasAnyContent) {
    stdout.writeln('Lyric payload was empty.');
    return;
  }

  final normalizedLyric =
      payload.lyric != null ? provider.normalizeLyric(payload.lyric!) : '';

  final timingSummary = LyricTimingUtils.summarize(normalizedLyric);

  stdout.writeln('Primary lyric length: ${normalizedLyric.length} characters.');
  stdout.writeln(
    'Total content lines: ${timingSummary.totalContentLines}, '
    'timestamped lines: ${timingSummary.timestampedLineCount}.',
  );
  stdout.writeln(
    'Contains LRC timestamps: ${timingSummary.hasTimestamps ? 'YES' : 'NO'}',
  );

  if (timingSummary.sampleTimestampedLines.isNotEmpty) {
    stdout.writeln('\nSample timestamped lines:');
    for (final line in timingSummary.sampleTimestampedLines) {
      stdout.writeln('  $line');
    }
  }

  if (timingSummary.samplePlainLines.isNotEmpty) {
    stdout.writeln('\nSample plain lines:');
    for (final line in timingSummary.samplePlainLines) {
      stdout.writeln('  $line');
    }
  }

  if (payload.translatedLyric != null &&
      payload.translatedLyric!.trim().isNotEmpty) {
    stdout.writeln(
      '\nTranslated lyric present (${payload.translatedLyric!.length} chars).',
    );
  }

  if (payload.romanizedLyric != null &&
      payload.romanizedLyric!.trim().isNotEmpty) {
    stdout.writeln(
      'Romanized lyric present (${payload.romanizedLyric!.length} chars).',
    );
  }
}
