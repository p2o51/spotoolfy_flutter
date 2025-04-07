import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';

class TranslationService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiApiBaseUrl = 
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest'; // Use the latest flash model
  static const String _cacheKeyPrefix = 'translation_cache_'; // Cache key prefix

  Future<String?> translateLyrics(String lyricsText, String trackId, {String? targetLanguage}) async {
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
    if (cachedTranslation != null) {
      print('Retrieved translation from cache for track $trackId ($language)');
      return cachedTranslation;
    }

    print('Fetching translation from API for track $trackId ($language)');

    final url = Uri.parse('$_geminiApiBaseUrl:generateContent?key=$apiKey');
    
    // Prepare the prompt
    final prompt = '''
Please translate the following song lyrics into $languageName. 
Preserve the line breaks and general structure of the original lyrics. 
Only output the translated text, without any additional commentary, introductions, or explanations.

Original Lyrics:
"""
$lyricsText
"""

Translated Lyrics ($languageName):
"""
''';

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
            String translatedText = content['parts'][0]['text'] ?? '';
            // Clean up potential markdown quotes
            if (translatedText.startsWith('```')) {
              translatedText = translatedText.substring(3);
            }
            if (translatedText.endsWith('```')) {
              translatedText = translatedText.substring(0, translatedText.length - 3);
            }
            translatedText = translatedText.trim();
            
            // Save to cache on success
            await prefs.setString(cacheKey, translatedText);
            print('Translation cached for track $trackId ($language)');

            return translatedText;
          }
        }
        // Handle cases where the expected structure isn't found
        print('Unexpected Gemini response structure: ${response.body}');
        throw Exception('Failed to parse translation response.');
      } else {
        print('Gemini API Error: ${response.statusCode} ${response.body}');
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
      print('Error during translation request: $e');
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
      print('Translation cache cleared.');
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