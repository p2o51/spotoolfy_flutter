import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/local_database_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/album_insights_service.dart';
import '../services/spotify_service.dart';
import '../utils/responsive.dart';
import '../widgets/album_poster_preview_page.dart';
import '../widgets/materialui.dart';
import '../widgets/time_machine_carousel.dart'; // For AlbumColorExtractor

class AlbumPage extends StatefulWidget {
  final String albumId;

  const AlbumPage({super.key, required this.albumId});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Map<String, dynamic>? _albumData;
  List<Map<String, dynamic>> _tracks = [];
  Map<String, int?> _trackRatings = {};
  Map<String, int?> _trackRatingTimestamps = {};
  final Map<String, int> _pendingTrackRatings = {};
  final Set<String> _updatingTracks = {};
  bool _isLoading = true;
  bool _showQuickSelectors = false;
  String? _errorMessage;
  final AlbumInsightsService _albumInsightsService = AlbumInsightsService();
  Map<String, dynamic>? _albumInsights;
  DateTime? _albumInsightsGeneratedAt;
  String? _albumInsightsError;
  bool _isGeneratingAlbumInsights = false;
  bool _isAlbumInsightsExpanded = false;
  bool _isSavingPendingRatings = false;

  // Cached computed values
  double? _cachedAverageScore;
  int _cachedRatedTrackCount = 0;

  // Dynamic color from album cover
  ColorScheme? _albumColorScheme;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      final spotify = context.read<SpotifyProvider>();
      final localDb = context.read<LocalDatabaseProvider>();

      final album = await spotify.fetchAlbumDetails(
        widget.albumId,
        forceRefresh: forceRefresh,
      );

      final trackSection =
          (album['tracks'] as Map<String, dynamic>? ?? const {});
      final items = trackSection['items'] as List? ?? const [];
      final tracks = <Map<String, dynamic>>[
        for (final item in items)
          if (item is Map<String, dynamic>) Map<String, dynamic>.from(item)
      ];

      final trackIds = tracks
          .map((track) => track['id'])
          .whereType<String>()
          .toList(growable: false);

      final latestRatingsWithTimestamp =
          await localDb.getLatestRatingsWithTimestampForTracks(trackIds);
      final normalizedRatings = <String, int?>{};
      final normalizedTimestamps = <String, int?>{};

      for (final id in trackIds) {
        final ratingData = latestRatingsWithTimestamp[id];
        normalizedRatings[id] = ratingData?['rating'] as int?;
        normalizedTimestamps[id] = ratingData?['recordedAt'] as int?;
      }

      if (!mounted) return;
      setState(() {
        _albumData = album;
        _tracks = tracks;
        _trackRatings = normalizedRatings;
        _trackRatingTimestamps = normalizedTimestamps;
        _isLoading = false;
        _pendingTrackRatings.clear();
        _updateComputedValues();
      });
      _loadCachedAlbumInsights();
      _extractAlbumColors();
    } catch (e) {
      if (!mounted) return;
      final message = e is SpotifyAuthException ? e.message : e.toString();
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePlayAlbum() async {
    final albumId = (_albumData?['id'] as String?) ?? widget.albumId;
    try {
      final spotify = context.read<SpotifyProvider>();
      await spotify.playContext(type: 'album', id: albumId);
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToPlayAlbum(e.toString()))),
      );
    }
  }

  Future<void> _handleShareAlbumPoster() async {
    if (_cachedRatedTrackCount == 0) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.rateAtLeastOneSongForPoster)),
      );
      return;
    }

    final albumData = _albumData;
    if (albumData == null) {
      return;
    }

    HapticFeedback.mediumImpact();

    final l10n = AppLocalizations.of(context)!;
    final albumName = albumData['name'] as String? ?? l10n.unknownAlbum;
    final artistLine = _formatArtists(context, albumData['artists']);
    final coverUrl = _extractCoverUrl();
    final rawInsightsTitle = _albumInsights?['title'] as String?;
    final normalizedInsightsTitle = rawInsightsTitle?.trim();
    final insightsTitle = (normalizedInsightsTitle != null &&
            normalizedInsightsTitle.isNotEmpty)
        ? normalizedInsightsTitle
        : null;
    final shareText = _buildSharePosterMessage(
      albumName: albumName,
      artistLine: artistLine,
      averageScore: _cachedAverageScore,
      ratedTrackCount: _cachedRatedTrackCount,
      totalTrackCount: _tracks.length,
    );

    // Navigate to poster preview page
    ResponsiveNavigation.showSecondaryPage(
      context: context,
      child: AlbumPosterPreviewPage(
        albumName: albumName,
        artistLine: artistLine,
        averageScore: _cachedAverageScore,
        ratedTrackCount: _cachedRatedTrackCount,
        totalTrackCount: _tracks.length,
        tracks: _tracks,
        trackRatings: _trackRatings,
        trackRatingTimestamps: _trackRatingTimestamps,
        albumCoverUrl: coverUrl,
        insightsTitle: insightsTitle,
        shareText: shareText,
      ),
      preferredMode: SecondaryPageMode.fullScreen,
    );
  }

  Future<void> _handlePlayTrack(
      Map<String, dynamic> track, int trackIndex) async {
    final trackUri = track['uri'] as String? ??
        (track['id'] is String ? 'spotify:track:${track['id']}' : null);
    final albumUri = (_albumData?['uri'] as String?) ?? '';
    final albumId = (_albumData?['id'] as String?) ?? widget.albumId;
    final derivedContextUri = albumUri.isNotEmpty
        ? albumUri
        : (albumId.isNotEmpty ? 'spotify:album:$albumId' : null);

    if (trackUri == null) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cannotPlayMissingTrackLink)),
      );
      return;
    }

    try {
      final spotify = context.read<SpotifyProvider>();
      if (derivedContextUri != null) {
        await spotify.playTrackInContext(
          contextUri: derivedContextUri,
          trackUri: trackUri,
          offsetIndex: trackIndex,
        );
      } else {
        await spotify.playTrack(trackUri: trackUri);
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToPlaySong(e.toString()))),
      );
    }
  }

  Future<void> _extractAlbumColors() async {
    final coverUrl = _extractCoverUrl();
    if (coverUrl == null) return;

    final brightness = Theme.of(context).brightness;
    final colorScheme = await AlbumColorExtractor.extractFromUrl(coverUrl, brightness);

    if (mounted && colorScheme != null) {
      setState(() {
        _albumColorScheme = colorScheme;
      });
    }
  }

  Future<void> _loadCachedAlbumInsights() async {
    final albumId = _albumData?['id'] as String? ?? widget.albumId;
    if (albumId.isEmpty) {
      return;
    }
    try {
      final ratingsSignature = _buildRatingsSignature();
      final cached = await _albumInsightsService.getCachedAlbumInsights(
        albumId: albumId,
        ratingsSignature: ratingsSignature,
      );
      if (!mounted || cached == null) {
        return;
      }
      final generatedAt =
          DateTime.tryParse(cached['generatedAt'] as String? ?? '');
      setState(() {
        _albumInsights = cached['insights'] as Map<String, dynamic>?;
        _albumInsightsGeneratedAt = generatedAt;
        _albumInsightsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _albumInsightsError = l10n.failedToLoadCache(e.toString());
      });
    }
  }

  Future<void> _generateAlbumInsights() async {
    final albumData = _albumData;
    if (albumData == null || _tracks.isEmpty || _isGeneratingAlbumInsights) {
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      _isGeneratingAlbumInsights = true;
      _albumInsightsError = null;
    });

    try {
      final albumId = albumData['id'] as String? ?? widget.albumId;
      final ratingsSignature = _buildRatingsSignature();
      final result = await _albumInsightsService.generateAlbumInsights(
        albumId: albumId,
        albumData: albumData,
        tracks: _tracks,
        trackRatings: _trackRatings,
        averageScore: _cachedAverageScore,
        ratedTrackCount: _cachedRatedTrackCount,
        ratingsSignature: ratingsSignature,
      );

      if (!mounted) return;
      final generatedAt =
          DateTime.tryParse(result['generatedAt'] as String? ?? '');
      setState(() {
        _albumInsights = result['insights'] as Map<String, dynamic>?;
        _albumInsightsGeneratedAt = generatedAt;
        _albumInsightsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _albumInsightsError = l10n.failedToGenerateAlbumInsights(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingAlbumInsights = false;
        });
      }
    }
  }

  Future<void> _handleQuickRating(
    Map<String, dynamic> track,
    int rating,
  ) async {
    final trackId = track['id'] as String?;
    if (trackId == null || _updatingTracks.contains(trackId)) {
      return;
    }

    final albumName = _albumData?['name'] as String? ?? '';
    final images = _albumData?['images'] as List? ?? const [];
    final coverUrl = images.isNotEmpty
        ? (images.first as Map<String, dynamic>)['url'] as String?
        : null;
    final artistNames = _formatArtists(context, track['artists']);
    final trackName = track['name'] as String? ?? '';

    setState(() {
      _updatingTracks.add(trackId);
    });

    try {
      final localDb = context.read<LocalDatabaseProvider>();
      await localDb.quickRateTrack(
        trackId: trackId,
        trackName: trackName,
        artistName: artistNames,
        albumName: albumName,
        albumCoverUrl: coverUrl,
        rating: rating,
      );

      if (!mounted) return;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _trackRatings = Map<String, int?>.from(_trackRatings)
          ..[trackId] = rating;
        _trackRatingTimestamps = Map<String, int?>.from(_trackRatingTimestamps)
          ..[trackId] = timestamp;
        _pendingTrackRatings.remove(trackId);
        _isAlbumInsightsExpanded = false;
        _updateComputedValues();
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToSaveRating(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingTracks.remove(trackId);
        });
      }
    }
  }

  void _handleRatingDraftChange(String trackId, int rating) {
    if (_trackRatings[trackId] == rating) {
      setState(() {
        _pendingTrackRatings.remove(trackId);
      });
    } else {
      setState(() {
        _pendingTrackRatings[trackId] = rating;
      });
    }
  }

  void _updateComputedValues() {
    final values = <double>[];
    var count = 0;
    for (final track in _tracks) {
      final trackId = track['id'] as String?;
      if (trackId == null) continue;
      final rating = _trackRatings[trackId];
      if (rating != null) {
        count++;
        values.add(_mapRatingToScore(rating));
      }
    }
    _cachedRatedTrackCount = count;
    if (values.isEmpty) {
      _cachedAverageScore = null;
    } else {
      final total = values.reduce((value, element) => value + element);
      _cachedAverageScore = total / values.length;
    }
  }

  String _buildRatingsSignature() {
    final entries = <String>[];
    for (final track in _tracks) {
      final trackId = track['id'] as String?;
      if (trackId == null) continue;
      final rating = _trackRatings[trackId];
      entries.add('$trackId:${rating ?? 'null'}');
    }
    return entries.join('|');
  }

  String _buildSharePosterMessage({
    required String albumName,
    required String artistLine,
    required double? averageScore,
    required int ratedTrackCount,
    required int totalTrackCount,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final normalizedArtist =
        artistLine.isNotEmpty ? artistLine : l10n.unknownArtist;
    final averageLabel =
        averageScore != null ? averageScore.toStringAsFixed(1) : l10n.noRating;
    return l10n.shareAlbumMessage(
      albumName,
      normalizedArtist,
      averageLabel,
      ratedTrackCount,
      totalTrackCount,
    );
  }

  Map<String, dynamic>? _findTrackById(String trackId) {
    for (final track in _tracks) {
      if (track['id'] == trackId) {
        return track;
      }
    }
    return null;
  }

  Future<void> _savePendingRatings() async {
    if (_pendingTrackRatings.isEmpty || _isSavingPendingRatings) {
      return;
    }

    setState(() {
      _isSavingPendingRatings = true;
    });

    try {
      final entries = List<MapEntry<String, int>>.from(
        _pendingTrackRatings.entries,
      );

      for (final entry in entries) {
        final track = _findTrackById(entry.key);
        if (track == null) {
          _pendingTrackRatings.remove(entry.key);
          continue;
        }
        await _handleQuickRating(track, entry.value);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPendingRatings = false;
          _pendingTrackRatings.clear();
          _showQuickSelectors = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_albumData?['name'] as String? ?? l10n.albumDetails),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshAlbum,
            onPressed: () => _loadAlbum(forceRefresh: true),
          ),
        ],
      ),
      body: RepaintBoundary(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadAlbum(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildHeader(theme),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1.0,
                child: child,
              ),
              child: !_showQuickSelectors ||
                      (_pendingTrackRatings.isEmpty && !_isSavingPendingRatings)
                  ? const SizedBox.shrink()
                  : Padding(
                      key: const ValueKey('pending-save-bar'),
                      padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 12.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _pendingTrackRatings.isEmpty ||
                                  _isSavingPendingRatings
                              ? null
                              : _savePendingRatings,
                          icon: _isSavingPendingRatings
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            _isSavingPendingRatings
                                ? AppLocalizations.of(context)!.savingChanges
                                : AppLocalizations.of(context)!.saveAllChanges,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildInsightsTitle(theme),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  final trackId = track['id'] as String?;
                  final currentRating =
                      trackId != null ? _trackRatings[trackId] : null;
                  final pendingRating =
                      trackId != null ? _pendingTrackRatings[trackId] : null;
                  final ratingTimestamp =
                      trackId != null ? _trackRatingTimestamps[trackId] : null;
                  final isUpdating =
                      trackId != null && _updatingTracks.contains(trackId);
                  return Column(
                    children: [
                      _AlbumTrackTile(
                        index: index,
                        track: track,
                        rating: currentRating,
                        pendingRating: pendingRating,
                        ratingTimestamp: ratingTimestamp,
                        showQuickSelectors: _showQuickSelectors,
                        isUpdating: isUpdating,
                        onTap: () => _handlePlayTrack(track, index),
                        onRate: (newRating) {
                          if (trackId != null) {
                            _handleRatingDraftChange(trackId, newRating);
                          }
                        },
                      ),
                      if (index != _tracks.length - 1)
                        const SizedBox(height: 8),
                    ],
                  );
                },
                childCount: _tracks.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final coverUrl = _extractCoverUrl();
    final albumName = _albumData?['name'] as String? ?? '';
    final artists = _albumData?['artists'] as List? ?? const [];
    final releaseYear = _extractReleaseYear();
    final trackCount = _tracks.length;
    final averageScore = _cachedAverageScore;

    final hasInsights = _albumInsights != null;
    final insightsTitleRaw = (_albumInsights?['title'] as String?)?.trim() ?? '';
    final hasInsightsTitle = insightsTitleRaw.isNotEmpty;
    final hasError = _albumInsightsError != null;
    final showExpandButton =
        hasInsights || hasError || _isGeneratingAlbumInsights;
    final l10n = AppLocalizations.of(context)!;
    final generatedAtLabel = _formatGeneratedAt();
    final statusText = _albumInsightsError != null
        ? l10n.failedToGenerateAlbumInsightsStatus
        : hasInsights
            ? (generatedAtLabel ?? l10n.albumInsightReadyStatus)
            : l10n.clickToGenerateAlbumInsights;

    // 使用动态提取的颜色
    final albumColors = _albumColorScheme ?? theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      width: 160,
                      height: 160,
                      memCacheWidth: 320, // Optimize memory usage (2x for retina)
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 160,
                      height: 160,
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.album_outlined,
                        size: 64,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    albumName,
                    style: theme.textTheme.titleLarge,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _buildMetaLine(artists, releaseYear, trackCount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _handlePlayAlbum,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(l10n.playAlbum),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        child: IconButton(
                          onPressed: () {
                            if (_cachedRatedTrackCount == 0) {
                              final l10n = AppLocalizations.of(context)!;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.rateAtLeastOneSongForPoster),
                                ),
                              );
                              return;
                            }
                            _handleShareAlbumPoster();
                          },
                          icon: Icon(
                            Icons.ios_share_rounded,
                            color: _cachedRatedTrackCount == 0
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                : theme.colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          tooltip: _cachedRatedTrackCount == 0
                              ? l10n.rateAtLeastOneSongFirst
                              : l10n.shareAlbumRatingPoster,
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 40, // 与 FilledButton 相同的高度
                        width: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        child: IconButton(
                          onPressed: _tracks.isEmpty
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    if (_showQuickSelectors) {
                                      _showQuickSelectors = false;
                                      _pendingTrackRatings.clear();
                                    } else {
                                      _showQuickSelectors = true;
                                    }
                                  });
                                },
                          icon: Icon(
                            _showQuickSelectors ? Icons.close : Icons.edit,
                            color: _tracks.isEmpty
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          tooltip: _showQuickSelectors
                              ? l10n.hideQuickRating
                              : l10n.showQuickRating,
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: albumColors.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: albumColors.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: hasInsightsTitle
                          ? GestureDetector(
                              onLongPress: () async {
                                if (insightsTitleRaw.isNotEmpty) {
                                  await Clipboard.setData(
                                      ClipboardData(text: insightsTitleRaw));
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10n.titleCopied)),
                                  );
                                }
                              },
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  insightsTitleRaw,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: albumColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (hasInsightsTitle) const SizedBox(width: 12),
                    IconButton.filled(
                      onPressed: _isGeneratingAlbumInsights
                          ? null
                          : () {
                              if (_albumData == null) {
                                return;
                              }
                              _generateAlbumInsights();
                            },
                      style: IconButton.styleFrom(
                        backgroundColor: albumColors.primary,
                        foregroundColor: albumColors.onPrimary,
                      ),
                      icon: _isGeneratingAlbumInsights
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      tooltip: _isGeneratingAlbumInsights
                          ? l10n.generatingTooltip
                          : l10n.generateAlbumInsights,
                    ),
                    if (showExpandButton) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          _isAlbumInsightsExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: albumColors.onSurfaceVariant,
                        ),
                        tooltip: _isAlbumInsightsExpanded
                            ? l10n.collapseInsights
                            : l10n.expandInsights,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isAlbumInsightsExpanded =
                                !_isAlbumInsightsExpanded;
                          });
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  averageScore == null
                      ? l10n.currently
                      : averageScore.toStringAsFixed(1),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: albumColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _cachedRatedTrackCount == 0
                      ? l10n.noSongsRatedYet
                      : l10n.basedOnRatedSongs(
                          _cachedRatedTrackCount, _tracks.length),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: albumColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _albumInsightsError != null
                        ? theme.colorScheme.error
                        : albumColors.onSurfaceVariant,
                  ),
                ),
                if ((_isAlbumInsightsExpanded || _isGeneratingAlbumInsights) &&
                    (_albumInsights != null ||
                        _albumInsightsError != null ||
                        _isGeneratingAlbumInsights))
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: _buildAlbumInsightsContent(theme),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInsightsTitle(ThemeData theme) {
    // 标题现在显示在专辑标题下方，所以这里返回空
    return const SizedBox.shrink();
  }

  Widget _buildErrorState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.failedToLoadAlbum,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? l10n.unknownError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _loadAlbum(forceRefresh: true),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumInsightsContent(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    if (_isGeneratingAlbumInsights) {
      return Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.generatingAlbumInsights,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (_albumInsightsError != null) {
      return Text(
        _albumInsightsError!,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    final insights = _albumInsights;
    if (insights == null) {
      return Text(
        l10n.noInsightsAvailableTapToGenerate,
        style: theme.textTheme.bodyMedium,
      );
    }

    final summary = insights['summary'] as String?;

    final children = <Widget>[];

    if (summary != null && summary.isNotEmpty) {
      children.add(
        Text(
          summary,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    if (children.isEmpty) {
      return Text(
        l10n.insightsEmptyRetryGenerate,
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String? _formatGeneratedAt() {
    final generatedAt = _albumInsightsGeneratedAt;
    if (generatedAt == null) {
      return null;
    }
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final difference = now.difference(generatedAt);
    if (difference.inDays > 0) {
      return l10n.insightsGeneratedDaysAgo(difference.inDays);
    }
    if (difference.inHours > 0) {
      return l10n.insightsGeneratedHoursAgo(difference.inHours);
    }
    if (difference.inMinutes > 0) {
      return l10n.insightsGeneratedMinutesAgo(difference.inMinutes);
    }
    return l10n.insightsJustGenerated;
  }

  String _buildMetaLine(List artists, String? releaseYear, int trackCount) {
    final l10n = AppLocalizations.of(context)!;
    final parts = <String>[];

    // 添加艺术家名称
    final artistEntries = [
      for (final artist in artists)
        if (artist is Map<String, dynamic>) artist
    ];

    if (artistEntries.isNotEmpty) {
      final artistNames = artistEntries
          .map((artist) => (artist['name'] as String?) ?? l10n.unknownArtist)
          .join(', ');
      parts.add(artistNames);
    }

    // 添加年份
    if (releaseYear != null && releaseYear.isNotEmpty) {
      parts.add(releaseYear);
    }

    // 添加曲目数
    parts.add(l10n.totalTracksCount(trackCount));

    return parts.join(' · ');
  }

  String? _extractCoverUrl() {
    final images = _albumData?['images'] as List? ?? const [];
    if (images.isEmpty) return null;
    final first = images.first;
    if (first is Map<String, dynamic>) {
      return first['url'] as String?;
    }
    return null;
  }

  String? _extractReleaseYear() {
    final date = _albumData?['release_date'] as String?;
    if (date == null || date.isEmpty) {
      return null;
    }
    return date.split('-').first;
  }

  String _formatArtists(BuildContext context, dynamic artists) {
    if (artists is List) {
      final names = <String>[];
      for (final artist in artists) {
        if (artist is Map<String, dynamic>) {
          final name = artist['name'] as String?;
          if (name != null) {
            names.add(name);
          }
        }
      }
      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }
    final l10n = AppLocalizations.of(context)!;
    return l10n.unknownArtist;
  }

  double _mapRatingToScore(int rating) {
    switch (rating) {
      case 0:
        return 1;
      case 5:
        return 10;
      case 3:
      default:
        return 5;
    }
  }
}

class _AlbumTrackTile extends StatelessWidget {
  final int index;
  final Map<String, dynamic> track;
  final int? rating;
  final int? pendingRating;
  final int? ratingTimestamp;
  final bool showQuickSelectors;
  final bool isUpdating;
  final VoidCallback onTap;
  final void Function(int rating) onRate;

  const _AlbumTrackTile({
    required this.index,
    required this.track,
    required this.rating,
    required this.pendingRating,
    required this.ratingTimestamp,
    required this.showQuickSelectors,
    required this.isUpdating,
    required this.onTap,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final trackName = track['name'] as String? ?? l10n.unknownTrackName;
    final artistNames = _formatArtists(context, track['artists']);
    final borderRadius = BorderRadius.circular(24);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trackName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          artistNames,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 新的评分显示UI：图标 + 时间
                        _buildRatingRow(context, theme),
                      ],
                    ),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1.0,
                  child: child,
                ),
                child: !showQuickSelectors
                    ? const SizedBox.shrink()
                    : Column(
                        key: const ValueKey('quickSelectors'),
                        children: [
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.only(left: 56.0),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: isUpdating
                                  ? const SizedBox(
                                      key: ValueKey('loading'),
                                      height: 0,
                                    )
                                  : Row(
                                      key: ValueKey<int?>(
                                          pendingRating ?? rating),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Ratings(
                                          initialRating:
                                              pendingRating ?? rating,
                                          onRatingChanged: onRate,
                                        ),
                                        if (pendingRating != null &&
                                            pendingRating != rating) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.circle,
                                            size: 8,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingRow(BuildContext context, ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    // 获取评分对应的图标
    IconData ratingIcon;
    switch (rating) {
      case 0:
        ratingIcon = Icons.thumb_down_outlined;
        break;
      case 5:
        ratingIcon = Icons.whatshot_outlined;
        break;
      case 3:
        ratingIcon = Icons.sentiment_neutral_rounded;
        break;
      default:
        ratingIcon = Icons.star_border_outlined;
        break;
    }

    // 格式化时间戳
    String timeText = l10n.unratedStatus;
    if (ratingTimestamp != null) {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(ratingTimestamp!);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        timeText = l10n.daysAgoShort(difference.inDays);
      } else if (difference.inHours > 0) {
        timeText = l10n.hoursAgoShort(difference.inHours);
      } else if (difference.inMinutes > 0) {
        timeText = l10n.minutesAgoShort(difference.inMinutes);
      } else {
        timeText = l10n.justNow;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ratingIcon,
          size: 20,
          color: rating != null
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          timeText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatArtists(BuildContext context, dynamic artists) {
    if (artists is List) {
      final names = <String>[];
      for (final artist in artists) {
        if (artist is Map<String, dynamic>) {
          final name = artist['name'] as String?;
          if (name != null) {
            names.add(name);
          }
        }
      }
      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }
    final l10n = AppLocalizations.of(context)!;
    return l10n.unknownArtist;
  }
}
