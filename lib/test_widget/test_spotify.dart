import 'package:flutter/material.dart';
import 'dart:async';
import '../services/spotify_service.dart';

class TestSpotify extends StatefulWidget {
  const TestSpotify({super.key});

  @override
  State<TestSpotify> createState() => _TestSpotifyState();
}

class _TestSpotifyState extends State<TestSpotify> {
  final spotifyAuthService = SpotifyAuthService(
    clientId: '64103961829a42328a6634fb80574191',
    clientSecret: '2d1ae3a42dc94650887f4c73ab6926d1',
    redirectUrl: 'spotoolfy://callback',
  );

  String? username;
  bool isLoading = false;
  Map<String, dynamic>? currentTrack;
  Timer? _refreshTimer;
  bool? isCurrentTrackSaved;

  @override
  void initState() {
    super.initState();
    _startTrackRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startTrackRefresh() {
    _refreshTimer?.cancel();
    
    if (username != null) {
      _refreshCurrentTrack();
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _refreshCurrentTrack();
      });
    }
  }

  Future<void> _refreshCurrentTrack() async {
    try {
      final track = await spotifyAuthService.getCurrentlyPlayingTrack();
      if (mounted) {
        setState(() {
          currentTrack = track;
        });
        await _checkCurrentTrackSaveState();
      }
    } catch (e) {
      print('刷新播放状态失败: $e');
    }
  }

  Future<void> _checkCurrentTrackSaveState() async {
    if (currentTrack == null || currentTrack!['item'] == null) {
      setState(() {
        isCurrentTrackSaved = null;
      });
      return;
    }

    try {
      final trackId = currentTrack!['item']['id'];
      final isSaved = await spotifyAuthService.isTrackSaved(trackId);
      if (mounted) {
        setState(() {
          isCurrentTrackSaved = isSaved;
        });
      }
    } catch (e) {
      print('检查歌曲保存状态失败: $e');
    }
  }

  Future<void> _toggleTrackSave() async {
    if (currentTrack == null || currentTrack!['item'] == null) return;

    try {
      final trackId = currentTrack!['item']['id'];
      final newSaveState = await spotifyAuthService.toggleTrackSave(trackId);
      
      if (mounted) {
        setState(() {
          isCurrentTrackSaved = newSaveState;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newSaveState ? '已添加到我的音乐库' : '已从我的音乐库中移除'
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (username != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '欢迎, $username!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        if (username != null && currentTrack != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  '当前播放',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (currentTrack!['item']?['album']?['images'] != null &&
                    (currentTrack!['item']['album']['images'] as List).isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.network(
                      currentTrack!['item']['album']['images'][0]['url'],
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return SizedBox(
                          width: 200,
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey[300],
                          child: const Icon(
                            Icons.music_note,
                            size: 50,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            currentTrack!['item']['name'] ?? '未知歌曲',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            (currentTrack!['item']['artists'] as List)
                                .map((artist) => artist['name'])
                                .join(', '),
                            style: Theme.of(context).textTheme.titleSmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    if (isCurrentTrackSaved != null)
                      IconButton(
                        icon: Icon(
                          isCurrentTrackSaved! 
                              ? Icons.favorite 
                              : Icons.favorite_border,
                          color: isCurrentTrackSaved! 
                              ? Colors.red 
                              : null,
                        ),
                        onPressed: _toggleTrackSave,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  currentTrack!['is_playing'] ? '正在播放' : '已暂停',
                  style: TextStyle(
                    color: currentTrack!['is_playing'] 
                        ? Colors.green 
                        : Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 32,
                      onPressed: () async {
                        try {
                          await spotifyAuthService.skipToPrevious();
                          await _refreshCurrentTrack();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('上一首失败: $e')),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        currentTrack!['is_playing'] 
                            ? Icons.pause_circle_filled 
                            : Icons.play_circle_filled,
                      ),
                      iconSize: 48,
                      onPressed: () async {
                        try {
                          await spotifyAuthService.togglePlayPause();
                          await _refreshCurrentTrack();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('播放/暂停切换失败: $e')),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 32,
                      onPressed: () async {
                        try {
                          await spotifyAuthService.skipToNext();
                          await _refreshCurrentTrack();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('下一首失败: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ElevatedButton(
          onPressed: isLoading ? null : _handleLogin,
          child: isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Text(username == null ? '用 Spotify 登录' : '重新登录'),
        ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    try {
      setState(() {
        isLoading = true;
      });

      print('开始登录流程...');
      print('使用的配置：');
      print('clientId: ${spotifyAuthService.clientId}');
      print('redirectUrl: ${spotifyAuthService.redirectUrl}');

      final result = await spotifyAuthService.login();
      print('登录结果: $result');

      // 获取用户信息
      final userProfile = await spotifyAuthService.getUserProfile();
      print('用户信息:');
      print('- 用户名: ${userProfile['display_name']}');
      print('- 邮箱: ${userProfile['email']}');
      print('- ID: ${userProfile['id']}');

      if (mounted) {
        setState(() {
          username = userProfile['display_name'];
        });
        
        _startTrackRefresh();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录成功！'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('操作失败');
      print('错误类型: ${e.runtimeType}');
      print('错误信息: $e');
      print('堆栈跟踪:');
      print(stackTrace);

      if (mounted) {
        setState(() {
          username = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('操作失败'),
                Text('错误类型: ${e.runtimeType}'),
                Text('错误信息: $e'),
              ],
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }
}