import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart'; // Import AppLocalizations
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
    final l10n = AppLocalizations.of(context)!; // Get AppLocalizations instance
    
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
                    l10n.settingsTitle, // Use localization
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary.withAlpha((255 * 0.8).round()), // Use withAlpha as recommended alternative
                    ),
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
            if (spotifyProvider.currentTrack != null && spotifyProvider.username != null)
              Padding(
                padding: const EdgeInsets.only(top: kElementSpacing),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (spotifyProvider.username != null)
                      Flexible(
                        child: Text(
                          // Use localization with placeholder
                          spotifyProvider.username != null ? l10n.loggedInAs(spotifyProvider.username!) : '', 
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
    final l10n = AppLocalizations.of(context)!; // Get AppLocalizations instance here too

    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: spotifyProvider.currentTrack != null
            ? Theme.of(context).colorScheme.error
            : null,
      ),
      onPressed: spotifyProvider.isLoading
          ? null
          : () async {
              try {
                if (spotifyProvider.currentTrack != null) {
                  await spotifyProvider.logout();
                  HapticFeedback.lightImpact();
                  notificationService.showSuccessSnackBar(l10n.logoutSuccess); // Use localization
                } else {
                  await spotifyProvider.login();
                  HapticFeedback.lightImpact();
                  notificationService.showSuccessSnackBar(l10n.loginSuccess); // Use localization
                  if (context.mounted) Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  String errorMessage = l10n.operationFailed; // Use localization
                  
                  logger.e('登录/注销操作失败: $e');
                  logger.e('错误类型: ${e.runtimeType}');
                  
                  if (e.toString().contains('INVALID_CREDENTIALS') || e.toString().contains('客户端 ID 或密钥无效')) {
                    errorMessage = l10n.invalidCredentialsError; // Use localization
                  } else if (e.toString().contains('401')) {
                    errorMessage = l10n.authenticationError; // Use localization
                  } else if (e.toString().contains('429')) {
                    errorMessage = l10n.tooManyRequestsError; // Use localization
                  } else {
                    errorMessage = l10n.loginLogoutFailed(e.toString()); // Use localization with error detail
                  }
                  
                  notificationService.showErrorSnackBar(
                    errorMessage,
                    actionLabel: l10n.helpAction, // Use localization
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
          : Text(spotifyProvider.currentTrack != null
              ? l10n.logoutSpotifyButton // Use localization
              : l10n.authorizeSpotifyButton), // Use localization
    );
  }
}

class SettingsMenuSection extends StatefulWidget {
  const SettingsMenuSection({super.key});

  @override
  State<SettingsMenuSection> createState() => _SettingsMenuSectionState();
}

class _SettingsMenuSectionState extends State<SettingsMenuSection> {
  // Key to force FutureBuilder rebuild
  Key _languageKey = UniqueKey();
  Key _styleKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!; // Get AppLocalizations instance
    
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
              l10n.setupTitle, // Use localization
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.vpn_key,
              title: l10n.googleAiApiKeyTitle, // Use localization
              subtitle: l10n.googleAiApiKeySubtitle, // Use localization
              onTap: () => _showGeminiApiKeyDialog(context, l10n),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.api,
              title: l10n.spotifyApiTitle, // Use localization
              subtitle: l10n.spotifyApiSubtitle, // Use localization
              onTap: () => _showSpotifyCredentialsDialog(context, l10n),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.help_outline,
              title: l10n.tutorialTitle, // Use localization
              subtitle: l10n.tutorialSubtitle, // Use localization
              onTap: () => launchUrl(Uri.parse('https://51notepage.craft.me/spotoolfy')),
            ),
            const SizedBox(height: kSectionSpacing),
            
            // 常规设置部分
            Text(
              l10n.generalTitle, // Use localization
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),
            FutureBuilder<String>(
              future: context.read<SettingsService>().getTargetLanguage(),
              key: _languageKey,
              builder: (context, snapshot) {
                String languageDisplay = "";
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  // 显示语言名称
                  switch (snapshot.data) {
                    case 'en': languageDisplay = "English"; break;
                    case 'zh-CN': languageDisplay = "简体中文"; break;
                    case 'zh-TW': languageDisplay = "繁體中文"; break;
                    case 'ja': languageDisplay = "日本語"; break;
                    default: languageDisplay = snapshot.data ?? "";
                  }
                }
                return _buildSettingMenuItem(
                  context,
                  icon: Icons.language,
                  title: l10n.translationLanguageTitle,
                  subtitle: languageDisplay.isNotEmpty ? languageDisplay : l10n.translationLanguageSubtitle,
                  onTap: () => _showLanguageDialog(context, l10n, () {
                    setState(() { _languageKey = UniqueKey(); });
                  }),
                );
              },
            ),
            const SizedBox(height: kElementSpacing),
            FutureBuilder<TranslationStyle>(
              future: context.read<SettingsService>().getTranslationStyle(),
              key: _styleKey,
              builder: (context, snapshot) {
                String styleDisplay = "";
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  // 显示翻译样式名称
                  switch (snapshot.data) {
                    case TranslationStyle.faithful: styleDisplay = "Faithful"; break;
                    case TranslationStyle.melodramaticPoet: styleDisplay = "Melodramatic Poet"; break;
                    case TranslationStyle.machineClassic: styleDisplay = "Machine Classic"; break;
                    default: styleDisplay = "";
                  }
                }
                return _buildSettingMenuItem(
                  context,
                  icon: Icons.style,
                  title: l10n.translationStyleTitle,
                  subtitle: styleDisplay.isNotEmpty ? styleDisplay : l10n.translationStyleSubtitle,
                  onTap: () => _showTranslationStyleDialog(context, l10n, () {
                    setState(() { _styleKey = UniqueKey(); });
                  }),
                );
              },
            ),
            const SizedBox(height: kElementSpacing),
            _buildSwitchMenuItem(
              context,
              icon: Icons.text_format,
              title: l10n.copyLyricsAsSingleLineTitle, // Use localization
              subtitle: l10n.copyLyricsAsSingleLineSubtitle, // Use localization
            ),
            const SizedBox(height: kElementSpacing),
            _buildThinkingModeSwitchMenuItem(
              context,
              icon: Icons.psychology,
              title: l10n.deepTranslationTitle, // 使用多语言
              subtitle: l10n.deepTranslationSubtitle, // 使用多语言
            ),
            const SizedBox(height: kSectionSpacing),
            
            // 数据管理部分
            Text(
              l10n.dataManagementTitle, // Use localization
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.upload_file,
              title: l10n.exportDataTitle, // Use localization
              subtitle: l10n.exportDataSubtitle, // Use localization
              onTap: () => _exportData(context, l10n),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.download,
              title: l10n.importDataTitle, // Use localization
              subtitle: l10n.importDataSubtitle, // Use localization
              onTap: () => _showImportDialog(context, l10n),
            ),
            const SizedBox(height: kElementSpacing),
            _buildSettingMenuItem(
              context,
              icon: Icons.cleaning_services,
              title: l10n.clearCacheTitle, // Use localization
              subtitle: l10n.clearCacheSubtitle, // Use localization
              onTap: () => _showClearCacheDialog(context, l10n),
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
                  ? Theme.of(context).colorScheme.error.withAlpha((255 * 0.1).round())
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
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    return StatefulBuilder(
      builder: (context, setState) {
        return FutureBuilder<Map<String, dynamic>>(
          future: settingsService.getSettings(),
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
                  settingsService.saveCopyLyricsAsSingleLine(newValue);
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
                        settingsService.saveCopyLyricsAsSingleLine(value);
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

  Widget _buildThinkingModeSwitchMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    return StatefulBuilder(
      builder: (context, setState) {
        return FutureBuilder<bool>(
          future: settingsService.getEnableThinkingForTranslation(),
          builder: (context, snapshot) {
            bool enableThinking = false;
            if (snapshot.hasData) {
              enableThinking = snapshot.data!;
            }
            
            return InkWell(
              onTap: () {
                if (snapshot.hasData) {
                  HapticFeedback.lightImpact();
                  final newValue = !enableThinking;
                  settingsService.saveEnableThinkingForTranslation(newValue);
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
                      value: enableThinking,
                      onChanged: (bool value) {
                        HapticFeedback.lightImpact();
                        settingsService.saveEnableThinkingForTranslation(value);
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

  Future<void> _exportData(BuildContext context, AppLocalizations l10n) async {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    final currentContext = context;

    try {
      bool success = await localDbProvider.exportDataToJson();
      if (!currentContext.mounted) return; 
      if (success) {
        notificationService.showSuccessSnackBar(l10n.exportSuccess); 
      } else {
        notificationService.showErrorSnackBar(l10n.exportFailed);
      }
    } catch (e) {
      if (currentContext.mounted) { 
        notificationService.showErrorSnackBar(l10n.exportFailed);
      }
    }
  }

  Future<void> _showGeminiApiKeyDialog(BuildContext context, AppLocalizations l10n) async {
    final settingsService = context.read<SettingsService>();
    final notificationService = context.read<NotificationService>();
    final navigator = Navigator.of(context);
    final currentContext = context;

    final currentApiKey = await settingsService.getGeminiApiKey() ?? '';
    if (!currentContext.mounted) return; 
    final apiKeyController = TextEditingController(text: currentApiKey);

    showDialog(
      context: currentContext, 
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.geminiApiKeyDialogTitle), 
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
            child: TextField(
              controller: apiKeyController,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: l10n.geminiApiKeyDialogHint, 
              ),
              obscureText: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancelButton), 
            ),
            TextButton(
              onPressed: () async {
                final apiKey = apiKeyController.text.trim();
                await settingsService.saveGeminiApiKey(apiKey);
                if (!currentContext.mounted) return; 
                navigator.pop();
                notificationService.showSuccessSnackBar(l10n.apiKeySaved);
              },
              child: Text(l10n.okButton), 
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSpotifyCredentialsDialog(BuildContext context, AppLocalizations l10n) async {
    final spotifyProvider = context.read<SpotifyProvider>();
    final notificationService = context.read<NotificationService>();
    final navigator = Navigator.of(context);
    final currentContext = context;

    final credentials = await spotifyProvider.getClientCredentials();
    if (!currentContext.mounted) return; 
    final clientIdController = TextEditingController(text: credentials['clientId'] ?? '');

    showDialog(
      context: currentContext, 
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.spotifyCredentialsDialogTitle), 
              content: SizedBox(
                width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        'If you failed to log in with the default Client ID, you need to create your own app in the Spotify Developers Platform and configure the redirect URI as "spotoolfy://callback"',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextField(
                      controller: clientIdController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        labelText: l10n.clientIdLabel,
                        hintText: '64103961829a42328a6634fb80574191', 
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () {
                        launchUrl(Uri.parse('https://developer.spotify.com/dashboard'));
                      },
                      child: Text('Access the Spotify for Developers platform'),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Note: Please make sure to set the redirect URI in the Spotify Developer Platform to: "spotoolfy://callback"',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancelButton), 
                ),
                TextButton(
                  onPressed: () async {
                    final clientId = clientIdController.text;
                    if (clientId.isEmpty) {
                      notificationService.showErrorSnackBar(l10n.emptyCredentialsError);
                      return;
                    }
                    final hexRegex = RegExp(r'^[0-9a-fA-F]{32}$');
                    if (!hexRegex.hasMatch(clientId)) {
                      notificationService.showErrorSnackBar(l10n.invalidClientIdError);
                      return;
                    }
                    try {
                      await spotifyProvider.setClientCredentials(
                        clientId,
                      );
                      navigator.pop();
                      notificationService.showSuccessSnackBar(l10n.credentialsSaved);
                    } catch (e) {
                      if (currentContext.mounted) { 
                        notificationService.showErrorSnackBar(l10n.credentialsSaveFailed);
                      }
                    }
                  },
                  child: Text(l10n.okButton), 
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _showLanguageDialog(BuildContext context, AppLocalizations l10n, VoidCallback onSuccess) async {
    final settingsService = context.read<SettingsService>();
    final notificationService = context.read<NotificationService>();
    final navigator = Navigator.of(context);
    final currentContext = context;

    final currentLanguage = await settingsService.getTargetLanguage();
    if (!currentContext.mounted) return; 

    showDialog(
      context: currentContext, 
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.languageDialogTitle), 
              content: SizedBox(
                width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      title: const Text('English'),
                      value: 'en',
                      groupValue: currentLanguage,
                      onChanged: (value) async {
                        if (value != null) {
                          try {
                            await settingsService.saveTargetLanguage(value);
                            navigator.pop();
                            notificationService.showSuccessSnackBar(l10n.languageSaved);
                            onSuccess();
                          } catch (e) {
                            if (currentContext.mounted) { 
                              notificationService.showErrorSnackBar(l10n.failedToChangeLanguage(e.toString()));
                            }
                          }
                        }
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('简体中文 (Simplified Chinese)'),
                      value: 'zh-CN',
                      groupValue: currentLanguage,
                      onChanged: (value) async {
                        if (value != null) {
                          try {
                            await settingsService.saveTargetLanguage(value);
                            navigator.pop();
                            notificationService.showSuccessSnackBar(l10n.languageSaved);
                            onSuccess();
                          } catch (e) {
                            if (currentContext.mounted) { 
                              notificationService.showErrorSnackBar(l10n.failedToChangeLanguage(e.toString()));
                            }
                          }
                        }
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('繁體中文 (Traditional Chinese)'),
                      value: 'zh-TW',
                      groupValue: currentLanguage,
                      onChanged: (value) async {
                        if (value != null) {
                          try {
                            await settingsService.saveTargetLanguage(value);
                            navigator.pop();
                            notificationService.showSuccessSnackBar(l10n.languageSaved);
                            onSuccess();
                          } catch (e) {
                            if (currentContext.mounted) { 
                              notificationService.showErrorSnackBar(l10n.failedToChangeLanguage(e.toString()));
                            }
                          }
                        }
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('日本語 (Japanese)'),
                      value: 'ja',
                      groupValue: currentLanguage,
                      onChanged: (value) async {
                        if (value != null) {
                          try {
                            await settingsService.saveTargetLanguage(value);
                            navigator.pop();
                            notificationService.showSuccessSnackBar(l10n.languageSaved);
                            onSuccess();
                          } catch (e) {
                            if (currentContext.mounted) { 
                              notificationService.showErrorSnackBar(l10n.failedToChangeLanguage(e.toString()));
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancelButton), 
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _showTranslationStyleDialog(BuildContext context, AppLocalizations l10n, VoidCallback onSuccess) async {
    final settingsService = context.read<SettingsService>();
    final notificationService = context.read<NotificationService>();
    final navigator = Navigator.of(context);
    final currentContext = context;

    final currentStyle = await settingsService.getTranslationStyle();
    if (!currentContext.mounted) return; 

    showDialog(
      context: currentContext, 
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.translationStyleDialogTitle), 
              content: SizedBox(
                width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<TranslationStyle>(
                      title: const Text("Faithful"), // Use enum name
                      value: TranslationStyle.faithful, 
                      groupValue: currentStyle,
                      onChanged: (TranslationStyle? value) async {
                        if (value != null) {
                          try {
                            await settingsService.saveTranslationStyle(value);
                            navigator.pop();
                            notificationService.showSuccessSnackBar(l10n.translationStyleSaved);
                            onSuccess();
                          } catch (e) {
                            if (currentContext.mounted) { 
                              notificationService.showErrorSnackBar(l10n.failedToChangeStyle(e.toString()));
                            }
                          }
                        }
                      },
                    ),
                    RadioListTile<TranslationStyle>(
                      title: const Text("Melodramatic Poet"), // Use formatted enum name
                      value: TranslationStyle.melodramaticPoet, 
                      groupValue: currentStyle,
                      onChanged: (TranslationStyle? value) async {
                        if (value != null) {
                          try {
                            await settingsService.saveTranslationStyle(value);
                            navigator.pop();
                            notificationService.showSuccessSnackBar(l10n.translationStyleSaved);
                            onSuccess();
                          } catch (e) {
                            if (currentContext.mounted) { 
                              notificationService.showErrorSnackBar(l10n.failedToChangeStyle(e.toString()));
                            }
                          }
                        }
                      },
                    ),
                    RadioListTile<TranslationStyle>(
                      title: const Text("Machine Classic"), // Use formatted enum name
                      value: TranslationStyle.machineClassic, 
                      groupValue: currentStyle,
                      onChanged: (TranslationStyle? value) async {
                        if (value != null) {
                          try {
                            await settingsService.saveTranslationStyle(value);
                            navigator.pop();
                            notificationService.showSuccessSnackBar(l10n.translationStyleSaved);
                            onSuccess();
                          } catch (e) {
                            if (currentContext.mounted) { 
                              notificationService.showErrorSnackBar(l10n.failedToChangeStyle(e.toString()));
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancelButton), 
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _showImportDialog(BuildContext context, AppLocalizations l10n) async {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    final navigator = Navigator.of(context);
    final currentContext = context;

    showDialog(
      context: currentContext, 
      builder: (dialogContext) { 
        return AlertDialog(
          title: Text(l10n.importDialogTitle), 
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
            child: Text(
              l10n.importDialogMessage, 
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancelButton), 
            ),
            TextButton(
              onPressed: () async {
                navigator.pop(); 
                try {
                  bool success = await localDbProvider.importDataFromJson(); 
                  if (!currentContext.mounted) return; 
                  if (success) {
                    notificationService.showSuccessSnackBar(l10n.importSuccess); 
                  } else {
                    notificationService.showErrorSnackBar(l10n.importFailed); 
                  }
                } catch (e) {
                  if (currentContext.mounted) { 
                    notificationService.showErrorSnackBar(l10n.importFailed);
                  }
                }
              },
              child: Text(l10n.importButton), 
            ),
          ],
        );
      },
    );
  }

  Future<void> _showClearCacheDialog(BuildContext context, AppLocalizations l10n) async {
    final lyricsService = Provider.of<LyricsService>(context, listen: false);
    final translationService = Provider.of<TranslationService>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    final navigator = Navigator.of(context);
    final currentContext = context;

    showDialog(
      context: currentContext, 
      builder: (dialogContext) { 
        return AlertDialog(
          title: Text(l10n.clearCacheDialogTitle), 
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 500.0),
            child: Text(
              l10n.clearCacheDialogMessage, 
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancelButton), 
            ),
            TextButton(
              onPressed: () async {
                navigator.pop(); 
                showDialog(
                  context: currentContext, 
                  barrierDismissible: false,
                  builder: (progressContext) => AlertDialog(
                    content: Row(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(width: 16), 
                        Text(l10n.clearingCache), 
                      ],
                    ),
                  ),
                );

                try {
                  await lyricsService.clearCache();
                  await translationService.clearTranslationCache();

                  if (!currentContext.mounted) return; 
                  navigator.pop(); 
                  if (!currentContext.mounted) return; 
                  notificationService.showSuccessSnackBar(l10n.cacheCleared); 
                } catch (e) {
                  if (currentContext.mounted) { 
                    navigator.pop(); 
                    if (currentContext.mounted) { 
                      notificationService.showErrorSnackBar(l10n.cacheClearFailed); 
                    }
                  }
                }
              },
              child: Text(l10n.clearCacheButton), 
            ),
          ],
        );
      },
    );
  }
}