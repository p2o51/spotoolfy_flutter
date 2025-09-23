import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/local_database_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/spotify_service.dart';
import '../widgets/materialui.dart';

class PlaylistPage extends StatefulWidget {
  final String playlistId;

  const PlaylistPage({super.key, required this.playlistId});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  Map<String, dynamic>? _playlistData;
  List<Map<String, dynamic>> _tracks = [];
  Map<String, int?> _trackRatings = {};
  Map<String, int?> _trackRatingTimestamps = {};
  final Map<String, int> _pendingTrackRatings = {};
  final Set<String> _updatingTracks = {};
  bool _isLoading = true;
  bool _showQuickSelectors = false;
  bool _isSavingPendingRatings = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist({bool forceRefresh = false}) async {
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
      final playlist = await spotify.fetchPlaylistDetails(
        widget.playlistId,
        forceRefresh: forceRefresh,
      );

      final trackSection =
          (playlist['tracks'] as Map<String, dynamic>? ?? const {});
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
        _playlistData = playlist;
        _tracks = tracks;
        _trackRatings = normalizedRatings;
        _trackRatingTimestamps = normalizedTimestamps;
        _isLoading = false;
        _pendingTrackRatings.clear();
        _updatingTracks.clear();
        _showQuickSelectors = false;
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

  Future<void> _handlePlayPlaylist() async {
    final playlistId = (_playlistData?['id'] as String?) ?? widget.playlistId;
    try {
      final spotify = context.read<SpotifyProvider>();
      await spotify.playContext(type: 'playlist', id: playlistId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放播放列表失败：$e')),
      );
    }
  }

  Future<void> _handlePlayTrack(
      Map<String, dynamic> track, int trackIndex) async {
    final trackUri = track['uri'] as String? ??
        (track['id'] is String ? 'spotify:track:${track['id']}' : null);
    final playlistUri = (_playlistData?['uri'] as String?) ?? '';
    final playlistId = (_playlistData?['id'] as String?) ?? widget.playlistId;
    final derivedContextUri = playlistUri.isNotEmpty
        ? playlistUri
        : (playlistId.isNotEmpty ? 'spotify:playlist:$playlistId' : null);

    if (trackUri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法播放：缺少歌曲链接')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放歌曲失败：$e')),
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

    final playlistName = _playlistData?['name'] as String? ?? '';
    final trackAlbum = track['album'];
    var albumName = playlistName;
    String? albumCoverUrl;
    if (trackAlbum is Map<String, dynamic>) {
      final candidateName = trackAlbum['name'] as String?;
      if (candidateName != null && candidateName.isNotEmpty) {
        albumName = candidateName;
      }
      final albumImages = trackAlbum['images'];
      if (albumImages is List && albumImages.isNotEmpty) {
        final first = albumImages.first;
        if (first is Map<String, dynamic>) {
          albumCoverUrl = first['url'] as String?;
        }
      }
    }
    albumName = albumName.isEmpty ? '歌单曲目' : albumName;
    albumCoverUrl ??= _extractCoverUrl();

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
        albumCoverUrl: albumCoverUrl,
        rating: rating,
      );

      if (!mounted) return;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _trackRatings = Map<String, int?>.from(_trackRatings)
          ..[trackId] = rating;
        _trackRatingTimestamps = Map<String, int?>.from(
          _trackRatingTimestamps,
        )..[trackId] = timestamp;
        _pendingTrackRatings.remove(trackId);
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
      if (!mounted) return;
      setState(() {
        _isSavingPendingRatings = false;
        _pendingTrackRatings.clear();
        _showQuickSelectors = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_playlistData?['name'] as String? ?? '播放列表详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新播放列表',
            onPressed: () => _loadPlaylist(forceRefresh: true),
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
      onRefresh: () => _loadPlaylist(forceRefresh: true),
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
                      _PlaylistTrackTile(
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
    final playlistName = _playlistData?['name'] as String? ?? '';
    final ownerName = _extractOwnerName();
    final description = _extractDescription();
    final trackCount = _tracks.length;

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
                        Icons.queue_music,
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
                    playlistName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  if (ownerName != null)
                    Text(
                      '由 $ownerName 创建',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    _buildMetaLine(trackCount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _handlePlayPlaylist,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('播放播放列表'),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 40,
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
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notes_rounded,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
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
              '加载播放列表失败',
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
              onPressed: () => _loadPlaylist(forceRefresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  String _buildMetaLine(int trackCount) {
    return '共 $trackCount 首曲目';
  }

  String? _extractOwnerName() {
    final owner = _playlistData?['owner'];
    if (owner is Map<String, dynamic>) {
      final displayName = owner['display_name'] as String?;
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }
    }
    return null;
  }

  String? _extractDescription() {
    final description = _playlistData?['description'] as String?;
    if (description == null || description.isEmpty) {
      return null;
    }
    final cleaned = description.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return cleaned.isEmpty ? null : cleaned;
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

  String? _extractCoverUrl() {
    final images = _playlistData?['images'] as List? ?? const [];
    if (images.isEmpty) return null;
    final first = images.first;
    if (first is Map<String, dynamic>) {
      return first['url'] as String?;
    }
    return null;
  }
}

class _PlaylistTrackTile extends StatelessWidget {
  final int index;
  final Map<String, dynamic> track;
  final int? rating;
  final int? pendingRating;
  final int? ratingTimestamp;
  final bool showQuickSelectors;
  final bool isUpdating;
  final VoidCallback onTap;
  final void Function(int rating) onRate;

  const _PlaylistTrackTile({
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
                        const SizedBox(height: 6),
                        _buildMeta(theme),
                        const SizedBox(height: 12),
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

  Widget _buildMeta(ThemeData theme) {
    final albumName = track['album']?['name'] as String?;
    final durationMs = track['duration_ms'] as int?;

    String extra = '';
    if (albumName != null && albumName.isNotEmpty) {
      extra = albumName;
    }

    if (durationMs != null) {
      final minutes = durationMs ~/ 60000;
      final seconds = (durationMs % 60000) ~/ 1000;
      final formatted =
          '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
      extra = extra.isEmpty ? formatted : '$extra · $formatted';
    }

    if (extra.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      extra,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildRatingRow(ThemeData theme) {
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

    String timeText = '未评分';
    if (ratingTimestamp != null) {
      final dateTime =
          DateTime.fromMillisecondsSinceEpoch(ratingTimestamp!, isUtc: false);
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
