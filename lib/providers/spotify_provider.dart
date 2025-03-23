import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import '../services/spotify_service.dart';
import '../models/spotify_device.dart';
import 'package:collection/collection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../providers/firestore_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../config/secrets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';


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
      print('初始化 SpotifyService 失败: $e');
      _isInitialized = false;
    }
  }

  Future<void> setClientCredentials(String clientId, String clientSecret) async {
    await _secureStorage.write(key: _clientIdKey, value: clientId);
    await _secureStorage.write(key: _clientSecretKey, value: clientSecret);
    await _initSpotifyService();
    notifyListeners();
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
    await _secureStorage.delete(key: _clientIdKey);
    await _secureStorage.delete(key: _clientSecretKey);
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
      print('刷新可用设备列表失败: $e');
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
      print('转移播放失败: $e');
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
      print('设置音量失败: $e');
      rethrow;
    }
  }

  void startTrackRefresh() {
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    
    if (username != null) {
      // 立即执行一次刷新
      refreshCurrentTrack();
      refreshAvailableDevices();
      
      // API 刷新计时器 - 每5秒从服务器获取一次
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!_isSkipping) {
          try {
            // 在每次 API 调用前检查令牌是否需要刷新
            final token = await _spotifyService.getAccessToken();
            if (token == null) {
              // 如果获取不到有效令牌，可能需要重新登录
              await logout();
              return;
            }
            
            await refreshCurrentTrack();
            await refreshAvailableDevices();
          } catch (e) {
            print('定时刷新失败: $e');
            // 如果刷新失败，可能是令牌问题，尝试重新登录
            if (e is SpotifyAuthException) {
              await logout();
            }
          }
        }
      });
      
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
      // 打印当前的 ClientID
      final credentials = await getClientCredentials();
      print('当前使用的 ClientID: ${credentials['clientId']}');
      
      final track = await _spotifyService.getCurrentlyPlayingTrack();
      if (track != null) {
        final newId = track['item']?['id'];
        final oldId = currentTrack?['item']?['id'];
        final isPlaying = track['is_playing'];
        final oldIsPlaying = currentTrack?['is_playing'];
        final progress = track['progress_ms'];
        final newContextUri = track['context']?['uri'];
        final oldContextUri = currentTrack?['context']?['uri'];

        // 检查是否需要更新状态
        final shouldUpdate = currentTrack == null || 
            newId != oldId || 
            isPlaying != oldIsPlaying ||
            newContextUri != oldContextUri;

        if (shouldUpdate) {
          // 重置进度更新时间
          _lastProgressUpdate = DateTime.now();
          
          // 在以下情况刷新播放队列：
          // 1. 首次加载 (currentTrack == null)
          // 2. 歌曲改变 (newId != oldId)
          // 3. 播放状态改变 (isPlaying != oldIsPlaying)
          // 4. 播放上下文改变 (newContextUri != oldContextUri)
          await refreshPlaybackQueue();
          
          // 获取 FirestoreProvider 实例并保存播放上下文
          if (track['context'] != null) {
            final firestoreProvider = Provider.of<FirestoreProvider>(
              navigatorKey.currentContext!, 
              listen: false
            );
            
            final enrichedContext = await _enrichPlayContext(track['context']);
            await firestoreProvider.savePlayContext(
              trackId: track['item']['id'],
              context: enrichedContext,
              timestamp: DateTime.now(),
            );
          }

          previousTrack = currentTrack;
          currentTrack = track;
          
          if (track['item'] != null) {
            isCurrentTrackSaved = await _spotifyService.isTrackSaved(track['item']['id']);
          }
          
          // 更新小部件
          await updateWidget();
          
          notifyListeners();
        } else if (progress != currentTrack!['progress_ms']) {
          // 即使只是进度变化，也更新进度值
          currentTrack!['progress_ms'] = progress;
          notifyListeners();
        }
      } else if (currentTrack != null) {
        // 如果当前没有播放任何内容，但之前有，则清除状态
        currentTrack = null;
        previousTrack = null;
        nextTrack = null;
        isCurrentTrackSaved = null;
        upcomingTracks.clear();
        notifyListeners();
      }
    } catch (e) {
      print('刷新当前播放失败: $e');
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
        if (fullAlbum != null) {
          enrichedContext.addAll({
            'name': fullAlbum['name'],
            'images': fullAlbum['images'],
            'external_urls': fullAlbum['external_urls'],
          });
        }
      } else if (type == 'playlist') {
        final playlistId = uri.split(':').last;
        final fullPlaylist = await _spotifyService.getPlaylist(playlistId);
        if (fullPlaylist != null) {
          enrichedContext.addAll({
            'name': fullPlaylist['name'],
            'images': fullPlaylist['images'],
            'external_urls': fullPlaylist['external_urls'],
            'owner': fullPlaylist['owner'],
            'public': fullPlaylist['public'],
            'collaborative': fullPlaylist['collaborative'],
          });
        }
      }
    } catch (e) {
      print('获取完整上下文信息失败: $e');
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
      print('检查歌曲保存状态失败: $e');
    }
  }

  // 添加自动登录检查
  Future<bool> autoLogin() async {
    try {
      isLoading = true;
      notifyListeners();

      print('开始自动登录检查...');

      // 确保 SpotifyService 已初始化
      if (!_isInitialized) {
        await _initSpotifyService();
        if (!_isInitialized) {
          print('SpotifyService 初始化失败');
          return false;
        }
      }

      // 检查是否有有效的 token
      if (await _spotifyService.isAuthenticated()) {
        try {
          print('发现有效的认证信息，尝试获取用户信息');
          final userProfile = await _spotifyService.getUserProfile();
          username = userProfile['display_name'];
          
          print('成功获取用户信息：$username');
          
          // 启动定时刷新任务
          startTrackRefresh();
          
          // 更新小部件状态
          await updateWidget();
          
          return true;
        } catch (e) {
          print('获取用户信息失败: $e');
          // 如果获取用户信息失败，可能是令牌已失效
          // 尝试刷新令牌
          print('尝试刷新令牌...');
          final newToken = await _spotifyService.refreshToken();
          if (newToken != null) {
            print('令牌刷新成功，重新获取用户信息');
            final userProfile = await _spotifyService.getUserProfile();
            username = userProfile['display_name'];
            startTrackRefresh();
            await updateWidget();
            return true;
          } else {
            print('令牌刷新失败，需要重新登录');
          }
        }
      } else {
        print('未找到有效的认证信息，需要重新登录');
      }
      return false;
    } catch (e) {
      print('自动登录失败: $e');
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

      print('开始登录流程...');

      // 确保 SpotifyService 已初始化
      if (!_isInitialized) {
        await _initSpotifyService();
        if (!_isInitialized) {
          throw SpotifyAuthException('SpotifyService 初始化失败');
        }
      }

      // 先尝试自动登录
      if (await autoLogin()) {
        print('自动登录成功');
        return;
      }

      print('自动登录失败，尝试重新获取令牌...');
      final result = await _spotifyService.login();
      if (result == null) {
        throw SpotifyAuthException('登录失败：无法获取访问令牌');
      }

      final userProfile = await _spotifyService.getUserProfile();
      username = userProfile['display_name'];
      
      print('登录成功，用户名：$username');
      
      // 启动定时刷新任务
      startTrackRefresh();
      
      // 登录后更新小部件
      await updateWidget();
      
    } catch (e) {
      print('登录失败: $e');
      username = null;
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (currentTrack == null) return;
    
    // 保存当前状态用于恢复
    final wasPlaying = currentTrack!['is_playing'] as bool;
    
    try {
      // 立即更新 UI 状态（乐观更新）
      currentTrack!['is_playing'] = !wasPlaying;
      notifyListeners();
      
      // 发送请求到服务器
      await _spotifyService.togglePlayPause();
      
      // 等待一小段时间后验证状态
      await Future.delayed(const Duration(milliseconds: 500));
      final newState = await _spotifyService.getCurrentlyPlayingTrack();
      
      // 如果服务器状态与本地不一致，更新为服务器状态
      if (newState != null && newState['is_playing'] != currentTrack!['is_playing']) {
        currentTrack = newState;
        notifyListeners();
      }
      
      // 播放状态改变时刷新队列
      await refreshPlaybackQueue();
      // 更新小部件
      await updateWidget();
    } catch (e) {
      print('播放/暂停切换失败: $e');
      // 发生错误时恢复到原始状态
      currentTrack!['is_playing'] = wasPlaying;
      notifyListeners();
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
      print('下一首失败: $e');
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
      print('上一首失败: $e');
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

    try {
      final trackId = currentTrack!['item']['id'];
      await _spotifyService.toggleTrackSave(trackId);
      
      // 添加延迟和验证
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 从服务器重新获取实际的收藏状态
      isCurrentTrackSaved = await _spotifyService.isTrackSaved(trackId);
      notifyListeners();
      
      // 如果状态改变，等待一段时间后再次验证
      await Future.delayed(const Duration(seconds: 2));
      final finalState = await _spotifyService.isTrackSaved(trackId);
      if (finalState != isCurrentTrackSaved) {
        isCurrentTrackSaved = finalState;
        notifyListeners();
      }
    } catch (e) {
      print('切换收藏状态失败: $e');
      // 发生错误时，重新检查状态
      final trackId = currentTrack?['item']?['id'];
      if (trackId != null) {
        isCurrentTrackSaved = await _spotifyService.isTrackSaved(trackId);
        notifyListeners();
      }
    }
  }

  List<Map<String, dynamic>> upcomingTracks = [];

  Future<void> refreshPlaybackQueue() async {
    try {
      final queue = await _spotifyService.getPlaybackQueue();
      final rawQueue = List<Map<String, dynamic>>.from(queue['queue'] ?? []);
      
      // 限制队列长度，例如最多10个
      upcomingTracks = rawQueue.take(10).toList();
      
      // 更安全地获取下一首歌曲
      nextTrack = upcomingTracks.isNotEmpty 
          ? upcomingTracks.first 
          : null;
      
      // 批量缓存所有队列图片
      await _cacheQueueImages();
      
      notifyListeners();
    } catch (e) {
      print('刷新播放队列失败: $e');
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
      print('批量缓存队列图片失败: $e');
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
      print('同步播放模式失败: $e');
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
      print('设置播放模式失败: $e');
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
      print('预加载图片失败: $e');
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
      final firestoreProvider = Provider.of<FirestoreProvider>(
        navigatorKey.currentContext!, 
        listen: false
      );
      
      for (var item in items) {
        final context = item['context'];
        if (context != null) {
          final uri = context['uri'] as String;
          final type = context['type'] as String;
          final trackId = item['track']?['id'];
          final playedAt = DateTime.parse(item['played_at']);
          
          // 保存播放上下文到 Firestore
          await firestoreProvider.savePlayContext(
            trackId: trackId,
            context: context,
            timestamp: playedAt,
          );
          
          // 处理播放列表
          if (type == 'playlist' && !playlistUris.contains(uri)) {
            playlistUris.add(uri);
            final playlistId = uri.split(':').last;
            try {
              final playlist = await _spotifyService.getPlaylist(playlistId);
              uniquePlaylists.add(playlist);
              if (uniquePlaylists.length >= 10) break;
            } catch (e) {
              print('获取播放列表 $playlistId 详情失败: $e');
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
              print('获取专辑 $albumId 详情失败: $e');
            }
          }
        }
      }
      
      _recentPlaylists..clear()..addAll(uniquePlaylists);
      _recentAlbums..clear()..addAll(uniqueAlbums);
      
      notifyListeners();
    } catch (e) {
      print('刷新最近播放记录失败: $e');
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
          print('更新 widget 失败: $e');
        }
      }

    } catch (e) {
      print('退出登录失败: $e');
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
        print('更新 widget 失败: $e');
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
      print('跳转播放位置失败: $e');
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
      print('播放 $type 失败: $e');
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
      print('播放歌曲失败: $e');
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
      print('在上下文中播放歌曲时出错: $e');
      rethrow;
    }
  }

  /// 设置播放音量
  Future<void> setVolume(int volumePercent, {String? deviceId}) async {
    try {
      final headers = await _spotifyService.getAuthenticatedHeaders();
      
      // 构建查询参数
      final queryParams = {
        'volume_percent': volumePercent.toString(),
        if (deviceId != null) 'device_id': deviceId,
      };
      
      final uri = Uri.https(
        'api.spotify.com',
        '/v1/me/player/volume',
        queryParams,
      );
      
      final response = await http.put(uri, headers: headers);

      if (response.statusCode != 202 && response.statusCode != 204) {
        throw SpotifyAuthException(
          '设置音量失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      print('设置音量时出错: $e');
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
        print('重新连接成功');
        // 连接成功后刷新状态
        await refreshCurrentTrack();
        await refreshAvailableDevices();
      } else {
        print('重新连接失败');
      }
    } catch (e) {
      print('重新连接时出错: $e');
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
            print('检测到连接断开，开始重连流程...');
            await _handleDisconnection();
          } else if (status.connected) {
            print('检测到连接成功，刷新播放状态...');
            // 连接成功时刷新播放状态
            await refreshCurrentTrack();
            await refreshAvailableDevices();
          }
        },
        onError: (e) {
          print('连接状态监听错误: $e');
          _handleDisconnection();
        },
      );
    } catch (e) {
      print('设置连接监听器失败: $e');
    }
  }
}