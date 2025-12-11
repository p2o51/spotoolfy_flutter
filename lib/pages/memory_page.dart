import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

import '../services/time_machine_service.dart';
import '../providers/spotify_provider.dart';
import '../l10n/app_localizations.dart';

final _logger = Logger();

/// 时光机回忆页面 - 显示某个时间段的音乐回忆
class MemoryPage extends StatefulWidget {
  final TimeMachineService timeMachineService;
  final List<TimeMachineMemory>? initialMemories;
  final String? title;
  final int? yearsAgo;

  const MemoryPage({
    super.key,
    required this.timeMachineService,
    this.initialMemories,
    this.title,
    this.yearsAgo,
  });

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  List<TimeMachineMemory> _memories = [];
  bool _isLoading = false;
  String? _error;

  // 日期范围选择
  DateTimeRange? _selectedDateRange;
  bool _isDateRangeMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMemories != null) {
      _memories = widget.initialMemories!;
    } else {
      _loadTodayMemories();
    }
  }

  Future<void> _loadTodayMemories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final memories = await widget.timeMachineService.getTodayMemories(
        toleranceDays: 1,
      );
      setState(() {
        _memories = memories;
        _isLoading = false;
        _isDateRangeMode = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMemoriesByDateRange(DateTimeRange range) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedDateRange = range;
      _isDateRangeMode = true;
    });

    try {
      final memories = await widget.timeMachineService.getTracksByDateRange(
        startDate: range.start,
        endDate: range.end,
      );
      setState(() {
        _memories = memories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showDateRangePicker() async {
    final now = DateTime.now();
    final initialRange = _selectedDateRange ??
        DateTimeRange(
          start: DateTime(now.year - 1, now.month, now.day),
          end: now,
        );

    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: child!,
        );
      },
    );

    if (result != null) {
      await _loadMemoriesByDateRange(result);
    }
  }

  void _playMemory(TimeMachineMemory memory) {
    HapticFeedback.lightImpact();
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    try {
      spotifyProvider.playTrack(trackUri: memory.trackUri);
    } catch (e) {
      _logger.w('Failed to play track: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.playbackFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // 构建标题
    String pageTitle;
    if (widget.title != null) {
      pageTitle = widget.title!;
    } else if (_isDateRangeMode && _selectedDateRange != null) {
      final formatter = DateFormat.yMMMd();
      pageTitle = '${formatter.format(_selectedDateRange!.start)} - ${formatter.format(_selectedDateRange!.end)}';
    } else if (widget.yearsAgo != null) {
      pageTitle = l10n.yearsAgoToday(widget.yearsAgo!);
    } else {
      pageTitle = l10n.timeMachineTitle;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          // 日期范围选择按钮
          IconButton(
            icon: Icon(
              _isDateRangeMode ? Icons.today_rounded : Icons.date_range_rounded,
            ),
            onPressed: _isDateRangeMode ? _loadTodayMemories : _showDateRangePicker,
            tooltip: _isDateRangeMode
                ? l10n.timeMachineToday
                : l10n.timeMachineDateRange,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.unknownError,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadTodayMemories,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (_memories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off_rounded,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.timeMachineEmpty,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.timeMachineEmptyHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: _showDateRangePicker,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.timeMachineDateRange),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final memory = _memories[index];
        return _buildMemoryTile(context, memory);
      },
    );
  }

  Widget _buildMemoryTile(BuildContext context, TimeMachineMemory memory) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final dateFormatter = DateFormat.yMMMd();
    final formattedDate = dateFormatter.format(memory.addedAt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: memory.albumCoverUrl ?? '',
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.music_note_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.music_note_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      title: Text(
        memory.trackName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memory.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 12,
                color: colorScheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                _isDateRangeMode
                    ? formattedDate
                    : l10n.addedYearsAgo(memory.yearsAgo, formattedDate),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.play_circle_filled_rounded,
          color: colorScheme.primary,
          size: 36,
        ),
        onPressed: () => _playMemory(memory),
      ),
      onTap: () => _playMemory(memory),
    );
  }
}
