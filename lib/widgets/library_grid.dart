import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/spotify_provider.dart';
import 'package:flutter/services.dart';

class LibraryGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool isLoadingMore;
  final Function? onItemTap;
  final Function? onItemLongPress;
  final int gridCrossAxisCount; // Pass cross axis count from parent
  
  const LibraryGrid({
    super.key,
    required this.items,
    this.isLoadingMore = false,
    this.onItemTap,
    this.onItemLongPress,
    required this.gridCrossAxisCount,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !isLoadingMore) {
      // Return a sliver message if items are empty and not just loading more
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No items found'),
          ),
        ),
      );
    }

    // Return the grid as a SliverGrid
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
           // Build grid item
           final item = items[index];
           return _LibraryGridItem(
             key: ValueKey(item['id']), // Add a key for better performance
             item: item,
             onTap: onItemTap != null 
                 ? () => onItemTap!(item) 
                 : () => _playItem(context, item),
             onLongPress: onItemLongPress != null 
                 ? () => onItemLongPress!(item) 
                 : () => _openInSpotify(context, item),
           );
        },
        childCount: items.length,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridCrossAxisCount,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
    );

    // The loading indicator will be handled in the parent CustomScrollView
  }

  void _playItem(BuildContext context, Map<String, dynamic> item) {
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final type = item['type'];
    final id = item['id'];
    if (type != null && id != null) {
      spotifyProvider.playContext(type: type, id: id);
    }
  }

  Future<void> _openInSpotify(BuildContext context, Map<String, dynamic> item) async {
    String? webUrl;
    String? spotifyUri;
    
    // Try to get URI
    if (item['uri'] != null && item['uri'].toString().startsWith('spotify:')) {
      spotifyUri = item['uri'].toString();
      
      // Build web URL from URI
      final segments = spotifyUri.split(':');
      if (segments.length >= 3) {
        final type = segments[1]; // album, playlist, artist, track
        final id = segments[2];
        webUrl = 'https://open.spotify.com/$type/$id';
      }
    } 
    // Try to build URI
    else if (item['type'] != null && item['id'] != null) {
      final type = item['type'].toString();
      final id = item['id'].toString();
      spotifyUri = 'spotify:$type:$id';
      webUrl = 'https://open.spotify.com/$type/$id';
    }
    // Fallback: try from external_urls
    else if (item['external_urls'] != null && item['external_urls']['spotify'] != null) {
      webUrl = item['external_urls']['spotify'].toString();
      
      // Try to create URI from URL
      if (webUrl.contains('open.spotify.com/')) {
        final path = webUrl.split('open.spotify.com/')[1].split('?')[0];
        final segments = path.split('/');
        if (segments.length >= 2) {
          spotifyUri = 'spotify:${segments[0]}:${segments[1]}';
        }
      }
    }
    
    if (spotifyUri == null && webUrl == null) {
      if (!context.mounted) return; // Check context before using
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot create Spotify link'))
      );
      return;
    }
    
    try {
      // First try to launch Spotify app
      if (spotifyUri != null) {
        final uri = Uri.parse(spotifyUri);
        // print('Trying to open Spotify app: $uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return;
        }
      }
      
      // If can't open app, try web
      if (webUrl != null) {
        final uri = Uri.parse(webUrl);
        // print('Trying to open web link: $uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      
      // Both methods failed
      if (!context.mounted) return; // Check context before using
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open Spotify'))
      );
    } catch (e) {
      // print('Error opening Spotify: $e');
      if (!context.mounted) return; // Check context before using
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open Spotify: $e'))
      );
    }
  }
}

class _LibraryGridItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LibraryGridItem({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: key, // Use the key provided
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onLongPress();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: item['images'][0]['url'],
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.error),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item['name'],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            _getItemSubtitle(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((255 * 0.7).round()),
            ),
          ),
        ],
      ),
    );
  }

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
}

// Skeleton loading widget for the grid
class LibraryGridSkeleton extends StatelessWidget {
  final int itemCount;
  final int gridCrossAxisCount; // Add cross axis count here too

  const LibraryGridSkeleton({
    super.key,
    this.itemCount = 12,
    required this.gridCrossAxisCount,
  });

  @override
  Widget build(BuildContext context) {
     // Return a sliver grid skeleton
     return SliverGrid(
       delegate: SliverChildBuilderDelegate(
         (context, index) => _buildSkeletonItem(context),
         childCount: itemCount,
       ),
       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
         crossAxisCount: gridCrossAxisCount,
         childAspectRatio: 0.75,
         crossAxisSpacing: 16,
         mainAxisSpacing: 16,
       ),
     );
  }

  Widget _buildSkeletonItem(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 14,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 100,
          height: 12,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.7).round()),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
} 