import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotoolfy_flutter/services/lyrics/lyric_provider.dart';
import 'package:spotoolfy_flutter/services/lyrics/qq_provider_mobile.dart';

/// Mirrors Yoin's QQLyricsProviderTest. Fixtures under `test/fixtures/lyrics/qq/`
/// are live QQ responses recorded 2026-10-05 (trimmed). Two web hosts (`/web1`,
/// `/web2`) and two gateway hosts (`/gw1`, `/gw2`) on one mock client.
void main() {
  late Map<String, http.Response Function(http.Request)> routes;
  late List<http.Request> seen;
  late QQProvider provider;

  String fixture(String name) => File('test/fixtures/lyrics/qq/$name').readAsStringSync();
  http.Response ok(String body) => http.Response.bytes(utf8.encode(body), 200);
  void on(String prefix, http.Response Function(http.Request) handler) => routes[prefix] = handler;
  Iterable<http.Request> hits(String prefix) => seen.where((r) => r.url.path.startsWith(prefix));

  setUp(() {
    routes = {};
    seen = [];
    final client = MockClient((request) async {
      seen.add(request);
      for (final entry in routes.entries) {
        if (request.url.path.startsWith(entry.key)) return entry.value(request);
      }
      return http.Response('', 404);
    });
    provider = QQProvider(
      httpClient: client,
      webBaseUrls: const ['https://qq.test/web1', 'https://qq.test/web2'],
      gatewayBaseUrls: const ['https://qq.test/gw1', 'https://qq.test/gw2'],
    );
  });

  void expectMatch(SongMatch? match, String id, String title, String artist) {
    expect(match, isNotNull);
    expect(match!.songId, id);
    expect(match.title, title);
    expect(match.artist, artist);
  }

  group('search', () {
    test('matches traditional metadata with the default matcher', () async {
      on('/web1/soso/', (_) => ok('''{"code":0,"data":{"song":{"list":[
        {"id":1,"title":"雨爱","singer":[{"name":"张德伊玲"}]},
        {"id":2,"title":"雨爱","singer":[{"name":"杨丞琳"}]}
      ]}}}'''));

      expectMatch(await provider.search('雨愛', '楊丞琳'), '2', '雨爱', '杨丞琳');
      expect(seen.single.url.queryParameters['w'], '雨愛 楊丞琳');
    });

    test('returns artist-matched song when web search answers', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_qingtian.json')));

      expectMatch(await provider.search('晴天', '周杰伦'), '97773', '晴天', '周杰伦');
      final request = seen.single;
      expect(request.method, 'GET');
      expect(request.url.queryParameters['w'], '晴天 周杰伦');
      expect(request.url.queryParameters['new_json'], '1');
      expect(request.url.queryParameters['n'], '10');
      expect(request.headers['referer'], 'https://y.qq.com/');
    });

    test('tries next web host when first returns 500, then prefers the one that answered', () async {
      on('/web1/soso/', (_) => http.Response('', 500));
      on('/web2/soso/', (_) => ok(fixture('search_cp_qingtian.json')));

      expect((await provider.search('晴天', '周杰伦'))?.songId, '97773');
      expect((await provider.search('晴天', '周杰伦'))?.songId, '97773');
      expect(hits('/web1/').length, 1);
      expect(hits('/web2/').length, 2);
    });

    test('tries next web host when search body is blank', () async {
      on('/web1/soso/', (_) => ok(''));
      on('/web2/soso/', (_) => ok(fixture('search_cp_qingtian.json')));

      expect((await provider.search('晴天', '周杰伦'))?.songId, '97773');
    });

    test('falls back to gateway search when every web host fails', () async {
      on('/web1/soso/', (_) => http.Response('', 500));
      on('/web2/soso/', (_) => http.Response('', 502));
      on('/gw1/', (_) => ok(fixture('gateway_refused_2001.json')));
      on('/gw2/', (_) => ok(fixture('gateway_search_qingtian.json')));

      expect((await provider.search('晴天', '周杰伦'))?.songId, '97773');
      final body = hits('/gw2/').last.body;
      expect(body, contains('"method":"DoSearchForQQMusicDesktop"'));
      expect(body, contains('"query":"晴天 周杰伦"'));
      expect(body, contains('"ct":"19"'));
    });

    test('throws unavailable when every search route fails', () async {
      on('/', (_) => http.Response('', 500));

      await expectLater(
        provider.searchMultiple('晴天', '周杰伦', limit: 3),
        throwsA(isA<Exception>().having((e) => '$e', 'message', contains('QQ Music is unavailable'))),
      );
      expect(await provider.search('晴天', '周杰伦'), isNull);
    });

    test('returns null when katakana artist leaves same title ambiguous', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_stupid_love_katakana.json')));

      expect(await provider.search('Stupid Love', 'レディー・ガガ'), isNull);
    });

    test('skips wrong artist at top when artist is comparable', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_stupid_love_katakana.json')));

      expectMatch(await provider.search('Stupid Love', 'Lady Gaga'), '267472054', 'Stupid Love', 'Lady Gaga');
    });

    test('returns null when unverifiable artist matches several recordings', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_what_was_that_katakana.json')));

      expect(await provider.search('What Was That', 'ロード'), isNull);
      expect((await provider.search('What Was That', 'Lorde'))?.songId, '586058642');
    });

    test('keeps provider order when searching manually', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_stupid_love_katakana.json')));

      final matches = await provider.searchMultiple('Stupid Love', '', limit: 3);

      expect(matches.map((m) => m.songId).toList(), ['5017814', '449497875', '267472054']);
      expect(seen.single.url.queryParameters['w'], 'Stupid Love');
      expect(seen.single.url.queryParameters['n'], '3');
    });

    test('prefers studio album when plain title comes from concert album', () async {
      const list = '''[
        {"id":"9001","title":"晴天","singer":[{"name":"周杰伦"}],"album":{"name":"周杰伦 2004 无与伦比 演唱会 Live CD"}},
        {"id":"9002","title":"晴天","singer":[{"name":"周杰伦"}],"albumname":"Live in Tokyo 1966"},
        {"id":"97773","title":"晴天","singer":[{"name":"周杰伦"}],"album":{"name":"叶惠美"}}
      ]''';
      on('/web1/soso/', (_) => ok('{"code":0,"data":{"song":{"list":$list}}}'));

      expect((await provider.search('晴天', '周杰伦'))?.songId, '97773');
    });

    test('skips songs without numeric id', () async {
      const list = '[{"id":"abc123","title":"Lost Stars","singer":[{"name":"Adam Levine"}]}]';
      on('/web1/soso/', (_) => ok('{"code":0,"data":{"song":{"list":$list}}}'));

      expect(await provider.search('Lost Stars', 'Adam Levine'), isNull);
    });
  });

  group('lyric', () {
    test('decodes lyric and cleans translation when gateway answers', () async {
      on('/gw1/', (_) => ok(fixture('play_lyric_lemon_213086592.json')));

      final payload = await provider.fetchLyricWithTranslation('213086592');

      expect(payload, isNotNull);
      expect(payload!.lyric.startsWith('[ti:Lemon'), isTrue);
      expect(payload.lyric, contains('[00:01.54]夢ならば'));
      final translation = payload.translation!;
      expect(translation, contains('[00:01.54]如果只是一场梦'));
      expect(translation.split('\n').any((line) => line.endsWith(']//')), isFalse);
      expect(translation.contains('[kana:'), isFalse);
      final body = seen.single.body;
      expect(body, contains('"songID":213086592'));
      expect(body, contains('"crypt":0'));
      expect(body, contains('"trans":1'));
      expect(body.contains('songMID'), isFalse);
    });

    test('tries next gateway host when lyric code is non-zero', () async {
      on('/gw1/', (_) => ok('{"code":0,"req_1":{"code":24001}}'));
      on('/gw2/', (_) => ok(fixture('play_lyric_lemon_213086592.json')));

      expect((await provider.fetchLyric('213086592'))!.startsWith('[ti:Lemon'), isTrue);
    });

    test('decodes plain base64 lyric', () async {
      const plain = '[00:01.00]hello world';
      final b64 = base64Encode(utf8.encode(plain));
      on('/gw1/', (_) => ok('{"req_1": {"code": 0, "data": {"lyric": "$b64"}}}'));

      expect(await provider.fetchLyric('97773'), plain);
    });

    test('uses remembered mid when gateway is unreachable', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_qingtian.json')));
      on('/gw', (_) => http.Response('', 500));
      on('/web1/lyric/', (_) => ok(fixture('legacy_lyric_qingtian_0039MnYb0qxYhV.json')));

      final match = (await provider.search('晴天', '周杰伦'))!;
      final payload = await provider.fetchLyricWithTranslation(match.songId);

      expect(payload!.lyric.startsWith('[ti:晴天]'), isTrue);
      expect(payload.lyric, contains('故事的小黄花'));
      final lyricRequest = hits('/web1/lyric/').single;
      expect(lyricRequest.url.queryParameters['songmid'], '0039MnYb0qxYhV');
      expect(lyricRequest.url.queryParameters['nobase64'], '1');
      expect(seen.any((r) => r.url.path.contains('fcg_play_single_song')), isFalse);
    });

    test('resolves mid by song id when mid is unknown (JSONP + base64 legacy body)', () async {
      on('/gw', (_) => http.Response('', 500));
      on('/web1/v8/', (_) => ok(fixture('song_detail_97773.json')));
      on('/web1/lyric/', (_) => ok(fixture('legacy_lyric_qingtian_jsonp_base64.txt')));

      final lyric = await provider.fetchLyric('97773');

      expect(lyric!.startsWith('[ti:晴天]'), isTrue);
      expect(hits('/web1/v8/').single.url.queryParameters['songid'], '97773');
    });

    test('uses web lyric when gateway sends cipher text', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_qingtian.json')));
      on('/gw1/', (_) => ok('{"req_1":{"code":0,"data":{"lyric":"${'E5D94A70C91F7022' * 4}","trans":""}}}'));
      on('/web1/lyric/', (_) => ok(fixture('legacy_lyric_qingtian_0039MnYb0qxYhV.json')));

      await provider.search('晴天', '周杰伦');
      expect((await provider.fetchLyric('97773'))!.startsWith('[ti:晴天]'), isTrue);
    });

    test('returns null when gateway answers without lyric', () async {
      on('/gw1/', (_) => ok('{"req_1":{"code":0,"data":{"lyric":"","trans":""}}}'));

      expect(await provider.fetchLyric('97773'), isNull);
      expect(seen.length, 1);
    });

    test('tries next web host when web lyric is refused', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_qingtian.json')));
      on('/gw', (_) => http.Response('', 500));
      on('/web1/lyric/', (_) => ok(fixture('legacy_lyric_refused_1101.json')));
      on('/web2/lyric/', (_) => ok(fixture('legacy_lyric_qingtian_0039MnYb0qxYhV.json')));

      await provider.search('晴天', '周杰伦');
      expect((await provider.fetchLyric('97773'))!.startsWith('[ti:晴天]'), isTrue);
    });

    test('stops at first web host when song has no lyric', () async {
      on('/web1/soso/', (_) => ok(fixture('search_cp_qingtian.json')));
      on('/gw', (_) => http.Response('', 500));
      on('/web1/lyric/', (_) => ok('{"retcode":-1901,"code":-1901,"subcode":-1901}'));

      await provider.search('晴天', '周杰伦');
      expect(await provider.fetchLyric('97773'), isNull);
      expect(hits('/web2/lyric/'), isEmpty);
    });

    test('treats the instrumental placeholder as no lyric', () async {
      on('/gw1/', (_) => ok(jsonEncode({
            'req_1': {
              'code': 0,
              'data': {'lyric': '[00:00:00]此歌曲为没有填词的纯音乐，请您欣赏', 'trans': ''},
            },
          })));

      expect(await provider.fetchLyric('97773'), isNull);
    });

    test('rejects non-numeric song id without a request', () async {
      expect(await provider.fetchLyric('abc123'), isNull);
      expect(seen, isEmpty);
    });
  });
}
