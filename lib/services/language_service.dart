import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class LanguageService {
  static const String _languageKey = 'selected_language';
  static const MethodChannel _channel = MethodChannel('language_channel');
  
  // 支持的语言列表
  static const List<Locale> supportedLocales = [
    Locale('en'),       // English
    Locale('zh'),       // Simplified Chinese  
    Locale('zh', 'TW'), // Traditional Chinese
    Locale('ja'),       // Japanese
  ];
  
  /// 获取当前保存的语言设置
  static Future<Locale?> getSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString(_languageKey);
      
      if (languageCode == null) return null;
      
      // 解析语言代码
      final parts = languageCode.split('_');
      if (parts.length == 1) {
        return Locale(parts[0]);
      } else if (parts.length == 2) {
        return Locale(parts[0], parts[1]);
      }
      
      return null;
    } catch (e) {
      print('Error getting saved locale: $e');
      return null;
    }
  }
  
  /// 保存语言设置
  static Future<void> saveLocale(Locale locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = locale.countryCode != null 
          ? '${locale.languageCode}_${locale.countryCode}'
          : locale.languageCode;
      
      await prefs.setString(_languageKey, languageCode);
    } catch (e) {
      print('Error saving locale: $e');
    }
  }
  
  /// 清除语言设置（跟随系统）
  static Future<void> clearSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_languageKey);
    } catch (e) {
      print('Error clearing saved locale: $e');
    }
  }
  
  /// 设置应用语言（Android 13+ 使用系统API，旧版本使用应用内设置）
  static Future<void> setAppLocale(Locale? locale) async {
    if (!Platform.isAndroid) return;
    
    try {
      if (locale == null) {
        // 清除设置，跟随系统
        await _channel.invokeMethod('clearAppLocale');
        await clearSavedLocale();
      } else {
        // 设置特定语言
        final languageTag = locale.countryCode != null
            ? '${locale.languageCode}-${locale.countryCode}'
            : locale.languageCode;
        
        await _channel.invokeMethod('setAppLocale', {'languageTag': languageTag});
        await saveLocale(locale);
      }
    } catch (e) {
      print('Error setting app locale: $e');
      // 降级到仅保存偏好设置
      if (locale != null) {
        await saveLocale(locale);
      } else {
        await clearSavedLocale();
      }
    }
  }
  
  /// 打开系统语言设置页面（Android 13+）
  static Future<void> openSystemLanguageSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('openSystemLanguageSettings');
    } catch (e) {
      print('Error opening system language settings: $e');
    }
  }
  
  /// 检查是否支持系统级语言设置（Android 13+）
  static Future<bool> supportsSystemLanguageSettings() async {
    if (!Platform.isAndroid) return false;
    
    try {
      final result = await _channel.invokeMethod('supportsSystemLanguageSettings');
      return result as bool? ?? false;
    } catch (e) {
      print('Error checking system language support: $e');
      return false;
    }
  }
  
  /// 获取语言显示名称
  static String getLanguageDisplayName(Locale locale) {
    switch (locale.toString()) {
      case 'en':
        return 'English';
      case 'zh':
        return '简体中文';
      case 'zh_TW':
        return '繁體中文';
      case 'ja':
        return '日本語';
      default:
        return locale.toString();
    }
  }
}