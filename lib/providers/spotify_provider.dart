import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import '../services/spotify_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';


enum PlayMode {
  singleRepeat,    // 单曲循环（曲循环+顺序播放）
  sequential,      // 顺序播放（列表循环+顺序播放）
  shuffle          // 随机播放（列表循环+随机播放）
}

class SpotifyProvider extends ChangeNotifier {
  final SpotifyAuthService _spotifyService;

  String? username;
  Map<String, dynamic>? currentTrack;
  bool? isCurrentTrackSaved;
  Timer? _refreshTimer;
  bool isLoading = false;
  Map<String, dynamic>? previousTrack;
  Map<String, dynamic>? nextTrack;
  PlayMode _currentMode = PlayMode.sequential;
  PlayMode get currentMode => _currentMode;
  bool _isSkipping = false;

  // 添加图片预加载缓存
  final Map<String, String> _imageCache = {};
  
  SpotifyProvider() : _spotifyService = SpotifyAuthService(
    clientId: '64103961829a42328a6634fb80574191',
    clientSecret: '2d1ae3a42dc94650887f4c73ab6926d1',
    redirectUrl: kIsWeb 
        ? 'http://localhost:8080/spotify_callback.html'
        : 'spotoolfy://callback',
  );

  void startTrackRefresh() {
    _refreshTimer?.cancel();
    
    if (username != null) {
      refreshCurrentTrack();
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        // 如果正在切换歌曲，跳过这次刷新
        if (!_isSkipping) {
          refreshCurrentTrack();
        }
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshCurrentTrack() async {
    if (_isSkipping) return;  // 如果正在切歌，跳过刷新
    
    try {
      final track = await _spotifyService.getCurrentlyPlayingTrack();
      if (track != null) {
        currentTrack = track;
        notifyListeners();
        await checkCurrentTrackSaveState();
        await refreshPlaybackQueue();
      }
    } catch (e) {
      print('刷新播放状态失败: $e');
    }
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

  Future<void> login() async {
    try {
      isLoading = true;
      notifyListeners();

      final result = await _spotifyService.login();
      final userProfile = await _spotifyService.getUserProfile();
      username = userProfile['display_name'];
      
      startTrackRefresh();
      
    } catch (e) {
      print('登录失败: $e');
      username = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    try {
      await _spotifyService.togglePlayPause();
      await refreshCurrentTrack();
      await refreshPlaybackQueue();
    } catch (e) {
      print('播放/暂停切换失败: $e');
    }
  }

  Future<void> skipToNext() async {
    if (_isSkipping) return;
    
    try {
      _isSkipping = true;
      
      // 保存当前歌曲作为上一首
      previousTrack = currentTrack?['item'];
      
      // 如果已经有下一首的信息，先更新UI
      if (nextTrack != null) {
        final tempTrack = currentTrack;
        currentTrack = {'item': nextTrack, 'is_playing': true};
        notifyListeners();
      }
      
      // 执行切歌操作
      await _spotifyService.skipToNext();
      final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
      
      if (newTrack != null) {
        currentTrack = newTrack;
        notifyListeners();
      }
      
      // 刷新并预加载新的队列
      await refreshPlaybackQueue();
      
    } catch (e) {
      print('下一首失败: $e');
      // 如果失败，恢复到原来的状态
      currentTrack = {'item': previousTrack};
      notifyListeners();
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
      
      // 如果已经有上一首的信息，先更新UI
      if (previousTrack != null) {
        currentTrack = {'item': previousTrack, 'is_playing': true};
        notifyListeners();
      }
      
      // 执行切歌操作
      await _spotifyService.skipToPrevious();
      final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
      
      if (newTrack != null) {
        currentTrack = newTrack;
        notifyListeners();
      }
      
      // 刷新并预加载新的队列
      await refreshPlaybackQueue();
      
    } catch (e) {
      print('上一首失败: $e');
      // 如果失败，恢复到原来的状态
      currentTrack = {'item': nextTrack};
      notifyListeners();
    } finally {
      _isSkipping = false;
    }
  }

  Future<void> toggleTrackSave() async {
    if (currentTrack == null || currentTrack!['item'] == null) return;

    try {
      final trackId = currentTrack!['item']['id'];
      isCurrentTrackSaved = await _spotifyService.toggleTrackSave(trackId);
      notifyListeners();
    } catch (e) {
      print('切换收藏状态失败: $e');
    }
  }

  Future<void> refreshPlaybackQueue() async {
    try {
      final queue = await _spotifyService.getPlaybackQueue();
      nextTrack = queue['queue'].isNotEmpty ? queue['queue'][0] : null;
      // 获取队列后立即预加载图片
      await _preloadQueueImages();
      notifyListeners();
    } catch (e) {
      print('刷新播放队列失败: $e');
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

  // 预加载队列中的歌曲图片
  Future<void> _preloadQueueImages() async {
    if (nextTrack != null) {
      final nextImageUrl = nextTrack!['album']?['images']?[0]?['url'];
      await _preloadImage(nextImageUrl);
    }
    if (previousTrack != null) {
      final prevImageUrl = previousTrack!['album']?['images']?[0]?['url'];
      await _preloadImage(prevImageUrl);
    }
  }
}
