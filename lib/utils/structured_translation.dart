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

    // Defensive guard: drop any echoed delimiters and keep only the translated text.
    if (segment.contains(kStructuredOutputDelimiter)) {
      segment = segment.split(kStructuredOutputDelimiter).last;
    }
    if (segment.contains(kStructuredInputDelimiter)) {
      segment = segment.split(kStructuredInputDelimiter).last;
    }

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

/// --- Yoin-synced tagged line-translation format ---
///
/// The prompt asks the model to return one `[L0]translation[/L0]` block per
/// source line (indices refer to the original lyric line order). The parser
/// tolerates case/whitespace variants and falls back to plain-line mapping
/// when the model ignores the schema but keeps the line count intact.

/// Matches any `[TAG]` / `[/TAG]` marker (e.g. `[L0]`, `[ / L12 ]`).
final RegExp _tagMarkerRegex = RegExp(
  r'\[\s*/?\s*[A-Z][A-Z0-9_]*\s*\]',
  caseSensitive: false,
);

final RegExp _lineTranslationRegex = RegExp(
  r'\[\s*L(\d+)\s*\](.*?)\[\s*/\s*L\1\s*\]',
  caseSensitive: false,
  dotAll: true,
);

/// Leading list markers the model sometimes prepends: `- `, `[1] `, `【2】`,
/// `(3)`, `4.`, `5、` etc.
final RegExp _leadingLineMarkerRegex = RegExp(
  r'^(?:[-*•]\s*)?(?:(?:[\[【(]\s*\d+\s*[\]】)])(?:[.)：:、])?|\d+[.)：:、])\s*',
);

/// Strip any leftover `[TAG]` / `[/TAG]` markers from prose so a malformed
/// or truncated response still renders as clean text.
String stripTagMarkers(String text) =>
    text.replaceAll(_tagMarkerRegex, '').trim();

/// Sanitize a single translated line: drop tag markers and leading
/// bullet/number markers the model sometimes echoes.
String cleanLineTranslation(String text) {
  var cleaned = stripTagMarkers(text);
  for (var i = 0; i < 3; i++) {
    cleaned = cleaned.replaceFirst(_leadingLineMarkerRegex, '').trim();
  }
  return cleaned;
}

/// Parses `[L<i>]...[/L<i>]` blocks into an index → translation map.
/// Indices outside `[0, lineCount)` are dropped when [lineCount] is given.
Map<int, String> parseTaggedLineTranslations(
  String rawText, {
  int? lineCount,
}) {
  final tagged = <int, String>{};
  for (final match in _lineTranslationRegex.allMatches(rawText)) {
    final index = int.tryParse(match.group(1) ?? '');
    if (index == null || index < 0) continue;
    if (lineCount != null && index >= lineCount) continue;
    final text = cleanLineTranslation(match.group(2) ?? '');
    if (text.isNotEmpty) {
      tagged[index] = text;
    }
  }
  return tagged;
}

/// Indices of the lines that are actually sent to the model (blank lines
/// stay behind but keep their original index in the result map).
List<int> nonBlankLineIndices(List<String> originalLines) => [
      for (var i = 0; i < originalLines.length; i++)
        if (originalLines[i].trim().isNotEmpty) i,
    ];

/// Parses a lyric translation payload, trying (in order):
/// 1. the Yoin-style tagged `[L0]...[/L0]` format,
/// 2. the legacy `__L0001__ <<< ` structured format (older cache entries),
/// 3. plain lines mapped onto the non-blank source lines when counts match.
StructuredTranslationParserResult parseLyricsTranslationText(
  String rawText, {
  List<String>? originalLines,
}) {
  final tagged = parseTaggedLineTranslations(
    rawText,
    lineCount: originalLines?.length,
  );
  if (tagged.isNotEmpty) {
    return StructuredTranslationParserResult(
      translations: tagged,
      missingLineIndices: _findMissingIndices(originalLines, tagged),
      cleanedText: _buildCleanedText(
        originalLines: originalLines,
        translations: tagged,
      ),
    );
  }

  final legacy = parseStructuredTranslation(rawText, originalLines: originalLines);
  if (legacy.translations.isNotEmpty || originalLines == null) {
    return legacy;
  }

  final sentIndices = nonBlankLineIndices(originalLines);
  final plainLines = rawText
      .split('\n')
      .map(cleanLineTranslation)
      .where((line) => line.isNotEmpty)
      .toList();
  if (plainLines.isNotEmpty && plainLines.length == sentIndices.length) {
    final translations = <int, String>{
      for (var i = 0; i < plainLines.length; i++) sentIndices[i]: plainLines[i],
    };
    return StructuredTranslationParserResult(
      translations: translations,
      missingLineIndices: _findMissingIndices(originalLines, translations),
      cleanedText: _buildCleanedText(
        originalLines: originalLines,
        translations: translations,
      ),
    );
  }

  return legacy;
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
