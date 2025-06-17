import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard and HapticFeedback
import 'package:logger/logger.dart';
import '../services/settings_service.dart'; // Import TranslationStyle and SettingsService
import 'package:provider/provider.dart';
import '../providers/local_database_provider.dart';
// import '../models/translation.dart'; // Unused import
// 导入 AppLocalizations 类，用于访问本地化字符串
import '../l10n/app_localizations.dart';

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

final logger = Logger();

// 将类名更改为 TranslationResultPage，以反映其新用途
class TranslationResultPage extends StatefulWidget {
  final String originalLyrics;
  final String translatedLyrics;
  final Future<String?> Function() onReTranslate;
  final TranslationStyle translationStyle;
  final String trackId;

  const TranslationResultPage({
    super.key,
    required this.originalLyrics,
    required this.translatedLyrics,
    required this.onReTranslate,
    required this.translationStyle,
    required this.trackId,
  });

  @override
  State<TranslationResultPage> createState() => _TranslationResultPageState();
}

class _TranslationResultPageState extends State<TranslationResultPage> {
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
      if (!mounted) return;
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
      logger.d("Error reading copy setting: $e");
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

    // 使用 Scaffold 替换
    return Scaffold(
      appBar: AppBar(
        // 标题 - 使用本地化字符串
        title: Text(isWideScreen ? l10n.lyricsTitle : titleLabel),
        leading: IconButton( // 添加返回按钮
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // 翻译风格按钮 - Tooltip 使用本地化字符串
          IconButton( // 改为普通 IconButton 可能更合适在 AppBar
            icon: Icon(_getTranslationStyleIcon(_currentStyle), size: 20),
            // 调用辅助函数获取本地化的 Tooltip
            tooltip: _getTranslationStyleTooltip(_currentStyle, l10n),
            onPressed: _isTranslating ? null : _toggleTranslationStyle,
            // style: IconButton.styleFrom( // 移除 filledTonal 样式
            //   padding: const EdgeInsets.all(8),
            // ),
          ),
          // 重新翻译按钮 - Tooltip 使用本地化字符串
          _isTranslating
            ? const Padding( // 保持加载指示器
                padding: EdgeInsets.all(14.0), // 调整 padding
                child: SizedBox(
                  width: 20, // 调整大小
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                // 使用 l10n 获取 Tooltip
                tooltip: l10n.retranslateButton,
                onPressed: _handleReTranslate,
                // style: IconButton.styleFrom( // 移除 filledTonal 样式
                //   padding: const EdgeInsets.all(8),
                // ),
              ),
          // 复制按钮 - Tooltip 使用本地化字符串
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            // 使用 l10n 获取 Tooltip
            tooltip: l10n.copyToClipboard, // copyToClipboard key 似乎更通用
            onPressed: () => _copyToClipboard(isWideScreen),
            // style: IconButton.styleFrom( // 移除 filledTonal 样式
            //   padding: const EdgeInsets.all(8),
            // ),
          ),
          // 窄屏模式下的切换按钮 - Tooltip 使用本地化字符串
          if (!isWideScreen)
            _showTranslated
              ? IconButton(
                  key: const ValueKey('toggle_button_selected'),
                  icon: const Icon(Icons.translate, size: 20),
                  // 使用 l10n 获取 Tooltip
                  tooltip: l10n.showOriginal,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _showTranslated = !_showTranslated);
                  },
                  // style: IconButton.styleFrom( // 移除 filledTonal 样式
                  //   padding: const EdgeInsets.all(8),
                  //   // 保留视觉区分可能仍然有用，但可能不需要背景色
                  //   // backgroundColor: theme.colorScheme.secondaryContainer,
                  //   // foregroundColor: theme.colorScheme.onSecondaryContainer,
                  //   color: theme.colorScheme.primary, // 突出显示选中的状态
                  // ),
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
                  // style: IconButton.styleFrom( // 移除 filledTonal 样式
                  //   padding: const EdgeInsets.all(8),
                  //   foregroundColor: theme.colorScheme.onSurfaceVariant, // 使用 theme
                  // ),
                ),
          const SizedBox(width: 8), // 添加一点右边距
        ],
      ),
      // Body 使用原有的布局逻辑，但不再需要 ScrollController
      body: isWideScreen
          ? _buildWideLayout(context, l10n, theme) // 移除 scrollController
          : _buildNarrowLayout(context, l10n, theme), // 移除 scrollController
    );
  }

  // --- 布局构建函数 ---

  // 窄屏布局
  // 移除 scrollController 参数
  Widget _buildNarrowLayout(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    final lyricsToShow = _showTranslated ? _currentTranslatedLyrics : widget.originalLyrics;
    // 使用本地化的辅助函数获取风格名称
    final styleDisplayName = _getTranslationStyleDisplayName(_currentStyle, l10n);
    // 使用本地化的归因文本和风格标签
    final attributionText = "${l10n.translatedByAttribution}\n${l10n.spiritLabel(styleDisplayName)}";

    return ListView( // 使用 ListView 保持可滚动性
      // controller: scrollController, // 移除 controller
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
  // 移除 scrollController 参数
  Widget _buildWideLayout(BuildContext context, AppLocalizations l10n, ThemeData theme) {
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
          child: ListView( // 使用 ListView 保持可滚动性
            // controller: scrollController, // 移除 controller
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
          child: SingleChildScrollView( // 右侧保持 SingleChildScrollView
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