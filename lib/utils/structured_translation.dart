import 'dart:math';

/// Utilities for working with structured lyric translations that preserve line order.
///
/// Each line uses the pattern `__L0001__ >>> Original text` when sent to the LLM
/// and expects the response to mirror the pattern with `<<<` before the translated
/// text. These helpers make it easy to build the prompt input and to parse the
/// model output back into structured data.

const String kStructuredLinePrefix = '__L';
const String kStructuredLineSuffix = '__';
const String kStructuredInputDelimiter = ' >>> ';
const String kStructuredOutputDelimiter = ' <<< ';
const String kStructuredBlankPlaceholder = '[BLANK]';

String _padLineNumber(int index) => (index + 1).toString().padLeft(4, '0');

/// Builds the structured lyrics string sent to the LLM.
String buildStructuredLyrics(List<String> originalLines) {
  final buffer = StringBuffer();
  for (final entry in originalLines.asMap().entries) {
    final id =
        '$kStructuredLinePrefix${_padLineNumber(entry.key)}$kStructuredLineSuffix';
    final text =
        entry.value.trim().isEmpty ? kStructuredBlankPlaceholder : entry.value;
    buffer.writeln('$id$kStructuredInputDelimiter$text');
  }
  return buffer.toString().trimRight();
}

/// The parsed translation result.
class StructuredTranslationParserResult {
  final Map<int, String> translations;
  final List<int> missingLineIndices;
  final String cleanedText;

  const StructuredTranslationParserResult({
    required this.translations,
    required this.missingLineIndices,
    required this.cleanedText,
  });
}

/// Parses the structured translation output from the LLM.
StructuredTranslationParserResult parseStructuredTranslation(
  String rawText, {
  List<String>? originalLines,
}) {
  final sanitized = rawText.replaceAll('\r\n', '\n');
  final delimiterPattern =
      '(?:${RegExp.escape(kStructuredOutputDelimiter)}|${RegExp.escape(kStructuredInputDelimiter)})';
  final markerRegex = RegExp(
    '${RegExp.escape(kStructuredLinePrefix)}'
    r'(\d{4})'
    '${RegExp.escape(kStructuredLineSuffix)}'
    r'\s*'
    '$delimiterPattern',
    multiLine: true,
  );
  final matches = markerRegex.allMatches(sanitized).toList();

  final translations = <int, String>{};

  // If we didn't find the expected markers, fall back to naive line splitting.
  if (matches.isEmpty) {
    final fallbackLines =
        sanitized.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    if (originalLines != null && fallbackLines.length == originalLines.length) {
      for (final entry in fallbackLines.asMap().entries) {
        translations[entry.key] = entry.value;
      }
    }

    final cleaned = _cleanMarkersFromText(sanitized).trim();
    return StructuredTranslationParserResult(
      translations: translations,
      missingLineIndices: _findMissingIndices(originalLines, translations),
      cleanedText: cleaned,
    );
  }

  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final idx = int.tryParse(match.group(1) ?? '');
    if (idx == null) continue;
    final start = match.end;
    final end = i + 1 < matches.length ? matches[i + 1].start : sanitized.length;
    var segment = sanitized.substring(start, end);

    segment = _stripWrappingDelimiters(segment);

    if (segment == kStructuredBlankPlaceholder) {
      segment = '';
    }

    translations[idx - 1] = segment;
  }

  final cleanedText = _buildCleanedText(
    originalLines: originalLines,
    translations: translations,
  );

  return StructuredTranslationParserResult(
    translations: translations,
    missingLineIndices: _findMissingIndices(originalLines, translations),
    cleanedText: cleanedText,
  );
}

String _stripWrappingDelimiters(String value) {
  var result = value.trim();
  if (result.startsWith('```') && result.endsWith('```')) {
    result = result.substring(3, max(3, result.length - 3)).trim();
  }

  if (result.startsWith('###') && result.endsWith('###')) {
    result = result.substring(3, max(3, result.length - 3)).trim();
  }

  return result;
}

String _buildCleanedText({
  required List<String>? originalLines,
  required Map<int, String> translations,
}) {
  if (originalLines == null || originalLines.isEmpty) {
    final sorted = translations.keys.toList()..sort();
    if (sorted.isEmpty) {
      return _cleanMarkersFromText(translations.values.join('\n')).trim();
    }
    return sorted.map((index) => translations[index]!.trim()).join('\n').trim();
  }

  final buffer = StringBuffer();
  for (var i = 0; i < originalLines.length; i++) {
    final translated = translations[i];
    if (translated == null || translated.trim().isEmpty) {
      buffer.writeln(originalLines[i]);
    } else {
      buffer.writeln(translated.trim());
    }
  }
  return buffer.toString().trimRight();
}

List<int> _findMissingIndices(
  List<String>? originalLines,
  Map<int, String> translations,
) {
  if (originalLines == null) return const [];

  final missing = <int>[];
  for (var i = 0; i < originalLines.length; i++) {
    final candidate = translations[i];
    if (candidate == null || candidate.trim().isEmpty) {
      missing.add(i);
    }
  }
  return missing;
}

String _cleanMarkersFromText(String value) {
  return value
      .replaceAll(
        RegExp(
          '${RegExp.escape(kStructuredLinePrefix)}\\d{4}${RegExp.escape(kStructuredLineSuffix)}\\s*${RegExp.escape(kStructuredInputDelimiter)}\\s*',
          caseSensitive: false,
        ),
        '',
      ).replaceAll(
        RegExp(
          '${RegExp.escape(kStructuredLinePrefix)}\\d{4}${RegExp.escape(kStructuredLineSuffix)}\\s*${RegExp.escape(kStructuredOutputDelimiter)}\\s*',
          caseSensitive: false,
        ),
        '',
      ).trim();
}
