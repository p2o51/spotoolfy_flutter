import '../models/lyric_line.dart';

/// 把 LRC 文本解析成按时间排序的歌词行。与 Yoin 的 `LrcParser` 同一套规则：
///
/// - `[mm:ss]` / `[mm:ss.x]` / `[mm:ss.xx]` / `[mm:ss.xxx]`，分隔符也可以是 `:`
///   （QQ 的纯音乐占位行就是 `[00:00:00]`）；分钟 1–3 位；
/// - 一行多个时间戳（副歌复用）展开成多行，正文取最后一个时间戳之后的部分；
/// - 整行是 `[ti:…]` / `[ar:…]` / `[kana:…]` 之类的标签时跳过；
/// - 正文为空的行丢掉；
/// - 稳定排序：同一时间戳的行保持文件里的先后顺序（逐行配翻译要靠它）。
///
/// 一行时间戳都没有时返回空列表，由调用方按非同步歌词处理。
class LrcParser {
  LrcParser._();

  static final RegExp _timestamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _metadataTag = RegExp(r'^\[[a-zA-Z]+:[^\]]*\]$');

  static List<LyricLine> parse(String raw) {
    final entries = <_Entry>[];
    var order = 0;
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_metadataTag.hasMatch(line) && !_timestamp.hasMatch(line)) continue;

      final matches = _timestamp.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final ms = _toMilliseconds(match);
        if (ms == null) continue;
        entries.add(_Entry(ms, order++, text));
      }
    }
    entries.sort((a, b) => a.ms != b.ms ? a.ms.compareTo(b.ms) : a.order.compareTo(b.order));
    return entries.map((e) => LyricLine(Duration(milliseconds: e.ms), e.text)).toList();
  }

  static int? _toMilliseconds(RegExpMatch match) {
    final minutes = int.tryParse(match.group(1)!);
    final seconds = int.tryParse(match.group(2)!);
    if (minutes == null || seconds == null) return null;
    final fraction = match.group(3) ?? '';
    final int fractionMs;
    switch (fraction.length) {
      case 0:
        fractionMs = 0;
      case 1:
        fractionMs = int.parse(fraction) * 100;
      case 2:
        fractionMs = int.parse(fraction) * 10;
      default:
        fractionMs = int.parse(fraction.substring(0, 3));
    }
    return minutes * 60000 + seconds * 1000 + fractionMs;
  }
}

class _Entry {
  final int ms;
  final int order;
  final String text;

  _Entry(this.ms, this.order, this.text);
}
