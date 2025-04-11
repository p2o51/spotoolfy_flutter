import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/settings_service.dart';
import '../services/lyrics_service.dart'; // Import LyricsService
import '../services/translation_service.dart'; // Import TranslationService
import 'dart:math' as math; // Import dart:math

// 定义统一的间距常量
const double kDefaultPadding = 16.0;
const double kSectionSpacing = 24.0;
const double kElementSpacing = 16.0;
const double kSmallSpacing = 8.0;

class Login extends StatelessWidget {
  const Login({super.key});

  @override
  Widget build(BuildContext context) {
    final spotifyProvider = Provider.of<SpotifyProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    
    // 设置edge to edge显示
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kDefaultPadding,
      ),
      width: double.infinity,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kDefaultPadding,
          bottom: MediaQuery.of(context).padding.bottom + kDefaultPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: kSmallSpacing),
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
            const SizedBox(height: kSectionSpacing),
            const CredentialsSection(),
            const SizedBox(height: kSectionSpacing),
            const AppSettingsSection(),
            const SizedBox(height: kSectionSpacing),
            Row(
              children: [
                Expanded(child: _buildSpotifyButton(context, spotifyProvider)),
                const SizedBox(width: kElementSpacing),
                Expanded(child: _buildGoogleButton(context, authProvider)),
              ],
            ),
            if (spotifyProvider.username != null || authProvider.userDisplayName != null)
              Padding(
                padding: const EdgeInsets.only(top: kElementSpacing),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (spotifyProvider.username != null)
                      Flexible(
                        child: Text(
                          'Spotify: ${spotifyProvider.username}',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (authProvider.userDisplayName != null)
                      Flexible(
                        child: Text(
                          'Google: ${authProvider.userDisplayName}',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpotifyButton(BuildContext context, SpotifyProvider spotifyProvider) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
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
                  String errorMessage = 'Operation failed';
                  
                  print('登录/注销操作失败: $e');
                  print('错误类型: ${e.runtimeType}');
                  
                  if (e.toString().contains('INVALID_CREDENTIALS')) {
                    errorMessage = 'Invalid Spotify API credentials. Please check your Client ID and Secret.';
                  } else if (e.toString().contains('401')) {
                    errorMessage = 'Authentication failed: Invalid credentials or insufficient permissions.';
                  } else if (e.toString().contains('429')) {
                    errorMessage = 'Too many requests. Please try again later.';
                  } else if (e.toString().contains('客户端 ID 或密钥无效')) {
                    errorMessage = 'Invalid Spotify API credentials. Please check your Client ID and Secret.';
                  } else {
                    errorMessage = 'Operation failed: $e';
                  }
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      duration: const Duration(seconds: 8),
                      action: SnackBarAction(
                        label: 'Help',
                        onPressed: () {
                          launchUrl(Uri.parse('https://51notepage.craft.me/spotoolfy'));
                        },
                      ),
                    ),
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
    );
  }

  Widget _buildGoogleButton(BuildContext context, AuthProvider authProvider) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
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
    );
  }
}

class CredentialsSection extends StatefulWidget {
  const CredentialsSection({super.key});

  @override
  State<CredentialsSection> createState() => _CredentialsSectionState();
}

class _CredentialsSectionState extends State<CredentialsSection> {
  final _spotifyClientIdController = TextEditingController();
  final _spotifyClientSecretController = TextEditingController();
  final _geminiApiKeyController = TextEditingController();

  final _settingsService = SettingsService();
  bool _isEditing = false;
  bool _isLoadingSpotify = true;
  bool _isLoadingGemini = true;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _spotifyClientIdController.dispose();
    _spotifyClientSecretController.dispose();
    _geminiApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    setState(() {
      _isLoadingSpotify = true;
      _isLoadingGemini = true;
    });
    await _loadSpotifyCredentials();
    await _loadGeminiKey();
    if (mounted) {
       setState(() {});
    }
  }

  Future<void> _loadSpotifyCredentials() async {
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    try {
      final credentials = await spotifyProvider.getClientCredentials();
      if (mounted) {
        setState(() {
          _spotifyClientIdController.text = credentials['clientId'] ?? '';
          _spotifyClientSecretController.text = credentials['clientSecret'] ?? '';
          _isLoadingSpotify = false;
        });
      }
    } catch (e) {
      print("Error loading Spotify credentials: $e");
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error loading Spotify credentials: $e')),
         );
         setState(() { _isLoadingSpotify = false; });
       }
    }
  }

 Future<void> _loadGeminiKey() async {
    try {
      final settings = await _settingsService.getSettings();
      if (mounted) {
        setState(() {
          _geminiApiKeyController.text = settings['apiKey'] ?? '';
          _isLoadingGemini = false;
        });
      }
    } catch (e) {
      print("Error loading Gemini API key: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading Gemini API key: $e')),
        );
        setState(() { _isLoadingGemini = false; });
      }
    }
  }

  Future<void> _saveCredentials() async {
     bool spotifySaved = false;
     bool geminiSaved = false;

     if (_spotifyClientIdController.text.isEmpty || _spotifyClientSecretController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Please fill in both Spotify fields')),
       );
       return;
     }
     if (_spotifyClientIdController.text.length != 32 ||
         !RegExp(r'^[0-9a-f]{32}$').hasMatch(_spotifyClientIdController.text)) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Spotify Client ID should be a 32-character hex string')),
       );
       return;
     }
     if (_spotifyClientSecretController.text.length != 32 ||
         !RegExp(r'^[0-9a-f]{32}$').hasMatch(_spotifyClientSecretController.text)) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Spotify Client Secret should be a 32-character hex string')),
       );
       return;
     }

     try {
       final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
       await spotifyProvider.setClientCredentials(
         _spotifyClientIdController.text,
         _spotifyClientSecretController.text,
       );
       spotifySaved = true;
     } catch (e) {
       print("Error saving Spotify credentials: $e");
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error saving Spotify credentials: $e')),
         );
       }
     }

     if (_geminiApiKeyController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Please enter a Gemini API Key')),
       );
       if (!spotifySaved) return;
     } else {
        try {
           final settings = await _settingsService.getSettings();
           String? currentLanguage = settings['languageCode'];

           await _settingsService.saveSettings(
             apiKey: _geminiApiKeyController.text,
             languageCode: currentLanguage,
           );
           geminiSaved = true;
         } catch (e) {
           print("Error saving Gemini API key: $e");
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Error saving Gemini API key: $e')),
             );
           }
         }
     }

     if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
       if (spotifySaved && geminiSaved) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Credentials saved successfully. Please re-login if needed.')),
         );
         setState(() { _isEditing = false; });
       } else if (spotifySaved) {
           ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Spotify credentials saved. Gemini key failed.')),
         );
          setState(() { _isEditing = false; });
       } else if (geminiSaved) {
           ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Gemini API key saved. Spotify credentials failed.')),
         );
          setState(() { _isEditing = false; });
       } else {
       }
     }
  }

   Future<void> _resetSpotifyCredentials() async {
     final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
     await spotifyProvider.resetClientCredentials();
     if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Spotify Credentials reset to default')),
       );
       await _loadSpotifyCredentials();
       setState(() {});
     }
   }

  @override
  Widget build(BuildContext context) {
     if (_isLoadingSpotify || _isLoadingGemini) {
       return const Center(child: CircularProgressIndicator());
     }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kDefaultPadding),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kDefaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Credentials',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        launchUrl(Uri.parse('https://51notepage.craft.me/spotoolfy'));
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: kSmallSpacing),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Tutorial'),
                    ),
                    IconButton(
                      icon: Icon(_isEditing ? Icons.close : Icons.edit),
                      tooltip: _isEditing ? 'Cancel' : 'Edit Credentials',
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
              ],
            ),
            const SizedBox(height: kSmallSpacing),
            Text(
              'Spotify API',
              style: Theme.of(context).textTheme.titleSmall,
            ),
             const SizedBox(height: kSmallSpacing / 2),
            TextField(
              controller: _spotifyClientIdController,
              enabled: _isEditing,
              decoration: _buildInputDecoration('Client ID'),
            ),
            const SizedBox(height: kSmallSpacing),
            TextField(
              controller: _spotifyClientSecretController,
              enabled: _isEditing,
              obscureText: true,
              decoration: _buildInputDecoration('Client Secret'),
            ),
             if (_isEditing)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _resetSpotifyCredentials,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text('Reset Spotify to Default', style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
            const SizedBox(height: kElementSpacing),

            Text(
              'Google AI (Gemini)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: kSmallSpacing / 2),
            TextField(
              controller: _geminiApiKeyController,
              enabled: _isEditing,
              decoration: _buildInputDecoration('Gemini API Key'),
              obscureText: true,
            ),
             const SizedBox(height: kSmallSpacing),
             Text(
              'Needed for lyrics translation.',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            if (_isEditing) ...[
              const SizedBox(height: kElementSpacing),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saving credentials...')),
                      );
                      _saveCredentials();
                    },
                    child: const Text('Save All Credentials'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
    );
  }
}

class AppSettingsSection extends StatefulWidget {
  const AppSettingsSection({super.key});

  @override
  State<AppSettingsSection> createState() => _AppSettingsSectionState();
}

class _AppSettingsSectionState extends State<AppSettingsSection> {
  final _settingsService = SettingsService();
  final LyricsService _lyricsService = LyricsService();
  final TranslationService _translationService = TranslationService();

  String? _selectedLanguage;
  int _lyricsCacheSize = 0;
  int _translationCacheSize = 0;

  bool _isLoadingSettings = true;
  bool _isLoadingCache = true;

  final Map<String, String> _languageOptions = {
    'en': 'English',
    'zh-CN': '简体中文 (Simplified Chinese)',
    'zh-TW': '繁體中文 (Traditional Chinese)',
    'ja': '日本語 (Japanese)',
  };

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
     setState(() {
       _isLoadingSettings = true;
       _isLoadingCache = true;
      });
    await _loadLanguageSetting();
    await _loadCacheSizes();
    if (mounted) {
       setState(() {});
    }
  }

  Future<void> _loadLanguageSetting() async {
    try {
      final settings = await _settingsService.getSettings();
      if (mounted) {
        setState(() {
          if (settings['languageCode'] != null &&
              _languageOptions.containsKey(settings['languageCode'])) {
            _selectedLanguage = settings['languageCode'];
          } else {
            _selectedLanguage = 'en';
          }
          _isLoadingSettings = false;
        });
      }
    } catch (e) {
      print("Error loading language setting: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading language setting: $e')),
        );
        setState(() { _isLoadingSettings = false; });
      }
    }
  }

  Future<void> _saveLanguageSetting() async {
    try {
      final settings = await _settingsService.getSettings();
      String? currentApiKey = settings['apiKey'];

      await _settingsService.saveSettings(
        apiKey: currentApiKey,
        languageCode: _selectedLanguage,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Language setting saved')),
        );
      }
    } catch (e) {
      print("Error saving language setting: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving language setting: $e')),
        );
      }
    }
  }

  Future<void> _loadCacheSizes() async {
    try {
      final lyricsSize = await _lyricsService.getCacheSize();
      final translationSize = await _translationService.getTranslationCacheSize();
      if (mounted) {
        setState(() {
          _lyricsCacheSize = lyricsSize;
          _translationCacheSize = translationSize;
          _isLoadingCache = false;
        });
      }
    } catch (e) {
      print("Error loading cache sizes: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading cache sizes: $e')),
        );
         setState(() { _isLoadingCache = false; });
      }
    }
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    var i = (bytes == 0) ? 0 : (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _clearLyricsCache() async {
    await _lyricsService.clearCache();
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lyrics cache cleared')),
      );
      _loadCacheSizes();
    }
  }

   Future<void> _clearTranslationCache() async {
    await _translationService.clearTranslationCache();
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Translation cache cleared')),
      );
      _loadCacheSizes();
    }
  }

  @override
  Widget build(BuildContext context) {
     if (_isLoadingSettings || _isLoadingCache) {
       return const Center(child: CircularProgressIndicator());
     }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kDefaultPadding),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kDefaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(
              'App Settings',
               style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),

            Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Text(
                  'Translation',
                  style: Theme.of(context).textTheme.titleSmall,
                 ),
               ],
             ),
            const SizedBox(height: kSmallSpacing / 2),
            DropdownButtonFormField<String>(
              value: _selectedLanguage,
              items: _languageOptions.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null && newValue != _selectedLanguage) {
                  setState(() {
                    _selectedLanguage = newValue;
                  });
                  _saveLanguageSetting();
                }
              },
              decoration: _buildInputDecoration('Target Language', null),
            ),
            const SizedBox(height: kSmallSpacing),
            Text(
              'Preferred language for lyrics translation.',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: kElementSpacing),

            Text(
              'Cache Management',
               style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: kSmallSpacing / 2),
            _buildCacheItem(
              'Lyrics Cache',
              _formatBytes(_lyricsCacheSize),
              _clearLyricsCache,
            ),
            const SizedBox(height: kSmallSpacing),
            _buildCacheItem(
              'Translation Cache',
              _formatBytes(_translationCacheSize),
              _clearTranslationCache,
            ),
            const SizedBox(height: kSmallSpacing),
             Text(
              'Clear cached data to free up space or resolve issues.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheItem(String title, String size, VoidCallback onClear) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSmallSpacing, vertical: kSmallSpacing / 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$title: $size', style: Theme.of(context).textTheme.bodyMedium),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

   InputDecoration _buildInputDecoration(String label, String? hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
    );
  }
}