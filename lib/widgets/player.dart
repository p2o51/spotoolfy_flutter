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
  final _dragDistanceNotifier = ValueNotifier<double>(0.0);
  double? _dragStartX;
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
    _dragDistanceNotifier.dispose();
    _fadeController.dispose();
    super.dispose();
  }
  
  void _handleHorizontalDragStart(DragStartDetails details) {
    _fadeController.value = 1.0;
    _dragStartX = details.globalPosition.dx;
    _dragDistanceNotifier.value = 0.0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_dragStartX == null) return;
    _dragDistanceNotifier.value = details.globalPosition.dx - _dragStartX!;
  }

  void _handleHorizontalDragEnd(DragEndDetails details, SpotifyProvider spotify) async {
    if (_dragStartX == null) return;
    
    final velocity = details.velocity.pixelsPerSecond.dx;
    const threshold = 1000.0;
    final distance = _dragDistanceNotifier.value;
    
    if (velocity.abs() > threshold || distance.abs() > 100) {
      if (distance > 0) {
        spotify.skipToPrevious();
      } else {
        spotify.skipToNext();
      }
    }
    
    await _fadeController.animateTo(0.0);
    _dragStartX = null;
    _dragDistanceNotifier.value = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final spotify = context.watch<SpotifyProvider>();
    final track = spotify.currentTrack?['item'];
    
    return RepaintBoundary(
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _buildMainContent(track, spotify),
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
                _buildDragIndicators(),
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
      ),
    );
  }

  Widget _buildMainContent(Map<String, dynamic>? track, SpotifyProvider spotify) {
    return Positioned(
      child: GestureDetector(
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(details, spotify),
        child: RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
            child: _buildAlbumArt(track),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArt(Map<String, dynamic>? track) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    bool hasUpdatedTheme = false;

    return ClipRRect(
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
                if (frame != null && !hasUpdatedTheme) {
                  hasUpdatedTheme = true;
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
    );
  }

  Widget _buildDragIndicators() {
    return ValueListenableBuilder<double>(
      valueListenable: _dragDistanceNotifier,
      builder: (context, dragDistance, _) {
        if (dragDistance == 0) return const SizedBox.shrink();
        return DragIndicator(
          dragDistance: dragDistance,
          fadeAnimation: _fadeController,
          isNext: dragDistance < 0,
        );
      },
    );
  }

  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
      case PlayMode.sequential:
        return Icons.repeat_rounded;
      case PlayMode.singleRepeat:
        return Icons.repeat_one_rounded;
      default:
        return Icons.repeat_rounded;
    }
  }
}

class DragIndicator extends StatelessWidget {
  final double dragDistance;
  final Animation<double> fadeAnimation;
  final bool isNext;

  const DragIndicator({
    required this.dragDistance,
    required this.fadeAnimation,
    required this.isNext,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const maxWidth = 80.0;
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
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: fadeAnimation,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.horizontal(
                left: isNext ? const Radius.circular(16) : Radius.zero,
                right: isNext ? Radius.zero : const Radius.circular(16),
              ),
            ),
            child: Opacity(
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
