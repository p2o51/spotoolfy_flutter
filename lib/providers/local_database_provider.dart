import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import '../models/record.dart';
import '../models/track.dart';
import '../models/translation.dart';
import '../providers/spotify_provider.dart';
import '../services/lyrics_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:flutter/material.dart';

final logger = Logger();

class LocalDatabaseProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SpotifyProvider _spotifyProvider;
  final LyricsService _lyricsService = LyricsService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  bool _isRecentContextsLoading = false;
  bool get isRecentContextsLoading => _isRecentContextsLoading;

  List<Record> _currentTrackRecords = [];
  List<Record> get currentTrackRecords => _currentTrackRecords;

  int? _currentTrackLatestPlayedAt;
  int? get currentTrackLatestPlayedAt => _currentTrackLatestPlayedAt;

  List<Map<String, dynamic>> _randomRecords = [];
  List<Map<String, dynamic>> get randomRecords => _randomRecords;

  List<Map<String, dynamic>> _allRecordsOrdered = [];
  List<Map<String, dynamic>> get allRecordsOrdered => _allRecordsOrdered;

  Translation? _fetchedTranslation;
  Translation? get fetchedTranslation => _fetchedTranslation;

  List<Map<String, dynamic>> _relatedRecords = [];
  List<Map<String, dynamic>> get relatedRecords => _relatedRecords;
  bool _isLoadingRelated = false;
  bool get isLoadingRelated => _isLoadingRelated;

  List<Map<String, dynamic>> _recentContexts = [];
  List<Map<String, dynamic>> get recentContexts => _recentContexts;

  String? _lastProcessedTrackIdForPlayedAt;

  LocalDatabaseProvider(this._spotifyProvider) {
    _initializeProvider();
  }

  Future<void> _initializeProvider() async {
    await _dbHelper.insertSampleDataIfNotExists();
    await fetchInitialData();
    Future.microtask(_maybeWarmUpRecentlyPlayed);
  }

  void _maybeWarmUpRecentlyPlayed() {
    final usernameValue = _spotifyProvider.username;
    if (usernameValue == null || usernameValue.isEmpty) return;
    unawaited(_updateInitialRecentlyPlayed());
  }

  Future<void> _updateInitialRecentlyPlayed() async {
    try {
      final username = _spotifyProvider.username;
      if (username == null || username.isEmpty) return;

      final recentRawTracks =
          await _spotifyProvider.getRecentlyPlayedRawTracks(limit: 50);
      if (recentRawTracks.isEmpty) return;

      final db = await _dbHelper.database;
      final batch = db.batch();
      int updatedCount = 0;

      for (final item in recentRawTracks) {
        final track = item['track'];
        final playedAtStr = item['played_at'];

        if (track != null && track['id'] != null && playedAtStr != null) {
          final trackId = track['id'] as String;
          try {
            final playedAtTimestamp =
                DateTime.parse(playedAtStr).millisecondsSinceEpoch;
            batch.update(
              'tracks',
              {'latestPlayedAt': playedAtTimestamp},
              where: 'trackId = ?',
              whereArgs: [trackId],
            );
            updatedCount++;
          } catch (_) {}
        }
      }

      if (updatedCount > 0) {
        await batch.commit(noResult: true);
      }
    } catch (_) {}
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setRecentContextsLoading(bool value) {
    if (_isRecentContextsLoading == value) {
      return;
    }
    _isRecentContextsLoading = value;
    notifyListeners();
  }

  void _setLoadingRelated(bool value) {
    _isLoadingRelated = value;
    notifyListeners();
  }

  Future<Map<String, int?>> getLatestRatingsForTracks(
      List<String> trackIds) async {
    try {
      return await _dbHelper.getLatestRatingsForTracks(trackIds);
    } catch (e, s) {
      logger.e('[LocalDBProvider] Failed to get latest ratings',
          error: e, stackTrace: s);
      return {};
    }
  }

  Future<Map<String, Map<String, dynamic>?>> getLatestRatingsWithTimestampForTracks(
      List<String> trackIds) async {
    try {
      return await _dbHelper.getLatestRatingsWithTimestampForTracks(trackIds);
    } catch (e, s) {
      logger.e('[LocalDBProvider] Failed to get latest ratings with timestamp',
          error: e, stackTrace: s);
      return {};
    }
  }

  Future<void> quickRateTrack({
    required String trackId,
    required String trackName,
    required String artistName,
    required String albumName,
    String? albumCoverUrl,
    required int rating,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    try {
      final existingTrack = await _dbHelper.getTrack(trackId);
      if (existingTrack == null) {
        final track = Track(
          trackId: trackId,
          trackName: trackName,
          artistName: artistName,
          albumName: albumName,
          albumCoverUrl: albumCoverUrl,
          lastRecordedAt: timestamp,
        );
        await _dbHelper.insertTrack(track);
      } else {
        await _dbHelper.updateTrackLastRecordedAt(trackId, timestamp);
      }

      final record = Record(
        trackId: trackId,
        noteContent: null,
        rating: rating,
        songTimestampMs: null,
        recordedAt: timestamp,
        contextUri: null,
        contextName: null,
        lyricsSnapshot: null,
      );

      await _dbHelper.insertRecord(record);
    } catch (e, s) {
      logger.e('[LocalDBProvider] quickRateTrack failed for $trackId',
          error: e, stackTrace: s);
      rethrow;
    }
  }

  Future<void> fetchRecordsForTrack(String trackId) async {
    _setLoading(true);
    try {
      final recordsFromDb = await _dbHelper.getRecordsForTrack(trackId);
      _currentTrackRecords = List<Record>.from(recordsFromDb);
      final trackInfo = await _dbHelper.getTrack(trackId);
      _currentTrackLatestPlayedAt = trackInfo?.latestPlayedAt;
    } catch (e) {
      logger.d('Error fetching records for $trackId: $e');
      _currentTrackRecords = [];
      _currentTrackLatestPlayedAt = null;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchRandomRecords(int count) async {
    _setLoading(true);
    try {
      final recordsFromDb = await Future.microtask(
          () => _dbHelper.getRandomRecordsWithTrackInfo(count));
      _randomRecords = List<Map<String, dynamic>>.from(recordsFromDb);
    } catch (e) {
      logger.d('Error fetching random records: $e');
      _randomRecords = [];
    } finally {
      _setLoading(false);
    }
  }

  Future<Translation?> fetchTranslation(
      String trackId, String languageCode, String style) async {
    _setLoading(true);
    try {
      _fetchedTranslation =
          await _dbHelper.getTranslation(trackId, languageCode, style);
      return _fetchedTranslation;
    } catch (e) {
      logger.d('Error fetching translation: $e');
      _fetchedTranslation = null;
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<Track?> getTrack(String trackId) async {
    return await _dbHelper.getTrack(trackId);
  }

  Future<void> fetchRelatedRecords(String currentTrackId, String trackName,
      {int limit = 5}) async {
    _setLoadingRelated(true);
    try {
      final recordsFromDb =
          await _dbHelper.fetchRelatedRecords(currentTrackId, trackName, limit);
      _relatedRecords = List<Map<String, dynamic>>.from(recordsFromDb);
    } catch (e) {
      logger.d('Error fetching related records: $e');
      _relatedRecords = [];
    } finally {
      _setLoadingRelated(false);
    }
  }

  void clearRelatedRecords() {
    bool changed = false;
    if (_relatedRecords.isNotEmpty) {
      _relatedRecords = [];
      changed = true;
    }
    if (_currentTrackLatestPlayedAt != null) {
      _currentTrackLatestPlayedAt = null;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> addTrack(Track track) async {
    try {
      await _dbHelper.insertTrack(track);
    } catch (e) {
      logger.d('Error adding track: $e');
    }
  }

  Future<String?> _getLyricsSnippet(String trackId, String trackName,
      String artistName, int? timestampMs) async {
    try {
      final fullLyrics =
          await _lyricsService.getLyrics(trackName, artistName, trackId);
      if (fullLyrics == null || fullLyrics.isEmpty) return null;

      if (timestampMs == null || timestampMs <= 0) {
        return fullLyrics.split('\n').take(3).join('\n').trim();
      }

      final lines = fullLyrics.split('\n');
      final lrcEntries = <int, String>{};

      for (final line in lines) {
        final match = RegExp(r'^\[(\d{1,2}):(\d{2})(?:\.(\d{2}))?\](.*)')
            .firstMatch(line);
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
        return fullLyrics.split('\n').take(3).join('\n').trim();
      }

      final sortedTimes = lrcEntries.keys.toList()..sort();
      int closestTime = sortedTimes.first;

      for (final time in sortedTimes) {
        if (time <= timestampMs) {
          closestTime = time;
        } else {
          break;
        }
      }

      final currentIndex = sortedTimes.indexOf(closestTime);
      final snippetLines = <String>[];

      for (int i = currentIndex;
          i < sortedTimes.length && snippetLines.length < 3;
          i++) {
        final line = lrcEntries[sortedTimes[i]]!;
        if (line.isNotEmpty) {
          snippetLines.add(line);
        }
      }

      return snippetLines.join('\n').trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> addRecord({
    required Track track,
    required String? noteContent,
    required int? rating,
    required int? songTimestampMs,
    required String? contextUri,
    required String? contextName,
    String? lyricsSnapshot, // Optional: if provided, use directly instead of auto-fetching
  }) async {
    _setLoading(true);
    final recordedAt = DateTime.now().millisecondsSinceEpoch;

    try {
      final existingTrack = await _dbHelper.getTrack(track.trackId);
      if (existingTrack == null) {
        final newTrack = Track(
          trackId: track.trackId,
          trackName: track.trackName,
          artistName: track.artistName,
          albumName: track.albumName,
          albumCoverUrl: track.albumCoverUrl,
          lastRecordedAt: recordedAt,
          latestPlayedAt: track.latestPlayedAt,
        );
        await _dbHelper.insertTrack(newTrack);
      } else {
        await _dbHelper.updateTrackLastRecordedAt(track.trackId, recordedAt);
      }

      // Use provided lyricsSnapshot or auto-fetch from lyrics service
      final lyricsSnippet = lyricsSnapshot ?? await _getLyricsSnippet(
          track.trackId, track.trackName, track.artistName, songTimestampMs);

      final newRecord = Record(
        trackId: track.trackId,
        noteContent: noteContent,
        rating: rating,
        songTimestampMs: songTimestampMs,
        recordedAt: recordedAt,
        contextUri: contextUri,
        contextName: contextName,
        lyricsSnapshot: lyricsSnippet,
      );

      await _dbHelper.insertRecord(newRecord);

      await Future.wait([
        fetchRecordsForTrack(track.trackId),
        fetchAllRecordsOrderedByTime(),
      ]);
    } catch (e) {
      logger.d('Error adding record: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> saveTranslation(Translation translation) async {
    try {
      await _dbHelper.insertTranslation(translation);
    } catch (e) {
      logger.d('Error saving translation: $e');
      throw Exception('Failed to save translation: $e');
    }
  }

  Future<void> updateRecord({
    required int recordId,
    required String trackId,
    required String newNoteContent,
    required int newRating,
  }) async {
    _setLoading(true);
    try {
      final success = await _dbHelper.updateRecord(
        recordId: recordId,
        newNoteContent: newNoteContent,
        newRating: newRating,
      );

      if (success) {
        await Future.wait([
          fetchRecordsForTrack(trackId),
          fetchAllRecordsOrderedByTime(),
          fetchRandomRecords(15),
        ]);
      } else {
        logger.w('Failed to update record $recordId');
      }
    } catch (e) {
      logger.e('Error updating record $recordId: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteRecord({
    required int recordId,
    required String trackId,
  }) async {
    _setLoading(true);
    try {
      final rowsAffected = await _dbHelper.deleteRecord(recordId);
      final success = rowsAffected > 0;

      if (success) {
        bool changed = false;
        int initialLength = _currentTrackRecords.length;
        _currentTrackRecords.removeWhere((record) => record.id == recordId);
        if (_currentTrackRecords.length < initialLength) changed = true;

        initialLength = _randomRecords.length;
        _randomRecords.removeWhere((record) => record['id'] == recordId);
        if (_randomRecords.length < initialLength) changed = true;

        initialLength = _allRecordsOrdered.length;
        _allRecordsOrdered.removeWhere((record) => record['id'] == recordId);
        if (_allRecordsOrdered.length < initialLength) changed = true;

        initialLength = _relatedRecords.length;
        _relatedRecords.removeWhere((record) => record['id'] == recordId);
        if (_relatedRecords.length < initialLength) changed = true;

        if (changed) notifyListeners();
      } else {
        logger.w('Failed to delete record $recordId');
      }
    } catch (e, s) {
      logger.e('Error deleting record $recordId', error: e, stackTrace: s);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateLatestPlayedTime(String trackId, int timestamp) async {
    try {
      await _dbHelper.updateTrackLatestPlayedAt(trackId, timestamp);
    } catch (e) {
      logger.d('Error updating latest played time: $e');
    }
  }

  void spotifyProviderUpdated(SpotifyProvider newSpotifyProvider) {
    final currentSpotifyTrackId =
        newSpotifyProvider.currentTrack?['item']?['id'] as String?;

    if (currentSpotifyTrackId != _lastProcessedTrackIdForPlayedAt) {
      _lastProcessedTrackIdForPlayedAt = currentSpotifyTrackId;
      if (currentSpotifyTrackId != null) {
        _updateLatestPlayedAtFromApi();
      }
    }
  }

  Future<void> _updateLatestPlayedAtFromApi() async {
    try {
      if (_spotifyProvider.username?.isEmpty ?? true) return;

      final recentRawTracks =
          await _spotifyProvider.getRecentlyPlayedRawTracks(limit: 1);

      if (recentRawTracks.isNotEmpty) {
        final item = recentRawTracks.first;
        final recentTrack = item['track'];
        final recentTrackId = recentTrack?['id'] as String?;
        final playedAtStr = item['played_at'] as String?;

        if (recentTrackId != null && playedAtStr != null) {
          try {
            final playedAtTimestamp =
                DateTime.parse(playedAtStr).millisecondsSinceEpoch;
            await _dbHelper.updateTrackLatestPlayedAt(
                recentTrackId, playedAtTimestamp);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<bool> exportDataToJson() async {
    _setLoading(true);
    try {
      final tracks = await _dbHelper.getAllTracks();
      final records = await _dbHelper.getAllRecords();
      final translations = await _dbHelper.getAllTranslations();
      final playContexts = await _dbHelper.getAllPlayContexts();

      final exportData = {
        'tracks': tracks.map((t) => t.toMap()).toList(),
        'records': records.map((r) => r.toMap()).toList(),
        'translations': translations.map((tr) => tr.toMap()).toList(),
        'play_contexts': playContexts,
      };

      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(exportData);

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filePath = '${tempDir.path}/spotoolfy_backup_$timestamp.json';

      final file = File(filePath);
      await file.writeAsString(jsonString);

      final result = await Share.shareXFiles(
        [XFile(filePath, mimeType: 'application/json')],
        subject: 'Spotoolfy Data Backup $timestamp',
      );

      _setLoading(false);
      return result.status == ShareResultStatus.success;
    } catch (e) {
      logger.d('Error during data export: $e');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> importDataFromJson() async {
    _setLoading(true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        _setLoading(false);
        return false;
      }

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final jsonString = await file.readAsString();
      final dynamic jsonData = jsonDecode(jsonString);

      if (jsonData is! Map<String, dynamic>) {
        throw Exception('Invalid JSON format: Root object is not a Map.');
      }

      final tracksData = jsonData['tracks'] as List?;
      final recordsData = jsonData['records'] as List?;
      final translationsData = jsonData['translations'] as List?;
      final playContextsData = jsonData['play_contexts'] as List?;

      if (tracksData == null ||
          recordsData == null ||
          translationsData == null ||
          playContextsData == null) {
        throw Exception('Invalid JSON format: Missing required keys.');
      }

      List<Track> tracksToImport = [];
      for (var trackMap in tracksData) {
        if (trackMap is Map<String, dynamic> &&
            trackMap['trackId'] != null &&
            trackMap['trackName'] != null &&
            trackMap['artistName'] != null &&
            trackMap['albumName'] != null) {
          tracksToImport.add(Track.fromMap(trackMap));
        }
      }

      List<Record> recordsToImport = [];
      for (var recordMap in recordsData) {
        if (recordMap is Map<String, dynamic>) {
          final rawRating = recordMap['rating'];
          if (rawRating is String) {
            recordMap['rating'] = 3;
          } else if (rawRating != null && rawRating is! int) {
            recordMap['rating'] = null;
          }

          if (recordMap['trackId'] != null && recordMap['recordedAt'] != null) {
            recordsToImport.add(Record.fromMap(recordMap));
          }
        }
      }

      List<Translation> translationsToImport = [];
      for (var transMap in translationsData) {
        if (transMap is Map<String, dynamic> &&
            transMap['trackId'] != null &&
            transMap['languageCode'] != null &&
            transMap['style'] != null &&
            transMap['translatedLyrics'] != null &&
            transMap['generatedAt'] != null) {
          translationsToImport.add(Translation.fromMap(transMap));
        }
      }

      List<Map<String, dynamic>> contextsToImport = [];
      for (var contextMap in playContextsData) {
        if (contextMap is Map<String, dynamic> &&
            contextMap['contextUri'] is String &&
            contextMap['contextType'] is String &&
            contextMap['contextName'] is String &&
            contextMap['lastPlayedAt'] != null) {
          int? lastPlayedAtInt;
          if (contextMap['lastPlayedAt'] is int) {
            lastPlayedAtInt = contextMap['lastPlayedAt'] as int;
          } else if (contextMap['lastPlayedAt'] is String) {
            lastPlayedAtInt = int.tryParse(contextMap['lastPlayedAt']);
          } else if (contextMap['lastPlayedAt'] is double) {
            lastPlayedAtInt = (contextMap['lastPlayedAt'] as double).toInt();
          }

          if (lastPlayedAtInt != null) {
            contextsToImport.add({
              'contextUri': contextMap['contextUri'],
              'contextType': contextMap['contextType'],
              'contextName': contextMap['contextName'],
              'imageUrl': contextMap['imageUrl'],
              'lastPlayedAt': lastPlayedAtInt,
            });
          }
        }
      }

      await _dbHelper.batchInsertOrReplaceTracks(tracksToImport);
      await _dbHelper.batchInsertRecords(recordsToImport);
      await _dbHelper.batchInsertOrReplaceTranslations(translationsToImport);
      await _dbHelper.batchInsertOrReplacePlayContexts(contextsToImport);

      _setLoading(false);
      return true;
    } catch (e) {
      logger.d('Error during data import: $e');
      _setLoading(false);
      return false;
    }
  }

  Future<void> insertOrUpdatePlayContext({
    required String contextUri,
    required String contextType,
    required String contextName,
    required String? imageUrl,
    required int lastPlayedAt,
  }) async {
    try {
      await _dbHelper.insertOrUpdatePlayContext(
        contextUri: contextUri,
        contextType: contextType,
        contextName: contextName,
        imageUrl: imageUrl,
        lastPlayedAt: lastPlayedAt,
      );
      await fetchRecentContexts();
    } catch (e, s) {
      logger.e('Error in insertOrUpdatePlayContext', error: e, stackTrace: s);
    }
  }

  Future<void> fetchRecentContexts({int limit = 15}) async {
    _setRecentContextsLoading(true);
    try {
      final contextsFromDb = await _dbHelper.getRecentPlayContexts(limit);
      _recentContexts = contextsFromDb;
      notifyListeners();
    } catch (e, s) {
      logger.e('Error fetching recent contexts', error: e, stackTrace: s);
      _recentContexts = [];
      notifyListeners();
    } finally {
      _setRecentContextsLoading(false);
    }
  }

  Future<void> fetchAllRecordsOrderedByTime({bool descending = true}) async {
    try {
      final recordsFromDb = await Future.microtask(() => _dbHelper
          .getAllRecordsWithTrackInfoOrderedByTime(descending: descending));
      _allRecordsOrdered = List<Map<String, dynamic>>.from(recordsFromDb);
    } catch (e) {
      logger.d('Error fetching all ordered records: $e');
      _allRecordsOrdered = [];
    } finally {
      notifyListeners();
    }
  }

  Future<void> fetchInitialData() async {
    _setLoading(true);
    try {
      await fetchRandomRecords(15);
      Future.delayed(const Duration(milliseconds: 100), fetchAllRecordsOrderedByTime);
    } finally {
      _setLoading(false);
    }
  }
}
