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
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kDefaultPadding,
          vertical: kSmallSpacing,
        ),
        width: double.infinity,
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
              const SpotifyCredentialsConfig(),
              const SizedBox(height: kSectionSpacing),
              const AppSettingsConfig(),
              const SizedBox(height: kSectionSpacing),
              const CacheManagementSection(),
              const SizedBox(height: kSectionSpacing),
              _buildSpotifyButton(context, spotifyProvider),
              if (spotifyProvider.username != null)
                Padding(
                  padding: const EdgeInsets.only(top: kSmallSpacing),
                  child: Text(
                    'Welcome, ${spotifyProvider.username}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: kElementSpacing),
              _buildGoogleButton(context, authProvider),
              if (authProvider.userDisplayName != null)
                Padding(
                  padding: const EdgeInsets.only(top: kSmallSpacing),
                  child: Text(
                    'Welcome, ${authProvider.userDisplayName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                // 底部添加额外的间距，确保内容不被系统导航栏遮挡
                SizedBox(height: MediaQuery.of(context).padding.bottom + kDefaultPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpotifyButton(BuildContext context, SpotifyProvider spotifyProvider) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
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
        minimumSize: const Size(double.infinity, 48),
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
                  'Spotify API Credentials',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
            const SizedBox(height: kSmallSpacing),
            TextField(
              controller: _clientIdController,
              enabled: _isEditing,
              decoration: _buildInputDecoration('Client ID'),
            ),
            const SizedBox(height: kSmallSpacing),
            TextField(
              controller: _clientSecretController,
              enabled: _isEditing,
              decoration: _buildInputDecoration('Client Secret'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: kElementSpacing),
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
                      
                      if (_clientIdController.text.length != 32 || 
                          !RegExp(r'^[0-9a-f]{32}$').hasMatch(_clientIdController.text)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Client ID should be a 32-character hex string')),
                        );
                        return;
                      }
                      
                      if (_clientSecretController.text.length != 32 || 
                          !RegExp(r'^[0-9a-f]{32}$').hasMatch(_clientSecretController.text)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Client Secret should be a 32-character hex string')),
                        );
                        return;
                      }
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saving credentials...')),
                      );
                      
                      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
                      await spotifyProvider.setClientCredentials(
                        _clientIdController.text,
                        _clientSecretController.text,
                      );
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Credentials saved. Please login to verify')),
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
            const SizedBox(height: kSmallSpacing),
            Text(
              'Get your credentials from the Spotify Developer Dashboard',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton(
              onPressed: () {
                launchUrl(Uri.parse('https://51notepage.craft.me/spotoolfy'));
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0),
              ),
              child: const Text('Tutorial'),
            ),
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

class AppSettingsConfig extends StatefulWidget {
  const AppSettingsConfig({super.key});

  @override
  State<AppSettingsConfig> createState() => _AppSettingsConfigState();
}

class _AppSettingsConfigState extends State<AppSettingsConfig> {
  final _settingsService = SettingsService();
  final _geminiApiKeyController = TextEditingController();
  String? _selectedLanguage;
  bool _isEditing = false;
  bool _isLoading = true;

  final Map<String, String> _languageOptions = {
    'en': 'English',
    'zh-CN': '简体中文 (Simplified Chinese)',
    'zh-TW': '繁體中文 (Traditional Chinese)',
    'ja': '日本語 (Japanese)',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() { _isLoading = true; });
    try {
      final settings = await _settingsService.getSettings();
      if (mounted) {
        setState(() {
          _geminiApiKeyController.text = settings['apiKey'] ?? '';
          if (settings['languageCode'] != null && 
              _languageOptions.containsKey(settings['languageCode'])) {
            _selectedLanguage = settings['languageCode'];
          } else {
            _selectedLanguage = 'en'; 
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading settings: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e')),
        );
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_geminiApiKeyController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Gemini API Key')),
      );
      return;
    }
    if (_selectedLanguage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target language')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving settings...')), 
    );

    try {
      await _settingsService.saveSettings(
        apiKey: _geminiApiKeyController.text,
        languageCode: _selectedLanguage,
      );
      if (mounted) {
         ScaffoldMessenger.of(context).removeCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
        setState(() {
          _isEditing = false;
        });
      }
    } catch (e) {
       print("Error saving settings: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _geminiApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
                  'App Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(_isEditing ? Icons.close : Icons.edit),
                  onPressed: () {
                    setState(() {
                      if (_isEditing) {
                        _loadSettings();
                      }
                      _isEditing = !_isEditing;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: kSmallSpacing),
            TextField(
              controller: _geminiApiKeyController,
              enabled: _isEditing,
              decoration: _buildInputDecoration('Gemini API Key', 'Enter your Gemini API Key'),
              obscureText: true,
            ),
            const SizedBox(height: kSmallSpacing),
            DropdownButtonFormField<String>(
              value: _selectedLanguage,
              items: _languageOptions.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: _isEditing ? (String? newValue) {
                setState(() {
                  _selectedLanguage = newValue;
                });
              } : null,
              decoration: _buildInputDecoration('Target Translation Language', null),
              disabledHint: Text(_selectedLanguage != null 
                ? _languageOptions[_selectedLanguage] ?? 'Select Language' 
                : 'Select Language'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: kElementSpacing),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: _saveSettings,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: kSmallSpacing),
            Text(
              'Configure your Gemini API Key and preferred translation language.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
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

class CacheManagementSection extends StatefulWidget {
  const CacheManagementSection({super.key});

  @override
  State<CacheManagementSection> createState() => _CacheManagementSectionState();
}

class _CacheManagementSectionState extends State<CacheManagementSection> {
  final LyricsService _lyricsService = LyricsService();
  final TranslationService _translationService = TranslationService();

  int _lyricsCacheSize = 0;
  int _translationCacheSize = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
  }

  Future<void> _loadCacheSizes() async {
    setState(() { _isLoading = true; });
    try {
      final lyricsSize = await _lyricsService.getCacheSize();
      final translationSize = await _translationService.getTranslationCacheSize();
      if (mounted) {
        setState(() {
          _lyricsCacheSize = lyricsSize;
          _translationCacheSize = translationSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading cache sizes: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading cache sizes: $e')),
        );
         setState(() { _isLoading = false; });
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
              'Cache Management',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
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
            ],
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
      padding: const EdgeInsets.all(kSmallSpacing),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$title: $size'),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}