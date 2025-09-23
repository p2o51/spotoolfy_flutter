import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/spotify_provider.dart';
import '../widgets/library_grid.dart';
import '../widgets/materialui.dart' as custom_ui;
import '../widgets/materialui.dart'; // Import WavyDivider
import '../pages/library.dart'; // Add import for MyCarouselView
import '../pages/album_page.dart';
import '../pages/playlist_page.dart';
import 'package:flutter/services.dart'; // 新增导入
import '../l10n/app_localizations.dart';

class LibrarySection extends StatefulWidget {
  // Optional controller to allow parent widget to initiate refresh
  final Function(Function() refreshCallback)? registerRefreshCallback;
  final Function(VoidCallback)?
      registerScrollToTopCallback; // For parent scroll

  const LibrarySection({
    super.key,
    this.registerRefreshCallback,
    this.registerScrollToTopCallback,
  });

  @override
  State<LibrarySection> createState() => _LibrarySectionState();
}

class _LibrarySectionState extends State<LibrarySection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);

    // Register callbacks from parent
    if (widget.registerRefreshCallback != null) {
      widget.registerRefreshCallback!(_refreshData);
    }
    if (widget.registerScrollToTopCallback != null) {
      widget.registerScrollToTopCallback!(_scrollToTop);
    }

    // Trigger initial load if needed after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use listen: false as we only need to trigger the load, not react to changes here
      final libraryProvider =
          Provider.of<LibraryProvider>(context, listen: false);
      final spotifyProvider =
          Provider.of<SpotifyProvider>(context, listen: false);

      // 只有在用户已登录且是首次加载时才加载数据
      if (libraryProvider.isFirstLoad &&
          !libraryProvider.isLoading &&
          spotifyProvider.username != null) {
        // Use _refreshData to ensure consistency with pull-to-refresh logic
        // (although calling libraryProvider.loadData() directly would also work)
        _refreshData();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final libraryProvider =
          Provider.of<LibraryProvider>(context, listen: false);
      if (!libraryProvider.isLoading && !libraryProvider.isLoadingMore) {
        libraryProvider.loadMoreData();
      }
    }
  }

  Future<void> _refreshData() async {
    // Refresh both library provider and carousel
    final libraryProvider =
        Provider.of<LibraryProvider>(context, listen: false);
    await libraryProvider.loadData();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleLibraryItemTap(BuildContext context, Map<String, dynamic> item) {
    final type = item['type'] as String?;
    final id = item['id'] as String?;

    if (type == 'album' && id != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AlbumPage(albumId: id),
        ),
      );
      return;
    }

    if (type == 'playlist' && id != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistPage(playlistId: id),
        ),
      );
      return;
    }

    Provider.of<LibraryProvider>(context, listen: false).playItem(item);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LibraryProvider, SpotifyProvider>(
      builder: (context, libraryProvider, spotifyProvider, child) {
        // Check if user is authenticated
        if (spotifyProvider.username == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.login,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Please Login',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login to Spotify to view your library',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        // Calculate grid cross axis count here
        final screenWidth = MediaQuery.of(context).size.width;
        final gridCrossAxisCount = switch (screenWidth) {
          > 900 => 6, // 5 columns for screens wider than 900px
          > 600 => 5,
          _ => 3,
        };

        return CustomScrollView(
          controller: _scrollController,
          slivers: [
              // Remove the SearchBar placeholder
              // SliverToBoxAdapter(child: SizedBox(height: 0)),

              // Carousel section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: const MyCarouselView(),
                ),
              ),

              // Insert WavyDivider here
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0), // Added horizontal padding
                  child: WavyDivider(
                    height: 10,
                    waveHeight: 3,
                    waveFrequency: 0.03,
                    // Color will default to theme primary color
                  ),
                ),
              ),

              // "YOUR LIBRARY" header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: custom_ui.IconHeader(
                      icon: Icons.library_music,
                      text: AppLocalizations.of(context)!.yourLibrary,
                    ),
                  ),
                ),
              ),
              // Filter chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        selected: libraryProvider.showPlaylists,
                        label: Text(AppLocalizations.of(context)!.playlistsTab),
                        onSelected: (bool selected) {
                          HapticFeedback.lightImpact();
                          libraryProvider.setFilters(showPlaylists: selected);
                        },
                      ),
                      FilterChip(
                        selected: libraryProvider.showAlbums,
                        label: Text(AppLocalizations.of(context)!.albumsTab),
                        onSelected: (bool selected) {
                          HapticFeedback.lightImpact();
                          libraryProvider.setFilters(showAlbums: selected);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Add SizedBox for spacing below filter chips
              const SliverToBoxAdapter(
                child: SizedBox(height: 10.0), // Adjust height as needed
              ),

              // Add SliverPadding around the grid and loading states
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: _buildContentSliver(
                    context, libraryProvider, gridCrossAxisCount),
              ),
            ],
          );
      },
    );
  }

  // Helper method to build the main content sliver
  Widget _buildContentSliver(BuildContext context,
      LibraryProvider libraryProvider, int gridCrossAxisCount) {
    if (libraryProvider.isLoading && libraryProvider.isFirstLoad) {
      // Show skeleton grid during first load
      return LibraryGridSkeleton(gridCrossAxisCount: gridCrossAxisCount);
    } else if (libraryProvider.errorMessage != null) {
      // Show error message
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.errorLoadingLibrary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  libraryProvider.errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _refreshData,
                  child: Text(AppLocalizations.of(context)!.tryAgainButton),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Show the actual grid
      return SliverMainAxisGroup(
        slivers: [
          LibraryGrid(
            items: libraryProvider.filteredItems,
            gridCrossAxisCount: gridCrossAxisCount,
            onItemTap: (item) => _handleLibraryItemTap(context, item),
          ),
          // Show loading indicator for loading more at the bottom
          if (libraryProvider.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          // Show overlay loading indicator for non-first load
          // This might need rethinking, overlaying on a sliver is tricky
          // if (libraryProvider.isLoading && !libraryProvider.isFirstLoad)
          //   SliverFillRemaining(
          //     child: Container(
          //       color: Colors.black.withOpacity(0.1),
          //       child: const Center(child: RefreshProgressIndicator()),
          //     ),
          //   ),
        ],
      );
    }
  }
}
