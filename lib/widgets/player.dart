//player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import '../providers/spotify_provider.dart';
import '../providers/theme_provider.dart';

class Player extends StatelessWidget {
  const Player({super.key});

  @override
  Widget build(BuildContext context) {
    final spotify = context.watch<SpotifyProvider>();
    final track = spotify.currentTrack?['item'];
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Positioned(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: track != null && 
                           track['album']?['images'] != null &&
                           (track['album']['images'] as List).isNotEmpty
                        ? Image.network(
                            track['album']['images'][0]['url'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Image.asset('assets/examples/CXOXO.png');
                            },
                            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                              if (frame != null) {
                                // 图片加载完成后更新主题
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  themeProvider.updateThemeFromImage(
                                    NetworkImage(track['album']['images'][0]['url'])
                                  );
                                });
                              }
                              return child;
                            },
                          )
                        : Image.asset('assets/examples/CXOXO.png'),
                  ),
                ),
              ),
              Positioned(
                bottom: 64,
                right: 10,
                child: PlayButton(
                  isPlaying: spotify.currentTrack?['is_playing'] ?? false,
                  onPressed: () => spotify.togglePlayPause(),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 64,
                child: MyButton(
                  width: 64,
                  height: 64,
                  radius: 20,
                  icon: Icons.skip_next_rounded,
                  onPressed: () => spotify.skipToNext(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 48, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: HeaderAndFooter(
                        header: track?['name'] ?? 'Godspeed',
                        footer: track != null 
                            ? (track['artists'] as List?)
                                ?.map((artist) => artist['name'] as String)
                                .join(', ') ?? 'Unknown Artist'
                            : 'Camila Cabello',
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: spotify.username != null && track != null
                        ? () => spotify.toggleTrackSave()
                        : null,
                      icon: Icon(
                        spotify.isCurrentTrackSaved ?? false
                            ? Icons.favorite
                            : Icons.favorite_outline_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const PlayButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Container(
        width: 96,
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(32.0),
          border: Border.all(
            color: Theme.of(context).colorScheme.primaryContainer,
            width: 4,
          ),
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
        ),
      ),
    );
  }
}
