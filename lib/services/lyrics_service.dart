import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricsService {
  static const String _baseSearchUrl = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp';
  static const String _baseLyricUrl = 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  
  final Map<String, String> _headers = {
    'referer': 'https://y.qq.com/',
    'user-agent': 'Mozilla/5.0'
  };

  Future<String?> getLyrics(String songName, String artistName) async {
    try {
      // 1. 先搜索歌曲获取 songmid
      final songmid = await _searchSong(songName, artistName);
      if (songmid == null) return null;

      // 2. 用 songmid 获取歌词
      return await _fetchLyrics(songmid);
    } catch (e) {
      print('获取歌词失败: $e');
      return null;
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