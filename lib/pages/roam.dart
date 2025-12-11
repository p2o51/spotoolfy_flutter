//roam.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
// import '../providers/firestore_provider.dart'; // Remove old provider
import '../providers/local_database_provider.dart'; // Import new provider
import 'package:cached_network_image/cached_network_image.dart'; // Import CachedNetworkImage
import '../providers/spotify_provider.dart'; // <--- 添加 SpotifyProvider 导入
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../widgets/note_poster_preview_page.dart';
import '../l10n/app_localizations.dart';

final logger = Logger();

class Roam extends StatefulWidget {
  const Roam({super.key});

  @override
  State<Roam> createState() => _RoamState();
}

class _RoamState extends State<Roam> {
  // Filter state: null = all, 0 = thumb down, 3 = neutral, 5 = fire
  int? _selectedRatingFilter;

  // Show only "Rated" records (no note content)
  bool _showRatedOnly = false;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fetch initial data using the provider's public combined fetch method
      Provider.of<LocalDatabaseProvider>(context, listen: false).fetchInitialData(); // Call the public fetch
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshThoughts() async {
    // Refresh data using the provider's public combined fetch method
    await Provider.of<LocalDatabaseProvider>(context, listen: false).fetchInitialData(); // Call the public fetch
  }

  // --- Helper Methods for Edit/Delete ---

  void _showActionSheet(BuildContext context, Map<String, dynamic> record) {
    // localDbProvider variable removed as unused
    // 获取 SpotifyProvider
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    // Ensure your map fetched from the DB includes 'id', 'trackId', and 'songTimestampMs'
    final recordId = record['id'] as int?;
    final trackId = record['trackId'] as String?;
    final songTimestampMs = record['songTimestampMs'] as int?; // 获取时间戳

    if (recordId == null || trackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.incompleteRecordError)),
      );
      return;
    }

    // 格式化时间戳 (如果存在)
    String formattedTimestamp = '';
    if (songTimestampMs != null && songTimestampMs > 0) {
      final duration = Duration(milliseconds: songTimestampMs);
      final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      formattedTimestamp = '$minutes:$seconds';
    }

    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  record['trackName'] ?? AppLocalizations.of(context)!.optionsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              // Play from timestamp
              if (songTimestampMs != null && songTimestampMs > 0)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(AppLocalizations.of(context)!.playFromTimestamp(formattedTimestamp)),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(bottomSheetContext);
                    final trackUri = 'spotify:track:$trackId';
                    logger.d('Attempting to play URI: $trackUri from $songTimestampMs ms');

                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final localizations = AppLocalizations.of(context)!;

                    try {
                      await spotifyProvider.playTrack(trackUri: trackUri);
                      final duration = Duration(milliseconds: songTimestampMs);
                      await spotifyProvider.seekToPosition(duration.inMilliseconds);
                    } catch (e) {
                      logger.d('Error calling playTrack or seekToPosition: $e');
                      if (mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(localizations.playbackFailed(e.toString())),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                ),
              // Share
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(AppLocalizations.of(context)!.shareNote),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(bottomSheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotePosterPreviewPage(
                        noteContent: record['noteContent'] as String? ?? '',
                        lyricsSnapshot: record['lyricsSnapshot'] as String?,
                        trackTitle: record['trackName'] as String? ?? '',
                        artistName: record['artistName'] as String? ?? '',
                        albumName: record['albumName'] as String? ?? '',
                        rating: record['rating'] as int? ?? 3,
                        albumCoverUrl: record['albumCoverUrl'] as String?,
                      ),
                    ),
                  );
                },
              ),
              // Edit
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(AppLocalizations.of(context)!.editNote),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(bottomSheetContext);
                  _showEditDialog(context, record);
                },
              ),
              // Delete
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(
                  AppLocalizations.of(context)!.deleteNote,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(bottomSheetContext);
                  _confirmDeleteRecord(context, recordId, trackId);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic> record) {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final recordId = record['id'] as int; // Assumed not null from _showActionSheet check
    final trackId = record['trackId'] as String; // Assumed not null
    final initialContent = record['noteContent'] as String? ?? '';
    // Handle potential string rating from old data during edit prep
    dynamic initialRatingRaw = record['rating'];
    int initialRating = 3; // Default
     if (initialRatingRaw is int) {
      initialRating = initialRatingRaw;
    } else if (initialRatingRaw is String) {
      // If it's a string (old data), treat it as the default rating 3 for editing
      initialRating = 3;
    }

    final TextEditingController textController = TextEditingController(text: initialContent);
    // Use a local state variable for the dialog's rating selection
    int selectedRating = initialRating;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder( // Use StatefulBuilder to update rating selection within the dialog
           builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(AppLocalizations.of(context)!.editNoteTitle),
                content: SingleChildScrollView( // Allow scrolling if content is long
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: textController,
                        maxLines: null, // Allow multiple lines
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.noteContent,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Using SegmentedButton for rating selection
                      SegmentedButton<int>(
                        segments: const <ButtonSegment<int>>[
                           ButtonSegment<int>(value: 0, icon: Icon(Icons.thumb_down_outlined)),
                           ButtonSegment<int>(value: 3, icon: Icon(Icons.sentiment_neutral_rounded)),
                           ButtonSegment<int>(value: 5, icon: Icon(Icons.whatshot_outlined)),
                        ],
                        selected: {selectedRating}, // Use a Set for selected
                        onSelectionChanged: (Set<int> newSelection) {
                           HapticFeedback.selectionClick();
                           setDialogState(() { // Update dialog state
                              selectedRating = newSelection.first;
                           });
                        },
                        showSelectedIcon: false, // Don't show checkmark on selected
                        style: SegmentedButton.styleFrom(
                           selectedBackgroundColor: Theme.of(context).colorScheme.primaryContainer,
                           // Adjust other styles as needed
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: Text(AppLocalizations.of(context)!.cancel),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                  TextButton(
                    child: Text(AppLocalizations.of(context)!.saveChanges),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      localDbProvider.updateRecord(
                        recordId: recordId,
                        trackId: trackId,
                        newNoteContent: textController.text.trim(),
                        newRating: selectedRating,
                      );
                      Navigator.pop(dialogContext); // Close dialog
                    },
                  ),
                ],
              );
           },
        );
      },
    );
  }

  void _confirmDeleteRecord(BuildContext context, int recordId, String trackId) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.confirmDelete),
          content: Text(AppLocalizations.of(context)!.deleteConfirmMessage),
          actions: [
            TextButton(
              child: Text(AppLocalizations.of(context)!.cancel),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: Text(AppLocalizations.of(context)!.deleteNote),
              onPressed: () {
                HapticFeedback.mediumImpact();
                Provider.of<LocalDatabaseProvider>(context, listen: false).deleteRecord(
                   recordId: recordId,
                   trackId: trackId, // Pass trackId
                );
                Navigator.pop(dialogContext); // Close confirmation dialog
              },
            ),
          ],
        );
      },
    );
  }

  // Build Today's Review Card - Material 3 Style
  Widget _buildTodayReviewCard(BuildContext context, List<Map<String, dynamic>> records, SpotifyProvider spotifyProvider) {
    // Get a random record based on today's date (consistent for the day)
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    final randomIndex = seed % records.length;
    final record = records[randomIndex];

    final trackId = record['trackId'] as String?;
    final trackName = record['trackName'] as String? ?? 'Unknown Track';
    final artistName = record['artistName'] as String? ?? 'Unknown Artist';
    final noteContent = record['noteContent'] as String? ?? '';
    final albumCoverUrl = record['albumCoverUrl'] as String?;
    final lyricsSnapshot = record['lyricsSnapshot'] as String?;

    // Get rating icon
    final dynamic ratingRaw = record['rating'];
    int ratingValue = 3;
    if (ratingRaw is int) ratingValue = ratingRaw;
    IconData ratingIcon;
    switch (ratingValue) {
      case 0: ratingIcon = Icons.thumb_down_rounded; break;
      case 5: ratingIcon = Icons.whatshot_rounded; break;
      case 3: default: ratingIcon = Icons.sentiment_neutral_rounded; break;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: trackId != null ? () {
          HapticFeedback.lightImpact();
          final trackUri = 'spotify:track:$trackId';
          try {
            spotifyProvider.playTrack(trackUri: trackUri);
          } catch (e) {
            logger.d('Error playing track from review card: $e');
          }
        } : null,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with badge
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.todayReviewTitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Main content row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Album cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: albumCoverUrl ?? '',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 80, height: 80,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.music_note_rounded, size: 32, color: colorScheme.onSurfaceVariant),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 80, height: 80,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.music_note_rounded, size: 32, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Track name
                        Text(
                          trackName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        // Artist name
                        Text(
                          artistName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Rating icon and play hint
                        Row(
                          children: [
                            Icon(
                              ratingIcon,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const Spacer(),
                            Icon(
                              Icons.play_circle_outline_rounded,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Note content or lyrics snapshot
              if (noteContent.isNotEmpty || (lyricsSnapshot != null && lyricsSnapshot.isNotEmpty)) ...[
                const SizedBox(height: 12),
                if (noteContent.isNotEmpty)
                  Text(
                    noteContent,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (lyricsSnapshot != null && lyricsSnapshot.isNotEmpty) ...[
                  if (noteContent.isNotEmpty) const SizedBox(height: 8),
                  Text(
                    '"$lyricsSnapshot"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取 SpotifyProvider
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    // Consume the LocalDatabaseProvider
    return Consumer<LocalDatabaseProvider>(
      builder: (context, localDbProvider, child) {
        // Get all records with notes (not just "Rated")
        final allNotesRecords = localDbProvider.allRecordsOrdered.where((record) {
          final noteContent = record['noteContent'] as String? ?? '';
          return noteContent.isNotEmpty;
        }).toList();

        // Get all "Rated" only records (no note content)
        final allRatedOnlyRecords = localDbProvider.allRecordsOrdered.where((record) {
          final noteContent = record['noteContent'] as String? ?? '';
          return noteContent.isEmpty;
        }).toList();

        // Calculate stats
        final totalCount = allNotesRecords.length;
        final fireCount = allNotesRecords.where((r) => (r['rating'] as int? ?? 3) == 5).length;
        final neutralCount = allNotesRecords.where((r) => (r['rating'] as int? ?? 3) == 3).length;
        final downCount = allNotesRecords.where((r) => (r['rating'] as int? ?? 3) == 0).length;
        final ratedOnlyCount = allRatedOnlyRecords.length;

        // Choose base records based on _showRatedOnly
        final baseRecords = _showRatedOnly ? allRatedOnlyRecords : allNotesRecords;

        // Apply rating filter and search filter
        final filteredRecords = baseRecords.where((record) {
          // Rating filter
          if (_selectedRatingFilter != null) {
            final rating = record['rating'] as int? ?? 3;
            if (rating != _selectedRatingFilter) return false;
          }

          // Search filter
          if (_searchQuery.isNotEmpty) {
            final query = _searchQuery.toLowerCase();
            final trackName = (record['trackName'] as String? ?? '').toLowerCase();
            final artistName = (record['artistName'] as String? ?? '').toLowerCase();
            final noteContent = (record['noteContent'] as String? ?? '').toLowerCase();
            if (!trackName.contains(query) && !artistName.contains(query) && !noteContent.contains(query)) {
              return false;
            }
          }

          return true;
        }).toList();

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _refreshThoughts,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Today's Review Card
                if (allNotesRecords.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildTodayReviewCard(context, allNotesRecords, spotifyProvider),
                  ),
                // Search bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.searchNotesHint,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                  ),
                ),
                // Rating filter chips with stats
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        // Stats summary
                        Text(
                          AppLocalizations.of(context)!.statsTotal(totalCount),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Filter chips (icon only with count)
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                FilterChip(
                                  avatar: const Icon(Icons.select_all, size: 18),
                                  label: Text('$totalCount'),
                                  selected: _selectedRatingFilter == null && !_showRatedOnly,
                                  showCheckmark: false,
                                  onSelected: (selected) {
                                    if (selected) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedRatingFilter = null;
                                        _showRatedOnly = false;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  avatar: Icon(Icons.whatshot_outlined, size: 18, color: _selectedRatingFilter == 5 ? Theme.of(context).colorScheme.onSecondaryContainer : null),
                                  label: Text('$fireCount'),
                                  selected: _selectedRatingFilter == 5 && !_showRatedOnly,
                                  showCheckmark: false,
                                  onSelected: fireCount > 0 ? (selected) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _selectedRatingFilter = selected ? 5 : null;
                                      _showRatedOnly = false;
                                    });
                                  } : null,
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  avatar: Icon(Icons.sentiment_neutral_rounded, size: 18, color: _selectedRatingFilter == 3 ? Theme.of(context).colorScheme.onSecondaryContainer : null),
                                  label: Text('$neutralCount'),
                                  selected: _selectedRatingFilter == 3 && !_showRatedOnly,
                                  showCheckmark: false,
                                  onSelected: neutralCount > 0 ? (selected) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _selectedRatingFilter = selected ? 3 : null;
                                      _showRatedOnly = false;
                                    });
                                  } : null,
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  avatar: Icon(Icons.thumb_down_outlined, size: 18, color: _selectedRatingFilter == 0 ? Theme.of(context).colorScheme.onSecondaryContainer : null),
                                  label: Text('$downCount'),
                                  selected: _selectedRatingFilter == 0 && !_showRatedOnly,
                                  showCheckmark: false,
                                  onSelected: downCount > 0 ? (selected) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _selectedRatingFilter = selected ? 0 : null;
                                      _showRatedOnly = false;
                                    });
                                  } : null,
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  avatar: Icon(Icons.star_outline, size: 18, color: _showRatedOnly ? Theme.of(context).colorScheme.onSecondaryContainer : null),
                                  label: Text('$ratedOnlyCount'),
                                  selected: _showRatedOnly,
                                  showCheckmark: false,
                                  onSelected: ratedOnlyCount > 0 ? (selected) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _showRatedOnly = selected;
                                      _selectedRatingFilter = null;
                                    });
                                  } : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Use the provider's loading state AND check the filtered records list
                if (localDbProvider.isLoading && filteredRecords.isEmpty) // Show loading only if filtered list is empty
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                // Use the filtered records list for the empty state
                else if (filteredRecords.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_note_outlined,
                              size: 64,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.emptyNotesTitle,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!.emptyNotesSubtitle,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        // 获取屏幕宽度，使用SliverLayoutBuilder提供的约束
                        final double width = constraints.crossAxisExtent;
                        // 如果屏幕宽度大于600，使用双列布局
                        final bool useTwoColumns = width > 600;
                        
                        if (useTwoColumns) {
                          // 使用MasonryGridView实现交错的网格布局
                          return SliverMasonryGrid.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            itemBuilder: (context, index) {
                              // 移除对索引的检查，改用childCount来限制项目数量
                              // Access data using map keys from the filtered records list
                              final record = filteredRecords[index];
                              final recordId = record['id'] as int?;
                              final trackId = record['trackId'] as String?;
                              final albumCoverUrl = record['albumCoverUrl'] as String?; // Get album cover URL
                              final recordedAtRaw = record['recordedAt']; // CORRECT KEY: Get timestamp using 'recordedAt'
                              String formattedTime = 'Unknown Time';
                              
                              if (recordedAtRaw is int) { 
                                 final recordedDateTime = DateTime.fromMillisecondsSinceEpoch(recordedAtRaw).toLocal();
                                 final now = DateTime.now();
                                 final today = DateTime(now.year, now.month, now.day);
                                 final yesterday = DateTime(now.year, now.month, now.day - 1);
                                 final recordDate = DateTime(recordedDateTime.year, recordedDateTime.month, recordedDateTime.day);

                                 final timeStr = '${recordedDateTime.hour.toString().padLeft(2, '0')}:${recordedDateTime.minute.toString().padLeft(2, '0')}';

                                 if (recordDate == today) {
                                   formattedTime = '${AppLocalizations.of(context)!.today} $timeStr';
                                 } else if (recordDate == yesterday) {
                                   formattedTime = '${AppLocalizations.of(context)!.yesterday} $timeStr';
                                 } else {
                                   // Format as MM-DD HH:mm for other dates
                                   final dateStr = '${recordedDateTime.month.toString().padLeft(2, '0')}-${recordedDateTime.day.toString().padLeft(2, '0')}';
                                   formattedTime = '$dateStr $timeStr';
                                 }
                              } else if (recordedAtRaw is String) { 
                                // Fallback for potential string format (attempt to parse)
                                try {
                                  final recordedDateTime = DateTime.parse(recordedAtRaw).toLocal();
                                  // Apply same logic as above for parsed string date
                                   final now = DateTime.now();
                                   final today = DateTime(now.year, now.month, now.day);
                                   final yesterday = DateTime(now.year, now.month, now.day - 1);
                                   final recordDate = DateTime(recordedDateTime.year, recordedDateTime.month, recordedDateTime.day);
                                   final timeStr = '${recordedDateTime.hour.toString().padLeft(2, '0')}:${recordedDateTime.minute.toString().padLeft(2, '0')}';
                                   if (recordDate == today) {
                                     formattedTime = '${AppLocalizations.of(context)!.today} $timeStr';
                                   } else if (recordDate == yesterday) {
                                     formattedTime = '${AppLocalizations.of(context)!.yesterday} $timeStr';
                                   } else {
                                     final dateStr = '${recordedDateTime.month.toString().padLeft(2, '0')}-${recordedDateTime.day.toString().padLeft(2, '0')}';
                                     formattedTime = '$dateStr $timeStr';
                                   }
                                } catch (e) {
                                  logger.d("Error parsing timestamp string: $e");
                                  // Keep 'Unknown Time' if parsing fails
                                }
                              }

                              // Rating Icon Logic
                              final dynamic ratingRaw = record['rating'];
                              int? ratingValue;
                              if (ratingRaw is int) { ratingValue = ratingRaw; }
                              else if (ratingRaw is String) { ratingValue = 3; } // Default for old string data
                              IconData ratingIcon;
                              switch (ratingValue) {
                                case 0: ratingIcon = Icons.thumb_down_outlined; break;
                                case 5: ratingIcon = Icons.whatshot_outlined; break;
                                case 3: default: ratingIcon = Icons.sentiment_neutral_rounded; break;
                              }
                              final ratingIconWidget = Icon(ratingIcon, color: Theme.of(context).colorScheme.primary, size: 24);

                              // Get note content
                              final String noteContent = record['noteContent'] as String? ?? '';

                              // Get lyrics snapshot
                              final String? lyricsSnapshot = record['lyricsSnapshot'] as String?;

                              // Wrap InkWell/Card in a Column to add Divider
                              return Column(
                                children: [
                                  InkWell(
                                    onTap: trackId != null ? () {
                                      HapticFeedback.lightImpact();
                                      logger.d('Tapped on card with trackId: $trackId');
                                      final trackUri = 'spotify:track:$trackId';
                                      logger.d('Attempting to play URI: $trackUri');
                                      try {
                                        spotifyProvider.playTrack(trackUri: trackUri);
                                      } catch (e) {
                                         logger.d('Error calling playTrack: $e');
                                         ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(AppLocalizations.of(context)!.playbackFailed(e.toString())),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    } : null,
                                    onLongPress: recordId != null ? () {
                                      logger.d('Long pressed on card with recordId: $recordId');
                                      _showActionSheet(context, record);
                                    } : null,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Card(
                                      elevation: 0,
                                      color: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 1. Note Content (if available)
                                            if (noteContent.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 12.0), // Add space below note
                                                child: Text(
                                                  noteContent,
                                                  style: Theme.of(context).textTheme.bodyLarge,
                                                  overflow: TextOverflow.visible,
                                                ),
                                              ),
                                            // Show 'Rated' if noteContent is empty
                                            if (noteContent.isEmpty)
                                               Padding(
                                                 padding: const EdgeInsets.only(bottom: 12.0),
                                                 child: Text(
                                                   AppLocalizations.of(context)!.ratedStatus,
                                                   style: TextStyle(
                                                     fontStyle: FontStyle.italic,
                                                     color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                   ),
                                                 ),
                                               ),

                                            // 1.5. Lyrics Snapshot (if available)
                                            if (lyricsSnapshot != null && lyricsSnapshot.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 12.0),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      Icons.music_note_outlined,
                                                      size: 14,
                                                      color: Theme.of(context).colorScheme.outline,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        lyricsSnapshot,
                                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: Theme.of(context).colorScheme.outline,
                                                          height: 1.4,
                                                        ),
                                                        maxLines: 3,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                            // 2. Bottom Row (Image/Info + Rating)
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.center, // Vertically center items in this row
                                              children: [
                                                // 2a. Left Group (Image + Text Info)
                                                Expanded( // Allow this group to take available space
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.center, // Center image and text column vertically
                                                    children: [
                                                      // Album Cover
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(25.0), // Slightly rounded corners for cover
                                                        child: CachedNetworkImage(
                                                          imageUrl: albumCoverUrl ?? '',
                                                          width: 50, // Adjust size as needed
                                                          height: 50,
                                                          fit: BoxFit.cover,
                                                          placeholder: (context, url) => Container(
                                                            width: 50, height: 50,
                                                            color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(100),
                                                            child: Icon(Icons.music_note_outlined, size: 24, color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.5)),
                                                          ),
                                                          errorWidget: (context, url, error) => Container(
                                                            width: 50, height: 50,
                                                            color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(100),
                                                            child: Icon(Icons.broken_image_outlined, size: 24, color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.5)),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12), // Space between image and text
                                                      
                                                      // Text Info Column
                                                      Expanded( // Allow text to take remaining space in the inner row
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisAlignment: MainAxisAlignment.center, // Center text lines vertically
                                                          children: [
                                                            // Timestamp
                                                            Text(
                                                              AppLocalizations.of(context)!.recordsAt(formattedTime),
                                                              style: Theme.of(context).textTheme.labelSmall?.copyWith( // Use labelMedium for timestamp
                                                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                                                fontWeight: FontWeight.normal,
                                                              ),
                                                               maxLines: 1,
                                                               overflow: TextOverflow.ellipsis,
                                                            ),
                                                            // Track Name
                                                            Text(
                                                              '${record['trackName'] ?? 'Unknown Track'}',
                                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith( // Use titleMedium for track
                                                                color: Theme.of(context).colorScheme.primary,
                                                                fontWeight: FontWeight.w500, // Slightly bolder track name
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              softWrap: false,
                                                            ),
                                                            // Artist Name
                                                            Text(
                                                              '${record['artistName'] ?? 'Unknown Artist'}',
                                                              style: Theme.of(context).textTheme.bodySmall?.copyWith( // Use bodyMedium for artist
                                                                color: Theme.of(context).colorScheme.secondary,
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              softWrap: false,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 12), // Space before rating icon

                                                // 2b. Rating Icon
                                                ratingIconWidget,
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Add Divider below the card
                                  Divider(
                                    height: 10, 
                                    thickness: 1,
                                    indent: 16,
                                    endIndent: 16,
                                    // 使用主题颜色，而不是透明色
                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                  ),
                                ],
                              );
                            },
                            childCount: filteredRecords.length,
                          );
                        } else {
                          // 保持原有的单列SliverList布局
                          return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                                // 原有的单列实现代码
                          // Access data using map keys from the filtered records list
                          final record = filteredRecords[index];
                          // Determine if it's the first/last item in the filtered list
                          final isFirst = index == 0;
                          final isLast = index == filteredRecords.length - 1;
                          final recordId = record['id'] as int?;
                          final trackId = record['trackId'] as String?;
                          final albumCoverUrl = record['albumCoverUrl'] as String?; // Get album cover URL
                          final recordedAtRaw = record['recordedAt']; // CORRECT KEY: Get timestamp using 'recordedAt'
                          String formattedTime = 'Unknown Time';
                          
                          if (recordedAtRaw is int) { 
                             final recordedDateTime = DateTime.fromMillisecondsSinceEpoch(recordedAtRaw).toLocal();
                             final now = DateTime.now();
                             final today = DateTime(now.year, now.month, now.day);
                             final yesterday = DateTime(now.year, now.month, now.day - 1);
                             final recordDate = DateTime(recordedDateTime.year, recordedDateTime.month, recordedDateTime.day);

                             final timeStr = '${recordedDateTime.hour.toString().padLeft(2, '0')}:${recordedDateTime.minute.toString().padLeft(2, '0')}';

                             if (recordDate == today) {
                               formattedTime = '${AppLocalizations.of(context)!.today} $timeStr';
                             } else if (recordDate == yesterday) {
                               formattedTime = '${AppLocalizations.of(context)!.yesterday} $timeStr';
                             } else {
                               // Format as MM-DD HH:mm for other dates
                               final dateStr = '${recordedDateTime.month.toString().padLeft(2, '0')}-${recordedDateTime.day.toString().padLeft(2, '0')}';
                               formattedTime = '$dateStr $timeStr';
                             }
                          } else if (recordedAtRaw is String) { 
                            // Fallback for potential string format (attempt to parse)
                            try {
                              final recordedDateTime = DateTime.parse(recordedAtRaw).toLocal();
                              // Apply same logic as above for parsed string date
                               final now = DateTime.now();
                               final today = DateTime(now.year, now.month, now.day);
                               final yesterday = DateTime(now.year, now.month, now.day - 1);
                               final recordDate = DateTime(recordedDateTime.year, recordedDateTime.month, recordedDateTime.day);
                               final timeStr = '${recordedDateTime.hour.toString().padLeft(2, '0')}:${recordedDateTime.minute.toString().padLeft(2, '0')}';
                               if (recordDate == today) {
                                 formattedTime = '${AppLocalizations.of(context)!.today} $timeStr';
                               } else if (recordDate == yesterday) {
                                 formattedTime = '${AppLocalizations.of(context)!.yesterday} $timeStr';
                               } else {
                                 final dateStr = '${recordedDateTime.month.toString().padLeft(2, '0')}-${recordedDateTime.day.toString().padLeft(2, '0')}';
                                 formattedTime = '$dateStr $timeStr';
                               }
                            } catch (e) {
                              logger.d("Error parsing timestamp string: $e");
                              // Keep 'Unknown Time' if parsing fails
                            }
                          }

                          // Rating Icon Logic
                          final dynamic ratingRaw = record['rating'];
                          int? ratingValue;
                          if (ratingRaw is int) { ratingValue = ratingRaw; }
                          else if (ratingRaw is String) { ratingValue = 3; } // Default for old string data
                          IconData ratingIcon;
                          switch (ratingValue) {
                            case 0: ratingIcon = Icons.thumb_down_outlined; break;
                            case 5: ratingIcon = Icons.whatshot_outlined; break;
                            case 3: default: ratingIcon = Icons.sentiment_neutral_rounded; break;
                          }
                          final ratingIconWidget = Icon(ratingIcon, color: Theme.of(context).colorScheme.primary, size: 24);

                          // Get note content
                          final String noteContent = record['noteContent'] as String? ?? '';

                          // Get lyrics snapshot
                          final String? lyricsSnapshot = record['lyricsSnapshot'] as String?;

                          // Wrap with Dismissible for swipe gestures
                          return Dismissible(
                            key: Key('record_${recordId ?? index}'),
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 24),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                  const SizedBox(width: 8),
                                  Text(
                                    AppLocalizations.of(context)!.swipeToPlay,
                                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!.swipeToDelete,
                                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                                ],
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                // Swipe right to play
                                HapticFeedback.lightImpact();
                                if (trackId != null) {
                                  final trackUri = 'spotify:track:$trackId';
                                  try {
                                    spotifyProvider.playTrack(trackUri: trackUri);
                                  } catch (e) {
                                    logger.d('Error playing track: $e');
                                  }
                                }
                                return false; // Don't dismiss
                              } else if (direction == DismissDirection.endToStart) {
                                // Swipe left to delete - show confirmation
                                HapticFeedback.mediumImpact();
                                if (recordId != null && trackId != null) {
                                  return await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: Text(AppLocalizations.of(context)!.confirmDelete),
                                      content: Text(AppLocalizations.of(context)!.deleteConfirmMessage),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext, false),
                                          child: Text(AppLocalizations.of(context)!.cancel),
                                        ),
                                        TextButton(
                                          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                                          onPressed: () => Navigator.pop(dialogContext, true),
                                          child: Text(AppLocalizations.of(context)!.deleteNote),
                                        ),
                                      ],
                                    ),
                                  ) ?? false;
                                }
                                return false;
                              }
                              return false;
                            },
                            onDismissed: (direction) {
                              if (direction == DismissDirection.endToStart && recordId != null && trackId != null) {
                                Provider.of<LocalDatabaseProvider>(context, listen: false).deleteRecord(
                                  recordId: recordId,
                                  trackId: trackId,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!.noteDeleted),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: isFirst ? 0 : 4.0,
                                  bottom: 4.0,
                                  left: 0,
                                  right: 0,
                                ),
                                child: InkWell(
                                  onTap: trackId != null ? () {
                                    HapticFeedback.lightImpact();
                                    logger.d('Tapped on card with trackId: $trackId');
                                    final trackUri = 'spotify:track:$trackId';
                                    logger.d('Attempting to play URI: $trackUri');
                                    try {
                                      spotifyProvider.playTrack(trackUri: trackUri);
                                      // REMOVED Playback SnackBar
                                    } catch (e) {
                                       logger.d('Error calling playTrack: $e');
                                       ScaffoldMessenger.of(context).showSnackBar( // Keep error SnackBar
                                        SnackBar(
                                          content: Text(AppLocalizations.of(context)!.playbackFailed(e.toString())),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  } : null,
                                  onLongPress: recordId != null ? () { logger.d('Long pressed on card with recordId: $recordId'); _showActionSheet(context, record); } : () { logger.d('Long press disabled for record: ${record['noteContent']}'); },
                                  // Apply borderRadius to InkWell for ripple effect consistency
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(isFirst ? 24 : 16), // Adjusted radius
                                    topRight: Radius.circular(isFirst ? 24 : 16),
                                    bottomLeft: Radius.circular(isLast ? 24 : 16),
                                    bottomRight: Radius.circular(isLast ? 24 : 16),
                                  ),
                                  child: Card(
                                    elevation: 0,
                                    color: Colors.transparent, // Keep transparent background
                                    margin: EdgeInsets.zero, // Card margin handled by Padding
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(isFirst ? 24 : 16), // Use consistent radius
                                        topRight: Radius.circular(isFirst ? 24 : 16),
                                        bottomLeft: Radius.circular(isLast ? 24 : 16),
                                        bottomRight: Radius.circular(isLast ? 24 : 16),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 1. Note Content (if available)
                                          if (noteContent.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 12.0), // Add space below note
                                              child: Text(
                                                noteContent,
                                                style: Theme.of(context).textTheme.bodyLarge, // Use bodyLarge for note
                                                overflow: TextOverflow.visible,
                                              ),
                                            ),
                                          // Show 'Rated' if noteContent is empty
                                          if (noteContent.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 12.0),
                                              child: Text(
                                                AppLocalizations.of(context)!.ratedStatus,
                                                style: TextStyle(
                                                  fontStyle: FontStyle.italic,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),

                                          // 1.5. Lyrics Snapshot (if available)
                                          if (lyricsSnapshot != null && lyricsSnapshot.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 12.0),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.music_note_outlined,
                                                    size: 14,
                                                    color: Theme.of(context).colorScheme.outline,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      lyricsSnapshot,
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        fontStyle: FontStyle.italic,
                                                        color: Theme.of(context).colorScheme.outline,
                                                        height: 1.4,
                                                      ),
                                                      maxLines: 3,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // 2. Bottom Row (Image/Info + Rating)
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.center, // Vertically center items in this row
                                            children: [
                                              // 2a. Left Group (Image + Text Info)
                                              Expanded( // Allow this group to take available space
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.center, // Center image and text column vertically
                                                  children: [
                                                    // Album Cover
                                                    ClipRRect(
                                                      borderRadius: BorderRadius.circular(25.0), // Slightly rounded corners for cover
                                                      child: CachedNetworkImage(
                                                        imageUrl: albumCoverUrl ?? '',
                                                        width: 50, // Adjust size as needed
                                                        height: 50,
                                                        fit: BoxFit.cover,
                                                        placeholder: (context, url) => Container(
                                                          width: 50, height: 50,
                                                          color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(100),
                                                          child: Icon(Icons.music_note_outlined, size: 24, color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.5)),
                                                        ),
                                                        errorWidget: (context, url, error) => Container(
                                                          width: 50, height: 50,
                                                          color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(100),
                                                          child: Icon(Icons.broken_image_outlined, size: 24, color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.5)),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12), // Space between image and text

                                                    // Text Info Column
                                                    Expanded( // Allow text to take remaining space in the inner row
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        mainAxisAlignment: MainAxisAlignment.center, // Center text lines vertically
                                                        children: [
                                                          // Timestamp
                                                          Text(
                                                            AppLocalizations.of(context)!.recordsAt(formattedTime),
                                                            style: Theme.of(context).textTheme.labelSmall?.copyWith( // Use labelMedium for timestamp
                                                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                                              fontWeight: FontWeight.normal,
                                                            ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                          ),
                                                          // Track Name
                                                          Text(
                                                            '${record['trackName'] ?? 'Unknown Track'}',
                                                            style: Theme.of(context).textTheme.bodyLarge?.copyWith( // Use titleMedium for track
                                                              color: Theme.of(context).colorScheme.primary,
                                                              fontWeight: FontWeight.w500, // Slightly bolder track name
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            softWrap: false,
                                                          ),
                                                          // Artist Name
                                                          Text(
                                                            '${record['artistName'] ?? 'Unknown Artist'}',
                                                            style: Theme.of(context).textTheme.bodySmall?.copyWith( // Use bodyMedium for artist
                                                              color: Theme.of(context).colorScheme.secondary,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12), // Space before rating icon

                                              // 2b. Rating Icon
                                              ratingIconWidget,
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Add Divider below each card except the last one
                              if (!isLast)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                            ],
                          ),
                          );
                        },
                        childCount: filteredRecords.length,
                      ),
                          );
                        }
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 100), // Keep padding at the bottom
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}