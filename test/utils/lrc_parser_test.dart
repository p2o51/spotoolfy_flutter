import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/utils/lrc_parser.dart';
import 'package:spotoolfy_flutter/utils/provider_translation_pairing.dart';

void main() {
  group('LrcParser (mirrors Yoin LrcParserTest)', () {
    test('parses mm:ss.xx and mm:ss.xxx timestamps', () {
      final lines = LrcParser.parse('[00:12.34]a\n[01:05.00]b\n[00:01.123]c\n[00:02.5]d');
      expect(lines.map((l) => l.timestamp.inMilliseconds).toList(), [1123, 2500, 12340, 65000]);
    });

    test('skips metadata tags and kana lines', () {
      final lines = LrcParser.parse('[ti:Song]\n[ar:Artist]\n[offset:0]\n[kana:1よ]\n[00:01.00]line');
      expect(lines.single.text, 'line');
    });

    test('expands a line with several timestamps, keeping file order on ties', () {
      final lines = LrcParser.parse('[00:12.00][00:50.00]chorus\n[00:12.00]second at 12s');
      expect(lines.map((l) => '${l.timestamp.inMilliseconds}:${l.text}').toList(),
          ['12000:chorus', '12000:second at 12s', '50000:chorus']);
    });

    test('accepts colon fraction separator and single digit minutes', () {
      final lines = LrcParser.parse('[0:01:50]x');
      expect(lines.single.timestamp.inMilliseconds, 1500);
    });

    test('drops empty text and returns empty list for unsynced text', () {
      expect(LrcParser.parse('[00:01.00]\n[00:02.00]   '), isEmpty);
      expect(LrcParser.parse('just words\nno stamps'), isEmpty);
    });

    test('trims surrounding whitespace and CR before matching', () {
      final lines = LrcParser.parse('  [00:03.00]spaced  \r\n');
      expect(lines.single.text, 'spaced');
    });
  });

  group('pairProviderTranslations (mirrors Yoin buildProviderTranslations)', () {
    List<Duration> starts(String lrc) => LrcParser.parse(lrc).map((l) => l.timestamp).toList();

    test('zips equal groups and skips // placeholders', () {
      const original = '[00:00.00]Title - Artist\n[00:00.00]First line\n[00:04.00]Second';
      const translation = '[00:00.00]//\n[00:00.00]第一行\n[00:04.00]第二';
      expect(pairProviderTranslations(starts(original), translation), {1: '第一行', 2: '第二'});
    });

    test('shares the last translation across an unequal group', () {
      const original = '[00:00.00]Title - Artist\n[00:00.00]First line\n[00:04.00]Second';
      const translation = '[00:00.00]第一行\n[00:04.00]第二';
      expect(pairProviderTranslations(starts(original), translation), {0: '第一行', 1: '第一行', 2: '第二'});
    });

    test('falls back to one-to-one nearest match within 500ms', () {
      const original = '[00:01.00]One\n[00:02.00]Two';
      const translation = '[00:01.50]一\n[00:02.50]//';
      expect(pairProviderTranslations(starts(original), translation), {0: '一'});
    });

    test('translation text drops placeholders', () {
      expect(providerTranslationText('[00:00.00]//\n[00:01.00]一\n[00:02.00]二'), '一\n二');
    });
  });
}
