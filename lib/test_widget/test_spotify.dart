import 'package:flutter/material.dart';
import '../services/spotify_service.dart';

class TestSpotify extends StatefulWidget {
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