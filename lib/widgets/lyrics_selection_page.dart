import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/poster_lyric_line.dart';
import '../models/translation_load_result.dart';
import '../providers/spotify_provider.dart';
import '../services/gemini_chat_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../utils/responsive.dart';
import 'add_note.dart';
import 'ai_chat_sheet.dart';
import 'lyrics_poster_preview_page.dart';

enum _TranslationMenuAction {
  copyAllOriginal,
  copyAllTranslations,
  selectStyle,
  retranslate,
}

class LyricLine {
  final Duration timestamp;
  final String text;
  String? translation;
  bool isSelected;

  LyricLine(
    this.timestamp,
    this.text, {
    this.translation,
    this.isSelected = false,
  });
}

class LyricsSelectionPage extends StatefulWidget {
  // 修改 lyrics 参数类型以接收包含时间戳的列表
  final List<Map<String, dynamic>> lyrics;
  final String trackTitle;
  final String artistName;
  final String? albumCoverUrl;
  final bool initialShowTranslation;
  final TranslationStyle initialStyle;
  final Future<TranslationLoadResult> Function({
    bool forceRefresh,
    TranslationStyle? style,
  }) loadTranslation;
  final String originalLyrics;

  const LyricsSelectionPage({
    super.key,
    required this.lyrics,
    required this.trackTitle,
    required this.artistName,
    this.albumCoverUrl,
    required this.initialShowTranslation,
    required this.initialStyle,
    required this.loadTranslation,
    required this.originalLyrics,
  });

  @override
  State<LyricsSelectionPage> createState() => _LyricsSelectionPageState();
}

class _LyricsSelectionPageState extends State<LyricsSelectionPage> {
  late List<LyricLine> _lyricLines;
  // bool _isLoading = false; // isLoading can be final
  final bool _isLoading = false;
  int _selectedCount = 0;
  bool _showTranslation = false;
  bool _isTranslating = false;
  String? _translationError;
  late TranslationStyle _currentStyle;

  final _scrollController = ScrollController();
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _initializeLyricLines();
    _currentStyle = widget.initialStyle;
    _showTranslation = widget.initialShowTranslation;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showTranslation && !_hasTranslationsLoaded()) {
        _loadTranslation();
      }
    });
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
      final translation = lyricData['translation'] as String?;
      return LyricLine(timestamp, text, translation: translation);
    }).toList();
  }

  bool _hasTranslationsLoaded() {
    return _lyricLines.any(
      (line) => line.translation != null && line.translation!.trim().isNotEmpty,
    );
  }

  void _applyTranslations(Map<int, String> translations) {
    for (var i = 0; i < _lyricLines.length; i++) {
      final value = translations[i];
      if (value != null && value.trim().isNotEmpty) {
        _lyricLines[i].translation = value.trim();
      } else {
        _lyricLines[i].translation = null;
      }
    }
  }

  Future<void> _toggleTranslationVisibility() async {
    HapticFeedback.lightImpact();
    if (_showTranslation) {
      setState(() {
        _showTranslation = false;
        _translationError = null;
      });
      return;
    }

    if (!_hasTranslationsLoaded()) {
      await _loadTranslation();
    } else {
      setState(() {
        _showTranslation = true;
        _translationError = null;
      });
    }
  }

  Future<void> _loadTranslation({
    bool forceRefresh = false,
    TranslationStyle? style,
  }) async {
    if (_isTranslating) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isTranslating = true;
      _translationError = null;
    });

    try {
      final result = await widget.loadTranslation(
        forceRefresh: forceRefresh,
        style: style ?? _currentStyle,
      );

      if (!mounted) return;

      setState(() {
        _applyTranslations(result.perLineTranslations);
        _currentStyle = result.style;
        _isTranslating = false;
        _translationError = null;
        _showTranslation = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isTranslating = false;
        _translationError = e.toString();
      });

      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.translationFailed(e.toString()));
    }
  }

  Future<void> _showStyleSelectionDialog() async {
    if (_isTranslating) return;
    HapticFeedback.lightImpact();

    final l10n = AppLocalizations.of(context)!;
    final trackId = Provider.of<SpotifyProvider>(context, listen: false)
        .currentTrack?['item']?['id'] as String?;

    // 检查是否有网易云翻译缓存
    bool hasNeteaseTranslation = false;
    if (trackId != null) {
      final prefs = await SharedPreferences.getInstance();
      hasNeteaseTranslation = prefs.getString('netease_translation_$trackId') != null;
    }

    if (!mounted) return;

    final selectedStyle = await showDialog<TranslationStyle>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.translationStyleTitle),
        children: [
          _buildStyleOption(
            context,
            TranslationStyle.faithful,
            l10n.translationStyleFaithful,
            _currentStyle == TranslationStyle.faithful,
          ),
          _buildStyleOption(
            context,
            TranslationStyle.melodramaticPoet,
            l10n.translationStyleMelodramaticPoet,
            _currentStyle == TranslationStyle.melodramaticPoet,
          ),
          _buildStyleOption(
            context,
            TranslationStyle.machineClassic,
            l10n.translationStyleMachineClassic,
            _currentStyle == TranslationStyle.machineClassic,
          ),
          if (hasNeteaseTranslation)
            _buildStyleOption(
              context,
              TranslationStyle.neteaseProvider,
              l10n.translationStyleNetease,
              _currentStyle == TranslationStyle.neteaseProvider,
              subtitle: l10n.neteaseTranslationChineseOnly,
            ),
        ],
      ),
    );

    if (selectedStyle != null && selectedStyle != _currentStyle) {
      await _settingsService.saveTranslationStyle(selectedStyle);
      await _loadTranslation(style: selectedStyle);
    }
  }

  Widget _buildStyleOption(
    BuildContext context,
    TranslationStyle style,
    String title,
    bool isSelected, {
    String? subtitle,
  }) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(context).pop(style),
      child: Row(
        children: [
          if (isSelected)
            Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          else
            const SizedBox(width: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTranslationStyleDisplayName(AppLocalizations l10n) {
    switch (_currentStyle) {
      case TranslationStyle.faithful:
        return l10n.translationStyleFaithful;
      case TranslationStyle.melodramaticPoet:
        return l10n.translationStyleMelodramaticPoet;
      case TranslationStyle.machineClassic:
        return l10n.translationStyleMachineClassic;
      case TranslationStyle.neteaseProvider:
        return l10n.translationStyleNetease;
    }
  }

  Future<void> _handleTranslationMenu(_TranslationMenuAction action) async {
    HapticFeedback.lightImpact();
    switch (action) {
      case _TranslationMenuAction.copyAllOriginal:
        await _copyAllOriginalLyrics();
        break;
      case _TranslationMenuAction.copyAllTranslations:
        await _copyAllTranslatedLyrics();
        break;
      case _TranslationMenuAction.selectStyle:
        await _showStyleSelectionDialog();
        break;
      case _TranslationMenuAction.retranslate:
        await _loadTranslation(forceRefresh: true);
        break;
    }
  }

  Future<void> _copyAllOriginalLyrics() async {
    final l10n = AppLocalizations.of(context)!;
    final notificationService =
        Provider.of<NotificationService>(context, listen: false);

    final text = _lyricLines.map((line) => line.text).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    notificationService.showSnackBar(l10n.copiedToClipboard(l10n.lyricsTitle));
  }

  Future<void> _copyAllTranslatedLyrics() async {
    final l10n = AppLocalizations.of(context)!;
    final notificationService =
        Provider.of<NotificationService>(context, listen: false);

    if (!_hasTranslationsLoaded()) {
      await _loadTranslation();
    }

    final translations = _lyricLines
        .map((line) => line.translation?.trim())
        .whereType<String>()
        .where((line) => line.isNotEmpty)
        .toList();

    if (translations.isEmpty) {
      notificationService.showSnackBar(l10n.noLyricsToTranslate);
      return;
    }

    await Clipboard.setData(ClipboardData(text: translations.join('\n')));
    notificationService
        .showSnackBar(l10n.copiedToClipboard(l10n.translationTitle));
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

  List<PosterLyricLine> _getPosterLyricLines() {
    final includeTranslations = _showTranslation && _hasTranslationsLoaded();
    final posterLines = <PosterLyricLine>[];

    for (final line in _lyricLines) {
      if (!line.isSelected) continue;

      posterLines.add(PosterLyricLine(text: line.text));

      if (includeTranslations) {
        final translation = line.translation?.trim();
        if (translation != null && translation.isNotEmpty) {
          posterLines.add(
            PosterLyricLine(
              text: translation,
              isTranslation: true,
            ),
          );
        }
      }
    }

    return posterLines;
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

    final lyricsText = selectedLyrics.join('\n');

    // 使用统一的聊天界面
    AIChatSheet.show(
      context: context,
      chatContext: ChatContext(
        type: ChatContextType.lyricsAnalysis,
        trackTitle: widget.trackTitle,
        artistName: widget.artistName,
        selectedLyrics: lyricsText,
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
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final settings = await settingsService.getSettings();
    final copyAsSingleLine =
        settings['copyLyricsAsSingleLine'] as bool? ?? false;

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

    final posterLyricLines = _getPosterLyricLines();
    if (posterLyricLines.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsSelected);
      return;
    }

    // 导航到海报预览页面
    ResponsiveNavigation.showSecondaryPage(
      context: context,
      child: LyricsPosterPreviewPage(
        lyrics: posterLyricLines.map((line) => line.text).join('\n'),
        posterLyricLines: posterLyricLines,
        trackTitle: widget.trackTitle,
        artistName: widget.artistName,
        albumCoverUrl: widget.albumCoverUrl,
      ),
      preferredMode: SecondaryPageMode.fullScreen,
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

    // Join selected lyrics for the lyricsSnapshot field
    final lyricsSnapshot = selectedLyrics.join('\n');

    // 弹出添加笔记对话框，传递选中的歌词
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddNoteSheet(
        selectedLyrics: lyricsSnapshot, // Save to lyricsSnapshot field
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
        final currentProgressMs =
            spotifyProvider.currentTrack?['progress_ms'] ?? 0;
        final currentPosition = Duration(milliseconds: currentProgressMs);
        final currentLineIndex = _getCurrentLineIndex(currentPosition);

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.selectLyrics),
            actions: [
              IconButton(
                onPressed: _isTranslating ? null : _toggleTranslationVisibility,
                tooltip:
                    _showTranslation ? l10n.showOriginal : l10n.showTranslation,
                icon: _isTranslating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _showTranslation ? Icons.g_translate : Icons.translate,
                      ),
              ),
              PopupMenuButton<_TranslationMenuAction>(
                tooltip: l10n.translationTitle,
                enabled: !_isTranslating,
                onSelected: _handleTranslationMenu,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _TranslationMenuAction.copyAllOriginal,
                    child: Text(
                      '${l10n.copyButtonText} · ${l10n.originalTitle}',
                    ),
                  ),
                  PopupMenuItem(
                    value: _TranslationMenuAction.copyAllTranslations,
                    child: Text(
                      '${l10n.copyButtonText} · ${l10n.translationTitle}',
                    ),
                  ),
                  PopupMenuItem(
                    value: _TranslationMenuAction.selectStyle,
                    child: Text(
                      '${l10n.translationStyleTitle} · ${_getTranslationStyleDisplayName(l10n)}',
                    ),
                  ),
                  PopupMenuItem(
                    value: _TranslationMenuAction.retranslate,
                    child: Text(l10n.retranslateButton),
                  ),
                ],
              ),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
              if (_translationError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      title: Text(
                        _translationError!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: _isTranslating
                            ? null
                            : () => _loadTranslation(forceRefresh: true),
                        child: Text(l10n.retryButton),
                      ),
                    ),
                  ),
                ),
              // 歌词列表 - 包含歌曲信息的统一滚动
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount:
                      _lyricLines.length + 1, // +1 for the song info header
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // 第一项：歌曲信息卡片
                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.music_note,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.music_note,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.trackTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.artistName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
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
                        isFirstInGroup = lyricIndex == 0 ||
                            !_lyricLines[lyricIndex - 1].isSelected;

                        // 检查是否为组的最后一行
                        isLastInGroup = lyricIndex == _lyricLines.length - 1 ||
                            !_lyricLines[lyricIndex + 1].isSelected;
                      }

                      return _LyricTile(
                        index: lyricIndex,
                        line: _lyricLines[lyricIndex],
                        onTap: () => _toggleLineSelection(lyricIndex),
                        isFirstInGroup: isFirstInGroup,
                        isLastInGroup: isLastInGroup,
                        isCurrentlyPlaying:
                            lyricIndex == currentLineIndex, // 传递当前播放状态
                        showTranslation: _showTranslation,
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
                                onPressed:
                                    _isLoading ? null : _deselectAllLines,
                                icon: const Icon(Icons.close),
                                tooltip: l10n.deselectAll,
                                style: IconButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.onTertiaryContainer,
                                  backgroundColor:
                                      theme.colorScheme.tertiaryContainer,
                                  fixedSize: const Size(56, 56),
                                ),
                              ),
                            if (_hasSelectedLyrics()) const SizedBox(width: 12),
                            IconButton(
                              onPressed: _isLoading ? null : _askGemini,
                              icon: const Icon(Icons.auto_awesome),
                              tooltip: l10n.askGemini,
                              style: IconButton.styleFrom(
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                fixedSize: const Size(56, 56),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _selectedCount > 15 || _isLoading
                                    ? null
                                    : _shareAsPoster,
                                icon: Icon(
                                  Icons.image,
                                  color: (_selectedCount > 15 || _isLoading)
                                      ? theme.colorScheme.onSurface
                                          .withValues(alpha: 0.38)
                                      : null,
                                ),
                                label: Text(l10n.posterButtonLabel),
                                style: FilledButton.styleFrom(
                                  // fixedSize: const Size(double.infinity, 56),
                                  backgroundColor:
                                      (_selectedCount > 15 || _isLoading)
                                          ? theme.colorScheme.onSurface
                                              .withValues(alpha: 0.12)
                                          : null,
                                  foregroundColor:
                                      (_selectedCount > 15 || _isLoading)
                                          ? theme.colorScheme.onSurface
                                              .withValues(alpha: 0.38)
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
  final bool showTranslation;

  const _LyricTile({
    // super.key, // Parameter 'key' is not used
    required this.index,
    required this.line,
    required this.onTap,
    this.isFirstInGroup = false,
    this.isLastInGroup = false,
    this.isCurrentlyPlaying = false,
    this.showTranslation = false,
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

    final translationText = showTranslation
        ? (line.translation != null && line.translation!.trim().isNotEmpty
            ? line.translation!.trim()
            : null)
        : null;
    final translationColor = translationText != null ? textColor : null;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 18,
                    color: textColor,
                    fontWeight: fontWeight,
                  ),
                ),
                if (translationText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      translationText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 15,
                        color: translationColor,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
