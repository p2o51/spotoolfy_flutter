import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firestore_provider.dart';
import '../providers/spotify_provider.dart';
import 'materialui.dart';
import '../utils/date_formatter.dart';

class NotesDisplay extends StatefulWidget {
  const NotesDisplay({super.key});

  @override
  State<NotesDisplay> createState() => _NotesDisplayState();
}

class _NotesDisplayState extends State<NotesDisplay> {
  @override
  Widget build(BuildContext context) {
    final firestoreProvider = Provider.of<FirestoreProvider>(context);
    final spotifyProvider = Provider.of<SpotifyProvider>(context);
    final currentTrack = spotifyProvider.currentTrack?['item'];

    String getThoughtLeading(List<Map<String, dynamic>> thoughts, int index) {
      if (index == thoughts.length - 1) return '初';  // 最早的一条
      return getLeadingText(thoughts[index]['createdAt']);
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
          if (firestoreProvider.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (firestoreProvider.currentTrackThoughts.isEmpty)
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: firestoreProvider.currentTrackThoughts.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final thought = firestoreProvider.currentTrackThoughts[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        getThoughtLeading(
                          firestoreProvider.currentTrackThoughts, 
                          index
                        ),
                      ),
                    ),
                    title: Text(
                      thought['content'],
                      style: const TextStyle(fontSize: 16, height: 0.95),
                    ),
                  );
                },
              ),
            ),
          if (firestoreProvider.homoThoughts.isNotEmpty) ...[
            const SizedBox(height: 16),
            const IconHeader(
              icon: Icons.library_music_outlined,
              text: 'RELATED THOUGHTS',
            ),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: firestoreProvider.homoThoughts.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final thought = firestoreProvider.homoThoughts[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        getThoughtLeading(
                          firestoreProvider.homoThoughts, 
                          index
                        ),
                      ),
                    ),
                    title: Text(
                      thought['content'],
                      style: const TextStyle(fontSize: 16, height: 0.95),
                    ),
                    subtitle: Text(
                      '${thought['artistName']} - ${thought['trackName']}',
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