import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';

import 'spotify_service.dart';

final _logger = Logger();

/// 采样数据点 - 用于计算添加速率
class _SamplePoint {
  final int offset;
  final DateTime addedAt;

  _SamplePoint(this.offset, this.addedAt);
}

/// 稀疏索引检查点 - "路标"系统的核心数据结构
class IndexCheckpoint {
  final int offset;      // 在资料库中的位置
  final DateTime date;   // 该位置的时间戳

  IndexCheckpoint({
    required this.offset,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'offset': offset,
    'date': date.toIso8601String(),
  };

  factory IndexCheckpoint.fromJson(Map<String, dynamic> json) {
    return IndexCheckpoint(
      offset: json['offset'] as int,
      date: DateTime.parse(json['date'] as String),
    );
  }
}

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
  static const String _indexCacheFileName = 'sparse_index_cache.json';
  static const Duration _cacheMaxAge = Duration(days: 1); // 缓存有效期1天
  static const Duration _indexMaxAge = Duration(days: 30); // 索引缓存30天
  List<Map<String, dynamic>>? _cachedTracks;
  DateTime? _cacheTimestamp;

  // 稀疏索引缓存
  List<IndexCheckpoint>? _sparseIndex;
  DateTime? _indexTimestamp;

  TimeMachineService(this._spotifyService);

  /// 设置当前用户ID（用于缓存隔离）
  void setActiveUser(String? userId) {
    if (_activeUserId != userId) {
      _activeUserId = userId;
      _cachedTracks = null;
      _cacheTimestamp = null;
      _sparseIndex = null;
      _indexTimestamp = null;
    }
  }

  String get _resolvedCacheFileName {
    if (_activeUserId == null) return _cacheFileName;
    final sanitizedId = _activeUserId!.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'saved_tracks_cache_$sanitizedId.json';
  }

  String get _resolvedIndexCacheFileName {
    if (_activeUserId == null) return _indexCacheFileName;
    final sanitizedId = _activeUserId!.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'sparse_index_cache_$sanitizedId.json';
  }

  Future<File> _getCacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_resolvedCacheFileName');
  }

  Future<File> _getIndexCacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_resolvedIndexCacheFileName');
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
  /// [useSmartSearch] 是否使用智能预测搜索（仅在无缓存时生效）
  Future<List<TimeMachineMemory>> getTodayMemories({
    DateTime? targetDate,
    int toleranceDays = 0,
    bool forceRefresh = false,
    bool useSmartSearch = true,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    final date = targetDate ?? DateTime.now();
    final currentYear = date.year;

    List<Map<String, dynamic>> tracks;

    // 检查是否有完整缓存
    final hasCache = !forceRefresh &&
        _cachedTracks != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheMaxAge;

    if (hasCache) {
      // 优先级1: 使用完整缓存（最快）
      _logger.d('使用完整缓存模式');
      tracks = await _getSavedTracks(
        forceRefresh: forceRefresh,
        onProgress: onProgress,
      );
    } else if (useSmartSearch) {
      // 计算目标日期范围（考虑容差）
      final targetStart = DateTime(
        currentYear - 10, // 搜索过去 10 年
        date.month,
        date.day,
      ).subtract(Duration(days: toleranceDays));

      final targetEnd = DateTime(
        currentYear - 1, // 最近一年
        date.month,
        date.day,
      ).add(Duration(days: toleranceDays + 1));

      // 优先级2: 尝试使用稀疏索引（次快）
      final sparseIndex = await _getSparseIndex();

      if (sparseIndex != null && sparseIndex.isNotEmpty) {
        _logger.i('使用稀疏索引查询模式');
        tracks = await _searchWithSparseIndex(
          targetStart: targetStart,
          targetEnd: targetEnd,
          index: sparseIndex,
          onProgress: onProgress,
        );

        // 后台构建完整缓存
        _buildCacheInBackground();
      } else {
        // 优先级3: 智能预测搜索（最后手段）
        _logger.i('使用智能预测搜索模式');
        tracks = await _getTracksSmartSearch(
          targetStart: targetStart,
          targetEnd: targetEnd,
          onProgress: onProgress,
        );

        // 后台构建索引和缓存
        _buildIndexInBackground();
        _buildCacheInBackground();
      }
    } else {
      // 禁用智能搜索，使用全量获取
      _logger.d('使用全量获取模式');
      tracks = await _getSavedTracks(
        forceRefresh: forceRefresh,
        onProgress: onProgress,
      );
    }

    final memories = <TimeMachineMemory>[];

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

  /// 后台构建完整缓存（不阻塞主线程）
  void _buildCacheInBackground() {
    if (_cachedTracks != null) return; // 已有缓存，无需构建

    _logger.i('启动后台缓存构建任务');

    // 异步执行，不等待结果
    Future.microtask(() async {
      try {
        final tracks = await _spotifyService.getAllUserSavedTracks();
        _cachedTracks = tracks;
        _cacheTimestamp = DateTime.now();
        await _saveToCache(tracks);
        _logger.i('后台缓存构建完成：${tracks.length} 首歌');
      } catch (e) {
        _logger.w('后台缓存构建失败: $e');
      }
    });
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
    bool useSmartSearch = true,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    final memories = await getTodayMemories(
      targetDate: targetDate,
      toleranceDays: toleranceDays,
      forceRefresh: forceRefresh,
      useSmartSearch: useSmartSearch,
      onProgress: onProgress,
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
    _sparseIndex = null;
    _indexTimestamp = null;
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
        _logger.i('Time machine cache cleared');
      }
      final indexFile = await _getIndexCacheFile();
      if (await indexFile.exists()) {
        await indexFile.delete();
        _logger.i('Sparse index cache cleared');
      }
    } catch (e) {
      _logger.w('Failed to clear cache: $e');
    }
  }

  // ============ 稀疏索引系统 ============

  /// 从磁盘加载稀疏索引
  Future<bool> _loadSparseIndex() async {
    try {
      final file = await _getIndexCacheFile();
      if (!await file.exists()) return false;

      final raw = await file.readAsString();
      if (raw.isEmpty) return false;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;

      final timestampStr = decoded['timestamp'] as String?;
      if (timestampStr == null) return false;

      final timestamp = DateTime.tryParse(timestampStr);
      if (timestamp == null) return false;

      // 检查索引是否过期
      if (DateTime.now().difference(timestamp) > _indexMaxAge) {
        _logger.d('Sparse index expired');
        return false;
      }

      final checkpointsRaw = decoded['checkpoints'] as List?;
      if (checkpointsRaw == null) return false;

      _sparseIndex = checkpointsRaw
          .whereType<Map>()
          .map((item) => IndexCheckpoint.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      _indexTimestamp = timestamp;

      _logger.i('Loaded sparse index with ${_sparseIndex!.length} checkpoints');
      return true;
    } catch (e) {
      _logger.w('Failed to load sparse index: $e');
      return false;
    }
  }

  /// 保存稀疏索引到磁盘
  Future<void> _saveSparseIndex(List<IndexCheckpoint> checkpoints) async {
    if (_activeUserId == null) {
      _logger.w('Cannot save sparse index without active user');
      return;
    }

    try {
      final file = await _getIndexCacheFile();
      final payload = {
        'timestamp': DateTime.now().toIso8601String(),
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
      _logger.i('Saved sparse index with ${checkpoints.length} checkpoints');
    } catch (e) {
      _logger.w('Failed to save sparse index: $e');
    }
  }

  /// 构建稀疏索引（采样间隔100首歌）
  Future<List<IndexCheckpoint>> _buildSparseIndex({
    int interval = 100,
    int maxCheckpoints = 100,
  }) async {
    final checkpoints = <IndexCheckpoint>[];

    try {
      _logger.i('开始构建稀疏索引：间隔 $interval 首歌');

      for (int offset = 0; offset < 10000; offset += interval) {
        if (checkpoints.length >= maxCheckpoints) break;

        final tracks = await _spotifyService.getUserSavedTracks(
          offset: offset,
          limit: 1,
        );

        if (tracks.isEmpty) break;

        final addedAtStr = tracks.first['added_at'] as String?;
        if (addedAtStr == null) continue;

        final date = DateTime.tryParse(addedAtStr);
        if (date == null) continue;

        checkpoints.add(IndexCheckpoint(offset: offset, date: date));
        _logger.d('索引点 ${checkpoints.length}: offset=$offset, date=${date.toIso8601String()}');

        // 防止速率限制
        await Future.delayed(const Duration(milliseconds: 150));
      }

      _logger.i('稀疏索引构建完成：${checkpoints.length} 个检查点');

      // 保存到缓存
      _sparseIndex = checkpoints;
      _indexTimestamp = DateTime.now();
      await _saveSparseIndex(checkpoints);

      return checkpoints;
    } catch (e) {
      _logger.w('构建稀疏索引失败: $e');
      return checkpoints;
    }
  }

  /// 检查并获取稀疏索引（如果不存在则构建）
  Future<List<IndexCheckpoint>?> _getSparseIndex() async {
    // 检查内存缓存
    if (_sparseIndex != null && _indexTimestamp != null) {
      if (DateTime.now().difference(_indexTimestamp!) < _indexMaxAge) {
        return _sparseIndex;
      }
    }

    // 尝试从磁盘加载
    if (await _loadSparseIndex()) {
      return _sparseIndex;
    }

    // 如果都没有，返回 null（不在这里构建，避免阻塞）
    return null;
  }

  /// 后台构建稀疏索引（不阻塞主线程）
  void _buildIndexInBackground() {
    if (_sparseIndex != null) return; // 已有索引，无需构建

    _logger.i('启动后台稀疏索引构建任务');

    Future.microtask(() async {
      try {
        await _buildSparseIndex();
      } catch (e) {
        _logger.w('后台索引构建失败: $e');
      }
    });
  }

  /// 使用稀疏索引查找目标日期范围的歌曲
  Future<List<Map<String, dynamic>>> _searchWithSparseIndex({
    required DateTime targetStart,
    required DateTime targetEnd,
    required List<IndexCheckpoint> index,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    _logger.i('使用稀疏索引查询：[$targetStart, $targetEnd]');

    try {
      // 二分查找：找到目标日期范围的起始位置
      int leftBound = _binarySearchCheckpoint(index, targetEnd, searchForStart: true);
      int rightBound = _binarySearchCheckpoint(index, targetStart, searchForStart: false);

      if (leftBound == -1 || rightBound == -1 || leftBound > rightBound) {
        _logger.w('索引中未找到目标范围');
        return [];
      }

      // 确定需要扫描的 offset 范围
      final startOffset = index[leftBound].offset;
      final endOffset = (rightBound + 1 < index.length)
          ? index[rightBound + 1].offset
          : index[rightBound].offset + 200;

      _logger.i('索引定位：检查点 [$leftBound, $rightBound], offset [$startOffset, $endOffset]');

      // 扫描这个范围内的所有歌曲
      final results = <Map<String, dynamic>>[];

      for (int offset = startOffset; offset <= endOffset && offset < 10000; offset += 50) {
        final tracks = await _spotifyService.getUserSavedTracks(
          offset: offset,
          limit: 50,
        );

        if (tracks.isEmpty) break;

        for (final track in tracks) {
          final addedAtStr = track['added_at'] as String?;
          if (addedAtStr == null) continue;

          final addedAt = DateTime.tryParse(addedAtStr);
          if (addedAt == null) continue;

          // 只添加在目标范围内的歌曲
          if (addedAt.isAfter(targetStart.subtract(const Duration(days: 1))) &&
              addedAt.isBefore(targetEnd.add(const Duration(days: 1)))) {
            results.add(track);
          }

          // 提前退出：如果已经太早了
          if (addedAt.isBefore(targetStart.subtract(const Duration(days: 30)))) {
            _logger.d('已超出范围，提前结束扫描');
            return results;
          }
        }

        onProgress?.call(results.length, null);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _logger.i('稀疏索引查询完成：找到 ${results.length} 首歌');
      return results;
    } catch (e) {
      _logger.w('稀疏索引查询失败: $e');
      return [];
    }
  }

  /// 二分查找检查点
  /// [searchForStart] = true: 找第一个 >= target 的位置
  /// [searchForStart] = false: 找最后一个 <= target 的位置
  int _binarySearchCheckpoint(List<IndexCheckpoint> checkpoints, DateTime target, {required bool searchForStart}) {
    if (checkpoints.isEmpty) return -1;

    int left = 0;
    int right = checkpoints.length - 1;
    int result = -1;

    while (left <= right) {
      int mid = (left + right) ~/ 2;
      final checkDate = checkpoints[mid].date;

      if (searchForStart) {
        // 找第一个 >= target 的（最新的相关检查点）
        if (checkDate.isAfter(target) || checkDate.isAtSameMomentAs(target)) {
          result = mid;
          right = mid - 1; // 继续向左找更早的
        } else {
          left = mid + 1;
        }
      } else {
        // 找最后一个 <= target 的（最旧的相关检查点）
        if (checkDate.isBefore(target) || checkDate.isAtSameMomentAs(target)) {
          result = mid;
          left = mid + 1; // 继续向右找更晚的
        } else {
          right = mid - 1;
        }
      }
    }

    return result;
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

  // ============ 智能预测优化算法 ============

  /// 采样用户资料库，计算歌曲添加速率
  /// 返回采样点列表，用于预测目标日期的位置
  Future<List<_SamplePoint>> _sampleLibrary({
    int sampleSize = 200,
    int sampleInterval = 100,
  }) async {
    final samples = <_SamplePoint>[];

    try {
      _logger.d('开始采样资料库：采样 $sampleSize 首歌，间隔 $sampleInterval');

      for (int offset = 0; offset < sampleSize; offset += sampleInterval) {
        final tracks = await _spotifyService.getUserSavedTracks(
          offset: offset,
          limit: 1, // 只需要第一首歌的时间戳
        );

        if (tracks.isEmpty) break;

        final addedAtStr = tracks.first['added_at'] as String?;
        if (addedAtStr == null) continue;

        final addedAt = DateTime.tryParse(addedAtStr);
        if (addedAt == null) continue;

        samples.add(_SamplePoint(offset, addedAt));
        _logger.d('采样点 ${samples.length}: offset=$offset, date=${addedAt.toIso8601String()}');

        // 防止速率限制
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _logger.i('采样完成：获得 ${samples.length} 个数据点');
    } catch (e) {
      _logger.w('采样失败: $e');
    }

    return samples;
  }

  /// 根据采样数据预测目标日期的 offset 位置
  /// 返回预测的 offset，如果无法预测则返回 null
  int? _predictOffset(List<_SamplePoint> samples, DateTime targetDate) {
    if (samples.length < 2) {
      _logger.w('采样点不足，无法进行预测');
      return null;
    }

    try {
      // 计算平均添加速率（歌曲/天）
      final first = samples.first;
      final last = samples.last;

      final daysDiff = first.addedAt.difference(last.addedAt).inDays;
      if (daysDiff <= 0) {
        _logger.w('时间范围无效，无法计算速率');
        return null;
      }

      final tracksDiff = last.offset - first.offset;
      final tracksPerDay = tracksDiff / daysDiff;

      _logger.d('计算速率：$tracksDiff 首歌 / $daysDiff 天 ≈ ${tracksPerDay.toStringAsFixed(2)} 首/天');

      // 预测目标日期的位置
      final daysFromNow = DateTime.now().difference(targetDate).inDays;
      final predictedOffset = (tracksPerDay * daysFromNow).round();

      _logger.i('预测结果：目标日期 $targetDate 应该在 offset $predictedOffset 附近');

      // 限制在合理范围内（0 到 10000）
      return predictedOffset.clamp(0, 10000);
    } catch (e) {
      _logger.w('预测计算失败: $e');
      return null;
    }
  }

  /// 使用智能预测优化的方式获取特定日期范围内的歌曲
  /// 适用于"一年前的今天"这种精确日期查询
  Future<List<Map<String, dynamic>>> _getTracksSmartSearch({
    required DateTime targetStart,
    required DateTime targetEnd,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    _logger.i('开始智能搜索：目标区间 [$targetStart, $targetEnd]');

    try {
      // 步骤 1: 采样资料库
      final samples = await _sampleLibrary(sampleSize: 200, sampleInterval: 100);

      if (samples.isEmpty) {
        _logger.w('采样失败，降级到全量获取');
        return await _spotifyService.getAllUserSavedTracks(onProgress: onProgress);
      }

      // 步骤 2: 预测目标位置
      final predictedOffset = _predictOffset(samples, targetStart);

      if (predictedOffset == null) {
        _logger.w('预测失败，降级到全量获取');
        return await _spotifyService.getAllUserSavedTracks(onProgress: onProgress);
      }

      // 步骤 3: 在预测位置附近搜索
      final searchRange = 200; // 在预测位置前后各搜索 200 首
      final startOffset = (predictedOffset - searchRange).clamp(0, 10000);
      final endOffset = (predictedOffset + searchRange).clamp(0, 10000);

      _logger.d('在 offset [$startOffset, $endOffset] 范围内搜索');

      final results = <Map<String, dynamic>>[];

      for (int offset = startOffset; offset <= endOffset; offset += 50) {
        final tracks = await _spotifyService.getUserSavedTracks(
          offset: offset,
          limit: 50,
        );

        if (tracks.isEmpty) break;

        // 检查是否在目标时间范围内
        for (final track in tracks) {
          final addedAtStr = track['added_at'] as String?;
          if (addedAtStr == null) continue;

          final addedAt = DateTime.tryParse(addedAtStr);
          if (addedAt == null) continue;

          // 如果歌曲在目标范围内，添加到结果
          if (addedAt.isAfter(targetStart.subtract(const Duration(days: 1))) &&
              addedAt.isBefore(targetEnd.add(const Duration(days: 1)))) {
            results.add(track);
          }

          // 如果已经超出范围（太早），可以提前退出
          if (addedAt.isBefore(targetStart.subtract(const Duration(days: 30)))) {
            _logger.d('已超出搜索范围，提前结束');
            return results;
          }
        }

        onProgress?.call(results.length, null);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _logger.i('智能搜索完成：找到 ${results.length} 首歌');
      return results;
    } catch (e) {
      _logger.w('智能搜索失败: $e，降级到全量获取');
      return await _spotifyService.getAllUserSavedTracks(onProgress: onProgress);
    }
  }
}
