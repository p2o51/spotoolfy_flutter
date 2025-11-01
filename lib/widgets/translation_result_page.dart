import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard and HapticFeedback
import 'package:logger/logger.dart';
import '../services/settings_service.dart'; // Import TranslationStyle and SettingsService
import '../models/translation_load_result.dart';
// import '../models/translation.dart'; // Unused import
// 导入 AppLocalizations 类，用于访问本地化字符串
import '../l10n/app_localizations.dart';

// --- 本地化辅助函数 ---

// 使用 AppLocalizations 获取翻译风格的显示名称
String _getTranslationStyleDisplayName(
    TranslationStyle style, AppLocalizations l10n) {
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
String _getTranslationStyleTooltip(
    TranslationStyle style, AppLocalizations l10n) {
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
  final TranslationStyle initialStyle;
  final Future<TranslationLoadResult> Function({
    bool forceRefresh,
    TranslationStyle? style,
  }) loadTranslation;
  final Future<TranslationLoadResult>? initialData;

  const TranslationResultPage({
    super.key,
    required this.originalLyrics,
    required this.initialStyle,
    required this.loadTranslation,
    this.initialData,
  });

  @override
  State<TranslationResultPage> createState() => _TranslationResultPageState();
}

class _TranslationResultPageState extends State<TranslationResultPage> {
  bool _isTranslating = false;
  bool _isInitialLoading = true;
  String? _translationError;
  String? _currentCleanTranslatedLyrics;
  late TranslationStyle _currentStyle;
  Future<TranslationLoadResult>? _pendingInitialFuture;
  bool _showTranslated = true; // 默认显示翻译后的歌词 (窄屏模式下)

  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _currentStyle = widget.initialStyle;
    _pendingInitialFuture = widget.initialData;
    _loadInitialTranslation();
  }

  Future<void> _loadInitialTranslation() async {
    setState(() {
      _isInitialLoading = true;
      _translationError = null;
    });

    try {
      final future =
          _pendingInitialFuture ?? widget.loadTranslation(style: _currentStyle);
      _pendingInitialFuture = null;
      final result = await future;
      if (!mounted) return;
      setState(() {
        _currentCleanTranslatedLyrics = result.cleanedTranslatedLyrics;
        _currentStyle = result.style;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translationError = e.toString();
        _isInitialLoading = false;
      });
    }
  }

  // 切换翻译风格
  Future<void> _toggleTranslationStyle() async {
    if (_isTranslating || _isInitialLoading) return;

    final l10n = AppLocalizations.of(context)!;
    final nextStyle = _getNextTranslationStyle(_currentStyle);

    setState(() {
      _isTranslating = true;
      _translationError = null;
    });

    try {
      HapticFeedback.lightImpact();
      await _settingsService.saveTranslationStyle(nextStyle);
      final result = await widget.loadTranslation(style: nextStyle);
      if (!mounted) return;
      setState(() {
        _currentStyle = result.style;
        _currentCleanTranslatedLyrics = result.cleanedTranslatedLyrics;
        _isTranslating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translationError = l10n.translationFailed(e.toString());
        _isTranslating = false;
      });
    }
  }

  // 重新翻译
  Future<void> _handleReTranslate() async {
    if (_isTranslating) return;

    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _isTranslating = true;
      _translationError = null;
    });

    try {
      HapticFeedback.lightImpact();
      final result = await widget.loadTranslation(
        forceRefresh: true,
        style: _currentStyle,
      );
      if (!mounted) return;
      setState(() {
        _currentCleanTranslatedLyrics = result.cleanedTranslatedLyrics;
        _translationError = null;
        _isTranslating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translationError = l10n.translationFailed(e.toString());
        _isTranslating = false;
      });
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

    final String? lyricsToCopySource = isWideScreen
        ? _currentCleanTranslatedLyrics
        : (_showTranslated
            ? _currentCleanTranslatedLyrics
            : widget.originalLyrics);

    if (lyricsToCopySource == null || lyricsToCopySource.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translationFailed(l10n.operationFailed))),
        );
      }
      return;
    }

    final lyricsToCopy = lyricsToCopySource;

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
      snackBarMessage =
          "${l10n.copiedToClipboard(l10n.lyricsTitle)} (${l10n.copyLyricsAsSingleLineTitle})"; // 组合消息
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
    final bool translationAvailable = _currentCleanTranslatedLyrics != null;
    final bool hasError = _translationError != null;
    final bool isBusy = _isInitialLoading || _isTranslating;

    final bool canCopy = isWideScreen
        ? (!_isInitialLoading && translationAvailable && !hasError)
        : (_showTranslated
            ? (!_isInitialLoading && translationAvailable && !hasError)
            : true);

    // titleLabel variable removed as unused
    // final titleLabel = _showTranslated ? l10n.translationTitle : l10n.originalTitle;

    // 使用 Scaffold 替换
    return Scaffold(
      appBar: AppBar(
        title: Text(isWideScreen
            ? l10n.lyricsTitle
            : (_showTranslated ? l10n.translationTitle : l10n.originalTitle)),
        leading: IconButton(
          // 添加返回按钮
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // 翻译风格按钮 - Tooltip 使用本地化字符串
          if (isBusy)
            const Padding(
              // 保持加载指示器
              padding: EdgeInsets.all(14.0), // 调整 padding
              child: SizedBox(
                width: 20, // 调整大小
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              // 改为普通 IconButton 可能更合适在 AppBar
              icon: Icon(_getTranslationStyleIcon(_currentStyle), size: 20),
              // 调用辅助函数获取本地化的 Tooltip
              tooltip: _getTranslationStyleTooltip(_currentStyle, l10n),
              onPressed: _toggleTranslationStyle,
            ),
          if (!isBusy)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              // 使用 l10n 获取 Tooltip
              tooltip: l10n.retranslateButton,
              onPressed: _handleReTranslate,
            ),
          // 复制按钮 - Tooltip 使用本地化字符串
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            // 使用 l10n 获取 Tooltip
            tooltip: l10n.copyToClipboard, // copyToClipboard key 似乎更通用
            onPressed: canCopy ? () => _copyToClipboard(isWideScreen) : null,
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
      body: _isInitialLoading
          ? const Center(child: CircularProgressIndicator())
          : isWideScreen
              ? _buildWideLayout(context, l10n, theme) // 移除 scrollController
              : _buildNarrowLayout(context, l10n, theme), // 移除 scrollController
    );
  }

  // --- 布局构建函数 ---

  // 窄屏布局
  // 移除 scrollController 参数
  Widget _buildNarrowLayout(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    final lyricsToShow =
        _showTranslated ? _currentCleanTranslatedLyrics : widget.originalLyrics;
    // 使用本地化的辅助函数获取风格名称
    final styleDisplayName =
        _getTranslationStyleDisplayName(_currentStyle, l10n);
    // 使用本地化的归因文本和风格标签
    final attributionText =
        "${l10n.translatedByAttribution}\n${l10n.spiritLabel(styleDisplayName)}";

    return ListView(
      // 使用 ListView 保持可滚动性
      // controller: scrollController, // 移除 controller
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        Container(
          alignment: Alignment.topLeft,
          child: SelectableText(
            _translationError ?? lyricsToShow ?? '',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.4,
              color: _translationError != null ? theme.colorScheme.error : null,
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
  Widget _buildWideLayout(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    // 使用本地化的辅助函数获取风格名称
    final styleDisplayName =
        _getTranslationStyleDisplayName(_currentStyle, l10n);
    // 使用本地化的归因文本和风格标签
    final attributionText =
        "${l10n.translatedByAttribution}\n${l10n.spiritLabel(styleDisplayName)}";

    const edgeInsets = EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    const bottomPadding = SizedBox(height: 40);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧: 翻译
        Expanded(
          child: ListView(
            // 使用 ListView 保持可滚动性
            // controller: scrollController, // 移除 controller
            padding: edgeInsets,
            children: [
              Text(
                // 使用本地化的标题
                l10n.translationTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              SelectableText(
                // 如果有错误，显示错误信息 (已经本地化)；否则显示翻译歌词
                _translationError ?? _currentCleanTranslatedLyrics ?? '',
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.4,
                  // 如果是错误信息，使用错误颜色
                  color: _translationError != null
                      ? theme.colorScheme.error
                      : null,
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
            // 右侧保持 SingleChildScrollView
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
