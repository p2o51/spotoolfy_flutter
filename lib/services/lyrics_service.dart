import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LyricsService {
  static const String _baseSearchUrl = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp';
  static const String _baseLyricUrl = 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  
  final Map<String, String> _headers = {
    'referer': 'https://y.qq.com/',
    'user-agent': 'Mozilla/5.0'
  };

  // 缓存键的前缀
  static const String _cacheKeyPrefix = 'lyrics_cache_';

  Future<String?> getLyrics(String songName, String artistName) async {
    try {
      // 生成缓存键
      final cacheKey = _cacheKeyPrefix + _generateCacheKey(songName, artistName);
      
      // 尝试从缓存获取
      final prefs = await SharedPreferences.getInstance();
      final cachedLyrics = prefs.getString(cacheKey);
      
      if (cachedLyrics != null) {
        print('从缓存获取歌词: $songName - $artistName');
        return cachedLyrics;
      }

      // 如果缓存中没有，从网络获取
      print('从网络获取歌词: $songName - $artistName');
      
      // 1. 先搜索歌曲获取 songmid
      final songmid = await _searchSong(songName, artistName);
      if (songmid == null) return null;

      // 2. 用 songmid 获取歌词
      final lyrics = await _fetchLyrics(songmid);
      
      // 如果获取到歌词，保存到缓存
      if (lyrics != null) {
        await prefs.setString(cacheKey, lyrics);
        print('歌词已缓存: $songName - $artistName');
      }

      return lyrics;
    } catch (e) {
      print('获取歌词失败: $e');
      return null;
    }
  }

  // 生成缓存键
  String _generateCacheKey(String songName, String artistName) {
    // 移除特殊字符，并转换为小写
    final normalizedSong = songName.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final normalizedArtist = artistName.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    return '$normalizedSong-$normalizedArtist';
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
      print('歌词缓存已清除');
    } catch (e) {
      print('清除缓存失败: $e');
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
      print('获取缓存大小失败: $e');
      return 0;
    }
  }

  Future<String?> _searchSong(String songName, String artistName) async {
    try {
      final searchKeyword = Uri.encodeComponent('$songName $artistName');
      final url = '$_baseSearchUrl?w=$searchKeyword&p=1&n=1&format=json';
      
      final response = await http.get(Uri.parse(url), headers: _headers);
      final data = json.decode(response.body);

      if (data['data']?['song']?['list']?.isNotEmpty) {
        return data['data']['song']['list'][0]['songmid'];
      }
      return null;
    } catch (e) {
      print('搜索歌曲失败: $e');
      return null;
    }
  }

  Future<String?> _fetchLyrics(String songmid) async {
    try {
      final url = '$_baseLyricUrl?songmid=$songmid&format=json&nobase64=0';
      
      final response = await http.get(Uri.parse(url), headers: _headers);
      final data = json.decode(response.body);

      if (data['lyric'] != null) {
        final bytes = base64.decode(data['lyric']);
        return utf8.decode(bytes);
      }
      return null;
    } catch (e) {
      print('获取歌词详情失败: $e');
      return null;
    }
  }
}