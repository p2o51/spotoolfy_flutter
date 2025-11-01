import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
// import '../providers/local_database_provider.dart'; // Removed unused import
// 导入intl包用于日期格式化 (如果尚未导入)
// import 'package:intl/intl.dart'; 
import 'package:logger/logger.dart'; // Import logger

// Instantiate logger
final logger = Logger();

class InsightsService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/';
  static const String _geminiModel = 'gemini-2.5-flash';
  static const String _insightsCacheKey = 'cached_music_insights'; // 缓存键

  Future<Map<String, dynamic>?> generateMusicInsights(
      List<Map<String, dynamic>> recentContexts) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    if (recentContexts.isEmpty) {
      logger.d('No recent contexts provided for insights.');
      return null; // Or return a default message
    }

    // Extract context names for the prompt
    final contextNames = recentContexts
        .map((context) => context['contextName'] as String? ?? 'Unknown Context')
        .toList();
        
    // 获取用户设定的目标语言
    final String languageCode = await _settingsService.getTargetLanguage();
    final String languageName = _getLanguageName(languageCode);

    final prompt = _buildPrompt(contextNames, languageName);
    // 构建完整的模型URL
    final modelUrl = '$_geminiBaseUrl$_geminiModel';
    final url = Uri.parse('$modelUrl:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'contents': [
        {
          'parts': [{'text': prompt}]
        }
      ],
      // 更新 generationConfig 以包含 thinkingConfig
      'generationConfig': {
        'response_mime_type': 'application/json', // 保持强制JSON输出
        'temperature': 0.9, // 保留温度设置
        'thinkingConfig': {
          // 将思考预算硬编码为 0
          'thinkingBudget': 0,
        }
      },
      // Optional: Add safety settings if needed
      // 'safetySettings': [ ... ]
    });

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 45), onTimeout: () {
        throw Exception('Insights generation request timed out.');
      });

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        
        // Enhanced extraction logic for Gemini JSON response
        final candidates = decodedResponse['candidates'];
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null &&
              content['parts'] != null &&
              content['parts'].isNotEmpty) {
            String rawJsonText = content['parts'][0]['text'] ?? '';

            // Clean potential markdown fences if present
            rawJsonText = rawJsonText.replaceAll('```json', '').replaceAll('```', '').trim();

            logger.d('Raw JSON from Gemini: $rawJsonText');

            try {
              // Parse the cleaned JSON string
              final insightsJson = jsonDecode(rawJsonText);
              // Basic validation
              if (insightsJson is Map<String, dynamic> &&
                  insightsJson.containsKey('mood_analysis') &&
                  insightsJson.containsKey('recommendations') &&
                  insightsJson.containsKey('music_personality')) {
                 logger.d('Successfully parsed insights: $insightsJson');
                
                // 将结果保存到本地缓存
                await _saveInsightsToCache(insightsJson);
                
                return insightsJson;
              } else {
                throw Exception('Parsed JSON lacks expected structure.');
              }
            } catch (e) {
              logger.e('Error parsing JSON response from Gemini: $e');
              logger.d('Raw text was: $rawJsonText');
              throw Exception('Failed to parse insights JSON response.');
            }
          }
        }
        throw Exception('Failed to extract content from Gemini response.');
      } else {
        String errorMessage =
            'Insights generation failed (Code: ${response.statusCode}).';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error'] != null &&
              errorJson['error']['message'] != null) {
            errorMessage += ' Details: ${errorJson['error']['message']}';
          }
        } catch (_) {
          // Ignore parsing error, use default message
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      logger.e('Error during insights API call or processing: $e');
      // Rethrow or handle as needed, maybe return null or a specific error structure
      rethrow; // Rethrow to be caught by the UI layer
    }
  }

  // 从缓存获取上次生成的洞察数据
  Future<Map<String, dynamic>?> getCachedInsights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedInsightsJson = prefs.getString(_insightsCacheKey);
      
      if (cachedInsightsJson != null && cachedInsightsJson.isNotEmpty) {
        return jsonDecode(cachedInsightsJson) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      logger.e('Error retrieving cached insights: $e');
      return null;
    }
  }
  
  // 将洞察数据保存到本地缓存
  Future<void> _saveInsightsToCache(Map<String, dynamic> insights) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_insightsCacheKey, jsonEncode(insights));
      logger.d('Insights saved to cache');
    } catch (e) {
      logger.e('Error saving insights to cache: $e');
    }
  }
  
  // 清除缓存的洞察数据
  Future<void> clearCachedInsights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_insightsCacheKey);
      logger.d('Cached insights cleared');
    } catch (e) {
      logger.e('Error clearing cached insights: $e');
    }
  }

  String _buildPrompt(List<String> contextNames, String languageName) {
    final contextListString = contextNames.map((name) => '- "$name"').join('\n');
    // 获取当前时间并格式化
    final currentTime = DateTime.now().toIso8601String(); // 使用ISO 8601格式
    // 或者使用更友好的格式 (需要intl包): final currentTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    // 将当前时间添加到 prompt 中
    return '''
The current time is $currentTime.

Based on the following list of recently played music contexts by a user:

$contextListString

1. Create a music personality label for this listener. This should be a short creative descriptor that captures the essence of their musical taste. Examples: "Distortion Kaleidoscope", "Gazer of Post-Punk Fragments", "Synth Glacier Wanderer", "反高潮叙事信徒", "冷门圣地的守护灵".（should be written in $languageName.）

2. Analyze the overall mood conveyed by this listening history, considering the current time ($currentTime) might provide context. Say something to them in 2~5 concise sentences about their mood and daily life.

3. Your language should be:
- "Pitchfork"-style expression that maintains a slight distance and focuses more on the characteristics of the music itself or subcultural attributes.
- Carrying a subtle, almost imperceptible sense of solace. Touched upon lightly, avoiding directness. The wording is soft and delicate, yet of unsolved mysteries.


Please provide the response strictly in JSON format with the following structure:
{
  "music_personality": "Your music personality label here",
  "mood_analysis": "Your analysis text here.",
  "recommendations": [
    {"artist": "Artist Name 1", "track": "Track Name 1"},
    {"artist": "Artist Name 2", "track": "Track Name 2"}
    // ... up to 5 recommendations
  ]
}

IMPORTANT: The music_personality and mood_analysis should be written in $languageName, while the artist and track names should remain in their original language.
Only output the raw JSON object without any surrounding text or markdown formatting.
''';
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'en': return 'English';
      case 'zh-CN': return 'Simplified Chinese（简体中文）';
      case 'zh-TW': return 'Traditional Chinese（繁体中文）';
      case 'ja': return 'Japanese';
      default: return 'English'; // 默认使用英语
    }
  }
} 