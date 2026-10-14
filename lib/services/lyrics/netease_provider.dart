import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'lyric_candidate_matcher.dart';
import 'lyric_provider.dart';

/// 基于第三方代理 API 的网易云歌词提供者。
///
/// 自动匹配（[search]）多要几条，交给 [LyricCandidateMatcher] 校验（与 Yoin 同一套规则）：
/// 标题必须对上，艺人能比就必须对上，原版优先于 Live / Remix，伴奏不算。认不出就返回
/// null 让下一个 provider 试——网易云的第一条常是翻唱、同名的别人，甚至标题都不对的歌。
/// 手动搜索（[searchMultiple]）保持网易云自己的排序。
class NetEaseProvider extends LyricProvider {
  /// 第三方代理服务基础 URL
  static const String _defaultBaseUrl = 'https://api.spotoolfy.gojyuplus.com';

  /// 自动匹配时一次要的候选数。
  static const int _searchPageSize = 10;

  final Logger _logger = Logger();
  final http.Client _client;
  final String _baseUrl;
  final LyricCandidateMatcher _matcher;

  NetEaseProvider({http.Client? httpClient, String? baseUrl, LyricCandidateMatcher? matcher})
      : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? _defaultBaseUrl,
        _matcher = matcher ?? LyricCandidateMatcher();

  @override
  String get name => 'netease';

  @override
  Future<SongMatch?> search(String title, String artist) async {
    final songs = await _findSongs(title, artist, _searchPageSize);
    if (songs == null) return null;
    final picked = _matcher.pick(
      songs.map((s) => LyricCandidate(s.title ?? '', s.artists, album: s.album)).toList(),
      title,
      artist,
    );
    return picked == null ? null : songs[picked].toMatch(title, artist);
  }

  @override
  Future<List<SongMatch>> searchMultiple(String title, String artist, {int limit = 3}) async {
    if (limit <= 0) return [];
    final songs = await _findSongs(title, artist, limit) ?? const <_NetEaseSong>[];
    return songs.take(limit).map((s) => s.toMatch(title, artist)).toList();
  }

  /// `cloudsearch`，按网易云的原序返回。null = 没答上（网络、非 2xx、解析失败）；
  /// 空列表是真实的"搜不到"。没有 id 的条目取不了词，直接跳过。
  Future<List<_NetEaseSong>?> _findSongs(String title, String artist, int pageSize) async {
    try {
      final uri = Uri.parse('$_baseUrl/cloudsearch').replace(
        queryParameters: {
          'keywords': '$title $artist',
          'limit': pageSize.toString(),
        },
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _logger.w('搜索请求失败: ${response.statusCode}');
        return null;
      }

      final data = json.decode(utf8.decode(response.bodyBytes, allowMalformed: true));
      final result = data is Map<String, dynamic> ? data['result'] : null;
      final songs = result is Map<String, dynamic> ? result['songs'] : null;
      if (songs is! List) return [];
      return songs.map(_parseSong).whereType<_NetEaseSong>().toList();
    } catch (e) {
      _logger.w('网易云搜索失败: $e');
      return null;
    }
  }

  _NetEaseSong? _parseSong(dynamic element) {
    if (element is! Map<String, dynamic>) return null;
    final id = element['id'];
    if (id == null) return null;
    final artists = <String>[];
    final ar = element['ar'];
    if (ar is List) {
      for (final artist in ar) {
        final name = artist is Map<String, dynamic> ? artist['name'] : null;
        if (name is String && name.trim().isNotEmpty) artists.add(name.trim());
      }
    }
    final al = element['al'];
    final album = al is Map<String, dynamic> ? al['name'] : null;
    final name = element['name'];
    return _NetEaseSong(
      id: id.toString(),
      title: name is String ? name : null,
      artists: artists,
      album: album is String && album.trim().isNotEmpty ? album.trim() : null,
    );
  }

  /// 获取歌词（只要原文）
  @override
  Future<String?> fetchLyric(String songId) async =>
      (await fetchLyricWithTranslation(songId))?.lyric;

  /// 获取歌词（包含翻译信息，使用新版 API）
  @override
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

      final data = json.decode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (data is! Map<String, dynamic>) return null;

      final lrcText = _providerLyric(data['lrc']);
      if (lrcText == null) return null;

      return LyricResult(
        lyric: lrcText,
        // 翻译与原文同样可能是逐字 JSON 行，一并转换。
        translation: _providerLyric(data['tlyric']),
      );
    } catch (e, st) {
      _logger.e('获取歌词失败', error: e, stackTrace: st);
      return null;
    }
  }

  /// `{lyric: "..."}` → LRC 文本；逐字 JSON 行转成标准 LRC；空的返回 null。
  String? _providerLyric(dynamic field) {
    final text = field is Map<String, dynamic> ? field['lyric'] : null;
    if (text is! String || text.trim().isEmpty) return null;
    final converted = text.trim().startsWith('{') ? _parseJsonLyric(text) : text;
    return converted == null || converted.trim().isEmpty ? null : converted;
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

/// 一条搜索结果。[title] 缺失时不拿请求的歌名顶替去比对——那样任何一条没名字的
/// 结果都会被当成"标题对上了"；只在交给界面时（[toMatch]）才回退。[album] 只给匹配器
/// 认现场 / 访谈专辑用。
class _NetEaseSong {
  final String id;
  final String? title;
  final List<String> artists;
  final String? album;

  _NetEaseSong({required this.id, required this.title, required this.artists, this.album});

  SongMatch toMatch(String fallbackTitle, String fallbackArtist) => SongMatch(
        songId: id,
        title: title ?? fallbackTitle,
        artist: artists.isNotEmpty ? artists.first : fallbackArtist,
      );
}
