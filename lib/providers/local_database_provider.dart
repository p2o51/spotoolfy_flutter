import 'dart:convert'; // For jsonEncode
import 'dart:io'; // For File
import 'package:path_provider/path_provider.dart'; // For temporary directory
import 'package:share_plus/share_plus.dart'; // For sharing file
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import '../models/record.dart';
import '../models/track.dart'; // Assuming Track might be needed indirectly
import '../models/translation.dart';
import '../providers/spotify_provider.dart'; // Import SpotifyProvider
import '../services/lyrics_service.dart';
import 'package:file_picker/file_picker.dart'; // For picking file
import 'package:logger/logger.dart'; // Added logger
import 'package:flutter/material.dart'; // 需要引入 Material 用于 AlertDialog 等

final logger = Logger(); // Added logger instance

class LocalDatabaseProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SpotifyProvider _spotifyProvider; // Add SpotifyProvider instance variable
  final LyricsService _lyricsService = LyricsService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Record> _currentTrackRecords = [];
  List<Record> get currentTrackRecords => _currentTrackRecords;

  // --- Add state for latest played time of the current track ---
  int? _currentTrackLatestPlayedAt;
  int? get currentTrackLatestPlayedAt => _currentTrackLatestPlayedAt;
  // --- End added state ---

  // Example internal state for random records
  List<Map<String, dynamic>> _randomRecords = [];
  List<Map<String, dynamic>> get randomRecords => _randomRecords;

  // --- New State for all records ordered by time ---
  List<Map<String, dynamic>> _allRecordsOrdered = [];
  List<Map<String, dynamic>> get allRecordsOrdered => _allRecordsOrdered;
  // Use the existing _isLoading or add a specific one if needed
  // bool _isLoadingAll = false;
  // bool get isLoadingAll => _isLoadingAll;
  // --- End New State ---

  // Example internal state for fetched translation
  Translation? _fetchedTranslation;
  Translation? get fetchedTranslation => _fetchedTranslation;

  // State for related records
  List<Map<String, dynamic>> _relatedRecords = [];
  List<Map<String, dynamic>> get relatedRecords => _relatedRecords;
  bool _isLoadingRelated = false; // Separate loading state
  bool get isLoadingRelated => _isLoadingRelated;

  // State for recent play contexts
  List<Map<String, dynamic>> _recentContexts = [];
  List<Map<String, dynamic>> get recentContexts => _recentContexts;
  // Optional: Separate loading state for contexts if needed
  // bool _isLoadingContexts = false;
  // bool get isLoadingContexts => _isLoadingContexts;

  String? _lastProcessedTrackIdForPlayedAt; // Re-introduce state to track changes

  // Constructor accepts SpotifyProvider
  LocalDatabaseProvider(this._spotifyProvider) {
    _initializeProvider();
  }

  // Private async initialization method
  Future<void> _initializeProvider() async {
    // Insert sample data if the database is empty on provider creation
    await _dbHelper.insertSampleDataIfNotExists();
    // Update latest played time on initialization
    await _updateInitialRecentlyPlayed();
    // Fetch initial data (both random and all ordered)
    await fetchInitialData();
  }

  Future<void> _updateInitialRecentlyPlayed() async {
     logger.d('Updating initial recently played tracks...');
     try {
        // Check if logged in before proceeding
        if (!_spotifyProvider.username!.isNotEmpty) { // More robust check
            logger.d('User not logged in, skipping initial recently played update.');
            return;
        }

        final recentRawTracks = await _spotifyProvider.getRecentlyPlayedRawTracks(limit: 50);
        if (recentRawTracks.isEmpty) {
           logger.d('No recent tracks found from Spotify API.');
           return;
        }

        // Use a batch for potentially faster updates, though individual updates are fine too
        final batch = await _dbHelper.database.then((db) => db.batch());
        int updatedCount = 0;

        for (final item in recentRawTracks) {
           final track = item['track'];
           final playedAtStr = item['played_at'];

           if (track != null && track['id'] != null && playedAtStr != null) {
              final trackId = track['id'] as String;
              try {
                 final playedAtTimestamp = DateTime.parse(playedAtStr).millisecondsSinceEpoch;
                 // Use db.update directly here for simplicity, or use helper method
                  batch.update(
                    'tracks',
                    {'latestPlayedAt': playedAtTimestamp},
                    where: 'trackId = ?',
                    whereArgs: [trackId],
                  );
                 updatedCount++;
              } catch (e) {
                 logger.d('Error parsing played_at date or preparing batch for track $trackId: $e');
              }
           }
        }
        
        if (updatedCount > 0) {
          await batch.commit(noResult: true); // Don't need individual results
          logger.d('Batch update for $updatedCount recently played tracks committed.');
        } else {
          logger.d('No valid recently played tracks found to update.');
        }

     } catch (e) {
        logger.d('Error updating initial recently played tracks: $e');
     }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setLoadingRelated(bool value) {
    _isLoadingRelated = value;
    notifyListeners();
  }

  // --- Data Fetching Methods (Stubs initially) ---

  Future<void> fetchRecordsForTrack(String trackId) async {
    _setLoading(true);
    try {
      // Fetch records
      final recordsFromDb = await _dbHelper.getRecordsForTrack(trackId);
      _currentTrackRecords = List<Record>.from(recordsFromDb);

      // --- Fetch latestPlayedAt for the track --- 
      final trackInfo = await _dbHelper.getTrack(trackId);
      _currentTrackLatestPlayedAt = trackInfo?.latestPlayedAt;
      logger.d('Fetched latestPlayedAt for track $trackId: $_currentTrackLatestPlayedAt');
      // --- End fetching latestPlayedAt ---

    } catch (e) {
      logger.d('Error fetching records or track info for $trackId: $e');
      _currentTrackRecords = []; // Clear records on error
      _currentTrackLatestPlayedAt = null; // Clear timestamp on error
    } finally {
       _setLoading(false);
    }
  }

  Future<void> fetchRandomRecords(int count) async {
     _setLoading(true);
     logger.d('Fetching $count random records with track info...');
     try {
       // Ensure the list is mutable
       final recordsFromDb = await _dbHelper.getRandomRecordsWithTrackInfo(count);
       _randomRecords = List<Map<String, dynamic>>.from(recordsFromDb);
     } catch (e) {
       logger.d('Error fetching random records: $e');
       _randomRecords = []; // Clear on error
     } finally {
        _setLoading(false); // This will notify listeners
     }
  }

  Future<Translation?> fetchTranslation(String trackId, String languageCode, String style) async {
     _setLoading(true);
     logger.d('fetchTranslation($trackId, $languageCode, $style) called');
     try {
        _fetchedTranslation = await _dbHelper.getTranslation(trackId, languageCode, style);
        return _fetchedTranslation;
     } catch (e) {
       logger.d('Error fetching translation: $e');
       _fetchedTranslation = null;
       return null;
     } finally {
        _setLoading(false);
        // notifyListeners(); // Called in _setLoading. Consider if UI needs update even if called internally.
     }
  }

  /// Retrieves a track by its Spotify trackId.
  Future<Track?> getTrack(String trackId) async {
    // Simply delegates to the DatabaseHelper method
    return await _dbHelper.getTrack(trackId);
  }

  /// Fetches records related to the currently playing track by track name.
  Future<void> fetchRelatedRecords(String currentTrackId, String trackName, {int limit = 5}) async {
    _setLoadingRelated(true);
    logger.d('Fetching related records for "$trackName" (excluding $currentTrackId)...');
    try {
      // Ensure the list is mutable
      final recordsFromDb = await _dbHelper.fetchRelatedRecords(currentTrackId, trackName, limit);
      _relatedRecords = List<Map<String, dynamic>>.from(recordsFromDb);
    } catch (e) {
      logger.d('Error fetching related records: $e');
      _relatedRecords = []; // Clear on error
    } finally {
      _setLoadingRelated(false);
    }
  }

  /// Clears the locally stored related records list.
  void clearRelatedRecords() {
    bool changed = false;
    if (_relatedRecords.isNotEmpty) {
       _relatedRecords = [];
       changed = true;
    }
    // --- Also clear the current track's latest played timestamp --- 
    if (_currentTrackLatestPlayedAt != null) {
       _currentTrackLatestPlayedAt = null;
       changed = true;
       logger.d('Cleared current track latest played timestamp.');
    }
    // --- End clearing timestamp ---
    if (changed) {
      notifyListeners(); // Notify UI to update
    }
  }

  // --- Data Modification Methods ---

  /// Inserts a track into the database, ignoring if it already exists.
  Future<void> addTrack(Track track) async {
    try {
      await _dbHelper.insertTrack(track); // insertTrack uses ConflictAlgorithm.ignore
    } catch (e) {
      logger.d('Error adding track in provider: $e');
      // Decide if error needs to be propagated
    }
  }

  /// Extracts a relevant lyrics snippet around the given timestamp
  Future<String?> _getLyricsSnippet(String trackId, String trackName, String artistName, int? timestampMs) async {
    try {
      // Get full lyrics from the lyrics service
      final fullLyrics = await _lyricsService.getLyrics(trackName, artistName, trackId);
      if (fullLyrics == null || fullLyrics.isEmpty) {
        return null;
      }

      // If no timestamp provided, return the first few lines
      if (timestampMs == null || timestampMs <= 0) {
        final lines = fullLyrics.split('\n').take(3).toList();
        return lines.join('\n').trim();
      }

      // Parse LRC format lyrics to find lyrics around the timestamp
      final lines = fullLyrics.split('\n');
      final lrcEntries = <int, String>{};
      
      for (final line in lines) {
        // Match LRC format: [mm:ss.xx] or [mm:ss] 
        final match = RegExp(r'^\[(\d{1,2}):(\d{2})(?:\.(\d{2}))?\](.*)').firstMatch(line);
        if (match != null) {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          final centiseconds = int.tryParse(match.group(3) ?? '0') ?? 0;
          final lyricsText = match.group(4)!.trim();
          
          final timeMs = (minutes * 60 + seconds) * 1000 + centiseconds * 10;
          if (lyricsText.isNotEmpty) {
            lrcEntries[timeMs] = lyricsText;
          }
        }
      }

      if (lrcEntries.isEmpty) {
        // If not LRC format, return first few lines
        final plainLines = fullLyrics.split('\n').take(3).toList();
        return plainLines.join('\n').trim();
      }

      // Find the lyrics line closest to the timestamp
      final sortedTimes = lrcEntries.keys.toList()..sort();
      int closestTime = sortedTimes.first;
      
      for (final time in sortedTimes) {
        if (time <= timestampMs) {
          closestTime = time;
        } else {
          break;
        }
      }

      // Get the current line and next 1-2 lines for context
      final currentIndex = sortedTimes.indexOf(closestTime);
      final snippetLines = <String>[];
      
      for (int i = currentIndex; i < sortedTimes.length && snippetLines.length < 3; i++) {
        final line = lrcEntries[sortedTimes[i]]!;
        if (line.isNotEmpty) {
          snippetLines.add(line);
        }
      }

      return snippetLines.join('\n').trim();
    } catch (e) {
      logger.d('Failed to get lyrics snippet: $e');
      return null;
    }
  }

  /// Adds a new record for a given track.
  /// Handles inserting the track if it doesn't exist or updating its lastRecordedAt timestamp.
  Future<void> addRecord({
    required Track track, // Current track info from SpotifyProvider
    required String? noteContent,
    required int? rating,
    required int? songTimestampMs,
    required String? contextUri,
    required String? contextName,
    // required String? lyricsSnapshot, // Removed: Lyrics snapshot functionality deferred
  }) async {
    _setLoading(true); // Indicate loading state
    final recordedAt = DateTime.now().millisecondsSinceEpoch;
    logger.d('Adding record for track: ${track.trackId} with rating: $rating');

    try {
      // 1. Check if track exists, insert or update lastRecordedAt
      final existingTrack = await _dbHelper.getTrack(track.trackId);
      if (existingTrack == null) {
        logger.d('Track ${track.trackId} not found, inserting new track...');
        // Create a new track object with the first recorded timestamp
        final newTrack = Track(
          trackId: track.trackId,
          trackName: track.trackName,
          artistName: track.artistName,
          albumName: track.albumName,
          albumCoverUrl: track.albumCoverUrl,
          lastRecordedAt: recordedAt, // Set initial lastRecordedAt
          latestPlayedAt: track.latestPlayedAt, // Carry over if available from provider
        );
        await _dbHelper.insertTrack(newTrack);
      } else {
        logger.d('Track ${track.trackId} found, updating lastRecordedAt...');
        await _dbHelper.updateTrackLastRecordedAt(track.trackId, recordedAt);
      }

      // 2. Get lyrics snippet for the current timestamp
      final lyricsSnippet = await _getLyricsSnippet(
        track.trackId, 
        track.trackName, 
        track.artistName, 
        songTimestampMs
      );

      // 3. Create the Record object
      final newRecord = Record(
        trackId: track.trackId,
        noteContent: noteContent,
        rating: rating, // Passed the int? rating directly
        songTimestampMs: songTimestampMs,
        recordedAt: recordedAt, // Use the timestamp generated at the start
        contextUri: contextUri,
        contextName: contextName,
        lyricsSnapshot: lyricsSnippet, // Save the lyrics snippet around the timestamp
      );

      // 4. Insert the new record
      final recordId = await _dbHelper.insertRecord(newRecord);
      logger.d('Inserted new record with ID: $recordId for track ${track.trackId}');

      // 5. Refresh ALL relevant data lists to update UI
      await Future.wait([
        fetchRecordsForTrack(track.trackId),
        fetchAllRecordsOrderedByTime(), // Refresh the ordered list
        // Optionally refresh random records if needed, though less critical
        // fetchRandomRecords(15),
      ]);

    } catch (e) {
      logger.d('Error adding record: $e');
      // Optionally, provide user feedback about the error
      _setLoading(false); // Ensure loading indicator is turned off on error
    }
    // No need for setLoading(false) here if fetchRecordsForTrack handles it in its finally block
  }

  /// Saves a translation, replacing if it already exists.
  Future<void> saveTranslation(Translation translation) async {
    // Remove the old print statement
    // print('saveTranslation called - To be implemented'); 
    try {
      await _dbHelper.insertTranslation(translation); // Uses replace conflict algorithm
      logger.d('Translation saved/updated via DB Helper for track ${translation.trackId}');
    } catch (e) {
       logger.d('Error saving translation via DB Helper: $e');
       // Re-throw the exception so the caller (LyricsWidget) knows about it
       throw Exception('Failed to save translation to database: $e'); 
    }
  }

  /// Updates an existing record.
  Future<void> updateRecord({
    required int recordId,
    required String trackId,
    required String newNoteContent,
    required int newRating,
  }) async {
    _setLoading(true); // Indicate loading
    logger.d('Updating record ID: $recordId with rating: $newRating');
    try {
      // 调用 DatabaseHelper 的 updateRecord 方法
      final success = await _dbHelper.updateRecord(
        recordId: recordId,
        newNoteContent: newNoteContent,
        newRating: newRating,
      );
      
      if (success) {
        logger.d('Record $recordId updated successfully in DB.');
        // Refresh ALL relevant data lists
        await Future.wait([
          fetchRecordsForTrack(trackId),
          fetchAllRecordsOrderedByTime(), // Refresh the ordered list
          // Optionally refresh random records
           fetchRandomRecords(15),
        ]);

      } else {
        logger.w('Failed to update record $recordId in DB.');
        // Handle failure - maybe show an error message to the user
      }
    } catch (e) {
      logger.e('Error updating record $recordId: $e');
      // Handle error - maybe show an error message to the user
    } finally {
      _setLoading(false); // Ensure loading is turned off
    }
  }

  /// Deletes a record by its ID.
  Future<void> deleteRecord({
    required int recordId,
    required String trackId, // Need trackId to potentially refresh lists if needed
  }) async {
    _setLoading(true); // Indicate loading
    logger.d('Attempting to delete record ID: $recordId from DB...');
    try {
       // Actually call the database helper to delete the record
       final rowsAffected = await _dbHelper.deleteRecord(recordId);

       // Check if the deletion was successful (1 row affected)
       final bool success = rowsAffected > 0;

       if (success) {
         logger.i('Record $recordId deleted successfully from DB (rows affected: $rowsAffected). Now updating provider state.');

         // Remove from local lists and notify
         bool changed = false;
         // Remove from current track list
         int initialLength = _currentTrackRecords.length;
         _currentTrackRecords.removeWhere((record) => record.id == recordId);
         if (_currentTrackRecords.length < initialLength) changed = true;

         // Remove from random list
         initialLength = _randomRecords.length;
         _randomRecords.removeWhere((record) => record['id'] == recordId);
         if (_randomRecords.length < initialLength) changed = true;

         // Remove from all ordered list
         initialLength = _allRecordsOrdered.length;
         _allRecordsOrdered.removeWhere((record) => record['id'] == recordId);
         if (_allRecordsOrdered.length < initialLength) changed = true;

         // Remove from related list
         initialLength = _relatedRecords.length;
         _relatedRecords.removeWhere((record) => record['id'] == recordId);
         if (_relatedRecords.length < initialLength) changed = true;

         // Notify listeners only if something was actually removed
         if (changed) {
           notifyListeners();
         }

         // Optionally, trigger a full refresh of lists after local removal,
         // though local removal is faster for UI responsiveness.
         // await fetchAllRecordsOrderedByTime();
         // await fetchRandomRecords(15);

       } else {
         logger.w('Failed to delete record $recordId from DB (rows affected: $rowsAffected).');
         // Handle failure - maybe show an error message
       }
    } catch (e, s) {
      logger.e('Error during deleteRecord operation for ID $recordId', error: e, stackTrace: s);
      // Handle error - maybe show an error message
    } finally {
      _setLoading(false); // Ensure loading is turned off
    }
  }

  Future<void> updateLatestPlayedTime(String trackId, int timestamp) async {
    logger.d('updateLatestPlayedTime called - To be implemented');
     try {
      await _dbHelper.updateTrackLatestPlayedAt(trackId, timestamp);
      // Might need to also handle inserting the track if it doesn't exist yet
      // This logic is complex and might live elsewhere or be combined with track insertion
    } catch (e) {
       logger.d('Error updating latest played time: $e');
    }
    // notifyListeners(); // Only notify if UI needs immediate update
  }

  /// Called by ChangeNotifierProxyProvider when SpotifyProvider updates.
  void spotifyProviderUpdated(SpotifyProvider newSpotifyProvider) {
    final currentSpotifyTrackId = newSpotifyProvider.currentTrack?['item']?['id'] as String?;

    // *** Only trigger API call if the track ID has actually changed ***
    if (currentSpotifyTrackId != _lastProcessedTrackIdForPlayedAt) {
      
      // Update the state variable immediately
      _lastProcessedTrackIdForPlayedAt = currentSpotifyTrackId; 

      // Only call the API if the new track ID is not null
      if (currentSpotifyTrackId != null) {
        logger.d('Track ID changed to $currentSpotifyTrackId, fetching latest played time from API...');
        _updateLatestPlayedAtFromApi();
      } else {
        logger.d('Track ID changed to null (playback stopped?).');
      }
    }
  }

  /// Fetches the single most recent play record from API and updates the corresponding track in DB.
  Future<void> _updateLatestPlayedAtFromApi() async {
    try {
       // Check if logged in
       if (!_spotifyProvider.username!.isNotEmpty) return;

       // Fetch only the single most recent played track
       final recentRawTracks = await _spotifyProvider.getRecentlyPlayedRawTracks(limit: 1);
       
       if (recentRawTracks.isNotEmpty) {
         final item = recentRawTracks.first;
         final recentTrack = item['track'];
         final recentTrackId = recentTrack?['id'] as String?;
         final playedAtStr = item['played_at'] as String?;

         // No longer check if recentTrackId matches the current track in SpotifyProvider
         // Update the track returned by the API directly
         if (recentTrackId != null && playedAtStr != null) {
            try {
               final playedAtTimestamp = DateTime.parse(playedAtStr).millisecondsSinceEpoch;
               logger.d('Updating latestPlayedAt for track $recentTrackId (from API) to $playedAtTimestamp');
               await _dbHelper.updateTrackLatestPlayedAt(recentTrackId, playedAtTimestamp);
            } catch (e) {
               logger.d('Error parsing date or updating latestPlayedAt for track $recentTrackId: $e');
            }
         } else {
            logger.d('Could not get valid trackId or played_at from the latest play record API.');
         }
       } else {
         logger.d('Could not fetch latest played record from API.');
       }
    } catch (e) {
       logger.d('Error in _updateLatestPlayedAtFromApi: $e');
    }
  }

  // --- Data Export/Import Methods ---

  /// Exports all data from the local database to a JSON file and shares it.
  /// Returns true if successful, false otherwise.
  Future<bool> exportDataToJson() async {
    _setLoading(true); // Use general loading state or add a specific one
    logger.d('Starting data export...');
    try {
      // 1. Fetch all data from the database
      final List<Track> tracks = await _dbHelper.getAllTracks();
      final List<Record> records = await _dbHelper.getAllRecords();
      final List<Translation> translations = await _dbHelper.getAllTranslations();
      final List<Map<String, dynamic>> playContexts = await _dbHelper.getAllPlayContexts();

      // 2. Convert data to a JSON-compatible structure (List of Maps)
      final Map<String, dynamic> exportData = {
        'tracks': tracks.map((t) => t.toMap()).toList(), // Use toMap defined in models
        'records': records.map((r) => r.toMap()).toList(),
        'translations': translations.map((tr) => tr.toMap()).toList(),
        'play_contexts': playContexts,
      };

      // 3. Encode data to JSON string
      // Use JsonEncoder with indent for readability
      const jsonEncoder = JsonEncoder.withIndent('  '); 
      final jsonString = jsonEncoder.convert(exportData);

      // 4. Get temporary directory and create file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-'); // Filesafe timestamp
      final filePath = '${tempDir.path}/spotoolfy_backup_$timestamp.json';

      // 5. Write JSON string to the file
      final file = File(filePath);
      await file.writeAsString(jsonString);
      logger.d('Data exported to temporary file: $filePath');

      // 6. Use share_plus to share the file
      final result = await Share.shareXFiles(
          [XFile(filePath, mimeType: 'application/json')], 
          subject: 'Spotoolfy Data Backup $timestamp',
      );

      if (result.status == ShareResultStatus.success) {
        logger.d('Export file shared successfully.');
        _setLoading(false);
        return true;
      } else {
        logger.d('Export file sharing failed or was dismissed: ${result.status}');
         _setLoading(false);
        return false; // Indicate sharing wasn't fully successful
      }

    } catch (e) {
      logger.d('Error during data export: $e');
      _setLoading(false);
      return false;
    }
  }

  /// Imports data from a user-selected JSON file.
  /// Returns true if successful, false otherwise.
  /// Current conflict strategy: Replace tracks/translations, Insert records.
  Future<bool> importDataFromJson() async {
    _setLoading(true);
    logger.d('Starting data import...');
    try {
      // 1. Pick JSON file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        logger.d('File selection cancelled.');
        _setLoading(false);
        return false; // User cancelled picker
      }

      final filePath = result.files.single.path!;
      logger.d('Selected file: $filePath');

      // 2. Read file content
      final file = File(filePath);
      final jsonString = await file.readAsString();

      // 3. Parse JSON
      final dynamic jsonData = jsonDecode(jsonString);

      if (jsonData is! Map<String, dynamic>) {
         throw Exception('Invalid JSON format: Root object is not a Map.');
      }

      // 4. Validate and Extract Data
      final tracksData = jsonData['tracks'] as List?;
      final recordsData = jsonData['records'] as List?;
      final translationsData = jsonData['translations'] as List?;
      final playContextsData = jsonData['play_contexts'] as List?;

      if (tracksData == null || recordsData == null || translationsData == null || playContextsData == null) {
        throw Exception('Invalid JSON format: Missing required keys (tracks, records, translations, play_contexts).');
      }

      // 5. Convert JSON maps to Model objects
      List<Track> tracksToImport = [];
      for (var trackMap in tracksData) {
         if (trackMap is Map<String, dynamic>) {
            // Add robust checking for required fields before creating Track
            if (trackMap['trackId'] != null && trackMap['trackName'] != null && 
                trackMap['artistName'] != null && trackMap['albumName'] != null) {
               tracksToImport.add(Track.fromMap(trackMap));
            } else {
               logger.d('Skipping invalid track data: $trackMap');
            }
         } 
      }

      List<Record> recordsToImport = [];
       for (var recordMap in recordsData) {
         if (recordMap is Map<String, dynamic>) {
            // ** Compatibility check for rating type **
            final dynamic rawRating = recordMap['rating'];
            if (rawRating is String) {
              // If rating is a string (old format), set it to the default int value (3)
              recordMap['rating'] = 3;
              logger.d('Old string rating found for record, converting to default 3.');
            } else if (rawRating != null && rawRating is! int) {
              // If rating is not null, not string, and not int, treat as invalid -> null (default 3)
              recordMap['rating'] = null;
              logger.d('Invalid rating type found (${rawRating.runtimeType}), setting to null (default 3).');
            }
            // If rawRating is int or null, it's already compatible

             // Add robust checking for required fields
            if (recordMap['trackId'] != null && recordMap['recordedAt'] != null) {
               // Now that rating is compatible (int? or null), create the Record object
               recordsToImport.add(Record.fromMap(recordMap));
            } else {
               logger.d('Skipping invalid record data: $recordMap');
            }
         }
      }

      List<Translation> translationsToImport = [];
      for (var transMap in translationsData) {
          if (transMap is Map<String, dynamic>) {
             // Add robust checking for required fields
            if (transMap['trackId'] != null && transMap['languageCode'] != null &&
                transMap['style'] != null && transMap['translatedLyrics'] != null &&
                transMap['generatedAt'] != null) {
               translationsToImport.add(Translation.fromMap(transMap));
            } else {
               logger.d('Skipping invalid translation data: $transMap');
            }
         }
      }
      
      // --- Add validation and conversion for play contexts ---
      List<Map<String, dynamic>> contextsToImport = [];
      for (var contextMap in playContextsData) {
        if (contextMap is Map<String, dynamic>) {
          // Validate required fields and types
          if (contextMap['contextUri'] is String &&
              contextMap['contextType'] is String &&
              contextMap['contextName'] is String &&
              contextMap['lastPlayedAt'] != null) { // Check for existence first
            
            // Ensure lastPlayedAt is an int
            int? lastPlayedAtInt;
            if (contextMap['lastPlayedAt'] is int) {
              lastPlayedAtInt = contextMap['lastPlayedAt'] as int;
            } else if (contextMap['lastPlayedAt'] is String) {
              lastPlayedAtInt = int.tryParse(contextMap['lastPlayedAt']);
            } else if (contextMap['lastPlayedAt'] is double) {
              lastPlayedAtInt = (contextMap['lastPlayedAt'] as double).toInt();
            }

            if (lastPlayedAtInt != null) {
              // Add the validated/converted map
              contextsToImport.add({
                'contextUri': contextMap['contextUri'],
                'contextType': contextMap['contextType'],
                'contextName': contextMap['contextName'],
                'imageUrl': contextMap['imageUrl'], // Allow null
                'lastPlayedAt': lastPlayedAtInt,
              });
            } else {
              logger.w('Skipping invalid play context data (lastPlayedAt not convertible to int): ${json.encode(contextMap)}');
            }
          } else {
            logger.w('Skipping invalid play context data (missing fields or wrong types): ${json.encode(contextMap)}');
          }
        } else {
          logger.w('Skipping non-map item in play_contexts data: $contextMap');
        }
      }
      // --- End validation and conversion ---
      
      logger.d('Parsed ${tracksToImport.length} tracks, ${recordsToImport.length} records, ${translationsToImport.length} translations, ${contextsToImport.length} play contexts.');

      // 6. Perform Batch Insert/Replace
      // IMPORTANT: Consider wrapping this in a transaction if possible with sqflite batches,
      // or handle potential partial failures.
      await _dbHelper.batchInsertOrReplaceTracks(tracksToImport);
      await _dbHelper.batchInsertRecords(recordsToImport); // Note: Using Insert, not Replace
      await _dbHelper.batchInsertOrReplaceTranslations(translationsToImport);
      await _dbHelper.batchInsertOrReplacePlayContexts(contextsToImport);

      logger.d('Data import completed successfully.');
       _setLoading(false);
      return true;

    } catch (e) {
      logger.d('Error during data import: $e');
      _setLoading(false);
      return false;
    }
  }

  // --- Methods for Play Contexts ---

  /// Inserts or updates a play context in the database.
  Future<void> insertOrUpdatePlayContext({
    required String contextUri,
    required String contextType,
    required String contextName,
    required String? imageUrl,
    required int lastPlayedAt,
  }) async {
    logger.d('[LocalDBProvider] insertOrUpdatePlayContext called for URI: $contextUri'); // Log: Method entry
    try {
      logger.d('[LocalDBProvider] Calling _dbHelper.insertOrUpdatePlayContext...'); // Log: Before helper call
      await _dbHelper.insertOrUpdatePlayContext(
        contextUri: contextUri,
        contextType: contextType,
        contextName: contextName,
        imageUrl: imageUrl,
        lastPlayedAt: lastPlayedAt,
      );
      logger.d('[LocalDBProvider] Successfully called _dbHelper.insertOrUpdatePlayContext for $contextUri'); // Log: After helper call success
      // Optional: Fetch immediately after update if UI needs real-time carousel update
      // await fetchRecentContexts(); 
      // --- Fetch recent contexts to update the UI --- 
      await fetchRecentContexts();
      // --- End fetching ---
    } catch (e, s) { // Log: Catch internal error
      logger.e('[LocalDBProvider] Error in insertOrUpdatePlayContext', error: e, stackTrace: s);
    }
  }

  /// Fetches the most recent play contexts from the database and updates the state.
  Future<void> fetchRecentContexts({int limit = 15}) async {
    // Optional: Set loading state if you added one
    // _isLoadingContexts = true;
    // notifyListeners(); 
    logger.d('[LocalDBProvider] fetchRecentContexts called (limit: $limit)...'); // Log: Method entry
    try {
      logger.d('[LocalDBProvider] Calling _dbHelper.getRecentPlayContexts...'); // Log: Before helper call
      final contextsFromDb = await _dbHelper.getRecentPlayContexts(limit);
      logger.d('[LocalDBProvider] Received ${contextsFromDb.length} contexts from DB: ${json.encode(contextsFromDb)}'); // Log: Data received from helper
      _recentContexts = contextsFromDb;
      notifyListeners(); // Notify listeners after fetching data
    } catch (e, s) { // Log: Catch internal error
      logger.e('[LocalDBProvider] Error in fetchRecentContexts', error: e, stackTrace: s);
      _recentContexts = []; // Clear on error
      notifyListeners(); // Notify listeners even on error
    } finally {
      // Optional: Set loading state back to false
      // _isLoadingContexts = false;
      // notifyListeners();
    }
  }

  // --- New method to fetch all records ordered by time ---
  Future<void> fetchAllRecordsOrderedByTime({bool descending = true}) async {
    // If called standalone, manage its own loading state if needed
    // _setLoading(true); // Potentially set loading here
    logger.d('Fetching all records ordered by time (descending: $descending)...');
    try {
      _allRecordsOrdered = await _dbHelper.getAllRecordsWithTrackInfoOrderedByTime(descending: descending);
      // Ensure the list is mutable
      final recordsFromDb = await _dbHelper.getAllRecordsWithTrackInfoOrderedByTime(descending: descending);
      _allRecordsOrdered = List<Map<String, dynamic>>.from(recordsFromDb);
    } catch (e) {
      logger.d('Error fetching all ordered records: $e');
      _allRecordsOrdered = []; // Clear on error
    } finally {
       // _setLoading(false); // Manage loading state appropriately
       notifyListeners(); // Notify after updating data
    }
  }
  // --- End new method ---

  // Helper to fetch both types of data initially and on refresh
  Future<void> fetchInitialData() async {
    _setLoading(true);
    try {
      // Use Future.wait to fetch concurrently
      await Future.wait([
        fetchRandomRecords(15), // Fetch random for carousel
        fetchAllRecordsOrderedByTime() // Fetch all ordered for list
      ]);
    } finally {
      _setLoading(false);
    }
  }
} 