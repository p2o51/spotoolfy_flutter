import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../services/notification_service.dart';
import '../services/album_rating_poster_service.dart';
import '../l10n/app_localizations.dart';

// Poster style enum
enum AlbumPosterStyle {
  style1,
  style2,
  style3,
  style4,
}

// Poster color config - matches lyrics/note poster structure
class AlbumPosterColorConfig {
  final Color backgroundColor;
  final Color titleColor;
  final Color artistColor;
  final Color scoreColor;
  final Color trackColor;
  final Color ratingColor;
  final Color watermarkColor;

  const AlbumPosterColorConfig({
    required this.backgroundColor,
    required this.titleColor,
    required this.artistColor,
    required this.scoreColor,
    required this.trackColor,
    required this.ratingColor,
    required this.watermarkColor,
  });

  static AlbumPosterColorConfig getConfig(AlbumPosterStyle style, ColorScheme colorScheme) {
    switch (style) {
      case AlbumPosterStyle.style1:
        // Style 1: Primary container based (dark bg)
        return AlbumPosterColorConfig(
          backgroundColor: colorScheme.onPrimaryContainer,
          titleColor: colorScheme.primaryContainer,
          artistColor: colorScheme.primary,
          scoreColor: colorScheme.primaryContainer,
          trackColor: colorScheme.primaryContainer,
          ratingColor: colorScheme.primaryContainer.withValues(alpha: 0.7),
          watermarkColor: colorScheme.primaryContainer,
        );
      case AlbumPosterStyle.style2:
        // Style 2: Primary container based (light bg)
        return AlbumPosterColorConfig(
          backgroundColor: colorScheme.primaryContainer,
          titleColor: colorScheme.onPrimaryContainer,
          artistColor: colorScheme.primary,
          scoreColor: colorScheme.onPrimaryContainer,
          trackColor: colorScheme.onPrimaryContainer,
          ratingColor: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          watermarkColor: colorScheme.onPrimaryContainer,
        );
      case AlbumPosterStyle.style3:
        // Style 3: Tertiary based (dark bg)
        return AlbumPosterColorConfig(
          backgroundColor: colorScheme.tertiary,
          titleColor: colorScheme.onTertiary,
          artistColor: colorScheme.tertiaryContainer,
          scoreColor: colorScheme.onTertiary,
          trackColor: colorScheme.onTertiary,
          ratingColor: colorScheme.onTertiary.withValues(alpha: 0.7),
          watermarkColor: colorScheme.onTertiary,
        );
      case AlbumPosterStyle.style4:
        // Style 4: Tertiary container based (light bg)
        return AlbumPosterColorConfig(
          backgroundColor: colorScheme.tertiaryContainer,
          titleColor: colorScheme.onTertiaryContainer,
          artistColor: colorScheme.onTertiaryContainer.withValues(alpha: 0.7),
          scoreColor: colorScheme.onTertiaryContainer,
          trackColor: colorScheme.onTertiaryContainer,
          ratingColor: colorScheme.onTertiaryContainer.withValues(alpha: 0.6),
          watermarkColor: colorScheme.onTertiaryContainer,
        );
    }
  }
}

class AlbumPosterPreviewPage extends StatefulWidget {
  final String albumName;
  final String artistLine;
  final double? averageScore;
  final int ratedTrackCount;
  final int totalTrackCount;
  final List<Map<String, dynamic>> tracks;
  final Map<String, int?> trackRatings;
  final Map<String, int?> trackRatingTimestamps;
  final String? albumCoverUrl;
  final String? insightsTitle;
  final String? shareText;

  const AlbumPosterPreviewPage({
    super.key,
    required this.albumName,
    required this.artistLine,
    required this.averageScore,
    required this.ratedTrackCount,
    required this.totalTrackCount,
    required this.tracks,
    required this.trackRatings,
    required this.trackRatingTimestamps,
    this.albumCoverUrl,
    this.insightsTitle,
    this.shareText,
  });

  @override
  State<AlbumPosterPreviewPage> createState() => _AlbumPosterPreviewPageState();
}

class _AlbumPosterPreviewPageState extends State<AlbumPosterPreviewPage> {
  bool _isLoading = true;
  bool _isOperating = false;
  Uint8List? _posterBytes;
  String? _tempFilePath;
  String? _errorMessage;
  AlbumPosterStyle _currentStyle = AlbumPosterStyle.style1;
  bool get _isBusy => _isLoading || _isOperating;

  final AlbumRatingPosterService _posterService = AlbumRatingPosterService();

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
      final colorConfig = AlbumPosterColorConfig.getConfig(_currentStyle, theme.colorScheme);

      final bytes = await _posterService.generatePosterData(
        albumName: widget.albumName,
        artistLine: widget.artistLine,
        averageScore: widget.averageScore,
        ratedTrackCount: widget.ratedTrackCount,
        totalTrackCount: widget.totalTrackCount,
        tracks: widget.tracks,
        trackRatings: widget.trackRatings,
        trackRatingTimestamps: widget.trackRatingTimestamps,
        backgroundColor: colorConfig.backgroundColor,
        titleColor: colorConfig.titleColor,
        artistColor: colorConfig.artistColor,
        scoreColor: colorConfig.scoreColor,
        trackColor: colorConfig.trackColor,
        ratingColor: colorConfig.ratingColor,
        watermarkColor: colorConfig.watermarkColor,
        albumCoverUrl: widget.albumCoverUrl,
        fontFamily: uiFontFamily,
        insightsTitle: widget.insightsTitle,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = 'album_poster_preview_${DateTime.now().millisecondsSinceEpoch}.png';
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
      await _posterService.savePosterFromBytes(_posterBytes!, widget.albumName);

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
      await _posterService.sharePosterFile(
        _tempFilePath!,
        widget.shareText ?? '${widget.albumName} - ${widget.artistLine}',
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

  void _changeStyle(AlbumPosterStyle newStyle) {
    if (_currentStyle == newStyle || _isLoading || _isOperating) return;

    HapticFeedback.selectionClick();
    setState(() {
      _currentStyle = newStyle;
    });

    _generatePoster();
  }

  Widget _buildStyleButton(AlbumPosterStyle style, String label) {
    final isSelected = _currentStyle == style;
    final theme = Theme.of(context);
    final colorConfig = AlbumPosterColorConfig.getConfig(style, theme.colorScheme);

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
                            color: colorConfig.scoreColor,
                          ),
                          const SizedBox(height: 1),
                          Container(
                            height: 1,
                            width: 24,
                            color: colorConfig.trackColor,
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
          title: Text(AppLocalizations.of(context)!.sharePoster),
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
                        _buildStyleButton(AlbumPosterStyle.style1, '1'),
                        _buildStyleButton(AlbumPosterStyle.style2, '2'),
                        _buildStyleButton(AlbumPosterStyle.style3, '3'),
                        _buildStyleButton(AlbumPosterStyle.style4, '4'),
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
