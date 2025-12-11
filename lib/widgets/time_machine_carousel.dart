import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logger/logger.dart';

import '../services/time_machine_service.dart';
import '../l10n/app_localizations.dart';

final _logger = Logger();

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
  final PageController _pageController = PageController(viewportFraction: 0.92);
  Map<int, List<TimeMachineMemory>> _memoriesByYear = {};
  List<int> _years = [];
  bool _isLoading = true;
  String? _error;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

      setState(() {
        _memoriesByYear = grouped;
        _years = grouped.keys.toList()..sort(); // 按年份排序（1年前、2年前...）
        _isLoading = false;
      });
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.timeMachineTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 日期范围选择器按钮
              if (widget.onDateRangeTap != null)
                IconButton(
                  icon: Icon(
                    Icons.date_range_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: widget.onDateRangeTap,
                  tooltip: AppLocalizations.of(context)!.timeMachineDateRange,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),

        // 轮播图
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _years.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              final yearsAgo = _years[index];
              final memories = _memoriesByYear[yearsAgo] ?? [];
              return _buildMemoryCard(context, yearsAgo, memories);
            },
          ),
        ),

        // 页面指示器
        if (_years.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_years.length, (index) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? colorScheme.primary
                        : colorScheme.outline.withValues(alpha: 0.3),
                  ),
                );
              }),
            ),
          ),
      ],
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

  Widget _buildMemoryCard(
    BuildContext context,
    int yearsAgo,
    List<TimeMachineMemory> memories,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // 取第一首歌作为代表
    final primaryMemory = memories.first;
    final otherCount = memories.length - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
            if (memories.length == 1) {
              widget.onMemoryTap?.call(primaryMemory);
            } else {
              widget.onViewAllTap?.call(memories);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 专辑封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: primaryMemory.albumCoverUrl ?? '',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 100,
                      height: 100,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note_rounded,
                        size: 40,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 100,
                      height: 100,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note_rounded,
                        size: 40,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 文字内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 年份标签
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          l10n.yearsAgoToday(yearsAgo),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 歌曲名
                      Text(
                        primaryMemory.trackName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // 艺术家名
                      Text(
                        primaryMemory.artistName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 如果有更多歌曲，显示数量
                      if (otherCount > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.queue_music_rounded,
                              size: 14,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.andMoreTracks(otherCount),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // 播放图标
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 28,
                  color: colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
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
