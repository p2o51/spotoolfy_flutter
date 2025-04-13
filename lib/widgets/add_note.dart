import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/local_database_provider.dart';
import '../services/lyrics_service.dart';
import '../models/track.dart';

class AddNoteSheet extends StatefulWidget {
  const AddNoteSheet({super.key});

  @override
  State<AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<AddNoteSheet> {
  final _controller = TextEditingController();
  String? _selectedRating;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(BuildContext context) async {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final lyricsService = Provider.of<LyricsService>(context, listen: false);

    final currentTrackData = spotifyProvider.currentTrack;
    final trackItem = currentTrackData?['item'];

    if (trackItem == null || _controller.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取歌曲信息或笔记为空')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    String? lyricsSnapshot;
    String errorMsg = '';

    try {
      final trackId = trackItem['id'] as String;
      final track = Track(
        trackId: trackId,
        trackName: trackItem['name'] as String,
        artistName: (trackItem['artists'] as List).map((a) => a['name']).join(', '),
        albumName: trackItem['album']?['name'] as String? ?? 'Unknown Album',
        albumCoverUrl: (trackItem['album']?['images'] as List?)?.isNotEmpty == true
                       ? trackItem['album']['images'][0]['url']
                       : null,
      );

      final songTimestampMs = currentTrackData?['progress_ms'] as int?;
      final spotifyContext = currentTrackData?['context'];
      final contextUri = spotifyContext?['uri'] as String?;
      final contextName = trackItem['album']?['name'] as String? ?? 'Unknown Context';

      try {
        lyricsSnapshot = await lyricsService.getLyrics(track.trackName, track.artistName, track.trackId);
      } catch (e) {
        print('Error fetching lyrics snapshot: $e');
      }

      await localDbProvider.addRecord(
        track: track,
        noteContent: _controller.text,
        rating: _selectedRating,
        songTimestampMs: songTimestampMs,
        contextUri: contextUri,
        contextName: contextName,
        lyricsSnapshot: lyricsSnapshot,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记已保存')),
        );
      }
    } catch (e) {
      print('Error saving note: $e');
      errorMsg += '保存笔记时出错: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg.trim())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spotifyProvider = Provider.of<SpotifyProvider>(context);
    final currentTrack = spotifyProvider.currentTrack?['item'];

    final isTextEmpty = _controller.text.isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  currentTrack?['name'] ?? 'Add Note',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _isSubmitting || isTextEmpty
                    ? null
                    : () => _handleSubmit(context),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.check),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 5,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Show me your feelings...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            autofocus: true,
            onChanged: (value) => setState(() {}),
            enabled: !_isSubmitting,
          ),
        ],
      ),
    );
  }
}