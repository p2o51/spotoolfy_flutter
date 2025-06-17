import 'dart:convert';
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
// html_unescape is used in the provider classes
import 'lyrics/lyric_provider.dart';
import 'lyrics/qq_provider.dart';
import 'lyrics/netease_provider.dart';

class LyricsService {
  final Logger _logger = Logger();
  final List<LyricProvider> _providers = [];
  final QQProvider _qqProvider = QQProvider();
  final NetEaseProvider _neProvider = NetEaseProvider();

  // 缓存键的前缀
  static const String _cacheKeyPrefix = 'lyrics_cache_';
  // 缓存有效期（30天）
  static const int _cacheTtlDays = 30;

  LyricsService() {
    // 按优先级顺序添加提供者
    _providers.add(_qqProvider);
    _providers.add(_neProvider);
  }

  Future<String?> getLyrics(String songName, String artistName, String trackId) async {
    try {
      // 使用 trackId 作为缓存键
      final cacheKey = _cacheKeyPrefix + trackId;

      // 尝试从缓存获取
      final prefs = await SharedPreferences.getInstance();
      final cachedLyricsJson = prefs.getString(cacheKey);

      if (cachedLyricsJson != null) {
        try {
          final cacheData = LyricCacheData.fromJson(json.decode(cachedLyricsJson));

          // 检查缓存是否过期（30天）
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (now - cacheData.timestamp < _cacheTtlDays * 24 * 60 * 60) {
            _logger.i('从缓存获取歌词: $trackId (来源: ${cacheData.provider})');
            return cacheData.lyric;
          } else {
            _logger.i('缓存已过期: $trackId');
          }
        } catch (e) {
          _logger.w('解析缓存数据失败: $e');
          // 如果解析失败，继续获取新数据
        }
      }

      // 如果缓存中没有或已过期，从网络获取
      _logger.i('从网络获取歌词: $songName - $artistName');

      // 并行从多个提供者获取歌词
      final lyrics = await _getFromProviders(songName, artistName);

      // 使用 trackId 存储缓存
      if (lyrics != null) {
        final provider = lyrics['provider'] as String;
        final lyricText = lyrics['lyric'] as String;

        final cacheData = LyricCacheData(
          provider: provider,
          lyric: lyricText,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        await prefs.setString(cacheKey, json.encode(cacheData.toJson()));
        _logger.i('歌词已缓存: $trackId (来源: $provider)');

        return lyricText;
      }

      return null;
    } catch (e) {
      _logger.e('获取歌词失败: $e');
      return null;
    }
  }

  /// 从多个提供者并行获取歌词
  Future<Map<String, String>?> _getFromProviders(String title, String artist) async {
    try {
      // 创建所有提供者的Future
      final futures = _providers.map((provider) =>
        provider.getLyric(title, artist).then((lyric) =>
          lyric != null ? {'provider': provider.name, 'lyric': lyric} : null
        )
      ).toList();

      // 并行执行所有Future，返回第一个非空结果
      final results = await Future.wait(futures);
      final validResults = results.where((result) => result != null).toList();

      if (validResults.isNotEmpty) {
        // 返回第一个有效结果
        return validResults.first as Map<String, String>;
      }

      // 如果并行获取都失败，尝试顺序获取（增加超时时间）
      for (final provider in _providers) {
        _logger.i('尝试从 ${provider.name} 获取歌词（延长超时）');
        final lyric = await provider.getLyric(title, artist);
        if (lyric != null) {
          return {'provider': provider.name, 'lyric': lyric};
        }
      }

      return null;
    } catch (e) {
      _logger.e('从提供者获取歌词失败: $e');
      return null;
    }
  }

  // _evaluateLyricQuality method removed as it was unused

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // 只清除歌词缓存的键
      for (var key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          await prefs.remove(key);
        }
      }
      _logger.i('歌词缓存已清除');
    } catch (e) {
      _logger.e('清除缓存失败: $e');
    }
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int totalSize = 0;
      int qqCount = 0;
      int neCount = 0;
      int otherCount = 0;

      for (var key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          final value = prefs.getString(key);
          if (value != null) {
            totalSize += value.length;

            // 统计各提供者的缓存数量
            try {
              final cacheData = LyricCacheData.fromJson(json.decode(value));
              if (cacheData.provider == 'qq') {
                qqCount++;
              } else if (cacheData.provider == 'netease') {
                neCount++;
              } else {
                otherCount++;
              }
            } catch (e) {
              // 忽略解析错误，可能是旧格式缓存
              otherCount++;
            }
          }
        }
      }

      _logger.i('缓存统计 - 总数: ${qqCount + neCount + otherCount}, QQ音乐: $qqCount, 网易云: $neCount, 其他: $otherCount');
      return totalSize;
    } catch (e) {
      _logger.e('获取缓存大小失败: $e');
      return 0;
    }
  }

  /// 获取当前使用的提供者列表
  List<String> getProviderNames() {
    return _providers.map((provider) => provider.name).toList();
  }
}