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
import 'package:flutter/material.dart';
import '../pages/devices.dart';

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
  }

  Future<void> _initSpotifyService() async {
    if (_isInitialized) return;
    
    try {
      final clientId = await _secureStorage.read(key: _clientIdKey) ?? SpotifySecrets.clientId;
      
      _spotifyService = SpotifyAuthService(
        clientId: clientId,
        redirectUrl: kIsWeb 
            ? 'http://localhost:8080/spotify_callback.html'
            : 'spotoolfy://callback',
      );
      _isInitialized = true;
    } catch (e) {
      // debugPrint('初始化 SpotifyService 失败: $e');
      _isInitialized = false;
    }
  }

  Future<void> setClientCredentials(String clientId) async {
    try {
      // 1. Dispose existing service if initialized
      // Note: Accessing _spotifyService directly here is safe because _isInitialized check comes first.
      // If _isInitialized is false, _spotifyService might not be assigned, but the condition short-circuits.
      if (_isInitialized && _spotifyService != null) { 
        await _spotifyService.dispose();
      }

      // 2. Cancel timers
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _progressTimer?.cancel();
      _progressTimer = null;

      // 3. Reset all provider state variables
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
      // _currentMode = PlayMode.sequential; // Resetting to default if applicable
      
      // 4. Mark as uninitialized BEFORE saving new creds and re-init
      _isInitialized = false; 

      // 5. Save new credentials
      await _secureStorage.write(key: _clientIdKey, value: clientId);
      
      // 6. Re-initialize service with new credentials
      await _initSpotifyService(); // This will set up the new _spotifyService instance

      notifyListeners(); // Notify after all changes are complete
    } catch (e) {
      // debugPrint('设置客户端凭据失败: $e');
      // 不自动恢复默认凭据，让用户自己决定是否重置
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
    // 清除存储中的自定义凭据
    await _secureStorage.delete(key: _clientIdKey);
    
    // 清除现有状态
    username = null;
    currentTrack = null;
    previousTrack = null;
    nextTrack = null;
    isCurrentTrackSaved = null;
    _availableDevices.clear();
    _activeDeviceId = null;
    _isInitialized = false;
    
    // 停止所有计时器
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    
    // 如果之前已登录，先注销
    if (!_isInitialized) await _initSpotifyService(); // 确保服务初始化
    bool previouslyLoggedIn = false;
    if (_isInitialized) {
        try {
          previouslyLoggedIn = await _spotifyService.isAuthenticated();
        } catch(e) {
          // debugPrint('检查旧认证状态时出错: $e');
        }
    }

    if (previouslyLoggedIn) {
        try {
          // 确保服务已初始化才能调用 logout
          if(_isInitialized) await _spotifyService.logout();
        } catch (e) {
          // debugPrint('注销时出错: $e');
        }
    }

    // 用默认凭据重新初始化服务 (这一步会覆盖旧的 _spotifyService 实例)
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
    // logger.d("Attempting to start track refresh timers..."); // Log: Start attempt
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    
    if (username != null) {
      // logger.d("Username confirmed ($username), proceeding with timer setup."); // Log: Username OK
      // 立即执行一次刷新
      refreshCurrentTrack();
      refreshAvailableDevices();
      
      // API 刷新计时器 - 每 3.5 秒从服务器获取一次
      _refreshTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) async {
        // logger.d("_refreshTimer ticked!"); // Log: Timer ticked
        if (!_isSkipping) {
          try {
            // 在每次 API 调用前检查令牌是否需要刷新
            final token = await _spotifyService.getAccessToken();
            if (token == null) {
              // logger.w("_refreshTimer: No valid token, logging out."); // Log: Token issue
              await logout();
              return;
            }
            
            // logger.d("_refreshTimer: Calling refreshCurrentTrack and refreshAvailableDevices..."); // Log: Before refresh calls
            await refreshCurrentTrack();
            await refreshAvailableDevices();
          } catch (e) {
            // logger.e('定时刷新失败 (_refreshTimer)', error: e); // Log: Timer error
            // 如果刷新失败，可能是令牌问题，尝试重新登录
            if (e is SpotifyAuthException && e.code == '401') {
              // print('_refreshTimer encountered 401, attempting silent refresh...'); // Add logging
              // 尝试静默续约
              final token = await _spotifyService.getAccessToken();
              if (token != null) {
                // print('_refreshTimer: Silent refresh successful.'); // Add logging
                return; // 续约成功，下个 tick 继续
              }
              // print('_refreshTimer: Silent refresh failed, logging out.'); // Add logging
              // 仍为空则彻底登出
              await logout();
            } else {
              // Log other errors if necessary
              // logger.e('定时刷新失败 (_refreshTimer)', error: e);
            }
          }
        } else {
            // logger.d("_refreshTimer skipped due to _isSkipping flag."); // Log: Skipped
        }
      });
      // logger.d("_refreshTimer created: active=${_refreshTimer?.isActive}"); // Log: Timer created
      
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
      // logger.d("_progressTimer created: active=${_progressTimer?.isActive}"); // Log: Timer created
    } else {
      // logger.w("startTrackRefresh called but username is null. Timers not started."); // Log: No username
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
      // logger.d('Received track data from API: ${json.encode(track)}'); 

      if (track != null) {
        // --- Log 2: Log the context field specifically ---
        // logger.d('Context field value from API: ${track['context']}');

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
        String? enrichedContextName;
        List? enrichedContextImages;
        if (track['context'] != null && track['item'] != null) {
          // Log 3: Log before saving context
          // logger.d('Context found, starting save process...'); 
          try {
            final context = track['context'];
            final contextUri = context['uri'] as String;
            final contextType = context['type'] as String;

            // --- Log 4: Before enriching context --- 
            // logger.d('Attempting to enrich context for URI: $contextUri');
            final enrichedContext = await _enrichPlayContext(context); // 检查这里是否会出错
            // --- Log 5: After enriching context --- 
            // logger.d('Enriched context result: ${json.encode(enrichedContext)}');

            // !! Store enriched info for later use in currentTrack !!
            enrichedContextName = enrichedContext['name'] as String?;
            enrichedContextImages = enrichedContext['images'] as List?;

            final contextName = enrichedContextName ?? 'Unknown'; // Use stored name
            final imageUrlList = enrichedContextImages; // Use stored images
            final imageUrl = imageUrlList?.isNotEmpty == true ? imageUrlList![0]['url'] : null;

            // --- Log 6: Before getting LocalDatabaseProvider --- 
            // logger.d('Attempting to get LocalDatabaseProvider...');
            final localDbProvider = Provider.of<LocalDatabaseProvider>(
              navigatorKey.currentContext!, // 检查这里是否会出错
              listen: false
            );
            // --- Log 7: After getting LocalDatabaseProvider --- 
            // logger.d('Got LocalDatabaseProvider instance: $localDbProvider');

            // --- Log 8: Before calling insertOrUpdatePlayContext --- 
            // logger.d('Calling insertOrUpdatePlayContext with: URI=$contextUri, Name=$contextName, Image=$imageUrl');
            await localDbProvider.insertOrUpdatePlayContext(
              contextUri: contextUri,
              contextType: contextType,
              contextName: contextName,
              imageUrl: imageUrl,
              lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
            );
            // --- Log 9: After calling insertOrUpdatePlayContext --- 
            // logger.d('Successfully called insertOrUpdatePlayContext for $contextUri');
          } catch (e, s) { // Catch error and stack trace
            // Log 10: Log error during context saving
            // logger.e('Error saving play context to local DB', error: e, stackTrace: s);
          }
        }
        // *** End of Moved Context Saving Logic ***

        if (shouldUpdateCoreState) {
          // Reset progress update time
          _lastProgressUpdate = DateTime.now();
          
          // Refresh playback queue on core state change
          await refreshPlaybackQueue();
          
          // !! Merge enriched context info into track before assigning !!
          if (track['context'] != null && enrichedContextName != null) {
            // Ensure 'context' is a mutable map
            if (track['context'] is Map && !(track['context'] is Map<String, dynamic>)) {
              track['context'] = Map<String, dynamic>.from(track['context']);
            }
            track['context']['enriched_name'] = enrichedContextName;
            track['context']['enriched_images'] = enrichedContextImages;
          }

          previousTrack = currentTrack;
          currentTrack = track; // Assign the modified track object
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
            // debugPrint('刷新时检查歌曲保存状态失败: $e');
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
      // debugPrint('刷新当前播放失败: $e');
      await _handleApiError(e, contextMessage: 'Refresh current playback');
      // Consider adding more specific error handling if needed
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

  // 修改 autoLogin，移除 refreshToken 调用
  Future<bool> autoLogin() async {
    // debugPrint('开始自动登录检查...');
    isLoading = true;
    notifyListeners();

    try {
      final credentials = await getClientCredentials();
      String? clientId = credentials['clientId'];
      // debugPrint('自动登录使用的客户端ID: ${clientId?.substring(0, 4)}...${clientId?.substring(clientId.length - 4)}');

      // 确保服务已初始化
      if (!_isInitialized) {
        await _initSpotifyService();
      }
      if (!_isInitialized) {
        // debugPrint('SpotifyService 初始化失败，无法自动登录');
        // [!] 确保 isLoading 在返回前设置为 false
        isLoading = false;
        notifyListeners();
        return false;
      }

      // 检查是否有有效的 token (使用简化后的 isAuthenticated)
      if (await _spotifyService.isAuthenticated()) {
        // debugPrint('发现有效的认证信息，尝试获取用户信息');
        try {
          final userProfile = await _spotifyService.getUserProfile();
          username = userProfile['display_name'];
          // debugPrint('成功获取用户信息：$username');

          // [!] 只有在成功获取用户信息后才启动刷新和更新UI
          startTrackRefresh();
          await updateWidget();
          // [!] 在 return true 之前确保 isLoading 为 false 并通知
          isLoading = false;
          notifyListeners(); // 确保UI在成功后更新
          return true;
        } catch (e) {
          // debugPrint('自动登录时获取用户信息失败: $e');
          // [!] 如果获取用户信息失败，即使 token 可能有效，也视为登录失败，执行登出清理状态
          await logout(); // 调用 Provider 的 logout 清理 username 等状态
          // isLoading 已经在 logout 的 finally 中处理
          // notifyListeners 也在 logout 的 finally 中处理
          return false; // 返回 false 表示自动登录未完成
        }
      } else {
        // debugPrint('未找到有效的认证信息或已过期，需要重新登录');
        // [!] 确保 isLoading 在返回前设置为 false
        isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      // debugPrint('自动登录检查过程中发生异常: $e');
      // [!] 发生未知错误，也尝试清理状态并确保 loading 结束
      try {
          await logout(); // 尝试登出清理
      } catch (logoutError) {
          // debugPrint('自动登录异常处理中登出失败: $logoutError');
          // 即使登出失败，也要确保 loading 状态正确
          username = null; // 手动确保 username 为 null
      } finally {
          isLoading = false;
          notifyListeners();
      }
      return false;
    }
    // [!] 移除旧的 finally 块，因为每个分支都处理了 isLoading 和 notifyListeners
  }

  // 修改 login，移除 refreshToken 调用
  Future<void> login() async {
    isLoading = true;
    notifyListeners();

    try {
      // debugPrint('开始登录流程...');

      // 确保 SpotifyService 已初始化
      if (!_isInitialized) {
        await _initSpotifyService();
        if (!_isInitialized) {
          throw SpotifyAuthException('SpotifyService 初始化失败');
        }
      }

      // 打印凭据信息 (保持不变)
      // ...

      // 不再需要先调用 autoLogin，直接调用 service 的 login
      // 它内部会先检查 isAuthenticated
      // if (await autoLogin()) { ... return; }

      // debugPrint('调用 SpotifyAuthService.login()...');
      final accessToken = await _spotifyService.login(); // 使用 service 的 login
      // debugPrint('SpotifyAuthService.login() 调用成功，返回 token: ${accessToken != null}');

      if (accessToken == null) {
        // 如果 service.login 返回 null，说明用户取消或发生错误
        // service 内部应该已经抛出了具体的 SpotifyAuthException
        // 这里可以根据需要处理，或者依赖 service 抛出的异常
        // 为保险起见，抛出一个通用错误
        throw SpotifyAuthException('登录失败或用户取消 (token is null)');
      }

      // [!] 关键：获取 token 成功后，必须成功获取用户信息才算登录完成
      // debugPrint('登录成功，正在获取用户信息...');
      try {
         final userProfile = await _spotifyService.getUserProfile();
         username = userProfile['display_name'];
         // debugPrint('获取用户信息成功：$username');

         // [!] 只有用户信息获取成功后才启动刷新和更新 UI
         startTrackRefresh();
         await updateWidget();
         // isLoading = false; // 移到 finally
         // notifyListeners(); // 移到 finally
      } catch(e) {
         // debugPrint('登录后获取用户信息失败: $e');
         // [!] 获取用户信息失败，执行登出清理状态
         await logout(); // 清理 provider 状态 (username 会变 null)
         // 抛出特定错误给 UI 层提示
         throw SpotifyAuthException('登录成功但无法验证用户信息，请稍后重试。原始错误: ${e.toString()}'); 
      }

    } catch (e) {
      // debugPrint('Spotify 登录流程出错: $e');

      // [!] 不再在这里直接调用 logout，因为 login 失败 或 getUserProfile 失败时已调用
      // [!] _handleApiError 也不在此处调用，让异常自然抛出或由上层处理
      // [!] 确保 isLoading 在 finally 中被设置

      // 处理特定错误并可能重新包装抛出
      if (e is SpotifyAuthException) {
          if (e.code == 'AUTH_SETUP_ERROR' || e.code == 'INVALID_CREDENTIALS' /*或其他认证配置错误码*/) {
              // 抛出用户友好的设置错误
              throw SpotifyAuthException(
                 'Spotify 认证失败：请检查您的 Client ID 和 Redirect URI 设置。 (${e.message})',
                 code: 'AUTH_SETUP_ERROR'
               );
          } else if (e.code == 'AUTH_CANCELLED') {
             // 用户取消，静默处理，不需要抛异常给上层显示错误
             // isLoading 和 notifyListeners 会在 finally 中处理
             return; // 直接返回
          }
          // 其他 SpotifyAuthException 直接重新抛出
          rethrow;
      } else {
        // 包装其他未知错误
        throw Exception('发生未知登录错误: $e');
      }
    } finally {
      isLoading = false;
      notifyListeners(); // 确保无论成功、失败还是取消，UI 都更新 loading 状态
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
  Future<bool> _ensureActiveDeviceOrShowPicker() async {
    try {
      final playbackState = await _spotifyService.getPlaybackState();
      final hasActiveDevice = playbackState['device'] != null;
      if (!hasActiveDevice) {
        await _showDevicesPage();
        return false; // No active device, picker shown
      }
      return true; // Active device exists
    } catch (e) {
      // debugPrint('获取播放状态失败: $e');
      // Don't call _handleApiError here directly, as we want to show the picker anyway
      // Assume no active device if state fetch fails, show picker
      await _showDevicesPage();
      return false;
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
      // debugPrint('Playback State: HasDevice=$hasActiveDevice, IsPlaying=$isCurrentlyPlaying');
    } catch (e) {
      // debugPrint('获取播放状态失败: $e');
      // Assume no active device if state fetch fails
      hasActiveDevice = false;
      isCurrentlyPlaying = false;
    }

    try {
      if (!isCurrentlyPlaying) {
        // Logic to Start Playback
        if (!hasActiveDevice) {
          // No active device, show the device picker
          await _showDevicesPage();
          return; // Stop execution here, let user pick device
        } else {
           // Device already active, just send play command
           // debugPrint('已有活跃设备，调用 API 播放...');
           await _spotifyService.apiPut('/me/player/play');
        }
        
        // Optimistically update UI immediately for responsiveness
        if (currentTrack != null) {
          currentTrack!['is_playing'] = true;
          notifyListeners();
        }
        
        // Wait slightly then refresh state to confirm
        await Future.delayed(const Duration(milliseconds: 800)); 
        await refreshCurrentTrack();
        await refreshAvailableDevices(); // Refresh devices again after play attempt
        await updateWidget();

      } else {
        // Logic to Pause Playback (no device check needed for pause)
        // debugPrint('调用 API 暂停...');
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
      // debugPrint('播放/暂停切换失败: $e');
      // Revert optimistic update on error
      if (currentTrack != null) {
        currentTrack!['is_playing'] = isCurrentlyPlaying; // Revert to original state
        notifyListeners();
      }
      // Optionally show error to user
      await _handleApiError(e, contextMessage: '播放/暂停切换');
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
      // debugPrint('下一首失败: $e');
      await _handleApiError(e, contextMessage: '下一首');
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
      // debugPrint('上一首失败: $e');
      await _handleApiError(e, contextMessage: '上一首');
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
    // logger.d('Provider logout called');
    // [!] 优化：如果已经在 loading，避免重复设置和通知
    bool wasLoading = isLoading;
    if (!wasLoading) {
      isLoading = true;
      notifyListeners();
    }

    try {
      // 停止刷新计时器
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _progressTimer?.cancel(); // 也停止进度计时器
      _progressTimer = null;

      // Dispose and logout from the service, then mark as uninitialized
      if (_isInitialized && _spotifyService != null) {
        // logger.d('Calling _spotifyService.dispose() and _spotifyService.logout()');
        await _spotifyService.dispose();
        await _spotifyService.logout();
      }
      _isInitialized = false; 

      // Reset all provider state variables
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
      // _currentMode is a state variable, reset it to default if necessary, though not explicitly listed in prompt, good practice.
      // _currentMode = PlayMode.sequential; // Assuming sequential is the default.

      // 更新小部件为默认状态
      await updateWidget(); // 更新为无播放状态

    } catch (e) {
      // logger.e('Error during provider logout: $e');
      // 即使 service logout 失败，也要确保 provider 状态已清理 (username=null)
      rethrow; // 重新抛出，让调用者知道 logout 过程有错
    } finally {
      // [!] 确保 loading 状态恢复，并通知监听器最终状态
      if (!wasLoading) { // 只有当此函数启动 loading 时才停止它
          isLoading = false;
      }
      notifyListeners(); // 通知最终状态（username 为 null 等）
      // logger.d('Provider logout finished');
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

  Future<void> seekToPosition(Duration position) async {
    try {
      await _spotifyService.seekToPosition(position);
      await refreshCurrentTrack();
      // 跳转位置后刷新队列
      await refreshPlaybackQueue();
    } catch (e) {
      // debugPrint('跳转播放位置失败: $e');
      await _handleApiError(e, contextMessage: '跳转播放位置');
      rethrow;
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
    if (!await _ensureActiveDeviceOrShowPicker()) {
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
    if (!await _ensureActiveDeviceOrShowPicker()) {
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
    if (!await _ensureActiveDeviceOrShowPicker()) {
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
    if (!_isInitialized) await _initSpotifyService();
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
  Future<void> _handleApiError(dynamic e, {String? contextMessage}) async {
    final message = contextMessage ?? 'API 调用';
    if (e is SpotifyAuthException && e.code == '401') {
      // print('$message 遇到 401，尝试静默续约/重连...'); // Log updated message
      final token = await _spotifyService.getAccessToken();
      if (token != null) {
        // print('$message: Token 仍有效，尝试重连 Spotify Remote...'); // Log reconnection attempt
        // 尝试只重连，不清除票据
        try {
          await _spotifyService.login(); // Use login() which handles connection
          // print('$message: 重连成功。'); // Log success
        } catch (reconnectError) {
          // print('$message: 重连尝试失败: $reconnectError'); // Log reconnection failure
          // 如果重连也失败，可能需要登出，或者让下一次API调用再次触发401
          // 暂不处理，让下一次 API 调用再次触发
        }
        return; // 下个 tick 继续
      }
      // print('$message: getAccessToken() 返回 null，Token 确认无效，执行登出。'); // Log logout decision
      // [!] 续约失败，意味着会话彻底无效，必须登出。
      await logout(); // 清理 Provider 状态，设置 username = null
      // 抛出特定错误，通知 UI 会话已过期。
      throw SpotifyAuthException('会话已过期，请重新登录', code: 'SESSION_EXPIRED');
    } else {
      // print('$message 出错: $e');
      // 对于其他非 401 错误，直接重新抛出。
      if (e is Exception) {
        throw e; // Re-throw the original exception object
      } else {
        throw Exception('$message 发生未知错误: $e');
      }
    }
  }
  // --- 辅助方法结束 ---
}