import 'dart:async';
import 'package:flutter/material.dart';
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
  bool _isLoadingMore = false;
  bool _isFirstLoad = true;
  
  // Error state
  String? _errorMessage;
  
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
  
  // Main data loading method
  Future<void> loadData() async {
    if (_isLoading) return;
    
    final isFirstLoad = _isFirstLoad;
    
    _errorMessage = null;
    _isLoading = true;
    
    // Only notify on state change if it's not the first load
    // This prevents showing loading indicator on initial load
    if (!isFirstLoad) {
      notifyListeners();
    }
    
    try {
      // Parallel data loading to reduce total loading time
      final results = await Future.wait([
        _spotifyProvider.getUserPlaylists(),
        _spotifyProvider.getUserSavedAlbums(),
      ]);
      
      _userPlaylists = results[0];
      _userSavedAlbums = results[1];
      _isFirstLoad = false;
      _isLoading = false;
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load data: $e';
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Load more data when scrolling (pagination)
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
      if (_isFirstLoad || _userPlaylists.isEmpty) {
        loadData();
      }
    } else {
      // Clear data on logout
      _userPlaylists = [];
      _userSavedAlbums = [];
      _isFirstLoad = true;
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