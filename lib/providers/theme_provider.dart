import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

final logger = Logger();

class ThemeProvider extends ChangeNotifier {
  ColorScheme _colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
  final LinkedHashMap<String, ColorScheme> _paletteCache =
      LinkedHashMap<String, ColorScheme>();
  static const int _maxCacheEntries = 8;
  int _paletteRequestId = 0;

  ColorScheme get colorScheme => _colorScheme;

  void updateThemeFromSystem(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final newScheme = ColorScheme.fromSeed(
      seedColor: _colorScheme.primary,
      brightness: brightness,
    );
    _applyColorScheme(newScheme);
  }

  void _applyColorScheme(ColorScheme newScheme) {
    if (_colorScheme == newScheme) {
      return;
    }
    _colorScheme = newScheme;
    notifyListeners();
  }

  Future<void> updateThemeFromImage({
    required ImageProvider imageProvider,
    required Brightness brightness,
    String? cacheKey,
  }) async {
    final normalizedCacheKey =
        cacheKey != null ? '${cacheKey}_${brightness.name}' : null;

    if (normalizedCacheKey != null &&
        _paletteCache.containsKey(normalizedCacheKey)) {
      _applyColorScheme(_paletteCache[normalizedCacheKey]!);
      return;
    }

    final int requestId = ++_paletteRequestId;

    try {
      final pixels = await _extractPixelsFromImage(imageProvider);
      if (pixels.isEmpty) {
        logger.w('无法从图片提取像素');
        return;
      }

      // 量化颜色并评分选择最佳种子色
      final quantizerResult = await QuantizerCelebi().quantize(pixels, 128);
      final ranked = Score.score(quantizerResult.colorToCount);

      if (ranked.isEmpty) {
        logger.w('无法从图片提取种子色');
        return;
      }

      if (requestId != _paletteRequestId) {
        return;
      }

      final seedColor = Color(ranked.first);
      logger.d('种子色: #${ranked.first.toRadixString(16).padLeft(8, '0')}');

      final ColorScheme nextScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );

      if (normalizedCacheKey != null) {
        _cacheColorScheme(normalizedCacheKey, nextScheme);
      }

      _applyColorScheme(nextScheme);
    } catch (e) {
      logger.e('更新主题颜色失败: $e');
    }
  }

  Future<List<int>> _extractPixelsFromImage(ImageProvider imageProvider) async {
    final completer = Completer<ui.Image>();
    final stream = imageProvider.resolve(ImageConfiguration.empty);

    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (exception, stackTrace) {
        completer.completeError(exception, stackTrace);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);

    final image = await completer.future;

    // 采样到约 100x100 以提高性能
    const targetSize = 100;
    final width = image.width;
    final height = image.height;
    final stepX = (width / targetSize).ceil().clamp(1, width);
    final stepY = (height / targetSize).ceil().clamp(1, height);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return [];
    }

    final pixels = <int>[];
    final bytes = byteData.buffer.asUint8List();

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final index = (y * width + x) * 4;
        if (index + 3 < bytes.length) {
          final r = bytes[index];
          final g = bytes[index + 1];
          final b = bytes[index + 2];
          final a = bytes[index + 3];

          if (a < 128) continue;

          final argb = (a << 24) | (r << 16) | (g << 8) | b;
          pixels.add(argb);
        }
      }
    }

    return pixels;
  }

  void _cacheColorScheme(String cacheKey, ColorScheme scheme) {
    _paletteCache[cacheKey] = scheme;
    if (_paletteCache.length > _maxCacheEntries) {
      _paletteCache.remove(_paletteCache.keys.first);
    }
  }
}
