import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';

class QueueDisplay extends StatelessWidget {
  const QueueDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    final spotifyProvider = Provider.of<SpotifyProvider>(context);
    final currentQueue = spotifyProvider.upcomingTracks; // 假设这是播放队列数据

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          
          if (currentQueue == null || currentQueue.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No tracks in queue',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: currentQueue.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final track = currentQueue[index];
                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: CachedNetworkImage(
                        imageUrl: track['album']['images'][0]['url'],
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(
                      track['name'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track['artists'][0]['name'],
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _formatDuration(track['duration_ms']),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () {
                      final trackUri = track['uri'];
                      final contextUri = spotifyProvider.currentTrack?['context']?['uri'];
                      if (trackUri != null) {
                        spotifyProvider.playTrack(
                          trackUri: trackUri,
                          contextUri: contextUri,
                        );
                      }
                    },
                    onLongPress: () => _openInSpotify(context, track),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
  
  // 打开Spotify应用或网页
  Future<void> _openInSpotify(BuildContext context, Map<String, dynamic> track) async {
    String? webUrl;
    String? spotifyUri;
    
    // 先尝试获取URI
    if (track['uri'] != null && track['uri'].toString().startsWith('spotify:')) {
      // 直接使用原始URI格式，如 spotify:track:37vIh6I03bNlWKlVMjGRK3
      spotifyUri = track['uri'].toString();
      
      // 从URI构建web URL
      final segments = spotifyUri.split(':');
      if (segments.length >= 3) {
        final type = segments[1]; // track, album, playlist, artist
        final id = segments[2];
        webUrl = 'https://open.spotify.com/$type/$id';
      }
    } 
    // 尝试构建URI
    else if (track['type'] != null && track['id'] != null) {
      final type = track['type'].toString();
      final id = track['id'].toString();
      spotifyUri = 'spotify:$type:$id';
      webUrl = 'https://open.spotify.com/$type/$id';
    }
    // 后备方案：尝试从external_urls
    else if (track['external_urls'] != null && track['external_urls']['spotify'] != null) {
      webUrl = track['external_urls']['spotify'].toString();
      
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
        SnackBar(content: Text(AppLocalizations.of(context)!.cannotCreateSpotifyLink))
      );
      return;
    }
    
    try {
      // 先尝试使用URI启动Spotify应用
      if (spotifyUri != null) {
        final uri = Uri.parse(spotifyUri);
        debugPrint('尝试打开Spotify应用：$uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return; // 成功打开应用后直接返回
        }
      }
      
      // 如果无法打开应用，尝试打开网页
      if (webUrl != null) {
        final uri = Uri.parse(webUrl);
        debugPrint('尝试打开网页链接：$uri');
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      
      // 两种方式都失败
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.cannotOpenSpotify))
      );
    } catch (e) {
      debugPrint('打开Spotify出错: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedToOpenSpotify(e.toString())))
      );
    }
  }
}