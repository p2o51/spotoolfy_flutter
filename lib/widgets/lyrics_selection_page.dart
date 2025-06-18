import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
// import '../services/lyrics_poster_service.dart'; // Unused import
import '../services/settings_service.dart';
// import '../providers/local_database_provider.dart'; // Unused import
import '../providers/spotify_provider.dart';
// import '../models/track.dart'; // Unused import
import 'lyrics_poster_preview_page.dart';
import 'lyrics_analysis_page.dart';
import 'add_note.dart';
import '../l10n/app_localizations.dart';

class LyricLine {
  final Duration timestamp;
  final String text;
  bool isSelected;

  LyricLine(this.timestamp, this.text, {this.isSelected = false});
}

class LyricsSelectionPage extends StatefulWidget {
  // 修改 lyrics 参数类型以接收包含时间戳的列表
  final List<Map<String, dynamic>> lyrics;
  final String trackTitle;
  final String artistName;
  final String? albumCoverUrl;

  const LyricsSelectionPage({
    super.key,
    required this.lyrics,
    required this.trackTitle,
    required this.artistName,
    this.albumCoverUrl,
  });

  @override
  State<LyricsSelectionPage> createState() => _LyricsSelectionPageState();
}

class _LyricsSelectionPageState extends State<LyricsSelectionPage> {
  late List<LyricLine> _lyricLines;
  // bool _isLoading = false; // isLoading can be final
  final bool _isLoading = false; 
  int _selectedCount = 0;
  
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeLyricLines();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeLyricLines() {
    _lyricLines = widget.lyrics.map((lyricData) {
      final timestamp = lyricData['timestamp'] as Duration;
      final text = lyricData['text'] as String;
      return LyricLine(timestamp, text);
    }).toList();
  }

  // 获取当前播放行的索引
  int _getCurrentLineIndex(Duration currentPosition) {
    if (_lyricLines.isEmpty) return -1;
    
    // 如果当前位置在第一行之前，返回 -1
    if (_lyricLines.isNotEmpty && currentPosition < _lyricLines[0].timestamp) {
      return -1;
    }
    
    // 找到最后一行其时间戳小于等于当前位置的行
    for (int i = _lyricLines.length - 1; i >= 0; i--) {
      if (_lyricLines[i].timestamp <= currentPosition) {
        return i;
      }
    }
    
    return -1;
  }

  void _deselectAllLines() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedCount = 0;
      for (int i = 0; i < _lyricLines.length; i++) {
        _lyricLines[i].isSelected = false;
      }
    });
  }

  void _toggleLineSelection(int index) {
    if (index < 0 || index >= _lyricLines.length) return;
    
    HapticFeedback.selectionClick();
    setState(() {
      final wasSelected = _lyricLines[index].isSelected;
      _lyricLines[index].isSelected = !wasSelected;
      
      _selectedCount += wasSelected ? -1 : 1;
    });
  }

  List<String> _getSelectedLyrics() {
    return _lyricLines
        .where((line) => line.isSelected)
        .map((line) => line.text)
        .toList();
  }

  bool _hasSelectedLyrics() => _selectedCount > 0;

  Future<void> _askGemini() async {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context)!;
    final selectedLyrics = _getSelectedLyrics();
    if (selectedLyrics.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsSelected);
      return;
    }

    // 导航到分析页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LyricsAnalysisPage(
          lyrics: selectedLyrics.join('\n'),
          trackTitle: widget.trackTitle,
          artistName: widget.artistName,
          albumCoverUrl: widget.albumCoverUrl,
        ),
      ),
    );
  }

  Future<void> _copySelectedLyrics() async {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context)!;
    final selectedLyrics = _getSelectedLyrics();
    if (selectedLyrics.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsSelected);
      return;
    }

    // 获取设置服务
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    final settings = await settingsService.getSettings();
    final copyAsSingleLine = settings['copyLyricsAsSingleLine'] as bool? ?? false;

    // 根据设置格式化文本
    final String text;
    if (copyAsSingleLine) {
      // 复制为单行，用空格替换换行符
      text = selectedLyrics.join(' ');
    } else {
      // 复制为多行，保持原有格式
      text = selectedLyrics.join('\n');
    }

    await Clipboard.setData(ClipboardData(text: text));
    
    if (mounted) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.selectedLyricsCopied(selectedLyrics.length));
    }
  }

  Future<void> _shareAsPoster() async {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context)!;
    final selectedLyrics = _getSelectedLyrics();
    if (selectedLyrics.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsSelected);
      return;
    }

    // 检查行数限制
    if (selectedLyrics.length > 15) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.posterLyricsLimitExceeded);
      return;
    }

    // 导航到海报预览页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LyricsPosterPreviewPage(
          lyrics: selectedLyrics.join('\n'),
          trackTitle: widget.trackTitle,
          artistName: widget.artistName,
          albumCoverUrl: widget.albumCoverUrl,
        ),
      ),
    );
  }

  Future<void> _createNoteWithLyrics() async {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context)!;
    final selectedLyrics = _getSelectedLyrics();
    if (selectedLyrics.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsSelected);
      return;
    }

    // 使用三重引号包装歌词
    final lyricsContent = '"""\n${selectedLyrics.join('\n')}\n"""';

    // 弹出添加笔记对话框，预填充歌词
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddNoteSheet(
        prefilledContent: lyricsContent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    
    return Consumer<SpotifyProvider>(
      builder: (context, spotifyProvider, child) {
        // 获取当前播放进度
        final currentProgressMs = spotifyProvider.currentTrack?['progress_ms'] ?? 0;
        final currentPosition = Duration(milliseconds: currentProgressMs);
        final currentLineIndex = _getCurrentLineIndex(currentPosition);
        
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.selectLyrics),
            actions: [
              if (_hasSelectedLyrics())
                TextButton(
                  onPressed: _isLoading ? null : _copySelectedLyrics,
                  child: Text(l10n.copyButtonText),
                ),
              if (_hasSelectedLyrics())
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selectedCount > 15 
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_selectedCount/15',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: _selectedCount > 15 
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              // 歌词列表 - 包含歌曲信息的统一滚动
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _lyricLines.length + 1, // +1 for the song info header
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // 第一项：歌曲信息卡片
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            if (widget.albumCoverUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  widget.albumCoverUrl!,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.music_note,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                ),
                              )
                            else
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.music_note,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.trackTitle,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.artistName,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // 其余项：歌词行
                      final lyricIndex = index - 1;
                      
                      // 计算当前行是否为连续选中组的首尾
                      bool isFirstInGroup = false;
                      bool isLastInGroup = false;
                      
                      if (_lyricLines[lyricIndex].isSelected) {
                        // 检查是否为组的第一行
                        isFirstInGroup = lyricIndex == 0 || !_lyricLines[lyricIndex - 1].isSelected;
                        
                        // 检查是否为组的最后一行
                        isLastInGroup = lyricIndex == _lyricLines.length - 1 || !_lyricLines[lyricIndex + 1].isSelected;
                      }
                      
                      return _LyricTile(
                        index: lyricIndex,
                        line: _lyricLines[lyricIndex],
                        onTap: () => _toggleLineSelection(lyricIndex),
                        isFirstInGroup: isFirstInGroup,
                        isLastInGroup: isLastInGroup,
                        isCurrentlyPlaying: lyricIndex == currentLineIndex, // 传递当前播放状态
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          
          // 底部操作栏
          bottomNavigationBar: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: SizedBox(
              height: 56.0,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _hasSelectedLyrics()
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 取消全选按钮 (仅在有选中时显示)
                            if (_hasSelectedLyrics())
                              IconButton(
                                onPressed: _isLoading ? null : _deselectAllLines,
                                icon: const Icon(Icons.close),
                                tooltip: l10n.deselectAll,
                                style: IconButton.styleFrom(
                                  foregroundColor: theme.colorScheme.onTertiaryContainer,
                                  backgroundColor: theme.colorScheme.tertiaryContainer,
                                  fixedSize: const Size(56, 56),
                                ), 
                              ),
                            if (_hasSelectedLyrics())
                              const SizedBox(width: 12),
                            IconButton(
                              onPressed: _isLoading ? null : _askGemini,
                              icon: const Icon(Icons.auto_awesome),
                              tooltip: l10n.askGemini,
                              style: IconButton.styleFrom(
                                foregroundColor: theme.colorScheme.onPrimaryContainer,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                fixedSize: const Size(56, 56),
                              ), 
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _selectedCount > 15 || _isLoading ? null : _shareAsPoster,
                                icon: Icon(
                                  Icons.image,
                                  color: (_selectedCount > 15 || _isLoading)
                                      ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                      : null,
                                ),
                                label: Text(l10n.posterButtonLabel),
                                style: FilledButton.styleFrom(
                                  // fixedSize: const Size(double.infinity, 56),
                                  backgroundColor: (_selectedCount > 15 || _isLoading)
                                      ? theme.colorScheme.onSurface.withValues(alpha: 0.12)
                                      : null,
                                  foregroundColor: (_selectedCount > 15 || _isLoading)
                                      ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                      : null,
                                ), 
                              ),
                            ),
                            const SizedBox(width: 12),
                             Expanded(
                               child: FilledButton.tonalIcon(
                                onPressed: _createNoteWithLyrics,
                                icon: const Icon(Icons.note_add),
                                label: Text(l10n.noteButtonLabel),
                                style: FilledButton.styleFrom(
                                  // fixedSize: const Size(double.infinity, 56),
                                ),
                               ),
                             ),
                          ],
                        )
                      : Center(
                          child: Text(
                            l10n.tapToSelectLyrics,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
            ),
          ),
        );
      },
    );
  }
}

// 简化的歌词行组件
class _LyricTile extends StatelessWidget {
  final int index;
  final LyricLine line;
  final VoidCallback onTap;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool isCurrentlyPlaying;

  const _LyricTile({
    // super.key, // Parameter 'key' is not used
    required this.index,
    required this.line,
    required this.onTap,
    this.isFirstInGroup = false,
    this.isLastInGroup = false,
    this.isCurrentlyPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 计算圆角
    BorderRadius borderRadius;
    if (line.isSelected) {
      borderRadius = BorderRadius.only(
        topLeft: Radius.circular(isFirstInGroup ? 12 : 4),
        topRight: Radius.circular(isFirstInGroup ? 12 : 4),
        bottomLeft: Radius.circular(isLastInGroup ? 12 : 4),
        bottomRight: Radius.circular(isLastInGroup ? 12 : 4),
      );
    } else {
      borderRadius = BorderRadius.circular(12);
    }

    // 确定文本颜色 - 当前播放行使用primary颜色，选中行使用primary颜色，普通行使用secondaryContainer颜色
    Color textColor;
    FontWeight fontWeight = FontWeight.w700;

    if (isCurrentlyPlaying && !line.isSelected) {
      // 当前播放但未选中：使用primary颜色
      textColor = theme.colorScheme.primary;
    } else if (line.isSelected) {
      // 选中状态：使用primary颜色
      textColor = theme.colorScheme.primary;
    } else {
      // 普通状态：使用secondaryContainer颜色 (原文如此，但似乎应为 onSurfaceVariant 或类似)
      // 保持与之前逻辑一致，但可以考虑 theme.colorScheme.onSurfaceVariant
      textColor = theme.colorScheme.secondaryContainer;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
        ),
        color: line.isSelected 
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.6)
            : theme.colorScheme.surface, // 当前播放行不改变背景色
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              line.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 18,
                color: textColor,
                fontWeight: fontWeight,
                // fontStyle: isCurrentlyPlaying ? FontStyle.italic : FontStyle.normal, // 移除斜体
              ),
            ),
          ),
        ),
      ),
    );
  }
} 