import 'lrc_parser.dart';

/// 歌词源（网易云 / QQ）自带的翻译 LRC 和原文逐行配对。与 Yoin 的
/// `buildProviderTranslations` 同一套规则：
///
/// 1. 按时间戳分组。原文和翻译在同一时间戳上的行数相同 → 组内按顺序一一对应；
///    行数不同 → 这一组的原文都用该时间戳最后一条非空译文。
/// 2. `//` 是"这一行没有翻译"的占位，不算译文。
/// 3. 一个时间戳都对不上时（翻译来自另一次搜索，时间轴略有偏移），退回旧做法：
///    每行原文取 500ms 内最近的一条译文。
///
/// 返回 原文行下标 → 译文。
Map<int, String> pairProviderTranslations(
  List<Duration> lineStarts,
  String translationLrc,
) {
  final offered = LrcParser.parse(translationLrc);
  if (offered.isEmpty || lineStarts.isEmpty) return {};

  final offeredByStart = <int, List<String>>{};
  for (final line in offered) {
    (offeredByStart[line.timestamp.inMilliseconds] ??= <String>[]).add(line.text);
  }
  final originalsByStart = <int, List<int>>{};
  for (var i = 0; i < lineStarts.length; i++) {
    (originalsByStart[lineStarts[i].inMilliseconds] ??= <int>[]).add(i);
  }

  final exact = <int, String>{};
  originalsByStart.forEach((startMs, originals) {
    final texts = offeredByStart[startMs];
    if (texts == null) return;
    if (texts.length == originals.length) {
      for (var i = 0; i < originals.length; i++) {
        final translation = _usable(texts[i]);
        if (translation != null) exact[originals[i]] = translation;
      }
    } else {
      String? shared;
      for (final text in texts.reversed) {
        if (text.trim().isNotEmpty) {
          shared = _usable(text);
          break;
        }
      }
      if (shared == null) return;
      for (final index in originals) {
        exact[index] = shared;
      }
    }
  });
  if (exact.isNotEmpty) return exact;

  // 时间轴对不上：500ms 以内按距离从近到远一一配对，一条译文只给一行原文。
  final pairs = <(int, int, int)>[]; // (距离, 原文下标, 译文下标)
  for (var i = 0; i < lineStarts.length; i++) {
    final start = lineStarts[i].inMilliseconds;
    for (var j = 0; j < offered.length; j++) {
      if (_usable(offered[j].text) == null) continue;
      final diff = (offered[j].timestamp.inMilliseconds - start).abs();
      if (diff <= 500) pairs.add((diff, i, j));
    }
  }
  pairs.sort((a, b) => a.$1 != b.$1
      ? a.$1.compareTo(b.$1)
      : (a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3)));
  final nearest = <int, String>{};
  final usedOffered = <int>{};
  for (final (_, line, offer) in pairs) {
    if (nearest.containsKey(line) || usedOffered.contains(offer)) continue;
    nearest[line] = offered[offer].text.trim();
    usedOffered.add(offer);
  }
  return nearest;
}

/// 译文全文（去掉占位行），给"复制翻译"之类的地方用。
String providerTranslationText(String translationLrc) => LrcParser.parse(translationLrc)
    .map((line) => _usable(line.text))
    .whereType<String>()
    .join('\n');

String? _usable(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed == '//') return null;
  return trimmed;
}
