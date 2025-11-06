enum LyricsTranslationErrorCode {
  missingApiKey('LT001'),
  cacheFailure('LT002'),
  requestTimeout('LT003'),
  invalidResponse('LT004'),
  apiError('LT005'),
  apiUnreachable('LT006'),
  unknown('LT999');

  final String code;
  const LyricsTranslationErrorCode(this.code);
}

/// Exception thrown when lyrics translation fails.
class LyricsTranslationException implements Exception {
  final LyricsTranslationErrorCode code;
  final String message;
  final Object? cause;

  const LyricsTranslationException({
    required this.code,
    required this.message,
    this.cause,
  });

  String get codeString => code.code;

  @override
  String toString() {
    return 'Error code $codeString: $message';
  }
}
