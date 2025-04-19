import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'lyric_provider.dart';

/// QQ音乐歌词提供者
class QQProvider extends LyricProvider {
  static const String _baseSearchUrl = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp';
  static const String _baseLyricUrl = 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  static const String _backupLyricUrl = 'https://u6.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  
  final Logger _logger = Logger();
  bool _useBackupDomain = false;

  final Map<String, String> _headers = {
    'referer': 'https://y.qq.com/',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36'
  };

  @override
  String get name => 'qq';

  @override
  Future<SongMatch?> search(String title, String artist) async {
    try {
      final keyword = '$title $artist';
      final url = Uri.parse(_baseSearchUrl).replace(queryParameters: {
        'w': keyword,
        'p': '1',
        'n': '3',
        'format': 'json'
      });
      
      final response = await http.get(url, headers: _headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('搜索请求超时');
        },
      );

      if (response.statusCode != 200) {
        _logger.w('QQ音乐搜索请求失败，状态码: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      if (data['data']?['song']?['list']?.isNotEmpty) {
        final songData = data['data']['song']['list'][0];
        return SongMatch(
          songId: songData['songmid'],
          title: songData['songname'] ?? title,
          artist: songData['singer']?[0]?['name'] ?? artist,
        );
      }
      return null;
    } catch (e) {
      _logger.e('QQ音乐搜索歌曲失败: $e');
      if (e is SocketException) {
        _logger.e('网络连接错误: ${e.message}');
      } else if (e is TimeoutException) {
        _logger.w('请求超时: ${e.message}');
      }
      return null;
    }
  }

  @override
  Future<String?> fetchLyric(String songId) async {
    try {
      final baseUrl = _useBackupDomain ? _backupLyricUrl : _baseLyricUrl;
      final url = Uri.parse(baseUrl).replace(queryParameters: {
        'songmid': songId,
        'format': 'json',
        'nobase64': '1'
      });
      
      final response = await http.get(url, headers: _headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('获取歌词请求超时');
        },
      );

      // 如果遇到403或429，尝试切换到备用域名
      if (response.statusCode == 403 || response.statusCode == 429) {
        _logger.w('QQ音乐API限流或拒绝访问，尝试切换到备用域名');
        _useBackupDomain = !_useBackupDomain;
        return fetchLyric(songId); // 递归调用，使用新域名
      }

      if (response.statusCode != 200) {
        _logger.w('QQ音乐获取歌词请求失败，状态码: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      if (data['lyric'] != null) {
        return data['lyric'];
      }
      return null;
    } catch (e) {
      _logger.e('QQ音乐获取歌词详情失败: $e');
      if (e is SocketException) {
        _logger.e('网络连接错误: ${e.message}');
      } else if (e is TimeoutException) {
        _logger.w('请求超时: ${e.message}');
      }
      return null;
    }
  }
}
