import 'dart:async';
import 'dart:convert'; // Import dart:convert for JSON handling
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'package:logger/logger.dart';
import 'spotify_provider.dart';

final logger = Logger();

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

  // Cache settings - 保持完整数据缓存
  static const String _playlistsCacheKey = 'user_playlists_cache';
  static const String _albumsCacheKey = 'user_albums_cache';
  static const String _cacheTimestampKey = 'library_cache_timestamp';
  // Cache duration - 6小时缓存，平衡性能和数据新鲜度
  static const Duration _cacheDuration = Duration(hours: 6);
  
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

    // Check authentication first
    if (_spotifyProvider.username == null) {
      logger.w("Cannot load library data: User not authenticated");
      _errorMessage = 'Please log in to Spotify to view your library';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _isLoading = true;
    // Don't notify initial loading state immediately to avoid flicker if cache hits

    // Try loading from cache first unless forcing refresh
    if (!forceRefresh) {
      final stopwatch = Stopwatch()..start(); // Measure cache load time
      bool cacheLoaded = await _loadFromCache();
      stopwatch.stop();
      logger.d("Cache load attempt took ${stopwatch.elapsedMilliseconds}ms");

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
      logger.i("Starting to fetch library data from Spotify API...");
      
      // Parallel data loading to reduce total loading time
      final results = await Future.wait([
        _spotifyProvider.getUserPlaylists(),
        _spotifyProvider.getUserSavedAlbums(),
      ]);
      stopwatch.stop();
      logger.d("API fetch took ${stopwatch.elapsedMilliseconds}ms");
      
      _userPlaylists = results[0];
      _userSavedAlbums = results[1];
      
      logger.i("Loaded ${_userPlaylists.length} playlists and ${_userSavedAlbums.length} albums");
      
      _isFirstLoad = false;
      _isLoading = false;

      await _saveToCache(); // Save fresh data to cache
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load library data: $e';
      logger.w(_errorMessage); // Log error
      _isLoading = false;
      
      // 尝试加载过期缓存作为备用数据
      if (!forceRefresh && _userPlaylists.isEmpty && _userSavedAlbums.isEmpty) {
        logger.i("API failed, attempting to load expired cache as fallback...");
        final cacheLoaded = await _loadFromCache(ignoreTimestamp: true);
        if (cacheLoaded) {
          logger.i("Successfully loaded expired cache as fallback");
          _errorMessage = 'Using cached data - please refresh when connection improves';
        }
      }
      
      notifyListeners();
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
          logger.i("Loading expired cache as fallback.");
        } else {
          final timestamp = DateTime.parse(timestampString);
          if (DateTime.now().difference(timestamp) <= _cacheDuration) {
            isCacheValid = true;
          } else {
            logger.i("Library cache expired.");
          }
        }
      }

      if (isCacheValid) {
        final playlistsJson = prefs.getString(_playlistsCacheKey);
        final albumsJson = prefs.getString(_albumsCacheKey);

        if (playlistsJson != null && albumsJson != null) {
          _userPlaylists = List<Map<String, dynamic>>.from(jsonDecode(playlistsJson));
          _userSavedAlbums = List<Map<String, dynamic>>.from(jsonDecode(albumsJson));
          logger.i("Complete library cache loaded: ${_userPlaylists.length} playlists, ${_userSavedAlbums.length} albums");
          return true; // Cache loaded successfully
        }
      }
    } catch (e) {
      logger.w("Error loading library from cache: $e");
      // 只有在严重错误时才清除缓存，对于 JSON 解析错误可能只是临时的
      if (e.toString().contains('FormatException') || e.toString().contains('type') || e.toString().contains('cast')) {
        logger.e("Cache data corrupted, clearing cache");
        await _clearCache(); 
      } else {
        logger.w("Cache load failed but keeping cache for retry");
      }
    }
    return false; // Cache miss, invalid, expired, or error
  }

  // 保存完整的库数据到缓存
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final playlistsJson = jsonEncode(_userPlaylists);
      final albumsJson = jsonEncode(_userSavedAlbums);

      await prefs.setString(_playlistsCacheKey, playlistsJson);
      await prefs.setString(_albumsCacheKey, albumsJson);
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
      
      logger.i("Complete library cache saved: ${_userPlaylists.length} playlists, ${_userSavedAlbums.length} albums");
    } catch (e) {
      logger.w("Error saving library to cache: $e");
    }
  }

  // Helper to clear cache
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_playlistsCacheKey);
      await prefs.remove(_albumsCacheKey);
      await prefs.remove(_cacheTimestampKey);
      logger.i("Complete library cache cleared.");
    } catch (e) {
      logger.w("Error clearing library cache: $e");
    }
  }
  
  // Public method to manually clear cache (for settings page)
  Future<void> clearCache() async {
    await _clearCache();
    // Also clear in-memory data
    _userPlaylists = [];
    _userSavedAlbums = [];
    _isFirstLoad = true;
    notifyListeners();
  }

  // 智能缓存管理 - 仅在必要时清除缓存
  Future<void> handleTokenExpiration() async {
    logger.i("Token expired, clearing memory but keeping cache for re-login");
    // 仅清除内存数据，保留磁盘缓存
    _userPlaylists = [];
    _userSavedAlbums = [];
    _isFirstLoad = true;
    _errorMessage = null;
    notifyListeners();
    // 不清除磁盘缓存，以便重新登录后快速加载
  }

  // 检查缓存是否可用作为备用数据
  Future<bool> hasFallbackCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampString = prefs.getString(_cacheTimestampKey);
      final playlistsJson = prefs.getString(_playlistsCacheKey);
      final albumsJson = prefs.getString(_albumsCacheKey);
      
      return timestampString != null && playlistsJson != null && albumsJson != null;
    } catch (e) {
      logger.w("Error checking fallback cache: $e");
      return false;
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
      // 仅清除内存数据，保留缓存以便下次登录时快速加载
      _userPlaylists = [];
      _userSavedAlbums = [];
      _isFirstLoad = true;
      _errorMessage = null; // 清除错误信息
      logger.i("Auth state changed to logged out - keeping cache for faster re-login");
      // OPTIMIZATION: Keep cache across login sessions to improve re-login experience
      // Only clear cache if explicitly requested (e.g., in settings)
      // _clearCache(); // Don't clear cache on logout by default
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