import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotoolfy_flutter/services/lyrics/netease_provider.dart';

/// Mirrors Yoin's NetEaseLyricsProviderTest. Fixtures under
/// `test/fixtures/lyrics/netease/` are live `cloudsearch` answers from the
/// Spotoolfy proxy, recorded 2026-10-05 and trimmed.
void main() {
  late List<http.Response> queue;
  late List<http.Request> seen;
  late NetEaseProvider provider;

  String fixture(String name) => File('test/fixtures/lyrics/netease/$name').readAsStringSync();
  http.Response ok(String body) => http.Response.bytes(utf8.encode(body), 200);

  setUp(() {
    queue = [];
    seen = [];
    provider = NetEaseProvider(
      baseUrl: 'https://netease.test',
      httpClient: MockClient((request) async {
        seen.add(request);
        return queue.isEmpty ? http.Response('', 404) : queue.removeAt(0);
      }),
    );
  });

  group('automatic matching', () {
    test('reads ar first name and album from cloudsearch', () async {
      queue.add(ok('{"result":{"songs":[{"id":123456,"name":"晴天","ar":[{"name":"周杰伦"}]}]}}'));

      final match = await provider.search('晴天', '周杰伦');

      expect(match?.songId, '123456');
      expect(match?.title, '晴天');
      expect(match?.artist, '周杰伦');
      expect(seen.single.url.path, '/cloudsearch');
    });

    test('returns null when only result is an unrelated song', () async {
      queue.add(ok(fixture('cloudsearch_what_was_that_katakana.json')));

      expect(await provider.search('What Was That', 'ロード'), isNull);
      expect(seen.single.url.queryParameters['keywords'], 'What Was That ロード');
      expect(seen.single.url.queryParameters['limit'], '10');
    });

    test('returns null when katakana artist cannot be verified', () async {
      queue.add(ok(fixture('cloudsearch_stupid_love_katakana.json')));
      expect(await provider.search('Stupid Love', 'レディー・ガガ'), isNull);
    });

    test('returns null when only covers and namesakes answer', () async {
      queue.add(ok(fixture('cloudsearch_qingtian.json')));
      expect(await provider.search('晴天', '周杰伦'), isNull);
    });

    test('skips other artist ranked first when artist is comparable', () async {
      queue.add(ok(fixture('cloudsearch_let_it_go.json')));
      final match = await provider.search('Let It Go', 'Demi Lovato');
      expect(match?.songId, '28814175');
      expect(match?.title, 'Let It Go');
      expect(match?.artist, 'Demi Lovato');
    });

    test('prefers matching artist when bare title belongs to someone else', () async {
      queue.add(ok(fixture('cloudsearch_let_it_go.json')));
      expect((await provider.search('Let It Go', 'Idina Menzel'))?.songId, '28031119');
    });

    test('picks original when remix, live and instrumental rank first', () async {
      queue.add(ok(fixture('cloudsearch_blinding_lights_versions.json')));
      final match = await provider.search('Blinding Lights', 'The Weeknd');
      expect(match?.songId, '1433194293');
      expect(match?.title, 'Blinding Lights');
    });

    test('picks studio remaster when plain title is an unplugged recording', () async {
      queue.add(ok(fixture('cloudsearch_hotel_california.json')));
      expect((await provider.search('Hotel California', 'Eagles'))?.songId, '26289183');
    });

    test('reads album name when unplugged recording ranks first', () async {
      queue.add(ok('''{"result":{"songs":[
          {"id":1302701468,"name":"Hotel California","ar":[{"name":"Eagles"}],
           "al":{"name":"Unplugged 1994 - The Second Night"}},
          {"id":1318509823,"name":"Hotel California (1999 Remaster)","ar":[{"name":"Eagles"}],
           "al":{"name":"Selected Works 1972-1999"}}
      ]},"code":200}'''));
      expect((await provider.search('Hotel California', 'Eagles'))?.songId, '1318509823');
    });

    test('picks studio remaster when plain title is on an interview album', () async {
      queue.add(ok(fixture('cloudsearch_yesterday.json')));
      expect((await provider.search('Yesterday', 'The Beatles'))?.songId, '4337372');
    });

    test('picks instrumental when requested title is instrumental', () async {
      queue.add(ok(fixture('cloudsearch_blinding_lights_versions.json')));
      expect((await provider.search('Blinding Lights (Instrumental)', 'The Weeknd'))?.songId, '1478647776');
    });

    test('picks dominant performer when artist is written in another script', () async {
      queue
        ..add(ok(fixture('cloudsearch_lemon.json')))
        ..add(ok(fixture('cloudsearch_lemon.json')));
      expect((await provider.search('Lemon', 'Kenshi Yonezu'))?.songId, '536622304');
      expect((await provider.search('Lemon', '米津玄師'))?.songId, '536622304');
    });

    test('does not match by requested title when result has no name', () async {
      const body = '{"result":{"songs":[{"id":1,"ar":[{"name":"Placeholder Artist"}]}]},"code":200}';
      queue
        ..add(ok(body))
        ..add(ok(body));
      expect(await provider.search('Placeholder Song', 'Placeholder Artist'), isNull);
      final manual = await provider.searchMultiple('Placeholder Song', 'Placeholder Artist', limit: 3);
      expect(manual.single.songId, '1');
      expect(manual.single.title, 'Placeholder Song');
      expect(manual.single.artist, 'Placeholder Artist');
    });

    test('returns null when search fails', () async {
      queue
        ..add(http.Response('', 500))
        ..add(ok('not json'));
      expect(await provider.search('Placeholder Song', 'Placeholder Artist'), isNull);
      expect(await provider.searchMultiple('Placeholder Song', 'Placeholder Artist', limit: 3), isEmpty);
    });
  });

  group('manual search', () {
    test("keeps NetEase's order", () async {
      queue.add(ok(fixture('cloudsearch_blinding_lights_versions.json')));

      final matches = await provider.searchMultiple('Blinding Lights', 'The Weeknd', limit: 3);

      expect(matches.map((m) => m.songId).toList(), ['1500412585', '2027162148', '1478647776']);
      expect(matches.map((m) => m.title).toList(),
          ['Blinding Lights (Remix)', 'Blinding Lights (Live)', 'Blinding Lights (Instrumental)']);
      expect(seen.single.url.queryParameters['keywords'], 'Blinding Lights The Weeknd');
      expect(seen.single.url.queryParameters['limit'], '3');
    });

    test('lists unrelated result so the user decides', () async {
      queue.add(ok(fixture('cloudsearch_what_was_that_katakana.json')));
      final matches = await provider.searchMultiple('What Was That', 'ロード', limit: 3);
      expect(matches.single.songId, '2079173646');
      expect(matches.single.title, 'Bittersweet');
      expect(matches.single.artist, 'BONNIE PINK');
    });

    test('skips request when limit is zero', () async {
      expect(await provider.searchMultiple('Placeholder Song', '', limit: 0), isEmpty);
      expect(seen, isEmpty);
    });
  });

  group('lyric', () {
    test('returns plain lrc and converts word-level JSON lines in both lyric and translation', () async {
      final yrc = [
        '{"t":1000,"c":[{"tx":"hel"},{"tx":"lo"}]}',
        '{"t":2500,"c":[{"tx":"world"}]}',
      ].join('\n');
      final tyrc = '{"t":1000,"c":[{"tx":"你好"}]}';
      queue.add(ok(jsonEncode({
        'lrc': {'lyric': yrc},
        'tlyric': {'lyric': tyrc},
      })));

      final result = await provider.fetchLyricWithTranslation('123');

      expect(result!.lyric, contains('[00:01.00]hello'));
      expect(result.lyric, contains('[00:02.50]world'));
      expect(result.translation, '[00:01.00]你好');
      expect(seen.single.url.path, '/lyric/new');
      expect(seen.single.url.queryParameters['id'], '123');
    });

    test('returns null on empty lrc', () async {
      queue.add(ok('{"lrc":{"lyric":""}}'));
      expect(await provider.fetchLyric('789'), isNull);
    });
  });
}
