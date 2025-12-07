import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class SongInfoService {
  final SettingsService _settingsService = SettingsService();
  static const String _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/';
  static const String _geminiModel = 'gemini-flash-latest';
  static const String _songInfoCacheKeyPrefix = 'cached_song_info_'; // 缓存键前缀
  SharedPreferences? _prefsCache;

  Future<Map<String, dynamic>?> generateSongInfo(
      Map<String, dynamic> trackData, {bool skipCache = false}) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    if (trackData.isEmpty) {
      logger.d('No track data provided for song info.');
      return null;
    }

    // 提取歌曲信息
    final trackName = trackData['name'] as String? ?? 'Unknown Track';
    final artistNames = (trackData['artists'] as List?)
        ?.map((artist) => artist['name'] as String)
        .join(', ') ?? 'Unknown Artist';
    final albumName = trackData['album']?['name'] as String? ?? 'Unknown Album';
    final releaseDate = trackData['album']?['release_date'] as String? ?? '';
    final trackId = trackData['id'] as String? ?? '';

    // 检查缓存（除非明确要求跳过缓存）
    if (!skipCache) {
      final cachedInfo = await _getCachedSongInfo(trackId);
      if (cachedInfo != null) {
        logger.d('从缓存获取歌曲信息: $trackId');
        return cachedInfo;
      }
    } else {
      logger.d('跳过缓存，强制重新生成歌曲信息: $trackId');
    }

    // 获取用户设定的目标语言
    final String languageCode = await _settingsService.getTargetLanguage();
    final String languageName = _getLanguageName(languageCode);

    final prompt = _buildPrompt(trackName, artistNames, albumName, releaseDate, languageName);
    
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
          .timeout(const Duration(seconds: 45), onTimeout: () {
        throw Exception('Song info generation request timed out.');
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

            logger.d('Raw text from Gemini: $rawText');

            try {
              // 解析标签格式的响应
              final songInfoJson = _parseTaggedResponse(rawText);
              logger.d('Successfully parsed song info: $songInfoJson');
              
              // 将结果保存到本地缓存
              await _saveSongInfoToCache(trackId, songInfoJson);
              
              return songInfoJson;
            } catch (e) {
              logger.e('Error parsing tagged response from Gemini: $e');
              logger.d('Raw text was: $rawText');
              throw Exception('Failed to parse song info response.');
            }
          }
        }
        throw Exception('Failed to extract content from Gemini response.');
      } else {
        String errorMessage =
            'Song info generation failed (Code: ${response.statusCode}).';
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
      logger.e('Error during song info API call or processing: $e');
      rethrow;
    }
  }

  // 从缓存获取歌曲信息
  Future<Map<String, dynamic>?> _getCachedSongInfo(String trackId) async {
    try {
      final prefs = await _getPrefs();
      final cacheKey = '$_songInfoCacheKeyPrefix$trackId';
      final cachedInfoJson = prefs.getString(cacheKey);
      
      if (cachedInfoJson != null && cachedInfoJson.isNotEmpty) {
        return jsonDecode(cachedInfoJson) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      logger.e('Error retrieving cached song info: $e');
      return null;
    }
  }
  
  // 将歌曲信息保存到本地缓存
  Future<void> _saveSongInfoToCache(String trackId, Map<String, dynamic> songInfo) async {
    try {
      final prefs = await _getPrefs();
      final cacheKey = '$_songInfoCacheKeyPrefix$trackId';
      await prefs.setString(cacheKey, jsonEncode(songInfo));
      logger.d('Song info saved to cache for track: $trackId');
    } catch (e) {
      logger.e('Error saving song info to cache: $e');
    }
  }
  
  // 清除缓存的歌曲信息
  Future<void> clearCachedSongInfo() async {
    try {
      final prefs = await _getPrefs();
      final keys = prefs.getKeys();
      final songInfoKeys = keys.where((key) => key.startsWith(_songInfoCacheKeyPrefix));
      
      for (final key in songInfoKeys) {
        await prefs.remove(key);
      }
      logger.d('Cached song info cleared');
    } catch (e) {
      logger.e('Error clearing cached song info: $e');
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    final cached = _prefsCache;
    if (cached != null) {
      return cached;
    }
    final prefs = await SharedPreferences.getInstance();
    _prefsCache = prefs;
    return prefs;
  }

  String _buildPrompt(String trackName, String artistNames, String albumName, String releaseDate, String languageName) {
    return '''
请搜索并提供以下歌曲的详细信息：

歌曲名称：$trackName
艺术家：$artistNames
专辑：$albumName
发行日期：$releaseDate

请使用搜索功能查找准确的信息，并按照以下格式提供信息（如果某些信息无法找到，请写"无法获取"）：

请用$languageName回答，并严格按照以下格式输出：

[CREATION_TIME]
创作时间信息或无法获取
[/CREATION_TIME]

[CREATION_LOCATION]
创作地点信息或无法获取
[/CREATION_LOCATION]

[LYRICIST]
作词人信息或无法获取
[/LYRICIST]

[COMPOSER]
作曲人信息或无法获取
[/COMPOSER]

[PRODUCER]
制作人信息或无法获取
[/PRODUCER]

[REVIEW]
基于搜索到的信息，写一段的歌曲解析（包括歌曲背景和音乐赏析，2-4句话）
[/REVIEW]

对于音乐解析，语言风格要：
- 具有音乐评论的专业性和文艺性
- 有深度但不过于学术化
- 富有洞察力，能够揭示歌曲的深层含义和文化意义

请严格按照上述格式输出，每个字段都要包含对应的标签。
''';
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'en': return 'English';
      case 'zh-CN': return 'Simplified Chinese（简体中文）';
      case 'zh-TW': return 'Traditional Chinese（繁体中文）';
      case 'ja': return 'Japanese';
      default: return 'English';
    }
  }

  /// Ask a follow-up question about the track with context
  Future<String?> askFollowUp({
    required String question,
    required Map<String, dynamic> trackData,
    Map<String, dynamic>? songInfo,
  }) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    final trackName = trackData['name'] as String? ?? 'Unknown Track';
    final artistNames = (trackData['artists'] as List?)
        ?.map((artist) => artist['name'] as String)
        .join(', ') ?? 'Unknown Artist';
    final albumName = trackData['album']?['name'] as String? ?? 'Unknown Album';

    // Get user's preferred language
    final String languageCode = await _settingsService.getTargetLanguage();
    final String languageName = _getLanguageName(languageCode);

    // Build context from existing song info
    String contextInfo = '';
    if (songInfo != null) {
      if (songInfo['creation_time'] != null) contextInfo += '创作时间: ${songInfo['creation_time']}\n';
      if (songInfo['creation_location'] != null) contextInfo += '创作地点: ${songInfo['creation_location']}\n';
      if (songInfo['lyricist'] != null) contextInfo += '作词: ${songInfo['lyricist']}\n';
      if (songInfo['composer'] != null) contextInfo += '作曲: ${songInfo['composer']}\n';
      if (songInfo['producer'] != null) contextInfo += '制作人: ${songInfo['producer']}\n';
      if (songInfo['review'] != null) contextInfo += '歌曲解析: ${songInfo['review']}\n';
    }

    final prompt = '''
你是一个音乐专家助手。用户正在查看以下歌曲的信息，并有一个追问：

歌曲名称：$trackName
艺术家：$artistNames
专辑：$albumName

${contextInfo.isNotEmpty ? '已有的歌曲信息：\n$contextInfo' : ''}

用户的问题：$question

请使用搜索功能查找准确的信息来回答用户的问题。用$languageName回答，语言风格要：
- 简洁但有深度
- 具有音乐评论的专业性
- 富有洞察力

直接回答问题，不需要重复歌曲基本信息。
''';

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
        throw Exception('Follow-up request timed out.');
      });

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        final candidates = decodedResponse['candidates'];
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null &&
              content['parts'] != null &&
              content['parts'].isNotEmpty) {
            return content['parts'][0]['text'] as String?;
          }
        }
        return null;
      } else {
        String errorMessage = 'Follow-up failed (Code: ${response.statusCode}).';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error']?['message'] != null) {
            errorMessage += ' ${errorJson['error']['message']}';
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      logger.e('Error during follow-up API call: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _parseTaggedResponse(String rawText) {
    final result = <String, dynamic>{};
    
    // 定义标签映射
    final tags = {
      'CREATION_TIME': 'creation_time',
      'CREATION_LOCATION': 'creation_location',
      'LYRICIST': 'lyricist',
      'COMPOSER': 'composer',
      'PRODUCER': 'producer',
      'REVIEW': 'review',
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
        
        // 如果内容不是"无法获取"，则添加到结果中
        if (content.isNotEmpty && 
            content != '无法获取' && 
            content.toLowerCase() != 'null' &&
            content.toLowerCase() != 'n/a') {
          result[fieldName] = content;
        }
      }
    }
    
    return result;
  }
} 
