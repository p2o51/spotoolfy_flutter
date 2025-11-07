import 'dart:convert';

/// Utilities for detecting and fixing QQ lyric mojibake caused by
/// latin1-decoded UTF-8 payloads.
class QQEncoding {
  static const Set<int> _mojibakeIndicators = {
    0x00B0,
    0x00B1,
    0x00B2,
    0x00B3,
    0x00B4,
    0x00B5,
    0x00B6,
    0x00B7,
    0x00B8,
    0x00B9,
    0x00BA,
    0x00BB,
    0x00BC,
    0x00BD,
    0x00BE,
    0x00BF,
    0x00C2,
    0x00C3,
    0x00D0,
    0x00D1,
    0x00E2,
    0x00E3,
    0x00E4,
    0x00E5,
    0x00E6,
    0x00E7,
    0x00E8,
    0x00E9,
    0x00EA,
    0x00EB,
    0x00EC,
    0x00ED,
    0x00EE,
    0x00EF,
    0x00F0,
    0x00F1,
    0x00F2,
    0x00F3,
    0x00F4,
    0x00F5,
    0x00F6,
    0x00F7,
    0x00F8,
    0x00F9,
    0x00FA,
    0x00FB,
    0x00FC,
    0x00FD,
    0x00FE,
    0x00FF,
  };

  static String normalize(String value) {
    final originalScore = _mojibakeScore(value);
    if (originalScore == 0) {
      return value;
    }

    final decoded = _tryDecodeLatin1AsUtf8(value);
    if (decoded == null) {
      return value;
    }

    final decodedScore = _mojibakeScore(decoded);
    return decodedScore < originalScore ? decoded : value;
  }

  static String? normalizeNullable(String? value) {
    if (value == null || value.trim().isEmpty) {
      return value;
    }
    return normalize(value);
  }

  static String? _tryDecodeLatin1AsUtf8(String value) {
    final buffer = StringBuffer();
    final chunk = StringBuffer();
    var changed = false;

    void flushChunk() {
      if (chunk.isEmpty) return;
      final source = chunk.toString();
      try {
        final bytes = latin1.encode(source);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        buffer.write(decoded);
        if (decoded != source) {
          changed = true;
        }
      } catch (_) {
        buffer.write(source);
      }
      chunk.clear();
    }

    for (final codePoint in value.runes) {
      if (codePoint <= 0xFF) {
        chunk.writeCharCode(codePoint);
      } else {
        flushChunk();
        buffer.writeCharCode(codePoint);
      }
    }
    flushChunk();

    if (!changed) {
      return buffer.isEmpty ? value : buffer.toString();
    }
    return buffer.toString();
  }

  static int _mojibakeScore(String value) {
    var score = 0;
    for (final codePoint in value.runes) {
      if (_mojibakeIndicators.contains(codePoint)) {
        score++;
      } else if (codePoint >= 0x80 && codePoint <= 0x9F) {
        score += 2;
      } else if (codePoint == 0xFFFD) {
        score += 3;
      }
    }
    return score;
  }
}
