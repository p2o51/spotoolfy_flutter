import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/local_database_provider.dart';
import '../models/track.dart';
import 'package:flutter/services.dart';
import './materialui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';

class AddNoteSheet extends StatefulWidget {
  final String? prefilledContent;
  
  const AddNoteSheet({super.key, this.prefilledContent});

  @override
  State<AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<AddNoteSheet> {
  final _controller = TextEditingController();
  int? _selectedRatingValue;
  bool _isSubmitting = false;
  static const String _lastUsedRatingKey = 'last_used_rating';

  // State variables to store track info when the sheet opens
  Map<String, dynamic>? _initialTrackItem;
  int? _initialTimestampMs;
  Map<String, dynamic>? _initialContext;
  String? _initialTrackName; // Store track name separately for the title

  @override
  void initState() {
    super.initState();
    // Capture the track info when the sheet is initialized
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrackData = spotifyProvider.currentTrack;
    if (currentTrackData != null) {
      _initialTrackItem = currentTrackData['item'] as Map<String, dynamic>?;
      _initialTimestampMs = currentTrackData['progress_ms'] as int?;
      _initialContext = currentTrackData['context'] as Map<String, dynamic>?;
      _initialTrackName = _initialTrackItem?['name'] as String?; // Store name
    }

    // 设置预填充内容
    if (widget.prefilledContent != null) {
      _controller.text = widget.prefilledContent!;
    }

    _loadLastUsedRating();
  }

  // 加载上次使用的评分
  Future<void> _loadLastUsedRating() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRating = prefs.getInt(_lastUsedRatingKey);
      if (lastRating != null) {
        setState(() {
          _selectedRatingValue = lastRating;
        });
      }
    } catch (e) {
      // 获取失败时保持默认评分，不需要额外处理
      debugPrint('Failed to load last used rating: $e');
    }
  }

  // 保存当前使用的评分
  Future<void> _saveLastUsedRating(int rating) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastUsedRatingKey, rating);
    } catch (e) {
      // 保存失败不影响应用功能，仅记录日志
      debugPrint('Failed to save last used rating: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(BuildContext context) async {
    HapticFeedback.lightImpact();
    // Capture the context before the async gap
    final currentContext = context;
    final localDbProvider = Provider.of<LocalDatabaseProvider>(currentContext, listen: false);

    // Use the initial track data stored in the state
    final trackItem = _initialTrackItem;

    if (trackItem == null) {
      if (currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(currentContext)!.noTrackOrEmptyNote)),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    String errorMsg = '';

    try {
      final trackId = trackItem['id'] as String;
      final track = Track(
        trackId: trackId,
        trackName: trackItem['name'] as String,
        artistName: (trackItem['artists'] as List).map((a) => a['name']).join(', '),
        albumName: trackItem['album']?['name'] as String? ?? AppLocalizations.of(context)!.unknownAlbum,
        albumCoverUrl: (trackItem['album']?['images'] as List?)?.isNotEmpty == true
                       ? trackItem['album']['images'][0]['url']
                       : null,
      );

      // Use initial timestamp and context
      final songTimestampMs = _initialTimestampMs;
      final spotifyContext = _initialContext;
      final contextUri = spotifyContext?['uri'] as String?;
      // Use album name from initial track item or context name as fallback
      final contextName = trackItem['album']?['name'] as String?
                          ?? (spotifyContext?['type'] == 'playlist' ? AppLocalizations.of(context)!.playlist : AppLocalizations.of(context)!.unknownContext);

      await localDbProvider.addRecord(
        track: track,
        noteContent: _controller.text,
        rating: _selectedRatingValue,
        songTimestampMs: songTimestampMs,
        contextUri: contextUri,
        contextName: contextName,
      );

      if (currentContext.mounted) {
        Navigator.pop(currentContext);
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(currentContext)!.noteSaved)),
        );
      }
    } catch (e) {
      if (currentContext.mounted) {
        // Fetch localization string inside the mounted check
        errorMsg = AppLocalizations.of(currentContext)!.errorSavingNote(e.toString());
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text(errorMsg)), // errorMsg already includes the e.toString()
        );
      }
    } finally {
      if (currentContext.mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  _initialTrackName ?? AppLocalizations.of(context)!.addNote,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _isSubmitting
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
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.noteHint,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            autofocus: true,
            onChanged: (value) => setState(() {}),
            enabled: !_isSubmitting,
          ),
          const SizedBox(height: 16),
          // --- Add the Ratings Widget Here ---
          Center(
            child: Ratings(
              initialRating: _selectedRatingValue, // Pass the current int rating
              onRatingChanged: (newRating) { // Rename parameter for clarity
                 // Directly use the passed rating value (0, 3, or 5)
                setState(() {
                  _selectedRatingValue = newRating;
                  // 保存最后使用的评分
                  _saveLastUsedRating(_selectedRatingValue!);
                });
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}