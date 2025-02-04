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
      child: SingleChildScrollView(
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
            // Add Spotify Credentials Configuration
            const SpotifyCredentialsConfig(),
            const SizedBox(height: 24),
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
      ),
    );
  }
}

class SpotifyCredentialsConfig extends StatefulWidget {
  const SpotifyCredentialsConfig({super.key});

  @override
  State<SpotifyCredentialsConfig> createState() => _SpotifyCredentialsConfigState();
}

class _SpotifyCredentialsConfigState extends State<SpotifyCredentialsConfig> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final credentials = await spotifyProvider.getClientCredentials();
    
    setState(() {
      _clientIdController.text = credentials['clientId'] ?? '';
      _clientSecretController.text = credentials['clientSecret'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spotify API Credentials',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                icon: Icon(_isEditing ? Icons.close : Icons.edit),
                onPressed: () {
                  setState(() {
                    if (_isEditing) {
                      _loadCredentials();
                    }
                    _isEditing = !_isEditing;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clientIdController,
            enabled: _isEditing,
            decoration: InputDecoration(
              labelText: 'Client ID',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clientSecretController,
            enabled: _isEditing,
            decoration: InputDecoration(
              labelText: 'Client Secret',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () async {
                    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
                    await spotifyProvider.resetClientCredentials();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Credentials reset to default')),
                      );
                      setState(() {
                        _isEditing = false;
                      });
                      _loadCredentials();
                    }
                  },
                  child: const Text('Reset to Default'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (_clientIdController.text.isEmpty || _clientSecretController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill in both fields')),
                      );
                      return;
                    }
                    
                    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
                    await spotifyProvider.setClientCredentials(
                      _clientIdController.text,
                      _clientSecretController.text,
                    );
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Credentials saved')),
                      );
                      setState(() {
                        _isEditing = false;
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Get your credentials from the Spotify Developer Dashboard',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            onPressed: () {
              launchUrl(Uri.parse('https://51notepage.craft.me/spotoolfy'));
            },
            child: const Text('Tutorial'),
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