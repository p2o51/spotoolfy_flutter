import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart'; // Added logger
// import '../providers/firestore_provider.dart'; // Keep for homoThoughts for now
import '../providers/local_database_provider.dart'; // Import new provider
import '../providers/spotify_provider.dart';
import '../models/record.dart' as model; // Use prefix to avoid name collision
import 'materialui.dart';
import '../utils/date_formatter.dart'; // Assuming getLeadingText uses this
import 'package:flutter/cupertino.dart'; // For CupertinoActionSheet
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

final logger = Logger(); // Added logger instance

class NotesDisplay extends StatefulWidget {
  const NotesDisplay({super.key});

  @override
  State<NotesDisplay> createState() => _NotesDisplayState();
}

class _NotesDisplayState extends State<NotesDisplay> {
  String? _lastFetchedTrackId;

  // --- Helper Methods for Edit/Delete ---
  
  void _showActionSheetForRecord(BuildContext context, model.Record record) {
    // Remove unused variable
    final recordId = record.id;
    final trackId = record.trackId;
    final songTimestampMs = record.songTimestampMs; // 获取时间戳
    // 获取 SpotifyProvider
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);

    if (recordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot proceed: Incomplete record information')),
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

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return CupertinoActionSheet(
          title: Text('Options'),
          actions: <CupertinoActionSheetAction>[
            // 新增：从指定时间播放
            if (trackId != null && songTimestampMs != null && songTimestampMs > 0)
              CupertinoActionSheetAction(
                child: Text('Play from $formattedTimestamp'), // TODO: Add localization
                onPressed: () async {
                  Navigator.pop(bottomSheetContext);
                  final trackUri = 'spotify:track:$trackId';
                  print('Attempting to play URI: $trackUri from $songTimestampMs ms');
                  try {
                    await spotifyProvider.playTrack(trackUri: trackUri);
                    final duration = Duration(milliseconds: songTimestampMs);
                    await spotifyProvider.seekToPosition(duration);
                  } catch (e) {
                    print('Error calling playTrack or seekToPosition: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Playback failed: ${e.toString()}"),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            CupertinoActionSheetAction(
              child: Text(AppLocalizations.of(context)!.editNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _showEditDialogForRecord(context, record);
              },
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              child: Text(AppLocalizations.of(context)!.deleteNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _confirmDeleteRecordForRecord(context, recordId, trackId);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: Text(AppLocalizations.of(context)!.cancel),
            onPressed: () => Navigator.pop(bottomSheetContext),
          ),
        );
      },
    );
  }

  void _showActionSheetForRelatedRecord(BuildContext context, Map<String, dynamic> record) {
    // 对于相关记录，确保从 map 中获取 id, trackId, 和 songTimestampMs
    final recordId = record['id'] as int?;
    final trackId = record['trackId'] as String?;
    final songTimestampMs = record['songTimestampMs'] as int?; // 获取时间戳
    // 获取 SpotifyProvider
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);

    if (recordId == null || trackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot proceed: Incomplete record information')),
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

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return CupertinoActionSheet(
          title: Text(record['trackName'] ?? 'Options'),
          actions: <CupertinoActionSheetAction>[
            // 新增：从指定时间播放
            if (songTimestampMs != null && songTimestampMs > 0)
              CupertinoActionSheetAction(
                child: Text('Play from $formattedTimestamp'), // TODO: Add localization
                onPressed: () async {
                  Navigator.pop(bottomSheetContext);
                  final trackUri = 'spotify:track:$trackId';
                  print('Attempting to play URI: $trackUri from $songTimestampMs ms');
                  try {
                    await spotifyProvider.playTrack(trackUri: trackUri);
                    final duration = Duration(milliseconds: songTimestampMs);
                    await spotifyProvider.seekToPosition(duration);
                  } catch (e) {
                    print('Error calling playTrack or seekToPosition: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Playback failed: ${e.toString()}"),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            CupertinoActionSheetAction(
              child: Text(AppLocalizations.of(context)!.editNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _showEditDialogForRelatedRecord(context, record);
              },
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              child: Text(AppLocalizations.of(context)!.deleteNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _confirmDeleteRecordForRelatedRecord(context, recordId, trackId);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: Text(AppLocalizations.of(context)!.cancel),
            onPressed: () => Navigator.pop(bottomSheetContext),
          ),
        );
      },
    );
  }

  void _showEditDialogForRecord(BuildContext context, model.Record record) {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final recordId = record.id!; // 我们在上面检查过了
    final trackId = record.trackId;
    final initialContent = record.noteContent ?? '';
    final initialRating = record.rating ?? 3; // 默认值为 3

    final TextEditingController textController = TextEditingController(text: initialContent);
    int selectedRating = initialRating;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.editNote),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: null,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.noteContent,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 0, icon: Icon(Icons.thumb_down_outlined)),
                        ButtonSegment<int>(value: 3, icon: Icon(Icons.sentiment_neutral_rounded)),
                        ButtonSegment<int>(value: 5, icon: Icon(Icons.whatshot_outlined)),
                      ],
                      selected: {selectedRating},
                      onSelectionChanged: (Set<int> newSelection) {
                        setDialogState(() {
                          selectedRating = newSelection.first;
                        });
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
                    localDbProvider.updateRecord(
                      recordId: recordId,
                      trackId: trackId,
                      newNoteContent: textController.text.trim(),
                      newRating: selectedRating,
                    );
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDialogForRelatedRecord(BuildContext context, Map<String, dynamic> record) {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final recordId = record['id'] as int;
    final trackId = record['trackId'] as String;
    final initialContent = record['noteContent'] as String? ?? '';
    
    // 处理从旧数据格式中可能的字符串评分
    dynamic initialRatingRaw = record['rating'];
    int initialRating = 3; // 默认值
    if (initialRatingRaw is int) {
      initialRating = initialRatingRaw;
    } else if (initialRatingRaw is String) {
      initialRating = 3; // 对编辑来说，将旧数据格式的字符串视为默认值 3
    }

    final TextEditingController textController = TextEditingController(text: initialContent);
    int selectedRating = initialRating;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.editNote),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: null,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.noteContent,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 0, icon: Icon(Icons.thumb_down_outlined)),
                        ButtonSegment<int>(value: 3, icon: Icon(Icons.sentiment_neutral_rounded)),
                        ButtonSegment<int>(value: 5, icon: Icon(Icons.whatshot_outlined)),
                      ],
                      selected: {selectedRating},
                      onSelectionChanged: (Set<int> newSelection) {
                        setDialogState(() {
                          selectedRating = newSelection.first;
                        });
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                  onPressed: () {
                    localDbProvider.updateRecord(
                      recordId: recordId,
                      trackId: trackId,
                      newNoteContent: textController.text.trim(),
                      newRating: selectedRating,
                    );
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteRecordForRecord(BuildContext context, int recordId, String trackId) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const Text('Are you sure you want to delete this note? This action cannot be undone.'),
          actions: [
            TextButton(
              child: Text(AppLocalizations.of(context)!.cancel),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete'),
              onPressed: () {
                Provider.of<LocalDatabaseProvider>(context, listen: false).deleteRecord(
                  recordId: recordId,
                  trackId: trackId,
                );
                Navigator.pop(dialogContext);
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteRecordForRelatedRecord(BuildContext context, int recordId, String trackId) {
    // 对于关联记录的删除确认，我们可以重用相同的逻辑
    _confirmDeleteRecordForRecord(context, recordId, trackId);
  }

  @override
  Widget build(BuildContext context) {
    // Remove FirestoreProvider if no longer needed after this change
    // final firestoreProvider = Provider.of<FirestoreProvider>(context); 
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context);
    final spotifyProvider = Provider.of<SpotifyProvider>(context);
    final currentTrack = spotifyProvider.currentTrack?['item'];
    final currentTrackId = currentTrack?['id'] as String?;
    final currentTrackName = currentTrack?['name'] as String?; // Get track name

    // Fetch records and related records if track changed
    if (currentTrackId != null && currentTrackId != _lastFetchedTrackId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          logger.d('NotesDisplay: Track changed, fetching records for $currentTrackId');
          localDbProvider.fetchRecordsForTrack(currentTrackId);
          // Also fetch related records
          if (currentTrackName != null) {
             logger.d('NotesDisplay: Fetching related records for "$currentTrackName"');
             localDbProvider.fetchRelatedRecords(currentTrackId, currentTrackName);
          }
          setState(() {
            _lastFetchedTrackId = currentTrackId;
          });
        }
      });
    } else if (currentTrackId == null && _lastFetchedTrackId != null) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
            logger.d('NotesDisplay: Track is null, clearing last fetched ID and related records');
            // Clear related records when track becomes null
            localDbProvider.clearRelatedRecords(); // Need to add this method
            setState(() {
               _lastFetchedTrackId = null;
            });
         }
       });
    }

    // Helper for current track thoughts (using model.Record)
    String getCurrentThoughtLeading(List<model.Record> records, int index) {
      if (index == records.length - 1) return '初';
      final dt = DateTime.fromMillisecondsSinceEpoch(records[index].recordedAt);
      // Format DateTime to ISO 8601 String for getLeadingText
      return getLeadingText(dt.toIso8601String()); 
    }

    // Helper for related thoughts (using Map from Local DB)
    String getRelatedThoughtLeading(List<Map<String, dynamic>> records, int index) {
      if (index == records.length - 1) return '初';
      final recordedAtTimestamp = records[index]['recordedAt'] as int?;
      if (recordedAtTimestamp != null) {
         final dt = DateTime.fromMillisecondsSinceEpoch(recordedAtTimestamp);
         return getLeadingText(dt.toIso8601String());
      }
      return '?';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconHeader(
            icon: Icons.comment_bank_outlined, 
            text: currentTrack != null 
              ? 'THOUGHTS'
              : 'NO TRACK'
          ),
          if (currentTrackId == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Play a track to see thoughts.'),
              ),
            )
          else if (localDbProvider.isLoading && _lastFetchedTrackId == currentTrackId && localDbProvider.currentTrackRecords.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (localDbProvider.currentTrackRecords.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No ideas for this song yet. \n Come share the first idea!',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: localDbProvider.currentTrackRecords.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final record = localDbProvider.currentTrackRecords[index];
                  // Determine the icon based on the integer rating
                  IconData ratingIcon;
                  switch (record.rating) {
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
                  
                  // 为 ListTile 添加长按功能
                  return InkWell(
                    onLongPress: () => _showActionSheetForRecord(context, record),
                    // 使 InkWell 占据整个宽度，以便长按事件更容易触发
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          getCurrentThoughtLeading(
                            localDbProvider.currentTrackRecords,
                            index,
                          ),
                        ),
                      ),
                      title: Text(
                        record.noteContent ?? '',
                        style: const TextStyle(fontSize: 16, height: 1.05),
                      ),
                      // Add the rating icon as the trailing widget
                      trailing: Icon(ratingIcon, color: Theme.of(context).colorScheme.secondary),
                    ),
                  );
                },
              ),
            ),
          // --- RELATED THOUGHTS (Use LocalDatabaseProvider) ---
          // Show loading indicator if fetching related records
          if (localDbProvider.isLoadingRelated)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          // Show related thoughts only if not loading and list is not empty
          else if (localDbProvider.relatedRecords.isNotEmpty) ...[
            const SizedBox(height: 16),
            IconHeader(
              icon: Icons.library_music_outlined,
              text: 'Related Thoughts',
            ),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Use relatedRecords from LocalDatabaseProvider
                itemCount: localDbProvider.relatedRecords.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  // Access data from the map
                  final relatedRecord = localDbProvider.relatedRecords[index];
                  // Determine the icon based on the integer rating from the map
                  IconData relatedRatingIcon;
                  final int? ratingValue = relatedRecord['rating'] as int?;
                  switch (ratingValue) {
                    case 0:
                      relatedRatingIcon = Icons.thumb_down_outlined;
                      break;
                    case 5:
                      relatedRatingIcon = Icons.whatshot_outlined;
                      break;
                    case 3:
                    default:
                      relatedRatingIcon = Icons.sentiment_neutral_rounded;
                      break;
                  }
                  
                  // 为相关记录的 ListTile 添加长按功能
                  return InkWell(
                    onLongPress: () => _showActionSheetForRelatedRecord(context, relatedRecord),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          // Use the correct helper function
                          getRelatedThoughtLeading(
                            localDbProvider.relatedRecords,
                            index,
                          ),
                        ),
                      ),
                      title: Text(
                        // Access note content from map
                        relatedRecord['noteContent'] ?? '',
                        style: const TextStyle(fontSize: 16, height: 1.05),
                      ),
                      subtitle: Text(
                        // Access track/artist name from map
                        '[0m${relatedRecord['artistName'] ?? AppLocalizations.of(context)!.unknownArtist} - ${relatedRecord['trackName'] ?? AppLocalizations.of(context)!.unknownTrack}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      // Add the rating icon as the trailing widget for related records
                      trailing: Icon(relatedRatingIcon, color: Theme.of(context).colorScheme.secondary),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}