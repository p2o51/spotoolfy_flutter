import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import '../services/spotify_service.dart'
    show SpotifyAuthService, SpotifyAuthException;
import '../models/spotify_device.dart';
import 'package:collection/collection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/local_database_provider.dart';
import 'package:logger/logger.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../env.dart';
import '../utils/notify_throttler.dart';
import '../managers/image_preload_manager.dart';

final logger = Logger();

enum PlayMode {
  singleRepeat, // 单曲循环（曲循环+顺序播放）
  sequential, // 顺序播放（列表循环+顺序播放）
  shuffle // 随机播放（列表循环+随机播放）
}

class SpotifyProvider extends ChangeNotifier {
  late SpotifyAuthService _spotifyService;
  static const String _clientIdKey = 'spotify_client_id';
  static const String _lastPlayedImageKey = 'last_played_image_url';
  final Logger logger = Logger();

  // 异步初始化控制
  Completer<void> _initDone = Completer<void>();

  // 生命周期观察者
  late final WidgetsBinding _binding;
  _AppLifecycleObserver? _lifecycleObserver;

  // 网络状态跟踪
  // Network tracking fields removed - no longer used
  int _consecutiveNetworkErrors = 0;

  String? username;
  Map<String, dynamic>? currentTrack;
  bool? isCurrentTrackSaved;
  Timer? _refreshTimer;
  Timer? _progressTimer;
  DateTime? _lastProgressUpdate;
  DateTime? _lastProgressNotify;
  bool isLoading = false;
  bool _isBootstrapping = false; // 防止并发bootstrap
  Map<String, dynamic>? previousTrack;
  Map<String, dynamic>? nextTrack;
  PlayMode _currentMode = PlayMode.sequential;
  PlayMode get currentMode => _currentMode;
  bool _isSkipping = false;
  bool _isInitialized = false;
  bool _isRefreshTickRunning = false;
  bool _isQueuePrefetchRunning = false;
  DateTime? _lastDeviceRefresh;
  DateTime? _lastQueueRefresh;

  // 添加图片预加载缓存 - 持久化跨登录会话
  final Map<String, String> _imageCache = {};
  final Map<String, Map<String, dynamic>> _albumCache = {};
  final Map<String, Map<String, dynamic>> _playlistCache = {};

  // 通知节流器 - 减少不必要的 UI 重建
  late final CategorizedNotifyThrottler _notifyThrottler;

  // 图片预加载管理器
  final ImagePreloadManager _imagePreloadManager = ImagePreloadManager();
  final AlbumArtPreloadStrategy _albumArtPreloader = AlbumArtPreloadStrategy();

  // 持久化存储最后播放的图像 URL（用于离线显示）
  String? _lastPlayedImageUrl;

  static const Duration _progressTimerInterval = Duration(milliseconds: 500);
  static const Duration _refreshTickInterval = Duration(seconds: 3);
  static const Duration _deviceRefreshInterval = Duration(seconds: 15);
  static const Duration _queueRefreshInterval = Duration(seconds: 9);
  static const int _progressNotifyIntervalMs = 500;

  // 添加图片缓存管理方法
  void clearImageCache() {
    _imageCache.clear();
  }

  // 获取缓存状态
  bool isImageCached(String? imageUrl) {
    if (imageUrl == null) return false;
    return _imageCache.containsKey(imageUrl);
  }

  // 获取最后播放的图像 URL（用于离线默认显示）
  String? get lastPlayedImageUrl => _lastPlayedImageUrl;

  // 从持久化存储加载最后播放的图像 URL
  Future<void> loadLastPlayedImageUrl() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _lastPlayedImageUrl = sp.getString(_lastPlayedImageKey);
      logger.d('已加载最后播放图像 URL: $_lastPlayedImageUrl');
    } catch (e) {
      logger.e('加载最后播放图像 URL 失败', error: e);
    }
  }

  // 保存最后播放的图像 URL 到持久化存储
  Future<void> _saveLastPlayedImageUrl(String? imageUrl) async {
    if (imageUrl == null || imageUrl == _lastPlayedImageUrl) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_lastPlayedImageKey, imageUrl);
      _lastPlayedImageUrl = imageUrl;
      logger.d('已保存最后播放图像 URL: $imageUrl');
    } catch (e) {
      logger.e('保存最后播放图像 URL 失败', error: e);
    }
  }

  /// 验证 Access Token 格式的有效性
  bool _isValidAccessToken(String token) {
    if (token.isEmpty) return false;

    // Spotify access token 通常是 Base64 编码的字符串
    // 长度通常在 100-300 字符之间
    if (token.length < 50 || token.length > 500) {
      logger.w('Token长度异常: ${token.length}');
      return false;
    }

    // 检查是否包含有效的 Base64 字符
    final base64Regex = RegExp(r'^[A-Za-z0-9+/=_-]+$');
    if (!base64Regex.hasMatch(token)) {
      logger.w('Token包含无效字符');
      return false;
    }

    return true;
  }

  // CSRF 防护相关变量和方法
  String? _currentState;

  /// 生成 OAuth state 参数以防止 CSRF 攻击
  /// 注意：当前 Spotify SDK 可能不支持自定义 state，此方法为将来扩展预留
  // ignore: unused_element
  String _generateState() {
    final random = math.Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final state = String.fromCharCodes(Iterable.generate(
        32, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
    _currentState = state;
    return state;
  }

  /// 验证 OAuth state 参数
  bool _verifyState(String? receivedState) {
    if (receivedState == null || _currentState == null) {
      logger.w('CSRF验证失败：state参数为空');
      return false;
    }

    final isValid = receivedState == _currentState;
    if (!isValid) {
      logger.e('CSRF验证失败：state参数不匹配');
      logger.d('期望: $_currentState, 收到: $receivedState');
    } else {
      logger.d('CSRF验证成功');
    }

    // 使用后清除state
    _currentState = null;
    return isValid;
  }

  /// 检查授权状态和连接健康度
  Future<bool> checkAuthHealth() async {
    try {
      if (!_isInitialized) {
        await _bootstrap();
      }

      // 1. 检查基本认证状态
      final isAuth = await _guard(() => _spotifyService.isAuthenticated());
      if (!isAuth) {
        logger.w('Auth Health: 未认证状态');
        return false;
      }

      // 2. 尝试调用用户资料API验证token有效性
      try {
        final profile = await _guard(() => _spotifyService.getUserProfile());
        if (profile['id'] != null) {
          logger.d('Auth Health: Token验证成功');
          return true;
        }
      } catch (e) {
        logger.w('Auth Health: Token验证失败: $e');
        return false;
      }

      return false;
    } catch (e) {
      logger.e('Auth Health: 检查失败: $e');
      return false;
    }
  }

  SpotifyProvider() {
    // 初始化分类节流器
    // - progress: 播放进度更新，较高频率但节流
    // - track: 曲目切换，立即响应
    // - default: 其他更新，中等节流
    _notifyThrottler = CategorizedNotifyThrottler(
      notifyCallback: super.notifyListeners,
      categoryIntervals: {
        'progress': const Duration(milliseconds: 200), // 进度更新节流 200ms
        'track': const Duration(milliseconds: 16), // 曲目切换几乎立即响应
        'devices': const Duration(milliseconds: 500), // 设备更新节流 500ms
        'queue': const Duration(milliseconds: 300), // 队列更新节流 300ms
      },
      defaultInterval: const Duration(milliseconds: 50),
    );
    _bootstrap();
  }

  /// 分类通知 - 根据更新类型使用不同的节流策略
  void _notifyCategory(String category) {
    _notifyThrottler.notify(category);
  }

  /// 异步初始化bootstrap过程
  Future<void> _bootstrap() async {
    // 防止并发bootstrap
    if (_isBootstrapping) {
      logger.w('Bootstrap已在进行中，跳过重复调用');
      return;
    }

    _isBootstrapping = true;
    try {
      // 确保在设备解锁后再读取存储
      await WidgetsBinding.instance.endOfFrame;

      // 使用SharedPreferences读取Client ID，避免KeyStore的限制
      final sp = await SharedPreferences.getInstance();
      final storedClientId = sp.getString(_clientIdKey);

      // 加载最后播放的图像 URL（用于离线显示）
      _lastPlayedImageUrl = sp.getString(_lastPlayedImageKey);
      logger.d('Bootstrap: 已加载最后播放图像 URL: $_lastPlayedImageUrl');

      logger.d(
          'Bootstrap: 从SharedPreferences读取ClientID: ${storedClientId ?? "null"}');

      // 安全的ClientID获取 - 提供默认值
      const String envClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
      const String defaultClientId = Env.clientId;
      const String redirectUrl = String.fromEnvironment('SPOTIFY_REDIRECT_URL',
          defaultValue: Env.redirectUriMobile);

      final clientId = storedClientId ??
          (envClientId.isNotEmpty ? envClientId : defaultClientId);

      // 现在应该永远不会为空，因为我们提供了默认值
      logger.d('Bootstrap: 检查最终 Client ID: ${clientId.isEmpty ? "空" : "有效"}');

      logger.d('Bootstrap: Using Client ID: ${clientId.substring(0, 8)}...');

      _spotifyService = SpotifyAuthService(
        clientId: clientId,
        redirectUrl: redirectUrl,
      );

      // 设置token刷新回调
      _spotifyService.onTokenRefreshed = () {
        _refreshUserProfile();
      };

      _isInitialized = true;
      _initDone.complete(); // 标记初始化完成

      logger.d('Bootstrap: SpotifyService初始化完成');

      // 初始化生命周期观察者
      _initLifecycleObserver();

      // 尝试自动登录（如果 Client ID 可用）
      try {
        await autoLogin();
      } catch (e) {
        if (e is SpotifyAuthException && e.code == 'CLIENT_ID_MISSING') {
          logger.d('Bootstrap: 跳过自动登录 - Client ID 未配置');
          // 不重新抛出，允许应用正常启动
        } else {
          rethrow;
        }
      }
    } catch (e) {
      logger.d('Bootstrap过程失败: $e');
      if (!_initDone.isCompleted) {
        _initDone.completeError(e);
      }
    } finally {
      _isBootstrapping = false;
    }
  }

  /// 通用的服务调用保护器，确保初始化完成后才执行
  Future<T> _guard<T>(Future<T> Function() job) async {
    await _initDone.future;
    return job();
  }

  void _initLifecycleObserver() {
    // 先移除旧的监听器（如果存在）
    if (_lifecycleObserver != null) {
      _binding.removeObserver(_lifecycleObserver!);
    }

    _binding = WidgetsBinding.instance;
    _lifecycleObserver = _AppLifecycleObserver(
      onResume: _onAppResume,
      onPause: _onAppPause,
    );
    _binding.addObserver(_lifecycleObserver!);
  }

  /// 应用恢复到前台时的处理
  Future<void> _onAppResume() async {
    logger.i('应用恢复到前台，重新初始化连接状态');

    try {
      // 等待一下，让网络连接稳定
      await Future.delayed(const Duration(milliseconds: 500));

      // 检查认证状态
      if (await _guard(() => _spotifyService.isAuthenticated())) {
        // 刷新token和用户信息
        await _refreshUserProfile();

        // 重新启动定时器
        if (username != null && _refreshTimer == null) {
          startTrackRefresh();
        }

        // 分阶段恢复功能，减少同时发起的网络请求
        Future.delayed(const Duration(milliseconds: 1000), () async {
          try {
            await refreshCurrentTrack();
          } catch (e) {
            logger.w('恢复后刷新当前播放状态失败: $e');
          }
        });

        Future.delayed(const Duration(milliseconds: 2000), () async {
          try {
            await refreshAvailableDevices();
          } catch (e) {
            logger.w('恢复后刷新设备列表失败: $e');
          }
        });
      }
    } catch (e) {
      logger.w('应用恢复时重新初始化失败: $e');
    }
  }

  /// 应用进入后台时的处理
  Future<void> _onAppPause() async {
    logger.i('应用进入后台，暂停定时器');
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    // 可以在这里添加一些清理工作，比如暂停一些不必要的网络请求
  }

  Future<void> _refreshUserProfile() async {
    try {
      final user = await _guard(() => _spotifyService.getUserProfile());
      username = user['display_name'];
      _notifyCategory('default'); // UI 马上刷新
      if (_refreshTimer == null && username != null)
        startTrackRefresh(); // 仅在定时器未运行且用户已登录时启动
    } catch (_) {
      /* 忽略失败 */
    }
  }

  Future<void> setClientCredentials(String clientId) async {
    try {
      // 使用SharedPreferences保存新凭据
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_clientIdKey, clientId);

      logger
          .d('已保存新的ClientID到SharedPreferences: ${clientId.substring(0, 4)}...');

      final bool wasInitialized = _isInitialized; // Store original state

      // 清除现有状态
      username = null;
      currentTrack = null;
      previousTrack = null;
      nextTrack = null;
      isCurrentTrackSaved = null;
      _availableDevices.clear();
      _activeDeviceId = null;
      _isInitialized = false; // Set to false before re-init

      // 停止所有计时器
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _progressTimer?.cancel();
      _progressTimer = null;

      // 如果之前已初始化并且已登录，先注销
      if (wasInitialized) {
        try {
          await _guard(() => _spotifyService.logout());
        } catch (e) {
          logger.e('注销旧凭据时出错: $e');
        }
      }

      // 创建新的Completer以避免重复完成
      _initDone = Completer<void>();

      // 用新凭据重新初始化服务
      const String redirectUrl = String.fromEnvironment('SPOTIFY_REDIRECT_URL',
          defaultValue: 'spotoolfy://callback');
      _spotifyService = SpotifyAuthService(
        clientId: clientId,
        redirectUrl: redirectUrl,
      );
      _spotifyService.onTokenRefreshed = () {
        _refreshUserProfile();
      };
      _isInitialized = true;
      _initDone.complete(); // 标记新的初始化完成

      // 记录新凭据应用情况
      logger.d('已应用新的ClientID: ${clientId.substring(0, 4)}...');

      _notifyCategory('default');
    } catch (e) {
      logger.e('设置客户端凭据失败: $e');
      rethrow;
    }
  }

  Future<Map<String, String?>> getClientCredentials() async {
    final sp = await SharedPreferences.getInstance();
    final clientId = sp.getString(_clientIdKey);
    return {
      'clientId': clientId,
    };
  }

  Future<void> resetClientCredentials() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_clientIdKey);

    final bool wasInitialized = _isInitialized; // Store original state

    username = null;
    currentTrack = null;
    previousTrack = null;
    nextTrack = null;
    isCurrentTrackSaved = null;
    _availableDevices.clear();
    _activeDeviceId = null;
    _isInitialized = false; // Set to false before re-init

    _refreshTimer?.cancel();
    _refreshTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;

    if (wasInitialized) {
      try {
        await _guard(() => _spotifyService.logout());
      } catch (e) {
        // debugPrint('注销时出错: $e');
      }
    }

    // 创建新的Completer以避免重复完成
    _initDone = Completer<void>();

    // 重新进行bootstrap初始化
    _bootstrap();
    _notifyCategory('default');
  }

  // 添加设备列表状态
  List<SpotifyDevice> _availableDevices = [];
  String? _activeDeviceId;

  // Getter
  List<SpotifyDevice> get availableDevices => _availableDevices;
  String? get activeDeviceId => _activeDeviceId;

  SpotifyDevice? get activeDevice =>
      _availableDevices.firstWhereOrNull(
        (device) => device.isActive,
      ) ??
      _availableDevices.firstWhereOrNull(
        (device) => device.id == _activeDeviceId,
      ) ??
      (_availableDevices.isEmpty ? null : _availableDevices.first);

  /// 刷新可用设备列表
  Future<void> refreshAvailableDevices() async {
    try {
      final devices = await _guard(() => _spotifyService.getAvailableDevices());
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

      _notifyCategory('devices');
    } catch (e) {
      // debugPrint('刷新可用设备列表失败: $e');
      await _handleApiError(e,
          contextMessage: '刷新可用设备列表', isUserInitiated: true);
    }
  }

  /// 转移播放到指定设备
  Future<void> transferPlaybackToDevice(String deviceId,
      {bool play = false}) async {
    try {
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

      await _guard(
          () => _spotifyService.transferPlayback(deviceId, play: play));

      // 等待一小段时间确保转移完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 刷新设备列表和播放状态
      await Future.wait([
        refreshAvailableDevices(),
        refreshCurrentTrack(),
      ]);
    } catch (e) {
      // debugPrint('转移播放失败: $e');
      await _handleApiError(e, contextMessage: '转移播放', isUserInitiated: true);
      rethrow; // Rethrow original or modified error from _handleApiError
    }
  }

  /// 设置设备音量
  Future<void> setDeviceVolume(String deviceId, int volumePercent) async {
    try {
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

      await _guard(() => _spotifyService.setVolume(
            volumePercent.clamp(0, 100),
            deviceId: deviceId,
          ));

      await refreshAvailableDevices();
    } catch (e) {
      // debugPrint('设置音量失败: $e');
      await _handleApiError(e, contextMessage: '设置音量', isUserInitiated: true);
      rethrow; // Rethrow original or modified error from _handleApiError
    }
  }

  void startTrackRefresh() {
    logger.d(
        'startTrackRefresh: User: $username, Initialized: $_isInitialized, IsSkipping: $_isSkipping');
    if (username == null || !_isInitialized) {
      logger.w(
          'startTrackRefresh: Aborted. Username is null or service not initialized.');
      _refreshTimer?.cancel();
      _progressTimer?.cancel();
      _refreshTimer = null;
      _progressTimer = null;
      return;
    }

    Future.microtask(() async {
      // 使用 microtask 异步执行初始刷新
      try {
        logger.d(
            'startTrackRefresh (microtask): Fetching initial track and device data...');
        await refreshCurrentTrack(); // 使用恢复后的 refreshCurrentTrack
        await refreshAvailableDevices();
        await refreshPlaybackQueue(); // 初始化时也刷新播放队列
        final now = DateTime.now();
        _lastDeviceRefresh = now;
        _lastQueueRefresh = now;
        logger.i(
            'startTrackRefresh (microtask): Initial data fetched. Current progress: ${currentTrack?['progress_ms']}, isPlaying: ${currentTrack?['is_playing']}');
      } catch (e) {
        logger.e(
            'startTrackRefresh (microtask): Failed to fetch initial data, timers will still start.',
            error: e);
      } finally {
        // 确保 _lastProgressUpdate 在 _progressTimer 启动前有合理的值
        if (currentTrack != null &&
            currentTrack!['is_playing'] == true &&
            _lastProgressUpdate == null) {
          _lastProgressUpdate = DateTime.now();
        }

        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(_refreshTickInterval, (_) {
          if (_isSkipping) {
            logger.t('_refreshTimer tick: Skipped due to _isSkipping=true.');
            return;
          }
          if (_isRefreshTickRunning) {
            logger.t(
                '_refreshTimer tick: Previous refresh still running, skipping.');
            return;
          }
          _isRefreshTickRunning = true;
          Future(() async {
            try {
              logger.t(
                  '_refreshTimer tick. Refreshing current track, devices, and queue.');
              await refreshCurrentTrack();

              final now = DateTime.now();

              final shouldRefreshDevices = _lastDeviceRefresh == null ||
                  now.difference(_lastDeviceRefresh!) >= _deviceRefreshInterval;
              if (shouldRefreshDevices) {
                await refreshAvailableDevices();
                _lastDeviceRefresh = now;
              }

              final shouldRefreshQueue = _lastQueueRefresh == null ||
                  now.difference(_lastQueueRefresh!) >= _queueRefreshInterval;
              if (shouldRefreshQueue) {
                await refreshPlaybackQueue();
                _lastQueueRefresh = now;
              }
            } finally {
              _isRefreshTickRunning = false;
            }
          });
        });

        _progressTimer?.cancel();
        _progressTimer = Timer.periodic(_progressTimerInterval, (_) {
          if (_isSkipping || currentTrack == null) {
            return;
          }

          if (currentTrack!['is_playing'] == true) {
            final now = DateTime.now();
            if (_lastProgressUpdate != null) {
              final elapsed =
                  now.difference(_lastProgressUpdate!).inMilliseconds;
              if (elapsed > 0) {
                final oldProgress = currentTrack!['progress_ms'] as int;
                final duration = currentTrack!['item']?['duration_ms'] as int?;
                int newProgressValue = oldProgress + elapsed;

                if (duration != null) {
                  newProgressValue = newProgressValue.clamp(0, duration);
                } else {
                  newProgressValue =
                      newProgressValue > 0 ? newProgressValue : 0;
                }

                if (currentTrack!['progress_ms'] != newProgressValue) {
                  currentTrack!['progress_ms'] = newProgressValue;

                  final shouldNotify = _lastProgressNotify == null ||
                      now.difference(_lastProgressNotify!).inMilliseconds >=
                          _progressNotifyIntervalMs;
                  if (shouldNotify) {
                    _notifyCategory('progress');
                    _lastProgressNotify = now;
                  }
                }
              }
            }
            _lastProgressUpdate = now;
          } else if (currentTrack!['is_playing'] == false) {
            _lastProgressUpdate = DateTime
                .now(); // Also update if paused, to have a fresh start when resuming
          }
        });
        logger.d(
            'startTrackRefresh: Timers (re)started. _refreshTimer active: ${_refreshTimer?.isActive}, _progressTimer active: ${_progressTimer?.isActive}');
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    // 清理节流器
    _notifyThrottler.dispose();
    // 清理生命周期观察者
    if (_lifecycleObserver != null) {
      _binding.removeObserver(_lifecycleObserver!);
    }
    super.dispose();
  }

  Future<void> refreshCurrentTrack() async {
    try {
      final track =
          await _guard(() => _spotifyService.getCurrentlyPlayingTrack());

      // 成功获取数据，检查并重置网络错误状态
      _isNetworkError(Exception('success')); // 调用以重置计数（传入非网络错误）

      final debugTrackName = track?['item']?['name'];
      final debugArtist = (track?['item']?['artists'] is List &&
              track!['item']['artists'].isNotEmpty)
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

        logger.d(
            'refreshCurrentTrack: API data -> isPlaying: $isPlayingFromApi, progress: $progressFromApi, id: $newId, context: $newContextUri');
        logger.d(
            'refreshCurrentTrack: Provider state BEFORE update -> isPlaying: $oldIsPlaying, progress: $oldProgressMs, id: $oldId, context: $oldContextUri, _lastProgressUpdate: $_lastProgressUpdate');

        bool needsNotify = false;
        const int kProgressJumpThreshold = 1500; // 1.5 seconds

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
            logger.t(
                'refreshCurrentTrack: Preserved previous context for track $newId because API response omitted context data.');
          }

          if (newId != oldId ||
              (currentTrack!['is_playing'] == true &&
                  progressFromApi != null) ||
              significantProgressJump) {
            _lastProgressUpdate = DateTime.now();
            _lastProgressNotify = null;
          }
          needsNotify = true;
          logger.i(
              'refreshCurrentTrack: Updated currentTrack due to coreChange ($coreTrackInfoChanged) or progressJump ($significantProgressJump). New progress: ${currentTrack!['progress_ms']}, isPlaying: ${currentTrack!['is_playing']}. Reset _lastProgressUpdate: $_lastProgressUpdate');

          if (newId != oldId && newId != null) {
            // 保存当前歌曲的专辑图像 URL 到持久化存储
            final albumImageUrl =
                track['item']?['album']?['images']?[0]?['url'] as String?;
            if (albumImageUrl != null) {
              _saveLastPlayedImageUrl(albumImageUrl);
            }

            try {
              isCurrentTrackSaved =
                  await _guard(() => _spotifyService.isTrackSaved(newId));
              logger.d(
                  'refreshCurrentTrack: Fetched save state for new track $newId: $isCurrentTrackSaved');
              if (track['context'] != null) {
                final enrichedContext = await _enrichPlayContext(
                    Map<String, dynamic>.from(track['context']));
                currentTrack!['context'] = enrichedContext;
                logger.d(
                    'refreshCurrentTrack: Enriched context for new track $newId.');

                // 保存播放上下文到本地数据库
                try {
                  final context = navigatorKey.currentContext;
                  if (context != null && context.mounted) {
                    final localDbProvider = Provider.of<LocalDatabaseProvider>(
                        context,
                        listen: false);
                    await localDbProvider.insertOrUpdatePlayContext(
                      contextUri: enrichedContext['uri'] as String,
                      contextType: enrichedContext['type'] as String,
                      contextName: enrichedContext['name'] as String,
                      imageUrl:
                          (enrichedContext['images'] as List?)?.isNotEmpty ==
                                  true
                              ? enrichedContext['images'][0]['url'] as String?
                              : null,
                      lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
                    );
                    logger.d(
                        'refreshCurrentTrack: Saved play context to local database: ${enrichedContext['uri']}');
                  }
                } catch (dbError) {
                  logger.e(
                      'refreshCurrentTrack: Failed to save play context to database',
                      error: dbError);
                  // 不重新抛出错误，以免影响其他功能
                }
              }
            } catch (e) {
              logger.e(
                  'refreshCurrentTrack: Failed to fetch save state or enrich context for new track $newId',
                  error: e);
            }
          } else if (newContextUri != null) {
            Map<String, dynamic>? contextFromApi;
            if (currentTrack!['context'] is Map<String, dynamic>) {
              contextFromApi = Map<String, dynamic>.from(
                  currentTrack!['context'] as Map<String, dynamic>);
            }

            final hasContextName = contextFromApi != null &&
                (contextFromApi['name'] is String) &&
                (contextFromApi['name'] as String).trim().isNotEmpty;

            if (!hasContextName) {
              Map<String, dynamic>? enrichedContext;
              if (track['context'] is Map<String, dynamic>) {
                try {
                  enrichedContext = await _enrichPlayContext(
                      Map<String, dynamic>.from(
                          track['context'] as Map<String, dynamic>));
                  currentTrack!['context'] = enrichedContext;
                  logger.d(
                      'refreshCurrentTrack: Enriched missing context metadata for $newContextUri.');
                } catch (e) {
                  logger.w(
                      'refreshCurrentTrack: Failed to enrich missing context metadata for $newContextUri',
                      error: e);
                }
              }

              if ((currentTrack!['context']?['name'] as String?)?.isEmpty ??
                  true) {
                if (previousContext != null &&
                    previousContext['uri'] == newContextUri &&
                    (previousContext['name'] as String?)?.isNotEmpty == true) {
                  currentTrack!['context'] = previousContext;
                  logger.t(
                      'refreshCurrentTrack: Reused cached context metadata for $newContextUri.');
                } else if (contextFromApi != null) {
                  currentTrack!['context'] = contextFromApi;
                }
              }
            } else if (contextFromApi != null) {
              currentTrack!['context'] = contextFromApi;
            }
          }
        } else if (currentTrack != null &&
            progressFromApi != null &&
            progressFromApi != oldProgressMs) {
          currentTrack!['progress_ms'] = progressFromApi;
          if (currentTrack!['is_playing'] == true) {
            _lastProgressUpdate = DateTime.now();
          }
          needsNotify = true;
          logger.d(
              'refreshCurrentTrack: Calibrated progress_ms from API to $progressFromApi. Reset _lastProgressUpdate: $_lastProgressUpdate');
        }

        if (needsNotify) {
          logger.d('refreshCurrentTrack: Calling notifyListeners()');
          _notifyCategory('track');
          _lastProgressNotify = DateTime.now();

          // 预加载播放相关的封面图片
          _triggerImagePreload();
        }
      } else if (currentTrack != null) {
        logger.d(
            'refreshCurrentTrack: API returned null, clearing currentTrack.');
        currentTrack = null;
        isCurrentTrackSaved = null;
        _lastProgressNotify = null;
        _notifyCategory('track');
      }
    } catch (e) {
      logger.e('Error in refreshCurrentTrack: $e');

      // 检查是否为网络连接错误
      if (_isNetworkError(e)) {
        // 对于网络错误，我们只记录日志，不显示用户通知
        // 因为这是定时刷新操作，网络错误很常见
        logger.w('refreshCurrentTrack: 网络连接错误，跳过本次刷新: $e');
        return; // 直接返回，不调用_handleApiError
      }

      // Add a specific log before calling _handleApiError
      logger.w(
          'refreshCurrentTrack caught an error. About to call _handleApiError. Error: $e');
      await _handleApiError(e, contextMessage: '刷新当前播放状态');
    }
  }

  // 辅助方法：丰富播放上下文信息
  Future<Map<String, dynamic>> _enrichPlayContext(
      Map<String, dynamic> context) async {
    final type = context['type'];
    final uri = context['uri'] as String;

    Map<String, dynamic> enrichedContext = {
      ...context,
      'name': 'UNKNOWN CONTEXT',
      'images': [
        {'url': 'https://via.placeholder.com/300'}
      ],
    };

    try {
      if (type == 'album') {
        final albumId = uri.split(':').last;
        final fullAlbum = await _guard(() => _spotifyService.getAlbum(albumId));
        enrichedContext.addAll({
          'name': fullAlbum['name'],
          'images': fullAlbum['images'],
          'external_urls': fullAlbum['external_urls'],
        });
      } else if (type == 'playlist') {
        final playlistId = uri.split(':').last;
        final fullPlaylist =
            await _guard(() => _spotifyService.getPlaylist(playlistId));
        enrichedContext.addAll({
          'name': fullPlaylist['name'],
          'images': fullPlaylist['images'],
          'external_urls': fullPlaylist['external_urls'],
          'owner': fullPlaylist['owner'],
          'public': fullPlaylist['public'],
          'collaborative': fullPlaylist['collaborative'],
        });
      }
    } catch (e) {
      // debugPrint('获取完整上下文信息失败: $e');
    }

    // 确保必要的字段存在
    enrichedContext['images'] ??= [
      {'url': 'https://via.placeholder.com/300'}
    ];
    enrichedContext['name'] ??= '未知${type == 'playlist' ? '播放列表' : '专辑'}';

    return enrichedContext;
  }

  Future<void> checkCurrentTrackSaveState() async {
    if (currentTrack == null || currentTrack!['item'] == null) {
      isCurrentTrackSaved = null;
      _notifyCategory('track');
      return;
    }

    try {
      final trackId = currentTrack!['item']['id'];
      isCurrentTrackSaved =
          await _guard(() => _spotifyService.isTrackSaved(trackId));
      _notifyCategory('track');
    } catch (e) {
      // debugPrint('检查歌曲保存状态失败: $e');
      await _handleApiError(e, contextMessage: '检查歌曲保存状态');
    }
  }

  /// 处理从URL回调中获取的token
  Future<void> handleCallbackToken(String accessToken, String? expiresIn,
      {String? state}) async {
    logger.i('收到iOS授权回调，token长度: ${accessToken.length}');

    try {
      // 增强的安全验证
      if (!_isValidAccessToken(accessToken)) {
        logger.e('iOS回调：无效的access token格式');
        throw SpotifyAuthException('Invalid access token format',
            code: 'INVALID_TOKEN_FORMAT');
      }

      // CSRF 防护：验证 state 参数
      if (state != null) {
        if (!_verifyState(state)) {
          logger.e('iOS回调：State参数验证失败，可能的CSRF攻击');
          throw SpotifyAuthException('State parameter mismatch',
              code: 'CSRF_PROTECTION');
        }
      } else {
        logger.w('iOS回调：未提供state参数，跳过CSRF验证（建议升级到支持state的授权流程）');
      }

      final expiresInSeconds = int.tryParse(expiresIn ?? '3600') ?? 3600;

      // 验证过期时间的合理性
      if (expiresInSeconds < 300 || expiresInSeconds > 7200) {
        // 5分钟到2小时
        logger.w('iOS回调：异常的token过期时间: ${expiresInSeconds}s, 使用默认值');
      }

      // 直接保存token到SpotifyAuthService
      await _guard(() => _spotifyService.saveAuthResponse(accessToken,
          expiresInSeconds: expiresInSeconds));
      logger.d('iOS回调：token已保存到安全存储');

      // 立即获取用户资料并更新状态
      try {
        final userProfile =
            await _guard(() => _spotifyService.getUserProfile());
        username = userProfile['display_name'];
        logger.d('iOS回调：成功获取用户资料: $username');

        // 启动定时器
        startTrackRefresh();

        // 触发UI更新
        _notifyCategory('default');

        logger.i('iOS回调：成功保存access token并更新用户状态');
      } catch (profileError) {
        logger.e('iOS回调：获取用户资料失败: $profileError');
        // 即使获取用户资料失败，也要触发token刷新回调
        try {
          await _guard(() async => _spotifyService.onTokenRefreshed?.call());
        } catch (e) {
          logger.w('调用token刷新回调失败: $e');
        }
      }
    } catch (e) {
      logger.e('保存回调token失败: $e');
    } finally {
      // ⬇️⬇️ 关键修复：确保回调后重置loading状态 ⬇️⬇️
      if (isLoading) {
        isLoading = false;
        _notifyCategory('default');
        logger.d('iOS回调：已重置isLoading状态');
      }
    }
  }

  /// 自动登录
  Future<void> autoLogin() async {
    // 如果正在加载中，跳过自动登录
    if (isLoading) {
      logger.d('跳过自动登录：已在加载中');
      return;
    }

    isLoading = true;
    _notifyCategory('default');

    try {
      if (!_isInitialized) {
        _bootstrap();
      }
      // It's possible _bootstrap failed if not handled well,
      // but let's assume it sets _isInitialized correctly or throws.
      if (!_isInitialized) {
        // This case should ideally not be reached if _bootstrap is robust
        return;
      }

      final token = await _guard(() => _spotifyService.ensureFreshToken());
      if (token != null) {
        logger.d('自动登录：使用现有token成功');
        await _refreshUserProfile();
        await updateWidget();
      } else {
        // No token, ensure user is in a logged-out state if they weren't already
        logger.d('自动登录：未找到有效token，保持登出状态');
        if (username != null) {
          username = null;
          // No need to call notifyListeners here, finally block will do it.
        }
      }
    } catch (e) {
      logger.w('自动登录失败: $e');
      if (username != null) {
        username = null;
      }
    } finally {
      isLoading = false;
      _notifyCategory('default');
    }
  }

  /// 登录
  Future<void> login() async {
    if (isLoading) {
      logger.w('登录操作已在进行中，跳过重复调用');
      return;
    }

    isLoading = true;
    _notifyCategory('default');

    try {
      if (!_isInitialized) {
        _bootstrap();
        if (!_isInitialized) {
          throw SpotifyAuthException('SpotifyService 初始化失败');
        }
      }

      logger.d('开始Spotify登录流程');
      final accessToken = await _guard(() => _spotifyService
          .login()); // This now calls ensureFreshToken or SDK getAccessToken
      // and onTokenRefreshed internally

      if (accessToken == null) {
        logger.w('登录返回null token，可能被用户取消');
        // Login was cancelled or failed silently in ensureFreshToken/login in service
        // UI should reflect this (e.g. isLoading false, no username)
      } else {
        logger.d('登录成功获取token，长度: ${accessToken.length}');
        // Token obtained, _refreshUserProfile should have been called by onTokenRefreshed
        // If not, or for robustness:
        if (username == null) await _refreshUserProfile();
        await updateWidget();
      }
    } catch (e) {
      logger.e('登录过程出错: $e');
      // Handle SpotifyAuthException (e.g. AUTH_CANCELLED, CONFIG_ERROR)
      // or other exceptions
      if (e is SpotifyAuthException && e.code == 'AUTH_CANCELLED') {
        logger.d('用户取消授权');
        // User cancelled, do nothing further, isLoading will be set to false in finally
      } else {
        // For other errors, rethrow or handle appropriately
        // Potentially clear username if login failed critically
        username = null;
        rethrow;
      }
    } finally {
      // 注意：对于iOS，isLoading会在handleCallbackToken()的finally中重置
      // 对于Android/其他平台，在这里重置
      final isIOSPlatform =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      if (!isIOSPlatform) {
        isLoading = false;
        _notifyCategory('default');
        logger.d('登录流程结束，isLoading已重置为false');
      } else {
        logger.d('iOS登录流程：等待回调重置isLoading状态');
      }
    }
  }

  // Helper function to check for active device and show picker if needed
  Future<bool> _ensureAuthenticatedAndReady() async {
    logger.d('_ensureAuthenticatedAndReady: Start. Username: $username');
    logger.d('===== SPOTIFY PROVIDER DEBUG =====');
    logger.d('_ensureAuthenticatedAndReady: 开始. 用户名: $username');

    // 开关：是否忽略 Remote 连接失败，继续 Web API
    // 在您的实际应用中，您可能希望这个值来自配置或用户的偏好设置
    // const bool ignoreRemoteConnectionFailure = true; // Always ignore for now

    try {
      if (username == null) {
        logger.d(
            '_ensureAuthenticatedAndReady: Username is null, attempting autoLogin...');
        logger.d('用户名为空，尝试自动登录...');
        await autoLogin();
        if (username == null) {
          logger.d(
              '_ensureAuthenticatedAndReady: autoLogin failed or did not set username. Checking isAuthenticated...');
          logger.d('自动登录失败或未设置用户名，检查是否已认证...');
          if (!await _guard(() => _spotifyService.isAuthenticated())) {
            logger.w(
                '_ensureAuthenticatedAndReady: Not authenticated after autoLogin failure. Throwing SESSION_EXPIRED.');
            logger.w('自动登录后未认证，抛出 SESSION_EXPIRED');
            logger.d('===== SPOTIFY PROVIDER DEBUG END =====');
            throw SpotifyAuthException('需要登录', code: 'SESSION_EXPIRED');
          }
          logger.d('已认证但用户名为空，尝试获取用户资料...');
          final userProfile =
              await _guard(() => _spotifyService.getUserProfile());
          username = userProfile['display_name'];
          startTrackRefresh();
          _notifyCategory('default');
        }
        logger.d(
            '_ensureAuthenticatedAndReady: autoLogin processed. Username: $username');
        logger.d('自动登录处理完成。用户名: $username');
      }

      logger.d('检查是否需要连接 Remote...');
      if (!await _guard(() => _spotifyService.connectRemoteIfNeeded())) {
        logger.w('_ensureAuthenticatedAndReady: Failed to connect Remote');
        logger.w('连接 Remote 失败');
        // Since ignoreRemoteConnectionFailure = true, always ignore failure and continue
        logger.i(
            '_ensureAuthenticatedAndReady: Remote 连接失败，但已配置为忽略并继续 Web API 操作。');
        logger.i('Remote 连接失败，但已配置为忽略并继续 Web API 操作。');
      } else {
        logger.d(
            '_ensureAuthenticatedAndReady: connectRemoteIfNeeded succeeded or was skipped.');
        logger.d('Remote 连接成功或已跳过。');
      }

      logger.d('第一次获取播放状态...');
      var playbackState =
          await _guard(() => _spotifyService.getPlaybackState());
      var device = playbackState['device'];
      logger.d(
          '_ensureAuthenticatedAndReady: Initial playback state device: $device');
      logger.d('初次获取播放状态设备: $device');

      // 如果初次获取没有设备信息，尝试刷新设备列表再获取一次
      if (device == null) {
        logger.w(
            '_ensureAuthenticatedAndReady: No device in initial playback state. Refreshing devices and trying again...');
        logger.w('初次播放状态无设备，刷新设备列表后重试...');
        await refreshAvailableDevices();
        playbackState = await _guard(() => _spotifyService.getPlaybackState());
        device = playbackState['device'];
        logger.d(
            '_ensureAuthenticatedAndReady: Playback state after refresh device: $device');
        logger.d('刷新后播放状态设备: $device');
      }

      final hasDevice = device != null;
      final deviceName = hasDevice ? device['name'] : '无';
      final deviceId = hasDevice ? device['id'] : '无';
      final isActive = hasDevice ? device['is_active'] : false;
      final isRestricted = hasDevice ? device['is_restricted'] : false;

      logger.d(
          '播放状态设备信息: 有设备=$hasDevice, 名称=$deviceName, ID=$deviceId, 活跃=$isActive, 受限=$isRestricted');

      if (device == null) {
        // 如果仍然没有设备，根据您的建议，可以考虑显示设备选择器或允许_withDevice处理
        // 当前我们保持原来的逻辑：允许后续指令尝试执行
        logger.w(
            '_ensureAuthenticatedAndReady: No active device info even after refresh, but continuing to allow command attempt.');
        logger.w('刷新后仍无活跃设备信息，但继续尝试发送指令');
        // 即使没有设备，也返回 true，让 _withDevice 尝试处理
        logger.d('===== SPOTIFY PROVIDER DEBUG END =====');
        return true;
      }

      // 如果设备受限，则不应继续
      if (isRestricted) {
        logger.w(
            '_ensureAuthenticatedAndReady: Device is restricted. Cannot proceed with command.');
        logger.w('设备 ($deviceName) 受限，无法继续操作。');
        // 可以在这里抛出异常或向用户显示消息
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.deviceRestrictedMessage(deviceName))),
          );
        }
        logger.d('===== SPOTIFY PROVIDER DEBUG END =====');
        return false; // 阻止后续操作
      }

      // 设备可用，继续操作
      logger.d(
          '_ensureAuthenticatedAndReady: Authenticated and ready. Returning true.');
      logger.d('已认证并就绪，返回 true');
      logger.d('===== SPOTIFY PROVIDER DEBUG END =====');
      return true;
    } on SpotifyAuthException catch (e) {
      logger.e('捕获 SpotifyAuthException: ${e.message} (${e.code})');
      logger.d('===== SPOTIFY PROVIDER DEBUG END =====');
      rethrow;
    } catch (e) {
      logger.e('_ensureAuthenticatedAndReady: Error occurred', error: e);
      logger.e('发生错误: $e');
      logger.d('===== SPOTIFY PROVIDER DEBUG END =====');
      // 即便发生其他错误，也先尝试让 _handleApiError 处理，如果它重新抛出，则这里会捕获并返回 false
      // 如果 _handleApiError 成功处理（例如401后静默续签），则不会到这里
      await _handleApiError(e,
          contextMessage: '_ensureAuthenticatedAndReady',
          isUserInitiated: true);
      return false; // 如果 _handleApiError 没有重抛出会话过期等，则返回false阻止操作
    }
  }

  Future<void> togglePlayPause() async {
    logger.d('togglePlayPause: 开始执行');
    logger.d('===== TOGGLE PLAY/PAUSE DEBUG =====');
    logger.d('togglePlayPause: 开始执行');

    Map<String, dynamic>? initialPlaybackStateForRevert;
    try {
      logger.d('检查认证和设备就绪情况...');
      if (!await _ensureAuthenticatedAndReady()) {
        logger.w('togglePlayPause: _ensureAuthenticatedAndReady 返回 false，中止操作');
        logger.w('_ensureAuthenticatedAndReady 返回 false，中止操作');
        logger.d('===== TOGGLE PLAY/PAUSE DEBUG END =====');
        return;
      }
      logger.d('认证和设备检查通过');

      logger.d('获取当前播放状态...');
      final playbackState =
          await _guard(() => _spotifyService.getPlaybackState());
      initialPlaybackStateForRevert = playbackState;
      final bool isCurrentlyPlaying = playbackState['is_playing'] ?? false;

      logger.d('togglePlayPause: 当前播放状态 - isPlaying: $isCurrentlyPlaying');
      logger.d('当前播放状态 - isPlaying: $isCurrentlyPlaying');

      // 使用新的 togglePlayPause 方法替代直接调用 apiPut
      logger.d('togglePlayPause: 调用 _spotifyService.togglePlayPause()');
      logger.d('调用 _spotifyService.togglePlayPause()...');
      await _guard(() => _spotifyService.togglePlayPause());
      logger.d('togglePlayPause: _spotifyService.togglePlayPause() 调用成功');
      logger.d('_spotifyService.togglePlayPause() 调用成功');

      // 更新本地状态
      if (currentTrack != null) {
        currentTrack!['is_playing'] = !isCurrentlyPlaying; // 切换播放状态
        logger.d(
            'togglePlayPause: 更新本地状态 - is_playing: ${currentTrack!['is_playing']}');
        logger.d('更新本地状态 - is_playing: ${currentTrack!['is_playing']}');
      }

      _notifyCategory('track');

      logger.d('延时600毫秒后刷新曲目信息...');
      await Future.delayed(const Duration(milliseconds: 600));
      logger.d('togglePlayPause: 刷新当前曲目信息');
      logger.d('刷新当前曲目信息...');
      await refreshCurrentTrack();
      logger.d('更新组件...');
      await updateWidget();
      logger.d('togglePlayPause: 成功完成');
      logger.d('成功完成');
      logger.d('===== TOGGLE PLAY/PAUSE DEBUG END =====');
    } on SpotifyAuthException catch (e) {
      logger.e(
          'togglePlayPause: 捕获 SpotifyAuthException: ${e.message} (${e.code})');
      logger.e('捕获 SpotifyAuthException: ${e.message} (${e.code})');

      if (e.code == 'SESSION_EXPIRED' ||
          e.code == 'PROFILE_FETCH_ERROR_AFTER_REFRESH') {
        logger.d('togglePlayPause: Session expired, attempting login...');
        logger.d('会话过期，尝试登录...');
        try {
          await login();
          logger.d(
              'togglePlayPause: Login successful, retrying original play/pause command...');
          logger.d('登录成功，重试原始播放/暂停命令...');
          logger.d('===== TOGGLE PLAY/PAUSE DEBUG END =====');
          // 登录成功后重试原始指令
          await togglePlayPause();
        } catch (loginError) {
          if (loginError is SpotifyAuthException &&
              loginError.code == 'AUTH_CANCELLED') {
            logger.d('togglePlayPause: User cancelled login');
            logger.d('用户取消登录');
          } else {
            logger.e('togglePlayPause: Login failed', error: loginError);
            logger.e('登录失败: $loginError');
            // 恢复原始状态
            if (currentTrack != null && initialPlaybackStateForRevert != null) {
              currentTrack!['is_playing'] =
                  initialPlaybackStateForRevert['is_playing'] ?? false;
              logger.d('恢复原始播放状态: ${currentTrack!['is_playing']}');
              _notifyCategory('track');
            }
          }
          logger.d('===== TOGGLE PLAY/PAUSE DEBUG END =====');
        }
      } else {
        logger.e('togglePlayPause: Auth error occurred', error: e);
        logger.e('认证错误: ${e.message} (${e.code})');
        if (currentTrack != null && initialPlaybackStateForRevert != null) {
          currentTrack!['is_playing'] =
              initialPlaybackStateForRevert['is_playing'] ?? false;
          logger.d('恢复原始播放状态: ${currentTrack!['is_playing']}');
          _notifyCategory('track');
        }
        await _handleApiError(e,
            contextMessage: '播放/暂停切换 (auth error)', isUserInitiated: true);
        logger.d('===== TOGGLE PLAY/PAUSE DEBUG END =====');
      }
    } catch (e) {
      logger.e('togglePlayPause: Unknown error occurred', error: e);
      logger.e('发生未知错误: $e');
      if (currentTrack != null && initialPlaybackStateForRevert != null) {
        currentTrack!['is_playing'] =
            initialPlaybackStateForRevert['is_playing'] ?? false;
        logger.d('恢复原始播放状态: ${currentTrack!['is_playing']}');
        _notifyCategory('track');
      }
      await _handleApiError(e,
          contextMessage: '播放/暂停切换 (unknown error)', isUserInitiated: true);
      logger.d('===== TOGGLE PLAY/PAUSE DEBUG END =====');
    }
  }

  Future<void> seekToPosition(int positionMs) async {
    logger.d('seekToPosition: 开始执行，目标位置: $positionMs ms');
    if (!await _ensureAuthenticatedAndReady()) {
      logger.w('seekToPosition: _ensureAuthenticatedAndReady 返回 false，中止操作');
      return;
    }
    try {
      _isSkipping = true;
      logger.d('seekToPosition: 调用 _spotifyService.seekToPosition()');
      await _guard(() =>
          _spotifyService.seekToPosition(Duration(milliseconds: positionMs)));
      logger.d('seekToPosition: _spotifyService.seekToPosition() 调用成功');
    } catch (e) {
      logger.e('seekToPosition: 捕获错误', error: e);
      await _handleApiError(e,
          contextMessage: '跳转到指定位置', isUserInitiated: true);
    } finally {
      _isSkipping = false;
      logger.d('seekToPosition: 刷新当前曲目信息');
      await refreshCurrentTrack();
      logger.d('seekToPosition: 成功完成，当前进度: ${currentTrack?['progress_ms']}');
    }
  }

  Future<void> skipToNext() async {
    logger.d('skipToNext: 开始执行');
    if (!await _ensureAuthenticatedAndReady()) {
      logger.w('skipToNext: _ensureAuthenticatedAndReady 返回 false，中止操作');
      return;
    }
    try {
      _isSkipping = true;
      logger.d('skipToNext: 调用 _spotifyService.skipToNext()');
      await _guard(() => _spotifyService.skipToNext());
      logger.d('skipToNext: _spotifyService.skipToNext() 调用成功');
    } catch (e) {
      logger.e('skipToNext: 捕获错误', error: e);
      await _handleApiError(e, contextMessage: '播放下一首', isUserInitiated: true);
    } finally {
      _isSkipping = false;
      logger.d('skipToNext: 刷新当前曲目信息');
      await refreshCurrentTrack();
      logger.d('skipToNext: 成功完成');
    }
  }

  Future<void> skipToPrevious() async {
    logger.d('skipToPrevious: 开始执行');
    if (!await _ensureAuthenticatedAndReady()) {
      logger.w('skipToPrevious: _ensureAuthenticatedAndReady 返回 false，中止操作');
      return;
    }
    try {
      _isSkipping = true;
      logger.d('skipToPrevious: 调用 _spotifyService.skipToPrevious()');
      await _guard(() => _spotifyService.skipToPrevious());
      logger.d('skipToPrevious: _spotifyService.skipToPrevious() 调用成功');
    } catch (e) {
      logger.e('skipToPrevious: 捕获错误', error: e);
      await _handleApiError(e, contextMessage: '播放上一首', isUserInitiated: true);
    } finally {
      _isSkipping = false;
      logger.d('skipToPrevious: 刷新当前曲目信息');
      await refreshCurrentTrack();
      logger.d('skipToPrevious: 成功完成');
    }
  }

  Future<void> toggleTrackSave() async {
    if (currentTrack == null || currentTrack!['item'] == null) return;

    final trackId = currentTrack!['item']['id'];
    final originalState = isCurrentTrackSaved; // 记录原始状态以便出错时恢复

    try {
      // Optimistically update UI first for responsiveness
      isCurrentTrackSaved = !(isCurrentTrackSaved ?? false);
      _notifyCategory('track');

      // Call the API to toggle the save state
      await _guard(() => _spotifyService.toggleTrackSave(trackId));

      // Immediately fetch the actual state from Spotify to confirm
      final actualState =
          await _guard(() => _spotifyService.isTrackSaved(trackId));

      // If the actual state differs from the optimistic update, correct it
      if (isCurrentTrackSaved != actualState) {
        isCurrentTrackSaved = actualState;
        _notifyCategory('track');
      }

      // Optional: Add a very short delay ONLY if needed due to API eventual consistency
      // await Future.delayed(const Duration(milliseconds: 200));
      // final finalState = await _spotifyService.isTrackSaved(trackId);
      // if (finalState != isCurrentTrackSaved) {
      //   isCurrentTrackSaved = finalState;
      //   notifyListeners();
      // }
    } catch (e) {
      // debugPrint('切换收藏状态失败: $e');
      // Revert to the original state on error
      if (isCurrentTrackSaved != originalState) {
        isCurrentTrackSaved = originalState;
        _notifyCategory('track');
      }
      // Optionally re-check the state after error
      // try {
      //   isCurrentTrackSaved = await _spotifyService.isTrackSaved(trackId);
      //   _notifyCategory('track');
      // } catch (recheckError) {
      //   print('重新检查收藏状态失败: $recheckError');
      // }
      await _handleApiError(e, contextMessage: '切换收藏状态', isUserInitiated: true);
    }
  }

  List<Map<String, dynamic>> upcomingTracks = [];

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

  Future<void> refreshPlaybackQueue() async {
    try {
      final queue = await _guard(() => _spotifyService.getPlaybackQueue());
      final rawQueue = List<Map<String, dynamic>>.from(queue['queue'] ?? []);

      final queueChanged = _queuesDiffer(rawQueue);

      if (!queueChanged) {
        return;
      }

      // 移除队列长度限制
      upcomingTracks = rawQueue;

      // 更安全地获取下一首歌曲
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

      _notifyCategory('queue');

      // 队列更新后触发图片预加载
      _triggerImagePreload();
    } catch (e) {
      // debugPrint('刷新播放队列失败: $e');
      await _handleApiError(e, contextMessage: '刷新播放队列');
      upcomingTracks = [];
      nextTrack = null;
      _notifyCategory('queue');
    }
  }

  // 批量缓存队列图片
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
      // debugPrint('批量缓存队列图片失败: $e');
    }
  }

  // 获取当前播放模式
  Future<void> syncPlaybackMode() async {
    try {
      final state = await _guard(() => _spotifyService.getPlaybackState());
      final repeatMode = state['repeat_state'];
      final isShuffling = state['shuffle_state'] ?? false;

      // 如果用户设置了其他模式组合，默认转为顺序播放
      if (repeatMode == 'track' && !isShuffling) {
        _currentMode = PlayMode.singleRepeat;
      } else if (repeatMode == 'context' && !isShuffling) {
        _currentMode = PlayMode.sequential;
      } else if (repeatMode == 'context' && isShuffling) {
        _currentMode = PlayMode.shuffle;
      } else {
        // 其他情况默认设置为顺序播放
        await setPlayMode(PlayMode.sequential);
      }
      _notifyCategory('track');
    } catch (e) {
      // debugPrint('同步播放模式失败: $e');
      await _handleApiError(e, contextMessage: '同步播放模式');
    }
  }

  // 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    try {
      switch (mode) {
        case PlayMode.singleRepeat:
          await _guard(() => _spotifyService.setRepeatMode('track'));
          await _guard(() => _spotifyService.setShuffle(false));
          break;
        case PlayMode.sequential:
          await _guard(() => _spotifyService.setRepeatMode('context'));
          await _guard(() => _spotifyService.setShuffle(false));
          break;
        case PlayMode.shuffle:
          await _guard(() => _spotifyService.setRepeatMode('context'));
          await _guard(() => _spotifyService.setShuffle(true));
          break;
      }
      _currentMode = mode;
      await refreshPlaybackQueue();
      _notifyCategory('track');
    } catch (e) {
      // debugPrint('设置播放模式失败: $e');
      await _handleApiError(e, contextMessage: '设置播放模式', isUserInitiated: true);
    }
  }

  // 循环切换播放模式
  Future<void> togglePlayMode() async {
    final nextMode =
        PlayMode.values[(currentMode.index + 1) % PlayMode.values.length];
    await setPlayMode(nextMode);
  }

  // 预加载图片的方法 (旧版保留用于兼容)
  Future<void> _preloadImage(String? imageUrl) async {
    if (imageUrl == null || _imageCache.containsKey(imageUrl)) return;
    if (navigatorKey.currentContext == null) return; // Add null check

    try {
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      await precacheImage(imageProvider, navigatorKey.currentContext!);
      _imageCache[imageUrl] = imageUrl;
    } catch (e) {
      // debugPrint('预加载图片失败: $e');
    }
  }

  /// 触发播放相关图片的智能预加载
  ///
  /// 使用 ImagePreloadManager 预加载当前曲目、下一首、以及队列中的封面图片
  void _triggerImagePreload() {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    // 异步执行预加载，不阻塞主流程
    Future.microtask(() {
      _albumArtPreloader.preloadForPlayback(
        context: context,
        currentTrack: currentTrack,
        nextTrack: nextTrack,
        upcomingTracks: upcomingTracks,
      );
    });
  }

  Future<Map<String, dynamic>> fetchAlbumDetails(String albumId,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _albumCache.containsKey(albumId)) {
      return _albumCache[albumId]!;
    }

    final albumRaw = await _guard(() => _spotifyService.getAlbum(albumId));
    final Map<String, dynamic> albumData = Map<String, dynamic>.from(albumRaw);

    final Map<String, dynamic> tracksSection = Map<String, dynamic>.from(
        (albumData['tracks'] as Map<String, dynamic>? ?? {}));
    final initialItems = tracksSection['items'] as List? ?? const [];
    final List<Map<String, dynamic>> allTracks = [
      for (final item in initialItems)
        if (item is Map<String, dynamic>) Map<String, dynamic>.from(item)
    ];

    final total = (tracksSection['total'] as int?) ?? allTracks.length;
    var offset = allTracks.length;

    while (offset < total) {
      final page = await _guard(
          () => _spotifyService.getAlbumTracks(albumId, offset: offset));
      final pageItems = page['items'] as List? ?? const [];
      final extracted = <Map<String, dynamic>>[
        for (final item in pageItems)
          if (item is Map<String, dynamic>) Map<String, dynamic>.from(item)
      ];
      if (extracted.isEmpty) {
        break;
      }
      allTracks.addAll(extracted);
      offset = allTracks.length;
      if (page['next'] == null) {
        break;
      }
    }

    tracksSection['items'] = allTracks;
    tracksSection['total'] = allTracks.length;
    albumData['tracks'] = tracksSection;

    _albumCache[albumId] = albumData;
    return albumData;
  }

  Future<Map<String, dynamic>> fetchPlaylistDetails(String playlistId,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _playlistCache.containsKey(playlistId)) {
      return _playlistCache[playlistId]!;
    }

    final playlistRaw =
        await _guard(() => _spotifyService.getPlaylist(playlistId));
    final Map<String, dynamic> playlistData =
        Map<String, dynamic>.from(playlistRaw);

    final Map<String, dynamic> tracksSection = Map<String, dynamic>.from(
        (playlistData['tracks'] as Map<String, dynamic>? ?? {}));

    final allTracks = <Map<String, dynamic>>[];

    void addTrackFromContainer(Map<String, dynamic> container) {
      final track = container['track'];
      if (track is Map<String, dynamic>) {
        final trackMap = Map<String, dynamic>.from(track);
        if (trackMap['id'] != null) {
          allTracks.add(trackMap);
        }
      }
    }

    final initialItems = tracksSection['items'] as List? ?? const [];
    for (final item in initialItems) {
      if (item is Map<String, dynamic>) {
        addTrackFromContainer(item);
      }
    }

    final total = (tracksSection['total'] as int?) ?? allTracks.length;
    var offset = initialItems.length;

    while (offset < total) {
      final page = await _guard(
          () => _spotifyService.getPlaylistTracks(playlistId, offset: offset));
      final pageItems = page['items'] as List? ?? const [];
      if (pageItems.isEmpty) {
        break;
      }
      for (final item in pageItems) {
        if (item is Map<String, dynamic>) {
          addTrackFromContainer(item);
        }
      }
      offset += pageItems.length;
      if (page['next'] == null) {
        break;
      }
    }

    tracksSection['items'] = allTracks;
    tracksSection['total'] = allTracks.length;
    playlistData['tracks'] = tracksSection;

    _playlistCache[playlistId] = playlistData;
    return playlistData;
  }

  // 存储最近播放的播放列表和专辑
  final List<Map<String, dynamic>> _recentPlaylists = [];
  final List<Map<String, dynamic>> _recentAlbums = [];

  List<Map<String, dynamic>> get recentPlaylists => _recentPlaylists;
  List<Map<String, dynamic>> get recentAlbums => _recentAlbums;

  // 刷新最近播放记录
  Future<void> refreshRecentlyPlayed() async {
    try {
      final data =
          await _guard(() => _spotifyService.getRecentlyPlayed(limit: 50));
      final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

      final playlistUris = <String>{};
      final albumUris = <String>{};
      final List<Map<String, dynamic>> uniquePlaylists = [];
      final List<Map<String, dynamic>> uniqueAlbums = [];

      // 获取 LocalDatabaseProvider 实例用于保存播放上下文
      LocalDatabaseProvider? localDbProvider;
      try {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          localDbProvider =
              Provider.of<LocalDatabaseProvider>(context, listen: false);
        }
      } catch (e) {
        logger.w(
            'refreshRecentlyPlayed: Failed to get LocalDatabaseProvider: $e');
      }

      for (var item in items) {
        final context = item['context'];
        if (context != null) {
          final uri = context['uri'] as String;
          final type = context['type'] as String;
          final playedAt = DateTime.parse(item['played_at']);

          // 保存播放上下文到本地数据库
          if (localDbProvider != null) {
            try {
              await localDbProvider.insertOrUpdatePlayContext(
                contextUri: uri,
                contextType: type,
                contextName: context['name'] ??
                    '未知${type == 'playlist' ? '播放列表' : '专辑'}',
                imageUrl: null, // 在这里我们暂时不获取图片，因为会增加 API 调用
                lastPlayedAt: playedAt.millisecondsSinceEpoch,
              );
            } catch (dbError) {
              logger.e(
                  'refreshRecentlyPlayed: Failed to save context to database: $dbError');
            }
          }

          // 处理播放列表
          if (type == 'playlist' && !playlistUris.contains(uri)) {
            playlistUris.add(uri);
            final playlistId = uri.split(':').last;
            try {
              final playlist =
                  await _guard(() => _spotifyService.getPlaylist(playlistId));
              uniquePlaylists.add(playlist);
              if (uniquePlaylists.length >= 10) break;
            } catch (e) {
              // debugPrint('获取播放列表 $playlistId 详情失败: $e');
            }
          }

          // 处理专辑
          else if (type == 'album' && !albumUris.contains(uri)) {
            albumUris.add(uri);
            final albumId = uri.split(':').last;
            try {
              final album =
                  await _guard(() => _spotifyService.getAlbum(albumId));
              uniqueAlbums.add(album);
              if (uniqueAlbums.length >= 10) break;
            } catch (e) {
              // debugPrint('获取专辑 $albumId 详情失败: $e');
            }
          }
        }
      }

      _recentPlaylists
        ..clear()
        ..addAll(uniquePlaylists);
      _recentAlbums
        ..clear()
        ..addAll(uniqueAlbums);

      _notifyCategory('default');
    } catch (e) {
      // debugPrint('刷新最近播放记录失败: $e');
      await _handleApiError(e, contextMessage: '刷新最近播放记录');
    }
  }

  // 在 SpotifyProvider 类中添加 logout 方法
  Future<void> logout() async {
    bool wasLoading = isLoading;
    if (!wasLoading) {
      isLoading = true;
      _notifyCategory('default');
    }

    try {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _progressTimer?.cancel();
      _progressTimer = null;

      // 注销时重置loading状态
      if (isLoading) {
        logger.d('注销时重置isLoading状态');
        isLoading = false;
      }

      username = null;
      currentTrack = null;
      previousTrack = null;
      nextTrack = null;
      isCurrentTrackSaved = null;
      _availableDevices.clear();
      _activeDeviceId = null;
      upcomingTracks.clear();
      // Keep image cache across login sessions to avoid reloading
      // _imageCache.clear(); // OPTIMIZATION: Don't clear image cache on logout
      _recentAlbums.clear();
      _recentPlaylists.clear();
      _albumCache.clear();
      _playlistCache.clear();

      if (!_isInitialized) _bootstrap();
      if (_isInitialized) {
        await _guard(() => _spotifyService.logout());
      }

      await updateWidget();
    } catch (e) {
      rethrow;
    } finally {
      if (!wasLoading) {
        isLoading = false;
      }
      _notifyCategory('default');
    }
  }

  Future<void> updateWidget() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const platform = MethodChannel('com.gojyuplusone.spotoolfy/widget');
      try {
        await platform.invokeMethod('updateWidget', {
          'songName': currentTrack?['item']?['name'] ?? '未在播放',
          'artistName': currentTrack?['item']?['artists']?[0]?['name'] ?? '',
          'albumArtUrl':
              currentTrack?['item']?['album']?['images']?[0]?['url'] ?? '',
          'isPlaying': currentTrack?['is_playing'] ?? false,
        });
      } catch (e) {
        // debugPrint('更新 widget 失败: $e');
      }
    }
  }

  /// 播放专辑或播放列表
  Future<void> playContext({
    required String type,
    required String id,
    int? offsetIndex,
    String? deviceId, // deviceId is now less relevant for initial play
  }) async {
    // Check for active device BEFORE attempting to play
    if (!await _ensureAuthenticatedAndReady()) {
      return; // Stop if no active device and picker is shown
    }

    try {
      final contextUri = 'spotify:$type:$id';

      // Get the current active device ID if not explicitly provided
      final targetDeviceId = deviceId ?? activeDeviceId;

      await _guard(() => _spotifyService.playContext(
            contextUri: contextUri,
            offsetIndex: offsetIndex,
            deviceId: targetDeviceId, // Use the determined device ID
          ));

      // Wait slightly to allow Spotify state to update
      await Future.delayed(const Duration(milliseconds: 500));

      // Refresh state after initiating play
      await refreshCurrentTrack();
      await refreshPlaybackQueue();
    } catch (e) {
      // debugPrint('播放 $type 失败: $e');
      await _handleApiError(e,
          contextMessage: '播放 $type', isUserInitiated: true);
      // Check if the error is due to a restricted device (already handled by _handleApiError or original throw)
      if (e is SpotifyAuthException && e.code == 'RESTRICTED_DEVICE') {
        // Show a snackbar or dialog informing the user
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      } else if (e is! SpotifyAuthException || e.code != 'SESSION_EXPIRED') {
        // Rethrow if it wasn't a 401 leading to logout, or a restricted device
        rethrow;
      }
    }
  }

  /// 播放指定歌曲
  Future<void> playTrack({
    required String trackUri,
    String? deviceId, // deviceId is now less relevant for initial play
    String? contextUri,
    int? offsetIndex,
  }) async {
    // Check for active device BEFORE attempting to play
    if (!await _ensureAuthenticatedAndReady()) {
      return; // Stop if no active device and picker is shown
    }

    try {
      // Get the current active device ID if not explicitly provided
      final targetDeviceId = deviceId ?? activeDeviceId;

      if (contextUri != null) {
        // If context is provided, play within that context
        await _guard(() => _spotifyService.playTrackInContext(
              contextUri: contextUri,
              trackUri: trackUri,
              deviceId: targetDeviceId,
              offsetIndex: offsetIndex,
            ));
      } else {
        // Otherwise, play the track individually
        await _guard(() => _spotifyService.playTrack(
              trackUri: trackUri,
              deviceId: targetDeviceId,
            ));
      }

      // Wait slightly to allow Spotify state to update
      await Future.delayed(const Duration(milliseconds: 500));

      // Refresh state after initiating play
      await refreshCurrentTrack();
      await refreshPlaybackQueue();
    } catch (e) {
      // debugPrint('播放歌曲失败: $e');
      await _handleApiError(e, contextMessage: '播放歌曲', isUserInitiated: true);
      // Check if the error is due to a restricted device
      if (e is SpotifyAuthException && e.code == 'RESTRICTED_DEVICE') {
        // Show a snackbar or dialog informing the user
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
      // Consider rethrowing other errors
      rethrow;
    }
  }

  // Note: _spotifyService.playTrackInContext already handles restricted devices
  // But we still add the initial active device check
  Future<void> playTrackInContext({
    required String contextUri,
    required String trackUri,
    String? deviceId, // deviceId is now less relevant for initial play
    int? offsetIndex,
  }) async {
    // Check for active device BEFORE attempting to play
    if (!await _ensureAuthenticatedAndReady()) {
      return; // Stop if no active device and picker is shown
    }

    try {
      // Get the current active device ID if not explicitly provided
      final targetDeviceId = deviceId ?? activeDeviceId;

      // Call the service method which includes its own device checks
      await _guard(() => _spotifyService.playTrackInContext(
            contextUri: contextUri,
            trackUri: trackUri,
            deviceId: targetDeviceId,
            offsetIndex: offsetIndex,
          ));

      // Wait slightly to allow Spotify state to update
      await Future.delayed(const Duration(milliseconds: 500));

      // Refresh state after initiating play
      await refreshCurrentTrack();
      await refreshPlaybackQueue();
    } catch (e) {
      // debugPrint('在上下文中播放歌曲时出错: $e');
      await _handleApiError(e,
          contextMessage: '在上下文中播放歌曲', isUserInitiated: true);
      // Check if the error is due to a restricted device (already handled by service, but catch here too for UI feedback)
      if (e is SpotifyAuthException && e.code == 'RESTRICTED_DEVICE') {
        // Show a snackbar or dialog informing the user
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      } else if (e is! SpotifyAuthException || e.code != 'SESSION_EXPIRED') {
        rethrow;
      }
    }
  }

  /// Get authenticated headers from the Spotify service
  Future<Map<String, String>> getAuthenticatedHeaders() async {
    // Ensure service is initialized
    if (!_isInitialized) _bootstrap();
    if (!_isInitialized) throw Exception('Spotify Service not initialized.');
    return await _guard(() => _spotifyService.getAuthenticatedHeaders());
  }

  /// 获取用户的播放列表
  Future<List<Map<String, dynamic>>> getUserPlaylists(
      {int limit = 50, int offset = 0}) async {
    try {
      if (!await _guard(() => _spotifyService.isAuthenticated())) {
        // debugPrint('未登录，无法获取播放列表');
        return [];
      }

      final response = await _guard(() =>
          _spotifyService.apiGet('/me/playlists?limit=$limit&offset=$offset'));
      if (response['items'] == null) return [];

      final List<Map<String, dynamic>> playlists =
          List<Map<String, dynamic>>.from(response['items'].map((item) => {
                'id': item['id'],
                'type': 'playlist',
                'name': item['name'],
                'uri': item['uri'],
                'images': item['images'],
                'owner': item['owner'],
                'tracks': item['tracks'],
                'context': {
                  'uri': item['uri'],
                  'name': item['name'],
                  'type': 'playlist',
                  'images': item['images'],
                }
              }));

      // 如果有更多数据且请求的是第一页，递归获取后续页面
      final bool hasMoreItems = response['next'] != null;
      if (hasMoreItems && offset == 0) {
        // 获取总数以计算需要的请求次数
        final int total = response['total'] ?? 0;
        final int maxRequests = 5; // 最多请求5页，避免过多API调用
        final int pages = ((total - limit) / limit).ceil();
        final int requestCount = pages > maxRequests ? maxRequests : pages;

        List<Map<String, dynamic>> additionalPlaylists = [];

        for (int i = 1; i <= requestCount; i++) {
          final nextOffset = offset + (limit * i);
          final nextPlaylists =
              await getUserPlaylists(limit: limit, offset: nextOffset);
          additionalPlaylists.addAll(nextPlaylists);
        }

        playlists.addAll(additionalPlaylists);
      }

      return playlists;
    } catch (e) {
      // debugPrint('获取用户播放列表失败: $e');
      await _handleApiError(e,
          contextMessage: '获取用户播放列表', isUserInitiated: true);
      return [];
    }
  }

  /// 获取用户收藏的专辑
  Future<List<Map<String, dynamic>>> getUserSavedAlbums(
      {int limit = 50, int offset = 0}) async {
    try {
      if (!await _guard(() => _spotifyService.isAuthenticated())) {
        // debugPrint('未登录，无法获取收藏专辑');
        return [];
      }

      final response = await _guard(() =>
          _spotifyService.apiGet('/me/albums?limit=$limit&offset=$offset'));
      if (response['items'] == null) return [];

      final List<Map<String, dynamic>> albums =
          List<Map<String, dynamic>>.from(response['items'].map((item) => {
                'id': item['album']['id'],
                'type': 'album',
                'name': item['album']['name'],
                'uri': item['album']['uri'],
                'images': item['album']['images'],
                'artists': item['album']['artists'],
                'context': {
                  'uri': item['album']['uri'],
                  'name': item['album']['name'],
                  'type': 'album',
                  'images': item['album']['images'],
                }
              }));

      // 如果有更多数据且请求的是第一页，递归获取后续页面
      final bool hasMoreItems = response['next'] != null;
      if (hasMoreItems && offset == 0) {
        // 获取总数以计算需要的请求次数
        final int total = response['total'] ?? 0;
        final int maxRequests = 5; // 最多请求5页，避免过多API调用
        final int pages = ((total - limit) / limit).ceil();
        final int requestCount = pages > maxRequests ? maxRequests : pages;

        List<Map<String, dynamic>> additionalAlbums = [];

        for (int i = 1; i <= requestCount; i++) {
          final nextOffset = offset + (limit * i);
          final nextAlbums =
              await getUserSavedAlbums(limit: limit, offset: nextOffset);
          additionalAlbums.addAll(nextAlbums);
        }

        albums.addAll(additionalAlbums);
      }

      return albums;
    } catch (e) {
      // debugPrint('获取收藏专辑失败: $e');
      await _handleApiError(e, contextMessage: '获取收藏专辑', isUserInitiated: true);
      return [];
    }
  }

  /// 获取最近播放的记录
  Future<List<Map<String, dynamic>>> getRecentlyPlayed() async {
    try {
      if (!await _guard(() => _spotifyService.isAuthenticated())) {
        // debugPrint('未登录，无法获取最近播放');
        return [];
      }

      final response = await _guard(
          () => _spotifyService.apiGet('/me/player/recently-played?limit=50'));
      if (response['items'] == null) return [];

      // 提取唯一的上下文（专辑和播放列表）
      final Map<String, Map<String, dynamic>> uniqueContexts = {};

      for (final item in response['items']) {
        if (item['context'] != null) {
          final contextUri = item['context']['uri'];
          if (!uniqueContexts.containsKey(contextUri)) {
            final contextType =
                contextUri.split(':')[1]; // playlist, album, etc.
            final contextId = contextUri.split(':').last;

            // 为上下文获取更详细信息
            Map<String, dynamic> details = {};
            try {
              details = await _guard(
                  () => _spotifyService.apiGet('/$contextType' 's/$contextId'));
            } catch (e) {
              // debugPrint('获取上下文详情失败: $e');
            }

            uniqueContexts[contextUri] = {
              'id': contextId,
              'type': contextType,
              'uri': contextUri,
              'name': details['name'] ?? 'Unknown',
              'images': details['images'] ?? [],
              'context': {
                'uri': contextUri,
                'type': contextType,
                'name': details['name'] ?? 'Unknown',
                'images': details['images'] ?? [],
              }
            };
          }
        }
      }

      return uniqueContexts.values.toList();
    } catch (e) {
      // debugPrint('获取最近播放记录失败: $e');
      return [];
    }
  }

  /// Fetches the raw list of recently played track items from Spotify.
  Future<List<Map<String, dynamic>>> getRecentlyPlayedRawTracks(
      {int limit = 50}) async {
    try {
      if (!await _guard(() => _spotifyService.isAuthenticated())) {
        // debugPrint('未登录，无法获取原始最近播放记录');
        return [];
      }
      return await _guard(
          () => _spotifyService.getRecentlyPlayedRawTracks(limit: limit));
    } catch (e) {
      // debugPrint('获取原始最近播放记录失败: $e');
      return [];
    }
  }

  /// Search for items (tracks, albums, artists, playlists)
  Future<Map<String, List<Map<String, dynamic>>>> searchItems(String query,
      {List<String> types = const ['track', 'album', 'artist', 'playlist'],
      int limit = 20}) async {
    if (!_isInitialized) {
      _bootstrap();
    }
    if (!_isInitialized) {
      throw Exception('Spotify service could not be initialized.');
    }

    try {
      if (query.trim().isEmpty) return {};

      // Call the search method in SpotifyAuthService
      // Pass types as the second argument, and limit as a named argument
      final response = await _guard(
          () => _spotifyService.search(query, types, limit: limit));

      // --- Add logging for decoded response ---
      // debugPrint('SpotifyProvider.searchItems - Decoded Response:');
      // debugPrint(json.encode(response));
      // --- End logging ---

      final Map<String, List<Map<String, dynamic>>> results = {};

      // Process tracks
      if (response['tracks']?['items'] != null && types.contains('track')) {
        // debugPrint('Processing tracks...');
        results['tracks'] = List<Map<String, dynamic>>.from(
            (response['tracks']['items'] as List)
                .where((item) =>
                    item != null &&
                    item['id'] != null &&
                    item['name'] != null &&
                    item['album']?['images'] != null)
                .map((item) => {
                      'id': item['id'],
                      'type': 'track',
                      'name': item['name'],
                      'uri': item['uri'],
                      'album': item['album'],
                      'artists': item['artists'],
                      'duration_ms': item['duration_ms'],
                      'images': (item['album']?['images'] is List &&
                              (item['album']['images'] as List).isNotEmpty)
                          ? item['album']['images']
                          : null,
                    })
                .where((item) => item['images'] != null));
      }

      // Process albums
      if (response['albums']?['items'] != null && types.contains('album')) {
        // debugPrint('Processing albums...');
        results['albums'] = List<Map<String, dynamic>>.from((response['albums']
                ['items'] as List)
            .where((item) =>
                item != null &&
                item['id'] != null &&
                item['name'] != null &&
                item['images'] != null)
            .map((item) => {
                  'id': item['id'],
                  'type': 'album',
                  'name': item['name'],
                  'uri': item['uri'],
                  'artists': item['artists'],
                  'images': item['images'],
                })
            .where((item) =>
                item['images'] != null && (item['images'] as List).isNotEmpty));
      }

      // Process artists
      if (response['artists']?['items'] != null && types.contains('artist')) {
        // debugPrint('Processing artists...');
        results['artists'] = List<Map<String, dynamic>>.from(
            (response['artists']['items'] as List)
                .where((item) =>
                    item != null &&
                    item['id'] != null &&
                    item['name'] != null &&
                    item['images'] != null)
                .map((item) => {
                      'id': item['id'],
                      'type': 'artist',
                      'name': item['name'],
                      'uri': item['uri'],
                      'images': item['images'],
                    })
                .where((item) =>
                    item['images'] != null &&
                    (item['images'] as List).isNotEmpty));
      }

      // Process playlists
      if (response['playlists']?['items'] != null &&
          types.contains('playlist')) {
        // debugPrint('Processing playlists...');
        results['playlists'] = List<Map<String, dynamic>>.from(
            (response['playlists']['items'] as List)
                .where((item) =>
                    item != null &&
                    item['id'] != null &&
                    item['name'] != null &&
                    item['images'] != null)
                .map((item) => {
                      'id': item['id'],
                      'type': 'playlist',
                      'name': item['name'],
                      'uri': item['uri'],
                      'owner': item['owner'],
                      'images': item['images'],
                    })
                .where((item) =>
                    item['images'] != null &&
                    (item['images'] as List).isNotEmpty));
      }

      // --- Add logging for final results map ---
      // debugPrint('SpotifyProvider.searchItems - Final Results Map:');
      // debugPrint(json.encode(results));
      // --- End logging ---

      return results;
    } catch (e) {
      // debugPrint('Spotify search failed: $e');
      // Depending on how you want to handle errors, you might return empty or rethrow
      // rethrow;
      return {}; // Return empty map on error for now
    }
  }

  // --- 添加新的错误处理辅助方法 ---

  /// 检查是否为网络连接错误
  bool _isNetworkError(dynamic error) {
    final errorString = error.toString().toLowerCase(); // 转为小写以增加匹配鲁棒性
    bool isNetworkErrorType = false;

    if (error is SpotifyAuthException) {
      // 检查来自 SpotifyAuthService 的特定网络错误代码
      isNetworkErrorType = error.code == 'NETWORK_RETRY_EXHAUSTED' ||
          error.code == 'RETRY_LOGIC_ERROR' || // 通常不应发生，但作为网络相关问题处理
          error.code == 'OPERATION_FAILED_UNKNOWN' ||
          error.code == 'TOKEN_REFRESH_FAILED_NETWORK';
    }

    // 检查通用的网络错误关键字
    isNetworkErrorType = isNetworkErrorType ||
        errorString.contains('socketexception') ||
        errorString.contains('timeoutexception') ||
        errorString.contains(
            'clientexception') || // 包括 ClientException with SocketException
        errorString.contains('connection') ||
        errorString.contains('software caused connection abort') ||
        errorString.contains('host unreachable') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('network_error') || // 通用网络错误标记
        errorString.contains('failed host lookup') || // DNS解析失败
        errorString.contains('os error: connection refused'); // 连接被拒绝

    if (isNetworkErrorType) {
      _consecutiveNetworkErrors++;
      // Network issue tracking removed

      logger.w('检测到网络错误 (连续第 $_consecutiveNetworkErrors 次): $errorString');

      // 如果连续网络错误超过3次，暂停定时刷新一段时间
      if (_consecutiveNetworkErrors >= 3 && _refreshTimer != null) {
        // 仅当定时器存在时才操作
        logger.w('连续网络错误过多，暂停定时刷新30秒');
        _pauseRefreshTimerTemporarily();
      }
    } else {
      // 成功的请求或非网络错误，重置网络错误计数
      if (_consecutiveNetworkErrors > 0) {
        logger.i('网络连接已恢复或错误非网络相关，重置错误计数');
        _consecutiveNetworkErrors = 0;
        // Network issue tracking removed
      }
    }

    return isNetworkErrorType;
  }

  /// 暂时暂停刷新定时器
  void _pauseRefreshTimerTemporarily() {
    _refreshTimer?.cancel();

    // 30秒后重新启动定时器
    Future.delayed(const Duration(seconds: 30), () {
      if (username != null && _refreshTimer == null) {
        logger.i('网络错误恢复期结束，重新启动定时刷新');
        startTrackRefresh();
      }
    });
  }

  void _showNetworkSnackBarIfNeeded(bool isUserInitiated) {
    // No longer surface background or foreground network snack bars; logging already captures the issue.
    // Method kept to avoid touching all call sites.
  }

  void _notifyUser(String message, {Color? severityColor}) {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: severityColor ?? Colors.grey[800],
        ),
      );
    }
  }

  /// 详细的错误日志记录和分析
  void _logDetailedError(dynamic error, String contextMessage) {
    if (error is SpotifyAuthException) {
      switch (error.code) {
        case '401':
          logger.w('[$contextMessage] 授权过期或无效: ${error.message}');
          break;
        case '403':
          logger.w('[$contextMessage] 权限不足: ${error.message}');
          break;
        case '404':
          logger.w('[$contextMessage] 资源未找到: ${error.message}');
          break;
        case '429':
          logger.w('[$contextMessage] 请求频率限制: ${error.message}');
          break;
        case 'CLIENT_ID_MISSING':
          logger.e('[$contextMessage] 客户端ID未配置: ${error.message}');
          break;
        case 'CSRF_PROTECTION':
          logger.e('[$contextMessage] CSRF防护触发: ${error.message}');
          break;
        case 'INVALID_TOKEN_FORMAT':
          logger.e('[$contextMessage] 无效的令牌格式: ${error.message}');
          break;
        case 'SESSION_EXPIRED':
          logger.i('[$contextMessage] 会话已过期，需要重新登录');
          break;
        case 'RESTRICTED_DEVICE':
          logger.w('[$contextMessage] 设备受限: ${error.message}');
          break;
        default:
          logger.e(
              '[$contextMessage] Spotify API错误 (${error.code}): ${error.message}');
      }
    } else if (error.toString().contains('SocketException') ||
        error.toString().contains('NetworkException')) {
      logger.w('[$contextMessage] 网络连接问题: $error');
    } else if (error.toString().contains('TimeoutException')) {
      logger.w('[$contextMessage] 请求超时: $error');
    } else {
      logger.e('[$contextMessage] 未知错误: $error',
          error: error, stackTrace: error is Error ? error.stackTrace : null);
    }
  }

  Future<void> _handleApiError(dynamic e,
      {String? contextMessage, bool isUserInitiated = false}) async {
    final message = contextMessage ?? 'API 调用';

    // 详细的错误分析和日志
    _logDetailedError(e, message);

    // 检查是否为网络连接错误
    if (_isNetworkError(e)) {
      logger.w('$message 遇到网络连接错误: $e');
      _showNetworkSnackBarIfNeeded(isUserInitiated);
      return;
    }

    if (e is SpotifyAuthException && e.code == '401') {
      logger.w('检测到401认证错误，尝试智能恢复...');
      logger.i('$message 遇到 401，尝试静默续约/重连...');
      try {
        final token = await _guard(() => _spotifyService.getAccessToken());
        if (token != null) {
          try {
            // Re-fetch user profile and re-initialize session state
            final userProfile =
                await _guard(() => _spotifyService.getUserProfile());
            username = userProfile['display_name'];
            _notifyCategory('default');
            startTrackRefresh();
          } catch (profileError) {
            await logout();
            throw SpotifyAuthException('会话已恢复但无法获取用户信息，请重新登录。',
                code: 'PROFILE_FETCH_ERROR_AFTER_REFRESH');
          }
          return; // Silent refresh succeeded
        }
        // Token 为 null，视为真正过期
        await logout();
        throw SpotifyAuthException('会话已过期，请重新登录', code: 'SESSION_EXPIRED');
      } on SpotifyAuthException catch (refreshError) {
        // 针对刷新阶段的特定错误进行细分处理
        if (refreshError.code == 'TOKEN_REFRESH_FAILED_NETWORK') {
          logger.w('静默刷新失败：网络异常，保持当前登录状态');
          _showNetworkSnackBarIfNeeded(isUserInitiated);
          return;
        }

        if (refreshError.code == 'AUTH_CANCELLED') {
          logger.i('静默刷新被取消，保持当前状态');
          return;
        }

        if (refreshError.code == 'IOS_CONNECTION_FAILED') {
          _notifyUser(
            '无法连接 Spotify，请确认已安装并登录 Spotify 应用后重试。',
            severityColor: Colors.orange,
          );
          return;
        }

        if (refreshError.code == 'CONFIG_ERROR') {
          _notifyUser('Spotify SDK 配置异常，请检查客户端 ID / Redirect URI 设置。');
          throw refreshError;
        }

        // 未知错误，回退到要求用户重新登录，但不立即清除状态
        throw SpotifyAuthException('无法刷新会话，请重新登录', code: 'SESSION_EXPIRED');
      }
    } else if (e is SpotifyAuthException &&
        (e.code == '403' || e.code == '415')) {
      logger.w('$message 遇到 ${e.code}: ${e.message}');
      final context = navigatorKey.currentContext;

      if (e.code == '403') {
        final lowerCaseMessage = e.message.toLowerCase();

        // 特别处理 insufficient_client_scope 错误
        if (lowerCaseMessage.contains('insufficient') &&
            (lowerCaseMessage.contains('scope') ||
                lowerCaseMessage.contains('client'))) {
          logger.w('检测到 insufficient_client_scope 错误，触发重新登录: ${e.message}');

          if (context != null && context.mounted) {
            final l10n = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.insufficientPermissionsReauth),
                duration: const Duration(seconds: 2),
              ),
            );
          }

          try {
            // 强制重新登录以获取完整的scope
            await login();
            logger.i('insufficient_client_scope: 重新登录成功，返回允许重试');
            return; // 允许调用方重试原始操作
          } catch (loginError) {
            logger.e('insufficient_client_scope: 重新登录失败: $loginError');
            if (context != null && context.mounted) {
              final l10n = AppLocalizations.of(context)!;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.reauthFailedManualLogin),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            // 重新登录失败，抛出会话过期错误
            throw SpotifyAuthException('权限范围不足且重新登录失败，请手动重新登录',
                code: 'SESSION_EXPIRED');
          }
        }

        // 处理其他已知的403错误
        if (context != null && context.mounted) {
          String displayMessage;
          bool isHandledKnown403 = false;

          if (lowerCaseMessage.contains('premium')) {
            displayMessage = '此操作需要 Spotify Premium 会员。';
            isHandledKnown403 = true;
          } else if (lowerCaseMessage.contains('restricted') ||
              lowerCaseMessage.contains('restriction violated')) {
            final l10n = context != null ? AppLocalizations.of(context)! : null;
            displayMessage = l10n?.deviceOperationNotSupported ??
                '当前设备不支持此操作或受限。请尝试在其他设备上播放音乐，或检查您的账户类型。';
            isHandledKnown403 = true;
          } else {
            displayMessage = '权限不足 (403): ${e.message}';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(displayMessage)),
          );

          // 对于已知的403错误，不重新抛出
          if (isHandledKnown403) {
            logger.i('已处理的403错误 (${e.message})，不再重新抛出。');
            return;
          }
        }
      } else {
        // 415 或其他错误码
        if (context != null && context.mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.badRequestError(e.code ?? 'UNKNOWN'))),
          );
        }
      }

      throw e;
    } else {
      logger.e('$message 遇到其他错误，将重新抛出: $e');
      if (e is Exception) {
        throw e;
      } else {
        throw Exception('$message 发生未知错误: $e');
      }
    }
  }
  // --- 辅助方法结束 ---
}

// 应用生命周期观察者类
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Future<void> Function() onResume;
  final Future<void> Function()? onPause;

  _AppLifecycleObserver({required this.onResume, this.onPause});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.paused:
        onPause?.call();
        break;
      default:
        break;
    }
  }
}
