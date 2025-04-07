//search.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../widgets/materialui.dart' as custom_ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

class _SearchState extends State<Search> {
  bool showPlaylists = true;
  bool showAlbums = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isFirstLoad = true; // 标记是否为首次加载
  String _searchQuery = '';
  bool _isSearching = false;
  List<Map<String, dynamic>> _userPlaylists = [];
  List<Map<String, dynamic>> _userSavedAlbums = [];
  List<Map<String, dynamic>> _recentlyPlayed = [];
  Map<String, List<Map<String, dynamic>>> _searchResults = {};
  final ScrollController _scrollController = ScrollController();
  bool _wasAuthenticated = false; // Track previous auth state

  @override
  void initState() {
    super.initState();
    // Initial load is now handled by didChangeDependencies
    // _loadData(); 
    _scrollController.addListener(_scrollListener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final isAuthenticated = spotifyProvider.username != null;

    // Check if the user just logged in
    if (isAuthenticated && !_wasAuthenticated) {
      print("User logged in, refreshing Search page data...");
      _loadData(); // Load data on login
    } else if (!isAuthenticated && _wasAuthenticated) {
      // Optional: Clear data on logout if needed
      setState(() {
        _userPlaylists = [];
        _userSavedAlbums = [];
        _recentlyPlayed = [];
        _searchResults = {};
        _searchQuery = '';
        _isFirstLoad = true; // Reset first load flag on logout
      });
      print("User logged out, clearing Search page data.");
    }

    // Handle initial load if not logged in initially but becomes authenticated later
    // Or handle the very first load when the widget is built
    if (_isFirstLoad && isAuthenticated) {
       _loadData();
    }

    _wasAuthenticated = isAuthenticated; // Update the flag
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading && 
        !_isLoadingMore &&
        _searchQuery.isEmpty) {
      _loadMoreData();
    }
  }

  Future<void> _loadData() async {
    if (_isLoading || !mounted) return;
    
    // 如果不是首次加载，显示轻量级的加载指示器，而不是完全清空UI
    final bool isFirstLoad = _isFirstLoad;
    
    if (isFirstLoad) {
      setState(() => _isLoading = true);
    } else {
      // 仅显示轻量级的加载指示器，不重置现有数据
      setState(() => _isLoading = true);
    }
    
    try {
      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      
      // 并行请求数据以减少总加载时间
      final results = await Future.wait([
        spotifyProvider.getUserPlaylists(),
        spotifyProvider.getUserSavedAlbums(),
        spotifyProvider.getRecentlyPlayed(),
      ]);
      
      if (!mounted) return;
      
      setState(() {
        _userPlaylists = results[0];
        _userSavedAlbums = results[1];
        _recentlyPlayed = results[2];
        _isFirstLoad = false;
        _isLoading = false;
      });
    } catch (e) {
      print('加载数据失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载数据失败: $e'))
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty || !mounted) return;
    
    // 保留原有状态，仅更新搜索状态
    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });
    
    try {
      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      final results = await spotifyProvider.searchItems(query);
      
      if (!mounted) return;
      
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      print('搜索失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e'))
        );
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoadingMore) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      
      // 计算当前偏移量
      final playlistOffset = _userPlaylists.length;
      final albumOffset = _userSavedAlbums.length;
      
      // 加载更多数据
      if (showPlaylists) {
        final morePlaylists = await spotifyProvider.getUserPlaylists(offset: playlistOffset);
        if (mounted) {
          setState(() {
            _userPlaylists.addAll(morePlaylists);
          });
        }
      }
      
      if (showAlbums) {
        final moreAlbums = await spotifyProvider.getUserSavedAlbums(offset: albumOffset);
        if (mounted) {
          setState(() {
            _userSavedAlbums.addAll(moreAlbums);
          });
        }
      }
    } catch (e) {
      print('加载更多数据失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多数据失败: $e'))
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SpotifyProvider>(
      builder: (context, spotifyProvider, child) {
        // 根据当前状态决定显示的数据
        final List<Map<String, dynamic>> playlists = _searchQuery.isNotEmpty && _searchResults.containsKey('playlists')
            ? _searchResults['playlists']!
            : showPlaylists ? _userPlaylists : [];
            
        final List<Map<String, dynamic>> albums = _searchQuery.isNotEmpty && _searchResults.containsKey('albums')
            ? _searchResults['albums']!
            : showAlbums ? _userSavedAlbums : [];

        // 如果在搜索中，需要显示更多的结果类别
        final bool showTracks = _searchQuery.isNotEmpty && _searchResults.containsKey('tracks');
        final bool showArtists = _searchQuery.isNotEmpty && _searchResults.containsKey('artists');
        
        final List<Map<String, dynamic>> tracks = showTracks ? _searchResults['tracks']! : [];
        final List<Map<String, dynamic>> artists = showArtists ? _searchResults['artists']! : [];
        
        // 组合所有要显示的项目
        final items = [
          if (showPlaylists) 
            ...playlists.where((p) {
              final hasImage = p['images'] != null && p['images'].isNotEmpty && p['images'][0]['url'] != null;
              return hasImage;
            }).map((p) => ({
              ...p, 
              'type': 'playlist',
            })),
          if (showAlbums) 
            ...albums.where((a) {
              final hasImage = a['images'] != null && a['images'].isNotEmpty && a['images'][0]['url'] != null;
              return hasImage;
            }).map((a) => ({
              ...a, 
              'type': 'album',
            })),
          if (showTracks)
            ...tracks.where((t) {
              final hasImage = t['images'] != null && t['images'].isNotEmpty && t['images'][0]['url'] != null;
              return hasImage;
            }).map((t) => ({
              ...t,
              'type': 'track',
            })),
          if (showArtists)
            ...artists.where((a) {
              final hasImage = a['images'] != null && a['images'].isNotEmpty && a['images'][0]['url'] != null;
              return hasImage;
            }).map((a) => ({
              ...a,
              'type': 'artist',
            })),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final isWideScreen = screenWidth > 600;
            final maxContentWidth = isWideScreen ? 1200.0 : screenWidth;
            final gridCrossAxisCount = switch (screenWidth) {
              > 1200 => 6,
              > 900 => 5,
              > 600 => 4,
              _ => 3,
            };

            return RefreshIndicator(
              onRefresh: _loadData,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Stack(
                    children: [
                      ListView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: SearchBar(
                              hintText: 'Search songs, albums, artists...',
                              leading: const Icon(Icons.search),
                              trailing: _searchQuery.isNotEmpty
                                ? [
                                    IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                          _searchResults = {};
                                        });
                                      },
                                      tooltip: 'Clear search',
                                    ),
                                  ]
                                : null,
                              elevation: MaterialStatePropertyAll(0),
                              backgroundColor: MaterialStatePropertyAll(Colors.transparent),
                              side: MaterialStatePropertyAll(
                                BorderSide(
                                  color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                ),
                              ),
                              padding: const MaterialStatePropertyAll<EdgeInsets>(
                                EdgeInsets.symmetric(horizontal: 16.0),
                              ),
                              onSubmitted: (query) {
                                _performSearch(query);
                              },
                            ),
                          ),
                          
                          // 仅在未搜索状态显示轮播图
                          if (_searchQuery.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: MyCarouselView(),
                            ),
                          
                          // 搜索结果标题栏，添加返回按钮
                          if (_searchQuery.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    onPressed: () {
                                      setState(() {
                                        _searchQuery = '';
                                        _searchResults = {};
                                      });
                                    },
                                    tooltip: 'Back to library',
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Center(
                                      child: custom_ui.IconHeader(
                                        icon: Icons.search,
                                        text: "SEARCH RESULTS",
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          // 在非搜索状态下显示"YOUR LIBRARY"标题
                          if (_searchQuery.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: custom_ui.IconHeader(
                                  icon: Icons.history,
                                  text: "YOUR LIBRARY",
                                ),
                              ),
                            ),
                          
                          // 过滤器 Chips
                          if (_searchQuery.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  FilterChip(
                                    selected: showPlaylists,
                                    label: const Text('Playlists'),
                                    onSelected: (bool selected) {
                                      setState(() {
                                        showPlaylists = selected;
                                      });
                                    },
                                  ),
                                  FilterChip(
                                    selected: showAlbums,
                                    label: const Text('Albums'),
                                    onSelected: (bool selected) {
                                      setState(() {
                                        showAlbums = selected;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          
                          const SizedBox(height: 24),
                          
                          // 显示加载中
                          if (_isLoading && _isFirstLoad)
                            const Center(
                              child: CircularProgressIndicator(),
                            ),
                          
                          // 显示搜索结果或库内容
                          if ((!_isLoading || !_isFirstLoad) && !_isSearching && items.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridCrossAxisCount,
                                  childAspectRatio: 0.75,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return GestureDetector(
                                    onTap: () {
                                      final type = item['type'];
                                      final id = item['id'];
                                      if (type != null && id != null) {
                                        spotifyProvider.playContext(type: type, id: id);
                                      }
                                    },
                                    onLongPress: () => _openInSpotify(item),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: AspectRatio(
                                            aspectRatio: 1,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: CachedNetworkImage(
                                                imageUrl: item['images'][0]['url'],
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Container(
                                                  color: Theme.of(context).colorScheme.surfaceVariant,
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
                                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                                  child: const Icon(Icons.error),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item['name'],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        Text(
                                          _getItemSubtitle(item),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          
                          // 无内容显示
                          if ((!_isLoading || !_isFirstLoad) && !_isSearching && items.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No items found'),
                              ),
                            ),
                            
                          // 加载更多指示器
                          if (_isLoadingMore && !_searchQuery.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                        ],
                      ),
                      
                      // 非首次加载时使用覆盖式加载指示器
                      if (_isLoading && !_isFirstLoad)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.1),
                            child: const Center(
                              child: RefreshProgressIndicator(),
                            ),
                          ),
                        ),
                        
                      // 搜索中指示器
                      if (_isSearching)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.1),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Searching...'),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  // 根据项目类型获取副标题
  String _getItemSubtitle(Map<String, dynamic> item) {
    switch (item['type']) {
      case 'playlist':
        return 'Playlist';
      case 'album':
        if (item['artists'] != null && item['artists'].isNotEmpty) {
          return 'Album • ${item['artists'][0]['name']}';
        }
        return 'Album';
      case 'track':
        if (item['artists'] != null && item['artists'].isNotEmpty) {
          return 'Song • ${item['artists'][0]['name']}';
        }
        return 'Song';
      case 'artist':
        return 'Artist';
      default:
        return item['type'] ?? '';
    }
  }
  
  // 打开 Spotify 应用或网页
  Future<void> _openInSpotify(Map<String, dynamic> item) async {
    String? webUrl;
    String? spotifyUri;
    
    // 先尝试获取URI
    if (item['uri'] != null && item['uri'].toString().startsWith('spotify:')) {
      // 直接使用原始URI格式，如 spotify:album:37vIh6I03bNlWKlVMjGRK3
      spotifyUri = item['uri'].toString();
      
      // 从URI构建web URL
      final segments = spotifyUri.split(':');
      if (segments.length >= 3) {
        final type = segments[1]; // album, playlist, artist, track
        final id = segments[2];
        webUrl = 'https://open.spotify.com/$type/$id';
      }
    } 
    // 尝试构建URI
    else if (item['type'] != null && item['id'] != null) {
      final type = item['type'].toString();
      final id = item['id'].toString();
      spotifyUri = 'spotify:$type:$id';
      webUrl = 'https://open.spotify.com/$type/$id';
    }
    // 后备方案：尝试从external_urls
    else if (item['external_urls'] != null && item['external_urls']['spotify'] != null) {
      webUrl = item['external_urls']['spotify'].toString();
      
      // 尝试从URL创建URI
      if (webUrl.contains('open.spotify.com/')) {
        final path = webUrl.split('open.spotify.com/')[1].split('?')[0];
        final segments = path.split('/');
        if (segments.length >= 2) {
          spotifyUri = 'spotify:${segments[0]}:${segments[1]}';
        }
      }
    }
    
    if (spotifyUri == null && webUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法构建Spotify链接'))
      );
      return;
    }
    
    try {
      // 先尝试使用URI启动Spotify应用
      if (spotifyUri != null) {
        final uri = Uri.parse(spotifyUri);
        print('尝试打开Spotify应用：$uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return; // 成功打开应用后直接返回
        }
      }
      
      // 如果无法打开应用，尝试打开网页
      if (webUrl != null) {
        final uri = Uri.parse(webUrl);
        print('尝试打开网页链接：$uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      
      // 两种方式都失败
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开Spotify'))
      );
    } catch (e) {
      print('打开Spotify出错: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开Spotify失败: $e'))
      );
    }
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
  bool _isLoading = false;
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _loadInitialItems();
  }

  void _loadInitialItems() {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    
    spotifyProvider.getRecentlyPlayed().then((recentItems) {
      if (!mounted) return;
      setState(() {
        allItems = List.from(recentItems);
        if (allItems.isNotEmpty) {
          allItems.shuffle();
        }
        _isLoading = false;
        _hasLoadedOnce = true;
      });
    }).catchError((error) {
      if (!mounted) return;
      print('加载轮播图数据失败: $error');
      setState(() {
        _isLoading = false;
        _hasLoadedOnce = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final validItems = allItems.where((item) {
      final hasImage = item['images'] != null && item['images'].isNotEmpty && item['images'][0]['url'] != null;
      return hasImage;
    }).toList();

    // 如果在加载中且从未加载过，显示占位轮播图
    if (_isLoading && !_hasLoadedOnce) {
      return _buildLoadingCarousel(context);
    }
    
    // 如果加载完成但没有有效项目，返回空内容
    if (validItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final carouselHeight = screenWidth > 900 ? 300.0 : 190.0;
        final itemExtent = screenWidth > 900 ? 300.0 : 190.0;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: carouselHeight),
            child: Stack(
              children: [
                custom_ui.CarouselView(
                  itemExtent: itemExtent,
                  shrinkExtent: 10,
                  itemSnapping: true,
                  children: validItems.map((item) {
                    final imageUrl = item['images'][0]['url'];
                    final type = item['type'];
                    final id = item['id'];

                    return GestureDetector(
                      onTap: () {
                        if (type != null && id != null) {
                          final spotifyProvider = Provider.of<SpotifyProvider>(
                            context, 
                            listen: false
                          );
                          spotifyProvider.playContext(type: type, id: id);
                        }
                      },
                      onLongPress: () => _openInSpotify(item),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Theme.of(context).colorScheme.surfaceVariant,
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
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              child: const Icon(Icons.error),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                
                // 显示正在加载中的覆盖层
                if (_isLoading && _hasLoadedOnce)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.1),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
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
                    child: Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
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
  
  // 打开 Spotify 应用或网页
  Future<void> _openInSpotify(Map<String, dynamic> item) async {
    String? webUrl;
    String? spotifyUri;
    
    // 先尝试获取URI
    if (item['uri'] != null && item['uri'].toString().startsWith('spotify:')) {
      // 直接使用原始URI格式，如 spotify:album:37vIh6I03bNlWKlVMjGRK3
      spotifyUri = item['uri'].toString();
      
      // 从URI构建web URL
      final segments = spotifyUri.split(':');
      if (segments.length >= 3) {
        final type = segments[1]; // album, playlist, artist, track
        final id = segments[2];
        webUrl = 'https://open.spotify.com/$type/$id';
      }
    } 
    // 尝试构建URI
    else if (item['type'] != null && item['id'] != null) {
      final type = item['type'].toString();
      final id = item['id'].toString();
      spotifyUri = 'spotify:$type:$id';
      webUrl = 'https://open.spotify.com/$type/$id';
    }
    // 后备方案：尝试从external_urls
    else if (item['external_urls'] != null && item['external_urls']['spotify'] != null) {
      webUrl = item['external_urls']['spotify'].toString();
      
      // 尝试从URL创建URI
      if (webUrl.contains('open.spotify.com/')) {
        final path = webUrl.split('open.spotify.com/')[1].split('?')[0];
        final segments = path.split('/');
        if (segments.length >= 2) {
          spotifyUri = 'spotify:${segments[0]}:${segments[1]}';
        }
      }
    }
    
    if (spotifyUri == null && webUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法构建Spotify链接'))
      );
      return;
    }
    
    try {
      // 先尝试使用URI启动Spotify应用
      if (spotifyUri != null) {
        final uri = Uri.parse(spotifyUri);
        print('尝试打开Spotify应用：$uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return; // 成功打开应用后直接返回
        }
      }
      
      // 如果无法打开应用，尝试打开网页
      if (webUrl != null) {
        final uri = Uri.parse(webUrl);
        print('尝试打开网页链接：$uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      
      // 两种方式都失败
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开Spotify'))
      );
    } catch (e) {
      print('打开Spotify出错: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开Spotify失败: $e'))
      );
    }
  }
}