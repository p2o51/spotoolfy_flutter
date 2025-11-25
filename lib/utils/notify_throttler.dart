import 'dart:async';

import 'package:flutter/foundation.dart';

/// 通知节流器 - 防止 notifyListeners 调用过于频繁
///
/// 使用示例:
/// ```dart
/// class MyProvider extends ChangeNotifier {
///   late final NotifyThrottler _throttler;
///
///   MyProvider() {
///     _throttler = NotifyThrottler(
///       minInterval: Duration(milliseconds: 50),
///       notifyCallback: super.notifyListeners,
///     );
///   }
///
///   @override
///   void notifyListeners() {
///     _throttler.notify();
///   }
///
///   @override
///   void dispose() {
///     _throttler.dispose();
///     super.dispose();
///   }
/// }
/// ```
class NotifyThrottler {
  /// 最小通知间隔
  final Duration minInterval;

  /// 通知回调
  final VoidCallback notifyCallback;

  /// 上次通知时间
  DateTime? _lastNotifyTime;

  /// 待处理的通知定时器
  Timer? _pendingTimer;

  /// 是否有待处理的通知
  bool _hasPendingNotification = false;

  /// 统计：总调用次数
  int _totalCalls = 0;

  /// 统计：实际通知次数
  int _actualNotifications = 0;

  NotifyThrottler({
    this.minInterval = const Duration(milliseconds: 50),
    required this.notifyCallback,
  });

  /// 请求通知
  ///
  /// 如果距离上次通知时间超过 [minInterval]，则立即通知
  /// 否则，延迟到 [minInterval] 后通知
  void notify() {
    _totalCalls++;
    final now = DateTime.now();

    // 如果从未通知过，或者已经超过最小间隔，立即通知
    if (_lastNotifyTime == null ||
        now.difference(_lastNotifyTime!) >= minInterval) {
      _executeNotify(now);
      return;
    }

    // 否则，标记有待处理的通知，并设置定时器
    _hasPendingNotification = true;
    _pendingTimer ??= Timer(
      minInterval - now.difference(_lastNotifyTime!),
      () {
        if (_hasPendingNotification) {
          _executeNotify(DateTime.now());
        }
        _pendingTimer = null;
      },
    );
  }

  /// 强制立即通知（跳过节流）
  void notifyImmediately() {
    _totalCalls++;
    _executeNotify(DateTime.now());
  }

  void _executeNotify(DateTime time) {
    _lastNotifyTime = time;
    _hasPendingNotification = false;
    _actualNotifications++;
    notifyCallback();
  }

  /// 取消待处理的通知
  void cancel() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _hasPendingNotification = false;
  }

  /// 获取节流效率统计
  ///
  /// 返回 (总调用次数, 实际通知次数, 节省百分比)
  (int total, int actual, double savedPercent) get stats {
    final saved = _totalCalls > 0
        ? ((_totalCalls - _actualNotifications) / _totalCalls * 100)
        : 0.0;
    return (_totalCalls, _actualNotifications, saved);
  }

  /// 重置统计
  void resetStats() {
    _totalCalls = 0;
    _actualNotifications = 0;
  }

  /// 释放资源
  void dispose() {
    cancel();
  }
}

/// 分类通知节流器 - 支持按类别独立节流
///
/// 适用于需要区分不同类型状态更新的场景
/// 例如：播放进度更新 vs 曲目切换
class CategorizedNotifyThrottler {
  final VoidCallback notifyCallback;
  final Map<String, Duration> categoryIntervals;
  final Duration defaultInterval;

  final Map<String, DateTime> _lastNotifyTimes = {};
  final Map<String, Timer?> _pendingTimers = {};
  final Map<String, bool> _hasPendingNotifications = {};

  CategorizedNotifyThrottler({
    required this.notifyCallback,
    this.categoryIntervals = const {},
    this.defaultInterval = const Duration(milliseconds: 50),
  });

  /// 按类别请求通知
  void notify(String category) {
    final now = DateTime.now();
    final interval = categoryIntervals[category] ?? defaultInterval;
    final lastTime = _lastNotifyTimes[category];

    if (lastTime == null || now.difference(lastTime) >= interval) {
      _executeNotify(category, now);
      return;
    }

    _hasPendingNotifications[category] = true;
    _pendingTimers[category] ??= Timer(
      interval - now.difference(lastTime),
      () {
        if (_hasPendingNotifications[category] == true) {
          _executeNotify(category, DateTime.now());
        }
        _pendingTimers[category] = null;
      },
    );
  }

  void _executeNotify(String category, DateTime time) {
    _lastNotifyTimes[category] = time;
    _hasPendingNotifications[category] = false;
    notifyCallback();
  }

  /// 释放资源
  void dispose() {
    for (final timer in _pendingTimers.values) {
      timer?.cancel();
    }
    _pendingTimers.clear();
    _hasPendingNotifications.clear();
  }
}

/// 批量通知收集器 - 收集多个状态变更后统一通知
///
/// 适用于一系列连续的状态更新需要合并为一次通知的场景
class BatchNotifyCollector {
  final VoidCallback notifyCallback;
  final Duration batchWindow;

  Timer? _batchTimer;
  bool _hasChanges = false;

  BatchNotifyCollector({
    required this.notifyCallback,
    this.batchWindow = const Duration(milliseconds: 16), // 约等于一帧时间
  });

  /// 标记有变更需要通知
  void markChanged() {
    _hasChanges = true;
    _batchTimer ??= Timer(batchWindow, _flush);
  }

  /// 立即刷新所有待处理的通知
  void flush() {
    _flush();
  }

  void _flush() {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_hasChanges) {
      _hasChanges = false;
      notifyCallback();
    }
  }

  /// 释放资源
  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
  }
}
