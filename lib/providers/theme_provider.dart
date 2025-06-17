import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class ThemeProvider extends ChangeNotifier {
  ColorScheme _colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
  
  ColorScheme get colorScheme => _colorScheme;

  void updateThemeFromSystem(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    _updateColorScheme(brightness);
    notifyListeners();
  }

  void _updateColorScheme(Brightness brightness) {
    final seedColor = _colorScheme.primary;
    _colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
  }

  Future<void> updateThemeFromImage(ImageProvider imageProvider, [Brightness? brightness]) async {
    try {
      final PaletteGenerator generator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200),
      );

      final Color dominantColor = generator.dominantColor?.color ?? 
                                generator.vibrantColor?.color ?? 
                                Colors.blue;

      final effectiveBrightness = brightness ?? Brightness.light;
      _colorScheme = ColorScheme.fromSeed(
        seedColor: dominantColor,
        brightness: effectiveBrightness,
      );
      
      notifyListeners();
    } catch (e) {
      logger.e('更新主题颜色失败: $e');
    }
  }
}