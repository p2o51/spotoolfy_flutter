import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:palette_generator/palette_generator.dart';

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

  Future<void> updateThemeFromImage(
    ImageProvider imageProvider, [
    Brightness? brightness,
  ]) async {
    try {
      final PaletteGenerator generator =
          await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200),
        maximumColorCount: 128,
      );

      final Color dominantColor = _selectBestSeedColor(generator);

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

  /// 智能颜色选择:支持灰色调专辑封面
  Color _selectBestSeedColor(PaletteGenerator generator) {
    const double minChromaForColor = 5.0; // 有色彩的最低色度
    const double targetChroma = 48.0;

    final coloredCandidates = <_ColorScore>[];
    final grayscaleCandidates = <_ColorScore>[];

    final allColors = <PaletteColor?>[
      generator.dominantColor,
      generator.vibrantColor,
      generator.lightVibrantColor,
      generator.darkVibrantColor,
      generator.mutedColor,
      generator.lightMutedColor,
      generator.darkMutedColor,
      ...generator.paletteColors,
    ].whereType<PaletteColor>().toList();

    final totalPopulation =
        allColors.fold<int>(0, (sum, c) => sum + c.population);

    if (totalPopulation == 0) {
      return generator.dominantColor?.color ??
          generator.vibrantColor?.color ??
          Colors.blue;
    }

    for (final paletteColor in allColors) {
      final color = paletteColor.color;
      final hct = Hct.fromInt(color.value);
      final proportion = paletteColor.population / totalPopulation;

      final proportionScore = proportion * 0.7 * 100;
      final chromaScore = hct.chroma < targetChroma
          ? 0.1 * (hct.chroma - targetChroma)
          : 0.3 * (hct.chroma - targetChroma);
      final score = proportionScore + chromaScore;

      if (hct.chroma >= minChromaForColor) {
        coloredCandidates.add(
          _ColorScore(color, score, hct.hue, hct.chroma, proportion),
        );
      } else {
        grayscaleCandidates.add(
          _ColorScore(color, score, hct.hue, hct.chroma, proportion),
        );
      }
    }

    coloredCandidates.sort((a, b) => b.score.compareTo(a.score));
    grayscaleCandidates.sort((a, b) => b.score.compareTo(a.score));

    final shouldUseGrayscale = _shouldUseGrayscaleTheme(
      coloredCandidates,
      grayscaleCandidates,
    );

    if (shouldUseGrayscale && grayscaleCandidates.isNotEmpty) {
      logger.d('检测到灰色调专辑封面,使用灰色主题');
      return _enhanceGrayscaleColor(grayscaleCandidates.first.color);
    }

    if (coloredCandidates.isNotEmpty) {
      logger.d(
        '使用彩色主题,色度: '
        '${Hct.fromInt(coloredCandidates.first.color.value).chroma.toStringAsFixed(1)}',
      );
      return coloredCandidates.first.color;
    }

    return generator.dominantColor?.color ?? const Color(0xFF1B6EF3);
  }

  bool _shouldUseGrayscaleTheme(
    List<_ColorScore> coloredCandidates,
    List<_ColorScore> grayscaleCandidates,
  ) {
    if (coloredCandidates.isEmpty) {
      return true;
    }

    final totalColoredProportion = coloredCandidates.fold<double>(
      0,
      (sum, c) => sum + c.proportion,
    );
    final totalGrayscaleProportion = grayscaleCandidates.fold<double>(
      0,
      (sum, c) => sum + c.proportion,
    );

    if (totalGrayscaleProportion > 0.7) {
      return true;
    }

    final bestColored = coloredCandidates.first;
    if (bestColored.proportion < 0.15 && bestColored.chroma < 15) {
      return true;
    }

    return false;
  }

  Color _enhanceGrayscaleColor(Color grayColor) {
    final hct = Hct.fromInt(grayColor.value);

    const double enhancedChroma = 10.0;
    const double neutralBlueHue = 210.0;

    final enhanced = Hct.from(neutralBlueHue, enhancedChroma, hct.tone);

    return Color(enhanced.toInt());
  }
}

class _ColorScore {
  final Color color;
  final double score;
  final double hue;
  final double chroma;
  final double proportion;

  _ColorScore(
    this.color,
    this.score,
    this.hue,
    this.chroma,
    this.proportion,
  );
}
