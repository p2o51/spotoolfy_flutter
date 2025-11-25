import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:palette_generator/palette_generator.dart';

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
      final PaletteGenerator generator =
          await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200),
        maximumColorCount: 128,
        // 禁用默认过滤器，获取包括黑白在内的所有颜色
        // 默认的 AvoidRedBlackWhitePaletteFilter 会过滤掉黑色、白色和低饱和度红色
        filters: const [],
      );

      final Color dominantColor = _selectBestSeedColor(generator);

      if (requestId != _paletteRequestId) {
        // A newer request has superseded this one.
        return;
      }

      final ColorScheme nextScheme = ColorScheme.fromSeed(
        seedColor: dominantColor,
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

  void _cacheColorScheme(String cacheKey, ColorScheme scheme) {
    _paletteCache[cacheKey] = scheme;
    if (_paletteCache.length > _maxCacheEntries) {
      final firstKey = _paletteCache.keys.first;
      _paletteCache.remove(firstKey);
    }
  }

  /// 智能颜色选择:支持灰色调专辑封面
  Color _selectBestSeedColor(PaletteGenerator generator) {
    const double minChromaForColor = 8.0; // 有色彩的最低色度（略微提高以更准确区分）
    // 理想色度区间：30-60 之间的颜色作为种子色效果最好
    const double idealChromaMin = 30.0;
    const double idealChromaMax = 60.0;
    // 理想明度区间：避免过亮或过暗的颜色
    const double idealToneMin = 30.0;
    const double idealToneMax = 70.0;

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
      final hct = Hct.fromInt(color.toARGB32());
      final proportion = paletteColor.population / totalPopulation;

      // 改进的评分算法：占比(50分) + 色度(30分) + 明度(20分) = 总分100分
      final proportionScore = proportion * 50;

      // 色度评分：理想区间内得满分，超出范围线性惩罚
      double chromaScore;
      if (hct.chroma >= idealChromaMin && hct.chroma <= idealChromaMax) {
        chromaScore = 30.0; // 满分
      } else if (hct.chroma < idealChromaMin) {
        // 色度不足，按比例给分
        chromaScore = (hct.chroma / idealChromaMin) * 30.0;
      } else {
        // 色度过高（>60），轻微惩罚避免刺眼的颜色
        chromaScore = 30.0 - ((hct.chroma - idealChromaMax) / 40.0) * 15.0;
      }
      chromaScore = chromaScore.clamp(0.0, 30.0);

      // 明度评分：避免过亮或过暗的颜色作为种子色
      double toneScore;
      if (hct.tone >= idealToneMin && hct.tone <= idealToneMax) {
        toneScore = 20.0; // 满分
      } else if (hct.tone < idealToneMin) {
        // 过暗
        toneScore = (hct.tone / idealToneMin) * 20.0;
      } else {
        // 过亮
        toneScore = 20.0 - ((hct.tone - idealToneMax) / 30.0) * 20.0;
      }
      toneScore = toneScore.clamp(0.0, 20.0);

      final score = proportionScore + chromaScore + toneScore;

      if (hct.chroma >= minChromaForColor) {
        coloredCandidates.add(
          _ColorScore(color, score, hct.hue, hct.chroma, hct.tone, proportion),
        );
      } else {
        grayscaleCandidates.add(
          _ColorScore(color, score, hct.hue, hct.chroma, hct.tone, proportion),
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
      final best = coloredCandidates.first;
      logger.d(
        '使用彩色主题 - 色度: ${best.chroma.toStringAsFixed(1)}, '
        '明度: ${best.tone.toStringAsFixed(1)}, '
        '占比: ${(best.proportion * 100).toStringAsFixed(1)}%',
      );
      return best.color;
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

    // 提高阈值到80%，避免误判有少量彩色元素的封面
    if (totalGrayscaleProportion > 0.80) {
      return true;
    }

    final bestColored = coloredCandidates.first;
    // 更严格的条件：只有当最佳彩色占比很低且色度很低时才使用灰色主题
    // 同时考虑：如果彩色部分的总占比低于10%，也应该使用灰色主题
    if (bestColored.proportion < 0.10 && bestColored.chroma < 20) {
      return true;
    }
    if (totalColoredProportion < 0.10 && bestColored.chroma < 25) {
      return true;
    }

    return false;
  }

  Color _enhanceGrayscaleColor(Color grayColor) {
    final hct = Hct.fromInt(grayColor.toARGB32());

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
  final double tone;
  final double proportion;

  _ColorScore(
    this.color,
    this.score,
    this.hue,
    this.chroma,
    this.tone,
    this.proportion,
  );
}
