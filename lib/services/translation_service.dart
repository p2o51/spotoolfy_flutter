import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';

class TranslationService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiBaseUrl = 
      'https://generativelanguage.googleapis.com/v1beta/models/';
  static const String _geminiDefaultModel = 'gemini-2.5-flash-preview-04-17';
  static const String _geminiThinkingModel = 'gemini-2.5-flash-preview-04-17';
  static const int _thinkingBudget = 1024;
  static const String _cacheKeyPrefix = 'translation_cache_'; // Cache key prefix

  Future<Map<String, String?>?> translateLyrics(String lyricsText, String trackId, {String? targetLanguage, bool forceRefresh = false}) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    final languageCodeUsed = targetLanguage ?? await _settingsService.getTargetLanguage(); // Capture the language used
    final languageName = _getLanguageName(languageCodeUsed);
    final styleUsed = await _settingsService.getTranslationStyle(); // Capture the style used
    final styleNameUsed = translationStyleToString(styleUsed); // Get style name for cache key and return value
    final enableThinking = await _settingsService.getEnableThinkingForTranslation(); // 获取思考模式设置

    // 选择合适的模型
    final model = enableThinking ? _geminiThinkingModel : _geminiDefaultModel;
    final modelUrl = '$_geminiBaseUrl$model';

    // Generate cache key including language and style
    final thinkingSuffix = enableThinking ? '_thinking$_thinkingBudget' : '_noThinking';
    final cacheKey = '$_cacheKeyPrefix${trackId}_${languageCodeUsed}_${styleNameUsed}$thinkingSuffix';
    final prefs = await SharedPreferences.getInstance();

    // Try fetching from cache first
    final cachedTranslation = prefs.getString(cacheKey);
    if (cachedTranslation != null && !forceRefresh) {
      print('Translation cache hit for $cacheKey');
      // Return cached text along with the language/style it was created with
      return {
        'text': cachedTranslation,
        'languageCode': languageCodeUsed,
        'style': styleNameUsed,
      };
    }

    // If forcing refresh, remove existing cache entry
    if (forceRefresh) {
      await prefs.remove(cacheKey);
      print('Forcing refresh: Removed cache for $cacheKey');
    }

    final url = Uri.parse('$modelUrl:generateContent?key=$apiKey');
    
    // Get the prompt based on the selected style
    final prompt = _getPromptForStyle(styleUsed, languageName, lyricsText);

    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'contents': [{
        'parts': [{'text': prompt}]
      }],
      'generationConfig': {
        'thinkingConfig': {
          'thinkingBudget': enableThinking ? _thinkingBudget : 0
        }
      },
    });

    try {
      final response = await http.post(url, headers: headers, body: body).timeout(
        const Duration(seconds: 30), // Increased timeout for potential long translations
        onTimeout: () => throw Exception('Translation request timed out.'),
      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        // Extract the text, handling potential errors or different structures
        final candidates = decodedResponse['candidates'];
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null && content['parts'] != null && content['parts'].isNotEmpty) {
            String rawResult = content['parts'][0]['text'] ?? '';
            
            // 更全面的文本清理算法
            String translatedText = rawResult;
            
            // 方法1：尝试通过定界符提取
            final startIndex = rawResult.indexOf('###');
            final endIndex = rawResult.lastIndexOf('###');
            
            if (startIndex != -1 && endIndex != -1 && startIndex < endIndex) {
              translatedText = rawResult.substring(startIndex + 3, endIndex).trim();
            }
            
            // 方法2：无论如何确保开始和结束的###都被移除
            // 移除开头的###
            if (translatedText.startsWith('###')) {
              translatedText = translatedText.substring(3);
            }
            
            // 移除结尾的###
            if (translatedText.endsWith('###')) {
              translatedText = translatedText.substring(0, translatedText.length - 3);
            }
            
            // 再次整理文本
            translatedText = translatedText.trim();
            
            // 移除任何井号之间的空白，有些AI会用`### ###`形式
            if (translatedText.contains('### ###')) {
              translatedText = translatedText.replaceAll('### ###', '');
            }
            
            // 检查并移除内部出现的###
            final parts = translatedText.split('###');
            if (parts.length > 1) {
              // 如果内部有###，取最长的部分作为翻译结果
              String longestPart = '';
              for (final part in parts) {
                final trimmedPart = part.trim();
                if (trimmedPart.length > longestPart.length) {
                  longestPart = trimmedPart;
                }
              }
              translatedText = longestPart;
            }
            
            // 最后的整理
            translatedText = translatedText.trim();
            
            // 移除任何未预期的换行符或空白
            translatedText = translatedText.replaceAll(RegExp(r'^\s*###\s*|\s*###\s*$'), '');
            
            // 打印调试信息 (开发阶段，最终可以移除)
            print('Raw result from AI:\n$rawResult');
            print('Final cleaned translation:\n$translatedText');
            
            // Save to cache (even if refreshed, save the new result)
            // Use the style-specific cache key but save only the clean text
            await prefs.setString(cacheKey, translatedText); 

            // Return the result map
            return {
              'text': translatedText,
              'languageCode': languageCodeUsed,
              'style': styleNameUsed,
            };
          }
        }
        // Handle cases where the expected structure isn't found
        throw Exception('Failed to parse translation response.');
      } else {
        // Try to parse error message from response
        String errorMessage = 'Translation failed (Code: ${response.statusCode}).';
        try {
           final errorJson = jsonDecode(response.body);
           if (errorJson['error'] != null && errorJson['error']['message'] != null) {
             errorMessage += ' Details: ${errorJson['error']['message']}';
           }
        } catch (_) {
          // Ignore parsing error, use default message
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('Error during translation API call or processing: $e');
      // Return null if translation fails
      return null;
    }
  }

  // Helper function to generate the prompt based on the selected style
  String _getPromptForStyle(TranslationStyle style, String languageName, String lyricsText) {
    switch (style) {
      case TranslationStyle.faithful:
        // Updated Faithful Style Prompt
        return '''
Please translate the following song lyrics into $languageName in a **Faithful** style.

Your **absolute primary goal** is **accuracy in conveying the most likely intended meaning** of the original words and phrases.
**Secondly**, strive to **retain the artistry, tone, and feeling** that are **explicitly present in the original wording**, without making assumptions about broader context.
**Preserve the line breaks and general sentence structure** of the original lyrics as closely as grammatically possible in $languageName.

**Handling Potential Issues:**
*   **Idioms & Figurative Language:** Translate common, well-understood idioms and metaphors by conveying their **conceptual meaning** in $languageName, finding the closest natural equivalent if one exists. If an expression is obscure, highly ambiguous without context, or seems like unique wordplay, lean towards a **more literal translation** that preserves the original image or phrasing, even if it feels slightly unusual in $languageName.
*   **Adjustments for Flow:** Only make **minimal grammatical adjustments** (e.g., adding necessary particles, slightly altering word order to fit $languageName syntax) if a direct, literal rendering is **grammatically incorrect or completely unintelligible** in $languageName. **Prioritize fidelity to the original phrasing and structure** over achieving perfect colloquial fluency. Avoid adding conjunctions or smoothing transitions unless grammatically essential.


Only output the translated text, wrapped between '###' symbols, like ###Translated Lyrics Here###. Do not include the '###' symbols themselves in the final output if they are part of the original lyrics.

Original Lyrics:
"""
$lyricsText
"""

Translated Lyrics ($languageName) [Faithful Style]:
###
''';
      case TranslationStyle.melodramaticPoet:
        // Unchanged Melodramatic Poet Style Prompt
        return '''
Please translate the following song lyrics into $languageName in a **Melodramatic Poet** style.
Preserve the line breaks and general structure of the original lyrics.
Your main goal is to create lyrics that are **highly emotionally resonant, poetic, and appealing** .
Feel free to use **embellished, flowery, and evocative language** to capture or even **heighten the mood and sentiment**.
You have permission and are encouraged to **deviate somewhat from the literal meaning** if it serves the emotional impact and makes the lyrics more captivating or 'popular' (讨好大众).
**Prioritize poetic flair, emotional punch, and audience appeal** over strict fidelity to the original text. However, the core theme should remain recognizable.

Only output the translated text, wrapped between '###' symbols, like ###Translated Lyrics Here###. Do not include the '###' symbols themselves in the final output if they are part of the original lyrics.
Even though you are a poet, the output format should still be lyrics, and **DO NOT** input punctuation marks that does not exist in the original text.

Original Lyrics:
"""
$lyricsText
"""

Translated Lyrics ($languageName) [Melodramatic Poet Style]:
###
''';
      case TranslationStyle.machineClassic:
        // Updated Machine Classic Style Prompt
        return '''
Please translate the following song lyrics into $languageName, strictly adhering to the **"Machine Translation Classic" (circa 2004) style**, aiming for a result that sounds deliberately awkward and unnatural, sometimes even humorously so.
Preserve the line breaks and general structure of the original lyrics.

Your **absolute top priority** is ensuring the output strongly exhibits a **stiff, overly literal, and context-ignoring** machine translation style. The goal is **maximum literalness**, even at the cost of naturalness, fluency, idiomatic meaning, or even perfect semantic accuracy in context.

**Key Characteristics to Emulate:**
*   **Word-for-word:** Stick as closely as possible to the original word order and word choices, even if it results in awkward phrasing in $languageName.
*   **Ignore Context & Idioms:** Translate words based on their most basic or literal dictionary meaning, ignoring idiomatic usage, figurative language, or common sense context.
*   **Awkward & Unnatural Phrasing:** Do not try to make the translation sound smooth or natural in $languageName. Embrace stiffness and potential grammatical oddities if they arise from literal translation.

**Examples of the desired style:**
*   "Yes, and?" should NOT be translated as "是的，然后呢？" (natural), but as something like "是的，而且。" (literal 'and').
*   "Don't think twice about it" should NOT be translated as "不要再多想它" (natural), but as "不要想两次关于它。" (literal structure).
*   "I need a, yeah, I need, fuck it, I need a minute." should NOT be "我需要，是啊，我需要，妈的，我需要一分钟" (natural flow & interpretation), but rather "我需要一个，耶，我需要，操它，我需要一分钟。" (literal particles and interjections).

**Do NOT prioritize:** Naturalness, fluency, idiomatic correctness, poetic quality, or conveying subtle nuances. The goal is a **grammatically possible but pragmatically strange, literal output characteristic of early, non-contextual MT.**
**Do not enter too many spaces in the same line of lyrics.**

Only output the translated text, wrapped between '###' symbols, like ###Translated Lyrics Here###. Do not include the '###' symbols themselves in the final output if they are part of the original lyrics.

Original Lyrics:
"""
$lyricsText
"""

Translated Lyrics ($languageName) [Machine Translation Classic Style]:
###
''';
    }
  }

  // Helper to get the full language name for the prompt
  String _getLanguageName(String code) {
    switch (code) {
      case 'en': return 'English';
      case 'zh-CN': return 'Simplified Chinese';
      case 'zh-TW': return 'Traditional Chinese';
      case 'ja': return 'Japanese';
      default: return 'English'; // Fallback
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
      print('Failed to clear translation cache: $e');
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
      print('Failed to get translation cache size: $e');
      return 0;
    }
  }

  // Helper to convert enum to string for saving/cache key
  String translationStyleToString(TranslationStyle style) {
    return style.toString().split('.').last;
  }
} 