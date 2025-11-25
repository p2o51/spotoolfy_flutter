import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logger/logger.dart';

/// 图片预加载管理器
///
/// 功能:
/// - 智能图片预加载队列
/// - LRU 缓存管理
/// - 并发控制
/// - 优先级队列
class ImagePreloadManager {
  static final ImagePreloadManager _instance = ImagePreloadManager._internal();
  factory ImagePreloadManager() => _instance;
  ImagePreloadManager._internal();

  final Logger _logger = Logger();

  /// 已缓存的图片 URL（LRU 缓存）
  final LinkedHashMap<String, DateTime> _cachedUrls = LinkedHashMap();

  /// 正在加载的图片 URL
  final Set<String> _loadingUrls = {};

  /// 预加载队列（优先级队列）
  final List<_PreloadTask> _queue = [];

  /// 最大缓存数量
  static const int _maxCacheSize = 100;

  /// 最大并发加载数
  static const int _maxConcurrent = 3;

  /// 当前并发数
  int _currentConcurrent = 0;

  /// 检查图片是否已缓存
  bool isCached(String? url) {
    if (url == null || url.isEmpty) return false;
    return _cachedUrls.containsKey(url);
  }

  /// 预加载单张图片
  ///
  /// [priority] 优先级，数值越大越优先
  Future<void> preload(
    String? url,
    BuildContext context, {
    int priority = 0,
  }) async {
    if (url == null || url.isEmpty) return;
    if (_cachedUrls.containsKey(url)) return;
    if (_loadingUrls.contains(url)) return;

    // 添加到队列
    _queue.add(_PreloadTask(url: url, priority: priority, context: context));
    _queue.sort((a, b) => b.priority.compareTo(a.priority));

    // 尝试处理队列
    _processQueue();
  }

  /// 批量预加载图片
  ///
  /// [urls] 图片 URL 列表
  /// [basePriority] 基础优先级，列表越靠前优先级越高
  Future<void> preloadBatch(
    List<String?> urls,
    BuildContext context, {
    int basePriority = 0,
  }) async {
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      if (url != null && url.isNotEmpty) {
        // 列表越靠前优先级越高
        await preload(url, context, priority: basePriority + (urls.length - i));
      }
    }
  }

  /// 预加载当前播放相关的图片
  ///
  /// 包括：当前曲目、上一首、下一首、队列前几首
  Future<void> preloadPlaybackImages({
    required BuildContext context,
    String? currentAlbumArt,
    String? previousAlbumArt,
    String? nextAlbumArt,
    List<String?>? queueAlbumArts,
  }) async {
    // 收集所有需要预加载的任务，然后一次性添加到队列
    // 这样避免在 async gaps 中使用 context
    final tasks = <({String url, int priority})>[];

    // 当前曲目最高优先级
    if (currentAlbumArt != null) {
      tasks.add((url: currentAlbumArt, priority: 100));
    }

    // 下一首次高优先级
    if (nextAlbumArt != null) {
      tasks.add((url: nextAlbumArt, priority: 90));
    }

    // 上一首
    if (previousAlbumArt != null) {
      tasks.add((url: previousAlbumArt, priority: 80));
    }

    // 队列中的图片
    if (queueAlbumArts != null) {
      for (var i = 0; i < queueAlbumArts.length && i < 5; i++) {
        final url = queueAlbumArts[i];
        if (url != null) {
          tasks.add((url: url, priority: 70 - i * 10));
        }
      }
    }

    // 同步添加所有任务
    for (final task in tasks) {
      preload(task.url, context, priority: task.priority);
    }
  }

  void _processQueue() {
    while (_currentConcurrent < _maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);

      // 跳过已缓存或正在加载的
      if (_cachedUrls.containsKey(task.url) || _loadingUrls.contains(task.url)) {
        continue;
      }

      _currentConcurrent++;
      _loadingUrls.add(task.url);

      _loadImage(task).then((_) {
        _currentConcurrent--;
        _loadingUrls.remove(task.url);
        _processQueue();
      }).catchError((e) {
        _currentConcurrent--;
        _loadingUrls.remove(task.url);
        _logger.w('预加载图片失败: ${task.url}, 错误: $e');
        _processQueue();
      });
    }
  }

  Future<void> _loadImage(_PreloadTask task) async {
    if (!task.context.mounted) return;

    try {
      final imageProvider = CachedNetworkImageProvider(task.url);
      await precacheImage(imageProvider, task.context);

      // 添加到缓存
      _addToCache(task.url);
    } catch (e) {
      rethrow;
    }
  }

  void _addToCache(String url) {
    // 如果已存在，先移除（为了更新 LRU 顺序）
    _cachedUrls.remove(url);

    // 添加到末尾（最近使用）
    _cachedUrls[url] = DateTime.now();

    // 如果超出最大缓存，移除最旧的
    while (_cachedUrls.length > _maxCacheSize) {
      _cachedUrls.remove(_cachedUrls.keys.first);
    }
  }

  /// 标记 URL 为已使用（更新 LRU 顺序）
  void markUsed(String? url) {
    if (url == null || url.isEmpty) return;
    if (_cachedUrls.containsKey(url)) {
      _cachedUrls.remove(url);
      _cachedUrls[url] = DateTime.now();
    }
  }

  /// 清除缓存
  void clearCache() {
    _cachedUrls.clear();
    _queue.clear();
  }

  /// 获取缓存统计
  ({int cached, int loading, int queued}) get stats => (
        cached: _cachedUrls.length,
        loading: _loadingUrls.length,
        queued: _queue.length,
      );

  /// 取消所有待处理的预加载
  void cancelAll() {
    _queue.clear();
  }
}

class _PreloadTask {
  final String url;
  final int priority;
  final BuildContext context;

  _PreloadTask({
    required this.url,
    required this.priority,
    required this.context,
  });
}

/// 专辑封面预加载策略
///
/// 根据播放状态智能预加载相关专辑封面
class AlbumArtPreloadStrategy {
  final ImagePreloadManager _manager = ImagePreloadManager();

  /// 从曲目数据中提取封面 URL
  String? extractAlbumArt(Map<String, dynamic>? track) {
    if (track == null) return null;

    // 尝试从 item 中获取
    final item = track['item'] as Map<String, dynamic>?;
    if (item != null) {
      return _getAlbumArtFromItem(item);
    }

    // 直接从 track 获取（队列中的格式）
    return _getAlbumArtFromItem(track);
  }

  String? _getAlbumArtFromItem(Map<String, dynamic> item) {
    final album = item['album'] as Map<String, dynamic>?;
    if (album == null) return null;

    final images = album['images'] as List?;
    if (images == null || images.isEmpty) return null;

    // 优先选择中等尺寸的图片（通常是第二张）
    if (images.length >= 2) {
      final mediumImage = images[1] as Map<String, dynamic>?;
      if (mediumImage != null && mediumImage['url'] != null) {
        return mediumImage['url'] as String;
      }
    }

    // 否则返回第一张
    final firstImage = images[0] as Map<String, dynamic>?;
    return firstImage?['url'] as String?;
  }

  /// 预加载播放相关的封面
  Future<void> preloadForPlayback({
    required BuildContext context,
    Map<String, dynamic>? currentTrack,
    Map<String, dynamic>? nextTrack,
    List<Map<String, dynamic>>? upcomingTracks,
  }) async {
    final queueArts = upcomingTracks
        ?.take(5)
        .map((t) => extractAlbumArt(t))
        .toList();

    await _manager.preloadPlaybackImages(
      context: context,
      currentAlbumArt: extractAlbumArt(currentTrack),
      nextAlbumArt: extractAlbumArt(nextTrack),
      queueAlbumArts: queueArts,
    );
  }
}
