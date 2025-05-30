import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../services/settings_service.dart';

final logger = Logger();

class LyricsAnalysisService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/';
  static const String _geminiModel = 'gemini-2.5-flash-preview-05-20';

  Future<Map<String, dynamic>?> analyzeLyrics(
    String lyrics,
    String trackTitle,
    String artistName,
  ) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    if (lyrics.trim().isEmpty) {
      logger.d('No lyrics provided for analysis.');
      return null;
    }

    // 获取用户设定的目标语言
    final String languageCode = await _settingsService.getTargetLanguage();
    final String languageName = _getLanguageName(languageCode);

    final prompt = _buildPrompt(lyrics, trackTitle, artistName, languageName);
    
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
      'generationConfig': {
        'response_mime_type': 'application/json',
        'temperature': 0.8,
        'thinkingConfig': {
          'thinkingBudget': 0,
        }
      },
    });

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('Lyrics analysis request timed out.');
      });

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        
        final candidates = decodedResponse['candidates'];
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null &&
              content['parts'] != null &&
              content['parts'].isNotEmpty) {
            String rawJsonText = content['parts'][0]['text'] ?? '';

            // 清理可能的markdown围栏
            rawJsonText = rawJsonText.replaceAll('```json', '').replaceAll('```', '').trim();

            logger.d('Raw JSON from Gemini: $rawJsonText');

            try {
              final analysisJson = jsonDecode(rawJsonText);
              if (analysisJson is Map<String, dynamic>) {
                logger.d('Successfully parsed analysis: $analysisJson');
                return analysisJson;
              } else {
                throw Exception('Parsed JSON is not a valid map.');
              }
            } catch (e) {
              logger.e('Error parsing JSON response from Gemini: $e');
              logger.d('Raw text was: $rawJsonText');
              throw Exception('Failed to parse analysis JSON response.');
            }
          }
        }
        throw Exception('Failed to extract content from Gemini response.');
      } else {
        String errorMessage =
            'Analysis generation failed (Code: ${response.statusCode}).';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error'] != null &&
              errorJson['error']['message'] != null) {
            errorMessage += ' Details: ${errorJson['error']['message']}';
          }
        } catch (_) {
          // 忽略解析错误，使用默认消息
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      logger.e('Error during analysis API call or processing: $e');
      rethrow;
    }
  }

  String _buildPrompt(String lyrics, String trackTitle, String artistName, String languageName) {
    return '''
请分析以下歌词的内容，并用$languageName回答：

歌曲：$trackTitle
艺术家：$artistName

歌词：
$lyrics

请从以下几个方面进行分析：

1. 主题分析：这段歌词的主要主题是什么？
2. 情感表达：这段歌词传达了什么样的情感？
3. 隐喻和象征：歌词中有哪些隐喻、象征或比喻的表达？请解释其含义。
4. 深度解读：结合歌曲背景，这段歌词可能想要表达什么深层含义？

请以JSON格式回答，包含以下字段：
{
  "theme": "主题分析内容",
  "emotion": "情感分析内容", 
  "metaphor": "隐喻分析内容",
  "interpretation": "深度解读内容"
}

注意：请确保回答简洁而有深度，每个字段的内容控制在100字以内。
''';
  }

  String _getLanguageName(String languageCode) {
    switch (languageCode) {
      case 'zh':
      case 'zh-CN':
        return '中文';
      case 'zh-TW':
        return '繁体中文';
      case 'en':
        return 'English';
      case 'ja':
        return '日本语';
      case 'ko':
        return '한국어';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      case 'es':
        return 'Español';
      case 'it':
        return 'Italiano';
      case 'pt':
        return 'Português';
      case 'ru':
        return 'Русский';
      default:
        return 'English';
    }
  }
} 