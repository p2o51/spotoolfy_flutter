import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart'; // Added logger
// import '../providers/firestore_provider.dart'; // Keep for homoThoughts for now
import '../providers/local_database_provider.dart'; // Import new provider
import '../providers/spotify_provider.dart';
import '../models/record.dart' as model; // Use prefix to avoid name collision
import 'materialui.dart';
import '../utils/date_formatter.dart'; // Assuming getLeadingText uses this

final logger = Logger(); // Added logger instance

class NotesDisplay extends StatefulWidget {
  const NotesDisplay({super.key});

  @override
  State<NotesDisplay> createState() => _NotesDisplayState();
}

class _NotesDisplayState extends State<NotesDisplay> {
  String? _lastFetchedTrackId;

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
                  return ListTile(
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
                      style: const TextStyle(fontSize: 16, height: 0.95),
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
            const IconHeader(
              icon: Icons.library_music_outlined,
              text: 'RELATED THOUGHTS',
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
                  return ListTile(
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
                      style: const TextStyle(fontSize: 16, height: 0.95),
                    ),
                    subtitle: Text(
                      // Access track/artist name from map
                      '${relatedRecord['artistName'] ?? 'Unknown Artist'} - ${relatedRecord['trackName'] ?? 'Unknown Track'}',
                      style: const TextStyle(fontSize: 12),
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