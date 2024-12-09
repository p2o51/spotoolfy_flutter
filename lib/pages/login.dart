import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/auth_provider.dart';

class Login extends StatelessWidget {
  const Login({super.key});

  @override
  Widget build(BuildContext context) {
    final spotifyProvider = Provider.of<SpotifyProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close),
          ),
          const Welcome(),
          const SizedBox(height: 40),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: spotifyProvider.username != null 
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
            onPressed: spotifyProvider.isLoading
              ? null 
              : () async {
                  try {
                    if (spotifyProvider.username != null) {
                      await spotifyProvider.logout();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已退出 Spotify')),
                        );
                      }
                    } else {
                      await spotifyProvider.login();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Spotify 登录成功！')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('操作失败: $e')),
                      );
                    }
                  }
                },
            child: spotifyProvider.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(spotifyProvider.username != null 
                  ? 'Logout from Spotify' 
                  : 'Authorize Spotify'),
          ),
          if (spotifyProvider.username != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '欢迎你，${spotifyProvider.username}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          const Text('and',
            style: TextStyle(
              fontFamily: 'Derivia',
              fontSize: 64,
              height: 0.9,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: authProvider.isSignedIn 
                  ? Theme.of(context).colorScheme.errorContainer 
                  : null,
            ),
            onPressed: authProvider.isLoading
              ? null
              : () async {
                  try {
                    if (authProvider.isSignedIn) {
                      await authProvider.signOut();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已退出 Google 账号')),
                        );
                      }
                    } else {
                      final credential = await authProvider.signInWithGoogle();
                      if (context.mounted && credential != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Google 登录成功！')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('操作失败: $e')),
                      );
                    }
                  }
                },
            child: authProvider.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(authProvider.isSignedIn 
                  ? 'Logout from Google' 
                  : 'Login with Google'),
          ),
          if (authProvider.userDisplayName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '欢迎你，${authProvider.userDisplayName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text('Kisses',
          style: TextStyle(
            fontFamily: 'Derivia',
            fontSize: 96,
            height: 0.9,
          ),
        ),
        Text('for',
          style: TextStyle(
            fontFamily: 'Derivia',
            fontSize: 64,
            height: 0.9,
          ),
        ),
        Text('Music.',
          style: TextStyle(
            fontFamily: 'Derivia',
            fontSize: 112,
            height: 0.9,
          ),
        ),
      ],
    );
  }
}