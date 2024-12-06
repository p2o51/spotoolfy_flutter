//search.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../widgets/materialui.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

class _SearchState extends State<Search> {
  bool showPlaylists = true;
  bool showAlbums = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<SpotifyProvider>(
      builder: (context, provider, child) {
        final items = [
          if (showPlaylists) ...provider.recentPlaylists.map((p) => ({...p, 'type': 'playlist'})),
          if (showAlbums) ...provider.recentAlbums.map((a) => ({...a, 'type': 'album'})),
        ];

        return RefreshIndicator(
          onRefresh: () async {
            await provider.refreshRecentlyPlayed();
          },
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SearchBar(
                  hintText: 'Search songs, albums, artists...',
                  leading: const Icon(Icons.search),
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
                  onTap: () {
                    // TODO: 处理搜索点击事件
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: MyCarouselView(),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: IconHeader(
                    icon: Icons.history,
                    text: "RECENTLY PLAYED",
                  ),
                ),
              ),
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
              if (items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                item['images'][0]['url'],
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            item['type'] == 'playlist' ? 'Playlist' : 'Album',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              if (items.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No recently played items'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class MyCarouselView extends StatefulWidget {
  const MyCarouselView({super.key});

  @override
  State<MyCarouselView> createState() => _MyCarouselViewState();
}

class _MyCarouselViewState extends State<MyCarouselView> {
  List<Map<String, dynamic>> allItems = [];
  List<Map<String, dynamic>> _newItems = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialItems();
    // 静默更新数据
    _refreshItemsSilently();
  }

  void _loadInitialItems() {
    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    setState(() {
      allItems = [
        ...provider.recentAlbums,
        ...provider.recentPlaylists,
      ];
      if (allItems.isNotEmpty) {
        allItems.shuffle();
      }
    });
  }

  Future<void> _refreshItemsSilently() async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      final provider = Provider.of<SpotifyProvider>(context, listen: false);
      await provider.refreshRecentlyPlayed();
      
      if (!mounted) return;

      // 准备新数据但不立即显示
      _newItems = [
        ...provider.recentAlbums,
        ...provider.recentPlaylists,
      ];

      // 只有当有新数据且与当前数据不同时才更新
      if (_newItems.isNotEmpty && _newItems.length != allItems.length) {
        _newItems.shuffle();
        setState(() {
          allItems = _newItems;
        });
      }
    } finally {
      _isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (allItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: CarouselView(
          itemExtent: 190,
          shrinkExtent: 10,
          itemSnapping: true,
          children: allItems.map((item) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  item['images'][0]['url'],
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}