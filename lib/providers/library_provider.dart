import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../services/library_cache_service.dart';
import 'spotify_provider.dart';

final logger = Logger();

class LibraryProvider extends ChangeNotifier {
  final SpotifyProvider _spotifyProvider;

  // Data
  List<Map<String, dynamic>> _userPlaylists = [];
  List<Map<String, dynamic>> _userSavedAlbums = [];

  String? _activeUsername;
  String? _refreshWarningMessage;

  // Filters
  bool _showPlaylists = true;
  bool _showAlbums = true;

  // Loading states
  bool _isLoading = false;
  bool _isLoadingMore =
      false; // Note: loadMoreData is not cached in this implementation
  bool _isFirstLoad = true;

  // Error state
  String? _errorMessage;

  // Cache duration - 6小时缓存，平衡性能和数据新鲜度
  static const Duration _cacheDuration = Duration(hours: 6);
  final LibraryCacheService _cacheService;

  // Getters
  List<Map<String, dynamic>> get userPlaylists => _userPlaylists;
  List<Map<String, dynamic>> get userSavedAlbums => _userSavedAlbums;
  bool get showPlaylists => _showPlaylists;
  bool get showAlbums => _showAlbums;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isFirstLoad => _isFirstLoad;
  String? get errorMessage => _errorMessage;
  bool get hasData => _userPlaylists.isNotEmpty || _userSavedAlbums.isNotEmpty;
  String? get refreshWarningMessage => _refreshWarningMessage;

  // Combined items based on filters
  List<Map<String, dynamic>> get filteredItems {
    final items = <Map<String, dynamic>>[];

    if (_showPlaylists) {
      items.addAll(_userPlaylists.where((p) {
        final hasImage = p['images'] != null &&
            p['images'].isNotEmpty &&
            p['images'][0]['url'] != null;
        return hasImage;
      }).map((p) => ({...p, 'type': 'playlist'})));
    }

    if (_showAlbums) {
      items.addAll(_userSavedAlbums.where((a) {
        final hasImage = a['images'] != null &&
            a['images'].isNotEmpty &&
            a['images'][0]['url'] != null;
        return hasImage;
      }).map((a) => ({...a, 'type': 'album'})));
    }

    return items;
  }

  void _handleSpotifyProviderChange() {
    _syncActiveUser();
  }

  void _syncActiveUser() {
    final username = _spotifyProvider.username;
    if (username == _activeUsername) {
      return;
    }

    _activeUsername = username;
    _cacheService.setActiveUser(username);

    if (username == null) {
      _userPlaylists = [];
      _userSavedAlbums = [];
      _refreshWarningMessage = null;
      _errorMessage = null;
      _isFirstLoad = true;
      notifyListeners();
      return;
    }

    _userPlaylists = [];
    _userSavedAlbums = [];
    _refreshWarningMessage = null;
    _errorMessage = null;
    _isFirstLoad = true;
    notifyListeners();
    loadData();
  }

  LibraryProvider(this._spotifyProvider, {LibraryCacheService? cacheService})
      : _cacheService = cacheService ?? LibraryCacheService() {
    _spotifyProvider.addListener(_handleSpotifyProviderChange);
    _syncActiveUser();
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
    if (_isLoading) {
      return;
    }

    final username = _spotifyProvider.username;
    _cacheService.setActiveUser(username);
    _activeUsername = username;

    if (username == null) {
      logger.d("Cannot load library data: User not authenticated");
      if (hasData || _errorMessage != null || _refreshWarningMessage != null) {
        _userPlaylists = [];
        _userSavedAlbums = [];
        _errorMessage = null;
        _refreshWarningMessage = null;
        _isFirstLoad = true;
        notifyListeners();
      }
      return;
    }

    if (!forceRefresh) {
      _errorMessage = null;
    }

    var hasExistingData = hasData;

    if (!forceRefresh) {
      final stopwatch = Stopwatch()..start();
      final cacheLoaded = await _loadFromCache();
      stopwatch.stop();
      logger.d("Cache load attempt took ${stopwatch.elapsedMilliseconds}ms");

      if (cacheLoaded) {
        hasExistingData = hasData;
        _isFirstLoad = false;
        notifyListeners();
        await _fetchFromApi(showLoadingIndicator: !hasExistingData);
        return;
      }
    }

    await _fetchFromApi(showLoadingIndicator: !hasExistingData);
  }

  Future<void> _fetchFromApi({required bool showLoadingIndicator}) async {
    if (_isLoading) return;

    final hadDataBeforeFetch = hasData;

    if (showLoadingIndicator) {
      _isLoading = true;
      notifyListeners();
    } else {
      _isLoading = true;
    }

    try {
      final stopwatch = Stopwatch()..start();
      logger.i("Starting to fetch library data from Spotify API...");

      final results = await Future.wait([
        _spotifyProvider.getUserPlaylists(),
        _spotifyProvider.getUserSavedAlbums(),
      ]);
      stopwatch.stop();
      logger.d("API fetch took ${stopwatch.elapsedMilliseconds}ms");

      _userPlaylists = results[0];
      _userSavedAlbums = results[1];
      logger.i(
          "Loaded ${_userPlaylists.length} playlists and ${_userSavedAlbums.length} albums");

      _isFirstLoad = false;
      _errorMessage = null;
      _refreshWarningMessage = null;
      await _saveToCache();
    } catch (e) {
      final failureMessage = 'Failed to refresh library data: $e';
      logger.w(failureMessage);

      if (hadDataBeforeFetch) {
        _refreshWarningMessage = failureMessage;
      } else {
        _errorMessage = failureMessage;
      }

      if (!hadDataBeforeFetch) {
        logger.i("API failed, attempting to load expired cache as fallback...");
        final cacheLoaded = await _loadFromCache(ignoreTimestamp: true);
        if (cacheLoaded) {
          logger.i("Successfully loaded expired cache as fallback");
          _errorMessage = null;
          _refreshWarningMessage =
              'Using cached data - please refresh when connection improves';
          _isFirstLoad = false;
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Helper to load from cache
  Future<bool> _loadFromCache({bool ignoreTimestamp = false}) async {
    try {
      final cache = await _cacheService.loadCache();
      if (cache == null) {
        return false;
      }

      if (!ignoreTimestamp && cache.isExpired(_cacheDuration)) {
        logger.i("Library cache expired.");
        return false;
      }

      if (ignoreTimestamp && cache.isExpired(_cacheDuration)) {
        logger.i("Loading expired cache as fallback.");
      }

      _userPlaylists = cache.playlists;
      _userSavedAlbums = cache.albums;
      logger.i(
          "Library cache loaded: ${_userPlaylists.length} playlists, ${_userSavedAlbums.length} albums");
      return true;
    } catch (e) {
      logger.w("Error loading library from cache: $e");
      // 只有在严重错误时才清除缓存，对于 JSON 解析错误可能只是临时的
      if (e.toString().contains('FormatException') ||
          e.toString().contains('type') ||
          e.toString().contains('cast')) {
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
      await _cacheService.saveCache(
        playlists: _userPlaylists,
        albums: _userSavedAlbums,
      );
      logger.i(
          "Library cache saved: ${_userPlaylists.length} playlists, ${_userSavedAlbums.length} albums");
    } catch (e) {
      logger.w("Error saving library to cache: $e");
    }
  }

  // Helper to clear cache
  Future<void> _clearCache() async {
    try {
      await _cacheService.clearCache();
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
    _refreshWarningMessage = null;
    _errorMessage = null;
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
    _refreshWarningMessage = null;
    notifyListeners();
    // 不清除磁盘缓存，以便重新登录后快速加载
  }

  // 检查缓存是否可用作为备用数据
  Future<bool> hasFallbackCache() async {
    try {
      final cache = await _cacheService.loadCache();
      return cache != null;
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
        final morePlaylists =
            await _spotifyProvider.getUserPlaylists(offset: playlistOffset);
        _userPlaylists.addAll(morePlaylists);
      }

      if (_showAlbums) {
        final moreAlbums =
            await _spotifyProvider.getUserSavedAlbums(offset: albumOffset);
        _userSavedAlbums.addAll(moreAlbums);
      }

      await _saveToCache();

      _isLoadingMore = false;
      notifyListeners();
    } catch (e) {
      _refreshWarningMessage = 'Failed to load more data: $e';
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // Handle login state changes
  void handleAuthStateChange(bool isAuthenticated) {
    if (isAuthenticated) {
      _syncActiveUser();
      loadData(forceRefresh: true);
    } else {
      // 仅清除内存数据，保留缓存以便下次登录时快速加载
      _userPlaylists = [];
      _userSavedAlbums = [];
      _isFirstLoad = true;
      _errorMessage = null; // 清除错误信息
      _refreshWarningMessage = null;
      _cacheService.setActiveUser(null);
      _activeUsername = null;
      logger.i(
          "Auth state changed to logged out - keeping cache for faster re-login");
      // OPTIMIZATION: Keep cache across login sessions to improve re-login experience
      // Only clear cache if explicitly requested (e.g., in settings)
      // _clearCache(); // Don't clear cache on logout by default
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _spotifyProvider.removeListener(_handleSpotifyProviderChange);
    super.dispose();
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
