import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/spotify_provider.dart';
import '../providers/library_provider.dart';
import '../providers/local_database_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/library_section.dart';
import '../widgets/search_section.dart';
import '../services/insights_service.dart';

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

// Modify MyCarouselView to use LocalDatabaseProvider and InsightsService
class MyCarouselView extends StatefulWidget {
  const MyCarouselView({super.key});

  @override
  State<MyCarouselView> createState() => _MyCarouselViewState();
}

class _MyCarouselViewState extends State<MyCarouselView> {
  // State variables for insights
  bool _isLoadingInsights = false;
  Map<String, dynamic>? _insightsResult;
  String? _insightsError;
  bool _isInsightsExpanded = false; // State for expansion

  @override
  void initState() {
    super.initState();
    // Fetch initial data using LocalDatabaseProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
         Provider.of<LocalDatabaseProvider>(context, listen: false).fetchRecentContexts();
         _loadCachedInsights(); // 从缓存加载洞察数据
      }
    });
  }

  // 从缓存加载洞察数据的方法
  Future<void> _loadCachedInsights() async {
    try {
      final insightsService = InsightsService();
      final cachedInsights = await insightsService.getCachedInsights();
      
      if (cachedInsights != null && mounted) {
        setState(() {
          _insightsResult = cachedInsights;
          _isInsightsExpanded = true; // 展开显示缓存的洞察数据
        });
      }
    } catch (e) {
      print('Error loading cached insights: $e');
    }
  }

  // 复制文本到剪贴板并显示提示
  void _copyToClipboard(String text, String messageType) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      // 显示Snackbar提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$messageType 已复制到剪贴板'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  // Method to handle Generate Insights button press
  Future<void> _generateInsights() async {
    if (_isLoadingInsights) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isLoadingInsights = true;
      _insightsResult = null;
      _insightsError = null;
      _isInsightsExpanded = false; // Collapse previous results while loading
    });

    try {
      final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
      final insightsService = InsightsService();

      if (localDbProvider.recentContexts.isEmpty) {
         await localDbProvider.fetchRecentContexts(); 
      }
      
      final result = await insightsService.generateMusicInsights(localDbProvider.recentContexts);

      if (mounted) {
        setState(() {
          _insightsResult = result;
          _isLoadingInsights = false;
          _isInsightsExpanded = result != null; // Expand if we got a result
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _insightsError = 'Failed to generate insights: ${e.toString()}';
          _isLoadingInsights = false;
          _isInsightsExpanded = true; // Also expand to show the error
        });
        print('Error generating insights: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consume LocalDatabaseProvider
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context);
    // Get recent contexts from the provider
    final recentContexts = localDbProvider.recentContexts;

    // Use a simple loading check for carousel
    final isCarouselLoading = recentContexts.isEmpty && !localDbProvider.isLoading;

    if (isCarouselLoading) {
      return _buildLoadingCarousel(context); // Show loading placeholder for carousel
    }

    // Even if contexts load but are empty, show the button, but disable it?
    // Or hide the section? For now, let's show the button.
    // if (recentContexts.isEmpty) {
    //   return const SizedBox.shrink(); // Or show a message
    // }

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
          child: Column( // Wrap carousel, button, and results in a Column
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Important for Column within potential scroll view
            children: [
              // Only show carousel if there are contexts
              if (recentContexts.isNotEmpty)
                ConstrainedBox(
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
              
              // Show message if no recent contexts but button should be visible
              if (recentContexts.isEmpty && !isCarouselLoading)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Play some music to generate insights!',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),

              // Generate Insights Button和展开/收起按钮在同一行
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: recentContexts.isNotEmpty && !_isLoadingInsights ? _generateInsights : null,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(_isLoadingInsights ? 'Generating...' : 'Generate Insights'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                    // 只有在有结果或错误时才显示展开/收起按钮
                    if (_insightsResult != null || _insightsError != null)
                      IconButton(
                        icon: Icon(
                          _isInsightsExpanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        tooltip: _isInsightsExpanded ? '收起' : '展开',
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isInsightsExpanded = !_isInsightsExpanded;
                          });
                        },
                      ),
                  ],
                ),
              ),

              // Loading Indicator or Results/Error Section
              if (_isLoadingInsights || (_isInsightsExpanded && (_insightsError != null || _insightsResult != null)))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: _buildInsightsSection(context),
                ),
            ],
          ),
        );
      },
    );
  }

  // Widget to display insights loading, result, or error with expansion
  Widget _buildInsightsSection(BuildContext context) {
    if (_isLoadingInsights) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    
    // 直接显示内容，不使用卡片
    if (_insightsError != null) {
      return Text(
        _insightsError!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    } else if (_insightsResult != null) {
      final mood = _insightsResult!['mood_analysis'] as String?;
      final recommendations = (_insightsResult!['recommendations'] as List<dynamic>?)
          ?.map((rec) => rec as Map<String, dynamic>)
          .toList();

      // 返回空如果没有有效数据
      if (mood == null && (recommendations == null || recommendations.isEmpty)) {
        return Text('Could not generate insights from the provided history.', 
                   style: Theme.of(context).textTheme.bodyMedium);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mood != null) ...[
            Text(
              'Insights',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            // 将普通Text替换为支持长按复制的GestureDetector
            GestureDetector(
              onLongPress: () => _copyToClipboard(mood, 'Insights内容'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Text(
                  mood,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (recommendations != null && recommendations.isNotEmpty) ...[
            Text(
              'Inspirations',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recommendations.length,
              itemBuilder: (context, index) {
                final rec = recommendations[index];
                final artist = rec['artist'] as String? ?? 'Unknown Artist';
                final track = rec['track'] as String? ?? 'Unknown Track';
                final recommendationText = '$artist - $track';
                
                return ListTile(
                  leading: Icon(
                    Icons.music_note_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(track),
                  subtitle: Text(artist),
                  dense: true,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    // 构建搜索查询字符串 "艺术家名 - 歌曲名"
                    final searchQuery = recommendationText;
                    
                    // 获取SearchProvider并提交搜索
                    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
                    
                    // 更新搜索查询并提交搜索（这会激活搜索界面）
                    searchProvider.updateSearchQuery(searchQuery);
                    searchProvider.submitSearch(searchQuery);
                    
                    // 收起推荐面板
                    setState(() {
                      _isInsightsExpanded = false;
                    });
                  },
                  onLongPress: () => _copyToClipboard(recommendationText, '推荐歌曲'),
                );
              },
            ),
          ],
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
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