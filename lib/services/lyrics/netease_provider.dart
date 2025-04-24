import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'lyric_provider.dart';

/// 基于社区 Node API 的网易云歌词提供者
class NetEaseProvider extends LyricProvider {
  /// 社区服务基础 URL
  static const String _baseUrl = 'https://neteasecloudmusicapi.vercel.app';

  final Logger _logger = Logger();

  @override
  String get name => 'netease';

  /// 搜索歌曲，返回首条匹配
  @override
  Future<SongMatch?> search(String title, String artist) async {
    try {
      final keyword = '$title $artist';
      final uri = Uri.parse('$_baseUrl/search').replace(
        queryParameters: {
          'keywords': keyword,
          'type': '1',  // 单曲
          'limit': '3',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.w('搜索请求失败: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      final songs = data['result']?['songs'] as List<dynamic>?;
      if (songs != null && songs.isNotEmpty) {
        final song = songs[0] as Map<String, dynamic>;
        final artists = song['artists'] as List<dynamic>?;
        final artistName = (artists != null && artists.isNotEmpty)
            ? artists[0]['name'] as String
            : artist;
        return SongMatch(
          songId: song['id'].toString(),
          title: song['name'] as String? ?? title,
          artist: artistName,
        );
      }
      return null;
    } catch (e, st) {
      _logger.e('搜索失败', error: e, stackTrace: st);
      return null;
    }
  }

  /// 获取歌词
  @override
  Future<String?> fetchLyric(String songId) async {
    try {
      final uri = Uri.parse('$_baseUrl/lyric').replace(
        queryParameters: {'id': songId},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.w('获取歌词失败: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final lrc = data['lrc'] as Map<String, dynamic>?;
      if (lrc != null && lrc['lyric'] != null) {
        return lrc['lyric'] as String;
      }
      return null;
    } catch (e, st) {
      _logger.e('获取歌词失败', error: e, stackTrace: st);
      return null;
    }
  }
}
