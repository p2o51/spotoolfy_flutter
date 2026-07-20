import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../utils/lru_cache.dart';

final _logger = Logger();

/// Spotify 缓存管理器
///
/// 职责:
/// - 管理图片预加载缓存
/// - 管理专辑和播放列表详情缓存
/// - 提供缓存清理和状态查询
class SpotifyCacheManager {
  // 缓存配置
  static const int imageCacheMaxSize = 200;
  static const int albumCacheMaxSize = 50;
  static const int playlistCacheMaxSize = 30;

  // 使用 LRU 缓存限制内存使用
  final LruCache<String, String> _imageCache =
      LruCache(maxSize: imageCacheMaxSize);
  final LruCache<String, Map<String, dynamic>> _albumCache =
      LruCache(maxSize: albumCacheMaxSize);
  final LruCache<String, Map<String, dynamic>> _playlistCache =
      LruCache(maxSize: playlistCacheMaxSize);

  // ============ 图片缓存 ============

  /// 检查图片是否已缓存
  bool isImageCached(String imageUrl) => _imageCache.containsKey(imageUrl);

  /// 标记图片为已缓存
  void markImageCached(String imageUrl) {
    _imageCache.put(imageUrl, imageUrl);
  }

  /// 预加载图片
  Future<void> preloadImage(String? imageUrl, BuildContext context) async {
    if (imageUrl == null || isImageCached(imageUrl)) return;

    try {
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      await precacheImage(imageProvider, context);
      markImageCached(imageUrl);
    } catch (e) {
      _logger.w('预加载图片失败: $e');
    }
  }

  /// 批量预加载图片
  Future<void> preloadImages(
    List<String> imageUrls,
    BuildContext context,
  ) async {
    final uncachedUrls =
        imageUrls.where((url) => !isImageCached(url)).toList();

    // ⚡ Bolt: 性能优化 - 并发预加载图片，减少整体等待时间
    await Future.wait(
      uncachedUrls.map((url) => preloadImage(url, context)),
    );
  }

  /// 清除图片缓存
  void clearImageCache() => _imageCache.clear();

  // ============ 专辑缓存 ============

  /// 检查专辑是否已缓存
  bool isAlbumCached(String albumId) => _albumCache.containsKey(albumId);

  /// 获取缓存的专辑
  Map<String, dynamic>? getCachedAlbum(String albumId) =>
      _albumCache.get(albumId);

  /// 缓存专辑详情
  void cacheAlbum(String albumId, Map<String, dynamic> albumData) {
    _albumCache.put(albumId, albumData);
  }

  /// 清除专辑缓存
  void clearAlbumCache() => _albumCache.clear();

  // ============ 播放列表缓存 ============

  /// 检查播放列表是否已缓存
  bool isPlaylistCached(String playlistId) =>
      _playlistCache.containsKey(playlistId);

  /// 获取缓存的播放列表
  Map<String, dynamic>? getCachedPlaylist(String playlistId) =>
      _playlistCache.get(playlistId);

  /// 缓存播放列表详情
  void cachePlaylist(String playlistId, Map<String, dynamic> playlistData) {
    _playlistCache.put(playlistId, playlistData);
  }

  /// 清除播放列表缓存
  void clearPlaylistCache() => _playlistCache.clear();

  // ============ 通用操作 ============

  /// 清除所有缓存（登出时调用）
  void clearAllCaches() {
    // 图片缓存保留，因为跨会话仍可复用
    clearAlbumCache();
    clearPlaylistCache();
  }

  /// 获取缓存统计信息
  Map<String, int> getCacheStats() {
    return {
      'images': _imageCache.length,
      'albums': _albumCache.length,
      'playlists': _playlistCache.length,
    };
  }

  @override
  String toString() {
    final stats = getCacheStats();
    return 'SpotifyCacheManager(images: ${stats['images']}/$imageCacheMaxSize, '
        'albums: ${stats['albums']}/$albumCacheMaxSize, '
        'playlists: ${stats['playlists']}/$playlistCacheMaxSize)';
  }
}
