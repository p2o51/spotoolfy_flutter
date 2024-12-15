//search.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/firestore_provider.dart';
import '../widgets/materialui.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

class _SearchState extends State<Search> {
  bool showPlaylists = true;
  bool showAlbums = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final firestoreProvider = Provider.of<FirestoreProvider>(context, listen: false);
      await firestoreProvider.fetchRecentPlayContexts();
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpotifyProvider, FirestoreProvider>(
      builder: (context, spotifyProvider, firestoreProvider, child) {
        final recentContexts = firestoreProvider.recentPlayContexts ?? [];

        final playlists = recentContexts
            .where((context) => context['type'] == 'playlist')
            .toList();
            
        final albums = recentContexts
            .where((context) => context['type'] == 'album')
            .toList();

        final items = [
          if (showPlaylists) 
            ...playlists.where((p) {
              final hasImage = p['images']?[0]?['url'] != null || 
                              p['context']?['images']?[0]?['url'] != null;
              return hasImage;
            }).map((p) => ({
              ...p, 
              'type': 'playlist',
              'images': p['images'] ?? p['context']?['images'],
              'name': p['name'] ?? p['context']?['name'] ?? 'Unknown Playlist',
            })),
          if (showAlbums) 
            ...albums.where((a) {
              final hasImage = a['images']?[0]?['url'] != null || 
                              a['context']?['images']?[0]?['url'] != null;
              return hasImage;
            }).map((a) => ({
              ...a, 
              'type': 'album',
              'images': a['images'] ?? a['context']?['images'],
              'name': a['name'] ?? a['context']?['name'] ?? 'Unknown Album',
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
                                  final id = item['id'] ?? item['context']?['uri']?.split(':').last;
                                  if (type != null && id != null) {
                                    spotifyProvider.playContext(type: type, id: id);
                                  }
                                },
                                child: Column(
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
                                ),
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
                ),
              ),
            );
          },
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialItems();
  }

  void _loadInitialItems() {
    if (!mounted) return;
    final firestoreProvider = Provider.of<FirestoreProvider>(context, listen: false);
    final recentContexts = firestoreProvider.recentPlayContexts ?? [];
    
    setState(() {
      allItems = List.from(recentContexts);
      if (allItems.isNotEmpty) {
        allItems.shuffle();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final validItems = allItems.where((item) {
      final hasImage = item['images']?[0]?['url'] != null || 
                      item['context']?['images']?[0]?['url'] != null;
      return hasImage;
    }).toList();

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
            child: CarouselView(
              itemExtent: itemExtent,
              shrinkExtent: 10,
              itemSnapping: true,
              children: validItems.map((item) {
                final imageUrl = item['images']?[0]?['url'] ?? 
                               item['context']?['images']?[0]?['url'];
                final type = item['type'];
                final id = item['id'] ?? item['context']?['uri']?.split(':').last;

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
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
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
}