import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import '../services/spotify_service.dart';
import '../models/spotify_device.dart';
import 'package:collection/collection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../config/secrets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';
import '../providers/local_database_provider.dart';
import 'package:logger/logger.dart';

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
  static const String _clientSecretKey = 'spotify_client_secret';

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
  bool _isReconnecting = false;  // 添加重连状态标志

  // 添加图片预加载缓存
  final Map<String, String> _imageCache = {};
  
  SpotifyProvider() {
    _initSpotifyService();
    _setupConnectionListener();
  }

  Future<void> _initSpotifyService() async {
    if (_isInitialized) return;
    
    try {
      final clientId = await _secureStorage.read(key: _clientIdKey) ?? SpotifySecrets.clientId;
      final clientSecret = await _secureStorage.read(key: _clientSecretKey) ?? SpotifySecrets.clientSecret;
      
      _spotifyService = SpotifyAuthService(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUrl: kIsWeb 
            ? 'http://localhost:8080/spotify_callback.html'
            : 'spotoolfy://callback',
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('初始化 SpotifyService 失败: $e');
      _isInitialized = false;
    }
  }

  Future<void> setClientCredentials(String clientId, String clientSecret) async {
    try {
      // 保存新凭据
      await _secureStorage.write(key: _clientIdKey, value: clientId);
      await _secureStorage.write(key: _clientSecretKey, value: clientSecret);
      
      // 清除现有状态
      username = null;
      currentTrack = null;
      previousTrack = null;
      nextTrack = null;
      _isInitialized = false;
      
      // 停止所有计时器
      _refreshTimer?.cancel();
      _progressTimer?.cancel();
      
      // 如果之前已登录，先注销
      if (_isInitialized) {
        try {
          await _spotifyService.logout();
        } catch (e) {
          debugPrint('注销旧凭据时出错: $e');
        }
      }
      
      // 用新凭据重新初始化服务
      await _initSpotifyService();
      
      // 不立即验证凭据，让用户在登录时再验证
      notifyListeners();
    } catch (e) {
      debugPrint('设置客户端凭据失败: $e');
      // 不自动恢复默认凭据，让用户自己决定是否重置
      rethrow;
    }
  }

  Future<Map<String, String?>> getClientCredentials() async {
    final clientId = await _secureStorage.read(key: _clientIdKey);
    final clientSecret = await _secureStorage.read(key: _clientSecretKey);
    return {
      'clientId': clientId,
      'clientSecret': clientSecret,
    };
  }

  Future<void> resetClientCredentials() async {
    // 清除存储中的自定义凭据
    await _secureStorage.delete(key: _clientIdKey);
    await _secureStorage.delete(key: _clientSecretKey);
    
    // 清除现有状态
    username = null;
    currentTrack = null;
    previousTrack = null;
    nextTrack = null;
    _isInitialized = false;
    
    // 停止所有计时器
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    
    // 如果之前已登录，先注销
    try {
      await _spotifyService.logout();
    } catch (e) {
      debugPrint('注销时出错: $e');
    }
    
    // 用默认凭据重新初始化服务
    await _initSpotifyService();
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
      debugPrint('刷新可用设备列表失败: $e');
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
      debugPrint('转移播放失败: $e');
      rethrow;
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
      debugPrint('设置音量失败: $e');
      rethrow;
    }
  }

  void startTrackRefresh() {
    logger.d("Attempting to start track refresh timers..."); // Log: Start attempt
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    
    if (username != null) {
      logger.d("Username confirmed ($username), proceeding with timer setup."); // Log: Username OK
      // 立即执行一次刷新
      refreshCurrentTrack();
      refreshAvailableDevices();
      
      // API 刷新计时器 - 每 3.5 秒从服务器获取一次
      _refreshTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) async {
        logger.d("_refreshTimer ticked!"); // Log: Timer ticked
        if (!_isSkipping) {
          try {
            // 在每次 API 调用前检查令牌是否需要刷新
            final token = await _spotifyService.getAccessToken();
            if (token == null) {
              logger.w("_refreshTimer: No valid token, logging out."); // Log: Token issue
              await logout();
              return;
            }
            
            logger.d("_refreshTimer: Calling refreshCurrentTrack and refreshAvailableDevices..."); // Log: Before refresh calls
            await refreshCurrentTrack();
            await refreshAvailableDevices();
          } catch (e) {
            logger.e('定时刷新失败 (_refreshTimer)', error: e); // Log: Timer error
            // 如果刷新失败，可能是令牌问题，尝试重新登录
            if (e is SpotifyAuthException) {
              await logout();
            }
          }
        } else {
            logger.d("_refreshTimer skipped due to _isSkipping flag."); // Log: Skipped
        }
      });
      logger.d("_refreshTimer created: active=${_refreshTimer?.isActive}"); // Log: Timer created
      
      // 本地进度计时器保持不变
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!_isSkipping && currentTrack != null && currentTrack!['is_playing']) {
          final now = DateTime.now();
          if (_lastProgressUpdate != null) {
            final elapsed = now.difference(_lastProgressUpdate!).inMilliseconds;
            currentTrack!['progress_ms'] = 
                (currentTrack!['progress_ms'] as int) + elapsed;
            notifyListeners();
          }
          _lastProgressUpdate = now;
        }
      });
      logger.d("_progressTimer created: active=${_progressTimer?.isActive}"); // Log: Timer created
    } else {
      logger.w("startTrackRefresh called but username is null. Timers not started."); // Log: No username
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshCurrentTrack() async {
    if (_isSkipping) return;
    
    try {
      final track = await _spotifyService.getCurrentlyPlayingTrack();
      
      // --- Log 1: Log the entire track data from API ---
      logger.d('Received track data from API: ${json.encode(track)}'); 

      if (track != null) {
        // --- Log 2: Log the context field specifically ---
        logger.d('Context field value from API: ${track['context']}');

        final newId = track['item']?['id'];
        final oldId = currentTrack?['item']?['id'];
        final isPlaying = track['is_playing'];
        final oldIsPlaying = currentTrack?['is_playing'];
        final progress = track['progress_ms'];
        final newContextUri = track['context']?['uri'];
        final oldContextUri = currentTrack?['context']?['uri'];

        // *** Add LocalDatabaseProvider Access ***
        // Assuming LocalDatabaseProvider is accessible via context or injected dependency
        // This might require adjusting how providers are set up (e.g., using ChangeNotifierProxyProvider)
        final localDbProvider = Provider.of<LocalDatabaseProvider>(
          navigatorKey.currentContext!, // Assuming navigatorKey provides context
          listen: false
        );

        // 检查是否需要更新状态 (基于核心播放信息)
        final shouldUpdateCoreState = currentTrack == null ||
            newId != oldId ||
            isPlaying != oldIsPlaying ||
            newContextUri != oldContextUri;
            
        bool needsNotify = false;

        // *** Moved Context Saving Logic OUTSIDE shouldUpdateCoreState check ***
        if (track['context'] != null && track['item'] != null) {
          // Log 3: Log before saving context
          logger.d('Context found, starting save process...'); 
          try {
            final context = track['context'];
            final contextUri = context['uri'] as String;
            final contextType = context['type'] as String;

            // --- Log 4: Before enriching context --- 
            logger.d('Attempting to enrich context for URI: $contextUri');
            final enrichedContext = await _enrichPlayContext(context); // 检查这里是否会出错
            // --- Log 5: After enriching context --- 
            logger.d('Enriched context result: ${json.encode(enrichedContext)}');

            final contextName = enrichedContext['name'] as String? ?? 'Unknown';
            final imageUrlList = enrichedContext['images'] as List?;
            final imageUrl = imageUrlList?.isNotEmpty == true ? imageUrlList![0]['url'] : null;

            // --- Log 6: Before getting LocalDatabaseProvider --- 
            logger.d('Attempting to get LocalDatabaseProvider...');
            final localDbProvider = Provider.of<LocalDatabaseProvider>(
              navigatorKey.currentContext!, // 检查这里是否会出错
              listen: false
            );
            // --- Log 7: After getting LocalDatabaseProvider --- 
            logger.d('Got LocalDatabaseProvider instance: $localDbProvider');

            // --- Log 8: Before calling insertOrUpdatePlayContext --- 
            logger.d('Calling insertOrUpdatePlayContext with: URI=$contextUri, Name=$contextName, Image=$imageUrl');
            await localDbProvider.insertOrUpdatePlayContext(
              contextUri: contextUri,
              contextType: contextType,
              contextName: contextName,
              imageUrl: imageUrl,
              lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
            );
            // --- Log 9: After calling insertOrUpdatePlayContext --- 
            logger.d('Successfully called insertOrUpdatePlayContext for $contextUri');
          } catch (e, s) { // Catch error and stack trace
            // Log 10: Log error during context saving
            logger.e('Error saving play context to local DB', error: e, stackTrace: s);
          }
        }
        // *** End of Moved Context Saving Logic ***

        if (shouldUpdateCoreState) {
          // Reset progress update time
          _lastProgressUpdate = DateTime.now();
          
          // Refresh playback queue on core state change
          await refreshPlaybackQueue();
          
          // No longer save context here

          previousTrack = currentTrack;
          currentTrack = track;
          needsNotify = true;
        } else if (progress != currentTrack!['progress_ms']) {
          // 即使只是进度变化，也更新进度值
          currentTrack!['progress_ms'] = progress;
          needsNotify = true; // 只需要更新进度，也要通知
        }
        
        // *** 总是检查收藏状态 ***
        bool savedStateChanged = false;
        if (track['item'] != null) {
          try {
            final currentSavedState = await _spotifyService.isTrackSaved(track['item']['id']);
            if (isCurrentTrackSaved != currentSavedState) {
              isCurrentTrackSaved = currentSavedState;
              savedStateChanged = true;
              needsNotify = true; // 如果收藏状态改变，需要通知
            }
          } catch (e) {
            debugPrint('刷新时检查歌曲保存状态失败: $e');
            // 即使检查失败，也继续执行，避免阻塞其他更新
          }
        } else if (isCurrentTrackSaved != null) {
           // 如果没有 item 了，清除收藏状态
           isCurrentTrackSaved = null;
           savedStateChanged = true;
           needsNotify = true;
        }

        // 如果核心状态或收藏状态有变化，更新 Widget 和通知监听器
        if (shouldUpdateCoreState || savedStateChanged) {
           await updateWidget();
        }
        
        if (needsNotify) {
          notifyListeners();
        }
        
      } else if (currentTrack != null) {
        // 如果当前没有播放任何内容，但之前有，则清除状态
        currentTrack = null;
        previousTrack = null;
        nextTrack = null;
        isCurrentTrackSaved = null;
        upcomingTracks.clear();
        await updateWidget(); // 更新 widget 为无播放状态
        notifyListeners();
      }
    } catch (e) {
      debugPrint('刷新当前播放失败: $e');
      // Consider adding more specific error handling if needed
    }
  }

  // 辅助方法：丰富播放上下文信息
  Future<Map<String, dynamic>> _enrichPlayContext(Map<String, dynamic> context) async {
    final type = context['type'];
    final uri = context['uri'] as String;
    
    Map<String, dynamic> enrichedContext = {
      ...context,
      'name': '未知${type == 'playlist' ? '播放列表' : '专辑'}',
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
      debugPrint('获取完整上下文信息失败: $e');
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
      debugPrint('检查歌曲保存状态失败: $e');
    }
  }

  // 添加自动登录检查
  Future<bool> autoLogin() async {
    try {
      isLoading = true;
      notifyListeners();

      debugPrint('开始自动登录检查...');
      
      // 打印当前使用的凭据信息（隐藏部分内容以保护安全）
      final credentials = await getClientCredentials();
      String? clientId = credentials['clientId'];
      
      if (clientId != null && clientId.length > 8) {
        debugPrint('自动登录使用的客户端ID: ${clientId.substring(0, 4)}...${clientId.substring(clientId.length - 4)}');
        debugPrint('客户端ID长度: ${clientId.length}');
      } else {
        debugPrint('自动登录的客户端ID为空或格式不正确');
      }

      // 检查是否有有效的 token
      if (await _spotifyService.isAuthenticated()) {
        try {
          debugPrint('发现有效的认证信息，尝试获取用户信息');
          final userProfile = await _spotifyService.getUserProfile();
          username = userProfile['display_name'];
          
          debugPrint('成功获取用户信息：$username');
          debugPrint('用户信息: ${json.encode(userProfile)}');
          
          // 启动定时刷新任务
          startTrackRefresh();
          
          // 更新小部件状态
          await updateWidget();
          
          return true;
        } catch (e) {
          debugPrint('获取用户信息失败: $e');
          debugPrint('错误类型: ${e.runtimeType}');
          
          // 检查是否为客户端ID/密钥错误 (401 Unauthorized)
          if (e is SpotifyAuthException && 
              (e.code == '401' || e.message.contains('401'))) {
            debugPrint('认证错误，可能是客户端ID或密钥无效');
            
            // 清除保存的token，但保留客户端凭据
            await _spotifyService.logout();
            
            // 不重试，直接返回失败
            return false;
          }
          
          // 尝试刷新令牌
          debugPrint('尝试刷新令牌...');
          try {
            final newToken = await _spotifyService.refreshToken();
            if (newToken != null) {
              debugPrint('令牌刷新成功，重新获取用户信息');
              final userProfile = await _spotifyService.getUserProfile();
              username = userProfile['display_name'];
              startTrackRefresh();
              await updateWidget();
              return true;
            } else {
              debugPrint('令牌刷新失败，需要重新登录');
            }
          } catch (refreshError) {
            debugPrint('刷新令牌时出错: $refreshError');
            debugPrint('错误类型: ${refreshError.runtimeType}');
            // 如果刷新也失败，可能是客户端凭据问题
            if (refreshError is SpotifyAuthException && 
                (refreshError.code == '401' || refreshError.message.contains('401'))) {
              debugPrint('刷新令牌时遇到认证错误，可能是客户端ID或密钥无效');
            }
          }
        }
      } else {
        debugPrint('未找到有效的认证信息，需要重新登录');
      }
      return false;
    } catch (e) {
      debugPrint('自动登录失败: $e');
      debugPrint('错误类型: ${e.runtimeType}');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login() async {
    try {
      isLoading = true;
      notifyListeners();

      debugPrint('开始登录流程...');

      // 确保 SpotifyService 已初始化
      if (!_isInitialized) {
        await _initSpotifyService();
        if (!_isInitialized) {
          throw SpotifyAuthException('SpotifyService 初始化失败');
        }
      }

      // 打印当前使用的凭据信息（隐藏部分内容以保护安全）
      final credentials = await getClientCredentials();
      String? clientId = credentials['clientId'];
      String? clientSecret = credentials['clientSecret'];
      
      if (clientId != null && clientId.length > 8) {
        debugPrint('使用的客户端ID: ${clientId.substring(0, 4)}...${clientId.substring(clientId.length - 4)}');
        debugPrint('客户端ID长度: ${clientId.length}');
      } else {
        debugPrint('客户端ID为空或格式不正确');
      }
      
      if (clientSecret != null && clientSecret.length > 8) {
        debugPrint('使用的客户端密钥: ${clientSecret.substring(0, 4)}...${clientSecret.substring(clientSecret.length - 4)}');
        debugPrint('客户端密钥长度: ${clientSecret.length}');
      } else {
        debugPrint('客户端密钥为空或格式不正确');
      }

      // 先尝试自动登录
      if (await autoLogin()) {
        debugPrint('自动登录成功');
        return;
      }

      debugPrint('自动登录失败，尝试重新获取令牌...');
      
      try {
        debugPrint('正在调用 SpotifySdk.getAccessToken...');
        final result = await _spotifyService.login();
        debugPrint('SpotifySdk.getAccessToken 调用成功，返回结果长度: ${result?.length ?? 0}');
        
        if (result == null) {
          throw SpotifyAuthException('登录失败：无法获取访问令牌');
        }

        debugPrint('正在获取用户信息...');
        final userProfile = await _spotifyService.getUserProfile();
        username = userProfile['display_name'];
        
        debugPrint('登录成功，用户名：$username');
        debugPrint('用户信息: ${json.encode(userProfile)}');
        
        // 启动定时刷新任务
        startTrackRefresh();
        
        // 登录后更新小部件
        await updateWidget();
      } catch (e) {
        debugPrint('登录过程中出错: $e');
        
        // 检查是否是客户端凭据问题
        if (e is SpotifyAuthException) {
          if (e.code == '401' || 
              e.message.toLowerCase().contains('invalid client') ||
              e.message.toLowerCase().contains('unauthorized') ||
              e.message.toLowerCase().contains('invalid api credentials')) {
            // 这很可能是客户端ID或密钥无效
            throw SpotifyAuthException(
              'Spotify 认证失败：客户端 ID 或密钥无效。请检查您的 Spotify 开发者凭据。',
              code: 'INVALID_CREDENTIALS'
            );
          }
        }
        
        // 其他错误，直接传递
        rethrow;
      }
    } catch (e, stack) {
      debugPrint('Spotify 登录错误详情:');
      debugPrint('错误类型: ${e.runtimeType}');
      debugPrint('错误消息: $e');
      debugPrint('堆栈跟踪:');
      debugPrint(stack.toString());
      
      // 清理可能的无效状态
      username = null;
      _refreshTimer?.cancel();
      _progressTimer?.cancel();
      
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    // Use getPlaybackState to check for active device
    Map<String, dynamic>? playbackState;
    bool hasActiveDevice = false;
    bool isCurrentlyPlaying = false;

    try {
      playbackState = await _spotifyService.getPlaybackState();
      hasActiveDevice = playbackState['device'] != null;
      isCurrentlyPlaying = playbackState['is_playing'] ?? false;
      debugPrint('Playback State: HasDevice=$hasActiveDevice, IsPlaying=$isCurrentlyPlaying');
    } catch (e) {
      debugPrint('获取播放状态失败: $e');
      // Assume no active device if state fetch fails
      hasActiveDevice = false;
      isCurrentlyPlaying = false;
    }

    try {
      if (!isCurrentlyPlaying) {
        // Logic to Start Playback
        if (!hasActiveDevice) {
          debugPrint('没有活跃设备，尝试连接并启动 Spotify...');
          bool connected = false;
          try {
            // This might prompt the user to open Spotify
            connected = await SpotifySdk.connectToSpotifyRemote(
              clientId: _spotifyService.clientId,
              redirectUrl: _spotifyService.redirectUrl,
            );
            debugPrint('连接尝试结果: $connected');

            if (connected) {
              // Connection succeeded, refresh devices and try to transfer playback
              debugPrint('连接成功，刷新设备列表并尝试转移播放...');
              await refreshAvailableDevices();
              // Short delay for provider state update
              await Future.delayed(const Duration(milliseconds: 500)); 
              
              // Try to find the newly active/local device
              final localDevice = availableDevices.firstWhereOrNull(
                (d) => d.isActive || d.type == SpotifyDeviceType.computer,
              );

              if (localDevice != null && localDevice.id != null) {
                debugPrint('找到本地设备: ${localDevice.name} (ID: ${localDevice.id}), 尝试转移播放...');
                await transferPlaybackToDevice(localDevice.id!, play: true);
              } else {
                debugPrint('无法确定本地设备，尝试通用播放命令...');
                await _spotifyService.apiPut('/me/player/play');
              }
            } else {
              // Even if connect returns false, Spotify might be open/opening.
              // Wait a bit longer before trying the generic play command.
              debugPrint('连接返回 false，等待后尝试通用播放命令...');
              await Future.delayed(const Duration(milliseconds: 3000));
              await _spotifyService.apiPut('/me/player/play');
            }
          } catch (e) {
            debugPrint('连接或播放启动失败: $e. 尝试通用播放命令...');
            // Wait a bit before fallback API call
            await Future.delayed(const Duration(milliseconds: 1000)); 
             try {
               await _spotifyService.apiPut('/me/player/play');
             } catch (fallbackError) {
               debugPrint('通用播放命令也失败: $fallbackError');
             }
          }
        } else {
           // Device already active, just send play command
           debugPrint('已有活跃设备，调用 API 播放...');
           await _spotifyService.apiPut('/me/player/play');
        }
        
        // Optimistically update UI immediately for responsiveness
        if (currentTrack != null) {
          currentTrack!['is_playing'] = true;
          notifyListeners();
        }
        
        // Wait slightly then refresh state to confirm
        await Future.delayed(const Duration(milliseconds: 800)); // Slightly longer wait after potential transfer
        await refreshCurrentTrack();
        await refreshAvailableDevices(); // Refresh devices again after play attempt
        await updateWidget();

      } else {
        // Logic to Pause Playback
        debugPrint('调用 API 暂停...');
        await _spotifyService.apiPut('/me/player/pause');
        
        // Optimistically update UI
        if (currentTrack != null) {
          currentTrack!['is_playing'] = false;
          notifyListeners();
        }

        // Wait slightly then refresh state
        await Future.delayed(const Duration(milliseconds: 500));
        await refreshCurrentTrack();
        // Don't necessarily need to refresh devices on pause
        // await refreshAvailableDevices(); 
        await updateWidget();
      }
    } catch (e) {
      debugPrint('播放/暂停切换失败: $e');
      // Revert optimistic update on error
      if (currentTrack != null) {
        currentTrack!['is_playing'] = isCurrentlyPlaying; // Revert to original state
        notifyListeners();
      }
      // Optionally show error to user
    }
  }

  Future<void> skipToNext() async {
    if (_isSkipping) return;
    
    try {
      _isSkipping = true;
      
      // 保存当前歌曲作为上一首
      previousTrack = currentTrack?['item'];
      
      // 执行切歌操作
      await _spotifyService.skipToNext();
      
      // 等待适当的时间确保 Spotify 已经切换
      // 使用轮询方式检查，最多等待1秒
      int attempts = 0;
      const maxAttempts = 10;
      const delayMs = 100;
      
      while (attempts < maxAttempts) {
        final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
        if (newTrack != null && 
            newTrack['item']?['id'] != currentTrack?['item']?['id']) {
          currentTrack = newTrack;
          await updateWidget();
          await refreshPlaybackQueue();
          notifyListeners();
          break;
        }
        
        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: delayMs));
        }
      }
      
    } catch (e) {
      debugPrint('下一首失败: $e');
      // 如果失败，恢复到原来的状态
      if (previousTrack != null) {
        currentTrack = {'item': previousTrack, 'is_playing': true};
        await updateWidget();
        notifyListeners();
      }
    } finally {
      _isSkipping = false;
    }
  }

  Future<void> skipToPrevious() async {
    if (_isSkipping) return;
    
    try {
      _isSkipping = true;
      
      // 保存当前歌曲作为下一首
      nextTrack = currentTrack?['item'];
      
      // 执行切歌操作
      await _spotifyService.skipToPrevious();
      
      // 等待适当的时间确保 Spotify 已经切换
      // 使用轮询方式检查，最多等待1秒
      int attempts = 0;
      const maxAttempts = 10;
      const delayMs = 100;
      
      while (attempts < maxAttempts) {
        final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
        if (newTrack != null && 
            newTrack['item']?['id'] != currentTrack?['item']?['id']) {
          currentTrack = newTrack;
          await updateWidget();
          await refreshPlaybackQueue();
          notifyListeners();
          break;
        }
        
        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: delayMs));
        }
      }
      
    } catch (e) {
      debugPrint('上一首失败: $e');
      // 如果失败，恢复到原来的状态
      if (nextTrack != null) {
        currentTrack = {'item': nextTrack, 'is_playing': true};
        await updateWidget();
        notifyListeners();
      }
    } finally {
      _isSkipping = false;
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
      debugPrint('切换收藏状态失败: $e');
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
      debugPrint('刷新播放队列失败: $e');
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
      debugPrint('批量缓存队列图片失败: $e');
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
      debugPrint('同步播放模式失败: $e');
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
      debugPrint('设置播放模式失败: $e');
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
    
    try {
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      await precacheImage(imageProvider, navigatorKey.currentContext!);
      _imageCache[imageUrl] = imageUrl;
    } catch (e) {
      debugPrint('预加载图片失败: $e');
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
      
      // 获取 FirestoreProvider 实例
      // final firestoreProvider = Provider.of<FirestoreProvider>(
      //   navigatorKey.currentContext!, 
      //   listen: false
      // );
      
      for (var item in items) {
        final context = item['context'];
        if (context != null) {
          final uri = context['uri'] as String;
          final type = context['type'] as String;
          final trackId = item['track']?['id'];
          final playedAt = DateTime.parse(item['played_at']);
          
          // 保存播放上下文到 Firestore
          // await firestoreProvider.savePlayContext(
          //   trackId: trackId,
          //   context: context,
          //   timestamp: playedAt,
          // );
          
          // 处理播放列表
          if (type == 'playlist' && !playlistUris.contains(uri)) {
            playlistUris.add(uri);
            final playlistId = uri.split(':').last;
            try {
              final playlist = await _spotifyService.getPlaylist(playlistId);
              uniquePlaylists.add(playlist);
              if (uniquePlaylists.length >= 10) break;
            } catch (e) {
              debugPrint('获取播放列表 $playlistId 详情失败: $e');
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
              debugPrint('获取专辑 $albumId 详情失败: $e');
            }
          }
        }
      }
      
      _recentPlaylists..clear()..addAll(uniquePlaylists);
      _recentAlbums..clear()..addAll(uniqueAlbums);
      
      notifyListeners();
    } catch (e) {
      debugPrint('刷新最近播放记录失败: $e');
    }
  }

  // 在 SpotifyProvider 类中添加 logout 方法
  Future<void> logout() async {
    try {
      isLoading = true;
      notifyListeners();

      // 清除 token 和用户信息
      await _spotifyService.logout();
      username = null;
      currentTrack = null;
      previousTrack = null;
      nextTrack = null;
      isCurrentTrackSaved = null;
      
      // 停止刷新计时器
      _refreshTimer?.cancel();
      _refreshTimer = null;

      // 登出后更新小部件为默认状态
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.gojyuplusone.spotoolfy/widget');
        try {
          await platform.invokeMethod('updateWidget', {
            'songName': '',
            'artistName': '',
            'albumArtUrl': '',
            'isPlaying': false,
          });
        } catch (e) {
          debugPrint('更新 widget 失败: $e');
        }
      }

    } catch (e) {
      debugPrint('退出登录失败: $e');
      rethrow;
    } finally {
      isLoading = false;
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
        debugPrint('更新 widget 失败: $e');
      }
    }
  }

  Future<void> seekToPosition(Duration position) async {
    try {
      await _spotifyService.seekToPosition(position);
      await refreshCurrentTrack();
      // 跳转位置后刷新队列
      await refreshPlaybackQueue();
    } catch (e) {
      debugPrint('跳转播放位置失败: $e');
      rethrow;
    }
  }

  /// 播放专辑或播放列表
  Future<void> playContext({
    required String type,
    required String id,
    int? offsetIndex,
    String? deviceId,
  }) async {
    try {
      final contextUri = 'spotify:$type:$id';
      await _spotifyService.playContext(
        contextUri: contextUri,
        offsetIndex: offsetIndex,
        deviceId: deviceId,
      );

      // 等待适当的时间确保 Spotify 已经切换
      // 使用轮询方式检查，最多等待2秒
      int attempts = 0;
      const maxAttempts = 20;  // 增加尝试次数，因为加载播放列表可能需要更长时间
      const delayMs = 100;
      
      while (attempts < maxAttempts) {
        final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
        if (newTrack != null && 
            newTrack['context']?['uri'] == contextUri) {
          currentTrack = newTrack;
          await updateWidget();
          await refreshPlaybackQueue();
          notifyListeners();
          break;
        }
        
        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: delayMs));
        }
      }

      // 即使没有检测到变化，也刷新一次以确保状态同步
      if (attempts >= maxAttempts) {
        await refreshCurrentTrack();
        await refreshPlaybackQueue();
      }
    } catch (e) {
      debugPrint('播放 $type 失败: $e');
      rethrow;
    }
  }

  /// 播放指定歌曲
  Future<void> playTrack({
    required String trackUri,
    String? deviceId,
    String? contextUri,  // 添加上下文URI参数
  }) async {
    try {
      if (contextUri != null) {
        // 如果有上下文，在上下文中播放
        await _spotifyService.playTrackInContext(
          contextUri: contextUri,
          trackUri: trackUri,
          deviceId: deviceId,
        );
      } else {
        // 否则单独播放
        await _spotifyService.playTrack(
          trackUri: trackUri,
          deviceId: deviceId,
        );
      }
      
      // 等待适当的时间确保 Spotify 已经切换
      // 使用轮询方式检查，最多等待2秒
      int attempts = 0;
      const maxAttempts = 20;  // 增加尝试次数，因为加载可能需要更长时间
      const delayMs = 100;
      
      while (attempts < maxAttempts) {
        final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
        if (newTrack != null && 
            newTrack['item']?['uri'] == trackUri) {
          currentTrack = newTrack;
          await updateWidget();
          await refreshPlaybackQueue();
          notifyListeners();
          break;
        }
        
        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: delayMs));
        }
      }

      // 即使没有检测到变化，也刷新一次以确保状态同步
      if (attempts >= maxAttempts) {
        await refreshCurrentTrack();
        await refreshPlaybackQueue();
      }
    } catch (e) {
      debugPrint('播放歌曲失败: $e');
      rethrow;
    }
  }

  Future<void> playTrackInContext({
    required String contextUri,
    required String trackUri,
    String? deviceId,
  }) async {
    try {
      final headers = await getAuthenticatedHeaders();
      
      // 首先检查设备状态
      if (deviceId != null) {
        final devicesResponse = await http.get(
          Uri.parse('https://api.spotify.com/v1/me/player/devices'),
          headers: headers,
        );
        
        if (devicesResponse.statusCode == 200) {
          final devices = json.decode(devicesResponse.body)['devices'] as List;
          final targetDevice = devices.firstWhere(
            (d) => d['id'] == deviceId,
            orElse: () => null,
          );
          
          if (targetDevice != null && targetDevice['is_restricted'] == true) {
            throw SpotifyAuthException(
              '此设备（${targetDevice['name']}）不支持通过 API 控制播放。\n'
              '请使用 Spotify 或设备自带的应用进行控制。',
              code: 'RESTRICTED_DEVICE',
            );
          }
        }
      }
      
      // 对于非受限设备，使用标准播放方式
      final trackResponse = await http.get(
        Uri.parse('https://api.spotify.com/v1/tracks/${trackUri.split(':').last}'),
        headers: headers,
      );

      if (trackResponse.statusCode != 200) {
        throw SpotifyAuthException(
          '获取歌曲信息失败: ${trackResponse.body}',
          code: trackResponse.statusCode.toString(),
        );
      }

      final trackInfo = json.decode(trackResponse.body);
      
      // 构建播放请求
      Map<String, dynamic> body = {
        'context_uri': contextUri,
      };

      // 尝试使用 URI 作为 offset
      body['offset'] = {'uri': trackUri};

      final queryParams = deviceId != null ? '?device_id=$deviceId' : '';
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 202 && response.statusCode != 204) {
        // 如果使用 URI 失败，尝试使用 track_number
        final trackNumber = trackInfo['track_number'];
        if (response.statusCode == 404 && trackNumber is int && trackNumber > 0) {
          body['offset'] = {'position': trackNumber - 1};
          
          final retryResponse = await http.put(
            Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
            headers: headers,
            body: json.encode(body),
          );
          
          if (retryResponse.statusCode != 202 && retryResponse.statusCode != 204) {
            throw SpotifyAuthException(
              '开始播放失败: ${retryResponse.body}',
              code: retryResponse.statusCode.toString(),
            );
          }
        } else {
          throw SpotifyAuthException(
            '开始播放失败: ${response.body}',
            code: response.statusCode.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('在上下文中播放歌曲时出错: $e');
      rethrow;
    }
  }

  /// Get authenticated headers from the Spotify service
  Future<Map<String, String>> getAuthenticatedHeaders() async {
    return await _spotifyService.getAuthenticatedHeaders();
  }

  // 处理断开连接
  Future<void> _handleDisconnection() async {
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    
    try {
      // 尝试重新连接
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _spotifyService.clientId,
        redirectUrl: _spotifyService.redirectUrl,
      );
      
      if (connected) {
        debugPrint('重新连接成功');
        // 连接成功后刷新状态
        await refreshCurrentTrack();
        await refreshAvailableDevices();
      } else {
        debugPrint('重新连接失败');
      }
    } catch (e) {
      debugPrint('重新连接时出错: $e');
    } finally {
      _isReconnecting = false;
    }
  }

  // 监听连接状态
  void _setupConnectionListener() {
    try {
      SpotifySdk.subscribeConnectionStatus().listen(
        (status) async {
          if (!status.connected && !_isReconnecting) {
            debugPrint('检测到连接断开，开始重连流程...');
            await _handleDisconnection();
          } else if (status.connected) {
            debugPrint('检测到连接成功，刷新播放状态...');
            // 连接成功时刷新播放状态
            await refreshCurrentTrack();
            await refreshAvailableDevices();
          }
        },
        onError: (e) {
          debugPrint('连接状态监听错误: $e');
          _handleDisconnection();
        },
      );
    } catch (e) {
      debugPrint('设置连接监听器失败: $e');
    }
  }

  /// 获取用户的播放列表
  Future<List<Map<String, dynamic>>> getUserPlaylists({int limit = 50, int offset = 0}) async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        debugPrint('未登录，无法获取播放列表');
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
      debugPrint('获取用户播放列表失败: $e');
      return [];
    }
  }

  /// 获取用户收藏的专辑
  Future<List<Map<String, dynamic>>> getUserSavedAlbums({int limit = 50, int offset = 0}) async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        debugPrint('未登录，无法获取收藏专辑');
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
      debugPrint('获取收藏专辑失败: $e');
      return [];
    }
  }

  /// 获取最近播放的记录
  Future<List<Map<String, dynamic>>> getRecentlyPlayed() async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        debugPrint('未登录，无法获取最近播放');
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
              debugPrint('获取上下文详情失败: $e');
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
      debugPrint('获取最近播放记录失败: $e');
      return [];
    }
  }

  /// Fetches the raw list of recently played track items from Spotify.
  Future<List<Map<String, dynamic>>> getRecentlyPlayedRawTracks({int limit = 50}) async {
    try {
      if (!await _spotifyService.isAuthenticated()) {
        debugPrint('未登录，无法获取原始最近播放记录');
        return [];
      }
      return await _spotifyService.getRecentlyPlayedRawTracks(limit: limit);
    } catch (e) {
      debugPrint('获取原始最近播放记录失败: $e');
      return [];
    }
  }

  /// Search for items (tracks, albums, artists, playlists)
  Future<Map<String, List<Map<String, dynamic>>>> searchItems(String query, {List<String> types = const ['track', 'album', 'artist', 'playlist'], int limit = 20}) async {
    if (!_isInitialized) {
      await _initSpotifyService();
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
      debugPrint('SpotifyProvider.searchItems - Decoded Response:');
      debugPrint(json.encode(response));
      // --- End logging ---

      final Map<String, List<Map<String, dynamic>>> results = {};

      // Process tracks
      if (response['tracks']?['items'] != null && types.contains('track')) {
        debugPrint('Processing tracks...');
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
        debugPrint('Processing albums...');
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
        debugPrint('Processing artists...');
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
        debugPrint('Processing playlists...');
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
      debugPrint('SpotifyProvider.searchItems - Final Results Map:');
      debugPrint(json.encode(results));
      // --- End logging ---

      return results;
    } catch (e) {
      debugPrint('Spotify search failed: $e');
      // Depending on how you want to handle errors, you might return empty or rethrow
      // rethrow;
      return {}; // Return empty map on error for now
    }
  }
}