import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      final Uri emailLaunchUri = Uri(
                        scheme: 'mailto',
                        path: 'lastnatsu51@gmail.com',
                      );
                      launchUrl(emailLaunchUri);
                    },
                    icon: const Icon(Icons.email),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Welcome(),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Traditional Chinese Lyrics'),
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '測試',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: spotifyProvider.useTraditionalChinese,
                  onChanged: (value) {
                    spotifyProvider.toggleTraditionalChinese();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                          const SnackBar(content: Text('Logged out from Spotify')),
                        );
                      }
                    } else {
                      await spotifyProvider.login();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged in with Spotify')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Operation failed: $e')),
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
                'Welcome, ${spotifyProvider.username}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          
          
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
                          const SnackBar(content: Text('Logged out from Google')),
                        );
                      }
                    } else {
                      final credential = await authProvider.signInWithGoogle();
                      if (context.mounted && credential != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged in with Google')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Operation failed: $e')),
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
                'Welcome, ${authProvider.userDisplayName}',
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