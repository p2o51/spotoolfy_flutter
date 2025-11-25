import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../models/spotify_device.dart';
import '../services/spotify_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';

/// 设备管理器 - 负责 Spotify 设备相关操作
///
/// 职责:
/// - 管理可用设备列表
/// - 处理设备切换
/// - 管理音量控制
class SpotifyDeviceManager {
  final Logger logger;
  final Future<T> Function<T>(Future<T> Function() job) guard;
  final SpotifyAuthService Function() getService;
  final VoidCallback notifyListeners;

  // 设备列表状态
  List<SpotifyDevice> _availableDevices = [];
  String? _activeDeviceId;
  DateTime? _lastDeviceRefresh;

  static const Duration _deviceRefreshInterval = Duration(seconds: 15);

  SpotifyDeviceManager({
    required this.logger,
    required this.guard,
    required this.getService,
    required this.notifyListeners,
  });

  // Getters
  List<SpotifyDevice> get availableDevices => _availableDevices;
  String? get activeDeviceId => _activeDeviceId;
  DateTime? get lastDeviceRefresh => _lastDeviceRefresh;

  SpotifyDevice? get activeDevice =>
      _availableDevices.firstWhereOrNull(
        (device) => device.isActive,
      ) ??
      _availableDevices.firstWhereOrNull(
        (device) => device.id == _activeDeviceId,
      ) ??
      (_availableDevices.isEmpty ? null : _availableDevices.first);

  /// 检查是否应该刷新设备列表
  bool shouldRefreshDevices() {
    return _lastDeviceRefresh == null ||
        DateTime.now().difference(_lastDeviceRefresh!) >= _deviceRefreshInterval;
  }

  /// 标记设备已刷新
  void markDevicesRefreshed() {
    _lastDeviceRefresh = DateTime.now();
  }

  /// 刷新可用设备列表
  Future<void> refreshAvailableDevices() async {
    try {
      final devices = await guard(() => getService().getAvailableDevices());
      _availableDevices =
          devices.map((json) => SpotifyDevice.fromJson(json)).toList();

      // 更新当前活动设备ID
      final activeDevice = _availableDevices.firstWhereOrNull(
            (device) => device.isActive,
          ) ??
          (_availableDevices.isEmpty
              ? SpotifyDevice(
                  name: 'No Device',
                  type: SpotifyDeviceType.unknown,
                  isActive: false,
                  isPrivateSession: false,
                  isRestricted: true,
                  supportsVolume: false,
                )
              : _availableDevices.first);

      _activeDeviceId = activeDevice.id;
      markDevicesRefreshed();
      notifyListeners();
    } catch (e) {
      logger.e('刷新可用设备列表失败: $e');
      rethrow;
    }
  }

  /// 转移播放到指定设备
  Future<void> transferPlaybackToDevice(String deviceId, {bool play = false}) async {
    final targetDevice = _availableDevices.firstWhereOrNull(
      (device) => device.id == deviceId,
    );

    if (targetDevice == null) {
      throw Exception('Device not found');
    }

    // 检查设备是否受限
    if (targetDevice.isRestricted) {
      throw Exception('Device is restricted');
    }

    await guard(() => getService().transferPlayback(deviceId, play: play));

    // 等待一小段时间确保转移完成
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// 设置设备音量
  Future<void> setDeviceVolume(String deviceId, int volumePercent) async {
    final targetDevice = _availableDevices.firstWhereOrNull(
      (device) => device.id == deviceId,
    );

    if (targetDevice == null) {
      throw Exception('Device not found');
    }

    // 检查设备是否支持音量控制
    if (!targetDevice.supportsVolume) {
      throw Exception('Device does not support volume control');
    }

    await guard(() => getService().setVolume(
          volumePercent.clamp(0, 100),
          deviceId: deviceId,
        ));
  }

  /// 检查设备是否受限并显示消息
  bool checkDeviceRestricted(Map<String, dynamic>? device) {
    if (device == null) return false;

    final isRestricted = device['is_restricted'] as bool? ?? false;
    if (isRestricted) {
      final deviceName = device['name'] as String? ?? 'Unknown';
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deviceRestrictedMessage(deviceName))),
        );
      }
      return true;
    }
    return false;
  }

  /// 清除设备状态
  void clear() {
    _availableDevices.clear();
    _activeDeviceId = null;
    _lastDeviceRefresh = null;
  }
}
