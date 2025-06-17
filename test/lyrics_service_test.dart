import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/services/lyrics_service.dart';
import 'package:spotoolfy_flutter/services/lyrics/qq_provider.dart';
import 'package:spotoolfy_flutter/services/lyrics/netease_provider.dart';

void main() {
  // 初始化Flutter绑定
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LyricsService Tests', () {
    test('QQ Provider can search and fetch lyrics', () async {
      final provider = QQProvider();
      final songMatch = await provider.search('Bohemian Rhapsody', 'Queen');

      expect(songMatch, isNotNull);
      if (songMatch != null) {
        final lyrics = await provider.fetchLyric(songMatch.songId);
        expect(lyrics, isNotNull);

        if (lyrics != null) {
          // 验证歌词格式
          expect(lyrics.contains('['), isTrue);
          expect(lyrics.contains(']'), isTrue);
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
      final service = LyricsService();
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
