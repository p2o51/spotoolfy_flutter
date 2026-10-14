import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'lyric_candidate_matcher.dart';
import 'lyric_provider.dart';
import 'qq_encoding.dart';

/// QQ 音乐歌词源，免登录。与 Yoin 的 `QQLyricsProvider`（2026-10）同步：两组主机、三类接口。
///
/// - **Web 主机**（`c.y.qq.com` 一族）：`client_search_cp` 搜歌；`fcg_play_single_song`
///   把数字 songid 换成 songmid；`fcg_query_lyric_new` 按 songmid 取 LRC（必须带
///   `Referer: https://y.qq.com/`，只有原文没有翻译）。
/// - **网关主机**（`u.y.qq.com` 一族）：`musicu.fcg` 上的 `DoSearchForQQMusicDesktop`
///   搜歌兜底；`GetPlayLyricInfo` 按数字 songID 取 base64 LRC 和翻译，是取词主路。
///
/// 对外的 song id 一律是数字 songid（十进制字符串）。取词先走网关；网关全挂、被拒或
/// 只给密文时，用搜索时记下的 mid（没有就现查）走 Web 旧接口。每组主机记住上次答复的
/// 那台，下次先问它。所有接口的 Content-Type 都不可信，统一按文本解析 JSON（Web 旧接口
/// 可能包一层 JSONP）。
///
/// 自动匹配（[search]）交给 [LyricCandidateMatcher] 校验，宁可 null 让下一个 provider
/// 试，也不拿同名别人的歌；手动搜索（[searchMultiple]）保持平台原序。
class QQProvider extends LyricProvider {
  QQProvider({
    http.Client? httpClient,
    List<String>? webBaseUrls,
    List<String>? gatewayBaseUrls,
    LyricCandidateMatcher? matcher,
  })  : _client = httpClient ?? http.Client(),
        _webHosts = _HostRotation(webBaseUrls ?? _defaultWebBaseUrls),
        _gatewayHosts = _HostRotation(gatewayBaseUrls ?? _defaultGatewayBaseUrls),
        _matcher = matcher ?? LyricCandidateMatcher();

  final http.Client _client;
  final _HostRotation _webHosts;
  final _HostRotation _gatewayHosts;
  final LyricCandidateMatcher _matcher;
  final _SongMidMemory _midsById = _SongMidMemory(_midMemoryCapacity);
  final Logger _logger = Logger();

  @override
  String get name => 'qq';

  @override
  Future<SongMatch?> search(String title, String artist) async {
    final songs = await _findSongs(title, artist, _searchPageSize);
    if (songs == null) return null;
    final picked = _matcher.pick(
      songs.map((s) => LyricCandidate(s.title, s.artists, album: s.album)).toList(),
      title,
      artist,
    );
    return picked == null ? null : songs[picked].toMatch();
  }

  /// 手动搜索：平台原序。所有主机都没答上时抛出异常，让搜索页显示"不可用"而不是"搜不到"。
  @override
  Future<List<SongMatch>> searchMultiple(String title, String artist,
      {int limit = 3}) async {
    if (limit <= 0) return [];
    final songs = await _findSongs(title, artist, limit);
    if (songs == null) throw Exception(_unavailableMessage);
    return songs.take(limit).map((s) => s.toMatch()).toList();
  }

  /// 只认正整数 songid；旧版用的 songmid（字母数字混排）一律拒绝。
  bool canFetch(String songId) =>
      RegExp(r'^\d+$').hasMatch(songId) && (int.tryParse(songId) ?? 0) > 0;

  @override
  Future<String?> fetchLyric(String songId) async =>
      (await _fetchPayload(songId))?.lyric;

  @override
  Future<LyricResult?> fetchLyricWithTranslation(String songId) =>
      _fetchPayload(songId);

  /// 调试用（`tool/qq_lyric_probe.dart`）：原文和清理后的翻译。
  Future<QQLyricPayload?> fetchLyricPayload(String songId) async {
    final payload = await _fetchPayload(songId);
    if (payload == null) return null;
    return QQLyricPayload(lyric: payload.lyric, translatedLyric: payload.translation);
  }

  // ── 搜索 ─────────────────────────────────────────────────────────────────

  /// null = 所有主机都没答上；空列表是真实的"搜不到"，不再换路。
  Future<List<_QQSong>?> _findSongs(String title, String artist, int pageSize) async {
    final query = [title, artist]
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (query.isEmpty) return [];
    final songs = await _webHosts.firstAnswer((base) => _searchOnWeb(base, query, pageSize)) ??
        await _gatewayHosts.firstAnswer((base) => _searchOnGateway(base, query, pageSize));
    if (songs == null) return null;
    for (final song in songs.value) {
      _midsById.remember(song.id, song.mid);
    }
    return songs.value;
  }

  Future<_Answer<List<_QQSong>>?> _searchOnWeb(String base, String query, int pageSize) async {
    final url = Uri.parse('$base$_webSearchPath').replace(queryParameters: {
      'w': query,
      'format': 'json',
      'n': pageSize.toString(),
      'p': '1',
      't': '0',
      'cr': '1',
      'new_json': '1',
    });
    final root = await _fetchJson(() => _client.get(url, headers: _webHeaders), 'search');
    if (root == null || !_codeIsZero(root)) return null;
    final list = _obj(_obj(root['data'])?['song'])?['list'];
    if (list is! List) return null;
    return _Answer(_parseSongs(list));
  }

  Future<_Answer<List<_QQSong>>?> _searchOnGateway(String base, String query, int pageSize) async {
    final body = _gatewayBody(_searchModule, _searchMethod, {
      'query': query,
      'search_type': 0,
      'num_per_page': pageSize,
      'page_num': 1,
    });
    final data = await _callGateway(base, body, 'gateway search');
    if (data == null) return null;
    final list = _obj(_obj(data['body'])?['song'])?['list'];
    if (list is! List) return null;
    return _Answer(_parseSongs(list));
  }

  /// 没有数字 id 的条目取不了词，直接跳过。
  List<_QQSong> _parseSongs(List<dynamic> list) {
    final songs = <_QQSong>[];
    for (final element in list) {
      final item = _obj(element);
      if (item == null) continue;
      final id = int.tryParse(_string(item['id']) ?? '');
      if (id == null || id <= 0) continue;
      final title = _nonBlank(_string(item['title'])) ?? _nonBlank(_string(item['name']));
      if (title == null) continue;
      final artists = <String>[];
      final singers = item['singer'];
      if (singers is List) {
        for (final singer in singers) {
          final name = _nonBlank(_string(_obj(singer)?['name']))?.trim();
          if (name != null) artists.add(QQEncoding.normalize(name));
        }
      }
      final album = [
        _string(_obj(item['album'])?['name']),
        _string(_obj(item['album'])?['title']),
        _string(item['albumname']),
      ].map(_nonBlank).whereType<String>().firstOrNull;
      songs.add(_QQSong(
        id: id,
        mid: _string(item['mid'])?.trim(),
        title: QQEncoding.normalize(title.trim()),
        artists: artists,
        album: album == null ? null : QQEncoding.normalize(album.trim()),
      ));
    }
    return songs;
  }

  // ── 取词 ─────────────────────────────────────────────────────────────────

  Future<LyricResult?> _fetchPayload(String songId) async {
    if (!canFetch(songId)) return null;
    final id = int.parse(songId);
    final gatewayReply =
        (await _gatewayHosts.firstAnswer((base) => _lyricFromGateway(base, id)))?.value;
    final LyricResult? payload;
    if (gatewayReply is _GatewayFound) {
      payload = gatewayReply.payload;
    } else if (gatewayReply is _GatewayMissing) {
      // 网关明确说没词：不再查 Web，同一首歌那边也没有。
      return null;
    } else {
      payload = await _lyricFromWeb(id);
    }
    if (payload == null || _isInstrumentalPlaceholder(payload.lyric)) return null;
    return payload;
  }

  Future<_Answer<_GatewayLyric>?> _lyricFromGateway(String base, int songId) async {
    final body = _gatewayBody(_lyricModule, _lyricMethod, {
      'songID': songId,
      'format': 'json',
      'crypt': 0,
      'qrc': 0,
      'roma': 0,
      'trans': 1,
    });
    final data = await _callGateway(base, body, 'lyric');
    if (data == null) return null;
    if (!data.containsKey('lyric')) return null;
    final lyricField = data['lyric'];
    if (lyricField != null && lyricField is! String && lyricField is! num) return null;
    final lyric = _decodeLyricField(lyricField?.toString());
    return switch (lyric) {
      _FieldEmpty() => const _Answer(_GatewayMissing()),
      // 只有逐字 QRC 的歌会无视 crypt:0 回密文；另一台网关是同一个后端，直接走 Web。
      _FieldUnreadable() => const _Answer(_GatewayEncrypted()),
      _FieldText(:final value) => _Answer(_GatewayFound(LyricResult(
          lyric: value,
          translation: _cleanTranslation(_string(data['trans'])),
        ))),
    };
  }

  Future<LyricResult?> _lyricFromWeb(int songId) async {
    final mid = _midsById.recall(songId) ??
        (await _webHosts.firstAnswer((base) => _resolveMid(base, songId)))?.value;
    if (mid == null) return null;
    final lyric = (await _webHosts.firstAnswer((base) => _legacyLyric(base, mid)))?.value;
    return lyric == null ? null : LyricResult(lyric: lyric);
  }

  /// songid → songmid。查不到（含答非所问）是权威的 null。
  Future<_Answer<String?>?> _resolveMid(String base, int songId) async {
    final url = Uri.parse('$base$_songDetailPath').replace(queryParameters: {
      'songid': songId.toString(),
      'format': 'json',
    });
    final root = await _fetchJson(() => _client.get(url, headers: _webHeaders), 'song detail');
    if (root == null || !_codeIsZero(root)) return null;
    final songs = root['data'];
    if (songs is! List) return null;
    // 某些 id（比如 1）会回一首不相干的歌，只信 id 对得上的那条。
    final first = songs.isEmpty ? null : _obj(songs.first);
    final mid = first != null && int.tryParse(_string(first['id']) ?? '') == songId
        ? _nonBlank(_string(first['mid'])?.trim())
        : null;
    _midsById.remember(songId, mid);
    return _Answer(mid);
  }

  /// 按 songmid 取原文。`-1901` = 这首歌没词（权威）；其余非零码换下一台主机。
  Future<_Answer<String?>?> _legacyLyric(String base, String mid) async {
    final url = Uri.parse('$base$_legacyLyricPath').replace(queryParameters: {
      'songmid': mid,
      'format': 'json',
      'nobase64': '1',
    });
    final root = await _fetchJson(() => _client.get(url, headers: _webHeaders), 'legacy lyric');
    if (root == null) return null;
    final retcode = _asInt(root['retcode'] ?? root['code']);
    if (retcode == 0) {
      return switch (_decodeLyricField(_string(root['lyric']))) {
        _FieldEmpty() => const _Answer(null),
        _FieldUnreadable() => null,
        _FieldText(:final value) => _Answer(value),
      };
    }
    if (retcode == _noLyricRetcode) return const _Answer(null);
    _logger.w('QQ legacy lyric refused: $retcode');
    return null;
  }

  // ── 载荷解码 ─────────────────────────────────────────────────────────────

  /// `lyric` / `trans` 字段有三种形态：明文 LRC（以 `[` 开头）、base64 LRC、十六进制密文。
  /// 十六进制字符同时也是合法 base64，所以必须先判密文再试 base64。
  _LyricField _decodeLyricField(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return const _FieldEmpty();
    if (trimmed.startsWith('[')) {
      return _FieldText(QQEncoding.normalize(trimmed));
    }
    final compact = trimmed.replaceAll(RegExp(r'\s'), '');
    if (compact.length.isEven && _hexText.hasMatch(compact)) {
      return const _FieldUnreadable();
    }
    final decoded = _decodeBase64Utf8(compact);
    if (decoded == null) return const _FieldUnreadable();
    final text = QQEncoding.normalize(decoded);
    return text.trim().isEmpty ? const _FieldEmpty() : _FieldText(text);
  }

  String? _decodeBase64Utf8(String value) {
    try {
      return utf8.decode(base64.decode(base64.normalize(value)));
    } on FormatException {
      return null;
    }
  }

  /// 网关翻译是与原文同时间轴的 LRC。去掉日语歌才有的注音行 `[kana:…]` 和 `//`
  /// 占位行（"这一行没有翻译"）；一行有效译文都不剩就当没翻译。
  String? _cleanTranslation(String? raw) {
    final field = _decodeLyricField(raw);
    if (field is! _FieldText) return null;
    final kept = field.value.split('\n').where((line) {
      final trimmed = line.trim();
      return !_kanaTag.hasMatch(trimmed) && _lineText(trimmed) != _translationPlaceholder;
    }).toList();
    final hasTranslatedLine = kept.any(
        (line) => _leadingTimestamps.hasMatch(line.trim()) && _lineText(line).isNotEmpty);
    return hasTranslatedLine ? kept.join('\n') : null;
  }

  /// 纯音乐在两条取词路上都只回一行 `[00:00:00]此歌曲为没有填词的纯音乐，请您欣赏`，
  /// 没有可同步的内容，按"没词"处理，让下一个 provider 试。
  bool _isInstrumentalPlaceholder(String lyric) {
    final texts = lyric
        .split('\n')
        .map(_lineText)
        .where((text) => text.isNotEmpty && !_idTag.hasMatch(text))
        .toList();
    return texts.isNotEmpty && texts.every((text) => text == _instrumentalPlaceholder);
  }

  /// 去掉行首所有时间戳后的正文。
  String _lineText(String line) => line.trim().replaceFirst(_leadingTimestamps, '').trim();

  // ── HTTP / JSON ──────────────────────────────────────────────────────────

  /// 网关应答里 `req_1.data`；任何一层 code 非零都算这台主机拒绝。
  Future<Map<String, dynamic>?> _callGateway(
      String base, Map<String, dynamic> body, String what) async {
    final url = Uri.parse('$base$_gatewayPath');
    final root = await _fetchJson(
      () => _client.post(url, headers: _gatewayHeaders, body: jsonEncode(body)),
      what,
    );
    if (root == null || !_codeIsZero(root)) return null;
    final reply = _obj(root[_gatewayRequestKey]);
    if (reply == null) return null;
    final code = _asInt(reply['code']);
    if (code != 0) {
      _logger.w('QQ $what refused: $code');
      return null;
    }
    return _obj(reply['data']);
  }

  Map<String, dynamic> _gatewayBody(String module, String method, Map<String, dynamic> param) => {
        'comm': {'ct': _gatewayClientType, 'cv': _gatewayClientVersion, 'uin': '0'},
        _gatewayRequestKey: {'module': module, 'method': method, 'param': param},
      };

  /// 2xx 且能解析成 JSON 对象的应答体；状态码、传输、超时、空体、解析失败都返回 null。
  Future<Map<String, dynamic>?> _fetchJson(
      Future<http.Response> Function() send, String what) async {
    final String text;
    try {
      final response = await send().timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logger.w('QQ $what failed: ${response.statusCode}');
        return null;
      }
      text = utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (e) {
      _logger.w('QQ $what error: $e');
      return null;
    }
    if (text.trim().isEmpty) return null;
    try {
      final decoded = json.decode(_unwrapJsonp(text));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      _logger.w('QQ $what parse error: $e');
      return null;
    }
  }

  /// `MusicJsonCallback({...})` / `callback({...});` → `{...}`；裸 JSON 原样返回。
  String _unwrapJsonp(String body) {
    final text = body.trim();
    if (text.startsWith('{') || text.startsWith('[')) return text;
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    if (open <= 0 || close <= open) return text;
    if (!_jsonpCallback.hasMatch(text.substring(0, open).trim())) return text;
    return text.substring(open + 1, close);
  }

  bool _codeIsZero(Map<String, dynamic> root) =>
      !root.containsKey('code') || _asInt(root['code']) == 0;

  static Map<String, dynamic>? _obj(dynamic value) =>
      value is Map<String, dynamic> ? value : null;

  static String? _string(dynamic value) =>
      value is String ? value : (value is num ? value.toString() : null);

  static String? _nonBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value;

  static int? _asInt(dynamic value) =>
      value is int ? value : (value is num ? value.toInt() : int.tryParse('$value'));

  // ── 常量 ─────────────────────────────────────────────────────────────────

  static const String _unavailableMessage = 'QQ Music is unavailable right now';

  static const List<String> _defaultWebBaseUrls = ['https://c.y.qq.com', 'https://shc.y.qq.com'];
  static const List<String> _defaultGatewayBaseUrls = ['https://u.y.qq.com', 'https://u6.y.qq.com'];

  static const String _webSearchPath = '/soso/fcgi-bin/client_search_cp';
  static const String _songDetailPath = '/v8/fcg-bin/fcg_play_single_song.fcg';
  static const String _legacyLyricPath = '/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  static const String _gatewayPath = '/cgi-bin/musicu.fcg';

  static const String _gatewayRequestKey = 'req_1';
  static const String _gatewayClientType = '19';
  static const String _gatewayClientVersion = '1859';
  static const String _searchModule = 'music.search.SearchCgiService';
  static const String _searchMethod = 'DoSearchForQQMusicDesktop';
  static const String _lyricModule = 'music.musichallSong.PlayLyricInfo';
  static const String _lyricMethod = 'GetPlayLyricInfo';

  static const int _searchPageSize = 10;
  static const int _midMemoryCapacity = 512;
  static const int _noLyricRetcode = -1901;
  static const String _artistSeparator = ' / ';
  static const String _translationPlaceholder = '//';
  static const String _instrumentalPlaceholder = '此歌曲为没有填词的纯音乐，请您欣赏';
  static const Duration _requestTimeout = Duration(seconds: 10);

  static const Map<String, String> _webHeaders = {
    'referer': 'https://y.qq.com/',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36',
  };
  static const Map<String, String> _gatewayHeaders = {
    'content-type': 'application/json; charset=utf-8',
  };

  static final RegExp _hexText = RegExp(r'^[0-9A-Fa-f]+$');
  static final RegExp _leadingTimestamps = RegExp(r'^(?:\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\])+');
  static final RegExp _idTag = RegExp(r'^\[[A-Za-z]+:[^\]]*\]$');
  static final RegExp _kanaTag = RegExp(r'^\[kana:.*\]$');
  static final RegExp _jsonpCallback = RegExp(r'^[A-Za-z_$][\w$.]*$');
}

/// 调试用的原文 + 翻译载荷（`tool/qq_lyric_probe.dart`）。
class QQLyricPayload {
  final String? lyric;
  final String? translatedLyric;
  final String? romanizedLyric;

  const QQLyricPayload({this.lyric, this.translatedLyric, this.romanizedLyric});

  bool get hasAnyContent =>
      (lyric?.trim().isNotEmpty ?? false) ||
      (translatedLyric?.trim().isNotEmpty ?? false) ||
      (romanizedLyric?.trim().isNotEmpty ?? false);
}

/// [album] 只给匹配器认现场 / 访谈专辑用。
class _QQSong {
  final int id;
  final String? mid;
  final String title;
  final List<String> artists;
  final String? album;

  _QQSong({required this.id, this.mid, required this.title, required this.artists, this.album});

  SongMatch toMatch() => SongMatch(
        songId: id.toString(),
        title: title,
        artist: artists.join(QQProvider._artistSeparator),
      );
}

/// 某台主机给出的权威答复；[value] 本身可以是"没有"。null 的 Answer 表示该换主机了。
class _Answer<T> {
  final T value;

  const _Answer(this.value);
}

sealed class _GatewayLyric {
  const _GatewayLyric();
}

class _GatewayFound extends _GatewayLyric {
  final LyricResult payload;

  const _GatewayFound(this.payload);
}

class _GatewayMissing extends _GatewayLyric {
  const _GatewayMissing();
}

class _GatewayEncrypted extends _GatewayLyric {
  const _GatewayEncrypted();
}

sealed class _LyricField {
  const _LyricField();
}

class _FieldEmpty extends _LyricField {
  const _FieldEmpty();
}

class _FieldUnreadable extends _LyricField {
  const _FieldUnreadable();
}

class _FieldText extends _LyricField {
  final String value;

  const _FieldText(this.value);
}

/// 一组同类主机，按"上次答复的那台优先"轮询。状态只属于这个 provider 实例。
class _HostRotation {
  _HostRotation(List<String> baseUrls)
      : _bases = baseUrls.map((base) => base.replaceFirst(RegExp(r'/+$'), '')).toList();

  final List<String> _bases;
  int _preferred = 0;

  Future<_Answer<T>?> firstAnswer<T>(Future<_Answer<T>?> Function(String base) attempt) async {
    final start = _preferred;
    for (var offset = 0; offset < _bases.length; offset++) {
      final index = (start + offset) % _bases.length;
      final answer = await attempt(_bases[index]);
      if (answer == null) continue;
      _preferred = index;
      return answer;
    }
    return null;
  }
}

/// 搜索结果里见过的 songid → songmid，供网关不可用时走 Web 旧接口。有界 LRU。
class _SongMidMemory {
  _SongMidMemory(this._capacity);

  final int _capacity;
  final LinkedHashMap<int, String> _mids = LinkedHashMap<int, String>();

  void remember(int songId, String? mid) {
    if (mid == null || mid.trim().isEmpty) return;
    _mids.remove(songId);
    _mids[songId] = mid;
    while (_mids.length > _capacity) {
      _mids.remove(_mids.keys.first);
    }
  }

  String? recall(int songId) {
    final mid = _mids.remove(songId);
    if (mid != null) _mids[songId] = mid;
    return mid;
  }
}
