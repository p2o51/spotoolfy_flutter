import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/utils/lyrics_language.dart';
import 'package:spotoolfy_flutter/utils/structured_translation.dart';

void main() {
  group('parseTaggedLineTranslations', () {
    test('parses tagged response and strips echoed line markers', () {
      const raw = '[L0][1] 第一行[/L0]\n[L1]【2】第二行[/L1]';

      final parsed = parseTaggedLineTranslations(raw, lineCount: 2);

      expect(parsed[0], '第一行');
      expect(parsed[1], '第二行');
    });

    test('tolerates case and whitespace variants', () {
      const raw = '[ l0 ]first[ / L0 ]\n[L1]second[/l1]';

      final parsed = parseTaggedLineTranslations(raw, lineCount: 2);

      expect(parsed[0], 'first');
      expect(parsed[1], 'second');
    });

    test('drops out-of-range indices', () {
      const raw = '[L0]ok[/L0]\n[L5]overflow[/L5]';

      final parsed = parseTaggedLineTranslations(raw, lineCount: 2);

      expect(parsed, {0: 'ok'});
    });
  });

  group('cleanLineTranslation', () {
    test('strips leading list markers', () {
      expect(cleanLineTranslation('[1] 第一行'), '第一行');
      expect(cleanLineTranslation('(2) 第二行'), '第二行');
      expect(cleanLineTranslation('3. 第三行'), '第三行');
      expect(cleanLineTranslation('- 4、第四行'), '第四行');
    });

    test('strips leftover tag markers', () {
      expect(cleanLineTranslation('[L0]text[/L0]'), 'text');
    });
  });

  group('parseLyricsTranslationText', () {
    test('prefers tagged format and maps onto original indices', () {
      final original = ['line one', '', 'line three'];
      const raw = '[L0]一行目[/L0]\n[L2]三行目[/L2]';

      final result = parseLyricsTranslationText(raw, originalLines: original);

      expect(result.translations, {0: '一行目', 2: '三行目'});
      expect(result.missingLineIndices, [1]);
    });

    test('falls back to legacy structured format for old cache entries', () {
      final original = ['line one', 'line two'];
      const raw = '__L0001__ <<< 一行目\n__L0002__ <<< 二行目';

      final result = parseLyricsTranslationText(raw, originalLines: original);

      expect(result.translations, {0: '一行目', 1: '二行目'});
    });

    test('maps plain lines onto non-blank source lines when counts match', () {
      final original = ['line one', '', 'line three'];
      const raw = '一行目\n三行目';

      final result = parseLyricsTranslationText(raw, originalLines: original);

      expect(result.translations, {0: '一行目', 2: '三行目'});
    });

    test('returns empty translations when plain fallback count differs', () {
      final original = ['line one', 'line two'];
      const raw = '第一行\n第二行\n第三行';

      final result = parseLyricsTranslationText(raw, originalLines: original);

      expect(result.translations, isEmpty);
    });
  });

  group('lyricsAlreadyInTargetLanguage', () {
    const chineseLyrics = [
      '你存在我深深的脑海里',
      '我的梦里我的心里我的歌声里',
      '世界之大为何我们相遇',
      '难道是缘分难道是天意',
    ];

    test('detects pure Chinese lyrics for Chinese targets', () {
      expect(lyricsAlreadyInTargetLanguage(chineseLyrics, 'zh-CN'), isTrue);
      expect(lyricsAlreadyInTargetLanguage(chineseLyrics, 'zh-TW'), isTrue);
    });

    test('never skips for non-Chinese targets', () {
      expect(lyricsAlreadyInTargetLanguage(chineseLyrics, 'en'), isFalse);
      expect(lyricsAlreadyInTargetLanguage(chineseLyrics, 'ja'), isFalse);
    });

    test('kanji-heavy Japanese lyrics with kana still get translated', () {
      const japanese = [
        '夜に駆ける君の輪郭をなぞる',
        '沈むように溶けてゆくように',
        '二人だけの空が広がる夜に',
      ];
      expect(lyricsAlreadyInTargetLanguage(japanese, 'zh-CN'), isFalse);
    });

    test('mostly-Latin lyrics are not treated as Chinese', () {
      const english = [
        'Hello darkness my old friend 朋友',
        'I have come to talk with you again',
      ];
      expect(lyricsAlreadyInTargetLanguage(english, 'zh-CN'), isFalse);
    });
  });
}
