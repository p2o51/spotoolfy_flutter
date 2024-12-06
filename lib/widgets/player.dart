//player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import '../providers/spotify_provider.dart';
import '../providers/theme_provider.dart';

class Player extends StatefulWidget {
  const Player({super.key});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> with SingleTickerProviderStateMixin {
  double? dragStartX;
  double dragDistance = 0.0;
  late AnimationController _fadeController;
  
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..value = 0.0;
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }
  
  void _handleHorizontalDragStart(DragStartDetails details) {
    _fadeController.value = 1.0;
    setState(() {
      dragStartX = details.globalPosition.dx;
      dragDistance = 0.0;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (dragStartX == null) return;
    
    setState(() {
      dragDistance = details.globalPosition.dx - dragStartX!;
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details, SpotifyProvider spotify) async {
    if (dragStartX == null) return;
    
    final velocity = details.velocity.pixelsPerSecond.dx;
    final threshold = 1000.0;
    
    if (velocity.abs() > threshold || dragDistance.abs() > 100) {
      if (dragDistance > 0) {
        spotify.skipToPrevious();
      } else {
        spotify.skipToNext();
      }
      await _fadeController.animateTo(0.0);
    } else {
      await _fadeController.animateTo(0.0);
    }
    
    setState(() {
      dragStartX = null;
      dragDistance = 0.0;
    });
  }

  Widget _buildDragIndicator(bool isNext) {
    final maxWidth = 80.0;
    final width = (dragDistance.abs() / 100.0).clamp(0.0, 1.0) * maxWidth;
    
    final maxHeight = MediaQuery.of(context).size.height - 64;
    final minHeight = maxHeight * 0.8;
    final heightProgress = (width / maxWidth).clamp(0.0, 1.0);
    final height = minHeight + (maxHeight - minHeight) * heightProgress;
    
    return Positioned(
      top: 32 + (maxHeight - height) / 2,
      bottom: 32 + (maxHeight - height) / 2,
      right: isNext ? 0 : null,
      left: isNext ? null : 0,
      child: FadeTransition(
        opacity: _fadeController,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.horizontal(
              left: isNext ? const Radius.circular(16) : Radius.zero,
              right: isNext ? Radius.zero : const Radius.circular(16),
            ),
          ),
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 100),
              opacity: (width / maxWidth).clamp(0.0, 1.0),
              child: Icon(
                isNext ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.singleRepeat:
        return Icons.repeat_one_rounded;
      case PlayMode.sequential:
        return Icons.repeat_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

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
                child: GestureDetector(
                  onHorizontalDragStart: _handleHorizontalDragStart,
                  onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                  onHorizontalDragEnd: (details) => 
                      _handleHorizontalDragEnd(details, spotify),
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
                  icon: _getPlayModeIcon(spotify.currentMode),
                  onPressed: () => spotify.togglePlayMode(),
                ),
              ),
              if (dragDistance != 0)
                _buildDragIndicator(dragDistance < 0),
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
