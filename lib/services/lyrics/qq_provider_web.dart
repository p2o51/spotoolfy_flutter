import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'lyric_provider.dart';
import 'qq_encoding.dart';

/// Web-specific QQ歌词提供者，所有请求都通过 Cloudflare Worker 代理。
class QQProvider extends LyricProvider {
  static const String _defaultWorkerBaseUrl = 'https://lyrics.gojyuplus.com';
  static const Duration _requestTimeout = Duration(seconds: 12);
  final Logger _logger = Logger();
  final http.Client _client;
  final String _workerBaseUrl;
  final String? _authSecret;

  QQProvider({
    http.Client? httpClient,
    String? workerBaseUrl,
    String? authSecret,
  })  : _client = httpClient ?? http.Client(),
        _workerBaseUrl = workerBaseUrl ?? _defaultWorkerBaseUrl,
        _authSecret = authSecret;

  Map<String, String> get _jsonHeaders {
    final headers = <String, String>{
      'content-type': 'application/json',
    };

    final secret = _authSecret;
    if (secret != null && secret.isNotEmpty) {
      headers['authorization'] = 'Bearer $secret';
    }

    return headers;
  }

  Uri _endpoint(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_workerBaseUrl$normalizedPath');
  }

  Future<Map<String, dynamic>?> _postJson(
    String path,
    Map<String, dynamic> payload, {
    bool treatNotFoundAsNull = true,
  }) async {
    try {
      final response = await _client
          .post(
            _endpoint(path),
            headers: _jsonHeaders,
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(response.body) as Map<String, dynamic>;
      }

      if (response.statusCode == 404 && treatNotFoundAsNull) {
        _logger.i('Worker未找到资源: $path');
        return null;
      }

      _logger.w(
        'Worker接口调用失败($path)，状态码: ${response.statusCode}, 响应: ${response.body}',
      );
    } on TimeoutException catch (e) {
      _logger.w('Worker请求超时: $e');
    } catch (e) {
      _logger.e('调用Worker失败: $e');
    }
    return null;
  }

  @override
  String get name => 'qq';

  @override
  Future<SongMatch?> search(String title, String artist) async {
    final result = await _postJson('/qq/search', {
      'title': title,
      'artist': artist,
      'limit': 3,
    });

    if (result == null) {
      return null;
    }

    final matches = result['matches'];
    if (matches is List && matches.isNotEmpty) {
      final dynamic firstMatch = matches.first;
      final Map<String, dynamic>? match =
          firstMatch is Map ? Map<String, dynamic>.from(firstMatch) : null;
      if (match == null) {
        return null;
      }

      final songId = match['songId'] as String?;
      if (songId == null || songId.isEmpty) {
        return null;
      }
      return SongMatch(
        songId: songId,
        title: _normalizeTextField(match['title'] as String?, title),
        artist: _normalizeTextField(match['artist'] as String?, artist),
      );
    }
    return null;
  }

  @override
  Future<String?> fetchLyric(String songId) async {
    final result = await _postJson(
      '/qq/lyrics',
      {
        'songId': songId,
        'includeTranslation': true,
        'includeRomanized': true,
      },
    );

    return _extractLyric(result);
  }

  @override
  Future<String?> getLyric(String title, String artist) async {
    final payload = await _postJson(
      '/qq/resolveLyric',
      {
        'title': title,
        'artist': artist,
        'includeTranslation': true,
        'includeRomanized': true,
      },
      treatNotFoundAsNull: false,
    );

    final lyric = _extractLyric(payload);
    if (lyric != null && lyric.trim().isNotEmpty) {
      return normalizeLyric(lyric);
    }

    // 如果组合接口失败，回退到搜索 + 单独获取的流程
    return await super.getLyric(title, artist);
  }

  String? _extractLyric(Map<String, dynamic>? payload) {
    if (payload == null) {
      return null;
    }

    final direct = payload['lyric'];
    if (direct is String && direct.trim().isNotEmpty) {
      return QQEncoding.normalize(direct);
    }

    final raw = payload['raw'];
    if (raw is Map<String, dynamic>) {
      final decoded = _decodeBase64Lyric(raw['lyric']);
      if (decoded != null && decoded.trim().isNotEmpty) {
        return decoded;
      }
    }

    return null;
  }

  String? _decodeBase64Lyric(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    try {
      final sanitized = value.replaceAll(RegExp(r'\s'), '');
      final bytes = base64.decode(sanitized);
      final decoded = utf8.decode(bytes);
      return QQEncoding.normalize(decoded);
    } catch (_) {
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
