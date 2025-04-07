import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  static const _targetLanguageKey = 'target_translation_language';
  static const _defaultLanguage = 'en'; // Default to English

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

  // Method to save both settings at once, potentially useful in the UI
  Future<void> saveSettings({String? apiKey, String? languageCode}) async {
    if (apiKey != null) {
      await saveGeminiApiKey(apiKey);
    }
    if (languageCode != null) {
      await saveTargetLanguage(languageCode);
    }
  }

  // Method to get all settings, useful for initialization
  Future<Map<String, String?>> getSettings() async {
    return {
      'apiKey': await getGeminiApiKey(),
      'languageCode': await getTargetLanguage(),
    };
  }

  // Method to clear all app-specific settings (optional)
  Future<void> clearSettings() async {
    await _secureStorage.delete(key: _geminiApiKey);
    await _secureStorage.delete(key: _targetLanguageKey);
  }
} 