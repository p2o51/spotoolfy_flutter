import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logger/logger.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../services/time_machine_service.dart';
import '../l10n/app_localizations.dart';

final _logger = Logger();

/// 从专辑封面提取颜色的工具类
class AlbumColorExtractor {
  static final LinkedHashMap<String, ColorScheme> _cache = LinkedHashMap();
  static const int _maxCacheEntries = 20;

  /// 从图片URL提取ColorScheme
  static Future<ColorScheme?> extractFromUrl(
    String? imageUrl,
    Brightness brightness,
  ) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;

    final cacheKey = '${imageUrl}_${brightness.name}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final imageProvider = NetworkImage(imageUrl);
      final pixels = await _extractPixelsFromImage(imageProvider);
      if (pixels.isEmpty) return null;

      final quantizerResult = await QuantizerCelebi().quantize(pixels, 128);
      final ranked = Score.score(quantizerResult.colorToCount);
      if (ranked.isEmpty) return null;

      final seedColor = Color(ranked.first);
      final colorScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );

      // Cache the result
      _cache[cacheKey] = colorScheme;
      if (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }

      return colorScheme;
    } catch (e) {
      _logger.w('Failed to extract color from image: $e');
      return null;
    }
  }

  static Future<List<int>> _extractPixelsFromImage(ImageProvider imageProvider) async {
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

    // Sample to ~50x50 for performance
    const targetSize = 50;
    final width = image.width;
    final height = image.height;
    final stepX = (width / targetSize).ceil().clamp(1, width);
    final stepY = (height / targetSize).ceil().clamp(1, height);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return [];

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
}

/// 时光机轮播图组件 - 显示"X年前的今天"添加的歌曲
class TimeMachineCarousel extends StatefulWidget {
  final TimeMachineService timeMachineService;
  final void Function(TimeMachineMemory memory)? onMemoryTap;
  final void Function(List<TimeMachineMemory> memories)? onViewAllTap;
  final VoidCallback? onDateRangeTap;

  const TimeMachineCarousel({
    super.key,
    required this.timeMachineService,
    this.onMemoryTap,
    this.onViewAllTap,
    this.onDateRangeTap,
  });

  @override
  State<TimeMachineCarousel> createState() => _TimeMachineCarouselState();
}

class _TimeMachineCarouselState extends State<TimeMachineCarousel> {
  Map<int, List<TimeMachineMemory>> _memoriesByYear = {};
  bool _isLoading = true;
  String? _error;

  // Auto-cycle state
  List<TimeMachineMemory> _allMemories = [];
  int _currentMemoryIndex = 0;
  Timer? _autoCycleTimer;

  // Dynamic color state
  ColorScheme? _currentColorScheme;
  String? _lastExtractedUrl;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  @override
  void dispose() {
    _autoCycleTimer?.cancel();
    super.dispose();
  }

  void _startAutoCycle() {
    _autoCycleTimer?.cancel();
    if (_allMemories.length <= 1) return;

    _autoCycleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _allMemories.isNotEmpty) {
        setState(() {
          _currentMemoryIndex = (_currentMemoryIndex + 1) % _allMemories.length;
        });
        // Extract color for new memory
        _extractColorForCurrentMemory();
      }
    });
  }

  /// 为当前显示的回忆提取颜色
  Future<void> _extractColorForCurrentMemory() async {
    if (_allMemories.isEmpty) return;

    final memory = _allMemories[_currentMemoryIndex];
    final imageUrl = memory.albumCoverUrl;

    // Skip if same URL or no URL
    if (imageUrl == null || imageUrl == _lastExtractedUrl) return;
    _lastExtractedUrl = imageUrl;

    final brightness = Theme.of(context).brightness;
    final colorScheme = await AlbumColorExtractor.extractFromUrl(imageUrl, brightness);

    if (mounted && colorScheme != null) {
      setState(() {
        _currentColorScheme = colorScheme;
      });
    }
  }

  Future<void> _loadMemories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final grouped = await widget.timeMachineService.getTodayMemoriesGroupedByYear(
        toleranceDays: 1, // 允许前后1天的容差
      );

      // Flatten all memories for auto-cycling
      final allMemories = <TimeMachineMemory>[];
      final years = grouped.keys.toList()..sort();
      for (final year in years) {
        allMemories.addAll(grouped[year] ?? []);
      }

      setState(() {
        _memoriesByYear = grouped;
        _allMemories = allMemories;
        _currentMemoryIndex = 0;
        _isLoading = false;
      });

      // Extract color for initial memory
      _extractColorForCurrentMemory();

      // Start auto-cycling if we have multiple memories
      _startAutoCycle();
    } catch (e) {
      _logger.w('Failed to load time machine memories: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 如果没有回忆或加载中/出错，显示简化版本
    if (_isLoading) {
      return _buildLoadingState(context);
    }

    // 如果出错，显示空状态但提供入口
    if (_error != null) {
      _logger.w('Time machine error: $_error');
      return _buildEmptyState(context, theme, colorScheme);
    }

    // 如果没有今日回忆，显示探索入口
    if (_memoriesByYear.isEmpty) {
      return _buildEmptyState(context, theme, colorScheme);
    }

    final currentMemory = _allMemories.isNotEmpty
        ? _allMemories[_currentMemoryIndex]
        : null;

    // 使用动态提取的颜色
    final headerColors = _currentColorScheme ?? colorScheme;

    // 整个卡片包裹在一个容器中，点击打开日期选择页面
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: headerColors.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: headerColors.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.lightImpact();
              if (currentMemory != null && widget.onMemoryTap != null) {
                widget.onMemoryTap!(currentMemory);
              } else {
                widget.onDateRangeTap?.call();
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏（使用动态颜色）
                  Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: headerColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.timeMachineTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: headerColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 自动轮播内容（淡入淡出效果）
                  if (currentMemory != null)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: _buildMemoryContent(
                        context,
                        currentMemory,
                        headerColors,
                        key: ValueKey(currentMemory.trackId),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// 构建回忆内容（不含外层卡片包装）
  Widget _buildMemoryContent(
    BuildContext context,
    TimeMachineMemory memory,
    ColorScheme cardColors, {
    Key? key,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // 计算该回忆是几年前的
    final yearsAgo = DateTime.now().year - memory.addedAt.year;

    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 专辑封面
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: memory.albumCoverUrl ?? '',
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 80,
              height: 80,
              color: cardColors.surfaceContainerHighest,
              child: Icon(
                Icons.music_note_rounded,
                size: 32,
                color: cardColors.onSurfaceVariant,
              ),
            ),
            errorWidget: (context, url, error) => Container(
              width: 80,
              height: 80,
              color: cardColors.surfaceContainerHighest,
              child: Icon(
                Icons.music_note_rounded,
                size: 32,
                color: cardColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 文字内容
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 年份标签和进度指示器
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cardColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.yearsAgoToday(yearsAgo),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cardColors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 显示当前索引/总数
                  if (_allMemories.length > 1)
                    Text(
                      '${_currentMemoryIndex + 1}/${_allMemories.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cardColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // 歌曲名
              Text(
                memory.trackName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cardColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // 艺术家名
              Text(
                memory.artistName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cardColors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // 专辑名
              Text(
                memory.albumName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cardColors.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 空状态 - 没有今日回忆时显示探索入口
  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onDateRangeTap?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.timeMachineTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.timeMachineEmptyHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
