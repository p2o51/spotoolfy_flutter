import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/library_provider.dart';
import '../providers/local_database_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/library_section.dart';
import '../widgets/search_section.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';

class Library extends StatefulWidget {
  const Library({super.key});

  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _wasAuthenticated = false; // Track previous auth state
  VoidCallback? _refreshLibraryCallback;

  @override
  void initState() {
    super.initState();
    // Add listener to sync text field with provider state
    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
    _searchController.text = searchProvider.searchQuery;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final isAuthenticated = spotifyProvider.username != null;
    
    if (isAuthenticated != _wasAuthenticated) {
      if (isAuthenticated) {
        // User logged in, refresh library
        _refreshLibraryCallback?.call(); 
      } else {
        // User logged out, clear library (using LibraryProvider) and search
        Provider.of<LibraryProvider>(context, listen: false).handleAuthStateChange(false);
        Provider.of<SearchProvider>(context, listen: false).clearSearch();
        _searchController.clear();
      }
    }
    
    _wasAuthenticated = isAuthenticated;
  }
  
  void _onSearchChanged() {
    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
    // Only update provider if text actually changed to avoid loops
    if (_searchController.text != searchProvider.searchQuery) {
       searchProvider.updateSearchQuery(_searchController.text);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Restore Consumer2 to use SearchProvider and LibraryProvider
    return Consumer2<SearchProvider, LibraryProvider>(
      builder: (context, searchProvider, libraryProvider, child) {
        final isSearchActive = searchProvider.isSearchActive;
        
        // Sync controller if provider clears search
        if (!isSearchActive && _searchController.text.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             _searchController.clear();
          });
        }
        
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final isWideScreen = screenWidth > 600;
            final maxContentWidth = isWideScreen ? 1200.0 : screenWidth;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                // Use a simple Column, no Stack needed now
                child: Column(
                  children: [
                    // Common search bar
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SearchBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hintText: 'Search songs, albums, artists...',
                        leading: const Icon(Icons.search),
                        trailing: _searchController.text.isNotEmpty
                          ? [
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  // Clear controller and provider
                                  _searchController.clear();
                                  searchProvider.clearSearch();
                                  _searchFocusNode.unfocus();
                                },
                                tooltip: 'Clear search',
                              ),
                            ]
                          : null,
                        elevation: const WidgetStatePropertyAll(0),
                        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
                        side: WidgetStatePropertyAll(
                          BorderSide(
                            color: Theme.of(context).colorScheme.outline.withAlpha((0.5 * 255).round()),
                          ),
                        ),
                        padding: const WidgetStatePropertyAll<EdgeInsets>(
                          EdgeInsets.symmetric(horizontal: 16.0),
                        ),
                        onSubmitted: (query) {
                          searchProvider.submitSearch(query);
                          _searchFocusNode.unfocus();
                        },
                        // onChanged handled by controller listener
                      ),
                    ),
                    
                    // Main content - either search results or library
                    Expanded(
                      child: Stack( // Wrap content with Stack
                        children: [
                          // Original content
                          isSearchActive
                            ? SearchSection(
                                onBackPressed: () {
                                  _searchController.clear();
                                  searchProvider.clearSearch();
                                  _searchFocusNode.unfocus();
                                },
                              )
                            : LibrarySection(
                                // Register callbacks to allow LibrarySection to trigger actions
                                registerRefreshCallback: (callback) {
                                  _refreshLibraryCallback = callback;
                                },
                              ),
                          
                          // Gradient overlay
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 24.0, // Adjust height as needed
                            child: IgnorePointer( // Prevent gradient from intercepting gestures
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Theme.of(context).scaffoldBackgroundColor, // Match background
                                      Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Modify MyCarouselView to use LocalDatabaseProvider
class MyCarouselView extends StatefulWidget {
  const MyCarouselView({super.key});

  @override
  State<MyCarouselView> createState() => _MyCarouselViewState();
}

class _MyCarouselViewState extends State<MyCarouselView> {
  @override
  void initState() {
    super.initState();
    // Fetch initial data using LocalDatabaseProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
         Provider.of<LocalDatabaseProvider>(context, listen: false).fetchRecentContexts();
      }
    });
  }

  // onTap handler remains similar but takes contextUri
  void _playContext(BuildContext context, String contextUri) {
    HapticFeedback.lightImpact();
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    // Extract type and id from URI (this might need adjustment based on URI format)
    // Assuming URI format like spotify:album:xxxx or spotify:playlist:yyyy
    final parts = contextUri.split(':');
    if (parts.length == 3) {
      final type = parts[1];
      final id = parts[2];
      spotifyProvider.playContext(type: type, id: id);
    } else {
      print('Error: Could not parse context URI: $contextUri');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consume LocalDatabaseProvider
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context);
    // Get recent contexts from the provider
    final recentContexts = localDbProvider.recentContexts;

    // Use a simple loading check (can be refined)
    // Consider adding a dedicated isLoadingContexts in LocalDbProvider if needed
    final isLoading = recentContexts.isEmpty && !localDbProvider.isLoading; // Crude check, needs refinement

    if (isLoading) {
      return _buildLoadingCarousel(context); // Show loading placeholder
    }

    if (recentContexts.isEmpty) {
      return const SizedBox.shrink(); // Show nothing if empty after loading
    }

    // Build the carousel using recentContexts
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final carouselHeight = screenWidth > 900 ? 300.0 : 190.0;
        final flexWeights = screenWidth > 900
            ? const [2, 7, 6, 5, 4, 3, 2]
            : screenWidth > 600
            ? const [2, 6, 5, 4, 3, 2]
            : const [3, 6, 3, 2];

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: carouselHeight),
            child: CarouselView.weighted(
              flexWeights: flexWeights,
              shrinkExtent: 0,
              itemSnapping: true,
              onTap: (index) {
                if (index >= 0 && index < recentContexts.length) {
                  final contextUri = recentContexts[index]['contextUri'] as String?;
                  if (contextUri != null) {
                    _playContext(context, contextUri);
                  }
                } else {
                   print('Error: Invalid index ($index) tapped in CarouselView.');
                }
              },
              children: recentContexts.map((contextData) {
                final imageUrl = contextData['imageUrl'] as String?;
                final fallbackColor = Theme.of(context).colorScheme.surfaceContainerHighest;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: fallbackColor,
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: fallbackColor,
                              child: const Icon(Icons.error),
                            ),
                          )
                        : Container( // Fallback if no image URL
                            color: fallbackColor,
                            child: Center(
                              child: Text(
                                contextData['contextName'] ?? '', // Show context name as fallback
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // _buildLoadingCarousel method remains the same
  Widget _buildLoadingCarousel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final carouselHeight = screenWidth > 900 ? 300.0 : 190.0;
        final itemExtent = screenWidth > 900 ? 300.0 : 190.0;
        
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: carouselHeight),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemExtent: itemExtent,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: index == 1 ? const CircularProgressIndicator() : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}