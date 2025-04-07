import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';

class TranslationService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiApiBaseUrl = 
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest'; // Use the latest flash model
  static const String _cacheKeyPrefix = 'translation_cache_'; // Cache key prefix

  Future<String?> translateLyrics(String lyricsText, String trackId, {String? targetLanguage, bool forceRefresh = false}) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    final language = targetLanguage ?? await _settingsService.getTargetLanguage();
    final languageName = _getLanguageName(language); // Get full language name for the prompt
    
    // Generate cache key
    final cacheKey = '$_cacheKeyPrefix${trackId}_$language';
    final prefs = await SharedPreferences.getInstance();

    // Try fetching from cache first
    final cachedTranslation = prefs.getString(cacheKey);
    if (cachedTranslation != null && !forceRefresh) {
      return cachedTranslation;
    }

    // If forcing refresh, remove existing cache entry
    if (forceRefresh) {
      await prefs.remove(cacheKey);
      print('Forcing refresh: Removed cache for $cacheKey');
    }

    final url = Uri.parse('$_geminiApiBaseUrl:generateContent?key=$apiKey');
    
    // Prepare the prompt correctly
    final prompt = '''
Please translate the following song lyrics into $languageName. 
Preserve the line breaks and general structure of the original lyrics. 
Your lyrics need to be accurate in meaning and retain the artistry of the original lyrics.
Based on the principles above, the lyrics can be vivid, or some conjunctions can be appropriately added to make them flow smoothly.

Only output the translated text, wrapped between '###' symbols, like ###Translated Lyrics Here###. Do not include the '###' symbols themselves in the final output if they are part of the original lyrics.

Original Lyrics:
"""
$lyricsText
"""

Translated Lyrics ($languageName):
###
'''; // Request AI to wrap result in ###

    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'contents': [{
        'parts': [{'text': prompt}]
      }],
      // Optional: Add generation config for safety settings etc. if needed
      // 'generationConfig': {
      //   'temperature': 0.7, 
      //   'topK': 1,
      //   'topP': 1,
      //   'maxOutputTokens': 2048, 
      // },
      // 'safetySettings': [
      //   { 'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_MEDIUM_AND_ABOVE' },
      //   { 'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_MEDIUM_AND_ABOVE' },
      //   { 'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_MEDIUM_AND_ABOVE' },
      //   { 'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_MEDIUM_AND_ABOVE' },
      // ],
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
            await prefs.setString(cacheKey, translatedText);

            return translatedText;
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
      // Re-throw the exception to be handled by the caller
      rethrow; 
    }
    return null; // Should not be reached if error handling is correct, but added for safety
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
} 