import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../services/settings_service.dart';

final _logger = Logger();

/// Context type for AI chat conversations
enum ChatContextType {
  songInfo,
  lyricsAnalysis,
}

/// Represents context data for AI chat
class ChatContext {
  final ChatContextType type;
  final String trackTitle;
  final String artistName;
  final String? albumName;
  final String? selectedLyrics;
  final Map<String, dynamic>? additionalContext;

  ChatContext({
    required this.type,
    required this.trackTitle,
    required this.artistName,
    this.albumName,
    this.selectedLyrics,
    this.additionalContext,
  });

  /// Build context description for AI
  String buildContextDescription() {
    final buffer = StringBuffer();
    buffer.writeln('歌曲：$trackTitle');
    buffer.writeln('艺术家：$artistName');
    if (albumName != null && albumName!.isNotEmpty) {
      buffer.writeln('专辑：$albumName');
    }

    if (selectedLyrics != null && selectedLyrics!.isNotEmpty) {
      buffer.writeln('\n选中的歌词：');
      buffer.writeln('"$selectedLyrics"');
    }

    if (additionalContext != null) {
      buffer.writeln('\n已有信息：');
      additionalContext!.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          buffer.writeln('$key: $value');
        }
      });
    }

    return buffer.toString();
  }
}

/// Unified Gemini chat service for AI conversations
class GeminiChatService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/';
  static const String _geminiModel = 'gemini-flash-latest';

  /// Send a chat message with context
  Future<String> chat({
    required String message,
    required ChatContext context,
    List<Map<String, String>>? conversationHistory,
  }) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    final String languageCode = await _settingsService.getTargetLanguage();
    final String languageName = _getLanguageName(languageCode);

    final systemPrompt = _buildSystemPrompt(context, languageName);
    final contents = _buildContents(systemPrompt, message, conversationHistory);

    final modelUrl = '$_geminiBaseUrl$_geminiModel';
    final url = Uri.parse('$modelUrl:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'contents': contents,
      'tools': [
        {'googleSearch': {}}
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
          .timeout(const Duration(seconds: 45), onTimeout: () {
        throw Exception('Request timed out.');
      });

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        final candidates = decodedResponse['candidates'];
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null &&
              content['parts'] != null &&
              content['parts'].isNotEmpty) {
            return content['parts'][0]['text'] as String? ?? 'No response.';
          }
        }
        throw Exception('Failed to extract response.');
      } else {
        String errorMessage = 'Request failed (Code: ${response.statusCode}).';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error']?['message'] != null) {
            errorMessage += ' ${errorJson['error']['message']}';
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      _logger.e('Error during chat API call: $e');
      rethrow;
    }
  }

  /// Perform initial analysis for lyrics
  Future<Map<String, dynamic>> analyzeLyrics({
    required String lyrics,
    required String trackTitle,
    required String artistName,
  }) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    final String languageCode = await _settingsService.getTargetLanguage();
    final String languageName = _getLanguageName(languageCode);

    final prompt = _buildLyricsAnalysisPrompt(
        lyrics, trackTitle, artistName, languageName);

    final modelUrl = '$_geminiBaseUrl$_geminiModel';
    final url = Uri.parse('$modelUrl:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'tools': [
        {'googleSearch': {}}
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
        throw Exception('Analysis request timed out.');
      });

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        final candidates = decodedResponse['candidates'];
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null &&
              content['parts'] != null &&
              content['parts'].isNotEmpty) {
            String rawText = content['parts'][0]['text'] ?? '';
            rawText =
                rawText.replaceAll('```json', '').replaceAll('```', '').trim();

            final result = _parseTaggedResponse(rawText);
            if (result.isNotEmpty) {
              return result;
            }
            throw Exception('Empty analysis result.');
          }
        }
        throw Exception('Failed to extract analysis.');
      } else {
        String errorMessage =
            'Analysis failed (Code: ${response.statusCode}).';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error']?['message'] != null) {
            errorMessage += ' ${errorJson['error']['message']}';
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      _logger.e('Error during lyrics analysis: $e');
      rethrow;
    }
  }

  String _buildSystemPrompt(ChatContext context, String languageName) {
    final contextDesc = context.buildContextDescription();

    switch (context.type) {
      case ChatContextType.songInfo:
        return '''
你是一个专业的音乐评论家和音乐历史学家。用户正在查看以下歌曲的信息：

$contextDesc

请使用搜索功能查找准确的信息来回答用户的问题。用$languageName回答，语言风格要：
- 简洁但有深度
- 具有音乐评论的专业性
- 富有洞察力

直接回答问题，不需要重复歌曲基本信息。''';

      case ChatContextType.lyricsAnalysis:
        return '''
你是一个专业的歌词分析师和文学评论家。用户正在分析以下歌曲的歌词：

$contextDesc

请使用搜索功能查找准确的信息来回答用户关于这些歌词的问题。用$languageName回答，语言风格要：
- 具有文学评论的专业性和文艺性
- 有深度但不过于学术化
- 富有洞察力，能够揭示歌词的深层含义和文化意义

直接回答问题，专注于用户询问的内容。''';
    }
  }

  List<Map<String, dynamic>> _buildContents(
    String systemPrompt,
    String currentMessage,
    List<Map<String, String>>? history,
  ) {
    final contents = <Map<String, dynamic>>[];

    // Add system prompt as first user message
    contents.add({
      'role': 'user',
      'parts': [
        {'text': systemPrompt}
      ]
    });

    // Add a simple acknowledgement
    contents.add({
      'role': 'model',
      'parts': [
        {'text': '好的，我已经了解了歌曲信息，请问你有什么问题？'}
      ]
    });

    // Add conversation history
    if (history != null) {
      for (final msg in history) {
        contents.add({
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [
            {'text': msg['content'] ?? ''}
          ]
        });
      }
    }

    // Add current message
    contents.add({
      'role': 'user',
      'parts': [
        {'text': currentMessage}
      ]
    });

    return contents;
  }

  String _buildLyricsAnalysisPrompt(
    String lyrics,
    String trackTitle,
    String artistName,
    String languageName,
  ) {
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

  Map<String, dynamic> _parseTaggedResponse(String rawText) {
    final result = <String, dynamic>{};

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
        final content =
            rawText.substring(startIndex + startTag.length, endIndex).trim();

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
}
