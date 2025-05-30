import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import '../services/lyrics_analysis_service.dart';
import '../services/lyrics_poster_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class LyricLine {
  final Duration timestamp;
  final String text;
  bool isSelected;

  LyricLine(this.timestamp, this.text, {this.isSelected = false});
}

class LyricsSelectionPage extends StatefulWidget {
  final List<String> lyrics;
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
  bool _isLoading = false;
  bool _selectAll = false;
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
    _lyricLines = widget.lyrics.asMap().entries.map((entry) {
      final index = entry.key;
      final text = entry.value;
      final timestamp = Duration(seconds: index * 5);
      return LyricLine(timestamp, text);
    }).toList();
  }

  void _deselectAllLines() {
    setState(() {
      _selectAll = false;
      _selectedCount = 0;
      for (int i = 0; i < _lyricLines.length; i++) {
        _lyricLines[i].isSelected = false;
      }
    });
  }

  void _toggleLineSelection(int index) {
    if (index < 0 || index >= _lyricLines.length) return;
    
    setState(() {
      final wasSelected = _lyricLines[index].isSelected;
      _lyricLines[index].isSelected = !wasSelected;
      
      _selectedCount += wasSelected ? -1 : 1;
      _selectAll = false;
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
    final l10n = AppLocalizations.of(context)!;
    final selectedLyrics = _getSelectedLyrics();
    if (selectedLyrics.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsSelected);
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final analysisService = LyricsAnalysisService();
      final analysis = await analysisService.analyzeLyrics(
        selectedLyrics.join('\n'),
        widget.trackTitle,
        widget.artistName,
      );

      if (mounted && analysis != null) {
        _showAnalysisDialog(analysis);
      }
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar(l10n.analysisFailed(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  void _showAnalysisDialog(Map<String, dynamic> analysis) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.geminiAnalysisResult),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (analysis['theme'] != null) ...[
                Text(l10n.lyricsTheme, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(analysis['theme']),
                const SizedBox(height: 16),
              ],
              if (analysis['emotion'] != null) ...[
                Text(l10n.lyricsEmotion, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(analysis['emotion']),
                const SizedBox(height: 16),
              ],
              if (analysis['metaphor'] != null) ...[
                Text(l10n.lyricsMetaphor, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(analysis['metaphor']),
                const SizedBox(height: 16),
              ],
              if (analysis['interpretation'] != null) ...[
                Text(l10n.lyricsInterpretation, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(analysis['interpretation']),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final fullText = [
                if (analysis['theme'] != null) '${l10n.lyricsTheme}: ${analysis['theme']}',
                if (analysis['emotion'] != null) '${l10n.lyricsEmotion}: ${analysis['emotion']}',
                if (analysis['metaphor'] != null) '${l10n.lyricsMetaphor}: ${analysis['metaphor']}',
                if (analysis['interpretation'] != null) '${l10n.lyricsInterpretation}: ${analysis['interpretation']}',
              ].join('\n\n');
              
              Clipboard.setData(ClipboardData(text: fullText));
              Provider.of<NotificationService>(context, listen: false)
                  .showSnackBar(l10n.analysisResultCopied);
            },
            child: Text(l10n.copyAnalysis),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
        ],
      ),
    );
  }

  Future<void> _copySelectedLyrics() async {
    final l10n = AppLocalizations.of(context)!;
    final selectedLyrics = _getSelectedLyrics();
    if (selectedLyrics.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsSelected);
      return;
    }

    final text = selectedLyrics.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    
    if (mounted) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.selectedLyricsCopied(selectedLyrics.length));
    }
  }

  Future<void> _shareAsPoster() async {
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

    setState(() { _isLoading = true; });

    try {
      final posterService = LyricsPosterService();
      await posterService.generateAndSharePoster(
        lyrics: selectedLyrics.join('\n'),
        trackTitle: widget.trackTitle,
        artistName: widget.artistName,
        albumCoverUrl: widget.albumCoverUrl,
      );
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar(l10n.posterGenerationFailed(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.selectLyrics),
        actions: [
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _lyricLines.length + 1, // +1 for the song info header
              itemBuilder: (context, index) {
                if (index == 0) {
                  // 第一项：歌曲信息卡片
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                style: Theme.of(context).textTheme.titleMedium,
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
                  return _LyricTile(
                    index: lyricIndex,
                    line: _lyricLines[lyricIndex],
                    onTap: () => _toggleLineSelection(lyricIndex),
                  );
                }
              },
            ),
          ),
        ],
      ),
      
      // 底部操作栏
      bottomNavigationBar: _hasSelectedLyrics()
          ? Container(
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
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                        FilledButton.tonalIcon(
                          onPressed: _selectedCount > 15 || _isLoading ? null : _shareAsPoster,
                          icon: Icon(
                            Icons.image,
                            color: (_selectedCount > 15 || _isLoading)
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                : null,
                          ),
                          label: const Text('Poster'),
                          style: FilledButton.styleFrom(
                            fixedSize: const Size(double.infinity, 56),
                            backgroundColor: (_selectedCount > 15 || _isLoading)
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.12)
                                : null,
                            foregroundColor: (_selectedCount > 15 || _isLoading)
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                : null,
                          ), 
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _copySelectedLyrics,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                          style: FilledButton.styleFrom(
                            fixedSize: const Size(double.infinity, 56),
                          ),
                        ),
                      ],
                    ),
            )
          : null,
    );
  }
}

// 简化的歌词行组件
class _LyricTile extends StatelessWidget {
  final int index;
  final LyricLine line;
  final VoidCallback onTap;

  const _LyricTile({
    super.key,
    required this.index,
    required this.line,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 左侧选择区域
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.transparent,
              ),
              child: Icon(
                line.isSelected 
                    ? Icons.check_circle 
                    : Icons.circle_outlined,
                color: line.isSelected 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),
          // 右侧文本区域
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: line.isSelected 
                      ? theme.colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: line.isSelected 
                      ? Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.3))
                      : null,
                ),
                child: Text(
                  line.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 18,
                    color: line.isSelected 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.secondary,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 