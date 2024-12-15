import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import '../services/spotify_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../providers/firestore_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';


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
  Timer? _progressTimer;
  DateTime? _lastProgressUpdate;
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
    _progressTimer?.cancel();
    
    if (username != null) {
      refreshCurrentTrack();
      
      // API 刷新计时器 - 每5秒从服务器获取一次
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_isSkipping) {
          refreshCurrentTrack();
        }
      });
      
      // 本地进度计时器 - 每100毫秒更新一次
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
      final track = await _spotifyService.getCurrentlyPlayingTrack();
      if (track != null) {
        final newId = track['item']?['id'];
        final oldId = currentTrack?['item']?['id'];
        final isPlaying = track['is_playing'];
        final oldIsPlaying = currentTrack?['is_playing'];
        final progress = track['progress_ms'];

        // 检查是否需要更新状态
        if (currentTrack == null || 
            newId != oldId || 
            isPlaying != oldIsPlaying) {
          
          // 重置进度更新时间
          _lastProgressUpdate = DateTime.now();
          
          // 只有在歌曲ID改变时才刷新播放队列
          if (currentTrack == null || newId != oldId) {
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
          }

          previousTrack = currentTrack;
          currentTrack = track;
          
          if (track['item'] != null) {
            isCurrentTrackSaved = await _spotifyService.isTrackSaved(track['item']['id']);
          }
          
          // 更新小部件
          await updateWidget();
          
          notifyListeners();
        } else {
          // 即使只是进度变化，也更新服务器的进度值
          currentTrack!['progress_ms'] = progress;
        }
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

  Future<void> login() async {
    try {
      isLoading = true;
      notifyListeners();

      final result = await _spotifyService.login();
      final userProfile = await _spotifyService.getUserProfile();
      username = userProfile['display_name'];
      
      startTrackRefresh();
      
      // 登录后更新小部件
      await updateWidget();
      
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
      // 更新小部件
      await updateWidget();
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
      
      // 预先准备下一首歌的信息
      final targetTrack = nextTrack;
      
      // 执行切歌操作，但不立即更新UI
      await _spotifyService.skipToNext();
      
      // 等待一小段时间确保 Spotify 已经切换
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 获取实际的新曲目信息
      final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
      
      // 只在确认切歌成功后更新一次UI
      if (newTrack != null) {
        currentTrack = newTrack;
        // 更新小部件
        await updateWidget();
        notifyListeners();
        
        // 如果新曲目与预期的下一首不同，更新队列
        if (targetTrack != null && newTrack['item']?['id'] != targetTrack['id']) {
          await refreshPlaybackQueue();
        }
      }
      
    } catch (e) {
      print('下一首失败: $e');
      // 如果失败，恢复到原来的状态
      if (previousTrack != null) {
        currentTrack = {'item': previousTrack, 'is_playing': true};
        // 更新小部件
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
      
      // 如果已经有上一首的信息，先更新UI
      if (previousTrack != null) {
        currentTrack = {'item': previousTrack, 'is_playing': true};
        // 更新小部件
        await updateWidget();
        notifyListeners();
      }
      
      // 执行切歌操作
      await _spotifyService.skipToPrevious();
      final newTrack = await _spotifyService.getCurrentlyPlayingTrack();
      
      if (newTrack != null) {
        currentTrack = newTrack;
        // 更新小部件
        await updateWidget();
        notifyListeners();
      }
      
      // 刷新并预加载新的队列
      await refreshPlaybackQueue();
      
    } catch (e) {
      print('上一首失败: $e');
      // 如果失败，恢复到原来的状态
      currentTrack = {'item': nextTrack};
      // 更新小部件
      await updateWidget();
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

  // 添加自动登录检查
  Future<bool> autoLogin() async {
    try {
      isLoading = true;
      notifyListeners();

      // 检查是否有有效的 token
      if (await _spotifyService.isAuthenticated()) {
        final userProfile = await _spotifyService.getUserProfile();
        username = userProfile['display_name'];
        startTrackRefresh();
        return true;
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
}