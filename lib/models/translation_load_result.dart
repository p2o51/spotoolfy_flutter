import '../services/settings_service.dart';

/// Represents the structured result returned after loading a translation.
class TranslationLoadResult {
  final String rawTranslatedLyrics;
  final String cleanedTranslatedLyrics;
  final Map<int, String> perLineTranslations;
  final TranslationStyle style;
  final String languageCode;

  const TranslationLoadResult({
    required this.rawTranslatedLyrics,
    required this.cleanedTranslatedLyrics,
    required this.perLineTranslations,
    required this.style,
    required this.languageCode,
  });
}
