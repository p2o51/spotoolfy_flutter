import 'dart:async';

import 'package:logger/logger.dart';

import '../services/spotify_service.dart';
import '../utils/timer_manager.dart';
import '../models/play_mode.dart';

final _logger = Logger();

/// Spotify 播放控制器
///
/// 职责:
/// - 管理播放状态刷新定时器
/// - 管理播放进度更新
/// - 处理播放/暂停/跳过等控制操作
/// - 管理播放模式
class SpotifyPlaybackController {
  final SpotifyAuthService _spotifyService;
  final TimerManager _timerManager = TimerManager();
  final void Function() _onStateChanged;

  // 定时器配置
  static const Duration progressTimerInterval = Duration(milliseconds: 500);
  static const Duration refreshTickInterval = Duration(seconds: 3);
  static const Duration deviceRefreshInterval = Duration(seconds: 15);
  static const Duration queueRefreshInterval = Duration(seconds: 9);
  static const int progressNotifyIntervalMs = 500;

  // 状态
  PlayMode _currentMode = PlayMode.sequential;
  bool _isRefreshTickRunning = false;
  bool _isSkipping = false;
  DateTime? _lastProgressUpdate;
  DateTime? _lastProgressNotify;
  DateTime? _lastDeviceRefresh;
  DateTime? _lastQueueRefresh;

  SpotifyPlaybackController({
    required SpotifyAuthService spotifyService,
    required void Function() onStateChanged,
  })  : _spotifyService = spotifyService,
        _onStateChanged = onStateChanged;

  // ============ Getters ============

  PlayMode get currentMode => _currentMode;
  bool get isRefreshTickRunning => _isRefreshTickRunning;
  bool get isSkipping => _isSkipping;
  DateTime? get lastProgressUpdate => _lastProgressUpdate;

  // ============ 定时器控制 ============

  /// 启动播放状态刷新定时器
  void startRefreshTimer(Future<void> Function() onRefreshTick) {
    _timerManager.startPeriodic(
      TimerKeys.refreshTrack,
      refreshTickInterval,
      (_) => onRefreshTick(),
    );
  }

  /// 启动播放进度更新定时器
  void startProgressTimer(void Function() onProgressUpdate) {
    _lastProgressUpdate = DateTime.now();
    _timerManager.startPeriodic(
      TimerKeys.progressUpdate,
      progressTimerInterval,
      (_) => onProgressUpdate(),
    );
  }

  /// 停止所有刷新定时器
  void stopAllTimers() {
    _timerManager.cancelAll();
    _isRefreshTickRunning = false;
  }

  /// 检查是否应该刷新设备列表
  bool shouldRefreshDevices() {
    if (_lastDeviceRefresh == null) return true;
    return DateTime.now().difference(_lastDeviceRefresh!) >=
        deviceRefreshInterval;
  }

  /// 标记设备已刷新
  void markDevicesRefreshed() {
    _lastDeviceRefresh = DateTime.now();
  }

  /// 检查是否应该刷新队列
  bool shouldRefreshQueue() {
    if (_lastQueueRefresh == null) return true;
    return DateTime.now().difference(_lastQueueRefresh!) >= queueRefreshInterval;
  }

  /// 标记队列已刷新
  void markQueueRefreshed() {
    _lastQueueRefresh = DateTime.now();
  }

  // ============ 播放控制 ============

  /// 设置跳过状态
  void setSkipping(bool value) {
    _isSkipping = value;
  }

  /// 更新进度时间戳
  void updateProgressTimestamp() {
    _lastProgressUpdate = DateTime.now();
  }

  /// 检查是否应该通知进度更新
  bool shouldNotifyProgress() {
    if (_lastProgressNotify == null) return true;
    return DateTime.now().difference(_lastProgressNotify!).inMilliseconds >=
        progressNotifyIntervalMs;
  }

  /// 标记进度已通知
  void markProgressNotified() {
    _lastProgressNotify = DateTime.now();
  }

  // ============ 播放模式 ============

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    final previousMode = _currentMode;
    _currentMode = mode;

    try {
      switch (mode) {
        case PlayMode.singleRepeat:
          await _spotifyService.setRepeatMode('track');
          await _spotifyService.setShuffle(false);
          break;
        case PlayMode.sequential:
          await _spotifyService.setRepeatMode('context');
          await _spotifyService.setShuffle(false);
          break;
        case PlayMode.shuffle:
          await _spotifyService.setRepeatMode('context');
          await _spotifyService.setShuffle(true);
          break;
      }
      _onStateChanged();
    } catch (e) {
      // 恢复之前的模式
      _currentMode = previousMode;
      _logger.w('设置播放模式失败: $e');
      rethrow;
    }
  }

  /// 循环切换播放模式
  Future<void> togglePlayMode() async {
    final nextMode =
        PlayMode.values[(currentMode.index + 1) % PlayMode.values.length];
    await setPlayMode(nextMode);
  }

  /// 从 Spotify API 同步播放模式
  void syncPlayModeFromApi({
    required String? repeatState,
    required bool? shuffleState,
  }) {
    if (repeatState == 'track') {
      _currentMode = PlayMode.singleRepeat;
    } else if (shuffleState == true) {
      _currentMode = PlayMode.shuffle;
    } else {
      _currentMode = PlayMode.sequential;
    }
  }

  // ============ 生命周期 ============

  /// 销毁控制器
  void dispose() {
    _timerManager.dispose();
  }
}
