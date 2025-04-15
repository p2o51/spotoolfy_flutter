//roam.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../providers/firestore_provider.dart'; // Remove old provider
import '../providers/local_database_provider.dart'; // Import new provider
// import 'package:flutter/services.dart'; // Unnecessary import removed
import 'package:cached_network_image/cached_network_image.dart'; // Import CachedNetworkImage
import 'package:flutter/cupertino.dart'; // For CupertinoActionSheet
// import '../widgets/carousel_view.dart'; // Removed incorrect import
import '../widgets/materialui.dart'; // Import materialui which contains CarouselView
import '../providers/spotify_provider.dart'; // <--- 添加 SpotifyProvider 导入

class Roam extends StatefulWidget {
  const Roam({super.key});

  @override
  State<Roam> createState() => _RoamState();
}

class _RoamState extends State<Roam> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fetch initial data using the provider's public combined fetch method
      Provider.of<LocalDatabaseProvider>(context, listen: false).fetchInitialData(); // Call the public fetch
    });
  }

  Future<void> _refreshThoughts() async {
    // Refresh data using the provider's public combined fetch method
    await Provider.of<LocalDatabaseProvider>(context, listen: false).fetchInitialData(); // Call the public fetch
  }

  // --- Helper Methods for Edit/Delete ---

  void _showActionSheet(BuildContext context, Map<String, dynamic> record) {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    // Ensure your map fetched from the DB includes 'id' and 'trackId'
    final recordId = record['id'] as int?;
    final trackId = record['trackId'] as String?;

    if (recordId == null || trackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot proceed: Incomplete record information')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      // Use RootNavigator to ensure it appears above bottom nav bar if applicable
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        // Using CupertinoActionSheet for iOS style, you can use Column + ListTiles for Material
        return CupertinoActionSheet(
          title: Text(record['trackName'] ?? 'Options'),
          // message: Text(record['noteContent'] ?? ''), // Optional: show content snippet
          actions: <CupertinoActionSheetAction>[
            CupertinoActionSheetAction(
              child: const Text('Edit Note'),
              onPressed: () {
                Navigator.pop(bottomSheetContext); // Close the sheet
                _showEditDialog(context, record); // Show edit dialog
              },
            ),
            CupertinoActionSheetAction(
              child: const Text('Delete Note'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(bottomSheetContext); // Close the sheet
                _confirmDeleteRecord(context, recordId, trackId); // Show delete confirmation
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.pop(bottomSheetContext);
            },
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
                title: const Text('Edit Note'),
                content: SingleChildScrollView( // Allow scrolling if content is long
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: textController,
                        maxLines: null, // Allow multiple lines
                        decoration: const InputDecoration(
                          labelText: 'Note Content',
                          border: OutlineInputBorder(),
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
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                  TextButton(
                    child: const Text('Save'),
                    onPressed: () {
                      // TODO: Ensure provider has updateRecord method implemented
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
          title: const Text('Confirm Delete'),
          content: const Text('Are you sure you want to delete this note? This action cannot be undone.'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete'),
              onPressed: () {
                // TODO: Ensure provider has deleteRecord method implemented
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

  @override
  Widget build(BuildContext context) {
    // 获取 SpotifyProvider
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    // Consume the LocalDatabaseProvider
    return Consumer<LocalDatabaseProvider>(
      builder: (context, localDbProvider, child) {
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _refreshThoughts,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Add the new NotesCarouselView here
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: NotesCarouselView(),
                  ),
                ),
                // Use the provider's loading state AND check the ALL records list
                if (localDbProvider.isLoading && localDbProvider.allRecordsOrdered.isEmpty) // Show loading only if all records list is empty
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                // Use the ALL records list for the empty state
                else if (localDbProvider.allRecordsOrdered.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        '还没有任何笔记...',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // Use the ALL records list now
                          if (index >= localDbProvider.allRecordsOrdered.length) {
                            return null;
                          }
                          
                          // Access data using map keys from the ALL records list
                          final record = localDbProvider.allRecordsOrdered[index];
                          // Determine if it's the first/last item in the ALL list
                          final isFirst = index == 0;
                          final isLast = index == localDbProvider.allRecordsOrdered.length - 1;
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
                               formattedTime = 'Today $timeStr';
                             } else if (recordDate == yesterday) {
                               formattedTime = 'Yesterday $timeStr';
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
                                 formattedTime = '今天 $timeStr';
                               } else if (recordDate == yesterday) {
                                 formattedTime = '昨天 $timeStr';
                               } else {
                                 final dateStr = '${recordedDateTime.month.toString().padLeft(2, '0')}-${recordedDateTime.day.toString().padLeft(2, '0')}';
                                 formattedTime = '$dateStr $timeStr';
                               }
                            } catch (e) {
                              print("Error parsing timestamp string: $e");
                              // Keep 'Unknown Time' if parsing fails
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: InkWell(
                              onTap: trackId != null ? () {
                                print('Tapped on card with trackId: $trackId');
                                final trackUri = 'spotify:track:$trackId';
                                print('Attempting to play URI: $trackUri');
                                try {
                                  spotifyProvider.playTrack(trackUri: trackUri);
                                  // REMOVED Playback SnackBar
                                } catch (e) {
                                   print('Error calling playTrack: $e');
                                   ScaffoldMessenger.of(context).showSnackBar( // Keep error SnackBar
                                    SnackBar(
                                      content: Text('播放失败: $e'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } : null,
                              onLongPress: recordId != null ? () { print('Long pressed on card with recordId: $recordId'); _showActionSheet(context, record); } : () { print('Long press disabled for record: ${record['noteContent']}'); },
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(isFirst ? 24 : 8),
                                topRight: Radius.circular(isFirst ? 24 : 8),
                                bottomLeft: Radius.circular(isLast ? 24 : 8),
                                bottomRight: Radius.circular(isLast ? 24 : 8),
                              ),
                              child: Card(
                                elevation: 0,
                                color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(153),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(isFirst ? 24 : 8),
                                    topRight: Radius.circular(isFirst ? 24 : 8),
                                    bottomLeft: Radius.circular(isLast ? 24 : 8),
                                    bottomRight: Radius.circular(isLast ? 24 : 8),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column( // Outer column for timestamp + main content row
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Timestamp Row (stays at top right)
                                      Row(
                                        children: [
                                          const Spacer(),
                                          Text(
                                            'Records at $formattedTime',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Main Content Row (Cover + Text Column)
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.end, // 保持底部对齐
                                        children: [
                                          // Column 1: Album Cover (No Align needed here)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(50.0),
                                            child: CachedNetworkImage(
                                              imageUrl: albumCoverUrl ?? '',
                                              width: 100, // 改为80
                                              height: 100, // 改为80
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => Container(
                                                width: 100, // 改为80
                                                height: 100, // 改为80
                                                color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(100),
                                                child: Icon(Icons.music_note_outlined, size: 30, color: Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.5)),
                                              ),
                                              errorWidget: (context, url, error) => Container(
                                                width: 100, // 改为80
                                                height: 100, // 改为80
                                                color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(100),
                                                child: Icon(Icons.broken_image_outlined, size: 30, color: Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.5)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16), // Space between columns

                                          // Column 2: Text Info & Rating
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.end, // 使列底部对齐
                                              mainAxisSize: MainAxisSize.min, // 保持内容紧凑
                                              children: [
                                                // Note Content (remains at top)
                                                if (record['noteContent'] != null && (record['noteContent'] as String).isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: 8.0),
                                                    child: Text(
                                                      record['noteContent'] ?? '',
                                                      style: Theme.of(context).textTheme.bodyLarge,
                                                      maxLines: 3,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                
                                                // 将评分图标和歌曲信息放在同一行，实现底部对齐
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    // 歌曲和艺术家信息
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          // Track Name
                                                          Text(
                                                            '${record['trackName'] ?? 'Unknown Track'}',
                                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                              fontWeight: FontWeight.bold,
                                                              color: Theme.of(context).colorScheme.primary,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            softWrap: false,
                                                          ),
                                                          // Artist Name
                                                          Text(
                                                            '${record['artistName'] ?? 'Unknown Artist'}',
                                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                              color: Theme.of(context).colorScheme.secondary,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    // 评分图标
                                                    (() { // IIFE for rating logic
                                                      final dynamic ratingRaw = record['rating'];
                                                      int? ratingValue;
                                                      if (ratingRaw is int) { ratingValue = ratingRaw; }
                                                      else if (ratingRaw is String) { ratingValue = 3; }
                                                      IconData ratingIcon;
                                                      switch (ratingValue) {
                                                        case 0: ratingIcon = Icons.thumb_down_outlined; break;
                                                        case 5: ratingIcon = Icons.whatshot_outlined; break;
                                                        case 3: default: ratingIcon = Icons.sentiment_neutral_rounded; break;
                                                      }
                                                      return Icon(ratingIcon, color: Theme.of(context).colorScheme.primary, size: 24);
                                                    }()),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: localDbProvider.allRecordsOrdered.length,
                      ),
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

// --- Add the new NotesCarouselView Widget ---

class NotesCarouselView extends StatelessWidget {
  const NotesCarouselView({super.key});

  // Helper to build the rating icon
  Widget _buildRatingIcon(BuildContext context, dynamic ratingRaw) {
      int? ratingValue;
      if (ratingRaw is int) {
        ratingValue = ratingRaw;
      } else if (ratingRaw is String) {
        ratingValue = 3; // Default for old string data
      }

      IconData ratingIcon;
      switch (ratingValue) {
        case 0:
          ratingIcon = Icons.thumb_down_outlined;
          break;
        case 5:
          ratingIcon = Icons.whatshot_outlined;
          break;
        case 3:
        default:
          ratingIcon = Icons.sentiment_neutral_rounded;
          break;
      }
      return Icon(ratingIcon, color: Theme.of(context).colorScheme.primary, size: 20);
  }


  @override
  Widget build(BuildContext context) {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context);
    // Get SpotifyProvider for playback
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final randomRecords = localDbProvider.randomRecords;

    // Don't show carousel if loading or no records
    if (localDbProvider.isLoading || randomRecords.isEmpty) {
       return const SizedBox.shrink(); 
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final carouselHeight = screenWidth > 900 ? 250.0 : 240.0;
        final flexWeights = screenWidth > 900
            ? const [1, 2, 5, 2, 1]
            : screenWidth > 600
            ? const [1, 4, 1]
            : const [1, 5, 1];

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: carouselHeight),
            child: CarouselView.weighted(
              flexWeights: flexWeights,
              shrinkExtent: 0,
              itemSnapping: true,
              // Use the onTap property of CarouselView.weighted
              onTap: (index) {
                // Ensure index is valid
                if (index >= 0 && index < randomRecords.length) {
                  final record = randomRecords[index];
                  final trackId = record['trackId'] as String?;
                  if (trackId != null) {
                    print('Tapped on carousel index: $index, trackId: $trackId');
                    final trackUri = 'spotify:track:$trackId';
                    print('Attempting to play URI from carousel: $trackUri');
                    try {
                      spotifyProvider.playTrack(trackUri: trackUri);
                      // REMOVED SnackBar for playback attempt in carousel
                      // ScaffoldMessenger.of(context).showSnackBar(
                      //   SnackBar(
                      //     content: Text('正在尝试播放: ${record['trackName'] ?? trackId}'),
                      //     duration: const Duration(seconds: 2),
                      //   ),
                      // );
                    } catch (e) {
                      print('Error calling playTrack from carousel: $e');
                      ScaffoldMessenger.of(context).showSnackBar( // Keep error SnackBar
                        SnackBar(
                          content: Text('播放失败: $e'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } else {
                     print('Tapped on carousel index: $index, but trackId is null.');
                  }
                } else {
                   print('Error: Invalid index ($index) tapped in CarouselView.');
                }
              },
              children: randomRecords.map((record) {
                final imageUrl = record['albumCoverUrl'] as String?;
                final fallbackColor = Theme.of(context).colorScheme.secondaryContainer.withAlpha(204);
                // final trackId = record['trackId'] as String?; // No longer needed here

                // Remove the InkWell wrapper
                // print('Building carousel item for trackId: $trackId'); // Removed diagnostic print
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background Image
                        if (imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: fallbackColor),
                            errorWidget: (context, url, error) => Container(
                              color: fallbackColor,
                              child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                            ),
                          )
                        else
                          Container(color: fallbackColor),

                        // Content Overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.7)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Note Content
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.format_quote_rounded,
                                      size: 20,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        record['noteContent'] ?? '',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Divider(color: Colors.white.withOpacity(0.3)),
                              const SizedBox(height: 8),
                              // Track Info and Rating
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${record['trackName'] ?? 'Unknown Track'}',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${record['artistName'] ?? 'Unknown Artist'}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.white.withOpacity(0.8),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildRatingIcon(context, record['rating']), // Use helper
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // Optional: Add a loading carousel placeholder like in MyCarouselView
  // Widget _buildLoadingCarousel(BuildContext context) { ... }
}