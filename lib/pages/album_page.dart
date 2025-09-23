import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/local_database_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/spotify_service.dart';
import '../widgets/materialui.dart';
import '../services/album_insights_service.dart';

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

      final localDb = context.read<LocalDatabaseProvider>();
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
      });
      _loadCachedAlbumInsights();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放专辑失败：$e')),
      );
    }
  }

  Future<void> _handlePlayTrack(Map<String, dynamic> track) async {
    final trackUri = track['uri'] as String? ??
        (track['id'] is String ? 'spotify:track:${track['id']}' : null);

    if (trackUri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法播放：缺少歌曲链接')),
      );
      return;
    }

    try {
      final spotify = context.read<SpotifyProvider>();
      await spotify.playTrack(trackUri: trackUri);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放歌曲失败：$e')),
      );
    }
  }

  Future<void> _handleOpenArtist(Map<String, dynamic> artist) async {
    final spotifyUri = artist['uri'] as String?;
    final externalUrls = artist['external_urls'];
    final webUrl = externalUrls is Map<String, dynamic>
        ? externalUrls['spotify'] as String?
        : null;

    Future<bool> _launchIfPossible(String? url) async {
      if (url == null || url.isEmpty) {
        return false;
      }
      try {
        final launched = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        return launched;
      } catch (_) {
        return false;
      }
    }

    final launchedSpotify = await _launchIfPossible(spotifyUri);
    if (launchedSpotify) {
      return;
    }

    final launchedWeb = await _launchIfPossible(webUrl);
    if (launchedWeb) {
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开艺术家链接')),
    );
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
      setState(() {
        _albumInsightsError = '读取缓存失败：$e';
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
        averageScore: _averageScore,
        ratedTrackCount: _ratedTrackCount,
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
      setState(() {
        _albumInsightsError = '生成洞察失败：$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isGeneratingAlbumInsights = false;
      });
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
    final artistNames = _formatArtists(track['artists']);
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
        _albumInsights = null;
        _albumInsightsGeneratedAt = null;
        _albumInsightsError = null;
        _isAlbumInsightsExpanded = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存评分失败：$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _updatingTracks.remove(trackId);
      });
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

  double? get _averageScore {
    final values = <double>[];
    for (final track in _tracks) {
      final trackId = track['id'] as String?;
      if (trackId == null) continue;
      final rating = _trackRatings[trackId];
      if (rating == null) continue;
      values.add(_mapRatingToScore(rating));
    }
    if (values.isEmpty) {
      return null;
    }
    final total = values.reduce((value, element) => value + element);
    return total / values.length;
  }

  int get _ratedTrackCount {
    var count = 0;
    for (final track in _tracks) {
      final trackId = track['id'] as String?;
      if (trackId == null) continue;
      if (_trackRatings[trackId] != null) {
        count++;
      }
    }
    return count;
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_albumData?['name'] as String? ?? '专辑详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新专辑',
            onPressed: () => _loadAlbum(forceRefresh: true),
          ),
        ],
      ),
      body: _buildBody(theme),
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
                            _isSavingPendingRatings ? '保存中…' : '保存全部修改',
                          ),
                        ),
                      ),
                    ),
            ),
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
                        onTap: () => _handlePlayTrack(track),
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
    final averageScore = _averageScore;

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
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 160,
                      height: 160,
                      color: theme.colorScheme.surfaceVariant,
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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  _buildArtistLinks(theme, artists),
                  const SizedBox(height: 12),
                  Text(
                    _buildMetaLine(releaseYear, trackCount),
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
                        label: const Text('播放专辑'),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 40, // 与 FilledButton 相同的高度
                        width: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceVariant,
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
                                ? theme.colorScheme.onSurface.withOpacity(0.38)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          tooltip: _showQuickSelectors ? '隐藏快捷评分' : '显示快捷评分',
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
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(
                  Icons.insights_rounded,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        averageScore == null
                            ? '目前'
                            : averageScore.toStringAsFixed(1),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ratedTrackCount == 0
                            ? '还没有歌曲被评分'
                            : '基于 $_ratedTrackCount/${_tracks.length} 首歌曲',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildAlbumInsightsToolbar(theme),
                      if ((_isAlbumInsightsExpanded ||
                              _isGeneratingAlbumInsights) &&
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
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 64),
            const SizedBox(height: 16),
            Text(
              '加载专辑失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '未知错误',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _loadAlbum(forceRefresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistLinks(ThemeData theme, List artists) {
    final artistEntries = [
      for (final artist in artists)
        if (artist is Map<String, dynamic>) artist
    ];

    if (artistEntries.isEmpty) {
      return Text(
        '未知艺术家',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final artist in artistEntries)
          TextButton(
            onPressed: () => _handleOpenArtist(artist),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              (artist['name'] as String?) ?? '未知艺术家',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAlbumInsightsToolbar(ThemeData theme) {
    final hasInsights = _albumInsights != null;
    final hasError = _albumInsightsError != null;
    final showExpandButton =
        hasInsights || hasError || _isGeneratingAlbumInsights;

    final generatedAtLabel = _formatGeneratedAt();
    final statusText = _albumInsightsError != null
        ? '生成专辑洞察失败'
        : hasInsights
            ? (generatedAtLabel ?? '专辑洞察已准备好')
            : '点击右侧按钮生成这张专辑的洞察';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            statusText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton.filled(
          onPressed: _isGeneratingAlbumInsights
              ? null
              : () {
                  if (_albumData == null) {
                    return;
                  }
                  _generateAlbumInsights();
                },
          icon: _isGeneratingAlbumInsights
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          tooltip: _isGeneratingAlbumInsights ? '生成中…' : '生成专辑洞察',
        ),
        if (showExpandButton)
          IconButton(
            icon: Icon(
              _isAlbumInsightsExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            tooltip: _isAlbumInsightsExpanded ? '收起洞察' : '展开洞察',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _isAlbumInsightsExpanded = !_isAlbumInsightsExpanded;
              });
            },
          ),
      ],
    );
  }

  Widget _buildAlbumInsightsContent(ThemeData theme) {
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
            '正在生成专辑洞察…',
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
        '暂无可用洞察。点击上方按钮生成一次吧。',
        style: theme.textTheme.bodyMedium,
      );
    }

    final generatedAtLabel = _formatGeneratedAt();
    final summary = insights['summary'] as String?;

    final children = <Widget>[];

    if (generatedAtLabel != null) {
      children.add(
        Text(
          generatedAtLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
    }

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
        '洞察结果空空如也，试着重新生成一次。',
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
    final now = DateTime.now();
    final difference = now.difference(generatedAt);
    if (difference.inDays > 0) {
      return '洞察生成于 ${difference.inDays} 天前';
    }
    if (difference.inHours > 0) {
      return '洞察生成于 ${difference.inHours} 小时前';
    }
    if (difference.inMinutes > 0) {
      return '洞察生成于 ${difference.inMinutes} 分钟前';
    }
    return '洞察刚刚生成';
  }

  String _buildMetaLine(String? releaseYear, int trackCount) {
    final parts = <String>[];
    if (releaseYear != null && releaseYear.isNotEmpty) {
      parts.add(releaseYear);
    }
    parts.add('共 $trackCount 首曲目');
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

  String _formatArtists(dynamic artists) {
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
    return '未知艺术家';
  }

  double _mapRatingToScore(int rating) {
    switch (rating) {
      case 0:
        return 1;
      case 5:
        return 10;
      case 3:
      default:
        return 6;
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
    final trackName = track['name'] as String? ?? '未知曲目';
    final artistNames = _formatArtists(track['artists']);
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
                        _buildRatingRow(theme),
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

  Widget _buildRatingRow(ThemeData theme) {
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
    String timeText = '未评分';
    if (ratingTimestamp != null) {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(ratingTimestamp!);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        timeText = '${difference.inDays}天前';
      } else if (difference.inHours > 0) {
        timeText = '${difference.inHours}小时前';
      } else if (difference.inMinutes > 0) {
        timeText = '${difference.inMinutes}分钟前';
      } else {
        timeText = '刚刚';
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

  static String _formatArtists(dynamic artists) {
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
    return '未知艺术家';
  }
}
