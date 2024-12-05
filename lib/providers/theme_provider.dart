import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class ThemeProvider extends ChangeNotifier {
  ColorScheme _colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
  
  ColorScheme get colorScheme => _colorScheme;

  Future<void> updateThemeFromImage(ImageProvider imageProvider) async {
    try {
      final PaletteGenerator generator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200), // 减小图片尺寸以提高性能
      );

      // 优先使用主色调，如果没有则使用最显眼的颜色
      final Color dominantColor = generator.dominantColor?.color ?? 
                                generator.vibrantColor?.color ?? 
                                Colors.blue;

      _colorScheme = ColorScheme.fromSeed(
        seedColor: dominantColor,
        brightness: Brightness.light,
      );
      
      notifyListeners();
    } catch (e) {
      print('更新主题颜色失败: $e');
    }
  }
}