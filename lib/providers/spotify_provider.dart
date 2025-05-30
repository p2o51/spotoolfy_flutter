import 'package:flutter/foundation.dart';
// import 'package:flutter/widgets.dart'; // Unnecessary
import 'dart:async';
import '../services/spotify_service.dart';
import '../models/spotify_device.dart';
import 'package:collection/collection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';
// import '../config/secrets.dart'; // No longer using clientSecret from here for SpotifyAuthService
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:http/http.dart' as http; // Unused -> NEEDED NOW! - Already present
// import 'package:spotify_sdk/spotify_sdk.dart'; // Unused
import '../providers/local_database_provider.dart';
import 'package:logger/logger.dart';
import 'package:flutter/material.dart';
import '../pages/devices.dart';
import 'dart:convert';
import 'package:flutter/widgets.dart';

final logger = Logger();

enum PlayMode {
  singleRepeat,    // 单曲循环（曲循环+顺序播放）
  sequential,      // 顺序播放（列表循环+顺序播放）
  shuffle          // 随机播放（列表循环+随机播放）
}

class SpotifyProvider extends ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late SpotifyAuthService _spotifyService;
  static const String _clientIdKey = 'spotify_client_id';
  final Logger logger = Logger();
  
  // 生命周期观察者
  late final WidgetsBinding _binding;
  late final _AppLifecycleObserver _lifecycleObserver;

  // 网络状态跟踪
  bool _hasNetworkIssue = false;
  DateTime? _lastNetworkError;
  int _consecutiveNetworkErrors = 0;

  String? username;
  Map<String, dynamic>? currentTrack;
  bool? isCurrentTrackSaved;
  Timer? _refreshTimer;
  Timer? _progressTimer;
  DateTime? _lastProgressUpdate;
  bool isLoading = false;
  Map<String, dynamic>? previousTrack;
  Map<String, dynamic>? nextTrack;
  PlayMode _currentMode = PlayMode.sequential;
  PlayMode get currentMode => _currentMode;
  bool _isSkipping = false;
  bool _isInitialized = false;

  // 添加图片预加载缓存
  final Map<String, String> _imageCache = {};
  
  SpotifyProvider() {
    _initSpotifyService();
    _initLifecycleObserver();
    // 自动尝试读取本地 token，成功就把 username 填好并启动定时器
    Future.microtask(() => autoLogin());
  }

  void _initSpotifyService() {
    // 使用默认的ClientID初始化Spotify服务
    // 如果用户配置了自己的ClientID，会在autoLogin中重新初始化
    const String clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID', defaultValue: '64103961829a42328a6634fb80574191');
    const String redirectUrl = String.fromEnvironment('SPOTIFY_REDIRECT_URL', defaultValue: 'spotoolfy://callback');

    _spotifyService = SpotifyAuthService(
      clientId: clientId,
      redirectUrl: redirectUrl,
    );

    // 设置token刷新回调
    _spotifyService.onTokenRefreshed = () {
      _refreshUserProfile();
    };
    _isInitialized = true;

    // 读取存储的ClientID并在需要时重新初始化
    _secureStorage.read(key: _clientIdKey).then((storedClientId) {
      if (storedClientId != null && storedClientId.isNotEmpty && storedClientId != clientId) {
        logger.d('从存储读取到自定义ClientID，重新初始化SpotifyService');
        _spotifyService = SpotifyAuthService(
          clientId: storedClientId,
          redirectUrl: redirectUrl,
        );
        _spotifyService.onTokenRefreshed = () {
          _refreshUserProfile();
        };
      }
    }).catchError((e) {
      logger.e('读取存储的ClientID失败: $e');
    });
  }

  void _initLifecycleObserver() {
    _binding = WidgetsBinding.instance;
    _lifecycleObserver = _AppLifecycleObserver(
      onResume: _onAppResume,
      onPause: _onAppPause,
    );
    _binding.addObserver(_lifecycleObserver);
  }

  /// 应用恢复到前台时的处理
  Future<void> _onAppResume() async {
    logger.i('应用恢复到前台，重新初始化连接状态');
    
    try {
      // 等待一下，让网络连接稳定
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 检查认证状态
      if (await _spotifyService.isAuthenticated()) {
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
      final user = await _spotifyService.getUserProfile();
      username = user['display_name'];
      notifyListeners(); // UI 马上刷新
      if (_refreshTimer == null && username != null) startTrackRefresh(); // Only start if not already running and user is logged in
    } catch (_) {
      /* 忽略失败 */
    }
  }

  Future<void> setClientCredentials(String clientId) async {
    try {
      // 保存新凭据
      await _secureStorage.write(key: _clientIdKey, value: clientId);
      
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
      _progressTimer?.cancel();
      
      // 如果之前已初始化并且已登录，先注销
      if (wasInitialized) { 
          try {
            await _spotifyService.logout(); 
          } catch(e) {
            logger.e('注销旧凭据时出错: $e');
          }
      }

      // 用新凭据重新初始化服务
      _initSpotifyService(); 
      
      // 记录新凭据应用情况
      logger.d('已应用新的ClientID: ${clientId.substring(0, 4)}...');
      
      notifyListeners();
    } catch (e) {
      logger.e('设置客户端凭据失败: $e');
      rethrow;
    }
  }

  Future<Map<String, String?>> getClientCredentials() async {
    final clientId = await _secureStorage.read(key: _clientIdKey);
    return {
      'clientId': clientId,
    };
  }

  Future<void> resetClientCredentials() async {
    await _secureStorage.delete(key: _clientIdKey);
    
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
    _progressTimer?.cancel();
    
    if (wasInitialized) {
        try {
          await _spotifyService.logout();
        } catch (e) {
          // debugPrint('注销时出错: $e');
        }
    }
    _initSpotifyService();
    notifyListeners();
  }

  // 添加设备列表状态
  List<SpotifyDevice> _availableDevices = [];
  String? _activeDeviceId;

  // Getter
  List<SpotifyDevice> get availableDevices => _availableDevices;
  String? get activeDeviceId => _activeDeviceId;
  
  SpotifyDevice? get activeDevice => _availableDevices.firstWhereOrNull(
    (device) => device.isActive,
  ) ?? _availableDevices.firstWhereOrNull(
    (device) => device.id == _activeDeviceId,
  ) ?? (_availableDevices.isEmpty ? null : _availableDevices.first);

  /// 刷新可用设备列表
  Future<void> refreshAvailableDevices() async {
    try {
      final devices = await _spotifyService.getAvailableDevices();
      _availableDevices = devices
          .map((json) => SpotifyDevice.fromJson(json))
          .toList();
      
      // 更新当前活动设备ID
      final activeDevice = _availableDevices.firstWhereOrNull(
        (device) => device.isActive,
      ) ?? (_availableDevices.isEmpty ? 
        SpotifyDevice(
          name: 'No Device',
          type: SpotifyDeviceType.unknown,
          isActive: false,
          isPrivateSession: false,
          isRestricted: true,
          supportsVolume: false,
        ) : _availableDevices.first);
      
      _activeDeviceId = activeDevice.id;
      
      notifyListeners();
    } catch (e) {
      // debugPrint('刷新可用设备列表失败: $e');
      await _handleApiError(e, contextMessage: '刷新可用设备列表');
    }
  }

  /// 转移播放到指定设备
  Future<void> transferPlaybackToDevice(String deviceId, {bool play = false}) async {
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
      
      await _spotifyService.transferPlayback(deviceId, play: play);
      
      // 等待一小段时间确保转移完成
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 刷新设备列表和播放状态
      await Future.wait([
        refreshAvailableDevices(),
        refreshCurrentTrack(),
      ]);
    } catch (e) {
      // debugPrint('转移播放失败: $e');
      await _handleApiError(e, contextMessage: '转移播放');
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
      
      await _spotifyService.setVolume(
        volumePercent.clamp(0, 100),
        deviceId: deviceId,
      );
      
      await refreshAvailableDevices();
    } catch (e) {
      // debugPrint('设置音量失败: $e');
      await _handleApiError(e, contextMessage: '设置音量');
      rethrow; // Rethrow original or modified error from _handleApiError
    }
  }

  void startTrackRefresh() {
    logger.d('startTrackRefresh: User: $username, Initialized: $_isInitialized, IsSkipping: $_isSkipping');
    if (username == null || !_isInitialized) {
      logger.w('startTrackRefresh: Aborted. Username is null or service not initialized.');
      _refreshTimer?.cancel();
      _progressTimer?.cancel();
      _refreshTimer = null;
      _progressTimer = null;
      return;
    }

    Future.microtask(() async { // 使用 microtask 异步执行初始刷新
        try {
          logger.d('startTrackRefresh (microtask): Fetching initial track and device data...');
          await refreshCurrentTrack(); // 使用恢复后的 refreshCurrentTrack
          await refreshAvailableDevices();
          await refreshPlaybackQueue(); // 初始化时也刷新播放队列
          logger.i('startTrackRefresh (microtask): Initial data fetched. Current progress: ${currentTrack?['progress_ms']}, isPlaying: ${currentTrack?['is_playing']}');
        } catch (e) {
          logger.e('startTrackRefresh (microtask): Failed to fetch initial data, timers will still start.', error: e);
        } finally {
          // 确保 _lastProgressUpdate 在 _progressTimer 启动前有合理的值
          if (currentTrack != null && currentTrack!['is_playing'] == true && _lastProgressUpdate == null) {
              _lastProgressUpdate = DateTime.now();
          }

          _refreshTimer?.cancel();
          _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
            if (!_isSkipping) {
              logger.v('_refreshTimer tick. Calling refreshCurrentTrack, refreshAvailableDevices & refreshPlaybackQueue.');
              refreshCurrentTrack(); // 使用恢复后的 refreshCurrentTrack
              refreshAvailableDevices(); // !! 加上这个 !!
              refreshPlaybackQueue(); // 定期刷新播放队列
            } else {
              logger.v('_refreshTimer tick: Skipped due to _isSkipping=true.');
            }
          });

          _progressTimer?.cancel();
          _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
            if (!_isSkipping && currentTrack != null && currentTrack!['is_playing'] == true) {
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
                    notifyListeners();
                  }
                }
              }
              _lastProgressUpdate = now;
            } else if (currentTrack != null && currentTrack!['is_playing'] == false) {
              _lastProgressUpdate = DateTime.now(); // Also update if paused, to have a fresh start when resuming
            }
          });
          logger.d('startTrackRefresh: Timers (re)started. _refreshTimer active: ${_refreshTimer?.isActive}, _progressTimer active: ${_progressTimer?.isActive}');
        }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    // 清理生命周期观察者
    _binding.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> refreshCurrentTrack() async {
    try {
      final track = await _spotifyService.getCurrentlyPlayingTrack();
      
      // 成功获取数据，检查并重置网络错误状态
      _isNetworkError(Exception('success')); // 调用以重置计数（传入非网络错误）
      
      logger.d('refreshCurrentTrack: API returned track: ${track != null ? json.encode(track) : "null"}');

      if (track != null) {
        final isPlayingFromApi = track['is_playing'] as bool?;
        final progressFromApi = track['progress_ms'] as int?;
        final newId = track['item']?['id'];
        final newContextUri = track['context']?['uri'];

        final oldId = currentTrack?['item']?['id'];
        final oldIsPlaying = currentTrack?['is_playing'] as bool?;
        final oldContextUri = currentTrack?['context']?['uri'];
        final oldProgressMs = currentTrack?['progress_ms'] as int?;

        logger.d('refreshCurrentTrack: API data -> isPlaying: $isPlayingFromApi, progress: $progressFromApi, id: $newId, context: $newContextUri');
        logger.d('refreshCurrentTrack: Provider state BEFORE update -> isPlaying: $oldIsPlaying, progress: $oldProgressMs, id: $oldId, context: $oldContextUri, _lastProgressUpdate: $_lastProgressUpdate');

        bool needsNotify = false;
        const int kProgressJumpThreshold = 1500; // 1.5 seconds

        final bool coreTrackInfoChanged = currentTrack == null ||
            newId != oldId ||
            (isPlayingFromApi != null && isPlayingFromApi != oldIsPlaying) ||
            newContextUri != oldContextUri;

        bool significantProgressJump = false;
        if (progressFromApi != null && oldProgressMs != null) {
            significantProgressJump = (progressFromApi - oldProgressMs).abs() > kProgressJumpThreshold;
        } else if (progressFromApi != null && oldProgressMs == null && currentTrack != null) { 
            significantProgressJump = true;
        } else if (progressFromApi != null && currentTrack == null) {
            significantProgressJump = true;
        }


        if (coreTrackInfoChanged || significantProgressJump) {
            currentTrack = Map<String, dynamic>.from(track); 
            currentTrack!['progress_ms'] = progressFromApi ?? oldProgressMs ?? 0;
            
            if (newId != oldId || (currentTrack!['is_playing'] == true && progressFromApi != null) || significantProgressJump) {
                _lastProgressUpdate = DateTime.now();
            }
            needsNotify = true;
            logger.i('refreshCurrentTrack: Updated currentTrack due to coreChange ($coreTrackInfoChanged) or progressJump ($significantProgressJump). New progress: ${currentTrack!['progress_ms']}, isPlaying: ${currentTrack!['is_playing']}. Reset _lastProgressUpdate: $_lastProgressUpdate');

            if (newId != oldId && newId != null) { 
              try {
                isCurrentTrackSaved = await _spotifyService.isTrackSaved(newId);
                logger.d('refreshCurrentTrack: Fetched save state for new track $newId: $isCurrentTrackSaved');
                if (track['context'] != null) {
                    final enrichedContext = await _enrichPlayContext(Map<String, dynamic>.from(track['context']));
                    currentTrack!['context'] = enrichedContext;
                    logger.d('refreshCurrentTrack: Enriched context for new track $newId.');
                    
                    // 保存播放上下文到本地数据库
                    try {
                      final context = navigatorKey.currentContext;
                      if (context != null && context.mounted) {
                        final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
                        await localDbProvider.insertOrUpdatePlayContext(
                          contextUri: enrichedContext['uri'] as String,
                          contextType: enrichedContext['type'] as String,
                          contextName: enrichedContext['name'] as String,
                          imageUrl: (enrichedContext['images'] as List?)?.isNotEmpty == true 
                              ? enrichedContext['images'][0]['url'] as String?
                              : null,
                          lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
                        );
                        logger.d('refreshCurrentTrack: Saved play context to local database: ${enrichedContext['uri']}');
                      }
                    } catch (dbError) {
                      logger.e('refreshCurrentTrack: Failed to save play context to database', error: dbError);
                      // 不重新抛出错误，以免影响其他功能
                    }
                }
              } catch (e) {
                  logger.e('refreshCurrentTrack: Failed to fetch save state or enrich context for new track $newId', error: e);
              }
            }
        } else if (currentTrack != null && progressFromApi != null && progressFromApi != oldProgressMs) {
            currentTrack!['progress_ms'] = progressFromApi;
            if (currentTrack!['is_playing'] == true) {
                 _lastProgressUpdate = DateTime.now();
            }
            needsNotify = true;
            logger.d('refreshCurrentTrack: Calibrated progress_ms from API to $progressFromApi. Reset _lastProgressUpdate: $_lastProgressUpdate');
        }


        if (needsNotify) {
            logger.d('refreshCurrentTrack: Calling notifyListeners()');
            notifyListeners();
        }

      } else if (currentTrack != null) { 
        logger.d('refreshCurrentTrack: API returned null, clearing currentTrack.');
        currentTrack = null;
        isCurrentTrackSaved = null; 
        notifyListeners();
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
      logger.w('refreshCurrentTrack caught an error. About to call _handleApiError. Error: $e');
      await _handleApiError(e, contextMessage: '刷新当前播放状态');
    }
  }

  // 辅助方法：丰富播放上下文信息
  Future<Map<String, dynamic>> _enrichPlayContext(Map<String, dynamic> context) async {
    final type = context['type'];
    final uri = context['uri'] as String;
    
    Map<String, dynamic> enrichedContext = {
      ...context,
      'name': 'UNKNOWN CONTEXT',
      'images': [{'url': 'https://via.placeholder.com/300'}],
    };
    
    try {
      if (type == 'album') {
        final albumId = uri.split(':').last;
        final fullAlbum = await _spotifyService.getAlbum(albumId);
        enrichedContext.addAll({
          'name': fullAlbum['name'],
          'images': fullAlbum['images'],
          'external_urls': fullAlbum['external_urls'],
        });
      } else if (type == 'playlist') {
        final playlistId = uri.split(':').last;
        final fullPlaylist = await _spotifyService.getPlaylist(playlistId);
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
    enrichedContext['images'] ??= [{'url': 'https://via.placeholder.com/300'}];
    enrichedContext['name'] ??= '未知${type == 'playlist' ? '播放列表' : '专辑'}';
    
    return enrichedContext;
  }

  Future<void> checkCurrentTrackSaveState() async {
    if (currentTrack == null || currentTrack!['item'] == null) {
      isCurrentTrackSaved = null;
      notifyListeners();
      return;
    }

    try {
      final trackId = currentTrack!['item']['id'];
      isCurrentTrackSaved = await _spotifyService.isTrackSaved(trackId);
      notifyListeners();
    } catch (e) {
      // debugPrint('检查歌曲保存状态失败: $e');
      await _handleApiError(e, contextMessage: '检查歌曲保存状态');
    }
  }

  /// 处理从URL回调中获取的token
  Future<void> handleCallbackToken(String accessToken, String? expiresIn) async {
    try {
      final expiresInSeconds = int.tryParse(expiresIn ?? '3600') ?? 3600;
      
      // 直接保存token到SpotifyAuthService
      await _spotifyService.saveAuthResponse(accessToken, expiresInSeconds: expiresInSeconds);
      
      // 立即获取用户资料并更新状态
      try {
        final userProfile = await _spotifyService.getUserProfile();
        username = userProfile['display_name'];
        logger.d('iOS回调：成功获取用户资料: $username');
        
        // 启动定时器
        startTrackRefresh();
        
        // 触发UI更新
        notifyListeners();
        
        print('成功保存从回调获取的access token并更新用户状态');
      } catch (profileError) {
        logger.e('iOS回调：获取用户资料失败: $profileError');
        // 即使获取用户资料失败，也要触发token刷新回调
        _spotifyService.onTokenRefreshed?.call();
      }
    } catch (e) {
      logger.e('保存回调token失败: $e');
    }
  }

  /// 自动登录
  Future<void> autoLogin() async {
    if (isLoading) return; // Avoid concurrent autoLogin calls
    isLoading = true;
    notifyListeners();

    try {
      if (!_isInitialized) {
        _initSpotifyService(); 
      }
      // It's possible _initSpotifyService failed if not handled well, 
      // but let's assume it sets _isInitialized correctly or throws.
      if (!_isInitialized) { 
        // This case should ideally not be reached if _initSpotifyService is robust
        return; 
      }

      final token = await _spotifyService.ensureFreshToken();
      if (token != null) {
        await _refreshUserProfile(); 
        await updateWidget();
      } else {
        // No token, ensure user is in a logged-out state if they weren't already
        if (username != null) {
            username = null;
            // No need to call notifyListeners here, finally block will do it.
        }
      }
    } catch (e) {
      // debugPrint('AutoLogin error: $e');
      if (username != null) {
        username = null; 
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 登录
  Future<void> login() async {
    isLoading = true;
    notifyListeners();

    try {
      if (!_isInitialized) {
        _initSpotifyService();
        if (!_isInitialized) {
          throw SpotifyAuthException('SpotifyService 初始化失败');
        }
      }

      final accessToken = await _spotifyService.login(); // This now calls ensureFreshToken or SDK getAccessToken
                                                  // and onTokenRefreshed internally

      if (accessToken == null) {
         // Login was cancelled or failed silently in ensureFreshToken/login in service
         // UI should reflect this (e.g. isLoading false, no username)
      } else {
        // Token obtained, _refreshUserProfile should have been called by onTokenRefreshed
        // If not, or for robustness:
        if (username == null) await _refreshUserProfile(); 
        await updateWidget();
      }

    } catch (e) {
      // Handle SpotifyAuthException (e.g. AUTH_CANCELLED, CONFIG_ERROR)
      // or other exceptions
      if (e is SpotifyAuthException && e.code == 'AUTH_CANCELLED') {
        // User cancelled, do nothing further, isLoading will be set to false in finally
      } else {
        // For other errors, rethrow or handle appropriately
        // Potentially clear username if login failed critically
        username = null;
        rethrow;
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _showDevicesPage() async {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // 确保设备列表是新的
      await refreshAvailableDevices();
      showModalBottomSheet(
        context: context,
        isScrollControlled: true, // Allow modal to take up more space
        builder: (context) => const DevicesPage(),
        shape: const RoundedRectangleBorder( // Optional: Add rounded corners
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      );
    } else {
      // debugPrint('Error: Navigator context is null, cannot show devices page.');
    }
  }

  // Helper function to check for active device and show picker if needed
  Future<bool> _ensureAuthenticatedAndReady() async {
    logger.d('_ensureAuthenticatedAndReady: Start. Username: $username');
    print('===== SPOTIFY PROVIDER DEBUG =====');
    print('_ensureAuthenticatedAndReady: 开始. 用户名: $username');
    
    // 开关：是否忽略 Remote 连接失败，继续 Web API
    // 在您的实际应用中，您可能希望这个值来自配置或用户的偏好设置
    const bool ignoreRemoteConnectionFailure = true; 

    try {
      if (username == null) {
        logger.d('_ensureAuthenticatedAndReady: Username is null, attempting autoLogin...');
        print('用户名为空，尝试自动登录...');
        await autoLogin(); 
        if (username == null) { 
          logger.d('_ensureAuthenticatedAndReady: autoLogin failed or did not set username. Checking isAuthenticated...');
          print('自动登录失败或未设置用户名，检查是否已认证...');
          if (!await _spotifyService.isAuthenticated()) {
            logger.w('_ensureAuthenticatedAndReady: Not authenticated after autoLogin failure. Throwing SESSION_EXPIRED.');
            print('自动登录后未认证，抛出 SESSION_EXPIRED');
            print('===== SPOTIFY PROVIDER DEBUG END =====');
            throw SpotifyAuthException('需要登录', code: 'SESSION_EXPIRED');
          }
          print('已认证但用户名为空，尝试获取用户资料...');
          final userProfile = await _spotifyService.getUserProfile();
          username = userProfile['display_name'];
          startTrackRefresh(); 
          notifyListeners();
        }
        logger.d('_ensureAuthenticatedAndReady: autoLogin processed. Username: $username');
        print('自动登录处理完成。用户名: $username');
      }

      print('检查是否需要连接 Remote...');
      if (!await _spotifyService.connectRemoteIfNeeded()) {
        logger.w('_ensureAuthenticatedAndReady: Failed to connect Remote');
        print('连接 Remote 失败');
        if (!ignoreRemoteConnectionFailure) {
          print('===== SPOTIFY PROVIDER DEBUG END =====');
          throw SpotifyAuthException('无法连接到 Spotify Remote', code: 'REMOTE_CONNECTION_FAILED');
        } else {
          logger.i('_ensureAuthenticatedAndReady: Remote 连接失败，但已配置为忽略并继续 Web API 操作。');
          print('Remote 连接失败，但已配置为忽略并继续 Web API 操作。');
        }
      } else {
        logger.d('_ensureAuthenticatedAndReady: connectRemoteIfNeeded succeeded or was skipped.');
        print('Remote 连接成功或已跳过。');
      }

      print('第一次获取播放状态...');
      var playbackState = await _spotifyService.getPlaybackState();
      var device = playbackState['device'];
      logger.d('_ensureAuthenticatedAndReady: Initial playback state device: $device');
      print('初次获取播放状态设备: $device');

      // 如果初次获取没有设备信息，尝试刷新设备列表再获取一次
      if (device == null) {
        logger.w('_ensureAuthenticatedAndReady: No device in initial playback state. Refreshing devices and trying again...');
        print('初次播放状态无设备，刷新设备列表后重试...');
        await refreshAvailableDevices();
        playbackState = await _spotifyService.getPlaybackState();
        device = playbackState['device'];
        logger.d('_ensureAuthenticatedAndReady: Playback state after refresh device: $device');
        print('刷新后播放状态设备: $device');
      }
      
      final hasDevice = device != null;
      final deviceName = hasDevice ? device['name'] : '无';
      final deviceId = hasDevice ? device['id'] : '无';
      final isActive = hasDevice ? device['is_active'] : false;
      final isRestricted = hasDevice ? device['is_restricted'] : false;
      
      print('播放状态设备信息: 有设备=$hasDevice, 名称=$deviceName, ID=$deviceId, 活跃=$isActive, 受限=$isRestricted');
      
      if (device == null) {
        // 如果仍然没有设备，根据您的建议，可以考虑显示设备选择器或允许_withDevice处理
        // 当前我们保持原来的逻辑：允许后续指令尝试执行
        logger.w('_ensureAuthenticatedAndReady: No active device info even after refresh, but continuing to allow command attempt.');
        print('刷新后仍无活跃设备信息，但继续尝试发送指令');
        // 即使没有设备，也返回 true，让 _withDevice 尝试处理
        print('===== SPOTIFY PROVIDER DEBUG END =====');
        return true; 
      }
      
      // 如果设备受限，则不应继续
      if (isRestricted) {
        logger.w('_ensureAuthenticatedAndReady: Device is restricted. Cannot proceed with command.');
        print('设备 ($deviceName) 受限，无法继续操作。');
        // 可以在这里抛出异常或向用户显示消息
         final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('设备 \'$deviceName\' 受限，无法通过API控制。')),
          );
        }
        print('===== SPOTIFY PROVIDER DEBUG END =====');
        return false; // 阻止后续操作
      }
      
      logger.d('_ensureAuthenticatedAndReady: Authenticated and ready. Returning true.');
      print('已认证并就绪，返回 true');
      print('===== SPOTIFY PROVIDER DEBUG END =====');
      return true;
    } on SpotifyAuthException catch (e) {
      print('捕获 SpotifyAuthException: ${e.message} (${e.code})');
      print('===== SPOTIFY PROVIDER DEBUG END =====');
      rethrow;
    } catch (e) {
      logger.e('_ensureAuthenticatedAndReady: Error occurred', error: e);
      print('发生错误: $e');
      print('===== SPOTIFY PROVIDER DEBUG END =====');
      // 即便发生其他错误，也先尝试让 _handleApiError 处理，如果它重新抛出，则这里会捕获并返回 false
      // 如果 _handleApiError 成功处理（例如401后静默续签），则不会到这里
      await _handleApiError(e, contextMessage: '_ensureAuthenticatedAndReady');
      return false; // 如果 _handleApiError 没有重抛出会话过期等，则返回false阻止操作
    }
  }

  Future<void> togglePlayPause() async {
    logger.d('togglePlayPause: 开始执行');
    print('===== TOGGLE PLAY/PAUSE DEBUG =====');
    print('togglePlayPause: 开始执行');
    
    Map<String, dynamic>? initialPlaybackStateForRevert;
    try {
      print('检查认证和设备就绪情况...');
      if (!await _ensureAuthenticatedAndReady()) {
        logger.w('togglePlayPause: _ensureAuthenticatedAndReady 返回 false，中止操作');
        print('_ensureAuthenticatedAndReady 返回 false，中止操作');
        print('===== TOGGLE PLAY/PAUSE DEBUG END =====');
        return;
      }
      print('认证和设备检查通过');

      print('获取当前播放状态...');
      final playbackState = await _spotifyService.getPlaybackState();
      initialPlaybackStateForRevert = playbackState;
      final bool isCurrentlyPlaying = playbackState['is_playing'] ?? false;
      
      logger.d('togglePlayPause: 当前播放状态 - isPlaying: $isCurrentlyPlaying');
      print('当前播放状态 - isPlaying: $isCurrentlyPlaying');

      // 使用新的 togglePlayPause 方法替代直接调用 apiPut
      logger.d('togglePlayPause: 调用 _spotifyService.togglePlayPause()');
      print('调用 _spotifyService.togglePlayPause()...');
      await _spotifyService.togglePlayPause();
      logger.d('togglePlayPause: _spotifyService.togglePlayPause() 调用成功');
      print('_spotifyService.togglePlayPause() 调用成功');
      
      // 更新本地状态
      if (currentTrack != null) {
        currentTrack!['is_playing'] = !isCurrentlyPlaying; // 切换播放状态
        logger.d('togglePlayPause: 更新本地状态 - is_playing: ${currentTrack!['is_playing']}');
        print('更新本地状态 - is_playing: ${currentTrack!['is_playing']}');
      }
      
      notifyListeners();

      print('延时600毫秒后刷新曲目信息...');
      await Future.delayed(const Duration(milliseconds: 600));
      logger.d('togglePlayPause: 刷新当前曲目信息');
      print('刷新当前曲目信息...');
      await refreshCurrentTrack();
      print('更新组件...');
      await updateWidget();
      logger.d('togglePlayPause: 成功完成');
      print('成功完成');
      print('===== TOGGLE PLAY/PAUSE DEBUG END =====');

    } on SpotifyAuthException catch (e) {
      logger.e('togglePlayPause: 捕获 SpotifyAuthException: ${e.message} (${e.code})');
      print('捕获 SpotifyAuthException: ${e.message} (${e.code})');
      
      if (e.code == 'SESSION_EXPIRED' || e.code == 'PROFILE_FETCH_ERROR_AFTER_REFRESH') {
        logger.d('togglePlayPause: Session expired, attempting login...');
        print('会话过期，尝试登录...');
        try {
          await login();
          logger.d('togglePlayPause: Login successful, retrying original play/pause command...');
          print('登录成功，重试原始播放/暂停命令...');
          print('===== TOGGLE PLAY/PAUSE DEBUG END =====');
          // 登录成功后重试原始指令
          await togglePlayPause();
        } catch (loginError) {
          if (loginError is SpotifyAuthException && loginError.code == 'AUTH_CANCELLED') {
            logger.d('togglePlayPause: User cancelled login');
            print('用户取消登录');
          } else {
            logger.e('togglePlayPause: Login failed', error: loginError);
            print('登录失败: $loginError');
            // 恢复原始状态
            if (currentTrack != null && initialPlaybackStateForRevert != null) {
              currentTrack!['is_playing'] = initialPlaybackStateForRevert['is_playing'] ?? false;
              print('恢复原始播放状态: ${currentTrack!['is_playing']}');
              notifyListeners();
            }
          }
          print('===== TOGGLE PLAY/PAUSE DEBUG END =====');
        }
      } else {
        logger.e('togglePlayPause: Auth error occurred', error: e);
        print('认证错误: ${e.message} (${e.code})');
        if (currentTrack != null && initialPlaybackStateForRevert != null) {
          currentTrack!['is_playing'] = initialPlaybackStateForRevert['is_playing'] ?? false;
          print('恢复原始播放状态: ${currentTrack!['is_playing']}');
          notifyListeners();
        }
        await _handleApiError(e, contextMessage: '播放/暂停切换 (auth error)');
        print('===== TOGGLE PLAY/PAUSE DEBUG END =====');
      }
    } catch (e) {
      logger.e('togglePlayPause: Unknown error occurred', error: e);
      print('发生未知错误: $e');
      if (currentTrack != null && initialPlaybackStateForRevert != null) {
        currentTrack!['is_playing'] = initialPlaybackStateForRevert['is_playing'] ?? false;
        print('恢复原始播放状态: ${currentTrack!['is_playing']}');
        notifyListeners();
      }
      await _handleApiError(e, contextMessage: '播放/暂停切换 (unknown error)');
      print('===== TOGGLE PLAY/PAUSE DEBUG END =====');
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
      await _spotifyService.seekToPosition(Duration(milliseconds: positionMs));
      logger.d('seekToPosition: _spotifyService.seekToPosition() 调用成功');
    } catch (e) {
      logger.e('seekToPosition: 捕获错误', error: e);
      await _handleApiError(e, contextMessage: '跳转到指定位置');
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
      await _spotifyService.skipToNext();
      logger.d('skipToNext: _spotifyService.skipToNext() 调用成功');
    } catch (e) {
      logger.e('skipToNext: 捕获错误', error: e);
      await _handleApiError(e, contextMessage: '播放下一首');
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
      await _spotifyService.skipToPrevious();
      logger.d('skipToPrevious: _spotifyService.skipToPrevious() 调用成功');
    } catch (e) {
      logger.e('skipToPrevious: 捕获错误', error: e);
      await _handleApiError(e, contextMessage: '播放上一首');
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
      notifyListeners();
      
      // Call the API to toggle the save state
      await _spotifyService.toggleTrackSave(trackId);
      
      // Immediately fetch the actual state from Spotify to confirm
      final actualState = await _spotifyService.isTrackSaved(trackId);
      
      // If the actual state differs from the optimistic update, correct it
      if (isCurrentTrackSaved != actualState) {
        isCurrentTrackSaved = actualState;
        notifyListeners();
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
        notifyListeners();
      }
      // Optionally re-check the state after error
      // try {
      //   isCurrentTrackSaved = await _spotifyService.isTrackSaved(trackId);
      //   notifyListeners();
      // } catch (recheckError) {
      //   print('重新检查收藏状态失败: $recheckError');
      // }
      await _handleApiError(e, contextMessage: '切换收藏状态');
    }
  }

  List<Map<String, dynamic>> upcomingTracks = [];

  Future<void> refreshPlaybackQueue() async {
    try {
      final queue = await _spotifyService.getPlaybackQueue();
      final rawQueue = List<Map<String, dynamic>>.from(queue['queue'] ?? []);
      
      // 移除队列长度限制
      upcomingTracks = rawQueue.toList();
      
      // 更安全地获取下一首歌曲
      nextTrack = upcomingTracks.isNotEmpty 
          ? upcomingTracks.first 
          : null;
      
      // 批量缓存所有队列图片
      await _cacheQueueImages();
      
      notifyListeners();
    } catch (e) {
      // debugPrint('刷新播放队列失败: $e');
      await _handleApiError(e, contextMessage: '刷新播放队列');
      upcomingTracks = [];
      nextTrack = null;
      notifyListeners();
    }
  }

  // 批量缓存队列图片
  Future<void> _cacheQueueImages() async {
    try {
      final imagesToCache = upcomingTracks
        .map((track) => track['album']?['images']?[0]?['url'])
        .where((url) => url != null)
        .toList();

      for (var imageUrl in imagesToCache) {
        await _preloadImage(imageUrl);
      }
    } catch (e) {
      // debugPrint('批量缓存队列图片失败: $e');
    }
  }

  // 获取当前播放模式
  Future<void> syncPlaybackMode() async {
    try {
      final state = await _spotifyService.getPlaybackState();
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
      notifyListeners();
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
      _currentMode = mode;
      await refreshPlaybackQueue();
      notifyListeners();
    } catch (e) {
      // debugPrint('设置播放模式失败: $e');
      await _handleApiError(e, contextMessage: '设置播放模式');
    }
  }

  // 循环切换播放模式
  Future<void> togglePlayMode() async {
    final nextMode = PlayMode.values[(currentMode.index + 1) % PlayMode.values.length];
    await setPlayMode(nextMode);
  }

  // 预加载图片的方法
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

  // 存储最近播放的播放列表和专辑
  final List<Map<String, dynamic>> _recentPlaylists = [];
  final List<Map<String, dynamic>> _recentAlbums = [];
  
  List<Map<String, dynamic>> get recentPlaylists => _recentPlaylists;
  List<Map<String, dynamic>> get recentAlbums => _recentAlbums;

  // 刷新最近播放记录
  Future<void> refreshRecentlyPlayed() async {
    try {
      final data = await _spotifyService.getRecentlyPlayed(limit: 50);
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
          localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
        }
      } catch (e) {
        logger.w('refreshRecentlyPlayed: Failed to get LocalDatabaseProvider: $e');
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
                contextName: context['name'] ?? '未知${type == 'playlist' ? '播放列表' : '专辑'}',
                imageUrl: null, // 在这里我们暂时不获取图片，因为会增加 API 调用
                lastPlayedAt: playedAt.millisecondsSinceEpoch,
              );
            } catch (dbError) {
              logger.e('refreshRecentlyPlayed: Failed to save context to database: $dbError');
            }
          }
          
          // 处理播放列表
          if (type == 'playlist' && !playlistUris.contains(uri)) {
            playlistUris.add(uri);
            final playlistId = uri.split(':').last;
            try {
              final playlist = await _spotifyService.getPlaylist(playlistId);
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
              final album = await _spotifyService.getAlbum(albumId);
              uniqueAlbums.add(album);
              if (uniqueAlbums.length >= 10) break;
            } catch (e) {
              // debugPrint('获取专辑 $albumId 详情失败: $e');
            }
          }
        }
      }
      
      _recentPlaylists..clear()..addAll(uniquePlaylists);
      _recentAlbums..clear()..addAll(uniqueAlbums);
      
      notifyListeners();
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
      notifyListeners();
    }

    try {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _progressTimer?.cancel(); 
      _progressTimer = null;

      username = null; 
      currentTrack = null;
      previousTrack = null;
      nextTrack = null;
      isCurrentTrackSaved = null;
      _availableDevices.clear();
      _activeDeviceId = null;
      upcomingTracks.clear();
      _imageCache.clear();
      _recentAlbums.clear();
      _recentPlaylists.clear();

      // Clear the stored client ID as well, so next login/init uses default or prompts
      await _secureStorage.delete(key: _clientIdKey);

      if (!_isInitialized) _initSpotifyService();
      if (_isInitialized) {
         await _spotifyService.logout(); 
      }

      await updateWidget(); 

    } catch (e) {
      rethrow; 
    } finally {
      if (!wasLoading) {
          isLoading = false;
      }
      notifyListeners(); 
    }
  }

  Future<void> updateWidget() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.gojyuplusone.spotoolfy/widget');
      try {
        await platform.invokeMethod('updateWidget', {
          'songName': currentTrack?['item']?['name'] ?? '未在播放',
          'artistName': currentTrack?['item']?['artists']?[0]?['name'] ?? '',
          'albumArtUrl': currentTrack?['item']?['album']?['images']?[0]?['url'] ?? '',
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
      
      await _spotifyService.playContext(
        contextUri: contextUri,
        offsetIndex: offsetIndex,
        deviceId: targetDeviceId, // Use the determined device ID
      );

      // Wait slightly to allow Spotify state to update
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Refresh state after initiating play
      await refreshCurrentTrack();
      await refreshPlaybackQueue();
      
    } catch (e) {
      // debugPrint('播放 $type 失败: $e');
      await _handleApiError(e, contextMessage: '播放 $type');
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
        await _spotifyService.playTrackInContext(
          contextUri: contextUri,
          trackUri: trackUri,
          deviceId: targetDeviceId,
        );
      } else {
        // Otherwise, play the track individually
        await _spotifyService.playTrack(
          trackUri: trackUri,
          deviceId: targetDeviceId,
        );
      }
      
      // Wait slightly to allow Spotify state to update
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Refresh state after initiating play
      await refreshCurrentTrack();
      await refreshPlaybackQueue();

    } catch (e) {
      // debugPrint('播放歌曲失败: $e');
      await _handleApiError(e, contextMessage: '播放歌曲');
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
  }) async {
     // Check for active device BEFORE attempting to play
    if (!await _ensureAuthenticatedAndReady()) {
      return; // Stop if no active device and picker is shown
    }

    try {
      // Get the current active device ID if not explicitly provided
      final targetDeviceId = deviceId ?? activeDeviceId;

      // Call the service method which includes its own device checks
      await _spotifyService.playTrackInContext(
        contextUri: contextUri,
        trackUri: trackUri,
        deviceId: targetDeviceId,
      );
      
      // Wait slightly to allow Spotify state to update
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Refresh state after initiating play
      await refreshCurrentTrack();
      await refreshPlaybackQueue();

    } catch (e) {
      // debugPrint('在上下文中播放歌曲时出错: $e');
      await _handleApiError(e, contextMessage: '在上下文中播放歌曲');
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
    if (!_isInitialized) _initSpotifyService();
    if (!_isInitialized) throw Exception('Spotify Service not initialized.');
    return await _spotifyService.getAuthenticatedHeaders();
  }
  
  /// 获取用户的播放列表
  Future<List<Map<String, dynamic>>> getUserPlaylists({int limit = 50, int offset = 0}) async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        // debugPrint('未登录，无法获取播放列表');
        return [];
      }

      final response = await _spotifyService.apiGet('/me/playlists?limit=$limit&offset=$offset');
      if (response['items'] == null) return [];

      final List<Map<String, dynamic>> playlists = List<Map<String, dynamic>>.from(response['items'].map((item) => {
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
          final nextPlaylists = await getUserPlaylists(limit: limit, offset: nextOffset);
          additionalPlaylists.addAll(nextPlaylists);
        }
        
        playlists.addAll(additionalPlaylists);
      }
      
      return playlists;
    } catch (e) {
      // debugPrint('获取用户播放列表失败: $e');
      await _handleApiError(e, contextMessage: '获取用户播放列表');
      return [];
    }
  }

  /// 获取用户收藏的专辑
  Future<List<Map<String, dynamic>>> getUserSavedAlbums({int limit = 50, int offset = 0}) async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        // debugPrint('未登录，无法获取收藏专辑');
        return [];
      }

      final response = await _spotifyService.apiGet('/me/albums?limit=$limit&offset=$offset');
      if (response['items'] == null) return [];

      final List<Map<String, dynamic>> albums = List<Map<String, dynamic>>.from(response['items'].map((item) => {
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
          final nextAlbums = await getUserSavedAlbums(limit: limit, offset: nextOffset);
          additionalAlbums.addAll(nextAlbums);
        }
        
        albums.addAll(additionalAlbums);
      }
      
      return albums;
    } catch (e) {
      // debugPrint('获取收藏专辑失败: $e');
      return [];
    }
  }

  /// 获取最近播放的记录
  Future<List<Map<String, dynamic>>> getRecentlyPlayed() async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        // debugPrint('未登录，无法获取最近播放');
        return [];
      }

      final response = await _spotifyService.apiGet('/me/player/recently-played?limit=50');
      if (response['items'] == null) return [];

      // 提取唯一的上下文（专辑和播放列表）
      final Map<String, Map<String, dynamic>> uniqueContexts = {};

      for (final item in response['items']) {
        if (item['context'] != null) {
          final contextUri = item['context']['uri'];
          if (!uniqueContexts.containsKey(contextUri)) {
            final contextType = contextUri.split(':')[1]; // playlist, album, etc.
            final contextId = contextUri.split(':').last;
            
            // 为上下文获取更详细信息
            Map<String, dynamic> details = {};
            try {
              details = await _spotifyService.apiGet('/$contextType' 's/$contextId');
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
  Future<List<Map<String, dynamic>>> getRecentlyPlayedRawTracks({int limit = 50}) async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        // debugPrint('未登录，无法获取原始最近播放记录');
        return [];
      }
      return await _spotifyService.getRecentlyPlayedRawTracks(limit: limit);
    } catch (e) {
      // debugPrint('获取原始最近播放记录失败: $e');
      return [];
    }
  }

  /// Search for items (tracks, albums, artists, playlists)
  Future<Map<String, List<Map<String, dynamic>>>> searchItems(String query, {List<String> types = const ['track', 'album', 'artist', 'playlist'], int limit = 20}) async {
    if (!_isInitialized) {
      _initSpotifyService();
    }
    if (!_isInitialized) {
      throw Exception('Spotify service could not be initialized.');
    }
    
    try {
      if (query.trim().isEmpty) return {};

      // Call the search method in SpotifyAuthService
      // Pass types as the second argument, and limit as a named argument
      final response = await _spotifyService.search(query, types, limit: limit);

      // --- Add logging for decoded response ---
      // debugPrint('SpotifyProvider.searchItems - Decoded Response:');
      // debugPrint(json.encode(response));
      // --- End logging ---

      final Map<String, List<Map<String, dynamic>>> results = {};

      // Process tracks
      if (response['tracks']?['items'] != null && types.contains('track')) {
        // debugPrint('Processing tracks...');
        results['tracks'] = List<Map<String, dynamic>>.from(
          (response['tracks']['items'] as List).where((item) => item != null && item['id'] != null && item['name'] != null && item['album']?['images'] != null).map((item) => {
            'id': item['id'],
            'type': 'track',
            'name': item['name'],
            'uri': item['uri'],
            'album': item['album'],
            'artists': item['artists'],
            'duration_ms': item['duration_ms'],
            'images': (item['album']?['images'] is List && (item['album']['images'] as List).isNotEmpty)
                        ? item['album']['images']
                        : null,
          }).where((item) => item['images'] != null)
        );
      }

      // Process albums
      if (response['albums']?['items'] != null && types.contains('album')) {
        // debugPrint('Processing albums...');
        results['albums'] = List<Map<String, dynamic>>.from(
          (response['albums']['items'] as List).where((item) => item != null && item['id'] != null && item['name'] != null && item['images'] != null).map((item) => {
            'id': item['id'],
            'type': 'album',
            'name': item['name'],
            'uri': item['uri'],
            'artists': item['artists'],
            'images': item['images'],
          }).where((item) => item['images'] != null && (item['images'] as List).isNotEmpty)
        );
      }

      // Process artists
      if (response['artists']?['items'] != null && types.contains('artist')) {
        // debugPrint('Processing artists...');
        results['artists'] = List<Map<String, dynamic>>.from(
          (response['artists']['items'] as List).where((item) => item != null && item['id'] != null && item['name'] != null && item['images'] != null).map((item) => {
            'id': item['id'],
            'type': 'artist',
            'name': item['name'],
            'uri': item['uri'],
            'images': item['images'],
          }).where((item) => item['images'] != null && (item['images'] as List).isNotEmpty)
        );
      }

      // Process playlists
      if (response['playlists']?['items'] != null && types.contains('playlist')) {
        // debugPrint('Processing playlists...');
        results['playlists'] = List<Map<String, dynamic>>.from(
          (response['playlists']['items'] as List).where((item) => item != null && item['id'] != null && item['name'] != null && item['images'] != null).map((item) => {
            'id': item['id'],
            'type': 'playlist',
            'name': item['name'],
            'uri': item['uri'],
            'owner': item['owner'],
            'images': item['images'],
          }).where((item) => item['images'] != null && (item['images'] as List).isNotEmpty)
        );
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
                           error.code == 'OPERATION_FAILED_UNKNOWN'; // 如果未知错误也认为是网络问题
    }

    // 检查通用的网络错误关键字
    isNetworkErrorType = isNetworkErrorType ||
           errorString.contains('socketexception') || 
           errorString.contains('timeoutexception') ||
           errorString.contains('clientexception') || // 包括 ClientException with SocketException
           errorString.contains('connection') ||
           errorString.contains('software caused connection abort') ||
           errorString.contains('host unreachable') ||
           errorString.contains('network is unreachable') ||
           errorString.contains('network_error') || // 通用网络错误标记
           errorString.contains('failed host lookup') || // DNS解析失败
           errorString.contains('os error: connection refused'); // 连接被拒绝
    
    if (isNetworkErrorType) {
      _consecutiveNetworkErrors++;
      _lastNetworkError = DateTime.now();
      _hasNetworkIssue = true;
      
      logger.w('检测到网络错误 (连续第 $_consecutiveNetworkErrors 次): $errorString');
      
      // 如果连续网络错误超过3次，暂停定时刷新一段时间
      if (_consecutiveNetworkErrors >= 3 && _refreshTimer != null) { // 仅当定时器存在时才操作
        logger.w('连续网络错误过多，暂停定时刷新30秒');
        _pauseRefreshTimerTemporarily();
      }
    } else {
      // 成功的请求或非网络错误，重置网络错误计数
      if (_consecutiveNetworkErrors > 0) {
        logger.i('网络连接已恢复或错误非网络相关，重置错误计数');
        _consecutiveNetworkErrors = 0;
        _hasNetworkIssue = false;
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
  
  Future<void> _handleApiError(dynamic e, {String? contextMessage}) async {
    final message = contextMessage ?? 'API 调用';
    logger.e('$message 出错: $e', error: e, stackTrace: e is Error ? e.stackTrace : null);

    // 检查是否为网络连接错误
    if (_isNetworkError(e)) {
      logger.w('$message 遇到网络连接错误: $e');
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('网络连接不稳定，请检查网络设置或稍后重试'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
      // 对于网络错误，我们可以选择不重新抛出，让应用继续运行
      // 但如果调用方需要知道错误发生，可以重新抛出
      // 这里我们选择不重新抛出，避免应用崩溃
      return;
    }

    if (e is SpotifyAuthException && e.code == '401') {
      logger.i('$message 遇到 401，尝试静默续约/重连...');
      final token = await _spotifyService.getAccessToken();
      if (token != null) { // Silent refresh was successful
        try {
          // Re-fetch user profile and re-initialize session state
          final userProfile = await _spotifyService.getUserProfile();
          username = userProfile['display_name'];
          
          // Notify listeners that username might have changed (e.g. if it was null before)
          // and other session-related states are fresh.
          // It's good practice to notify before starting timers if any UI might depend on the username
          // for immediate re-render, although startTrackRefresh also calls notifyListeners.
          notifyListeners();

          startTrackRefresh(); // Now this will work as username is set

          // The original operation that failed with 401 can now be retried by its caller.
          // _handleApiError should just return to allow this.
        } catch (profileError) {
          // Failed to get profile even after token refresh. This is a critical issue.
          // Treat as a full logout scenario.
          // print('$message: Token refreshed, but failed to get user profile: $profileError');
          await logout(); // Clears username, stops timers, notifies listeners.
          // Throw a specific exception indicating this state.
          throw SpotifyAuthException('会话已恢复但无法获取用户信息，请重新登录。', code: 'PROFILE_FETCH_ERROR_AFTER_REFRESH');
        }
        return; // Allow original operation to be retried by the caller of _handleApiError
      }
      // print('$message: getAccessToken() 返回 null，Token 确认无效，执行登出。'); // Log logout decision
      // Silent refresh failed (getAccessToken returned null), session is truly expired.
      await logout(); // Clears username, stops timers, notifies listeners.
      // Throw a specific exception that UI can catch to trigger interactive login.
      throw SpotifyAuthException('会话已过期，请重新登录', code: 'SESSION_EXPIRED');
    } else if (e is SpotifyAuthException && (e.code == '403' || e.code == '415')) {
      logger.w('$message 遇到 ${e.code}: ${e.message}');
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        String displayMessage;
        bool isHandledKnown403 = false; // Flag to indicate if we should stop re-throwing

        if (e.code == '403') {
          final lowerCaseMessage = e.message.toLowerCase();
          if (lowerCaseMessage.contains('premium')) {
            displayMessage = '此操作需要 Spotify Premium 会员。';
            isHandledKnown403 = true;
          } else if (lowerCaseMessage.contains('restricted') || 
                     lowerCaseMessage.contains('restriction violated')) { // More specific check
            displayMessage = '当前设备不支持此操作或受限。请尝试在其他设备上播放音乐，或检查您的账户类型。';
            isHandledKnown403 = true;
          } else {
            displayMessage = '权限不足 (403): ${e.message}';
            // For generic 403, we might still want to re-throw or handle differently
            // For now, let's consider it not fully handled for stopping re-throw unless specified
          }
        } else { // 415 or other codes that might fall into this block
          displayMessage = '请求格式错误 (${e.code})，请稍后重试或联系开发者。';
          // Potentially set isHandledKnown403 = true if 415 is also considered fully handled by SnackBar
          // For now, let's assume only specific 403s are non-re-throwable by this flag
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayMessage)),
        );
      }
      // 对于403和415，我们通常不希望应用层面再做其他特定的恢复逻辑，
      // 而是通知用户。如果需要，可以决定是否重新抛出。
      // 为了保持与之前行为的一致性（即不静默吞掉所有非401错误），我们仍然重新抛出。
      // --- MODIFICATION START ---
      // Only re-throw if it's not one of the specifically handled 403 errors where a user message was shown.
      if (e is SpotifyAuthException && e.code == '403') {
        // Use the already determined isHandledKnown403 flag or re-check condition
        final lowerCaseMessage = e.message.toLowerCase();
        if (lowerCaseMessage.contains('premium') || 
            lowerCaseMessage.contains('restricted') || 
            lowerCaseMessage.contains('restriction violated')) {
          logger.i('已处理的403错误 (${e.message})，不再重新抛出。');
          return; // Do not re-throw for these specific handled 403s
        }
      }
      // --- MODIFICATION END ---
      throw e;
    } else {
      logger.e('$message 遇到其他错误，将重新抛出: $e');
      // For other non-401 errors, re-throw the original exception.
      if (e is Exception) {
      throw e;
      } else {
        // Wrap non-Exception errors if necessary, though typically 'e' will be an Exception.
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