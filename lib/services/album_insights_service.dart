import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_service.dart';

class AlbumInsightsService {
  AlbumInsightsService();

  final SettingsService _settingsService = SettingsService();
  final Logger _logger = Logger();

  static const String _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/';
  static const String _geminiModel = 'gemini-flash-latest';
  static const String _cacheKeyPrefix = 'album_insights_';

  SharedPreferences? _prefsCache;

  Future<Map<String, dynamic>?> getCachedAlbumInsights({
    required String albumId,
    required String ratingsSignature,
  }) async {
    try {
      final prefs = await _getPrefs();
      final cachedJson = prefs.getString('$_cacheKeyPrefix$albumId');
      if (cachedJson == null || cachedJson.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(cachedJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final currentLanguage = await _settingsService.getTargetLanguage();
      if (decoded['languageCode'] != currentLanguage) {
        _logger.d('Cached album insights language mismatch, ignoring cache.');
        return null;
      }

      if (decoded['ratingsSignature'] != ratingsSignature) {
        _logger.d(
            'Cached album insights ratings signature mismatch, ignoring cache.');
        return null;
      }

      return decoded;
    } catch (e) {
      _logger.e('Error retrieving cached album insights: $e');
      return null;
    }
  }

  Future<void> clearCachedAlbumInsights(String albumId) async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove('$_cacheKeyPrefix$albumId');
      _logger.d('Cleared cached album insights for $albumId');
    } catch (e) {
      _logger.e('Error clearing cached album insights: $e');
    }
  }

  Future<Map<String, dynamic>> generateAlbumInsights({
    required String albumId,
    required Map<String, dynamic> albumData,
    required List<Map<String, dynamic>> tracks,
    required Map<String, int?> trackRatings,
    required double? averageScore,
    required int ratedTrackCount,
    required String ratingsSignature,
  }) async {
    final apiKey = await _settingsService.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not configured.');
    }

    final languageCode = await _settingsService.getTargetLanguage();
    final languageName = _getLanguageName(languageCode);
    final enableThinking =
        await _settingsService.getEnableThinkingForInsights();

    final albumName = albumData['name'] as String? ?? 'Unknown Album';
    final artists = _formatArtists(albumData['artists']);
    final releaseDate = albumData['release_date'] as String? ?? 'Unknown';

    final ratedCountText = ratedTrackCount > 0 ? '$ratedTrackCount' : '0';
    final averageScoreText =
        averageScore != null ? averageScore.toStringAsFixed(1) : '无可用平均分';
    final topTracks = _selectHighRatedTracks(tracks, trackRatings);

    final prompt = _buildPrompt(
      languageName: languageName,
      albumName: albumName,
      artists: artists,
      releaseDate: releaseDate,
      averageScoreText: averageScoreText,
      ratedCountText: ratedCountText,
      topTracks: topTracks,
    );

    final modelUrl = '$_geminiBaseUrl$_geminiModel';
    final url = Uri.parse('$modelUrl:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};

    final thinkingBudget = enableThinking ? 8 : 0;
    final generationConfig = <String, dynamic>{
      'temperature': 0.85,
      'thinkingConfig': {
        'thinkingBudget': thinkingBudget,
      },
    };

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text': prompt,
            }
          ],
        }
      ],
      'tools': [
        {
          'googleSearch': {},
        }
      ],
      'generationConfig': generationConfig,
    });

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 45), onTimeout: () {
        throw Exception('Album insights generation request timed out.');
      });

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        final candidates = decodedResponse['candidates'];
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No candidates returned from Gemini.');
        }

        final content = candidates[0]['content'];
        if (content == null ||
            content['parts'] == null ||
            content['parts'].isEmpty) {
          throw Exception('Missing content parts in Gemini response.');
        }

        String rawText = content['parts'][0]['text'] as String? ?? '';
        rawText =
            rawText.replaceAll('```json', '').replaceAll('```', '').trim();

        _logger.d('Raw album insights response: $rawText');

        final parsedInsights = jsonDecode(rawText);
        if (parsedInsights is! Map<String, dynamic>) {
          throw Exception('Unexpected insights format.');
        }

        final title = parsedInsights['title'];
        if (title is! String || title.trim().isEmpty) {
          throw Exception('Insights response missing title.');
        }

        final summary = parsedInsights['summary'];
        if (summary is! String || summary.trim().isEmpty) {
          throw Exception('Insights response missing summary text.');
        }

        final result = <String, dynamic>{
          'albumId': albumId,
          'languageCode': languageCode,
          'ratingsSignature': ratingsSignature,
          'generatedAt': DateTime.now().toIso8601String(),
          'insights': parsedInsights,
        };

        await _saveAlbumInsightsToCache(albumId, result);
        return result;
      } else {
        String errorMessage =
            'Album insights generation failed (Code: ${response.statusCode}).';
        try {
          final errorJson = jsonDecode(response.body);
          final errorDetail = errorJson['error']?['message'];
          if (errorDetail is String && errorDetail.isNotEmpty) {
            errorMessage += ' Details: $errorDetail';
          }
        } catch (_) {
          // Ignore parsing errors
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      _logger.e('Error during album insights API call: $e');
      rethrow;
    }
  }

  Future<void> _saveAlbumInsightsToCache(
    String albumId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString('$_cacheKeyPrefix$albumId', jsonEncode(payload));
      _logger.d('Album insights saved to cache for $albumId');
    } catch (e) {
      _logger.e('Error saving album insights to cache: $e');
    }
  }

  String _buildPrompt({
    required String languageName,
    required String albumName,
    required String artists,
    required String releaseDate,
    required String averageScoreText,
    required String ratedCountText,
    required List<String> topTracks,
  }) {
    final topTrackText = topTracks.isEmpty ? '暂无明显高分曲目' : topTracks.join('\n');

    return '''
你是一位以 $languageName 撰写的乐评人，需要结合互联网的公开资料和听众评分写一小段专辑速记。

专辑信息：
- 名称：$albumName
- 艺术家：$artists
- 发行：$releaseDate

听众评分提示：
- 专辑总体得分：$averageScoreText / 10
- 标记过的曲目数量：$ratedCountText
- 听众认为得分高于 6 的曲目：
$topTrackText

请搜索并提供专辑的背景信息（创作历程、地点、创作者名单等）再输出一段短评，语气保持克制、富有画面感，并体现听众偏好对专辑的共鸣。

请先给出一个 10 字以下的标题，像给乐评加的副标题那样，贴合专辑与听众偏好并具有独立乐评的创意（不能太油腻）。

以 JSON 返回，格式如下：
{
  "title": "短标题",
  "summary": "段落"
}
''';
  }

  List<String> _selectHighRatedTracks(
    List<Map<String, dynamic>> tracks,
    Map<String, int?> trackRatings,
  ) {
    final selected = <String>[];
    for (final track in tracks) {
      final id = track['id'] as String?;
      if (id == null) continue;
      final rating = trackRatings[id];
      final convertedScore = rating != null ? _mapRatingToScore(rating) : null;
      if (convertedScore != null && convertedScore > 6) {
        final name = track['name'] as String? ?? '未知曲目';
        final trackNumber = track['track_number'] as int?;
        final descriptor = _describeRating(rating);
        final prefix = trackNumber != null ? '#$trackNumber' : '-';
        selected.add('$prefix $name · $descriptor');
      }
    }
    return selected.take(5).toList();
  }

  double _mapRatingToScore(int rating) {
    switch (rating) {
      case 0:
        return 1;
      case 5:
        return 10;
      case 3:
      default:
        return 5;
    }
  }

  String _describeRating(int? rating) {
    switch (rating) {
      case 5:
        return '非常喜欢，反复想听';
      case 3:
        return '态度中立，偶尔合适';
      case 0:
        return '不太喜欢，可能会跳过';
      default:
        return '尚未标记偏好';
    }
  }

  String _formatArtists(dynamic artists) {
    if (artists is List) {
      final names = <String>[];
      for (final artist in artists) {
        if (artist is Map<String, dynamic>) {
          final name = artist['name'] as String?;
          if (name != null) {
            names.add(name);
          }
        }
      }
      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }
    return 'Unknown artist';
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'zh-CN':
        return '简体中文';
      case 'zh-TW':
        return '繁體中文';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      case 'es':
        return 'Español';
      case 'en':
      default:
        return 'English';
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
}
