import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

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

  Future<void> updateThemeFromImage(ImageProvider imageProvider, BuildContext context) async {
    try {
      final PaletteGenerator generator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200),
      );

      final Color dominantColor = generator.dominantColor?.color ?? 
                                generator.vibrantColor?.color ?? 
                                Colors.blue;

      final brightness = MediaQuery.platformBrightnessOf(context);
      _colorScheme = ColorScheme.fromSeed(
        seedColor: dominantColor,
        brightness: brightness,
      );
      
      notifyListeners();
    } catch (e) {
      print('更新主题颜色失败: $e');
    }
  }
}