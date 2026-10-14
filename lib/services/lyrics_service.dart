import 'dart:convert';
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
// html_unescape is used in the provider classes
import '../models/lyrics_result.dart';
import 'lyrics/lyric_provider.dart';
import 'lyrics/qq_provider.dart';
import 'lyrics/netease_provider.dart';
import 'lyrics/lrclib_provider.dart';

export '../models/lyrics_result.dart';

class LyricsService {
  final Logger _logger = Logger();
  final List<LyricProvider> _providers;
  SharedPreferences? _prefsCache;

  // 缓存键的前缀
  static const String _cacheKeyPrefix = 'lyrics_cache_';
  // 用户亲手选的歌词（搜索页选中、接受换源）。与 Yoin 一致：永不过期，优先于自动匹配。
  static const String _manualCacheKeyPrefix = 'manual_lyrics_cache_';
  // 缓存有效期（30天）
  static const int _cacheTtlDays = 30;

  LyricsService({List<LyricProvider>? providers, SharedPreferences? prefs})
      // 自动匹配顺序与 Yoin 一致：QQ → 网易云 → LRCLIB。
      : _providers = providers ?? [QQProvider(), NetEaseProvider(), LRCLibProvider()],
        _prefsCache = prefs;

  /// 获取歌词
  ///
  /// 返回 [LyricsResult] 包含歌词文本、来源信息和翻译可用性
  Future<LyricsResult?> getLyrics(String songName, String artistName, String trackId) async {
    try {
      // 使用 trackId 作为缓存键
      final cacheKey = _cacheKeyPrefix + trackId;
      // 历史键名：现在存放任意提供者（网易云/QQ）自带的翻译 LRC，
      // 键名保留 netease 前缀是为了兼容旧缓存。
      final translationCacheKey = 'netease_translation_$trackId';

      final prefs = await _getPrefs();

      // 用户亲手选的歌词永不过期，也不被自动匹配覆盖。
      final manualJson = prefs.getString(_manualCacheKeyPrefix + trackId);
      if (manualJson != null) {
        try {
          final manual = LyricCacheData.fromJson(json.decode(manualJson));
          if (manual.lyric.trim().isNotEmpty) {
            _logger.i('使用手动选择的歌词: $trackId (来源: ${manual.provider})');
            return LyricsResult(
              lyric: manual.lyric,
              provider: manual.provider,
              hasProviderTranslation: _providerSupportsTranslation(manual.provider) &&
                  prefs.getString(translationCacheKey) != null,
            );
          }
        } catch (e) {
          _logger.w('解析手动歌词缓存失败: $e');
        }
      }

      // 尝试从缓存获取
      final cachedLyricsJson = prefs.getString(cacheKey);

      if (cachedLyricsJson != null) {
        try {
          final cacheData = LyricCacheData.fromJson(json.decode(cachedLyricsJson));

          // 检查缓存是否过期（30天）
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (now - cacheData.timestamp < _cacheTtlDays * 24 * 60 * 60) {
            _logger.i('从缓存获取歌词: $trackId (来源: ${cacheData.provider})');
            // 检查是否有提供者自带翻译缓存
            final hasProviderTranslation =
                _providerSupportsTranslation(cacheData.provider) &&
                    prefs.getString(translationCacheKey) != null;
            return LyricsResult(
              lyric: cacheData.lyric,
              provider: cacheData.provider,
              hasProviderTranslation: hasProviderTranslation,
            );
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
        final translation = lyrics['translation'];
        final hasTranslation = translation != null && translation.isNotEmpty;

        final cacheData = LyricCacheData(
          provider: provider,
          lyric: lyricText,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        await prefs.setString(cacheKey, json.encode(cacheData.toJson()));
        _logger.i('歌词已缓存: $trackId (来源: $provider)');

        // 如果提供者自带翻译，单独缓存；没有就清掉旧歌词留下的翻译，免得对不上。
        if (hasTranslation) {
          await prefs.setString(translationCacheKey, translation);
          _logger.i('提供者翻译已缓存: $trackId (来源: $provider)');
        } else {
          await prefs.remove(translationCacheKey);
        }

        return LyricsResult(
          lyric: lyricText,
          provider: provider,
          hasProviderTranslation: hasTranslation,
        );
      }

      return null;
    } catch (e) {
      _logger.e('获取歌词失败: $e');
      return null;
    }
  }

  /// 支持自带翻译的提供者（与 Yoin 的 PROVIDER_TRANSLATION_NAMES 对应）
  static bool _providerSupportsTranslation(String providerName) =>
      providerName == 'netease' || providerName == 'qq';

  /// 从单个提供者获取歌词（带翻译提供者会一并抓取翻译）
  Future<Map<String, String>?> _fetchFromProvider(
      LyricProvider provider, String title, String artist) async {
    if (_providerSupportsTranslation(provider.name)) {
      final match = await provider.search(title, artist);
      if (match == null) return null;

      final result = await provider.fetchLyricWithTranslation(match.songId);
      if (result == null) return null;

      final normalized = provider.normalizeLyric(result.lyric);
      if (normalized.isEmpty) return null;

      final map = <String, String>{
        'provider': provider.name,
        'lyric': normalized,
      };
      // 如果有翻译，也加入返回
      if (result.hasTranslation) {
        map['translation'] = result.translation!;
      }
      return map;
    }

    // 其他提供者使用标准流程
    final lyric = await provider.getLyric(title, artist);
    return lyric != null ? {'provider': provider.name, 'lyric': lyric} : null;
  }

  /// 从多个提供者并行获取歌词，按 [_providers] 的优先级取第一个有结果的。
  /// 返回 Map 包含 provider, lyric, 以及可选的 translation（网易云/QQ）
  Future<Map<String, String>?> _getFromProviders(String title, String artist) async {
    try {
      // 创建所有提供者的Future
      final futures = _providers
          .map((provider) async {
            try {
              return await _fetchFromProvider(provider, title, artist);
            } catch (e) {
              _logger.w('从 ${provider.name} 获取歌词失败: $e');
              return null;
            }
          })
          .toList();

      // 并行执行所有Future，返回第一个非空结果
      final results = await Future.wait(futures);
      final validResults = results.where((result) => result != null).toList();

      // 返回优先级最高的有效结果。全部失败时不再顺序重跑一遍（超时相同，只会再等一轮）。
      return validResults.isNotEmpty ? validResults.first : null;
    } catch (e) {
      _logger.e('从提供者获取歌词失败: $e');
      return null;
    }
  }

  // _evaluateLyricQuality method removed as it was unused

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await _getPrefs();
      final keys = prefs.getKeys();

      // 清除歌词缓存的键。手动选的歌词平时永不过期，但"清除缓存"是用户的明确操作，
      // 一并清掉，连同音源翻译，回到自动匹配。
      for (var key in keys) {
        if (key.startsWith(_cacheKeyPrefix) ||
            key.startsWith(_manualCacheKeyPrefix) ||
            key.startsWith('netease_translation_')) {
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
      final prefs = await _getPrefs();
      final keys = prefs.getKeys();
      int totalSize = 0;
      int qqCount = 0;
      int neCount = 0;
      int lrclibCount = 0;
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
              } else if (cacheData.provider == 'lrclib') {
                lrclibCount++;
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

      final totalCount = qqCount + neCount + lrclibCount + otherCount;
      _logger.i('缓存统计 - 总数: $totalCount, QQ音乐: $qqCount, 网易云: $neCount, LRCLIB: $lrclibCount, 其他: $otherCount');
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

  Future<SharedPreferences> _getPrefs() async {
    final cached = _prefsCache;
    if (cached != null) {
      return cached;
    }
    final prefs = await SharedPreferences.getInstance();
    _prefsCache = prefs;
    return prefs;
  }
}
