import 'package:logger/logger.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'spotify_provider.dart';

final _logger = Logger();

class SearchProvider extends ChangeNotifier {
  final SpotifyProvider _spotifyProvider;
  
  // Search state
  String _searchQuery = '';
  bool _isSearching = false;
  Map<String, List<Map<String, dynamic>>> _searchResults = {};
  String? _errorMessage;
  List<Map<String, dynamic>> _filteredResultsCache = const [];
  bool _filteredResultsDirty = true;

  // Track search requests to avoid applying stale results.
  int _searchRequestId = 0;
  
  // Debounce timer for search
  Timer? _debounceTimer;
  static const _debounceTime = Duration(milliseconds: 500);
  
  // Constructor
  SearchProvider(this._spotifyProvider);
  
  // Getters
  String get searchQuery => _searchQuery;
  bool get isSearching => _isSearching;
  Map<String, List<Map<String, dynamic>>> get searchResults => _searchResults;
  String? get errorMessage => _errorMessage;
  
  // Check if search is active
  bool get isSearchActive => _searchQuery.isNotEmpty;
  
  // Get combined and filtered search results
  List<Map<String, dynamic>> get filteredResults {
    if (_filteredResultsDirty) {
      _filteredResultsCache = _buildFilteredResults();
      _filteredResultsDirty = false;
    }
    return _filteredResultsCache;
  }

  List<Map<String, dynamic>> _buildFilteredResults() {
    final List<Map<String, dynamic>> result = [];
    
    if (_searchQuery.isEmpty) return result;
    
    // Add tracks if available
    if (_searchResults.containsKey('tracks')) {
      result.addAll(_searchResults['tracks']!
        .where((t) {
          final hasImage = t['images'] != null && t['images'].isNotEmpty && t['images'][0]['url'] != null;
          return hasImage;
        })
        .map((t) => ({...t, 'type': 'track'}))
      );
    }
    
    // Add albums if available
    if (_searchResults.containsKey('albums')) {
      result.addAll(_searchResults['albums']!
        .where((a) {
          final hasImage = a['images'] != null && a['images'].isNotEmpty && a['images'][0]['url'] != null;
          return hasImage;
        })
        .map((a) => ({...a, 'type': 'album'}))
      );
    }
    
    // Add playlists if available
    if (_searchResults.containsKey('playlists')) {
      result.addAll(_searchResults['playlists']!
        .where((p) {
          final hasImage = p['images'] != null && p['images'].isNotEmpty && p['images'][0]['url'] != null;
          return hasImage;
        })
        .map((p) => ({...p, 'type': 'playlist'}))
      );
    }
    
    // Add artists if available
    if (_searchResults.containsKey('artists')) {
      result.addAll(_searchResults['artists']!
        .where((a) {
          final hasImage = a['images'] != null && a['images'].isNotEmpty && a['images'][0]['url'] != null;
          return hasImage;
        })
        .map((a) => ({...a, 'type': 'artist'}))
      );
    }
    
    return result;
  }

  void _markFilteredResultsDirty() {
    _filteredResultsDirty = true;
  }
  
  // Update search query with debounce
  void updateSearchQuery(String query) {
    if (query == _searchQuery) return;

    // Cancel previous timer only when query changes.
    _debounceTimer?.cancel();
    
    _searchQuery = query;
    _errorMessage = null;
    _markFilteredResultsDirty();
    
    // Clear results if query is empty
    if (query.isEmpty) {
      _searchResults = {};
      _isSearching = false;
      _searchRequestId++;
      _markFilteredResultsDirty();
      notifyListeners();
      return;
    }
    
    // Set new timer for search
    final requestId = ++_searchRequestId;
    _debounceTimer = Timer(_debounceTime, () {
      performSearch(query, requestId: requestId);
    });
    
    // Notify listeners immediately about query change
    notifyListeners();
  }
  
  // Immediate search without debounce (for submit action)
  void submitSearch(String query) {
    // Cancel any pending debounce
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      _searchQuery = '';
      _searchResults = {};
      _errorMessage = null;
      _isSearching = false;
      _searchRequestId++;
      _markFilteredResultsDirty();
      notifyListeners();
      return;
    }
    
    if (query != _searchQuery) {
      _searchQuery = query;
      _errorMessage = null;
      _markFilteredResultsDirty();
      notifyListeners();
    }
    
    final requestId = ++_searchRequestId;
    performSearch(query, requestId: requestId);
  }
  
  // Clear search
  void clearSearch() {
    _debounceTimer?.cancel();
    _searchQuery = '';
    _searchResults = {};
    _errorMessage = null;
    _isSearching = false;
    _searchRequestId++;
    _markFilteredResultsDirty();
    notifyListeners();
  }
  
  // Perform the actual search
  Future<void> performSearch(String query, {int? requestId}) async {
    if (query.trim().isEmpty) return;
    
    final activeRequestId = requestId ?? ++_searchRequestId;
    _isSearching = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // Use default types: track, album, artist, playlist
      final results = await _spotifyProvider.searchItems(query);
      
      if (!_isLatestRequest(activeRequestId, query)) return;

      _searchResults = results;
      _markFilteredResultsDirty();
    } catch (e) {
      _logger.d('Search failed: $e');
      if (!_isLatestRequest(activeRequestId, query)) return;
      _errorMessage = 'Search failed: $e';
    } finally {
      if (_isLatestRequest(activeRequestId, query)) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  bool _isLatestRequest(int requestId, String query) {
    return requestId == _searchRequestId && query == _searchQuery;
  }
  
  // Play a search result item based on its type
  void playItem(Map<String, dynamic> item) {
    final type = item['type'];
    final id = item['id'];
    final uri = item['uri']; // Get the URI

    if (type == null || (id == null && uri == null)) {
      _logger.d('Error: Search item missing type or identifier (id/uri).');
      return;
    }

    _logger.d('Playing item: type=$type, id=$id, uri=$uri');

    try {
      if (type == 'track' && uri != null) {
        _logger.d('[SearchProvider.playItem] Calling playTrack for URI: $uri');
        _spotifyProvider.playTrack(trackUri: uri);
      } else if ((type == 'album' || type == 'playlist' || type == 'artist') && id != null) {
        _logger.d('[SearchProvider.playItem] Calling playContext for type: $type, id: $id');
        // For artist, playContext might play top tracks or fail gracefully
        _spotifyProvider.playContext(type: type, id: id);
      } else {
        _logger.d('Error: Unsupported type ($type) or missing identifier for playback.');
      }
    } catch (e) {
      _logger.d('Error initiating playback: $e');
      // Optionally show a user-facing error message
      _errorMessage = 'Failed to play item: $e';
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
} 
