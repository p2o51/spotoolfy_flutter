import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/spotify_service.dart';
import '../main.dart';

/// 播放模式枚举
enum PlayMode {
  singleRepeat, // 单曲循环（曲循环+顺序播放）
  sequential, // 顺序播放（列表循环+顺序播放）
  shuffle // 随机播放（列表循环+随机播放）
}

/// 播放控制管理器 - 负责播放相关操作
///
/// 职责:
/// - 管理播放状态刷新
/// - 处理播放/暂停/跳转
/// - 管理播放队列
/// - 管理播放模式
class SpotifyPlaybackManager {
  final Logger logger;
  final Future<T> Function<T>(Future<T> Function() job) guard;
  final SpotifyAuthService Function() getService;
  final VoidCallback notifyListeners;

  // 播放状态
  Map<String, dynamic>? currentTrack;
  bool? isCurrentTrackSaved;
  Map<String, dynamic>? previousTrack;
  Map<String, dynamic>? nextTrack;
  List<Map<String, dynamic>> upcomingTracks = [];

  // 定时器
  Timer? _refreshTimer;
  Timer? _progressTimer;
  DateTime? _lastProgressUpdate;
  DateTime? _lastProgressNotify;
  DateTime? _lastQueueRefresh;

  // 状态标志
  bool _isSkipping = false;
  bool _isRefreshTickRunning = false;
  bool _isQueuePrefetchRunning = false;
  PlayMode _currentMode = PlayMode.sequential;

  // 图片缓存
  final Map<String, String> _imageCache = {};

  // 常量
  static const Duration _progressTimerInterval = Duration(milliseconds: 500);
  static const Duration _refreshTickInterval = Duration(seconds: 3);
  static const Duration _queueRefreshInterval = Duration(seconds: 9);
  static const int _progressNotifyIntervalMs = 500;

  SpotifyPlaybackManager({
    required this.logger,
    required this.guard,
    required this.getService,
    required this.notifyListeners,
  });

  // Getters
  PlayMode get currentMode => _currentMode;
  bool get isSkipping => _isSkipping;
  DateTime? get lastQueueRefresh => _lastQueueRefresh;

  /// 检查是否应该刷新队列
  bool shouldRefreshQueue() {
    return _lastQueueRefresh == null ||
        DateTime.now().difference(_lastQueueRefresh!) >= _queueRefreshInterval;
  }

  /// 标记队列已刷新
  void markQueueRefreshed() {
    _lastQueueRefresh = DateTime.now();
  }

  /// 启动轨道刷新定时器
  void startTrackRefresh({
    required Future<void> Function() onRefreshTrack,
    required Future<void> Function() onRefreshDevices,
    required Future<void> Function() onRefreshQueue,
    required bool Function() shouldRefreshDevices,
    required VoidCallback markDevicesRefreshed,
  }) {
    logger.d('startTrackRefresh: 启动定时器');

    Future.microtask(() async {
      try {
        logger.d('startTrackRefresh (microtask): 获取初始数据...');
        await onRefreshTrack();
        await onRefreshDevices();
        await onRefreshQueue();
        markQueueRefreshed();
        markDevicesRefreshed();
        logger.i('startTrackRefresh (microtask): 初始数据获取完成');
      } catch (e) {
        logger.e('startTrackRefresh (microtask): 获取初始数据失败', error: e);
      } finally {
        // 确保 _lastProgressUpdate 有合理的值
        if (currentTrack != null &&
            currentTrack!['is_playing'] == true &&
            _lastProgressUpdate == null) {
          _lastProgressUpdate = DateTime.now();
        }

        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(_refreshTickInterval, (_) {
          if (_isSkipping) {
            logger.t('_refreshTimer tick: 跳过 (_isSkipping=true)');
            return;
          }
          if (_isRefreshTickRunning) {
            logger.t('_refreshTimer tick: 跳过 (上次刷新仍在运行)');
            return;
          }
          _isRefreshTickRunning = true;
          Future(() async {
            try {
              logger.t('_refreshTimer tick: 刷新曲目、设备和队列');
              await onRefreshTrack();

              if (shouldRefreshDevices()) {
                await onRefreshDevices();
                markDevicesRefreshed();
              }

              if (shouldRefreshQueue()) {
                await onRefreshQueue();
                markQueueRefreshed();
              }
            } finally {
              _isRefreshTickRunning = false;
            }
          });
        });

        _progressTimer?.cancel();
        _progressTimer = Timer.periodic(_progressTimerInterval, (_) {
          _updateProgress();
        });

        logger.d('startTrackRefresh: 定时器已启动');
      }
    });
  }

  /// 更新播放进度
  void _updateProgress() {
    if (_isSkipping || currentTrack == null) {
      return;
    }

    if (currentTrack!['is_playing'] == true) {
      final now = DateTime.now();
      if (_lastProgressUpdate != null) {
        final elapsed = now.difference(_lastProgressUpdate!).inMilliseconds;
        if (elapsed > 0) {
          final oldProgress = currentTrack!['progress_ms'] as int;
          final duration = currentTrack!['item']?['duration_ms'] as int?;
          int newProgressValue = oldProgress + elapsed;

          if (duration != null) {
            newProgressValue = newProgressValue.clamp(0, duration);
          } else {
            newProgressValue = newProgressValue > 0 ? newProgressValue : 0;
          }

          if (currentTrack!['progress_ms'] != newProgressValue) {
            currentTrack!['progress_ms'] = newProgressValue;

            final shouldNotify = _lastProgressNotify == null ||
                now.difference(_lastProgressNotify!).inMilliseconds >=
                    _progressNotifyIntervalMs;
            if (shouldNotify) {
              notifyListeners();
              _lastProgressNotify = now;
            }
          }
        }
      }
      _lastProgressUpdate = now;
    } else if (currentTrack!['is_playing'] == false) {
      _lastProgressUpdate = DateTime.now();
    }
  }

  /// 停止定时器
  void stopTimers() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// 刷新当前曲目
  Future<void> refreshCurrentTrack({
    required Future<Map<String, dynamic>?> Function() fetchTrack,
    required Future<bool> Function(String trackId) checkTrackSaved,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> context)
        enrichContext,
    required Future<void> Function(Map<String, dynamic> enrichedContext)
        savePlayContext,
  }) async {
    try {
      final track = await fetchTrack();

      final debugTrackName = track?['item']?['name'];
      final debugArtist =
          (track?['item']?['artists'] is List && track!['item']['artists'].isNotEmpty)
              ? track['item']['artists'][0]['name']
              : null;
      logger.d(
          'refreshCurrentTrack: received ${debugTrackName ?? 'unknown track'} by ${debugArtist ?? 'unknown'} (progress ${track?['progress_ms'] ?? 'n/a'})');

      if (track != null) {
        final isPlayingFromApi = track['is_playing'] as bool?;
        final progressFromApi = track['progress_ms'] as int?;
        final newId = track['item']?['id'];
        final newContextUri = track['context']?['uri'];

        final oldId = currentTrack?['item']?['id'];
        final oldIsPlaying = currentTrack?['is_playing'] as bool?;
        final oldContextUri = currentTrack?['context']?['uri'];
        final oldProgressMs = currentTrack?['progress_ms'] as int?;

        bool needsNotify = false;
        const int kProgressJumpThreshold = 1500;

        final bool coreTrackInfoChanged = currentTrack == null ||
            newId != oldId ||
            (isPlayingFromApi != null && isPlayingFromApi != oldIsPlaying) ||
            newContextUri != oldContextUri;

        bool significantProgressJump = false;
        if (progressFromApi != null && oldProgressMs != null) {
          significantProgressJump =
              (progressFromApi - oldProgressMs).abs() > kProgressJumpThreshold;
        } else if (progressFromApi != null &&
            oldProgressMs == null &&
            currentTrack != null) {
          significantProgressJump = true;
        } else if (progressFromApi != null && currentTrack == null) {
          significantProgressJump = true;
        }

        if (coreTrackInfoChanged || significantProgressJump) {
          Map<String, dynamic>? previousContext;
          if (currentTrack != null &&
              currentTrack!['context'] is Map<String, dynamic>) {
            previousContext = Map<String, dynamic>.from(
                currentTrack!['context'] as Map<String, dynamic>);
          }

          currentTrack = Map<String, dynamic>.from(track);
          currentTrack!['progress_ms'] = progressFromApi ?? oldProgressMs ?? 0;

          if (newContextUri == null &&
              previousContext != null &&
              oldContextUri != null &&
              newId == oldId) {
            currentTrack!['context'] = previousContext;
          }

          if (newId != oldId ||
              (currentTrack!['is_playing'] == true && progressFromApi != null) ||
              significantProgressJump) {
            _lastProgressUpdate = DateTime.now();
            _lastProgressNotify = null;
          }
          needsNotify = true;

          if (newId != oldId && newId != null) {
            try {
              isCurrentTrackSaved = await checkTrackSaved(newId);
              if (track['context'] != null) {
                final enrichedContext = await enrichContext(
                    Map<String, dynamic>.from(track['context']));
                currentTrack!['context'] = enrichedContext;
                await savePlayContext(enrichedContext);
              }
            } catch (e) {
              logger.e('refreshCurrentTrack: 获取保存状态或丰富上下文失败', error: e);
            }
          } else if (newContextUri != null) {
            await _handleContextEnrichment(
              track: track,
              previousContext: previousContext,
              newContextUri: newContextUri,
              enrichContext: enrichContext,
            );
          }
        } else if (currentTrack != null &&
            progressFromApi != null &&
            progressFromApi != oldProgressMs) {
          currentTrack!['progress_ms'] = progressFromApi;
          if (currentTrack!['is_playing'] == true) {
            _lastProgressUpdate = DateTime.now();
          }
          needsNotify = true;
        }

        if (needsNotify) {
          notifyListeners();
          _lastProgressNotify = DateTime.now();
        }
      } else if (currentTrack != null) {
        currentTrack = null;
        isCurrentTrackSaved = null;
        _lastProgressNotify = null;
        notifyListeners();
      }
    } catch (e) {
      logger.e('Error in refreshCurrentTrack: $e');
      rethrow;
    }
  }

  Future<void> _handleContextEnrichment({
    required Map<String, dynamic> track,
    required Map<String, dynamic>? previousContext,
    required String newContextUri,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> context)
        enrichContext,
  }) async {
    Map<String, dynamic>? contextFromApi;
    if (currentTrack!['context'] is Map<String, dynamic>) {
      contextFromApi = Map<String, dynamic>.from(
          currentTrack!['context'] as Map<String, dynamic>);
    }

    final hasContextName = contextFromApi != null &&
        (contextFromApi['name'] is String) &&
        (contextFromApi['name'] as String).trim().isNotEmpty;

    if (!hasContextName) {
      if (track['context'] is Map<String, dynamic>) {
        try {
          final enrichedContext = await enrichContext(
              Map<String, dynamic>.from(track['context'] as Map<String, dynamic>));
          currentTrack!['context'] = enrichedContext;
        } catch (e) {
          logger.w('refreshCurrentTrack: 丰富上下文元数据失败', error: e);
        }
      }

      if ((currentTrack!['context']?['name'] as String?)?.isEmpty ?? true) {
        if (previousContext != null &&
            previousContext['uri'] == newContextUri &&
            (previousContext['name'] as String?)?.isNotEmpty == true) {
          currentTrack!['context'] = previousContext;
        } else if (contextFromApi != null) {
          currentTrack!['context'] = contextFromApi;
        }
      }
    } else {
      currentTrack!['context'] = contextFromApi;
    }
  }

  /// 刷新播放队列
  Future<void> refreshPlaybackQueue() async {
    try {
      final queue = await guard(() => getService().getPlaybackQueue());
      final rawQueue = List<Map<String, dynamic>>.from(queue['queue'] ?? []);

      final queueChanged = _queuesDiffer(rawQueue);
      if (!queueChanged) {
        return;
      }

      upcomingTracks = rawQueue;
      nextTrack = upcomingTracks.isNotEmpty ? upcomingTracks.first : null;

      if (!_isQueuePrefetchRunning) {
        _isQueuePrefetchRunning = true;
        Future(() async {
          try {
            await _cacheQueueImages();
          } finally {
            _isQueuePrefetchRunning = false;
          }
        });
      }

      markQueueRefreshed();
      notifyListeners();
    } catch (e) {
      logger.e('刷新播放队列失败: $e');
      upcomingTracks = [];
      nextTrack = null;
      notifyListeners();
      rethrow;
    }
  }

  bool _queuesDiffer(List<Map<String, dynamic>> newQueue) {
    if (newQueue.length != upcomingTracks.length) {
      return true;
    }

    for (var i = 0; i < math.min(newQueue.length, upcomingTracks.length); i++) {
      final newUri = newQueue[i]['uri'];
      final oldUri = upcomingTracks[i]['uri'];
      if (newUri != oldUri) {
        return true;
      }
    }
    return false;
  }

  Future<void> _cacheQueueImages() async {
    try {
      final imagesToCache = upcomingTracks
          .map((track) => track['album']?['images']?[0]?['url'] as String?)
          .whereType<String>()
          .where((url) => !_imageCache.containsKey(url))
          .take(6)
          .toList();

      for (final imageUrl in imagesToCache) {
        await _preloadImage(imageUrl);
      }
    } catch (e) {
      logger.w('批量缓存队列图片失败: $e');
    }
  }

  Future<void> _preloadImage(String? imageUrl) async {
    if (imageUrl == null || _imageCache.containsKey(imageUrl)) return;
    if (navigatorKey.currentContext == null) return;

    try {
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      await precacheImage(imageProvider, navigatorKey.currentContext!);
      _imageCache[imageUrl] = imageUrl;
    } catch (e) {
      logger.w('预加载图片失败: $e');
    }
  }

  /// 播放/暂停切换
  Future<void> togglePlayPause() async {
    logger.d('togglePlayPause: 开始执行');

    try {
      await guard(() => getService().togglePlayPause());

      // 更新本地状态
      if (currentTrack != null) {
        final isCurrentlyPlaying = currentTrack!['is_playing'] ?? false;
        currentTrack!['is_playing'] = !isCurrentlyPlaying;
      }

      notifyListeners();
    } catch (e) {
      logger.e('togglePlayPause: 捕获错误', error: e);
      rethrow;
    }
  }

  /// 跳转到指定位置
  Future<void> seekToPosition(int positionMs) async {
    logger.d('seekToPosition: 开始执行，目标位置: $positionMs ms');

    try {
      _isSkipping = true;
      await guard(
          () => getService().seekToPosition(Duration(milliseconds: positionMs)));
    } finally {
      _isSkipping = false;
    }
  }

  /// 下一首
  Future<void> skipToNext() async {
    logger.d('skipToNext: 开始执行');

    try {
      _isSkipping = true;
      await guard(() => getService().skipToNext());
    } finally {
      _isSkipping = false;
    }
  }

  /// 上一首
  Future<void> skipToPrevious() async {
    logger.d('skipToPrevious: 开始执行');

    try {
      _isSkipping = true;
      await guard(() => getService().skipToPrevious());
    } finally {
      _isSkipping = false;
    }
  }

  /// 切换收藏状态
  Future<void> toggleTrackSave() async {
    if (currentTrack == null || currentTrack!['item'] == null) return;

    final trackId = currentTrack!['item']['id'];
    final originalState = isCurrentTrackSaved;

    try {
      // 乐观更新 UI
      isCurrentTrackSaved = !(isCurrentTrackSaved ?? false);
      notifyListeners();

      // 调用 API
      await guard(() => getService().toggleTrackSave(trackId));

      // 获取实际状态确认
      final actualState = await guard(() => getService().isTrackSaved(trackId));
      if (isCurrentTrackSaved != actualState) {
        isCurrentTrackSaved = actualState;
        notifyListeners();
      }
    } catch (e) {
      // 回滚状态
      if (isCurrentTrackSaved != originalState) {
        isCurrentTrackSaved = originalState;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// 同步播放模式
  Future<void> syncPlaybackMode() async {
    try {
      final state = await guard(() => getService().getPlaybackState());
      final repeatMode = state['repeat_state'];
      final isShuffling = state['shuffle_state'] ?? false;

      if (repeatMode == 'track' && !isShuffling) {
        _currentMode = PlayMode.singleRepeat;
      } else if (repeatMode == 'context' && !isShuffling) {
        _currentMode = PlayMode.sequential;
      } else if (repeatMode == 'context' && isShuffling) {
        _currentMode = PlayMode.shuffle;
      } else {
        await setPlayMode(PlayMode.sequential);
      }
      notifyListeners();
    } catch (e) {
      logger.e('同步播放模式失败: $e');
      rethrow;
    }
  }

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    try {
      switch (mode) {
        case PlayMode.singleRepeat:
          await guard(() => getService().setRepeatMode('track'));
          await guard(() => getService().setShuffle(false));
          break;
        case PlayMode.sequential:
          await guard(() => getService().setRepeatMode('context'));
          await guard(() => getService().setShuffle(false));
          break;
        case PlayMode.shuffle:
          await guard(() => getService().setRepeatMode('context'));
          await guard(() => getService().setShuffle(true));
          break;
      }
      _currentMode = mode;
      await refreshPlaybackQueue();
      notifyListeners();
    } catch (e) {
      logger.e('设置播放模式失败: $e');
      rethrow;
    }
  }

  /// 循环切换播放模式
  Future<void> togglePlayMode() async {
    final nextMode = PlayMode.values[(currentMode.index + 1) % PlayMode.values.length];
    await setPlayMode(nextMode);
  }

  /// 清除状态
  void clear() {
    stopTimers();
    currentTrack = null;
    isCurrentTrackSaved = null;
    previousTrack = null;
    nextTrack = null;
    upcomingTracks.clear();
    _lastProgressUpdate = null;
    _lastProgressNotify = null;
    _lastQueueRefresh = null;
  }

  /// 清除图片缓存
  void clearImageCache() {
    _imageCache.clear();
  }

  /// 检查图片是否已缓存
  bool isImageCached(String? imageUrl) {
    if (imageUrl == null) return false;
    return _imageCache.containsKey(imageUrl);
  }
}
