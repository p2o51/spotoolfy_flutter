//roam.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/local_database_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/time_machine_service.dart';
import '../utils/responsive.dart';
import '../widgets/note_poster_preview_page.dart';
import '../widgets/random_review_card.dart';
import '../widgets/time_machine_carousel.dart';
import 'memory_page.dart';

final logger = Logger();

class Roam extends StatefulWidget {
  const Roam({super.key});

  @override
  State<Roam> createState() => _RoamState();
}

class _RoamState extends State<Roam> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Filter state: null = all, 0 = thumb down, 3 = neutral, 5 = fire
  int? _selectedRatingFilter;

  // Show only "Rated" records (no note content)
  bool _showRatedOnly = false;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Time Machine Service
  TimeMachineService? _timeMachineService;

  // SpotifyProvider listener
  SpotifyProvider? _spotifyProvider;

  // PageView controller for carousel
  final PageController _carouselController = PageController();
  int _currentCarouselPage = 0;

  // Random Review auto-cycle state
  int _randomReviewIndex = 0;
  Timer? _randomReviewTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fetch initial data using the provider's public combined fetch method
      Provider.of<LocalDatabaseProvider>(context, listen: false).fetchInitialData(); // Call the public fetch

      // Initialize TimeMachineService and listen for changes
      _spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      _spotifyProvider!.addListener(_onSpotifyProviderChanged);
      _initTimeMachineService();
    });
  }

  void _onSpotifyProviderChanged() {
    // Re-initialize TimeMachineService when user state changes
    if (_timeMachineService == null && _spotifyProvider?.username != null) {
      _initTimeMachineService();
    }
  }

  void _initTimeMachineService() {
    final spotifyProvider = _spotifyProvider ?? Provider.of<SpotifyProvider>(context, listen: false);
    logger.d('TimeMachine init: username=${spotifyProvider.username}');

    if (spotifyProvider.username != null) {
      _timeMachineService = TimeMachineService(spotifyProvider.spotifyAuthService);
      _timeMachineService!.setActiveUser(spotifyProvider.username);
      logger.d('TimeMachineService initialized for user: ${spotifyProvider.username}');
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _spotifyProvider?.removeListener(_onSpotifyProviderChanged);
    _searchController.dispose();
    _carouselController.dispose();
    _randomReviewTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshThoughts() async {
    // Refresh data using the provider's public combined fetch method
    await Provider.of<LocalDatabaseProvider>(context, listen: false).fetchInitialData(); // Call the public fetch
  }

  // --- Helper Methods for Edit/Delete ---

  void _showActionSheet(BuildContext context, Map<String, dynamic> record) {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);

    final recordId = record['id'] as int?;
    final trackId = record['trackId'] as String?;
    final songTimestampMs = record['songTimestampMs'] as int?;
    final trackName = record['trackName'] as String? ?? 'Unknown Track';
    final artistName = record['artistName'] as String? ?? 'Unknown Artist';
    final albumName = record['albumName'] as String? ?? '';
    final albumCoverUrl = record['albumCoverUrl'] as String?;
    final noteContent = record['noteContent'] as String? ?? '';
    final lyricsSnapshot = record['lyricsSnapshot'] as String?;

    // Get rating
    final dynamic ratingRaw = record['rating'];
    int initialRating = 3;
    if (ratingRaw is int) initialRating = ratingRaw;

    if (recordId == null || trackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.incompleteRecordError)),
      );
      return;
    }

    // Format timestamp
    String formattedTimestamp = '';
    if (songTimestampMs != null && songTimestampMs > 0) {
      final duration = Duration(milliseconds: songTimestampMs);
      final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      formattedTimestamp = '$minutes:$seconds';
    }

    // Format recorded time
    final recordedAtRaw = record['recordedAt'];
    String formattedRecordedAt = '';
    if (recordedAtRaw is int) {
      final recordedDateTime = DateTime.fromMillisecondsSinceEpoch(recordedAtRaw).toLocal();
      final dateStr = '${recordedDateTime.year}-${recordedDateTime.month.toString().padLeft(2, '0')}-${recordedDateTime.day.toString().padLeft(2, '0')}';
      final timeStr = '${recordedDateTime.hour.toString().padLeft(2, '0')}:${recordedDateTime.minute.toString().padLeft(2, '0')}';
      formattedRecordedAt = '$dateStr $timeStr';
    }

    HapticFeedback.mediumImpact();

    // State for editing
    final TextEditingController noteController = TextEditingController(text: noteContent);
    int selectedRating = initialRating;
    bool isEditing = false;
    bool hasChanges = false;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;

            // Check if there are unsaved changes
            hasChanges = noteController.text != noteContent || selectedRating != initialRating;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
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
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Scrollable content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Track info header
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
                                // Track details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        trackName,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        artistName,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (albumName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          albumName,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.outline,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      if (formattedRecordedAt.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time, size: 14, color: colorScheme.outline),
                                            const SizedBox(width: 4),
                                            Text(
                                              formattedRecordedAt,
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: colorScheme.outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Rating section
                            Text(
                              AppLocalizations.of(context)!.ratingLabel,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<int>(
                              segments: const <ButtonSegment<int>>[
                                ButtonSegment<int>(value: 0, icon: Icon(Icons.thumb_down_rounded)),
                                ButtonSegment<int>(value: 3, icon: Icon(Icons.sentiment_neutral_rounded)),
                                ButtonSegment<int>(value: 5, icon: Icon(Icons.whatshot_rounded)),
                              ],
                              selected: {selectedRating},
                              onSelectionChanged: (Set<int> newSelection) {
                                HapticFeedback.selectionClick();
                                setSheetState(() {
                                  selectedRating = newSelection.first;
                                });
                              },
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: colorScheme.primaryContainer,
                                selectedForegroundColor: colorScheme.onPrimaryContainer,
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Note content section
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.noteContent,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (!isEditing && noteContent.isNotEmpty)
                                  IconButton(
                                    icon: Icon(Icons.edit_outlined, size: 20, color: colorScheme.primary),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      setSheetState(() => isEditing = true);
                                    },
                                    visualDensity: VisualDensity.compact,
                                    tooltip: AppLocalizations.of(context)!.editNote,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (isEditing || noteContent.isEmpty)
                              TextField(
                                controller: noteController,
                                maxLines: 4,
                                minLines: 2,
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.of(context)!.addNoteHint,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                ),
                                onChanged: (_) => setSheetState(() {}),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  noteContent,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurface,
                                    height: 1.5,
                                  ),
                                ),
                              ),

                            // Lyrics snapshot section
                            if (lyricsSnapshot != null && lyricsSnapshot.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(Icons.music_note_outlined, size: 16, color: colorScheme.outline),
                                  const SizedBox(width: 6),
                                  Text(
                                    AppLocalizations.of(context)!.lyricsSnapshotLabel,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.outline.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  '"$lyricsSnapshot"',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 24),

                            // Action buttons
                            Row(
                              children: [
                                // Play button
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: () async {
                                      HapticFeedback.lightImpact();
                                      Navigator.pop(bottomSheetContext);
                                      final trackUri = 'spotify:track:$trackId';
                                      try {
                                        await spotifyProvider.playTrack(trackUri: trackUri);
                                        if (songTimestampMs != null && songTimestampMs > 0) {
                                          await spotifyProvider.seekToPosition(songTimestampMs);
                                        }
                                      } catch (e) {
                                        logger.d('Error playing track: $e');
                                      }
                                    },
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: Text(formattedTimestamp.isNotEmpty
                                        ? formattedTimestamp
                                        : AppLocalizations.of(context)!.play),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Share button
                                IconButton.filledTonal(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pop(bottomSheetContext);
                                    ResponsiveNavigation.showSecondaryPage(
                                      context: context,
                                      child: NotePosterPreviewPage(
                                        noteContent: noteController.text,
                                        lyricsSnapshot: lyricsSnapshot,
                                        trackTitle: trackName,
                                        artistName: artistName,
                                        albumName: albumName,
                                        rating: selectedRating,
                                        albumCoverUrl: albumCoverUrl,
                                      ),
                                      preferredMode: SecondaryPageMode.fullScreen,
                                    );
                                  },
                                  icon: const Icon(Icons.share_outlined),
                                  tooltip: AppLocalizations.of(context)!.shareNote,
                                ),
                                const SizedBox(width: 8),
                                // Delete button
                                IconButton.filledTonal(
                                  onPressed: () {
                                    HapticFeedback.mediumImpact();
                                    Navigator.pop(bottomSheetContext);
                                    _confirmDeleteRecord(context, recordId, trackId);
                                  },
                                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                                  tooltip: AppLocalizations.of(context)!.deleteNote,
                                ),
                              ],
                            ),

                            // Save changes button (only show if there are changes)
                            if (hasChanges) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    localDbProvider.updateRecord(
                                      recordId: recordId,
                                      trackId: trackId,
                                      newNoteContent: noteController.text.trim(),
                                      newRating: selectedRating,
                                    );
                                    Navigator.pop(bottomSheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(AppLocalizations.of(context)!.changesSaved),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.check_rounded),
                                  label: Text(AppLocalizations.of(context)!.saveChanges),
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

  /// 显示时光机回忆的 Action Sheet
  void _showMemoryActionSheet(BuildContext context, TimeMachineMemory memory, SpotifyProvider spotifyProvider) {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.mediumImpact();

    // 计算几年前
    final yearsAgo = DateTime.now().year - memory.addedAt.year;

    // 格式化添加日期
    final addedDateTime = memory.addedAt.toLocal();
    final dateStr = '${addedDateTime.year}-${addedDateTime.month.toString().padLeft(2, '0')}-${addedDateTime.day.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
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
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Track info header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Album cover
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: memory.albumCoverUrl ?? '',
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
                          // Track details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  memory.trackName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  memory.artistName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  memory.albumName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.outline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Year badge and date info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.history_rounded, size: 20, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.addedYearsAgo(yearsAgo, dateStr),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Action buttons
                      Row(
                        children: [
                          // Play button
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                HapticFeedback.lightImpact();
                                Navigator.pop(bottomSheetContext);
                                try {
                                  await spotifyProvider.playTrack(trackUri: memory.trackUri);
                                } catch (e) {
                                  logger.d('Error playing track: $e');
                                }
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(l10n.play),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // View all memories button
                          IconButton.filledTonal(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.pop(bottomSheetContext);
                              ResponsiveNavigation.showSecondaryPage(
                                context: context,
                                child: MemoryPage(
                                  timeMachineService: _timeMachineService!,
                                ),
                                preferredMode: SecondaryPageMode.sideSheet,
                                maxWidth: 520,
                              );
                            },
                            icon: const Icon(Icons.calendar_month_outlined),
                            tooltip: l10n.thisDayInHistory,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Build swipeable carousel with Time Machine and Random Review
  Widget _buildCarousel(BuildContext context, List<Map<String, dynamic>> allNotesRecords, SpotifyProvider spotifyProvider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Determine which pages to show
    final hasTimeMachine = _timeMachineService != null;
    final hasRandomReview = allNotesRecords.isNotEmpty;
    final pageCount = (hasTimeMachine ? 1 : 0) + (hasRandomReview ? 1 : 0);

    if (pageCount == 0) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 200, // Fixed height for the carousel
          child: PageView(
            controller: _carouselController,
            onPageChanged: (index) {
              HapticFeedback.selectionClick();
              setState(() => _currentCarouselPage = index);
            },
            children: [
              // Page 1: Time Machine (This Day in History)
              if (hasTimeMachine)
                _buildTimeMachinePage(context, spotifyProvider),
              // Page 2: Random Review
              if (hasRandomReview)
                _buildRandomReviewPage(context, allNotesRecords, spotifyProvider),
            ],
          ),
        ),
        // Page indicators
        if (pageCount > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pageCount, (index) {
                final isActive = _currentCarouselPage == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  // Build Time Machine page
  Widget _buildTimeMachinePage(BuildContext context, SpotifyProvider spotifyProvider) {
    return TimeMachineCarousel(
      timeMachineService: _timeMachineService!,
      onMemoryTap: (memory) {
        _showMemoryActionSheet(context, memory, spotifyProvider);
      },
      onViewAllTap: (memories) {
        ResponsiveNavigation.showSecondaryPage(
          context: context,
          child: MemoryPage(
            timeMachineService: _timeMachineService!,
            initialMemories: memories,
            yearsAgo: memories.isNotEmpty ? memories.first.yearsAgo : null,
          ),
          preferredMode: SecondaryPageMode.sideSheet,
          maxWidth: 520,
        );
      },
      onDateRangeTap: () {
        ResponsiveNavigation.showSecondaryPage(
          context: context,
          child: MemoryPage(
            timeMachineService: _timeMachineService!,
          ),
          preferredMode: SecondaryPageMode.sideSheet,
          maxWidth: 520,
        );
      },
    );
  }

  // Start random review auto-cycle timer
  void _startRandomReviewTimer(int recordCount) {
    _randomReviewTimer?.cancel();
    if (recordCount <= 1) return;

    _randomReviewTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && recordCount > 0) {
        setState(() {
          _randomReviewIndex = (_randomReviewIndex + 1) % recordCount;
        });
      }
    });
  }

  // Build Random Review page
  Widget _buildRandomReviewPage(BuildContext context, List<Map<String, dynamic>> records, SpotifyProvider spotifyProvider) {
    if (records.isEmpty) return const SizedBox.shrink();

    // Start timer if not running
    if (_randomReviewTimer == null || !_randomReviewTimer!.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startRandomReviewTimer(records.length);
      });
    }

    // Use cycling index, ensure it's within bounds
    final currentIndex = _randomReviewIndex % records.length;
    final record = records[currentIndex];

    final trackId = record['trackId'] as String?;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: RandomReviewCard(
        key: ValueKey(record['id']),
        record: record,
        onTap: trackId != null ? () => _showActionSheet(context, record) : null,
        onLongPress: trackId != null
            ? () {
                final trackUri = 'spotify:track:$trackId';
                try {
                  spotifyProvider.playTrack(trackUri: trackUri);
                } catch (e) {
                  logger.d('Error playing track from review card: $e');
                }
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // 获取 SpotifyProvider
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    // Consume the LocalDatabaseProvider
    return Consumer<LocalDatabaseProvider>(
      builder: (context, localDbProvider, child) {
        // Single-pass categorization for performance
        final allRecords = localDbProvider.allRecordsOrdered;
        final allNotesRecords = <Map<String, dynamic>>[];
        final allRatedOnlyRecords = <Map<String, dynamic>>[];
        int fireCount = 0, neutralCount = 0, downCount = 0;

        for (final record in allRecords) {
          final noteContent = record['noteContent'] as String? ?? '';
          final rating = record['rating'] as int? ?? 3;

          if (noteContent.isNotEmpty) {
            allNotesRecords.add(record);
            // Count by rating in the same pass
            switch (rating) {
              case 5: fireCount++; break;
              case 0: downCount++; break;
              default: neutralCount++; break;
            }
          } else {
            allRatedOnlyRecords.add(record);
          }
        }

        final totalCount = allNotesRecords.length;
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
                // Swipeable carousel: Time Machine + Random Review (isolated repaint)
                if (_timeMachineService != null || allNotesRecords.isNotEmpty)
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: _buildCarousel(context, allNotesRecords, spotifyProvider),
                    ),
                  ),
                // Search bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
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
                // Rating filter chips with stats - all scrollable together
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        // Stats summary - now scrolls with chips
                        Text(
                          AppLocalizations.of(context)!.statsTotal(totalCount),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Filter chips
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

                          // 计算背景圆角（与卡片一致）
                          final bgBorderRadius = BorderRadius.only(
                            topLeft: Radius.circular(isFirst ? 24 : 16),
                            topRight: Radius.circular(isFirst ? 24 : 16),
                            bottomLeft: Radius.circular(isLast ? 24 : 16),
                            bottomRight: Radius.circular(isLast ? 24 : 16),
                          );

                          // Wrap with Dismissible for swipe gestures
                          return Dismissible(
                            key: Key('record_${recordId ?? index}'),
                            // 改进滑动手感
                            movementDuration: const Duration(milliseconds: 150),
                            resizeDuration: const Duration(milliseconds: 200),
                            dismissThresholds: const {
                              DismissDirection.startToEnd: 0.3,
                              DismissDirection.endToStart: 0.4,
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 24),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: bgBorderRadius,
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
                                borderRadius: bgBorderRadius,
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
                                  // 点击打开笔记详情页（包含播放、编辑、删除选项）
                                  onTap: recordId != null ? () {
                                    HapticFeedback.lightImpact();
                                    _showActionSheet(context, record);
                                  } : null,
                                  onLongPress: recordId != null ? () {
                                    HapticFeedback.mediumImpact();
                                    _showActionSheet(context, record);
                                  } : null,
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
                        addAutomaticKeepAlives: false, // Performance: disable for long lists
                        addRepaintBoundaries: true, // Isolate item repaints
                      ),
                          );
                        }
                      },
                    ),
                  ),
                const SliverToBoxAdapter(
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