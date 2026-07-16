import 'dart:async';
import 'package:html_unescape/html_unescape.dart';

/// 歌词提供者抽象类
abstract class LyricProvider {
  /// 搜索歌曲，返回平台自己的歌曲ID（单个结果）
  Future<SongMatch?> search(String title, String artist);

  /// 搜索歌曲，返回多个匹配结果
  Future<List<SongMatch>> searchMultiple(String title, String artist, {int limit = 3});

  /// 获取歌词，只返回原文LRC
  Future<String?> fetchLyric(String songId);

  /// 获取歌词及提供者自带的翻译（若有）。
  /// 默认实现只取原文；支持翻译的提供者（网易云、QQ）应覆写。
  Future<LyricResult?> fetchLyricWithTranslation(String songId) async {
    final lyric = await fetchLyric(songId);
    if (lyric == null) return null;
    return LyricResult(lyric: lyric);
  }


  /// 提供者名称
  String get name;
  
  /// 规范化歌词文本
  String normalizeLyric(String rawLyric) {
    final unescape = HtmlUnescape();
    final decoded = unescape.convert(rawLyric);
    return decoded.replaceAll(RegExp(r'\r?\n+'), '\n').trim();
  }
  
  /// 获取歌词的完整流程
  Future<String?> getLyric(String title, String artist) async {
    try {
      final songMatch = await search(title, artist);
      if (songMatch == null) return null;
      
      final rawLyric = await fetchLyric(songMatch.songId);
      if (rawLyric == null) return null;
      
      final normalized = normalizeLyric(rawLyric);
      if (normalized.isEmpty) {
        return null;
      }
      return normalized;
    } catch (e) {
      return null;
    }
  }
}

/// 歌曲匹配结果
class SongMatch {
  final String songId;
  final String title;
  final String artist;

  SongMatch({
    required this.songId,
    required this.title,
    required this.artist,
  });
}

/// 歌词获取结果（包含可选翻译）
class LyricResult {
  final String lyric;
  final String? translation;

  LyricResult({
    required this.lyric,
    this.translation,
  });

  bool get hasTranslation => translation != null && translation!.trim().isNotEmpty;
}

/// 歌词缓存数据
class LyricCacheData {
  final String provider;
  final String lyric;
  final int timestamp;
  
  LyricCacheData({
    required this.provider,
    required this.lyric,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'lyric': lyric,
      'ts': timestamp,
    };
  }
  
  factory LyricCacheData.fromJson(Map<String, dynamic> json) {
    return LyricCacheData(
      provider: json['provider'] as String,
      lyric: json['lyric'] as String,
      timestamp: json['ts'] as int,
    );
  }
}
