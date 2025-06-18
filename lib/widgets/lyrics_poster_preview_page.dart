import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart'; // 确保导入
// import 'package:share_plus/share_plus.dart'; // Removed unused import
import '../services/notification_service.dart';
import '../services/lyrics_poster_service.dart';
import '../l10n/app_localizations.dart';

// 海报样式枚举
enum PosterStyle {
  style1, // 默认样式
  style2, // 样式2
  style3, // 样式3
  style4, // 样式4
}

// 海报颜色配置
class PosterColorConfig {
  final Color backgroundColor;
  final Color titleColor;
  final Color artistColor;
  final Color lyricsColor;
  final Color watermarkColor;
  final Color separatorColor;

  const PosterColorConfig({
    required this.backgroundColor,
    required this.titleColor,
    required this.artistColor,
    required this.lyricsColor,
    required this.watermarkColor,
    required this.separatorColor,
  });

  // 根据样式和主题获取颜色配置
  static PosterColorConfig getConfig(PosterStyle style, ColorScheme colorScheme) {
    switch (style) {
      case PosterStyle.style1:
        // 样式1: 歌词正文，脚注与标题：Primary Container, 歌手：Primary, 背景：On Primary Container
        return PosterColorConfig(
          backgroundColor: colorScheme.onPrimaryContainer,
          titleColor: colorScheme.primaryContainer,
          artistColor: colorScheme.primary,
          lyricsColor: colorScheme.primaryContainer,
          watermarkColor: colorScheme.primaryContainer,
          separatorColor: colorScheme.outline.withValues(alpha: 0.3),
        );
      case PosterStyle.style2:
        // 样式2: 歌词正文，脚注与标题：On Primary Container, 歌手：Primary, 背景：Primary Container
        return PosterColorConfig(
          backgroundColor: colorScheme.primaryContainer,
          titleColor: colorScheme.onPrimaryContainer,
          artistColor: colorScheme.primary,
          lyricsColor: colorScheme.onPrimaryContainer,
          watermarkColor: colorScheme.onPrimaryContainer,
          separatorColor: colorScheme.outline.withValues(alpha: 0.3),
        );
      case PosterStyle.style3:
        // 样式3: 歌词正文，脚注与标题：On Tertiary, 歌手：Tertiary Container, 背景：Tertiary
        return PosterColorConfig(
          backgroundColor: colorScheme.tertiary,
          titleColor: colorScheme.onTertiary,
          artistColor: colorScheme.tertiaryContainer,
          lyricsColor: colorScheme.onTertiary,
          watermarkColor: colorScheme.onTertiary,
          separatorColor: colorScheme.outline.withValues(alpha: 0.3),
        );
      case PosterStyle.style4:
        // 样式4: 歌词正文，脚注与标题：Tertiary, 歌手：Tertiary * 0.5（混白色）, 背景：Tertiary Container
        return PosterColorConfig(
          backgroundColor: colorScheme.tertiaryContainer,
          titleColor: colorScheme.tertiary,
          artistColor: Color.lerp(colorScheme.tertiary, Colors.white, 0.5)!,
          lyricsColor: colorScheme.tertiary,
          watermarkColor: colorScheme.tertiary,
          separatorColor: colorScheme.outline.withValues(alpha: 0.3),
        );
    }
  }
}

class LyricsPosterPreviewPage extends StatefulWidget {
  final String lyrics;
  final String trackTitle;
  final String artistName;
  final String? albumCoverUrl;

  const LyricsPosterPreviewPage({
    super.key,
    required this.lyrics,
    required this.trackTitle,
    required this.artistName,
    this.albumCoverUrl,
  });

  @override
  State<LyricsPosterPreviewPage> createState() => _LyricsPosterPreviewPageState();
}

class _LyricsPosterPreviewPageState extends State<LyricsPosterPreviewPage> {
  bool _isLoading = true;
  bool _isOperating = false; // 保存或分享操作中
  Uint8List? _posterBytes; // Store image bytes directly
  String? _tempFilePath; // Store temporary file path for sharing
  String? _errorMessage;
  PosterStyle _currentStyle = PosterStyle.style1; // 当前选择的样式

  @override
  void initState() {
    super.initState();
    // _generatePoster is called after the first frame is built, to have access to Theme
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _generatePoster();
      }
    });
  }

  Future<void> _generatePoster() async {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    final theme = Theme.of(context);
    // 获取主题字体或指定默认字体
    final String uiFontFamily = theme.textTheme.bodyMedium?.fontFamily ?? 'Montserrat'; // Default to Montserrat if not found

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _posterBytes = null;
      _tempFilePath = null;
    });

    try {
      final posterService = LyricsPosterService();
      final colorConfig = PosterColorConfig.getConfig(_currentStyle, theme.colorScheme);
      
      final bytes = await posterService.generatePosterData(
        lyrics: widget.lyrics,
        trackTitle: widget.trackTitle,
        artistName: widget.artistName,
        albumCoverUrl: widget.albumCoverUrl,
        // 使用样式配置的颜色
        backgroundColor: colorConfig.backgroundColor,
        titleColor: colorConfig.titleColor,
        artistColor: colorConfig.artistColor,
        lyricsColor: colorConfig.lyricsColor,
        watermarkColor: colorConfig.watermarkColor,
        separatorColor: colorConfig.separatorColor,
        fontFamily: uiFontFamily, // 传递字体族
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = 'lyrics_poster_preview_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _posterBytes = bytes;
          _tempFilePath = file.path;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePoster() async {
    if (_posterBytes == null || _isOperating) return;

    HapticFeedback.mediumImpact();
    // final l10n = AppLocalizations.of(context); // Kept for context if needed later
    setState(() { _isOperating = true; });

    try {
      final posterService = LyricsPosterService();
      await posterService.savePosterFromBytes(_posterBytes!, widget.trackTitle);
      
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showSnackBar(AppLocalizations.of(context)!.exportSuccess);
      }
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar('${AppLocalizations.of(context)!.operationFailed}: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() { _isOperating = false; });
      }
    }
  }

  Future<void> _sharePoster() async {
    if (_tempFilePath == null || _isOperating) return;
    
    HapticFeedback.mediumImpact();
    // final l10n = AppLocalizations.of(context); // Kept for context if needed later
    setState(() { _isOperating = true; });

    try {
      final posterService = LyricsPosterService();
      await posterService.sharePosterFile(
        _tempFilePath!,
        '${widget.trackTitle} - ${widget.artistName}\n\n${widget.lyrics}',
      );
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar('${AppLocalizations.of(context)!.operationFailed}: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() { _isOperating = false; });
      }
    }
  }

  // 切换海报样式并重新生成
  void _changeStyle(PosterStyle newStyle) {
    if (_currentStyle == newStyle || _isLoading || _isOperating) return;
    
    HapticFeedback.selectionClick();
    setState(() {
      _currentStyle = newStyle;
    });
    
    _generatePoster();
  }

  // 构建样式选择按钮
  Widget _buildStyleButton(PosterStyle style, String label) {
    final isSelected = _currentStyle == style;
    final theme = Theme.of(context);
    final colorConfig = PosterColorConfig.getConfig(style, theme.colorScheme);
    
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: isSelected 
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isLoading || _isOperating ? null : () => _changeStyle(style),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.outline.withValues(alpha: 0.5),
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorConfig.backgroundColor,
                      colorConfig.backgroundColor.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // 预览小样本
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 2,
                            width: double.infinity,
                            color: colorConfig.titleColor,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: 1,
                            width: 20,
                            color: colorConfig.artistColor,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 1,
                            width: 16,
                            color: colorConfig.lyricsColor,
                          ),
                          const SizedBox(height: 1),
                          Container(
                            height: 1,
                            width: 24,
                            color: colorConfig.lyricsColor,
                          ),
                        ],
                      ),
                    ),
                    // 样式标签
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? theme.colorScheme.primary 
                              : theme.colorScheme.outline.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isSelected 
                                ? theme.colorScheme.onPrimary 
                                : theme.colorScheme.surface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context); // Keep for parts that work in _buildPosterContent
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.sharePoster),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _buildPosterContent(theme, l10n), // Pass l10n
              ),
            ),
          ),
          
          if (!_isLoading && _posterBytes != null)
            Container(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行：样式选择按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStyleButton(PosterStyle.style1, '1'),
                      _buildStyleButton(PosterStyle.style2, '2'),
                      _buildStyleButton(PosterStyle.style3, '3'),
                      _buildStyleButton(PosterStyle.style4, '4'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 第二行：保存和分享按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: IconButton.filledTonal(
                          onPressed: _isOperating ? null : _savePoster,
                          icon: const Icon(Icons.download),
                          tooltip: AppLocalizations.of(context)!.saveChanges,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: IconButton.filled(
                          onPressed: _isOperating ? null : _sharePoster,
                          icon: const Icon(Icons.share),
                          tooltip: AppLocalizations.of(context)!.sharePoster,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPosterContent(ThemeData theme, AppLocalizations? l10n) {
    if (_isLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.loadingGenerating,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.posterGenerationFailed(_errorMessage!),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _generatePoster,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context)!.retryButton),
          ),
        ],
      );
    }

    if (_posterBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _posterBytes!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Column(
            children: [
              Icon(
                Icons.broken_image,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.lyricsFailedToLoad,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
} 