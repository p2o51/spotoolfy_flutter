import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'lyric_provider.dart';

/// 基于第三方代理 API 的网易云歌词提供者
class NetEaseProvider extends LyricProvider {
  /// 第三方代理服务基础 URL
  static const String _baseUrl = 'https://163api.qijieya.cn';

  final Logger _logger = Logger();
  final http.Client _client;

  NetEaseProvider({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  @override
  String get name => 'netease';

  /// 搜索歌曲，返回首条匹配
  @override
  Future<SongMatch?> search(String title, String artist) async {
    final results = await searchMultiple(title, artist, limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  @override
  Future<List<SongMatch>> searchMultiple(String title, String artist, {int limit = 3}) async {
    try {
      final keyword = '$title $artist';
      final uri = Uri.parse('$_baseUrl/cloudsearch').replace(
        queryParameters: {
          'keywords': keyword,
          'limit': limit.toString(),
        },
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.w('搜索请求失败: ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body);
      final songs = data['result']?['songs'] as List<dynamic>?;
      if (songs == null || songs.isEmpty) {
        return [];
      }

      final results = <SongMatch>[];
      for (var i = 0; i < songs.length && i < limit; i++) {
        final song = songs[i] as Map<String, dynamic>;
        // cloudsearch 使用 'ar' 而不是 'artists'
        final artists = song['ar'] as List<dynamic>?;
        final artistName = (artists != null && artists.isNotEmpty)
            ? artists[0]['name'] as String
            : artist;
        results.add(SongMatch(
          songId: song['id'].toString(),
          title: song['name'] as String? ?? title,
          artist: artistName,
        ));
      }
      return results;
    } catch (e, st) {
      _logger.e('搜索失败', error: e, stackTrace: st);
      return [];
    }
  }

  /// 获取歌词（使用新版 API，支持翻译歌词）
  @override
  Future<String?> fetchLyric(String songId) async {
    try {
      final uri = Uri.parse('$_baseUrl/lyric/new').replace(
        queryParameters: {'id': songId},
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.w('获取歌词失败: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // 获取原文歌词
      final lrc = data['lrc'] as Map<String, dynamic>?;
      String? lrcText = lrc?['lyric'] as String?;

      if (lrcText == null || lrcText.isEmpty) {
        return null;
      }

      // 检查是否是 JSON 格式的逐字歌词（新版 API 特性）
      if (lrcText.trim().startsWith('{')) {
        lrcText = _parseJsonLyric(lrcText);
      }

      return lrcText;
    } catch (e, st) {
      _logger.e('获取歌词失败', error: e, stackTrace: st);
      return null;
    }
  }

  /// 获取歌词（包含翻译信息）
  Future<LyricResult?> fetchLyricWithTranslation(String songId) async {
    try {
      final uri = Uri.parse('$_baseUrl/lyric/new').replace(
        queryParameters: {'id': songId},
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.w('获取歌词失败: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // 获取原文歌词
      final lrc = data['lrc'] as Map<String, dynamic>?;
      String? lrcText = lrc?['lyric'] as String?;

      if (lrcText == null || lrcText.isEmpty) {
        return null;
      }

      // 检查是否是 JSON 格式的逐字歌词
      if (lrcText.trim().startsWith('{')) {
        lrcText = _parseJsonLyric(lrcText);
      }

      if (lrcText == null || lrcText.isEmpty) {
        return null;
      }

      // 获取翻译歌词
      final tlyric = data['tlyric'] as Map<String, dynamic>?;
      final tlyricText = tlyric?['lyric'] as String?;

      return LyricResult(
        lyric: lrcText,
        translation: tlyricText,
      );
    } catch (e, st) {
      _logger.e('获取歌词失败', error: e, stackTrace: st);
      return null;
    }
  }

  /// 解析 JSON 格式的逐字歌词，转换为标准 LRC 格式
  String? _parseJsonLyric(String jsonLyric) {
    try {
      final lines = jsonLyric.split('\n');
      final lrcLines = <String>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        if (!line.trim().startsWith('{')) {
          // 已经是 LRC 格式
          lrcLines.add(line);
          continue;
        }

        try {
          final json = jsonDecode(line.trim());
          final time = json['t'] as int? ?? 0;
          final parts = json['c'] as List<dynamic>?;

          if (parts != null) {
            final text = parts.map((p) => p['tx'] ?? '').join('');
            // 跳过元数据行（作词、作曲等）
            if (_isMetadataLine(text)) continue;

            final minutes = (time ~/ 60000).toString().padLeft(2, '0');
            final seconds = ((time % 60000) ~/ 1000).toString().padLeft(2, '0');
            final millis = ((time % 1000) ~/ 10).toString().padLeft(2, '0');
            lrcLines.add('[$minutes:$seconds.$millis]$text');
          }
        } catch (_) {
          // 解析失败，跳过这行
        }
      }

      return lrcLines.isNotEmpty ? lrcLines.join('\n') : null;
    } catch (e) {
      _logger.w('解析 JSON 歌词失败: $e');
      return null;
    }
  }

  /// 检查是否是元数据行（作词、作曲等）
  bool _isMetadataLine(String text) {
    final metadataKeywords = [
      '歌词贡献者', '翻译贡献者', '作词', '作曲', '编曲',
      '制作', '词曲', '词 / 曲', 'lyricist', 'composer',
      'arrange', 'translation', 'translator', 'producer',
    ];
    final lowerText = text.toLowerCase();
    return metadataKeywords.any((keyword) =>
      lowerText.startsWith(keyword.toLowerCase()) ||
      lowerText.contains(':$keyword') ||
      lowerText.contains('：$keyword')
    );
  }
}
