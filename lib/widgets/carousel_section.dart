import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/spotify_provider.dart';
import '../widgets/materialui.dart' as custom_ui;
import 'package:collection/collection.dart';

class CarouselSection extends StatefulWidget {
  const CarouselSection({Key? key}) : super(key: key);

  @override
  CarouselSectionState createState() => CarouselSectionState();
}

class CarouselSectionState extends State<CarouselSection> {
  List<Map<String, dynamic>> _items = [];
  Set<String> _currentDisplayedItemUris = {};
  bool _isLoading = false;
  bool _isUpdating = false;
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> refreshItems() async {
    if (!mounted || _isLoading || _isUpdating) return;
    _loadItems(isRefresh: true);
  }

  Future<void> _loadItems({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (!isRefresh) {
        _isLoading = true;
      } else {
        _isUpdating = true;
      }
    });

    try {
      if (!mounted) return;
      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      final newItemsRaw = await spotifyProvider.getRecentlyPlayed();
      
      if (!mounted) return;

      final newValidItems = newItemsRaw.where((item) {
        final hasImage = item['images'] != null && 
                         item['images'].isNotEmpty && 
                         item['images'][0]['url'] != null;
        return hasImage;
      }).toList();

      final newItemUris = newValidItems.map((item) => item['uri'] as String).toSet();

      if (!const SetEquality().equals(newItemUris, _currentDisplayedItemUris)) {
        if (newValidItems.isNotEmpty) {
          if (!mounted) return;
          final imageFutures = newValidItems.map((item) {
            final imageUrl = item['images'][0]['url'];
            if (imageUrl != null) {
              return precacheImage(CachedNetworkImageProvider(imageUrl), context);
            }
            return Future.value();
          }).toList();

          await Future.wait(imageFutures);
          if (!mounted) return;
        }

        setState(() {
          _items = List.from(newValidItems);
          if (_items.isNotEmpty) {
            _items.shuffle();
          }
          _currentDisplayedItemUris = newItemUris;
          _isLoading = false;
          _isUpdating = false;
          _hasLoadedOnce = true;
        });
      } else {
        setState(() {
          _isLoading = false;
          _isUpdating = false;
          _hasLoadedOnce = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isUpdating = false;
        _hasLoadedOnce = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && !_hasLoadedOnce) {
      return _buildLoadingCarousel(context);
    }

    if (!_isLoading && !_isUpdating && _items.isEmpty && _hasLoadedOnce) {
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
                if (_items.isNotEmpty)
                  custom_ui.CarouselView(
                    itemExtent: itemExtent,
                    shrinkExtent: 10,
                    itemSnapping: true,
                    children: _items.map((item) {
                      final imageUrl = item['images'][0]['url'];
                      final type = item['type'];
                      final id = item['id'];

                      return GestureDetector(
                        key: ValueKey(item['id']),
                        onTap: () {
                          if (type != null && id != null) {
                            if (!mounted) return;
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

                if (_isUpdating)
                  Positioned.fill(
                    child: Container(
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

  Future<void> _openInSpotify(Map<String, dynamic> item) async {
    String? webUrl;
    String? spotifyUri;
    
    if (item['uri'] != null && item['uri'].toString().startsWith('spotify:')) {
      spotifyUri = item['uri'].toString();
      
      final segments = spotifyUri.split(':');
      if (segments.length >= 3) {
        final type = segments[1];
        final id = segments[2];
        webUrl = 'https://open.spotify.com/$type/$id';
      }
    } 
    else if (item['type'] != null && item['id'] != null) {
      final type = item['type'].toString();
      final id = item['id'].toString();
      spotifyUri = 'spotify:$type:$id';
      webUrl = 'https://open.spotify.com/$type/$id';
    }
    else if (item['external_urls'] != null && item['external_urls']['spotify'] != null) {
      webUrl = item['external_urls']['spotify'].toString();
      
      if (webUrl.contains('open.spotify.com/')) {
        final path = webUrl.split('open.spotify.com/')[1].split('?')[0];
        final segments = path.split('/');
        if (segments.length >= 2) {
          spotifyUri = 'spotify:${segments[0]}:${segments[1]}';
        }
      }
    }
    
    if (!mounted) return;
    if (spotifyUri == null && webUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot create Spotify link'))
      );
      return;
    }
    
    try {
      if (spotifyUri != null) {
        final uri = Uri.parse(spotifyUri);
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return;
        }
      }
      
      if (webUrl != null) {
        final uri = Uri.parse(webUrl);
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open Spotify'))
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open Spotify: $e'))
      );
    }
  }
} 