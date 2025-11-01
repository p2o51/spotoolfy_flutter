import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../services/settings_service.dart';

final logger = Logger();

class LyricsAnalysisService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/';
  static const String _geminiModel = 'gemini-2.5-flash';

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
      'tools': [
        {
          'googleSearch': {}
        }
      ],
      'generationConfig': {
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
              final analysisJson = _parseTaggedResponse(rawJsonText);
              if (analysisJson.isNotEmpty) {
                logger.d('Successfully parsed analysis: $analysisJson');
                return analysisJson;
              } else {
                throw Exception('Parsed response is empty.');
              }
            } catch (e) {
              logger.e('Error parsing tagged response from Gemini: $e');
              logger.d('Raw text was: $rawJsonText');
              throw Exception('Failed to parse analysis response.');
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
    return """
请以最精炼和深刻的方式分析以下歌词的内容，并用$languageName回答。请专注于核心洞察，避免不必要的细节和冗余描述，也避免使用 Markdown 格式。
（注意：如果歌词中确实不存在相关内容，请在对应标签内明确指出"无相关内容"，否则请提供精准分析。深度解读内容为必填内容。）
歌曲：$trackTitle
艺术家：$artistName

歌词：
$lyrics

请从以下几个方面进行分析，每个方面的阐述都应力求简洁、直击要点，当你使用到原文或者原歌词时应该使用原来的语言，不要翻译。：

1. **核心隐喻与象征**：
   识别歌词中1-3个最核心的隐喻、象征或明喻。请直接列出，并用一两句话简洁阐释它们在歌词语境下的主要含义与作用。

2. **关键引用与典故**：
   歌词中是否包含对理解歌词至关重要的引用或典故（如文学、历史、文化符号等）？如果存在，请列出1-2个最关键的，简述其来源及其为歌词带来的核心意义。若无，则忽略。

3. **特殊关键词解读**：
   是否存在1-3个因特定文化背景、时代特征或歌词语境而具有特殊引申含义的关键词或短语？请选择最重要的进行解释，一句话点明其特殊意义。

4. **精粹深度解读**：
   请结合上述分析（若有），并考虑歌曲可能的创作背景，用 Pitchfork 风格提供一段凝练且具有洞察力的深度解读。聚焦于歌词的核心主题、情感内核、突出的艺术手法，及其可能引发听者的核心思考或情感共鸣。追求表达的精准、逻辑的清晰和思辨性，避免空泛和不成体系的联想。

请严格按照以下格式输出：

[METAPHOR]
核心隐喻与象征分析内容或无相关内容
[/METAPHOR]

[REFERENCE]
关键引用与典故分析内容或无相关内容
[/REFERENCE]

[KEYWORDS_EXPLANATION]
特殊关键词解读内容或无相关内容
[/KEYWORDS_EXPLANATION]

[INTERPRETATION]
深度解读内容（必填）
[/INTERPRETATION]

请确保所有回答都高度凝练，直指核心。
""";
  }

  String _getLanguageName(String languageCode) {
    switch (languageCode) {
      case 'zh-CN':
        return '中文';
      case 'zh-TW':
        return '繁体中文';
      case 'en':
        return 'English';
      case 'ja':
        return '日本语';
      default:
        return 'English';
    }
  }

  Map<String, dynamic> _parseTaggedResponse(String rawText) {
    final result = <String, dynamic>{};
    
    // 定义标签映射
    final tags = {
      'METAPHOR': 'metaphor',
      'REFERENCE': 'reference', 
      'KEYWORDS_EXPLANATION': 'keywords_explanation',
      'INTERPRETATION': 'interpretation',
    };
    
    for (final entry in tags.entries) {
      final tagName = entry.key;
      final fieldName = entry.value;
      
      final startTag = '[$tagName]';
      final endTag = '[/$tagName]';
      
      final startIndex = rawText.indexOf(startTag);
      final endIndex = rawText.indexOf(endTag);
      
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        final content = rawText.substring(
          startIndex + startTag.length,
          endIndex
        ).trim();
        
        // 如果内容不是"无相关内容"且不为空，则添加到结果中
        if (content.isNotEmpty && 
            content != '无相关内容' && 
            content.toLowerCase() != 'null' &&
            content.toLowerCase() != 'n/a' &&
            content != 'No relevant content' &&
            content != 'None') {
          result[fieldName] = content;
        }
      }
    }
    
    return result;
  }
} 