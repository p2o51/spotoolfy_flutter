import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'lyric_provider.dart';
import 'qq_encoding.dart';

/// QQ音乐歌词提供者
class QQProvider extends LyricProvider {
  static const String _baseSearchUrl =
      'https://c.y.qq.com/soso/fcgi-bin/client_search_cp';
  static const String _baseLyricUrl =
      'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  static const String _backupLyricUrl =
      'https://u6.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';

  final Logger _logger = Logger();
  bool _useBackupDomain = false;
  final http.Client _client;

  final Map<String, String> _headers = {
    'referer': 'https://y.qq.com/',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36'
  };

  QQProvider({http.Client? httpClient}) : _client = httpClient ?? http.Client();

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

      final response = await _client.get(url, headers: _headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('搜索请求超时');
        },
      );

      if (response.statusCode != 200) {
        _logger.w('QQ音乐搜索请求失败，状态码: ${response.statusCode}');
        return null;
      }

      final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      final data = json.decode(decodedBody);
      final songList = data['data']?['song']?['list'];
      if (songList is List && songList.isNotEmpty) {
        final dynamic songData = songList.first;
        if (songData is! Map<String, dynamic>) {
          return null;
        }

        String? primaryArtist;
        final singers = songData['singer'];
        if (singers is List && singers.isNotEmpty) {
          final dynamic firstSinger = singers.first;
          if (firstSinger is Map<String, dynamic>) {
            primaryArtist = firstSinger['name'] as String?;
          } else if (firstSinger is String) {
            primaryArtist = firstSinger;
          }
        }

        return SongMatch(
          songId: songData['songmid'] as String,
          title: _normalizeTextField(songData['songname'] as String?, title),
          artist: _normalizeTextField(primaryArtist, artist),
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
    final payload = await fetchLyricPayload(songId);
    return payload?.lyric;
  }

  /// Fetches the raw QQ lyric payload with additional metadata such as
  /// translated or romanized lyrics. This is primarily used for debugging
  /// scenarios where QQ only exposes plain text lyrics without timestamps.
  Future<QQLyricPayload?> fetchLyricPayload(String songId) async {
    final baseUrl = _useBackupDomain ? _backupLyricUrl : _baseLyricUrl;
    final url = Uri.parse(baseUrl).replace(queryParameters: {
      'songmid': songId,
      'format': 'json',
      'nobase64': '1'
    });

    http.Response response;
    try {
      response = await _client.get(url, headers: _headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('获取歌词请求超时');
        },
      );
    } catch (e) {
      _logger.e('QQ音乐获取歌词详情失败: $e');
      if (e is SocketException) {
        _logger.e('网络连接错误: ${e.message}');
      } else if (e is TimeoutException) {
        _logger.w('请求超时: ${e.message}');
      }
      return null;
    }

    // 如果遇到403或429，尝试切换到备用域名
    if (response.statusCode == 403 || response.statusCode == 429) {
      _logger.w('QQ音乐API限流或拒绝访问，尝试切换到备用域名');
      _useBackupDomain = !_useBackupDomain;
      return fetchLyricPayload(songId); // 递归调用，使用新域名
    }

    if (response.statusCode != 200) {
      _logger.w('QQ音乐获取歌词请求失败，状态码: ${response.statusCode}');
      return null;
    }

    try {
      final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      final data = json.decode(decodedBody) as Map<String, dynamic>;
      return QQLyricPayload.fromJson(data);
    } catch (e) {
      _logger.e('解析QQ音乐歌词响应失败: $e');
      return null;
    }
  }

  String _normalizeTextField(String? value, String fallback) {
    final trimmed = (value ?? fallback).trim();
    if (trimmed.isEmpty) {
      return fallback;
    }
    return QQEncoding.normalize(trimmed);
  }
}

/// Represents the QQ lyric payload and exposes the primary, translated, and
/// romanized lyrics that may be returned by the API.
class QQLyricPayload {
  final Map<String, dynamic> raw;
  final String? lyric;
  final String? translatedLyric;
  final String? romanizedLyric;

  const QQLyricPayload._({
    required this.raw,
    required this.lyric,
    required this.translatedLyric,
    required this.romanizedLyric,
  });

  factory QQLyricPayload.fromJson(Map<String, dynamic> json) {
    String? romanized;
    final klyric = json['klyric'];
    if (klyric is Map<String, dynamic>) {
      romanized = klyric['lyric'] as String?;
    } else if (klyric is String) {
      romanized = klyric;
    }

    return QQLyricPayload._(
      raw: json,
      lyric: QQEncoding.normalizeNullable(json['lyric'] as String?),
      translatedLyric: QQEncoding.normalizeNullable(json['trans'] as String?),
      romanizedLyric: QQEncoding.normalizeNullable(romanized),
    );
  }

  bool get hasAnyContent {
    return (lyric != null && lyric!.trim().isNotEmpty) ||
        (translatedLyric != null && translatedLyric!.trim().isNotEmpty) ||
        (romanizedLyric != null && romanizedLyric!.trim().isNotEmpty);
  }
}
