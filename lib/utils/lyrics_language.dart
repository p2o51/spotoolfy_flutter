/// Script-based language heuristics for lyric translation.
///
/// Synced with Yoin's `appearsMostlyChinese` logic: when the translation
/// target is Chinese and the lyrics are already (almost) pure Han text,
/// translation is skipped instead of burning an API call on a no-op.
library;

/// Whether the app-level target language code refers to Chinese
/// (e.g. `zh-CN`, `zh-TW`).
bool isChineseLanguageCode(String languageCode) =>
    languageCode.trim().toLowerCase().startsWith('zh');

/// True when translating [lines] into [targetLanguageCode] would be a no-op
/// because the lyrics already appear to be in the target language.
///
/// Only Chinese targets are detected for now (mirrors Yoin): kana or hangul
/// anywhere disqualifies the match so Japanese/Korean lyrics with kanji or
/// hanja still get translated.
bool lyricsAlreadyInTargetLanguage(
  List<String> lines,
  String targetLanguageCode,
) =>
    isChineseLanguageCode(targetLanguageCode) && lyricsAppearMostlyChinese(lines);

/// Heuristic: enough Han ideographs, no kana/hangul at all, and a high
/// Han-to-meaningful-character ratio.
bool lyricsAppearMostlyChinese(List<String> lines) {
  var han = 0;
  var kana = 0;
  var hangul = 0;
  var latin = 0;
  for (final line in lines) {
    for (final rune in line.runes) {
      if (_isHanIdeograph(rune)) {
        han += 1;
      } else if (_isJapaneseKana(rune)) {
        kana += 1;
      } else if (_isHangul(rune)) {
        hangul += 1;
      } else if (_isLatinLetter(rune)) {
        latin += 1;
      }
    }
  }
  final meaningful = han + kana + hangul + latin;
  if (han < 8 || meaningful < 12) return false;
  if (kana > 0 || hangul > 0) return false;
  final hanRatio = han / meaningful;
  return hanRatio >= 0.72 || (han >= 20 && hanRatio >= 0.60);
}

bool _isHanIdeograph(int code) =>
    (code >= 0x4E00 && code <= 0x9FFF) || // CJK Unified Ideographs
    (code >= 0x3400 && code <= 0x4DBF) || // Extension A
    (code >= 0x20000 && code <= 0x2A6DF) || // Extension B
    (code >= 0x2A700 && code <= 0x2B73F) || // Extension C
    (code >= 0x2B740 && code <= 0x2B81F) || // Extension D
    (code >= 0x2B820 && code <= 0x2CEAF) || // Extension E
    (code >= 0x2CEB0 && code <= 0x2EBEF) || // Extension F
    (code >= 0x30000 && code <= 0x3134F) || // Extension G
    (code >= 0x31350 && code <= 0x323AF) || // Extension H
    (code >= 0xF900 && code <= 0xFAFF) || // CJK Compatibility Ideographs
    (code >= 0x2F800 && code <= 0x2FA1F); // CJK Compatibility Supplement

bool _isJapaneseKana(int code) =>
    (code >= 0x3040 && code <= 0x309F) || // Hiragana
    (code >= 0x30A0 && code <= 0x30FF) || // Katakana
    (code >= 0x31F0 && code <= 0x31FF); // Katakana Phonetic Extensions

bool _isHangul(int code) =>
    (code >= 0xAC00 && code <= 0xD7AF) || // Hangul Syllables
    (code >= 0x1100 && code <= 0x11FF) || // Hangul Jamo
    (code >= 0x3130 && code <= 0x318F) || // Hangul Compatibility Jamo
    (code >= 0xA960 && code <= 0xA97F) || // Hangul Jamo Extended-A
    (code >= 0xD7B0 && code <= 0xD7FF); // Hangul Jamo Extended-B

bool _isLatinLetter(int code) =>
    (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
