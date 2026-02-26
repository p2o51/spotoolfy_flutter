import 'dart:async';

/// 统一的定时器管理器
///
/// 提供集中化的定时器管理，避免代码重复和内存泄漏风险
class TimerManager {
  final Map<String, Timer> _timers = {};
  final Map<String, Timer> _periodicTimers = {};

  /// 启动一个一次性定时器
  ///
  /// 如果同名定时器已存在，会先取消旧的
  void startOnce(String key, Duration delay, void Function() callback) {
    cancel(key);
    _timers[key] = Timer(delay, () {
      _timers.remove(key);
      callback();
    });
  }

  /// 启动一个周期性定时器
  ///
  /// 如果同名定时器已存在，会先取消旧的
  void startPeriodic(
    String key,
    Duration interval,
    void Function(Timer timer) callback,
  ) {
    cancelPeriodic(key);
    _periodicTimers[key] = Timer.periodic(interval, callback);
  }

  /// 取消一次性定时器
  void cancel(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }

  /// 取消周期性定时器
  void cancelPeriodic(String key) {
    _periodicTimers[key]?.cancel();
    _periodicTimers.remove(key);
  }

  /// 取消指定的定时器（一次性或周期性）
  void cancelAny(String key) {
    cancel(key);
    cancelPeriodic(key);
  }

  /// 检查一次性定时器是否存在且活跃
  bool isActive(String key) => _timers[key]?.isActive ?? false;

  /// 检查周期性定时器是否存在且活跃
  bool isPeriodicActive(String key) => _periodicTimers[key]?.isActive ?? false;

  /// 取消所有定时器
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();

    for (final timer in _periodicTimers.values) {
      timer.cancel();
    }
    _periodicTimers.clear();
  }

  /// 取消所有一次性定时器
  void cancelAllOnce() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// 取消所有周期性定时器
  void cancelAllPeriodic() {
    for (final timer in _periodicTimers.values) {
      timer.cancel();
    }
    _periodicTimers.clear();
  }

  /// 获取当前活跃的一次性定时器数量
  int get activeCount => _timers.values.where((t) => t.isActive).length;

  /// 获取当前活跃的周期性定时器数量
  int get activePeriodicCount =>
      _periodicTimers.values.where((t) => t.isActive).length;

  /// 销毁管理器，取消所有定时器
  void dispose() {
    cancelAll();
  }
}

/// 定时器常用 key 常量
///
/// 用于在代码中标识不同用途的定时器
class TimerKeys {
  TimerKeys._();

  // SpotifyProvider 相关
  static const String refreshTrack = 'refresh_track';
  static const String progressUpdate = 'progress_update';
  static const String deviceRefresh = 'device_refresh';

  // Lyrics 相关
  static const String userScrollSuppression = 'user_scroll_suppression';
  static const String quickActionsHide = 'quick_actions_hide';
  static const String scrollabilityCheck = 'scrollability_check';

  // 通用
  static const String debounce = 'debounce';
  static const String throttle = 'throttle';
}
