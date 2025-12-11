import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';

import 'spotify_service.dart';

final _logger = Logger();

/// 表示一个"时光机"回忆项目
class TimeMachineMemory {
  final String trackId;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumCoverUrl;
  final DateTime addedAt;
  final int yearsAgo;
  final String trackUri;

  TimeMachineMemory({
    required this.trackId,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumCoverUrl,
    required this.addedAt,
    required this.yearsAgo,
    required this.trackUri,
  });

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'trackName': trackName,
        'artistName': artistName,
        'albumName': albumName,
        'albumCoverUrl': albumCoverUrl,
        'addedAt': addedAt.toIso8601String(),
        'yearsAgo': yearsAgo,
        'trackUri': trackUri,
      };

  factory TimeMachineMemory.fromJson(Map<String, dynamic> json) {
    return TimeMachineMemory(
      trackId: json['trackId'] as String,
      trackName: json['trackName'] as String,
      artistName: json['artistName'] as String,
      albumName: json['albumName'] as String,
      albumCoverUrl: json['albumCoverUrl'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
      yearsAgo: json['yearsAgo'] as int,
      trackUri: json['trackUri'] as String,
    );
  }
}

/// 时光机服务 - 处理"去年今日"等音乐回忆功能
class TimeMachineService {
  final SpotifyAuthService _spotifyService;
  String? _activeUserId;

  // 缓存相关
  static const String _cacheFileName = 'saved_tracks_cache.json';
  static const Duration _cacheMaxAge = Duration(days: 1); // 缓存有效期1天
  List<Map<String, dynamic>>? _cachedTracks;
  DateTime? _cacheTimestamp;

  TimeMachineService(this._spotifyService);

  /// 设置当前用户ID（用于缓存隔离）
  void setActiveUser(String? userId) {
    if (_activeUserId != userId) {
      _activeUserId = userId;
      _cachedTracks = null;
      _cacheTimestamp = null;
    }
  }

  String get _resolvedCacheFileName {
    if (_activeUserId == null) return _cacheFileName;
    final sanitizedId = _activeUserId!.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'saved_tracks_cache_$sanitizedId.json';
  }

  Future<File> _getCacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_resolvedCacheFileName');
  }

  /// 从缓存加载数据
  Future<bool> _loadFromCache() async {
    try {
      final file = await _getCacheFile();
      if (!await file.exists()) return false;

      final raw = await file.readAsString();
      if (raw.isEmpty) return false;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;

      final timestampStr = decoded['timestamp'] as String?;
      if (timestampStr == null) return false;

      final timestamp = DateTime.tryParse(timestampStr);
      if (timestamp == null) return false;

      // 检查缓存是否过期
      if (DateTime.now().difference(timestamp) > _cacheMaxAge) {
        _logger.d('Time machine cache expired');
        return false;
      }

      final tracksRaw = decoded['tracks'] as List?;
      if (tracksRaw == null) return false;

      _cachedTracks = tracksRaw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _cacheTimestamp = timestamp;

      _logger.i('Loaded ${_cachedTracks!.length} tracks from time machine cache');
      return true;
    } catch (e) {
      _logger.w('Failed to load time machine cache: $e');
      return false;
    }
  }

  /// 保存数据到缓存
  Future<void> _saveToCache(List<Map<String, dynamic>> tracks) async {
    if (_activeUserId == null) {
      _logger.w('Cannot save time machine cache without active user');
      return;
    }

    try {
      final file = await _getCacheFile();
      final payload = {
        'timestamp': DateTime.now().toIso8601String(),
        'tracks': tracks,
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
      _logger.i('Saved ${tracks.length} tracks to time machine cache');
    } catch (e) {
      _logger.w('Failed to save time machine cache: $e');
    }
  }

  /// 获取用户收藏的所有曲目（带缓存）
  Future<List<Map<String, dynamic>>> _getSavedTracks({
    bool forceRefresh = false,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    // 检查内存缓存
    if (!forceRefresh && _cachedTracks != null && _cacheTimestamp != null) {
      if (DateTime.now().difference(_cacheTimestamp!) < _cacheMaxAge) {
        return _cachedTracks!;
      }
    }

    // 尝试从磁盘缓存加载
    if (!forceRefresh && await _loadFromCache()) {
      return _cachedTracks!;
    }

    // 从API获取
    final tracks = await _spotifyService.getAllUserSavedTracks(
      onProgress: onProgress,
    );

    _cachedTracks = tracks;
    _cacheTimestamp = DateTime.now();
    await _saveToCache(tracks);

    return tracks;
  }

  /// 获取"今日回忆" - 历年同一天添加的歌曲
  ///
  /// [targetDate] 目标日期，默认为今天
  /// [toleranceDays] 日期容差，默认为0（精确匹配月日），可设为1-3扩大范围
  Future<List<TimeMachineMemory>> getTodayMemories({
    DateTime? targetDate,
    int toleranceDays = 0,
    bool forceRefresh = false,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    final date = targetDate ?? DateTime.now();
    final tracks = await _getSavedTracks(
      forceRefresh: forceRefresh,
      onProgress: onProgress,
    );

    final memories = <TimeMachineMemory>[];
    final currentYear = date.year;

    for (final item in tracks) {
      final addedAtStr = item['added_at'] as String?;
      if (addedAtStr == null) continue;

      final addedAt = DateTime.tryParse(addedAtStr);
      if (addedAt == null) continue;

      // 检查是否是历年的"今天"（排除今年）
      if (addedAt.year >= currentYear) continue;

      // 计算日期差异
      final daysDiff = _dayOfYearDifference(date, addedAt);
      if (daysDiff > toleranceDays) continue;

      final track = item['track'] as Map<String, dynamic>?;
      if (track == null) continue;

      final trackId = track['id'] as String?;
      final trackName = track['name'] as String?;
      final artists = track['artists'] as List?;
      final album = track['album'] as Map<String, dynamic>?;

      if (trackId == null || trackName == null) continue;

      final artistName = artists?.isNotEmpty == true
          ? (artists!.first as Map<String, dynamic>)['name'] as String? ?? 'Unknown'
          : 'Unknown';

      final albumName = album?['name'] as String? ?? 'Unknown Album';
      final albumImages = album?['images'] as List?;
      final albumCoverUrl = albumImages?.isNotEmpty == true
          ? (albumImages!.first as Map<String, dynamic>)['url'] as String?
          : null;

      memories.add(TimeMachineMemory(
        trackId: trackId,
        trackName: trackName,
        artistName: artistName,
        albumName: albumName,
        albumCoverUrl: albumCoverUrl,
        addedAt: addedAt,
        yearsAgo: currentYear - addedAt.year,
        trackUri: 'spotify:track:$trackId',
      ));
    }

    // 按年份排序（最近的年份优先）
    memories.sort((a, b) => a.yearsAgo.compareTo(b.yearsAgo));

    return memories;
  }

  /// 计算两个日期在一年中的天数差（忽略年份）
  int _dayOfYearDifference(DateTime date1, DateTime date2) {
    // 将两个日期都放到同一年来比较
    final d1 = DateTime(2000, date1.month, date1.day);
    final d2 = DateTime(2000, date2.month, date2.day);
    return (d1.difference(d2).inDays).abs();
  }

  /// 按日期范围获取歌曲
  ///
  /// 用于"时光机"功能，让用户选择一个日期范围
  Future<List<TimeMachineMemory>> getTracksByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    bool forceRefresh = false,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    final tracks = await _getSavedTracks(
      forceRefresh: forceRefresh,
      onProgress: onProgress,
    );

    final memories = <TimeMachineMemory>[];
    final now = DateTime.now();

    for (final item in tracks) {
      final addedAtStr = item['added_at'] as String?;
      if (addedAtStr == null) continue;

      final addedAt = DateTime.tryParse(addedAtStr);
      if (addedAt == null) continue;

      // 检查是否在日期范围内
      if (addedAt.isBefore(startDate) || addedAt.isAfter(endDate)) continue;

      final track = item['track'] as Map<String, dynamic>?;
      if (track == null) continue;

      final trackId = track['id'] as String?;
      final trackName = track['name'] as String?;
      final artists = track['artists'] as List?;
      final album = track['album'] as Map<String, dynamic>?;

      if (trackId == null || trackName == null) continue;

      final artistName = artists?.isNotEmpty == true
          ? (artists!.first as Map<String, dynamic>)['name'] as String? ?? 'Unknown'
          : 'Unknown';

      final albumName = album?['name'] as String? ?? 'Unknown Album';
      final albumImages = album?['images'] as List?;
      final albumCoverUrl = albumImages?.isNotEmpty == true
          ? (albumImages!.first as Map<String, dynamic>)['url'] as String?
          : null;

      memories.add(TimeMachineMemory(
        trackId: trackId,
        trackName: trackName,
        artistName: artistName,
        albumName: albumName,
        albumCoverUrl: albumCoverUrl,
        addedAt: addedAt,
        yearsAgo: now.year - addedAt.year,
        trackUri: 'spotify:track:$trackId',
      ));
    }

    // 按添加时间排序（最新的优先）
    memories.sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return memories;
  }

  /// 获取按年份分组的"今日回忆"
  Future<Map<int, List<TimeMachineMemory>>> getTodayMemoriesGroupedByYear({
    DateTime? targetDate,
    int toleranceDays = 1,
    bool forceRefresh = false,
  }) async {
    final memories = await getTodayMemories(
      targetDate: targetDate,
      toleranceDays: toleranceDays,
      forceRefresh: forceRefresh,
    );

    final grouped = <int, List<TimeMachineMemory>>{};
    for (final memory in memories) {
      grouped.putIfAbsent(memory.yearsAgo, () => []).add(memory);
    }

    return grouped;
  }

  /// 清除缓存
  Future<void> clearCache() async {
    _cachedTracks = null;
    _cacheTimestamp = null;
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
        _logger.i('Time machine cache cleared');
      }
    } catch (e) {
      _logger.w('Failed to clear time machine cache: $e');
    }
  }

  /// 检查是否有今日回忆
  Future<bool> hasTodayMemories({int toleranceDays = 1}) async {
    try {
      final memories = await getTodayMemories(toleranceDays: toleranceDays);
      return memories.isNotEmpty;
    } catch (e) {
      _logger.w('Failed to check today memories: $e');
      return false;
    }
  }
}
