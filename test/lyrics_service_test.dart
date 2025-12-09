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
            'data': {
              'song': {
                'list': [
                  {
                    'songmid': 'mock-song-id',
                    'songname': '你瞒我瞒',
                    'singer': [
                      {'name': '陈柏宇'}
                    ],
                  }
                ],
              },
            },
          };
          return http.Response(jsonEncode(response), 200,
              headers: {'content-type': 'application/json'});
        }

        if (path.contains('fcg_query_lyric_new')) {
          final response = {'lyric': '[00:00]你瞒我瞒'};
          final bodyBytes = utf8.encode(jsonEncode(response));
          return http.Response.bytes(bodyBytes, 200,
              headers: {'content-type': 'application/json'});
        }

        return http.Response('Not Found', 404);
      });

      final provider = QQProvider(httpClient: mockClient);
      final songMatch = await provider.search('Bohemian Rhapsody', 'Queen');

      expect(songMatch, isNotNull);
      if (songMatch != null) {
        expect(songMatch.title, '你瞒我瞒');
        expect(songMatch.artist, '陈柏宇');
        final lyrics = await provider.fetchLyric(songMatch.songId);
        expect(lyrics, isNotNull);

        if (lyrics != null) {
          // 验证歌词格式
          expect(lyrics.contains('['), isTrue);
          expect(lyrics.contains(']'), isTrue);
          expect(lyrics.contains('你瞒我瞒'), isTrue);
        }
      }
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
      final lyrics = await service.getLyrics('Bohemian Rhapsody', 'Queen', 'test_track_id');

      expect(lyrics, isNotNull);
      if (lyrics != null) {
        // 验证歌词格式
        expect(lyrics.contains('['), isTrue);
        expect(lyrics.contains(']'), isTrue);
      }
    });
  });
}

class _FakeLyricProvider extends LyricProvider {
  @override
  String get name => 'fake';

  @override
  Future<String?> fetchLyric(String songId) async {
    return '[00:00]Mock Lyric Line';
  }

  @override
  Future<SongMatch?> search(String title, String artist) async {
    return SongMatch(songId: 'fake-id', title: title, artist: artist);
  }

  @override
  Future<List<SongMatch>> searchMultiple(String title, String artist, {int limit = 3}) async {
    return [SongMatch(songId: 'fake-id', title: title, artist: artist)];
  }
}
