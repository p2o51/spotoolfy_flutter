import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
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

// Poster color config
class AlbumPosterColorConfig {
  final ColorScheme colorScheme;

  const AlbumPosterColorConfig({required this.colorScheme});

  static AlbumPosterColorConfig getConfig(AlbumPosterStyle style, ColorScheme baseScheme) {
    switch (style) {
      case AlbumPosterStyle.style1:
        // Default style - uses base color scheme
        return AlbumPosterColorConfig(colorScheme: baseScheme);
      case AlbumPosterStyle.style2:
        // Inverted primary colors
        return AlbumPosterColorConfig(
          colorScheme: baseScheme.copyWith(
            surface: baseScheme.primaryContainer,
            onSurface: baseScheme.onPrimaryContainer,
            onSurfaceVariant: baseScheme.onPrimaryContainer.withValues(alpha: 0.7),
            primary: baseScheme.primary,
            primaryContainer: baseScheme.onPrimaryContainer.withValues(alpha: 0.2),
            surfaceContainerHighest: baseScheme.onPrimaryContainer.withValues(alpha: 0.1),
          ),
        );
      case AlbumPosterStyle.style3:
        // Tertiary based
        return AlbumPosterColorConfig(
          colorScheme: baseScheme.copyWith(
            surface: baseScheme.tertiary,
            onSurface: baseScheme.onTertiary,
            onSurfaceVariant: baseScheme.onTertiary.withValues(alpha: 0.7),
            primary: baseScheme.tertiaryContainer,
            primaryContainer: baseScheme.onTertiary.withValues(alpha: 0.2),
            surfaceContainerHighest: baseScheme.onTertiary.withValues(alpha: 0.1),
          ),
        );
      case AlbumPosterStyle.style4:
        // Tertiary container based
        return AlbumPosterColorConfig(
          colorScheme: baseScheme.copyWith(
            surface: baseScheme.tertiaryContainer,
            onSurface: baseScheme.tertiary,
            onSurfaceVariant: baseScheme.tertiary.withValues(alpha: 0.7),
            primary: baseScheme.tertiary,
            primaryContainer: baseScheme.tertiary.withValues(alpha: 0.2),
            surfaceContainerHighest: baseScheme.tertiary.withValues(alpha: 0.1),
          ),
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
        colorScheme: colorConfig.colorScheme,
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
      final result = await ImageGallerySaverPlus.saveImage(
        _posterBytes!,
        quality: 100,
        name: 'album_poster_${widget.albumName}_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        if (result['isSuccess'] == true) {
          Provider.of<NotificationService>(context, listen: false)
              .showSnackBar(AppLocalizations.of(context)!.exportSuccess);
        } else {
          Provider.of<NotificationService>(context, listen: false)
              .showErrorSnackBar(AppLocalizations.of(context)!.operationFailed);
        }
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
      await Share.shareXFiles(
        [XFile(_tempFilePath!)],
        text: widget.shareText,
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
                      colorConfig.colorScheme.surface,
                      colorConfig.colorScheme.surface.withValues(alpha: 0.8),
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
                            color: colorConfig.colorScheme.onSurface,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: 1,
                            width: 20,
                            color: colorConfig.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 1,
                            width: 16,
                            color: colorConfig.colorScheme.primary,
                          ),
                          const SizedBox(height: 1),
                          Container(
                            height: 1,
                            width: 24,
                            color: colorConfig.colorScheme.primary,
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
