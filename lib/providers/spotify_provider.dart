import 'package:flutter/foundation.dart';
import 'dart:async';
import '../services/spotify_service.dart';

class SpotifyProvider extends ChangeNotifier {
  final SpotifyAuthService _spotifyService;
  String? username;
  Map<String, dynamic>? currentTrack;
  bool? isCurrentTrackSaved;
  Timer? _refreshTimer;
  bool isLoading = false;

  SpotifyProvider() : _spotifyService = SpotifyAuthService(
    clientId: '64103961829a42328a6634fb80574191',
    clientSecret: '2d1ae3a42dc94650887f4c73ab6926d1',
    redirectUrl: 'spotoolfy://callback',
  );

  void startTrackRefresh() {
    _refreshTimer?.cancel();
    
    if (username != null) {
      refreshCurrentTrack();
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        refreshCurrentTrack();
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshCurrentTrack() async {
    try {
      final track = await _spotifyService.getCurrentlyPlayingTrack();
      currentTrack = track;
      notifyListeners();
      await checkCurrentTrackSaveState();
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
    } catch (e) {
      print('播放/暂停切换失败: $e');
    }
  }

  Future<void> skipToNext() async {
    try {
      await _spotifyService.skipToNext();
      await refreshCurrentTrack();
    } catch (e) {
      print('下一首失败: $e');
    }
  }

  Future<void> skipToPrevious() async {
    try {
      await _spotifyService.skipToPrevious();
      await refreshCurrentTrack();
    } catch (e) {
      print('上一首失败: $e');
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
}
