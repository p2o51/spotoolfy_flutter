import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../widgets/library_grid.dart';
import '../widgets/materialui.dart' as custom_ui;
import '../pages/library.dart'; // Add import for MyCarouselView
import 'package:flutter/services.dart'; // 新增导入

class LibrarySection extends StatefulWidget {
  // Optional controller to allow parent widget to initiate refresh
  final Function(Function() refreshCallback)? registerRefreshCallback;
  final Function(VoidCallback)? registerScrollToTopCallback; // For parent scroll
  
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
      final libraryProvider = Provider.of<LibraryProvider>(context, listen: false);
      // Check if it's the first load and not already loading
      if (libraryProvider.isFirstLoad && !libraryProvider.isLoading) {
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
      final libraryProvider = Provider.of<LibraryProvider>(context, listen: false);
      if (!libraryProvider.isLoading && !libraryProvider.isLoadingMore) {
        libraryProvider.loadMoreData();
      }
    }
  }
  
  Future<void> _refreshData() async {
    HapticFeedback.mediumImpact();
    // Refresh both library provider and carousel
    final libraryProvider = Provider.of<LibraryProvider>(context, listen: false);
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

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, libraryProvider, child) {
         // Calculate grid cross axis count here
         final screenWidth = MediaQuery.of(context).size.width;
         final gridCrossAxisCount = switch (screenWidth) {
           > 900 => 6, // 5 columns for screens wider than 900px
           > 600 => 5,
           _ => 3,
         };
         
        return RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
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
              
              // "YOUR LIBRARY" header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: custom_ui.IconHeader(
                      icon: Icons.library_music,
                      text: "YOUR LIBRARY",
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
                        label: const Text('Playlists'),
                        onSelected: (bool selected) {
                          HapticFeedback.lightImpact();
                          libraryProvider.setFilters(showPlaylists: selected);
                        },
                      ),
                      FilterChip(
                        selected: libraryProvider.showAlbums,
                        label: const Text('Albums'),
                        onSelected: (bool selected) {
                          HapticFeedback.lightImpact();
                          libraryProvider.setFilters(showAlbums: selected);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SliverToBoxAdapter(
                child: SizedBox(height: 24),
              ),
              
              // Add SliverPadding around the grid and loading states
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: _buildContentSliver(context, libraryProvider, gridCrossAxisCount),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper method to build the main content sliver
  Widget _buildContentSliver(BuildContext context, LibraryProvider libraryProvider, int gridCrossAxisCount) {
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
                  'Error loading library',
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
                  child: const Text('Try Again'),
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
            onItemTap: (item) => libraryProvider.playItem(item),
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