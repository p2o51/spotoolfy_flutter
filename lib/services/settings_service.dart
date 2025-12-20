import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Define the translation styles
enum TranslationStyle {
  faithful,
  melodramaticPoet,
  machineClassic,
  neteaseProvider, // 网易云翻译（仅中文）
}

// Helper to convert enum to string for storage
String translationStyleToString(TranslationStyle style) {
  return style.name;
}

// Helper to convert string back to enum from storage
TranslationStyle stringToTranslationStyle(String? styleString) {
  if (styleString == null) {
    return SettingsService._defaultStyle; // Use the class-qualified constant default style
  }
  return TranslationStyle.values.firstWhere(
        (e) => e.name == styleString,
        orElse: () => SettingsService._defaultStyle, // Use the class-qualified constant default if value is invalid
      );
}

/// Gemini 模型配置
class GeminiModelConfig {
  final String modelName;
  final Map<String, dynamic> thinkingConfig;
  final String displayVersion;

  const GeminiModelConfig({
    required this.modelName,
    required this.thinkingConfig,
    required this.displayVersion,
  });

  /// Gemini 2.5 Flash 配置 (默认)
  static const gemini2 = GeminiModelConfig(
    modelName: 'gemini-flash-latest',
    thinkingConfig: {'thinkingBudget': 0},
    displayVersion: '2.5 Flash',
  );

  /// Gemini 3 Flash 配置
  static const gemini3 = GeminiModelConfig(
    modelName: 'gemini-3-flash-preview',
    thinkingConfig: {'thinkingLevel': 'MINIMAL'},
    displayVersion: '3 Flash',
  );
}

class SettingsService {
  // Removing aOptions for now to resolve persistent linter errors.
  // Default secure storage mechanisms will still be used.
  final _secureStorage = FlutterSecureStorage(
    // aOptions: const AndroidOptions(
    //   encryptedSharedPreferences: true,
    // ),
    // Add iOptions for iOS/macOS if needed (optional but good practice)
    // iOptions: const IOSOptions(
    //   accountName: 'flutter_secure_storage_service',
    // ),
    // Add webOptions for Web if needed (optional but good practice)
    // webOptions: const WebOptions(
    //   dbName: 'flutterSecureStorage',
    //   publicKey: 'publicKey',
    // ),
  );

  // Gemini API 相关常量
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/';

  static const _geminiApiKey = 'gemini_api_key';
  static const _spotifyClientIdKey = 'spotify_client_id'; // Spotify Client ID
  static const _targetLanguageKey = 'target_translation_language';
  static const _translationStyleKey = 'translation_style'; // Key for style
  static const _lastAiTranslationStyleKey = 'translation_style_last_ai';
  static const _copyLyricsAsSingleLineKey = 'copy_lyrics_single_line'; // Key for new setting
  static const _enableThinkingForInsightsKey = 'enable_thinking_for_insights';
  static const _autoTranslateLyricsKey = 'auto_translate_lyrics';
  static const _enableGemini3Key = 'enable_gemini_3';

  static const _defaultLanguage = 'en'; // Default to English
  static const _defaultStyle = TranslationStyle.faithful; // Default style

  Future<void> saveGeminiApiKey(String apiKey) async {
    await _secureStorage.write(key: _geminiApiKey, value: apiKey);
  }

  Future<String?> getGeminiApiKey() async {
    return await _secureStorage.read(key: _geminiApiKey);
  }

  Future<void> saveTargetLanguage(String languageCode) async {
    await _secureStorage.write(key: _targetLanguageKey, value: languageCode);
  }

  Future<String> getTargetLanguage() async {
    return await _secureStorage.read(key: _targetLanguageKey) ?? _defaultLanguage;
  }

  // Method to save translation style
  Future<void> saveTranslationStyle(TranslationStyle style) async {
    await _secureStorage.write(key: _translationStyleKey, value: translationStyleToString(style));
    if (style != TranslationStyle.neteaseProvider) {
      await _secureStorage.write(
        key: _lastAiTranslationStyleKey,
        value: translationStyleToString(style),
      );
    }
  }

  // Method to get translation style
  Future<TranslationStyle> getTranslationStyle() async {
    final styleString = await _secureStorage.read(key: _translationStyleKey);
    return stringToTranslationStyle(styleString);
  }

  Future<TranslationStyle> getLastAiTranslationStyle() async {
    final styleString = await _secureStorage.read(key: _lastAiTranslationStyleKey);
    if (styleString == null) {
      return _defaultStyle;
    }
    final style = stringToTranslationStyle(styleString);
    if (style == TranslationStyle.neteaseProvider) {
      return _defaultStyle;
    }
    return style;
  }

  // Method to save the copy format setting
  Future<void> saveCopyLyricsAsSingleLine(bool value) async {
    await _secureStorage.write(key: _copyLyricsAsSingleLineKey, value: value.toString());
  }

  // Method to get the copy format setting
  Future<bool> getCopyLyricsAsSingleLine() async {
    final valueString = await _secureStorage.read(key: _copyLyricsAsSingleLineKey);
    // Parse the string to bool. Handles null and defaults to false.
    return valueString?.toLowerCase() == 'true';
  }

  // Method to save the thinking mode for insights setting
  Future<void> saveEnableThinkingForInsights(bool value) async {
    await _secureStorage.write(key: _enableThinkingForInsightsKey, value: value.toString());
  }

  // Method to get the thinking mode for insights setting
  Future<bool> getEnableThinkingForInsights() async {
    final valueString = await _secureStorage.read(key: _enableThinkingForInsightsKey);
    // Parse the string to bool. Handles null and defaults to false.
    return valueString?.toLowerCase() == 'true';
  }

  Future<void> saveAutoTranslateLyricsEnabled(bool value) async {
    await _secureStorage.write(key: _autoTranslateLyricsKey, value: value.toString());
  }

  Future<bool> getAutoTranslateLyricsEnabled() async {
    final valueString = await _secureStorage.read(key: _autoTranslateLyricsKey);
    return valueString?.toLowerCase() == 'true';
  }

  // Gemini 3 开关设置
  Future<void> saveEnableGemini3(bool value) async {
    await _secureStorage.write(key: _enableGemini3Key, value: value.toString());
  }

  Future<bool> getEnableGemini3() async {
    final valueString = await _secureStorage.read(key: _enableGemini3Key);
    return valueString?.toLowerCase() == 'true';
  }

  /// 获取当前 Gemini 模型配置（统一入口）
  Future<GeminiModelConfig> getGeminiModelConfig() async {
    final enableGemini3 = await getEnableGemini3();
    return enableGemini3 ? GeminiModelConfig.gemini3 : GeminiModelConfig.gemini2;
  }

  /// 获取完整的 Gemini API URL
  Future<String> getGeminiApiUrl() async {
    final config = await getGeminiModelConfig();
    return '$geminiBaseUrl${config.modelName}';
  }

  /// 获取 Gemini 生成配置（用于 API 请求）
  /// [useGoogleSearch] - 是否启用 Google Search 工具
  /// [enableThinking] - 是否启用思考模式（仅对 Gemini 2.5 有效）
  Future<Map<String, dynamic>> getGeminiGenerationConfig({
    double temperature = 0.8,
    bool enableThinking = false,
  }) async {
    final modelConfig = await getGeminiModelConfig();
    final thinkingConfig = Map<String, dynamic>.from(modelConfig.thinkingConfig);

    // 对于 Gemini 2.5，如果启用思考模式则调整 thinkingBudget
    if (!await getEnableGemini3() && enableThinking) {
      thinkingConfig['thinkingBudget'] = 8;
    }

    return {
      'temperature': temperature,
      'thinkingConfig': thinkingConfig,
    };
  }

  // Method to save Spotify Client ID
  Future<void> saveSpotifyClientId(String clientId) async {
    await _secureStorage.write(key: _spotifyClientIdKey, value: clientId);
  }

  // Method to get Spotify Client ID
  Future<String?> getSpotifyClientId() async {
    return await _secureStorage.read(key: _spotifyClientIdKey);
  }

  // Method to save both settings at once, potentially useful in the UI
  Future<void> saveSettings({String? apiKey, String? languageCode, TranslationStyle? style, bool? copyAsSingleLine, bool? enableThinkingForInsights, bool? autoTranslateLyrics, bool? enableGemini3}) async {
    if (apiKey != null) {
      await saveGeminiApiKey(apiKey);
    }
    if (languageCode != null) {
      await saveTargetLanguage(languageCode);
    }
    if (style != null) {
      await saveTranslationStyle(style);
    }
    if (copyAsSingleLine != null) {
      await saveCopyLyricsAsSingleLine(copyAsSingleLine);
    }
    if (enableThinkingForInsights != null) {
      await saveEnableThinkingForInsights(enableThinkingForInsights);
    }
    if (autoTranslateLyrics != null) {
      await saveAutoTranslateLyricsEnabled(autoTranslateLyrics);
    }
    if (enableGemini3 != null) {
      await saveEnableGemini3(enableGemini3);
    }
  }

  // Method to get all settings, useful for initialization
  Future<Map<String, dynamic>> getSettings() async {
    return {
      'apiKey': await getGeminiApiKey(),
      'languageCode': await getTargetLanguage(),
      'style': await getTranslationStyle(),
      'copyLyricsAsSingleLine': await getCopyLyricsAsSingleLine(),
      'enableThinkingForInsights': await getEnableThinkingForInsights(),
      'autoTranslateLyrics': await getAutoTranslateLyricsEnabled(),
      'enableGemini3': await getEnableGemini3(),
    };
  }

  // Method to clear all app-specific settings (optional)
  Future<void> clearSettings() async {
    await _secureStorage.delete(key: _geminiApiKey);
    await _secureStorage.delete(key: _targetLanguageKey);
    await _secureStorage.delete(key: _translationStyleKey);
    await _secureStorage.delete(key: _lastAiTranslationStyleKey);
    await _secureStorage.delete(key: _copyLyricsAsSingleLineKey);
    await _secureStorage.delete(key: _enableThinkingForInsightsKey);
    await _secureStorage.delete(key: _autoTranslateLyricsKey);
    await _secureStorage.delete(key: _enableGemini3Key);
  }
}
