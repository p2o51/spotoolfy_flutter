import '../models/lyric_line.dart';

/// 歌词解析工具类
///
/// 负责解析不同格式的歌词文本
class LyricsParser {
  /// LRC 时间标签正则表达式
  static final RegExp _timeTagRegex = RegExp(r'^\[(\d{2,}):(\d{2})\.?(\d{2,3})?\]');

  /// 解析带时间戳的歌词 (LRC 格式)
  ///
  /// 返回按时间排序的 [LyricLine] 列表
  static List<LyricLine> parseSyncedLyrics(String rawLyrics) {
    final lines = rawLyrics.split('\n');
    final List<LyricLine> result = [];

    for (var line in lines) {
      final match = _timeTagRegex.firstMatch(line);
      if (match != null) {
        try {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          // 处理可选的毫秒（2或3位数字）
          final millisecondsStr = match.group(3);
          int milliseconds = 0;
          if (millisecondsStr != null) {
            if (millisecondsStr.length == 2) {
              // 2位数字表示厘秒，转换为毫秒
              milliseconds = int.parse(millisecondsStr) * 10;
            } else {
              // 3位数字表示毫秒
              milliseconds = int.parse(millisecondsStr);
            }
          }

          final timestamp = Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          );

          var text = line.substring(match.end).trim();
          // 解码常见的 HTML 实体
          text = _decodeHtmlEntities(text);

          // 只添加非空歌词行
          if (text.isNotEmpty) {
            result.add(LyricLine(timestamp, text));
          }
        } catch (e) {
          // 解析失败时跳过该行
        }
      }
    }

    // 按时间戳排序
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return result;
  }

  /// 解析不带时间戳的歌词
  ///
  /// 为每行分配递增的索引作为伪时间戳
  static List<LyricLine> parseUnsyncedLyrics(String rawLyrics) {
    final lines = rawLyrics
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final List<LyricLine> result = [];
    for (var i = 0; i < lines.length; i++) {
      // 使用递增的毫秒值作为伪时间戳
      result.add(LyricLine(Duration(milliseconds: i), _decodeHtmlEntities(lines[i])));
    }
    return result;
  }

  /// 检查歌词是否包含时间戳
  static bool hasSyncedTimestamps(String rawLyrics) {
    final lines = rawLyrics.split('\n');
    for (var line in lines) {
      if (_timeTagRegex.hasMatch(line)) {
        return true;
      }
    }
    return false;
  }

  /// 解码 HTML 实体
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  /// 根据当前播放位置获取当前歌词行索引
  ///
  /// 返回 -1 表示当前位置没有对应的歌词行
  static int getCurrentLineIndex(List<LyricLine> lyrics, Duration currentPosition) {
    if (lyrics.isEmpty) return -1;

    // 如果当前位置在第一行之前
    if (currentPosition < lyrics[0].timestamp) {
      return -1;
    }

    // 从后向前查找最后一个时间戳小于等于当前位置的行
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (lyrics[i].timestamp <= currentPosition) {
        return i;
      }
    }

    return -1;
  }

  /// 将歌词列表转换为纯文本
  static String lyricsToPlainText(List<LyricLine> lyrics, {bool includeTranslations = false}) {
    final buffer = StringBuffer();
    for (final line in lyrics) {
      buffer.writeln(line.text);
      if (includeTranslations && line.hasTranslation) {
        buffer.writeln(line.translation);
      }
    }
    return buffer.toString().trim();
  }

  /// 提取所有歌词行的原始文本
  static List<String> extractOriginalLines(List<LyricLine> lyrics) {
    return lyrics.map((line) => line.text).toList();
  }

  /// 应用翻译到歌词列表
  static void applyTranslations(List<LyricLine> lyrics, Map<int, String> translations) {
    for (var i = 0; i < lyrics.length; i++) {
      final translated = translations[i];
      if (translated != null && translated.trim().isNotEmpty) {
        lyrics[i].translation = translated.trim();
      } else {
        lyrics[i].translation = null;
      }
    }
  }

  /// 检查歌词列表中是否有翻译
  static bool hasTranslations(List<LyricLine> lyrics) {
    return lyrics.any((line) => line.hasTranslation);
  }
}
