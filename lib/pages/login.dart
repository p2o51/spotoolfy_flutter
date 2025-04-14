import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/local_database_provider.dart'; // Import LocalDatabaseProvider
import 'package:url_launcher/url_launcher.dart';
import '../services/settings_service.dart';
import '../services/lyrics_service.dart'; // Import LyricsService
import '../services/translation_service.dart'; // Import TranslationService
import '../services/notification_service.dart'; // Import NotificationService
import 'dart:math' as math; // Import dart:math
import 'package:logger/logger.dart'; // Import logger

// 定义统一的间距常量
const double kDefaultPadding = 16.0;
const double kSectionSpacing = 24.0;
const double kElementSpacing = 16.0;
const double kSmallSpacing = 8.0;

// Add a logger instance
final logger = Logger();

class Login extends StatelessWidget {
  const Login({super.key});

  @override
  Widget build(BuildContext context) {
    final spotifyProvider = Provider.of<SpotifyProvider>(context);
    
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
            const SettingsMenuSection(),
            const SizedBox(height: kSectionSpacing),
            Row(
              children: [
                Expanded(child: _buildSpotifyButton(context, spotifyProvider)),
              ],
            ),
            if (spotifyProvider.username != null)
              Padding(
                padding: const EdgeInsets.only(top: kElementSpacing),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (spotifyProvider.username != null)
                      Flexible(
                        child: Text(
                          'Spotify: ${spotifyProvider.username}',
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
    final notificationService = Provider.of<NotificationService>(context, listen: false);

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
                  HapticFeedback.lightImpact();
                  notificationService.showSuccessSnackBar('Logged out from Spotify');
                } else {
                  await spotifyProvider.login();
                  HapticFeedback.lightImpact();
                  notificationService.showSuccessSnackBar('Logged in with Spotify');
                  if (context.mounted) Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  String errorMessage = 'Operation failed';
                  
                  logger.e('登录/注销操作失败: $e');
                  logger.e('错误类型: ${e.runtimeType}');
                  
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
                  
                  notificationService.showErrorSnackBar(
                    errorMessage,
                    actionLabel: 'Help',
                    onActionPressed: () {
                      launchUrl(Uri.parse('https://51notepage.craft.me/spotoolfy'));
                    },
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
}

class SettingsMenuSection extends StatelessWidget {
  const SettingsMenuSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kDefaultPadding),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kDefaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 凭据设置部分
            Text(
              'Setup',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.vpn_key,
              title: 'Google AI API key',
              subtitle: 'Set up your Google AI Studio API key for Gemini translation',
              onTap: () => _showGeminiApiKeyDialog(context),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.api,
              title: 'Spotify API',
              subtitle: 'Set Spotify Client ID and Secret',
              onTap: () => _showSpotifyCredentialsDialog(context),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.help_outline,
              title: 'Tutorial',
              subtitle: 'See tutorial for setting up',
              onTap: () => launchUrl(Uri.parse('https://51notepage.craft.me/spotoolfy')),
            ),
            const SizedBox(height: kSectionSpacing),
            
            // 常规设置部分
            Text(
              'General',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.language,
              title: 'Translation Language',
              subtitle: 'Choose the target language for translations',
              onTap: () => _showLanguageSelectionDialog(context),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.style,
              title: 'Translation Style',
              subtitle: 'Set Gemini\'s Spirit',
              onTap: () => _showTranslationStyleDialog(context),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSwitchMenuItem(
              context,
              icon: Icons.text_format,
              title: 'Copy lyrics as single line',
              subtitle: 'Replaces line breaks with spaces when copying',
            ),
            const SizedBox(height: kSectionSpacing),
            
            // 数据管理部分
            Text(
              'Data Management',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.upload_file,
              title: 'Export Data',
              subtitle: 'Export all data as JSON file',
              onTap: () => _handleExport(context),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.download,
              title: 'Import Data',
              subtitle: 'Import data from exported JSON file',
              onTap: () => _handleImport(context),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.cleaning_services,
              title: 'Clear All Cache',
              subtitle: 'Clear lyrics and translation cache',
              onTap: () => _showClearCacheConfirmation(context),
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(kSmallSpacing),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDestructive 
                  ? Theme.of(context).colorScheme.error.withOpacity(0.1)
                  : Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isDestructive 
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: kElementSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDestructive 
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final _settingsService = SettingsService();
    return StatefulBuilder(
      builder: (context, setState) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _settingsService.getSettings(),
          builder: (context, snapshot) {
            bool copyAsSingleLine = false;
            if (snapshot.hasData) {
              copyAsSingleLine = snapshot.data!['copyLyricsAsSingleLine'] as bool? ?? false;
            }
            
            return InkWell(
              onTap: () {
                if (snapshot.hasData) {
                  HapticFeedback.lightImpact();
                  final newValue = !copyAsSingleLine;
                  _settingsService.saveCopyLyricsAsSingleLine(newValue);
                  setState(() {});
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(kSmallSpacing),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: kElementSpacing),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: copyAsSingleLine,
                      onChanged: (bool value) {
                        HapticFeedback.lightImpact();
                        _settingsService.saveCopyLyricsAsSingleLine(value);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _showGeminiApiKeyDialog(BuildContext context) async {
    final _settingsService = SettingsService();
    final settings = await _settingsService.getSettings();
    final currentApiKey = settings['apiKey'] as String? ?? '';
    
    final TextEditingController _apiKeyController = TextEditingController(text: currentApiKey);

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Gemini API key'),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
            child: TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: '输入你的Gemini API密钥',
              ),
              obscureText: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final newApiKey = _apiKeyController.text.trim();
                if (newApiKey.isNotEmpty) {
                  await _settingsService.saveSettings(
                    apiKey: newApiKey,
                    languageCode: settings['languageCode'] as String?,
                    style: settings['style'] as TranslationStyle?,
                  );
                  
                  if (context.mounted) {
                    Provider.of<NotificationService>(context, listen: false)
                        .showSuccessSnackBar('Gemini API key saved');
                    Navigator.of(context).pop();
                  }
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSpotifyCredentialsDialog(BuildContext context) async {
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final credentials = await spotifyProvider.getClientCredentials();
    
    final TextEditingController _clientIdController = TextEditingController(text: credentials['clientId'] ?? '');
    final TextEditingController _clientSecretController = TextEditingController(text: credentials['clientSecret'] ?? '');

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Spotify API'),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _clientIdController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    labelText: 'Client ID',
                  ),
                ),
                const SizedBox(height: kSmallSpacing),
                TextField(
                  controller: _clientSecretController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    labelText: 'Client Secret',
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final clientId = _clientIdController.text.trim();
                final clientSecret = _clientSecretController.text.trim();
                
                String? errorMessage;
                
                if (clientId.isEmpty || clientSecret.isEmpty) {
                  errorMessage = 'Both Client ID and Secret are required.';
                } else if (clientId.length != 32 || !RegExp(r'^[0-9a-f]{32}$').hasMatch(clientId)) {
                  errorMessage = 'Client ID must be a 32-character hex string.';
                } else if (clientSecret.length != 32 || !RegExp(r'^[0-9a-f]{32}$').hasMatch(clientSecret)) {
                  errorMessage = 'Client Secret must be a 32-character hex string.';
                }
                
                if (errorMessage != null) {
                  if (context.mounted) {
                    Provider.of<NotificationService>(context, listen: false)
                        .showErrorSnackBar(errorMessage);
                  }
                  return;
                }
                
                try {
                  await spotifyProvider.setClientCredentials(clientId, clientSecret);
                  if (context.mounted) {
                    Provider.of<NotificationService>(context, listen: false)
                        .showSuccessSnackBar('Spotify credentials saved');
                    Navigator.of(context).pop();
                  }
                } catch (e) {
                  if (context.mounted) {
                    Provider.of<NotificationService>(context, listen: false)
                        .showErrorSnackBar('Failed to save: $e');
                  }
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLanguageSelectionDialog(BuildContext context) async {
    final _settingsService = SettingsService();
    final settings = await _settingsService.getSettings();
    String selectedLanguage = settings['languageCode'] as String? ?? 'en';
    
    final Map<String, String> languageOptions = {
      'en': 'English',
      'zh-CN': '简体中文 (Simplified Chinese)',
      'zh-TW': '繁體中文 (Traditional Chinese)',
      'ja': '日本語 (Japanese)',
    };

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select Language'),
              content: SizedBox(
                width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: languageOptions.entries.map((entry) {
                    return RadioListTile<String>(
                      title: Text(entry.value),
                      value: entry.key,
                      groupValue: selectedLanguage,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedLanguage = value;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    await _settingsService.saveSettings(
                      apiKey: settings['apiKey'] as String?,
                      languageCode: selectedLanguage,
                      style: settings['style'] as TranslationStyle?,
                    );
                    
                    if (context.mounted) {
                      Provider.of<NotificationService>(context, listen: false)
                          .showSuccessSnackBar('Language setting saved');
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _showTranslationStyleDialog(BuildContext context) async {
    final _settingsService = SettingsService();
    final settings = await _settingsService.getSettings();
    TranslationStyle selectedStyle = settings['style'] as TranslationStyle? ?? TranslationStyle.faithful;
    
    String getTranslationStyleDisplayName(TranslationStyle style) {
      switch (style) {
        case TranslationStyle.faithful:
          return 'Faithful (Accuracy First)';
        case TranslationStyle.melodramaticPoet:
          return 'Melodramatic Poet (Artistic)';
        case TranslationStyle.machineClassic:
          return 'Machine Classic (Literal)';
      }
    }

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select AI model to use'),
              content: SizedBox(
                width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: TranslationStyle.values.map((style) {
                    return RadioListTile<TranslationStyle>(
                      title: Text(getTranslationStyleDisplayName(style)),
                      value: style,
                      groupValue: selectedStyle,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedStyle = value;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    await _settingsService.saveSettings(
                      apiKey: settings['apiKey'] as String?,
                      languageCode: settings['languageCode'] as String?,
                      style: selectedStyle,
                    );
                    
                    if (context.mounted) {
                      Provider.of<NotificationService>(context, listen: false)
                          .showSuccessSnackBar('Translation style saved');
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _handleExport(BuildContext context) async {
    final provider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    try {
      final success = await provider.exportDataToJson();
      if (context.mounted) {
         if (success) {
            debugPrint('Export process initiated, share sheet shown.');
         } else {
           notificationService.showErrorSnackBar('Export failed or cancelled.');
         }
      }
    } catch (e) {
       debugPrint('Export Exception: $e');
       if (context.mounted) {
          notificationService.showErrorSnackBar('Export failed: ${e.toString()}');
       }
    }
  }

  Future<void> _handleImport(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Import'),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
            child: const Text(
              'Importing data will replace existing tracks and translations with the same identifiers, and add all records from the file. This cannot be undone. Are you sure you want to continue?'
              '\n\nEnsure the JSON file is valid and was previously exported from Spotoolfy.'
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: Text('Import Data', style: TextStyle(color: Theme.of(dialogContext).colorScheme.primary)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final provider = Provider.of<LocalDatabaseProvider>(context, listen: false);
      try {
        final success = await provider.importDataFromJson();
        if (context.mounted) {
          if (success) {
            Provider.of<NotificationService>(context, listen: false)
                .showSuccessSnackBar('Data imported successfully!');
          } else {
            Provider.of<NotificationService>(context, listen: false)
                .showErrorSnackBar('Import failed or cancelled.');
          }
        }
      } catch (e) {
        debugPrint('Import Exception: $e');
        if (context.mounted) {
          Provider.of<NotificationService>(context, listen: false)
              .showErrorSnackBar('Import failed: ${e.toString()}');
        }
      }
    }
  }

  void _showClearCacheConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Clear Cache'),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
            child: const Text('Are you sure you want to clear the lyrics and translation cache? This cannot be undone.'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: Text('Clear Cache', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                _handleClearCache(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleClearCache(BuildContext context) async {
    final lyricsService = LyricsService();
    final translationService = TranslationService();

    try {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar('Clearing cache...', duration: const Duration(seconds: 1));
      
      await lyricsService.clearCache();
      await translationService.clearTranslationCache();
      
      if (context.mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showSuccessSnackBar('Cache cleared successfully!');
      }
    } catch (e) {
      logger.e('Failed to clear cache: $e');
      if (context.mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar('Failed to clear cache: $e');
      }
    }
  }
}