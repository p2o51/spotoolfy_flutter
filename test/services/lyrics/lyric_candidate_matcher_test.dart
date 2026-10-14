import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/services/lyrics/lyric_candidate_matcher.dart';

/// Mirrors Yoin's LyricCandidateMatcherTest (candidate lists from live QQ /
/// NetEase searches, 2026-10-05).
void main() {
  final matcher = LyricCandidateMatcher();

  LyricCandidate c(String title, List<String> artists, {String? album}) =>
      LyricCandidate(title, artists, album: album);

  test('matches simplified candidate when request is traditional Chinese', () {
    final candidates = [
      c('雨爱', ['杨丞琳']),
      c('雨爱 (DJ 阿若版)', ['杨丞琳']),
      c('雨爱', ['张德伊玲']),
    ];
    expect(matcher.pick(candidates, '雨愛', '楊丞琳'), 0);
  });

  test('matches traditional candidate when request is simplified Chinese', () {
    expect(matcher.pick([c('雨愛', ['楊丞琳'])], '雨爱', '杨丞琳'), 0);
  });

  test('normalizes traditional artist when the title is already identical', () {
    final candidates = [c('晴天', ['周杰伦']), c('晴天', ['林俊杰'])];
    expect(matcher.pick(candidates, '晴天', '周杰倫'), 0);
    expect(matcher.pick(candidates, '晴天', '陳奕迅'), isNull);
  });

  test('keeps an explicitly supplied folding function', () {
    final custom = LyricCandidateMatcher(fold: (text) => text.replaceAll('Alias', 'Band'));
    expect(custom.pick([c('Song', ['Band'])], 'Song', 'Alias'), 0);
  });

  test('prefers plain title when decorated version comes first', () {
    final candidates = [c('晴天 (Live)', ['周杰伦']), c('晴天', ['周杰伦'])];
    expect(matcher.pick(candidates, '晴天', '周杰伦'), 1);
  });

  test('accepts decorated title when no plain version exists', () {
    expect(matcher.pick([c('Detour (Explicit)', ['Kim Petras'])], 'Detour', 'Kim Petras'), 0);
  });

  test('matches artist when latin words overlap across scripts', () {
    expect(matcher.pick([c('party 4 u', ['Charli xcx'])], 'party 4 u', 'チャーリーxcx'), 0);
  });

  test('matches artist when request names several artists', () {
    final candidates = [
      c('In My Bag', ['Someone Else']),
      c('In My Bag (Explicit)', ['FLO', 'GloRilla']),
    ];
    expect(matcher.pick(candidates, 'In My Bag', 'FLO & GloRilla'), 1);
  });

  test('rejects all when comparable artist differs', () {
    final candidates = [c('Stupid Love', ['Jason Derulo']), c('Stupid Love', ['Dan + Shay'])];
    expect(matcher.pick(candidates, 'Stupid Love', 'Lady Gaga'), isNull);
  });

  test('skips wrong artist at top when right artist is further down', () {
    final candidates = [
      c('Stupid Love', ['Jason Derulo']),
      c('stupid love', ['米卡']),
      c('Stupid Love', ['Lady Gaga']),
    ];
    expect(matcher.pick(candidates, 'Stupid Love', 'Lady Gaga'), 2);
  });

  test('accepts unverifiable artist when every title match is by same artist', () {
    final candidates = [
      c('my tears ricochet', ['Taylor Swift']),
      c('my tears ricochet (the long pond studio sessions)', ['Taylor Swift']),
      c('cardigan', ['Taylor Swift']),
    ];
    expect(matcher.pick(candidates, 'my tears ricochet', 'テイラー・スウィフト'), 0);
  });

  test('rejects unverifiable artist when title matches several artists', () {
    final candidates = [
      c('Stupid Love', ['Jason Derulo']),
      c('stupid love', ['米卡']),
      c('Stupid Love', ['Lady Gaga']),
    ];
    expect(matcher.pick(candidates, 'Stupid Love', 'レディー・ガガ'), isNull);
  });

  test('accepts dominant performer when unverifiable artist has most cuts', () {
    final candidates = [
      c('痛快的哀艳 (苏打绿版)', ['苏打绿']),
      c('痛快的哀艳 (Live)', ['苏诗丁']),
      c('痛快的哀艳 (Endless Story Live)', ['苏打绿']),
      c('痛快的哀艳', ['苏打绿']),
      c('痛快的哀艳 (二十年一刻Live)', ['苏打绿']),
      c('四季未了 (Live)', ['苏打绿']),
      c('痛快的哀艳 (Live)', ['苏打绿']),
      c('痛快的哀艳 (Remix)', ['金鸿煊']),
      c('痛快的哀艳', ['泪零Namida']),
      c('痛快的哀艳', ['比利凯']),
    ];
    expect(matcher.pick(candidates, '痛快的哀艷', 'ソーダグリーン'), 3);
  });

  test("picks studio cut when dominant performer also has Taylor's Version", () {
    final candidates = [
      c('I Knew You Were Trouble', ['Taylor Swift']),
      c('I Knew You Were Trouble (Taylor’s Version)', ['Taylor Swift']),
      c('I Knew You Were Trouble', ['Party Hit Kings']),
      c('I Knew You Were Trouble (Live from the BRITs 2013)', ['Taylor Swift']),
      c('I Knew You Were Trouble (Fish Fugue Remix)', ['Fish Fugue', 'Taylor Swift']),
    ];
    expect(matcher.pick(candidates, 'I Knew You Were Trouble', 'テイラー・スウィフト'), 0);
  });

  test('returns null when top ranked performer has only one cut', () {
    final candidates = [
      c('What Was That', ['Lorde']),
      c('What Was That', ['Chartwave Collective']),
      c('What Was That (Live)', ['Chartwave Collective']),
    ];
    expect(matcher.pick(candidates, 'What Was That', 'ロード'), isNull);
  });

  test('does not treat kana prefix as same artist', () {
    expect(matcher.pick([c('What Was That', ['ロードオブメジャー'])], 'What Was That', 'ロード'), isNull);
  });

  test('does not match short latin fragment inside longer name', () {
    final candidates = [c('After LIKE', ['Five Seconds']), c('After LIKE', ['IVE'])];
    expect(matcher.pick(candidates, 'After LIKE', 'IVE'), 1);
  });

  test('returns null when no title matches', () {
    final candidates = [c("Making A Life Outa Livin'(feat. Ms. Lex)", ['Murdoq'])];
    expect(matcher.pick(candidates, 'Making Out', 'Lexie Liu'), isNull);
  });

  test('ignores case, width and punctuation when comparing titles', () {
    expect(matcher.pick([c('ＡＰＴ．', ['ROSÉ'])], 'APT.', 'ROSÉ & Bruno Mars'), 0);
  });

  test('skips instrumental cut when request is the vocal version', () {
    final candidates = [
      c('晴天 (伴奏)', ['周杰伦']),
      c('Instant Crush (Inst.)', ['Daft Punk']),
      c('晴天 (Live)', ['周杰伦']),
    ];
    expect(matcher.pick(candidates, '晴天', '周杰伦'), 2);
    expect(matcher.pick(candidates, 'Instant Crush', 'Daft Punk'), isNull);
  });

  test('accepts instrumental cut when request is instrumental too', () {
    expect(matcher.pick([c('晴天 (伴奏)', ['周杰伦'])], '晴天 (伴奏版)', '周杰伦'), 0);
  });

  group('same-master notes', () {
    test('ranks remaster with plain title when both name the studio cut', () {
      final remasterFirst = [c('Hotel California (2013 Remaster)', ['Eagles']), c('Hotel California', ['Eagles'])];
      final plainFirst = [c('Hotel California', ['Eagles']), c('Hotel California (1999 Remaster)', ['Eagles'])];
      expect(matcher.pick(remasterFirst, 'Hotel California', 'Eagles'), 0);
      expect(matcher.pick(plainFirst, 'Hotel California', 'Eagles'), 0);
    });

    test('prefers remaster when live cut ranks first', () {
      final candidates = [
        c('Hotel California (Live on MTV, 1994)', ['Eagles']),
        c('Hotel California (2013 Remaster)', ['Eagles']),
      ];
      expect(matcher.pick(candidates, 'Hotel California', 'Eagles'), 1);
    });

    test('prefers remaster when plain title comes from unplugged album', () {
      final candidates = [
        c('Hotel California', ['Eagles'], album: 'Unplugged 1994 - The Second Night'),
        c('Hotel California (2013 Remaster)', ['Eagles'], album: 'The Studio Albums 1972-1979 (2013 Remaster)'),
      ];
      expect(matcher.pick(candidates, 'Hotel California', 'Eagles'), 1);
    });

    test('picks studio remaster when NetEase lists live and unplugged cuts', () {
      final candidates = [
        c('Hotel California (2013 Remaster)', ['Eagles'], album: 'The Studio Albums 1972-1979 (2013 Remaster)'),
        c('Hotel California (Live on MTV, 1994)', ['Eagles'], album: 'Hell Freezes Over'),
        c('Hotel California (1999 Remaster)', ['Eagles'], album: 'Selected Works 1972-1999'),
        c('Hotel California', ['Eagles'], album: 'Unplugged 1994 - The Second Night'),
        c('Hotel California (live)', ['Eagles'], album: 'Unplugged 1994 (live)'),
        c('Hotel California', ['Eagles'], album: 'The Summit, Houston, 1976 (Hd Remastered Edition)'),
      ];
      expect(matcher.pick(candidates, 'Hotel California', 'Eagles'), 0);
      expect(matcher.pick(candidates.sublist(1), 'Hotel California', 'Eagles'), 1);
    });

    test('picks remaster when NetEase lists an interview album entry', () {
      final candidates = [
        c('Yesterday (Remastered)', ['The Beatles'], album: 'Help! (Remastered)'),
        c('Yesterday', ['The Beatles', 'Marty Murray'], album: 'Famous Interviews - The Beatles'),
        c('Yesterday (live)', ['The Beatles'], album: 'Live in Tokyo 1966'),
        c('Yesterday (Take 1 - Remastered)', ['The Beatles'], album: 'Anthology Highlights'),
        c('Yesterday (2023 Mix)', ['The Beatles'], album: 'The Beatles 1962 – 1966 (2023 Edition)'),
      ];
      expect(matcher.pick(candidates, 'Yesterday', 'The Beatles'), 0);
      expect(matcher.pick(candidates.take(2).toList().reversed.toList(), 'Yesterday', 'The Beatles'), 1);
    });

    test('ranks interview album below live cut when no studio cut exists', () {
      final candidates = [
        c('Yesterday', ['The Beatles', 'Marty Murray'], album: 'Famous Interviews - The Beatles'),
        c('Yesterday (live)', ['The Beatles'], album: 'Live in Tokyo 1966'),
      ];
      expect(matcher.pick(candidates, 'Yesterday', 'The Beatles'), 1);
      expect(matcher.pick(candidates.take(1).toList(), 'Yesterday', 'The Beatles'), 0);
    });

    test('treats note as original when it only names the same master', () {
      const sameMaster = [
        '(Remastered)', '(Remaster)', '(2013 Remaster)', '(Remastered 2009)', '- Remastered 2009',
        '- 2011 Remastered Version', '(Digitally Remastered)', '(40th Anniversary Remaster)',
        '(Hd Remastered Edition)', '(Mono)', '(Stereo)', '(Mono Version)', '(2009 Stereo Mix)',
        '(Mono / Remastered 2009)', '(Album Version)', '(LP Version)', '(Original Version)',
        '(Original Mix)', '(Explicit)', '[Explicit]', '(2019 リマスター)', '(アルバム・バージョン)',
      ];
      for (final note in sameMaster) {
        final candidates = [c('Placeholder Song (Live)', ['Band']), c('Placeholder Song $note', ['Band'])];
        expect(matcher.pick(candidates, 'Placeholder Song', 'Band'), 1, reason: note);
      }
    });

    test('keeps note decorated when it names another version', () {
      const otherVersions = [
        '(Live)', '(Unplugged)', '(Remix)', '(2023 Mix)', '(Single Version)', '(Single Edit)', '(Radio Edit)',
        '(Edit)', '(Clean)', '(Original)', '(Take 1 - Remastered)', '(Live / Remastered)',
        '(Taylor’s Version)', '(Acoustic)', '(Cover)', '(Sped Up)', '(Slowed)', '(Demo)', '(feat. Mono)',
      ];
      for (final note in otherVersions) {
        final candidates = [c('Placeholder Song $note', ['Band']), c('Placeholder Song', ['Band'])];
        expect(matcher.pick(candidates, 'Placeholder Song', 'Band'), 1, reason: note);
      }
    });

    test('keeps feat clause decorated when featured name looks like a master word', () {
      final candidates = [c('Placeholder Song feat. Stereo', ['Band']), c('Placeholder Song', ['Band'])];
      expect(matcher.pick(candidates, 'Placeholder Song', 'Band'), 1);
    });

    test('matches plain candidate when request title carries remaster', () {
      final candidates = [c('Yesterday (Live)', ['The Beatles']), c('Yesterday', ['The Beatles'])];
      expect(matcher.pick(candidates, 'Yesterday - Remastered 2009', 'The Beatles'), 1);
      expect(matcher.pick(candidates, 'Yesterday (2015 Remaster)', 'The Beatles'), 1);
    });

    test('does not backtrack exponentially on long digit runs', () {
      final note = '(${'1' * 40}x)';
      final candidates = [c('Placeholder Song $note', ['Band']), c('Placeholder Song', ['Band'])];
      final watch = Stopwatch()..start();
      expect(matcher.pick(candidates, 'Placeholder Song', 'Band'), 1);
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('album names', () {
    test('prefers studio album when plain title comes from concert album', () {
      final candidates = [
        c('晴天', ['周杰伦'], album: '周杰伦 2004 无与伦比 演唱会 Live CD'),
        c('晴天', ['周杰伦'], album: '叶惠美'),
      ];
      expect(matcher.pick(candidates, '晴天', '周杰伦'), 1);
    });

    test('does not flag studio album when live is just a word in its name', () {
      final throughThis = [
        c('Placeholder Song', ['Band'], album: 'Live Through This'),
        c('Placeholder Song (Remastered)', ['Band'], album: 'Collection'),
      ];
      final mysteryTour = [
        c('Placeholder Song', ['Band'], album: 'Magical Mystery Tour'),
        c('Placeholder Song (Remastered 2009)', ['Band'], album: '1967-1970'),
      ];
      expect(matcher.pick(throughThis, 'Placeholder Song', 'Band'), 0);
      expect(matcher.pick(mysteryTour, 'Placeholder Song', 'Band'), 0);
    });

    test('flags live album when live or tour is followed by a place or year', () {
      for (final album in ['Live in Tokyo 1966', 'After Hours (Live At SoFi Stadium)', 'idina: live', 'Tour 2019']) {
        final candidates = [
          c('Placeholder Song', ['Band'], album: album),
          c('Placeholder Song', ['Band'], album: 'Studio Album'),
        ];
        expect(matcher.pick(candidates, 'Placeholder Song', 'Band'), 1, reason: album);
      }
    });

    test('ranks instrumental album below live cut when title looks plain', () {
      final candidates = [
        c('Placeholder Song', ['Band'], album: 'Placeholder Song (Instrumental)'),
        c('Placeholder Song (Live)', ['Band']),
      ];
      expect(matcher.pick(candidates, 'Placeholder Song', 'Band'), 1);
    });

    test('ignores album when request itself is a live cut', () {
      final candidates = [
        c('Hotel California (Live, 1994)', ['Eagles'], album: 'Hell Freezes Over'),
        c('Hotel California (Live)', ['Eagles'], album: 'Unplugged 1994 (live)'),
      ];
      expect(matcher.pick(candidates, 'Hotel California (Live)', 'Eagles'), 1);
    });
  });
}
