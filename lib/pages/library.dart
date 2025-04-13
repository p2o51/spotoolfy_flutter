import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/library_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/library_section.dart';
import '../widgets/search_section.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
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
        // User logged out, clear library and search
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

// 修改 MyCarouselView 的实现为原来的样式
class MyCarouselView extends StatefulWidget {
  const MyCarouselView({super.key});

  @override
  State<MyCarouselView> createState() => _MyCarouselViewState();
}

class _MyCarouselViewState extends State<MyCarouselView> {
  List<Map<String, dynamic>> allItems = [];
  Set<String> _currentDisplayedItemUris = {}; // Store current URIs
  bool _isLoading = false;
  bool _isUpdating = false; // Flag for updates after initial load
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _loadInitialItems();
  }

  // Add a method to trigger refresh, could be called from parent if needed
  Future<void> refreshItems() async {
    if (!mounted || _isLoading || _isUpdating) return; // Prevent concurrent refreshes
    await _loadItems(isRefresh: true);
  }

  void _loadInitialItems() {
    _loadItems(isRefresh: false);
  }

  // Combined loading and refresh logic
  Future<void> _loadItems({required bool isRefresh}) async {
    if (!mounted) return;

    // Show appropriate loading indicator
    setState(() {
      if (!isRefresh) {
        _isLoading = true; // Full loading indicator on initial load
      } else {
        _isUpdating = true; // Overlay indicator during refresh
      }
    });

    try {
      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      final newItemsRaw = await spotifyProvider.getRecentlyPlayed();
      if (!mounted) return;

      // Filter for valid items with images before comparison/processing
      final newValidItems = newItemsRaw.where((item) {
        final hasImage = item['images'] != null && item['images'].isNotEmpty && item['images'][0]['url'] != null;
        return hasImage;
      }).toList();

      // --- Limit to 20 items --- START
      if (newValidItems.length > 20) {
        newValidItems.length = 20;
      }
      // --- Limit to 20 items --- END

      // Extract URIs from the new valid items (now limited to 20)
      final newItemUris = newValidItems.map((item) => item['uri'] as String).toSet();

      // Compare with current URIs
      if (!const SetEquality().equals(newItemUris, _currentDisplayedItemUris)) {
        // print('Recently played items changed. Updating carousel.');

        // Preload images for the new items
        if (newValidItems.isNotEmpty) {
          final imageFutures = newValidItems.map((item) {
            final imageUrl = item['images'][0]['url'];
            if (imageUrl != null) {
              return precacheImage(CachedNetworkImageProvider(imageUrl), context);
            }
            return Future.value(); // Return a completed future if no image
          }).toList();

          // Wait for all images to preload
          await Future.wait(imageFutures);
          if (!mounted) return; // Check again after async gap
        }

        // Update state only after preloading and if URIs changed
        setState(() {
          allItems = List.from(newValidItems); // Use the filtered valid items
          _currentDisplayedItemUris = newItemUris;
          // print('Carousel updated with ${allItems.length} items.');
          if (!_hasLoadedOnce) _hasLoadedOnce = true;
        });
      } else {
        // print('Recently played items haven\'t changed significantly.');
        if (!_hasLoadedOnce) _hasLoadedOnce = true; // Still mark as loaded
      }
    } catch (e) {
      // print('Error loading recently played: $e');
      if (mounted) {
        setState(() {
          if (!_hasLoadedOnce) _hasLoadedOnce = true; // Ensure loading finishes
          if (!isRefresh) _isLoading = false;
          _isUpdating = false;
        });
      }
    }
  }

  void _playItem(BuildContext context, Map<String, dynamic> item) {
    HapticFeedback.lightImpact();
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final type = item['type'];
    final id = item['id'];
    if (type != null && id != null) {
      spotifyProvider.playContext(type: type, id: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use 'allItems' directly as it's already filtered and shuffled in _loadItems
    final validItems = allItems;

    // If loading for the first time ever, show placeholder
    if (_isLoading && !_hasLoadedOnce) {
      return _buildLoadingCarousel(context);
    }

    // If loaded but no items, show nothing
    if (!_isLoading && !_isUpdating && validItems.isEmpty && _hasLoadedOnce) {
      return const SizedBox.shrink(); // Or a placeholder message
    }

    // If loaded and has items (or is updating), show the carousel
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final carouselHeight = screenWidth > 900 ? 300.0 : 190.0;
        // Determine flex weights based on screen width
        final flexWeights = screenWidth > 900
            ? const [2, 7, 6, 5, 4, 3, 2] // Very wide screen weights
            : screenWidth > 600
            ? const [2, 6, 5, 4, 3, 2] // Wide screen weights
            : const [3, 6, 3, 2];      // Default weights

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: carouselHeight),
            child: Stack(
              children: [
                // Show carousel only if there are items or it's the initial load phase (handled above)
                 if (validItems.isNotEmpty)
                   CarouselView.weighted(
                     flexWeights: flexWeights, // Use dynamic weights based on screen width
                     shrinkExtent: 0,
                     itemSnapping: true,
                     onTap: (index) {
                       if (index >= 0 && index < validItems.length) {
                         _playItem(context, validItems[index]);
                       } else {
                         // print('Error: Invalid index ($index) tapped in CarouselView.');
                       }
                     },
                     children: validItems.map((item) {
                        final imageUrl = item['images'][0]['url'];
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest, // Use surfaceContainerHighest
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest, // Use surfaceContainerHighest
                                child: const Icon(Icons.error),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                   ),

                // Show overlay loading indicator only when updating after the first load
                if (_isUpdating)
                  Positioned.fill(
                    child: const Center(
                      // Use a smaller indicator for updates?
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // 构建加载中的轮播图占位
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