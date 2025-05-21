import 'dart:async';
import 'dart:convert'; // Import dart:convert for JSON handling
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'spotify_provider.dart';

class LibraryProvider extends ChangeNotifier {
  final SpotifyProvider _spotifyProvider;
  
  // Data
  List<Map<String, dynamic>> _userPlaylists = [];
  List<Map<String, dynamic>> _userSavedAlbums = [];
  
  // Filters
  bool _showPlaylists = true;
  bool _showAlbums = true;
  
  // Loading states
  bool _isLoading = false;
  bool _isLoadingMore = false; // Note: loadMoreData is not cached in this implementation
  bool _isFirstLoad = true;
  
  // Error state
  String? _errorMessage;

  // Cache settings
  static const String _playlistsCacheKey = 'user_playlists_cache';
  static const String _albumsCacheKey = 'user_albums_cache';
  static const String _cacheTimestampKey = 'library_cache_timestamp';
  // Cache duration (e.g., 1 hour)
  static const Duration _cacheDuration = Duration(hours: 1);
  
  // Getters
  List<Map<String, dynamic>> get userPlaylists => _userPlaylists;
  List<Map<String, dynamic>> get userSavedAlbums => _userSavedAlbums;
  bool get showPlaylists => _showPlaylists;
  bool get showAlbums => _showAlbums;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isFirstLoad => _isFirstLoad;
  String? get errorMessage => _errorMessage;
  
  // Combined items based on filters
  List<Map<String, dynamic>> get filteredItems {
    final items = <Map<String, dynamic>>[];
    
    if (_showPlaylists) {
      items.addAll(_userPlaylists.where((p) {
        final hasImage = p['images'] != null && p['images'].isNotEmpty && p['images'][0]['url'] != null;
        return hasImage;
      }).map((p) => ({...p, 'type': 'playlist'})));
    }
    
    if (_showAlbums) {
      items.addAll(_userSavedAlbums.where((a) {
        final hasImage = a['images'] != null && a['images'].isNotEmpty && a['images'][0]['url'] != null;
        return hasImage;
      }).map((a) => ({...a, 'type': 'album'})));
    }
    
    return items;
  }
  
  LibraryProvider(this._spotifyProvider) {
    // Only load data initially if the user is already authenticated
    // loadData will now check cache first
    if (_spotifyProvider.username != null) {
      loadData();
    }
  }
  
  // Update filter settings
  void setFilters({bool? showPlaylists, bool? showAlbums}) {
    bool hasChanged = false;
    
    if (showPlaylists != null && showPlaylists != _showPlaylists) {
      _showPlaylists = showPlaylists;
      hasChanged = true;
    }
    
    if (showAlbums != null && showAlbums != _showAlbums) {
      _showAlbums = showAlbums;
      hasChanged = true;
    }
    
    if (hasChanged) {
      notifyListeners();
    }
  }
  
  // Main data loading method with cache logic
  Future<void> loadData({bool forceRefresh = false}) async {
    if (_isLoading) return;

    _errorMessage = null;
    _isLoading = true;
    // Don't notify initial loading state immediately to avoid flicker if cache hits

    // Try loading from cache first unless forcing refresh
    if (!forceRefresh) {
      final stopwatch = Stopwatch()..start(); // Measure cache load time
      bool cacheLoaded = await _loadFromCache();
      stopwatch.stop();
      print("Cache load attempt took ${stopwatch.elapsedMilliseconds}ms");

      if (cacheLoaded) {
        _isLoading = false;
        _isFirstLoad = false; // Cache counts as a load
        notifyListeners();
        // Optional: Trigger a background refresh after loading cache?
        // _refreshInBackground(); 
        return; // Data loaded from cache
      }
    }

    // If cache miss, invalid, or forceRefresh, fetch from API
    _isLoading = true; // Ensure loading state is true if cache missed
    notifyListeners(); // Notify loading state now

    try {
      final stopwatch = Stopwatch()..start(); // Measure API fetch time
      // Parallel data loading to reduce total loading time
      final results = await Future.wait([
        _spotifyProvider.getUserPlaylists(),
        _spotifyProvider.getUserSavedAlbums(),
      ]);
      stopwatch.stop();
      print("API fetch took ${stopwatch.elapsedMilliseconds}ms");
      
      _userPlaylists = results[0];
      _userSavedAlbums = results[1];
      _isFirstLoad = false;
      _isLoading = false;

      await _saveToCache(); // Save fresh data to cache
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load library data: $e';
      print(_errorMessage); // Log error
      _isLoading = false;
      notifyListeners();
      // Optionally try loading expired cache as fallback on API error?
      // if (!forceRefresh) await _loadFromCache(ignoreTimestamp: true);
    }
  }

  // Helper to load from cache
  Future<bool> _loadFromCache({bool ignoreTimestamp = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampString = prefs.getString(_cacheTimestampKey);
      
      // Check if cache exists and is still valid (or if ignoring timestamp)
      bool isCacheValid = false;
      if (timestampString != null) {
        if (ignoreTimestamp) {
          isCacheValid = true;
          print("Loading expired cache as fallback.");
        } else {
          final timestamp = DateTime.parse(timestampString);
          if (DateTime.now().difference(timestamp) <= _cacheDuration) {
            isCacheValid = true;
          } else {
            print("Library cache expired.");
          }
        }
      }

      if (isCacheValid) {
        final playlistsJson = prefs.getString(_playlistsCacheKey);
        final albumsJson = prefs.getString(_albumsCacheKey);

        if (playlistsJson != null && albumsJson != null) {
          // Use compute function for potentially long JSON decoding? (Consider if lists are huge)
          _userPlaylists = List<Map<String, dynamic>>.from(jsonDecode(playlistsJson));
          _userSavedAlbums = List<Map<String, dynamic>>.from(jsonDecode(albumsJson));
          print("Library data loaded from cache.");
          return true; // Cache loaded successfully
        }
      }
    } catch (e) {
      print("Error loading library from cache: $e");
      // Clear cache if parsing fails to avoid loading corrupted data next time
      await _clearCache(); 
    }
    return false; // Cache miss, invalid, expired, or error
  }

  // Helper to save to cache
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Use compute function for potentially long JSON encoding?
      final playlistsJson = jsonEncode(_userPlaylists);
      final albumsJson = jsonEncode(_userSavedAlbums);

      await prefs.setString(_playlistsCacheKey, playlistsJson);
      await prefs.setString(_albumsCacheKey, albumsJson);
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
      print("Library data saved to cache.");
    } catch (e) {
      print("Error saving library to cache: $e");
    }
  }

  // Helper to clear cache
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_playlistsCacheKey);
      await prefs.remove(_albumsCacheKey);
      await prefs.remove(_cacheTimestampKey);
      print("Library cache cleared.");
    } catch (e) {
      print("Error clearing library cache: $e");
    }
  }
  
  // Load more data when scrolling (pagination) - NOT CACHED
  Future<void> loadMoreData() async {
    if (_isLoadingMore || _isLoading) return;
    
    _isLoadingMore = true;
    notifyListeners();
    
    try {
      // Calculate current offsets
      final playlistOffset = _userPlaylists.length;
      final albumOffset = _userSavedAlbums.length;
      
      // Load more data based on filters
      if (_showPlaylists) {
        final morePlaylists = await _spotifyProvider.getUserPlaylists(offset: playlistOffset);
        _userPlaylists.addAll(morePlaylists);
      }
      
      if (_showAlbums) {
        final moreAlbums = await _spotifyProvider.getUserSavedAlbums(offset: albumOffset);
        _userSavedAlbums.addAll(moreAlbums);
      }
      
      _isLoadingMore = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load more data: $e';
      _isLoadingMore = false;
      notifyListeners();
    }
  }
  
  // Handle login state changes
  void handleAuthStateChange(bool isAuthenticated) {
    if (isAuthenticated) {
      // Try loading data (which will check cache first)
      // Don't check _isFirstLoad here, always try loading on login
      loadData();
    } else {
      // Clear data on logout
      _userPlaylists = [];
      _userSavedAlbums = [];
      _isFirstLoad = true;
      _clearCache(); // Clear cache on logout
      notifyListeners();
    }
  }
  
  // Play a library item
  void playItem(Map<String, dynamic> item) {
    final type = item['type'];
    final id = item['id'];
    if (type != null && id != null) {
      _spotifyProvider.playContext(type: type, id: id);
    }
  }
} 