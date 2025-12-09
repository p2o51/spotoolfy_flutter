import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'lyric_provider.dart';

/// LRCLIB 歌词提供者
class LRCLibProvider extends LyricProvider {
  static const String _baseUrl = 'https://lrclib.net';

  final Logger _logger = Logger();
  final http.Client _client;

  LRCLibProvider({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  @override
  String get name => 'lrclib';

  @override
  Future<SongMatch?> search(String title, String artist) async {
    final results = await searchMultiple(title, artist, limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  @override
  Future<List<SongMatch>> searchMultiple(String title, String artist, {int limit = 3}) async {
    final trimmedTitle = title.trim();
    final trimmedArtist = artist.trim();
    if (trimmedTitle.isEmpty && trimmedArtist.isEmpty) {
      return [];
    }

    try {
      final query = [trimmedTitle, trimmedArtist].where((part) => part.isNotEmpty).join(' ');
      final params = <String, String>{
        'q': query,
      };
      if (trimmedTitle.isNotEmpty) {
        params['track_name'] = trimmedTitle;
      }
      if (trimmedArtist.isNotEmpty) {
        params['artist_name'] = trimmedArtist;
      }

      final uri = Uri.parse('$_baseUrl/api/search').replace(queryParameters: params);
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.w('LRCLIB 搜索请求失败，状态码: ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body);
      if (data is! List) {
        _logger.w('LRCLIB 搜索响应格式异常');
        return [];
      }

      if (data.isEmpty) {
        return [];
      }

      final results = <SongMatch>[];
      for (var i = 0; i < data.length && i < limit; i++) {
        final item = data[i] as Map<String, dynamic>;
        final id = item['id'];
        if (id == null) continue;

        final trackName = (item['trackName'] as String?)?.trim();
        final artistName = (item['artistName'] as String?)?.trim();

        results.add(SongMatch(
          songId: id.toString(),
          title: trackName?.isNotEmpty == true ? trackName! : trimmedTitle,
          artist: artistName?.isNotEmpty == true ? artistName! : trimmedArtist,
        ));
      }
      return results;
    } catch (e, st) {
      _logger.e('LRCLIB 搜索失败', error: e, stackTrace: st);
      return [];
    }
  }

  @override
  Future<String?> fetchLyric(String songId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/get/$songId');
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.w('LRCLIB 获取歌词失败，状态码: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      if (data is! Map<String, dynamic>) {
        _logger.w('LRCLIB 获取歌词响应格式异常');
        return null;
      }

      final syncedLyrics = (data['syncedLyrics'] as String?)?.trim();
      if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
        return syncedLyrics;
      }

      final plainLyrics = (data['plainLyrics'] as String?)?.trim();
      if (plainLyrics != null && plainLyrics.isNotEmpty) {
        return plainLyrics;
      }

      return null;
    } catch (e, st) {
      _logger.e('LRCLIB 获取歌词失败', error: e, stackTrace: st);
      return null;
    }
  }
}
