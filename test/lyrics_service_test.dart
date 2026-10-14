import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/services/lyrics_service.dart';
import 'package:spotoolfy_flutter/services/lyrics/qq_provider.dart';
import 'package:spotoolfy_flutter/services/lyrics/netease_provider.dart';
import 'package:spotoolfy_flutter/services/lyrics/lyric_provider.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 初始化Flutter绑定
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('LyricsService Tests', () {
    test('QQ Provider can search and fetch lyrics', () async {
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('client_search_cp')) {
          final response = {
            'code': 0,
            'data': {
              'song': {
                'list': [
                  {
                    'id': 102065756,
                    'mid': 'mock-mid',
                    'title': '你瞒我瞒',
                    'singer': [
                      {'name': '陈柏宇'}
                    ],
                  }
                ],
              },
            },
          };
          return http.Response.bytes(utf8.encode(jsonEncode(response)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }

        if (path.contains('musicu.fcg')) {
          final response = {
            'code': 0,
            'req_1': {
              'code': 0,
              'data': {'lyric': '[00:00.00]你瞒我瞒', 'trans': ''},
            },
          };
          return http.Response.bytes(utf8.encode(jsonEncode(response)), 200);
        }

        return http.Response('Not Found', 404);
      });

      final provider = QQProvider(httpClient: mockClient);
      final songMatch = await provider.search('你瞒我瞒', '陈柏宇');

      expect(songMatch, isNotNull);
      expect(songMatch!.songId, '102065756');
      expect(songMatch.title, '你瞒我瞒');
      expect(songMatch.artist, '陈柏宇');
      final lyrics = await provider.fetchLyric(songMatch.songId);
      expect(lyrics, '[00:00.00]你瞒我瞒');
    });

    // 网易云API需要登录，所以这个测试可能会失败
    // 我们将其标记为skip
    test('NetEase Provider can search and fetch lyrics', () async {
      final provider = NetEaseProvider();
      final songMatch = await provider.search('Bohemian Rhapsody', 'Queen');

      // 如果API需要登录，这里可能返回null
      if (songMatch != null) {
        final lyrics = await provider.fetchLyric(songMatch.songId);
        if (lyrics != null) {
          // 验证歌词格式
          expect(lyrics.contains('['), isTrue);
          expect(lyrics.contains(']'), isTrue);
        }
      } else {
        // 如果API需要登录，打印信息并跳过
        debugPrint('网易云API需要登录，跳过测试');
      }
    }, skip: '网易云API可能需要登录');

    test('LyricsService can get lyrics from multiple providers', () async {
      final service = LyricsService(providers: [_FakeLyricProvider()]);
      final result = await service.getLyrics(
          'Bohemian Rhapsody', 'Queen', 'test_track_id');

      expect(result, isNotNull);
      if (result != null) {
        // 验证歌词格式
        expect(result.lyric.contains('['), isTrue);
        expect(result.lyric.contains(']'), isTrue);
        // 验证来源信息
        expect(result.provider, equals('fake'));
      }
    });

    test('takes the highest-priority provider that answers', () async {
      final service = LyricsService(providers: [
        _FakeLyricProvider(name: 'first', lyric: null),
        _FakeLyricProvider(name: 'second', lyric: '[00:01.00]second'),
        _FakeLyricProvider(name: 'third', lyric: '[00:01.00]third'),
      ]);

      final result = await service.getLyrics('t', 'a', 'track_priority');

      expect(result?.provider, 'second');
    });

    test('user-picked lyrics win over the automatic cache and never expire', () async {
      final yearAgo = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 365 * 24 * 3600;
      SharedPreferences.setMockInitialValues({
        'manual_lyrics_cache_t1': jsonEncode({'provider': 'netease', 'lyric': '[00:01.00]picked', 'ts': yearAgo}),
        'lyrics_cache_t1': jsonEncode({'provider': 'qq', 'lyric': '[00:01.00]auto', 'ts': yearAgo}),
      });
      final service = LyricsService(providers: [_FakeLyricProvider(lyric: '[00:01.00]network')]);

      final result = await service.getLyrics('t', 'a', 't1');

      expect(result?.lyric, '[00:01.00]picked');
      expect(result?.provider, 'netease');
    });

    test('clear cache also drops user picks and provider translations', () async {
      SharedPreferences.setMockInitialValues({
        'manual_lyrics_cache_t3': jsonEncode({'provider': 'qq', 'lyric': '[00:01.00]picked', 'ts': 1}),
        'lyrics_cache_t3': jsonEncode({'provider': 'qq', 'lyric': '[00:01.00]auto', 'ts': 1}),
        'netease_translation_t3': '[00:01.00]译',
        'unrelated_key': 'keep',
      });
      final prefs = await SharedPreferences.getInstance();
      await LyricsService(providers: [_FakeLyricProvider()], prefs: prefs).clearCache();

      expect(prefs.getKeys(), {'unrelated_key'});
    });

    test('clears a stale provider translation when new lyrics have none', () async {
      SharedPreferences.setMockInitialValues({
        'netease_translation_t2': '[00:01.00]旧翻译',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = LyricsService(providers: [_FakeLyricProvider()], prefs: prefs);

      final result = await service.getLyrics('t', 'a', 't2');

      expect(result?.hasProviderTranslation, isFalse);
      expect(prefs.getString('netease_translation_t2'), isNull);
    });
  });
}

class _FakeLyricProvider extends LyricProvider {
  _FakeLyricProvider({this.name = 'fake', this.lyric = '[00:00]Mock Lyric Line'});

  @override
  final String name;

  final String? lyric;

  @override
  Future<String?> fetchLyric(String songId) async => lyric;

  @override
  Future<SongMatch?> search(String title, String artist) async {
    return SongMatch(songId: 'fake-id', title: title, artist: artist);
  }

  @override
  Future<List<SongMatch>> searchMultiple(String title, String artist,
      {int limit = 3}) async {
    return [SongMatch(songId: 'fake-id', title: title, artist: artist)];
  }
}
