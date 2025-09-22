import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/local_database_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/spotify_service.dart';
import '../widgets/materialui.dart';

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
  final Set<String> _updatingTracks = {};
  bool _isLoading = true;
  bool _showQuickSelectors = false;
  String? _errorMessage;

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
      final latestRatingsWithTimestamp = await localDb.getLatestRatingsWithTimestampForTracks(trackIds);
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
      });
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
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  final trackId = track['id'] as String?;
                  final currentRating =
                      trackId != null ? _trackRatings[trackId] : null;
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
                        ratingTimestamp: ratingTimestamp,
                        showQuickSelectors: _showQuickSelectors,
                        isUpdating: isUpdating,
                        onRate: (rating) => _handleQuickRating(track, rating),
                      ),
                      if (index != _tracks.length - 1)
                        const SizedBox(height: 24),
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
    final artistNames = _formatArtists(_albumData?['artists']);
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
                  Text(
                    artistNames,
                    style: theme.textTheme.bodyMedium,
                  ),
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
                                    _showQuickSelectors = !_showQuickSelectors;
                                  });
                                },
                          icon: Icon(
                            _showQuickSelectors
                                ? Icons.close
                                : Icons.edit,
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
  final int? ratingTimestamp;
  final bool showQuickSelectors;
  final bool isUpdating;
  final void Function(int rating) onRate;

  const _AlbumTrackTile({
    required this.index,
    required this.track,
    required this.rating,
    required this.ratingTimestamp,
    required this.showQuickSelectors,
    required this.isUpdating,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackName = track['name'] as String? ?? '未知曲目';
    final artistNames = _formatArtists(track['artists']);

    return Padding(
      padding: const EdgeInsets.all(20.0),
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
          if (showQuickSelectors) ...[
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isUpdating
                  ? Row(
                      key: const ValueKey('loading'),
                      children: const [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('保存中…'),
                      ],
                    )
                  : Ratings(
                      key: ValueKey<int?>(rating),
                      initialRating: rating,
                      onRatingChanged: onRate,
                    ),
            ),
          ],
        ],
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
      children: [
        Icon(
          ratingIcon,
          size: 20,
          color: rating != null ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
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
