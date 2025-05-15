import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard and HapticFeedback
import '../services/settings_service.dart'; // Import TranslationStyle and SettingsService
import 'package:provider/provider.dart';
import '../providers/local_database_provider.dart';
import '../models/translation.dart';
// 导入 AppLocalizations 类，用于访问本地化字符串
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// --- 本地化辅助函数 ---

// 使用 AppLocalizations 获取翻译风格的显示名称
String _getTranslationStyleDisplayName(TranslationStyle style, AppLocalizations l10n) {
  switch (style) {
    case TranslationStyle.faithful:
      // 使用 l10n 获取本地化字符串
      return l10n.translationStyleFaithful;
    case TranslationStyle.melodramaticPoet:
      // 使用 l10n 获取本地化字符串
      return l10n.translationStyleMelodramaticPoet;
    case TranslationStyle.machineClassic:
      // 使用 l10n 获取本地化字符串
      return l10n.translationStyleMachineClassic;
  }
}

// 获取翻译风格对应的图标 (这个函数不涉及文本，无需本地化)
IconData _getTranslationStyleIcon(TranslationStyle style) {
  switch (style) {
    case TranslationStyle.faithful:
      return Icons.straight;
    case TranslationStyle.melodramaticPoet:
      return Icons.auto_stories;
    case TranslationStyle.machineClassic:
      return Icons.smart_toy;
  }
}

// 获取下一个翻译风格 (这个函数不涉及文本，无需本地化)
TranslationStyle _getNextTranslationStyle(TranslationStyle currentStyle) {
  switch (currentStyle) {
    case TranslationStyle.faithful:
      return TranslationStyle.melodramaticPoet;
    case TranslationStyle.melodramaticPoet:
      return TranslationStyle.machineClassic;
    case TranslationStyle.machineClassic:
      return TranslationStyle.faithful;
  }
}

// 使用 AppLocalizations 获取翻译风格按钮的 Tooltip 文本
String _getTranslationStyleTooltip(TranslationStyle style, AppLocalizations l10n) {
  switch (style) {
    case TranslationStyle.faithful:
      // 使用 l10n 获取本地化字符串
      return l10n.translationStyleTooltipFaithful;
    case TranslationStyle.melodramaticPoet:
      // 使用 l10n 获取本地化字符串
      return l10n.translationStyleTooltipMelodramatic;
    case TranslationStyle.machineClassic:
      // 使用 l10n 获取本地化字符串
      return l10n.translationStyleTooltipMachine;
  }
}

// --- Widget 主体 ---

class TranslationResultSheet extends StatefulWidget {
  final String originalLyrics;
  final String translatedLyrics;
  final Future<String?> Function() onReTranslate;
  final TranslationStyle translationStyle;
  final String trackId;

  const TranslationResultSheet({
    Key? key,
    required this.originalLyrics,
    required this.translatedLyrics,
    required this.onReTranslate,
    required this.translationStyle,
    required this.trackId,
  }) : super(key: key);

  @override
  State<TranslationResultSheet> createState() => _TranslationResultSheetState();
}

class _TranslationResultSheetState extends State<TranslationResultSheet> {
  bool _isTranslating = false;
  String? _translationError;
  late String _currentTranslatedLyrics;
  late TranslationStyle _currentStyle;
  bool _showTranslated = true; // 默认显示翻译后的歌词 (窄屏模式下)

  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _currentTranslatedLyrics = widget.translatedLyrics;
    _currentStyle = widget.translationStyle;
  }

  // 切换翻译风格
  Future<void> _toggleTranslationStyle() async {
    if (_isTranslating) return;

    // 获取 AppLocalizations 实例以用于错误消息
    final l10n = AppLocalizations.of(context)!;
    final nextStyle = _getNextTranslationStyle(_currentStyle);
    final nextStyleString = translationStyleToString(nextStyle);

    setState(() {
      _isTranslating = true;
      _translationError = null;
    });

    try {
      HapticFeedback.lightImpact();
      await _settingsService.saveTranslationStyle(nextStyle);

      setState(() {
        _currentStyle = nextStyle;
      });

      final currentLanguage = await _settingsService.getTargetLanguage();
      final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
      final cachedTranslation = await localDbProvider.fetchTranslation(
        widget.trackId,
        currentLanguage,
        nextStyleString
      );

      if (cachedTranslation != null) {
        if (mounted) {
          setState(() {
            _currentTranslatedLyrics = cachedTranslation.translatedLyrics;
            _isTranslating = false;
          });
        }
      } else {
        final newTranslation = await widget.onReTranslate();
        if (mounted) {
          setState(() {
            if (newTranslation != null) {
              _currentTranslatedLyrics = newTranslation;
              _translationError = null;
            } else {
              // 使用本地化的错误消息
              _translationError = l10n.translationFailed(l10n.operationFailed); // 或者一个更具体的错误 key
            }
            _isTranslating = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // 使用本地化的错误消息 (假设有一个通用的错误 key 或使用 translationFailed)
          _translationError = l10n.translationFailed(e.toString());
          _isTranslating = false;
        });
      }
    }
  }

  // 重新翻译
  Future<void> _handleReTranslate() async {
     if (_isTranslating) return;

    // 获取 AppLocalizations 实例
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _isTranslating = true; // 可以考虑显示本地化的 "Retranslating..." 状态
      _translationError = null;
    });

    try {
      HapticFeedback.lightImpact();
      final newTranslation = await widget.onReTranslate();
      if (mounted) {
        setState(() {
          if (newTranslation != null) {
            _currentTranslatedLyrics = newTranslation;
            _translationError = null;
          } else {
            // 使用本地化的错误消息
             _translationError = l10n.translationFailed(l10n.operationFailed); // 同上
          }
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // 使用本地化的错误消息
          _translationError = l10n.translationFailed(e.toString());
          _isTranslating = false;
        });
      }
    }
  }

  // 复制到剪贴板
  Future<void> _copyToClipboard(bool isWideScreen) async {
    HapticFeedback.lightImpact();
    // 获取 AppLocalizations 实例
    final l10n = AppLocalizations.of(context)!;

    bool copyAsSingleLine = false;
    try {
      copyAsSingleLine = await _settingsService.getCopyLyricsAsSingleLine();
    } catch (e) {
      print("Error reading copy setting: $e");
    }

    final lyricsToCopy = isWideScreen
        ? _currentTranslatedLyrics
        : (_showTranslated ? _currentTranslatedLyrics : widget.originalLyrics);

    String textToCopy;
    String snackBarMessage; // 本地化的提示消息

    if (!copyAsSingleLine) {
      textToCopy = lyricsToCopy;
      // 假设 arb 文件中有 lyricsCopied 键
      snackBarMessage = l10n.copiedToClipboard(l10n.lyricsTitle); // 使用通用 key
      // 或者使用特定的 key: snackBarMessage = l10n.lyricsCopied;
    } else {
      textToCopy = lyricsToCopy.replaceAll(RegExp(r'\s+'), ' ').trim();
      // 假设 arb 文件中有 lyricsCopiedAsSingleLine 键
      snackBarMessage = "${l10n.copiedToClipboard(l10n.lyricsTitle)} (${l10n.copyLyricsAsSingleLineTitle})"; // 组合消息
      // 或者使用特定的 key: snackBarMessage = l10n.lyricsCopiedAsSingleLine;
    }

    Clipboard.setData(ClipboardData(text: textToCopy));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        // 显示本地化的提示
        SnackBar(content: Text(snackBarMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 在 build 方法开头获取 AppLocalizations 实例，方便后续使用
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context); // 获取 Theme

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;

    // 使用本地化字符串决定窄屏时的标题
    final titleLabel = _showTranslated ? l10n.translationTitle : l10n.originalTitle;

    final screenHeight = MediaQuery.of(context).size.height;
    final initialHeight = screenHeight * 0.6;
    final maxHeight = screenHeight * 0.9;

    return DraggableScrollableSheet(
      initialChildSize: initialHeight / screenHeight,
      minChildSize: 0.3,
      maxChildSize: maxHeight / screenHeight,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          // ... (样式代码保持不变) ...
          decoration: BoxDecoration(
            color: theme.colorScheme.surface, // 使用 theme
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.2), // 使用 theme
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant, // 使用 theme
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Header Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 标题 - 使用本地化字符串
                    Text(
                      isWideScreen ? l10n.lyricsTitle : titleLabel,
                      style: theme.textTheme.titleLarge?.copyWith( // 使用 theme
                        color: theme.colorScheme.primary, // 使用 theme
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Action Buttons Row
                    Row(
                      children: [
                        // 翻译风格按钮 - Tooltip 使用本地化字符串
                        IconButton.filledTonal(
                          icon: Icon(_getTranslationStyleIcon(_currentStyle), size: 20),
                          // 调用辅助函数获取本地化的 Tooltip
                          tooltip: _getTranslationStyleTooltip(_currentStyle, l10n),
                          onPressed: _isTranslating ? null : _toggleTranslationStyle,
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // 重新翻译按钮 - Tooltip 使用本地化字符串
                        _isTranslating
                          ? SizedBox(
                              width: 36,
                              height: 36,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                // 可以考虑显示本地化的 "Retranslating..." 文本，但这通常用加载指示器代替
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton.filledTonal(
                              icon: const Icon(Icons.refresh, size: 20),
                              // 使用 l10n 获取 Tooltip
                              tooltip: l10n.retranslateButton,
                              onPressed: _handleReTranslate,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                        const SizedBox(width: 4),
                        // 复制按钮 - Tooltip 使用本地化字符串
                        IconButton.filledTonal(
                          icon: const Icon(Icons.copy, size: 20),
                          // 使用 l10n 获取 Tooltip
                          tooltip: l10n.copyToClipboard, // copyToClipboard key 似乎更通用
                          onPressed: () => _copyToClipboard(isWideScreen),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                        // 窄屏模式下的切换按钮 - Tooltip 使用本地化字符串
                        if (!isWideScreen) ...[
                           const SizedBox(width: 4),
                           _showTranslated
                            ? IconButton.filledTonal(
                                key: const ValueKey('toggle_button_selected'),
                                icon: const Icon(Icons.translate, size: 20),
                                // 使用 l10n 获取 Tooltip
                                tooltip: l10n.showOriginal,
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _showTranslated = !_showTranslated);
                                },
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(8),
                                  backgroundColor: theme.colorScheme.secondaryContainer, // 使用 theme
                                  foregroundColor: theme.colorScheme.onSecondaryContainer, // 使用 theme
                                ),
                              )
                            : IconButton(
                                key: const ValueKey('toggle_button_unselected'),
                                icon: const Icon(Icons.translate, size: 20),
                                // 使用 l10n 获取 Tooltip
                                tooltip: l10n.showTranslation,
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _showTranslated = !_showTranslated);
                                },
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(8),
                                  foregroundColor: theme.colorScheme.onSurfaceVariant, // 使用 theme
                                ),
                              ),
                        ],
                      ],
                    )
                  ],
                ),
              ),
              const Divider(),
              // 内容区域
              Expanded(
                child: isWideScreen
                    // 传递 l10n 和 theme 到布局构建函数
                    ? _buildWideLayout(context, scrollController, l10n, theme)
                    : _buildNarrowLayout(context, scrollController, l10n, theme),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- 布局构建函数 ---

  // 窄屏布局
  Widget _buildNarrowLayout(BuildContext context, ScrollController scrollController, AppLocalizations l10n, ThemeData theme) {
    final lyricsToShow = _showTranslated ? _currentTranslatedLyrics : widget.originalLyrics;
    // 使用本地化的辅助函数获取风格名称
    final styleDisplayName = _getTranslationStyleDisplayName(_currentStyle, l10n);
    // 使用本地化的归因文本和风格标签
    final attributionText = "${l10n.translatedByAttribution}\n${l10n.spiritLabel(styleDisplayName)}";

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          // ... (动画代码保持不变) ...
          transitionBuilder: (Widget child, Animation<double> animation) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            );
            final slideAnimation = Tween<Offset>(
              begin: const Offset(0.0, 0.05),
              end: Offset.zero,
            ).animate(curvedAnimation);
            return FadeTransition(
              opacity: curvedAnimation,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            );
          },
          child: Container(
            key: ValueKey<bool>(_showTranslated),
            alignment: Alignment.topLeft,
            child: SelectableText(
              // 如果有错误，显示错误信息 (已经本地化)；否则显示歌词
              _translationError ?? lyricsToShow,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.4,
                // 如果是错误信息，使用错误颜色
                color: _translationError != null ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 归因信息 (显示翻译且无错误时)
        if (_showTranslated && _translationError == null)
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome, // 或者考虑一个更合适的图标
                size: 24,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // 显示本地化的归因文本
                  attributionText,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis, // 保持省略号
                ),
              ),
            ],
          ),
        const SizedBox(height: 40), // 底部填充
      ],
    );
  }

  // 宽屏布局
  Widget _buildWideLayout(BuildContext context, ScrollController scrollController, AppLocalizations l10n, ThemeData theme) {
    // 使用本地化的辅助函数获取风格名称
    final styleDisplayName = _getTranslationStyleDisplayName(_currentStyle, l10n);
    // 使用本地化的归因文本和风格标签
    final attributionText = "${l10n.translatedByAttribution}\n${l10n.spiritLabel(styleDisplayName)}";

    const edgeInsets = EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    const bottomPadding = SizedBox(height: 40);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧: 翻译
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: edgeInsets,
            children: [
              Text(
                // 使用本地化的标题
                l10n.translationTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                // 如果有错误，显示错误信息 (已经本地化)；否则显示翻译歌词
                _translationError ?? _currentTranslatedLyrics,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.4,
                  // 如果是错误信息，使用错误颜色
                  color: _translationError != null ? theme.colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 16),
              // 归因信息 (无错误时)
              if (_translationError == null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        // 显示本地化的归因文本
                        attributionText,
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              bottomPadding,
            ],
          ),
        ),
        // 右侧: 原文
        Expanded(
          child: SingleChildScrollView(
             padding: edgeInsets.copyWith(left: 12),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   // 使用本地化的标题
                   l10n.originalTitle,
                   style: theme.textTheme.titleMedium?.copyWith(
                     fontWeight: FontWeight.w500,
                      color: theme.colorScheme.secondary // 使用次要颜色区分
                   ),
                 ),
                 const SizedBox(height: 8),
                 SelectableText(
                   widget.originalLyrics,
                   style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                 ),
                 bottomPadding,
               ],
             ),
          ),
        ),
      ],
    );
  }
}