import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../services/notification_service.dart';
import '../services/note_poster_service.dart';
import '../l10n/app_localizations.dart';

// Poster style enum
enum NotePosterStyle {
  style1,
  style2,
  style3,
  style4,
}

// Poster color config
class NotePosterColorConfig {
  final Color backgroundColor;
  final Color titleColor;
  final Color artistColor;
  final Color noteColor;
  final Color lyricsColor;
  final Color watermarkColor;

  const NotePosterColorConfig({
    required this.backgroundColor,
    required this.titleColor,
    required this.artistColor,
    required this.noteColor,
    required this.lyricsColor,
    required this.watermarkColor,
  });

  static NotePosterColorConfig getConfig(NotePosterStyle style, ColorScheme colorScheme) {
    switch (style) {
      case NotePosterStyle.style1:
        return NotePosterColorConfig(
          backgroundColor: colorScheme.onPrimaryContainer,
          titleColor: colorScheme.primaryContainer,
          artistColor: colorScheme.primary,
          noteColor: colorScheme.primaryContainer,
          lyricsColor: colorScheme.primaryContainer.withValues(alpha: 0.7),
          watermarkColor: colorScheme.primaryContainer,
        );
      case NotePosterStyle.style2:
        return NotePosterColorConfig(
          backgroundColor: colorScheme.primaryContainer,
          titleColor: colorScheme.onPrimaryContainer,
          artistColor: colorScheme.primary,
          noteColor: colorScheme.onPrimaryContainer,
          lyricsColor: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          watermarkColor: colorScheme.onPrimaryContainer,
        );
      case NotePosterStyle.style3:
        return NotePosterColorConfig(
          backgroundColor: colorScheme.tertiary,
          titleColor: colorScheme.onTertiary,
          artistColor: colorScheme.tertiaryContainer,
          noteColor: colorScheme.onTertiary,
          lyricsColor: colorScheme.onTertiary.withValues(alpha: 0.7),
          watermarkColor: colorScheme.onTertiary,
        );
      case NotePosterStyle.style4:
        return NotePosterColorConfig(
          backgroundColor: colorScheme.tertiaryContainer,
          titleColor: colorScheme.tertiary,
          artistColor: Color.lerp(colorScheme.tertiary, Colors.white, 0.5)!,
          noteColor: colorScheme.tertiary,
          lyricsColor: colorScheme.tertiary.withValues(alpha: 0.7),
          watermarkColor: colorScheme.tertiary,
        );
    }
  }
}

class NotePosterPreviewPage extends StatefulWidget {
  final String noteContent;
  final String? lyricsSnapshot;
  final String trackTitle;
  final String artistName;
  final String albumName;
  final int rating;
  final String? albumCoverUrl;

  const NotePosterPreviewPage({
    super.key,
    required this.noteContent,
    this.lyricsSnapshot,
    required this.trackTitle,
    required this.artistName,
    required this.albumName,
    required this.rating,
    this.albumCoverUrl,
  });

  @override
  State<NotePosterPreviewPage> createState() => _NotePosterPreviewPageState();
}

class _NotePosterPreviewPageState extends State<NotePosterPreviewPage> {
  bool _isLoading = true;
  bool _isOperating = false;
  Uint8List? _posterBytes;
  String? _tempFilePath;
  String? _errorMessage;
  NotePosterStyle _currentStyle = NotePosterStyle.style1;
  bool get _isBusy => _isLoading || _isOperating;

  @override
  void initState() {
    super.initState();
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
    final String uiFontFamily = theme.textTheme.bodyMedium?.fontFamily ?? 'Montserrat';

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _posterBytes = null;
      _tempFilePath = null;
    });

    try {
      final posterService = NotePosterService();
      final colorConfig = NotePosterColorConfig.getConfig(_currentStyle, theme.colorScheme);

      final bytes = await posterService.generatePosterData(
        noteContent: widget.noteContent,
        lyricsSnapshot: widget.lyricsSnapshot,
        trackTitle: widget.trackTitle,
        artistName: widget.artistName,
        albumName: widget.albumName,
        rating: widget.rating,
        albumCoverUrl: widget.albumCoverUrl,
        backgroundColor: colorConfig.backgroundColor,
        titleColor: colorConfig.titleColor,
        artistColor: colorConfig.artistColor,
        noteColor: colorConfig.noteColor,
        lyricsColor: colorConfig.lyricsColor,
        watermarkColor: colorConfig.watermarkColor,
        fontFamily: uiFontFamily,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = 'note_poster_preview_${DateTime.now().millisecondsSinceEpoch}.png';
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
    setState(() {
      _isOperating = true;
    });

    try {
      final posterService = NotePosterService();
      await posterService.savePosterFromBytes(_posterBytes!, widget.trackTitle);

      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showSnackBar(AppLocalizations.of(context)!.exportSuccess);
      }
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar('${AppLocalizations.of(context)!.operationFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  Future<void> _sharePoster() async {
    if (_tempFilePath == null || _isOperating) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isOperating = true;
    });

    try {
      final posterService = NotePosterService();
      await posterService.sharePosterFile(
        _tempFilePath!,
        '${widget.trackTitle} - ${widget.artistName}\n\n${widget.noteContent}',
      );
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar('${AppLocalizations.of(context)!.operationFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  void _changeStyle(NotePosterStyle newStyle) {
    if (_currentStyle == newStyle || _isLoading || _isOperating) return;

    HapticFeedback.selectionClick();
    setState(() {
      _currentStyle = newStyle;
    });

    _generatePoster();
  }

  Widget _buildStyleButton(NotePosterStyle style, String label) {
    final isSelected = _currentStyle == style;
    final theme = Theme.of(context);
    final colorConfig = NotePosterColorConfig.getConfig(style, theme.colorScheme);

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
                            color: colorConfig.noteColor,
                          ),
                          const SizedBox(height: 1),
                          Container(
                            height: 1,
                            width: 24,
                            color: colorConfig.noteColor,
                          ),
                        ],
                      ),
                    ),
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
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isBusy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isBusy) {
          HapticFeedback.mediumImpact();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.shareNote),
          backgroundColor: theme.colorScheme.surface,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: _buildPosterContent(theme),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStyleButton(NotePosterStyle.style1, '1'),
                        _buildStyleButton(NotePosterStyle.style2, '2'),
                        _buildStyleButton(NotePosterStyle.style3, '3'),
                        _buildStyleButton(NotePosterStyle.style4, '4'),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                            tooltip: AppLocalizations.of(context)!.shareNote,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterContent(ThemeData theme) {
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
