import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Define the translation styles
enum TranslationStyle {
  faithful,
  melodramaticPoet,
  machineClassic,
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

  static const _geminiApiKey = 'gemini_api_key';
  static const _spotifyClientIdKey = 'spotify_client_id'; // Spotify Client ID
  static const _targetLanguageKey = 'target_translation_language';
  static const _translationStyleKey = 'translation_style'; // Key for style
  static const _copyLyricsAsSingleLineKey = 'copy_lyrics_single_line'; // Key for new setting
  static const _enableThinkingForInsightsKey = 'enable_thinking_for_insights';
  static const _autoTranslateLyricsKey = 'auto_translate_lyrics';

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
  }

  // Method to get translation style
  Future<TranslationStyle> getTranslationStyle() async {
    final styleString = await _secureStorage.read(key: _translationStyleKey);
    return stringToTranslationStyle(styleString);
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

  // Method to save Spotify Client ID
  Future<void> saveSpotifyClientId(String clientId) async {
    await _secureStorage.write(key: _spotifyClientIdKey, value: clientId);
  }

  // Method to get Spotify Client ID
  Future<String?> getSpotifyClientId() async {
    return await _secureStorage.read(key: _spotifyClientIdKey);
  }

  // Method to save both settings at once, potentially useful in the UI
  Future<void> saveSettings({String? apiKey, String? languageCode, TranslationStyle? style, bool? copyAsSingleLine, bool? enableThinkingForInsights, bool? autoTranslateLyrics}) async {
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
    };
  }

  // Method to clear all app-specific settings (optional)
  Future<void> clearSettings() async {
    await _secureStorage.delete(key: _geminiApiKey);
    await _secureStorage.delete(key: _targetLanguageKey);
    await _secureStorage.delete(key: _translationStyleKey);
    await _secureStorage.delete(key: _copyLyricsAsSingleLineKey);
    await _secureStorage.delete(key: _enableThinkingForInsightsKey);
    await _secureStorage.delete(key: _autoTranslateLyricsKey);
  }
}
