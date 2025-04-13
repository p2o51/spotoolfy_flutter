import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LyricsService {
  static const String _baseSearchUrl = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp';
  static const String _baseLyricUrl = 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  
  final Logger _logger = Logger(); // Initialize logger

  final Map<String, String> _headers = {
    'referer': 'https://y.qq.com/',
    'user-agent': 'Mozilla/5.0'
  };

  // 缓存键的前缀
  static const String _cacheKeyPrefix = 'lyrics_cache_';

  Future<String?> getLyrics(String songName, String artistName, String trackId) async {
    try {
      // 使用 trackId 作为缓存键
      final cacheKey = _cacheKeyPrefix + trackId;
      
      // 尝试从缓存获取
      final prefs = await SharedPreferences.getInstance();
      final cachedLyrics = prefs.getString(cacheKey);
      
      if (cachedLyrics != null) {
        _logger.i('从缓存获取歌词: $trackId'); // Use logger.i for info
        return cachedLyrics;
      }

      // 如果缓存中没有，从网络获取
      _logger.i('从网络获取歌词: $songName - $artistName'); // Use logger.i for info
      
      final songmid = await _searchSong('$songName $artistName');
      if (songmid == null) return null;

      final lyrics = await _fetchLyrics(songmid);
      
      // 使用 trackId 存储缓存
      if (lyrics != null) {
        await prefs.setString(cacheKey, lyrics);
        _logger.i('歌词已缓存: $trackId'); // Use logger.i for info
      }

      return lyrics;
    } catch (e) {
      _logger.e('获取歌词失败: $e'); // Use logger.e for errors
      return null;
    }
  }

  Future<String?> _searchSong(String keyword) async {
    try {
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
        _logger.w('搜索请求失败，状态码: ${response.statusCode}'); // Use logger.w for warnings
        return null;
      }

      final data = json.decode(response.body);
      if (data['data']?['song']?['list']?.isNotEmpty) {
        return data['data']['song']['list'][0]['songmid'];
      }
      return null;
    } catch (e) {
      _logger.e('搜索歌曲失败: $e'); // Use logger.e for errors
      if (e is SocketException) {
        _logger.e('网络连接错误: ${e.message}'); // Use logger.e for errors
      } else if (e is TimeoutException) {
        _logger.w('请求超时: ${e.message}'); // Use logger.w for warnings
      }
      return null;
    }
  }

  Future<String?> _fetchLyrics(String songmid) async {
    try {
      final url = Uri.parse(_baseLyricUrl).replace(queryParameters: {
        'songmid': songmid,
        'format': 'json',
        'nobase64': '1'
      });
      
      final response = await http.get(url, headers: _headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('获取歌词请求超时');
        },
      );

      if (response.statusCode != 200) {
        _logger.w('获取歌词请求失败，状态码: ${response.statusCode}'); // Use logger.w for warnings
        return null;
      }

      final data = json.decode(response.body);
      if (data['lyric'] != null) {
        return data['lyric'];
      }
      return null;
    } catch (e) {
      _logger.e('获取歌词详情失败: $e'); // Use logger.e for errors
      if (e is SocketException) {
        _logger.e('网络连接错误: ${e.message}'); // Use logger.e for errors
      } else if (e is TimeoutException) {
        _logger.w('请求超时: ${e.message}'); // Use logger.w for warnings
      }
      return null;
    }
  }

  // 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // 只清除歌词缓存的键
      for (var key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          await prefs.remove(key);
        }
      }
      _logger.i('歌词缓存已清除'); // Use logger.i for info
    } catch (e) {
      _logger.e('清除缓存失败: $e'); // Use logger.e for errors
    }
  }

  // 获取缓存大小
  Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int totalSize = 0;
      
      for (var key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          final value = prefs.getString(key);
          if (value != null) {
            totalSize += value.length;
          }
        }
      }
      
      return totalSize;
    } catch (e) {
      _logger.e('获取缓存大小失败: $e'); // Use logger.e for errors
      return 0;
    }
  }
}