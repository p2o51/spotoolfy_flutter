import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';

class LibraryCacheResult {
  final DateTime timestamp;
  final List<Map<String, dynamic>> playlists;
  final List<Map<String, dynamic>> albums;

  LibraryCacheResult({
    required this.timestamp,
    required this.playlists,
    required this.albums,
  });

  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(timestamp) > maxAge;
  }
}

class LibraryCacheService {
  LibraryCacheService({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;
  static const String _fileName = 'library_cache.json';

  String? _activeUserId;

  /// Select the Spotify user whose library should be cached.
  void setActiveUser(String? userId) {
    final trimmed = userId?.trim();
    final nextId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (_activeUserId == nextId) return;
    _activeUserId = nextId;
  }

  String get _resolvedFileName {
    final userId = _activeUserId;
    if (userId == null) return _fileName;
    return 'library_cache_${_sanitizeUserId(userId)}.json';
  }

  Future<File> _getCacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_resolvedFileName');
  }

  Future<File?> _getLegacyCacheFileIfPresent() async {
    if (_activeUserId == null) return null;
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/$_fileName');
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<LibraryCacheResult?> loadCache() async {
    try {
      var file = await _getCacheFile();
      if (!await file.exists()) {
        final legacyFile = await _getLegacyCacheFileIfPresent();
        if (legacyFile == null || !await legacyFile.exists()) {
          return null;
        }
        file = legacyFile;
      }

      final raw = await file.readAsString();
      if (raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _logger.w('Library cache file has unexpected structure.');
        return null;
      }

      final timestampString = decoded['timestamp'] as String?;
      if (timestampString == null) {
        _logger.w('Library cache missing timestamp.');
        return null;
      }

      final playlistsRaw = decoded['playlists'];
      final albumsRaw = decoded['albums'];
      if (playlistsRaw is! List || albumsRaw is! List) {
        _logger.w('Library cache missing playlist/album data.');
        return null;
      }

      final playlists = playlistsRaw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final albums = albumsRaw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      return LibraryCacheResult(
        timestamp: DateTime.tryParse(timestampString) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        playlists: playlists,
        albums: albums,
      );
    } catch (e) {
      _logger.w('Failed to read library cache: $e');
      return null;
    }
  }

  Future<void> saveCache({
    required List<Map<String, dynamic>> playlists,
    required List<Map<String, dynamic>> albums,
  }) async {
    if (_activeUserId == null) {
      _logger.w(
          'Attempted to save library cache without active user context - skipping.');
      return;
    }
    try {
      final file = await _getCacheFile();
      final payload = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'playlists': playlists,
        'albums': albums,
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
      _logger.i('Library cache saved to ${file.path}.');
    } catch (e) {
      _logger.w('Failed to write library cache: $e');
    }
  }

  Future<void> clearCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
        _logger.i('Library cache file cleared.');
      }
    } catch (e) {
      _logger.w('Failed to clear library cache: $e');
    }
  }

  Future<bool> hasCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        return true;
      }
      final legacyFile = await _getLegacyCacheFileIfPresent();
      if (legacyFile != null && await legacyFile.exists()) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String _sanitizeUserId(String userId) {
    return userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
}
