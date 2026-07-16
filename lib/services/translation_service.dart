import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import '../models/lyrics_translation_error.dart';
import '../services/settings_service.dart';
import '../utils/lyrics_language.dart';
import '../utils/structured_translation.dart';

final logger = Logger();

class TranslationService {
  final SettingsService _settingsService = SettingsService();
  static const String _cacheKeyPrefix =
      'translation_cache_'; // Cache key prefix

  Future<Map<String, dynamic>> translateLyrics(
    List<String> originalLines,
    String trackId, {
    String? trackTitle,
    String? artistName,
    String? targetLanguage,
    bool forceRefresh = false,
    TranslationStyle? style,
  }) async {
    final languageCodeUsed = targetLanguage ??
        await _settingsService.getTargetLanguage(); // Capture the language used
    final languageName = _getLanguageName(languageCodeUsed);
    final styleUsed = style ?? await _settingsService.getTranslationStyle();
    final styleNameUsed = translationStyleToString(
        styleUsed); // Get style name for cache key and return value

    // Yoin-synced: skip the API round-trip entirely when the lyrics already
    // appear to be in the target language (currently Chinese targets only).
    if (lyricsAlreadyInTargetLanguage(originalLines, languageCodeUsed)) {
      throw const LyricsTranslationException(
        code: LyricsTranslationErrorCode.alreadyTargetLanguage,
        message: 'Lyrics already appear to be in the target language.',
      );
    }

    // Generate cache key including language and style
    final cacheKey =
        '$_cacheKeyPrefix${trackId}_${languageCodeUsed}_$styleNameUsed';
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      throw LyricsTranslationException(
        code: LyricsTranslationErrorCode.cacheFailure,
        message: 'Unable to access translation cache.',
        cause: e,
      );
    }

    if (!forceRefresh) {
      final cachedTranslation = prefs.getString(cacheKey);
      if (cachedTranslation != null) {
        logger.d('Translation cache hit for $cacheKey');
        final parsed = parseLyricsTranslationText(
          cachedTranslation,
          originalLines: originalLines,
        );

        final lineTranslations = <String, String>{};
        parsed.translations.forEach((index, value) {
          final trimmed = value.trim();
          if (trimmed.isNotEmpty) {
            lineTranslations[index.toString()] = trimmed;
          }
        });

        return {
          'text': cachedTranslation,
          'cleanedText': parsed.cleanedText,
          'lineTranslations': lineTranslations,
          'languageCode': languageCodeUsed,
          'style': styleNameUsed,
        };
      }
    } else {
      await prefs.remove(cacheKey);
      logger.d('Forcing refresh: Removed cache for $cacheKey');
    }

    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const LyricsTranslationException(
        code: LyricsTranslationErrorCode.missingApiKey,
        message: 'Gemini API Key not configured.',
      );
    }

    // 使用统一的模型配置
    final modelUrl = await _settingsService.getGeminiApiUrl();
    final generationConfig = await _settingsService.getGeminiGenerationConfig();

    final url = Uri.parse('$modelUrl:generateContent?key=$apiKey');

    // Get the prompt based on the selected style
    final prompt = _buildLyricsTranslationPrompt(
      style: styleUsed,
      languageName: languageName,
      trackTitle: trackTitle,
      artistName: artistName,
      originalLines: originalLines,
    );

    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      // 翻译不需要 Google Search，使用统一的生成配置
      'generationConfig': generationConfig,
    });

    try {
      final response =
          await http.post(url, headers: headers, body: body).timeout(
                const Duration(
                    seconds:
                        30), // Increased timeout for potential long translations
                onTimeout: () => throw const LyricsTranslationException(
                  code: LyricsTranslationErrorCode.requestTimeout,
                  message: 'Translation request timed out.',
                ),
              );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        // Extract the text, handling potential errors or different structures
        final candidates = decodedResponse['candidates'];
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null &&
              content['parts'] != null &&
              content['parts'].isNotEmpty) {
            final rawResult = (content['parts'][0]['text'] ?? '').toString();
            logger.d('Raw result from AI:\n$rawResult');

            final normalized = rawResult.trim();
            final parsed = parseLyricsTranslationText(
              normalized,
              originalLines: originalLines,
            );

            // Yoin-synced: a response with no usable per-line translations is
            // an error, not a silent success.
            if (parsed.translations.values
                .every((value) => value.trim().isEmpty)) {
              throw const LyricsTranslationException(
                code: LyricsTranslationErrorCode.invalidResponse,
                message: 'No usable lyric translations in response.',
              );
            }

            final lineTranslations = <String, String>{};
            parsed.translations.forEach((index, value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) {
                lineTranslations[index.toString()] = trimmed;
              }
            });

            await prefs.setString(cacheKey, normalized);

            return {
              'text': normalized,
              'cleanedText': parsed.cleanedText,
              'lineTranslations': lineTranslations,
              'languageCode': languageCodeUsed,
              'style': styleNameUsed,
            };
          }
        }
        // Handle cases where the expected structure isn't found
        throw const LyricsTranslationException(
          code: LyricsTranslationErrorCode.invalidResponse,
          message: 'Failed to parse translation response.',
        );
      } else {
        // Try to parse error message from response
        String errorMessage =
            'Translation failed (HTTP ${response.statusCode}).';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error'] != null &&
              errorJson['error']['message'] != null) {
            errorMessage += ' Details: ${errorJson['error']['message']}';
          }
        } catch (_) {
          // Ignore parsing error, use default message
        }
        throw LyricsTranslationException(
          code: LyricsTranslationErrorCode.apiError,
          message: errorMessage,
        );
      }
    } on LyricsTranslationException {
      rethrow;
    } on SocketException catch (e) {
      logger.d('Gemini API unreachable: $e');
      throw LyricsTranslationException(
        code: LyricsTranslationErrorCode.apiUnreachable,
        message: 'Unable to reach Gemini API endpoint.',
        cause: e,
      );
    } on http.ClientException catch (e) {
      logger.d('HTTP client error when calling Gemini API: $e');
      throw LyricsTranslationException(
        code: LyricsTranslationErrorCode.apiUnreachable,
        message: 'Gemini API request could not be completed.',
        cause: e,
      );
    } catch (e) {
      logger.d('Error during translation API call or processing: $e');
      throw LyricsTranslationException(
        code: LyricsTranslationErrorCode.unknown,
        message: 'Unexpected error during translation.',
        cause: e,
      );
    }
  }

  // Yoin-synced prompt: indexed source lines in, one tagged block per line
  // out. Blank lines keep their original index but are not sent.
  String _buildLyricsTranslationPrompt({
    required TranslationStyle style,
    required String languageName,
    required List<String> originalLines,
    String? trackTitle,
    String? artistName,
  }) {
    String tone;
    switch (style) {
      case TranslationStyle.faithful:
        tone = 'natural';
        break;
      case TranslationStyle.melodramaticPoet:
        tone = 'lyrical';
        break;
      case TranslationStyle.machineClassic:
        tone = 'robotic';
        break;
      case TranslationStyle.neteaseProvider:
        // 网易云翻译不使用 Gemini，此处不会被调用
        tone = 'natural';
        break;
    }

    final title = trackTitle?.trim().isNotEmpty == true
        ? trackTitle!.trim()
        : 'Unknown song';
    final artist = artistName?.trim().isNotEmpty == true
        ? artistName!.trim()
        : 'Unknown artist';
    final indexedLines = nonBlankLineIndices(originalLines)
        .map((index) => '[$index] ${originalLines[index]}')
        .join('\n');

    return '''
Translate these lyric lines into $languageName.

Song: $title
Artist: $artist

Preserve line count and meaning. Keep imagery natural, concise, and singable.
Tone: $tone.
Return strictly one tagged block per source line, keeping each line's index:

[L0]translation for line 0[/L0]
[L1]translation for line 1[/L1]

Lines:
$indexedLines
''';
  }

  // Helper to get the full language name for the prompt
  String _getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'zh-CN':
        return 'Simplified Chinese';
      case 'zh-TW':
        return 'Traditional Chinese';
      case 'ja':
        return 'Japanese';
      default:
        return 'English'; // Fallback
    }
  }

  // Method to clear only the translation cache
  Future<void> clearTranslationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (var key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      logger.d('Failed to clear translation cache: $e');
    }
  }

  // Method to get the approximate size of the translation cache
  Future<int> getTranslationCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int totalSize = 0;

      for (var key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          final value = prefs.getString(key);
          if (value != null) {
            // Estimate size based on UTF-16 code units (Dart strings)
            totalSize += value.length * 2;
          }
        }
      }
      return totalSize;
    } catch (e) {
      logger.d('Failed to get translation cache size: $e');
      return 0;
    }
  }

  // Helper to convert enum to string for saving/cache key
  String translationStyleToString(TranslationStyle style) {
    return style.toString().split('.').last;
  }
}
