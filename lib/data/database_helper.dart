import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'package:logger/logger.dart';

import '../models/record.dart';
import '../models/track.dart';
import '../models/translation.dart';

// Define logger instance for this file
final logger = Logger();

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  static const String _dbName = 'spotoolfy_database.db';
  static const int _dbVersion = 1;

  DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _dbName);
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      // onUpgrade: _onUpgrade, // Optional: Implement for future schema changes
      // Enable foreign key support explicitly
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // Creates the database tables
  Future<void> _onCreate(Database db, int version) async {
    // Create tracks table
    await db.execute('''
      CREATE TABLE tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trackId TEXT NOT NULL UNIQUE,
        trackName TEXT NOT NULL,
        artistName TEXT NOT NULL,
        albumName TEXT NOT NULL,
        albumCoverUrl TEXT,
        lastRecordedAt INTEGER,
        latestPlayedAt INTEGER
      );
    ''');
    // Add index on trackId for faster lookups
    await db.execute('CREATE INDEX idx_track_trackId ON tracks (trackId);');

    // Create records table
    await db.execute('''
      CREATE TABLE records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trackId TEXT NOT NULL,
        noteContent TEXT,
        rating INTEGER DEFAULT 3,
        songTimestampMs INTEGER,
        recordedAt INTEGER NOT NULL,
        contextUri TEXT,
        contextName TEXT,
        lyricsSnapshot TEXT,
        FOREIGN KEY (trackId) REFERENCES tracks (trackId)
          ON DELETE CASCADE ON UPDATE CASCADE
      );
    ''');
    // Add indexes
    await db.execute('CREATE INDEX idx_record_trackId ON records (trackId);');
    await db
        .execute('CREATE INDEX idx_record_recordedAt ON records (recordedAt);');

    // Create translations table
    await db.execute('''
      CREATE TABLE translations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trackId TEXT NOT NULL,
        languageCode TEXT NOT NULL,
        style TEXT NOT NULL,
        translatedLyrics TEXT NOT NULL,
        generatedAt INTEGER NOT NULL,
        UNIQUE (trackId, languageCode, style),
        FOREIGN KEY (trackId) REFERENCES tracks (trackId)
          ON DELETE CASCADE ON UPDATE CASCADE
      );
    ''');
    // Index for foreign key is often useful
    await db.execute(
        'CREATE INDEX idx_translation_trackId ON translations (trackId);');
    // Index for the unique constraint might also improve lookups if needed
    await db.execute(
        'CREATE INDEX idx_translation_unique ON translations (trackId, languageCode, style);');

    // Create play_contexts table
    await db.execute('''
      CREATE TABLE play_contexts (
        contextUri TEXT PRIMARY KEY,
        contextType TEXT NOT NULL, 
        contextName TEXT NOT NULL,
        imageUrl TEXT,
        lastPlayedAt INTEGER NOT NULL
      );
    ''');
    // Add index for sorting by lastPlayedAt
    await db.execute(
        'CREATE INDEX idx_play_contexts_lastPlayedAt ON play_contexts (lastPlayedAt);');
  }

  // --- CRUD Methods ---

  /// Inserts a new track into the database.
  /// Returns the id of the inserted row.
  Future<int> insertTrack(Track track) async {
    final db = await instance.database;
    // Use ConflictAlgorithm.ignore to prevent duplicates based on the UNIQUE trackId constraint
    // Alternatively, use ConflictAlgorithm.replace if you want to overwrite existing tracks.
    return await db.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Retrieves a track from the database by its Spotify trackId.
  /// Returns the Track object if found, otherwise null.
  Future<Track?> getTrack(String trackId) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tracks',
      where: 'trackId = ?',
      whereArgs: [trackId],
      limit: 1, // Should be unique, but limit 1 for safety
    );

    if (maps.isNotEmpty) {
      return Track.fromMap(maps.first);
    } else {
      return null;
    }
  }

  /// Inserts a new record into the database.
  /// Returns the id of the inserted row.
  Future<int> insertRecord(Record record) async {
    final db = await instance.database;
    return await db.insert(
      'records',
      record.toMap(),
      // Records don't have a unique constraint other than the primary key
    );
  }

  /// Retrieves all records associated with a specific trackId, ordered by recordedAt descending.
  Future<List<Record>> getRecordsForTrack(String trackId) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'records',
      where: 'trackId = ?',
      whereArgs: [trackId],
      orderBy: 'recordedAt DESC', // Order by most recent first
    );

    // Convert the List<Map<String, dynamic>> into a List<Record>.
    return List.generate(maps.length, (i) {
      return Record.fromMap(maps[i]);
    });
  }

  /// Inserts a new translation into the database.
  /// If a translation with the same trackId, languageCode, and style already exists,
  /// it will be replaced.
  /// Returns the id of the inserted or replaced row.
  Future<int> insertTranslation(Translation translation) async {
    final db = await instance.database;
    return await db.insert(
      'translations',
      translation.toMap(),
      conflictAlgorithm:
          ConflictAlgorithm.replace, // Replace existing entry on conflict
    );
  }

  /// Retrieves a specific translation from the database.
  /// Returns the Translation object if found, otherwise null.
  Future<Translation?> getTranslation(
      String trackId, String languageCode, String style) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'translations',
      where: 'trackId = ? AND languageCode = ? AND style = ?',
      whereArgs: [trackId, languageCode, style],
      limit: 1, // Should be unique due to constraint
    );

    if (maps.isNotEmpty) {
      return Translation.fromMap(maps.first);
    } else {
      return null;
    }
  }

  /// Updates the lastRecordedAt timestamp for a specific track.
  Future<void> updateTrackLastRecordedAt(String trackId, int timestamp) async {
    final db = await instance.database;
    final rowsAffected = await db.update(
      'tracks',
      {'lastRecordedAt': timestamp},
      where: 'trackId = ?',
      whereArgs: [trackId],
    );
    if (rowsAffected == 0) {
      debugPrint(
          'Warning: updateTrackLastRecordedAt did not affect any rows for trackId: $trackId');
      // This might happen if the trackId doesn't exist, though addRecord logic should prevent this call then.
    }
  }

  /// Returns the most recent rating for each track in [trackIds].
  Future<Map<String, int?>> getLatestRatingsForTracks(
      List<String> trackIds) async {
    if (trackIds.isEmpty) {
      return {};
    }

    final db = await instance.database;
    final placeholders = List.filled(trackIds.length, '?').join(',');

    final rows = await db.rawQuery('''
      SELECT r.trackId, r.rating
      FROM records r
      INNER JOIN (
        SELECT trackId, MAX(recordedAt) AS maxRecordedAt
        FROM records
        WHERE trackId IN ($placeholders)
        GROUP BY trackId
      ) latest ON latest.trackId = r.trackId AND latest.maxRecordedAt = r.recordedAt
    ''', trackIds);

    final result = <String, int?>{};
    for (final row in rows) {
      final trackId = row['trackId'] as String?;
      if (trackId == null) {
        continue;
      }
      result[trackId] = row['rating'] as int?;
    }
    return result;
  }

  /// Returns the most recent rating and timestamp for each track in [trackIds].
  Future<Map<String, Map<String, dynamic>?>> getLatestRatingsWithTimestampForTracks(
      List<String> trackIds) async {
    if (trackIds.isEmpty) {
      return {};
    }

    final db = await instance.database;
    final placeholders = List.filled(trackIds.length, '?').join(',');

    final rows = await db.rawQuery('''
      SELECT r.trackId, r.rating, r.recordedAt
      FROM records r
      INNER JOIN (
        SELECT trackId, MAX(recordedAt) AS maxRecordedAt
        FROM records
        WHERE trackId IN ($placeholders)
        GROUP BY trackId
      ) latest ON latest.trackId = r.trackId AND latest.maxRecordedAt = r.recordedAt
    ''', trackIds);

    final result = <String, Map<String, dynamic>?>{};
    for (final row in rows) {
      final trackId = row['trackId'] as String?;
      if (trackId == null) {
        continue;
      }
      result[trackId] = {
        'rating': row['rating'] as int?,
        'recordedAt': row['recordedAt'] as int?,
      };
    }
    return result;
  }

  /// Updates the latestPlayedAt timestamp for a specific track.
  Future<void> updateTrackLatestPlayedAt(String trackId, int timestamp) async {
    final db = await instance.database;
    await db.update(
      'tracks',
      {'latestPlayedAt': timestamp},
      where: 'trackId = ?',
      whereArgs: [trackId],
    );
  }

  /// Deletes a record from the database by its primary key ID.
  /// Returns the number of rows affected (should be 1 if successful).
  Future<int> deleteRecord(int recordId) async {
    final db = await instance.database;
    final rowsAffected = await db.delete(
      'records',
      where: 'id = ?',
      whereArgs: [recordId],
    );
    if (rowsAffected == 1) {
      logger.d('[DBHelper] Deleted record with id: $recordId');
    } else {
      logger.w(
          '[DBHelper] Attempted to delete record id: $recordId, but $rowsAffected rows were affected.');
    }
    return rowsAffected;
  }

  /// Updates a record in the database with new content and rating.
  /// Returns true if update was successful (1 row affected), false otherwise.
  Future<bool> updateRecord({
    required int recordId,
    required String newNoteContent,
    required int newRating,
  }) async {
    final db = await instance.database;

    // Update only specified fields
    final updateData = {
      'noteContent': newNoteContent,
      'rating': newRating,
    };

    logger
        .d('[DBHelper] Updating record ID: $recordId with rating: $newRating');

    try {
      final rowsAffected = await db.update(
        'records',
        updateData,
        where: 'id = ?',
        whereArgs: [recordId],
      );

      if (rowsAffected == 1) {
        logger.d('[DBHelper] Record ID: $recordId updated successfully');
        return true;
      } else {
        logger.w(
            '[DBHelper] Attempted to update record ID: $recordId, but $rowsAffected rows were affected.');
        return false;
      }
    } catch (e, s) {
      logger.e('[DBHelper] Error updating record ID: $recordId',
          error: e, stackTrace: s);
      return false;
    }
  }

  // --- Query Methods for Specific Use Cases ---

  /// Fetches a specified number of random records along with their associated track info.
  /// Returns a list of maps, where each map contains columns from both records and tracks tables.
  Future<List<Map<String, dynamic>>> getRandomRecordsWithTrackInfo(
      int limit) async {
    if (limit <= 0) return [];

    final db = await instance.database;
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as count FROM records');
    final totalRecords = Sqflite.firstIntValue(countResult) ?? 0;
    if (totalRecords == 0) {
      return [];
    }

    final effectiveLimit = min(limit, totalRecords);
    final maxOffset = totalRecords - effectiveLimit;
    final randomOffset = maxOffset > 0 ? Random().nextInt(maxOffset + 1) : 0;

    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT
        r.id as recordId, r.trackId, r.noteContent, r.rating, r.songTimestampMs, r.recordedAt,
        r.contextUri, r.contextName, r.lyricsSnapshot,
        t.trackName, t.artistName, t.albumName, t.albumCoverUrl
      FROM records r
      JOIN tracks t ON r.trackId = t.trackId
      ORDER BY r.recordedAt DESC
      LIMIT ? OFFSET ?
    ''', [effectiveLimit, randomOffset]);

    return result;
  }

  /// Fetches records associated with tracks that have the same name as the current track,
  /// excluding the current track itself. Includes track info for the fetched records.
  Future<List<Map<String, dynamic>>> fetchRelatedRecords(
      String currentTrackId, String trackName, int limit) async {
    final db = await instance.database;

    // Find trackIds with the same name but different ID
    // Then fetch records for those trackIds, joining with tracks for info
    // Order by recordedAt descending within the related tracks
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT
        r.id as recordId, r.trackId, r.noteContent, r.rating, r.songTimestampMs, r.recordedAt,
        r.contextUri, r.contextName, r.lyricsSnapshot,
        t.trackName, t.artistName, t.albumName, t.albumCoverUrl
      FROM records r
      JOIN tracks t ON r.trackId = t.trackId
      WHERE r.trackId IN (
        SELECT trackId 
        FROM tracks 
        WHERE trackName = ? AND trackId != ?
      )
      ORDER BY r.recordedAt DESC
      LIMIT ?
    ''', [trackName, currentTrackId, limit]);

    return result;
  }

  /// Fetches all records along with their associated track info, ordered by recordedAt timestamp.
  /// Returns a list of maps, where each map contains columns from both records and tracks tables.
  Future<List<Map<String, dynamic>>> getAllRecordsWithTrackInfoOrderedByTime(
      {bool descending = true}) async {
    final db = await instance.database;
    final orderBy = descending ? 'DESC' : 'ASC';

    // Use a JOIN query to combine records and tracks
    // Order by recordedAt
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT
        r.id, r.trackId, r.noteContent, r.rating, r.songTimestampMs, r.recordedAt,
        r.contextUri, r.contextName, r.lyricsSnapshot,
        t.trackName, t.artistName, t.albumName, t.albumCoverUrl
      FROM records r
      JOIN tracks t ON r.trackId = t.trackId
      ORDER BY r.recordedAt $orderBy
    ''');

    // Renaming r.id to 'id' for consistency with how Record.fromMap might expect it,
    // although the provider will use the map directly. This ensures the key is just 'id'.
    // If Record.fromMap expects 'recordId', adjust the alias in the SQL above.
    return result;
  }

  // --- Methods for Data Export/Import ---

  /// Fetches all tracks from the database.
  Future<List<Track>> getAllTracks() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('tracks');
    return List.generate(maps.length, (i) => Track.fromMap(maps[i]));
  }

  /// Fetches all records from the database.
  Future<List<Record>> getAllRecords() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('records');
    return List.generate(maps.length, (i) => Record.fromMap(maps[i]));
  }

  /// Fetches all translations from the database.
  Future<List<Translation>> getAllTranslations() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('translations');
    return List.generate(maps.length, (i) => Translation.fromMap(maps[i]));
  }

  /// Inserts or replaces multiple tracks in a batch.
  Future<void> batchInsertOrReplaceTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final track in tracks) {
      // Use the existing toMap() which excludes the auto-generated id
      batch.insert(
        'tracks',
        track.toMap(),
        conflictAlgorithm: ConflictAlgorithm
            .replace, // Replace based on trackId UNIQUE constraint
      );
    }
    await batch.commit(noResult: true);
  }

  /// Inserts multiple records in a batch.
  Future<void> batchInsertRecords(List<Record> records) async {
    if (records.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final record in records) {
      // Use the existing toMap() which excludes the auto-generated id
      // Simple insert is appropriate as records don't have other unique constraints
      batch.insert(
        'records',
        record.toMap(),
      );
    }
    await batch.commit(noResult: true);
  }

  /// Inserts or replaces multiple translations in a batch.
  Future<void> batchInsertOrReplaceTranslations(
      List<Translation> translations) async {
    if (translations.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final translation in translations) {
      // Use the existing toMap() which excludes the auto-generated id
      batch.insert(
        'translations',
        translation.toMap(),
        conflictAlgorithm:
            ConflictAlgorithm.replace, // Replace based on UNIQUE constraint
      );
    }
    await batch.commit(noResult: true);
  }

  // --- Methods for Play Contexts ---

  /// Inserts or updates a play context.
  /// If a context with the same URI exists, it updates the lastPlayedAt timestamp.
  /// Otherwise, it inserts a new context.
  Future<void> insertOrUpdatePlayContext({
    required String contextUri,
    required String contextType,
    required String contextName,
    required String? imageUrl,
    required int lastPlayedAt,
  }) async {
    final db = await instance.database;
    final dataToInsert = {
      'contextUri': contextUri,
      'contextType': contextType,
      'contextName': contextName,
      'imageUrl': imageUrl,
      'lastPlayedAt': lastPlayedAt,
    };
    logger.d(
        '[DBHelper] Attempting to insert/update play_context: ${json.encode(dataToInsert)}'); // Log: Data to insert
    try {
      await db.insert(
        'play_contexts',
        dataToInsert,
        conflictAlgorithm:
            ConflictAlgorithm.replace, // Replace updates if PK exists
      );
      logger.d(
          '[DBHelper] Successfully inserted/updated play_context for URI: $contextUri'); // Log: Success
    } catch (e, s) {
      logger.e('[DBHelper] Error inserting/updating play_context',
          error: e, stackTrace: s); // Log: Error
      rethrow; // Re-throw the error so the provider layer can potentially handle it
    }
  }

  /// Retrieves the most recent play contexts, ordered by lastPlayedAt descending.
  /// Limits the results to the specified number.
  Future<List<Map<String, dynamic>>> getRecentPlayContexts(int limit) async {
    final db = await instance.database;
    logger.d(
        '[DBHelper] Querying play_contexts, orderBy: lastPlayedAt DESC, limit: $limit'); // Log: Query details
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'play_contexts',
        orderBy: 'lastPlayedAt DESC',
        limit: limit,
      );
      logger.d(
          '[DBHelper] Query successful, returned ${maps.length} contexts.'); // Log: Query success
      return maps;
    } catch (e, s) {
      logger.e('[DBHelper] Error querying play_contexts',
          error: e, stackTrace: s); // Log: Error
      rethrow; // Re-throw the error
    }
  }

  /// Fetches all play contexts from the database.
  Future<List<Map<String, dynamic>>> getAllPlayContexts() async {
    final db = await instance.database;
    logger.d('[DBHelper] Querying all play_contexts...');
    try {
      final List<Map<String, dynamic>> maps = await db.query('play_contexts');
      logger.d(
          '[DBHelper] getAllPlayContexts successful, returned ${maps.length} contexts.');
      return maps;
    } catch (e, s) {
      logger.e('[DBHelper] Error querying all play_contexts',
          error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Inserts or replaces multiple play contexts in a batch.
  Future<void> batchInsertOrReplacePlayContexts(
      List<Map<String, dynamic>> contexts) async {
    if (contexts.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    logger.d(
        '[DBHelper] Starting batch insert/replace for ${contexts.length} play contexts...');
    int count = 0;
    for (final context in contexts) {
      // Basic validation before adding to batch
      if (context['contextUri'] != null &&
          context['contextType'] != null &&
          context['contextName'] != null &&
          context['lastPlayedAt'] is int) {
        // Ensure lastPlayedAt is int
        batch.insert(
          'play_contexts',
          context, // Assuming the map structure matches the table columns
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        count++;
      } else {
        logger.w(
            '[DBHelper] Skipping invalid play context data in batch: ${json.encode(context)}');
      }
    }
    if (count > 0) {
      await batch.commit(noResult: true);
      logger.d(
          '[DBHelper] Batch insert/replace for $count play contexts committed.');
    } else {
      logger.w('[DBHelper] No valid play contexts found to commit in batch.');
    }
  }

  // --- Debug/Testing Methods ---

  /// Inserts sample data for testing if the database appears empty.
  Future<void> insertSampleDataIfNotExists() async {
    final db = await instance.database;

    // Check if tracks table is empty before inserting
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as count FROM tracks');
    final count = Sqflite.firstIntValue(countResult);

    if (count == 0) {
      debugPrint('Database appears empty, inserting sample data...');
      try {
        await db.transaction((txn) async {
          // Sample Track 1
          int track1Id = await txn.insert(
            'tracks',
            Track(
              trackId: 'spotify:track:sample1',
              trackName: 'Sample Track One',
              artistName: 'Test Artist',
              albumName: 'Sample Album',
              albumCoverUrl: 'https://via.placeholder.com/150',
              lastRecordedAt: DateTime.now()
                  .subtract(Duration(days: 1))
                  .millisecondsSinceEpoch,
              latestPlayedAt: DateTime.now()
                  .subtract(Duration(hours: 2))
                  .millisecondsSinceEpoch,
            ).toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          debugPrint(
              'Inserted sample track 1 with DB ID: $track1Id'); // track1Id here is the DB row id

          // Sample Track 2
          await txn.insert(
            'tracks',
            Track(
              trackId: 'spotify:track:sample2',
              trackName: 'Another Sample Song',
              artistName: 'Different Artist',
              albumName: 'Test Hits',
              // albumCoverUrl: null, // Optional
              lastRecordedAt: DateTime.now().millisecondsSinceEpoch,
              latestPlayedAt: DateTime.now()
                  .subtract(Duration(minutes: 30))
                  .millisecondsSinceEpoch,
            ).toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          // Sample Record for Track 1
          await txn.insert(
            'records',
            Record(
                    trackId: 'spotify:track:sample1', // Matches Track 1
                    noteContent: 'This is a test note for Sample Track One.',
                    rating: 3,
                    songTimestampMs: 30000,
                    recordedAt: DateTime.now()
                        .subtract(Duration(days: 1, hours: 1))
                        .millisecondsSinceEpoch,
                    contextUri: 'spotify:playlist:testplaylist',
                    contextName: 'My Test Playlist',
                    lyricsSnapshot:
                        'Oh sample lyrics line one\nLine two goes here')
                .toMap(),
          );

          // Sample Record for Track 2
          await txn.insert(
            'records',
            Record(
              trackId: 'spotify:track:sample2', // Matches Track 2
              noteContent: 'A quick thought about Another Sample Song.',
              rating: 3,
              recordedAt: DateTime.now().millisecondsSinceEpoch,
              // songTimestampMs, context, lyricsSnapshot are optional
            ).toMap(),
          );

          // Sample Translation for Track 1
          await txn.insert(
            'translations',
            Translation(
              trackId: 'spotify:track:sample1', // Matches Track 1
              languageCode: 'zh-CN',
              style: 'faithful',
              translatedLyrics: '哦 示例歌词第一行\n第二行在这里',
              generatedAt: DateTime.now()
                  .subtract(Duration(hours: 5))
                  .millisecondsSinceEpoch,
            ).toMap(),
            conflictAlgorithm: ConflictAlgorithm
                .replace, // Use replace as defined in insertTranslation
          );
        });
        debugPrint('Sample data inserted successfully.');
      } catch (e) {
        debugPrint('Error inserting sample data: $e');
      }
    } else {
      debugPrint(
          'Database already contains data, skipping sample data insertion.');
    }
  }

  // --- Helper Methods (Optional) ---

  // Example: Close the database (might be needed in some scenarios)
  Future<void> close() async {
    final db = await instance.database;
    db.close();
    _database = null; // Reset the static variable
  }
}
