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
import 'package:file_picker/file_picker.dart'; // For picking file
import 'package:logger/logger.dart'; // Added logger

final logger = Logger(); // Added logger instance

class LocalDatabaseProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SpotifyProvider _spotifyProvider; // Add SpotifyProvider instance variable

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Record> _currentTrackRecords = [];
  List<Record> get currentTrackRecords => _currentTrackRecords;

  // Example internal state for random records
  List<Map<String, dynamic>> _randomRecords = [];
  List<Map<String, dynamic>> get randomRecords => _randomRecords;

  // Example internal state for fetched translation
  Translation? _fetchedTranslation;
  Translation? get fetchedTranslation => _fetchedTranslation;

  // State for related records
  List<Map<String, dynamic>> _relatedRecords = [];
  List<Map<String, dynamic>> get relatedRecords => _relatedRecords;
  bool _isLoadingRelated = false; // Separate loading state
  bool get isLoadingRelated => _isLoadingRelated;

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
          final results = await batch.commit(noResult: true); // Don't need individual results
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
      _currentTrackRecords = await _dbHelper.getRecordsForTrack(trackId);
      // Consider error handling if needed
    } catch (e) {
      logger.d('Error fetching records for track $trackId: $e');
      _currentTrackRecords = []; // Clear on error
    } finally {
       _setLoading(false);
       // notifyListeners() is called within _setLoading
    }
  }

  Future<void> fetchRandomRecords(int count) async {
     _setLoading(true);
     logger.d('Fetching $count random records with track info...');
     try {
       _randomRecords = await _dbHelper.getRandomRecordsWithTrackInfo(count);
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
      _relatedRecords = await _dbHelper.fetchRelatedRecords(currentTrackId, trackName, limit);
    } catch (e) {
      logger.d('Error fetching related records: $e');
      _relatedRecords = []; // Clear on error
    } finally {
      _setLoadingRelated(false);
    }
  }

  /// Clears the locally stored related records list.
  void clearRelatedRecords() {
    if (_relatedRecords.isNotEmpty) {
       _relatedRecords = [];
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

  /// Adds a new record for a given track.
  /// Handles inserting the track if it doesn't exist or updating its lastRecordedAt timestamp.
  Future<void> addRecord({
    required Track track, // Current track info from SpotifyProvider
    required String? noteContent,
    required String? rating,
    required int? songTimestampMs,
    required String? contextUri,
    required String? contextName,
    required String? lyricsSnapshot, // Lyrics snapshot from AddNoteSheet
  }) async {
    _setLoading(true); // Indicate loading state
    final recordedAt = DateTime.now().millisecondsSinceEpoch;
    logger.d('Adding record for track: ${track.trackId}');

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

      // 2. Create the Record object
      final newRecord = Record(
        trackId: track.trackId,
        noteContent: noteContent,
        rating: rating,
        songTimestampMs: songTimestampMs,
        recordedAt: recordedAt, // Use the timestamp generated at the start
        contextUri: contextUri,
        contextName: contextName,
        lyricsSnapshot: lyricsSnapshot,
      );

      // 3. Insert the new record
      final recordId = await _dbHelper.insertRecord(newRecord);
      logger.d('Inserted new record with ID: $recordId for track ${track.trackId}');

      // 4. Refresh the records list for the current track to update UI
      await fetchRecordsForTrack(track.trackId);
      // Loading state is handled within fetchRecordsForTrack

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

      // 2. Convert data to a JSON-compatible structure (List of Maps)
      final Map<String, dynamic> exportData = {
        'tracks': tracks.map((t) => t.toMap()).toList(), // Use toMap defined in models
        'records': records.map((r) => r.toMap()).toList(),
        'translations': translations.map((tr) => tr.toMap()).toList(),
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

      if (tracksData == null || recordsData == null || translationsData == null) {
        throw Exception('Invalid JSON format: Missing required keys (tracks, records, translations).');
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
             // Add robust checking for required fields
            if (recordMap['trackId'] != null && recordMap['recordedAt'] != null) {
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
      
      logger.d('Parsed ${tracksToImport.length} tracks, ${recordsToImport.length} records, ${translationsToImport.length} translations.');

      // 6. Perform Batch Insert/Replace
      // IMPORTANT: Consider wrapping this in a transaction if possible with sqflite batches,
      // or handle potential partial failures.
      await _dbHelper.batchInsertOrReplaceTracks(tracksToImport);
      await _dbHelper.batchInsertRecords(recordsToImport); // Note: Using Insert, not Replace
      await _dbHelper.batchInsertOrReplaceTranslations(translationsToImport);

      logger.d('Data import completed successfully.');
       _setLoading(false);
      return true;

    } catch (e) {
      logger.d('Error during data import: $e');
      _setLoading(false);
      return false;
    }
  }
} 