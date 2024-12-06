//player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import '../providers/spotify_provider.dart';
import '../providers/theme_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/physics.dart';

class Player extends StatefulWidget {
  const Player({super.key});

  @override
  State<Player> createState() => _PlayerState();
}
class _PlayerState extends State<Player> with TickerProviderStateMixin {
  final _dragDistanceNotifier = ValueNotifier<double>(0.0);
  double? _dragStartX;
  late AnimationController _fadeController;
  late AnimationController _transitionController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Map<String, dynamic>? _lastTrack;
  late AnimationController _indicatorController;
  String? _lastImageUrl;
  bool _isThemeUpdating = false;
  
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    )..value = 0.0;
    
    _transitionController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..value = 0.0;
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _transitionController, curve: Curves.easeOutCubic)
    );
    
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _transitionController, curve: Curves.easeOutCubic)
    );
    
    _indicatorController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    )..value = 0.0;
    
    if (_lastImageUrl != null) {
      _prefetchImage(_lastImageUrl!);
    }
  }

  Future<void> _prefetchImage(String imageUrl) async {
    final imageProvider = CachedNetworkImageProvider(
      imageUrl,
      maxWidth: MediaQuery.sizeOf(context).width.toInt(),
    );
    await precacheImage(imageProvider, context);
  }

  @override
  void dispose() {
    _dragDistanceNotifier.dispose();
    _fadeController.dispose();
    _transitionController.dispose();
    _indicatorController.dispose();
    super.dispose();
  }
  
  void _handleHorizontalDragStart(DragStartDetails details) {
    _fadeController.value = 1.0;
    _indicatorController.value = 0.0;
    _dragStartX = details.globalPosition.dx;
    _dragDistanceNotifier.value = 0.0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_dragStartX == null) return;
    _dragDistanceNotifier.value = details.globalPosition.dx - _dragStartX!;
    
    final progress = (_dragDistanceNotifier.value.abs() / 100).clamp(0.0, 1.0);
    _transitionController.value = progress;
  }

  void _handleHorizontalDragEnd(DragEndDetails details, SpotifyProvider spotify) async {
    if (_dragStartX == null) return;
    
    final velocity = details.velocity.pixelsPerSecond.dx;
    const threshold = 800.0;
    final distance = _dragDistanceNotifier.value;
    
    if (velocity.abs() > threshold || distance.abs() > 80) {
      _indicatorController.forward();
      
      final spring = SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: 500.0,
        ratio: 1.1,
      );
      
      final simulation = SpringSimulation(spring, _transitionController.value, 1.0, velocity / 1500);
      await _transitionController.animateWith(simulation);
      
      if (distance > 0) {
        spotify.skipToPrevious();
      } else {
        spotify.skipToNext();
      }
      
      await _transitionController.reverse();
    } else {
      _indicatorController.forward();
      
      final spring = SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: 500.0,
        ratio: 0.9,
      );
      
      final simulation = SpringSimulation(spring, _transitionController.value, 0.0, velocity / 1500);
      await _transitionController.animateWith(simulation);
    }
    
    _dragStartX = null;
    _dragDistanceNotifier.value = 0.0;
    _fadeController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final track = context.select<SpotifyProvider, Map<String, dynamic>?>(
      (provider) => provider.currentTrack?['item']
    );
    
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    
    if (track != null) {
      _lastTrack = track;
    }
    
    final displayTrack = track ?? _lastTrack;

    return RepaintBoundary(
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _buildMainContent(displayTrack, spotifyProvider),
                Positioned(
                  bottom: 64,
                  right: 10,
                  child: PlayButton(
                    isPlaying: context.watch<SpotifyProvider>().currentTrack?['is_playing'] ?? false,
                    onPressed: () => spotifyProvider.togglePlayPause(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 64,
                  child: MyButton(
                    width: 64,
                    height: 64,
                    radius: 20,
                    icon: _getPlayModeIcon(context.watch<SpotifyProvider>().currentMode),
                    onPressed: () => spotifyProvider.togglePlayMode(),
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
                          header: displayTrack?['name'] ?? 'Godspeed',
                          footer: displayTrack != null 
                              ? (displayTrack['artists'] as List?)
                                  ?.map((artist) => artist['name'] as String)
                                  .join(', ') ?? 'Unknown Artist'
                              : 'Camila Cabello',
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: spotifyProvider.username != null && track != null
                          ? () => spotifyProvider.toggleTrackSave()
                          : null,
                        icon: Icon(
                          context.select<SpotifyProvider, bool>((provider) => 
                            provider.isCurrentTrackSaved ?? false)
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
    return AnimatedBuilder(
      animation: _transitionController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        );
      },
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final displayTrack = track ?? _lastTrack;
    final String? currentImageUrl = displayTrack?['album']?['images']?[0]?['url'];

    if (currentImageUrl != null && currentImageUrl != _lastImageUrl) {
      _prefetchImage(currentImageUrl);
      
      if (!_isThemeUpdating) {
        _isThemeUpdating = true;
        _lastImageUrl = currentImageUrl;
        
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && currentImageUrl == _lastImageUrl) {
            final imageProvider = CachedNetworkImageProvider(
              currentImageUrl,
              maxWidth: MediaQuery.sizeOf(context).width.toInt(),
            );
            themeProvider.updateThemeFromImage(imageProvider);
          }
          _isThemeUpdating = false;
        });
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: displayTrack != null && 
             displayTrack['album']?['images'] != null &&
             (displayTrack['album']['images'] as List).isNotEmpty
          ? CachedNetworkImage(
              imageUrl: currentImageUrl!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              fadeOutDuration: const Duration(milliseconds: 150),
              placeholderFadeInDuration: const Duration(milliseconds: 150),
              memCacheWidth: (MediaQuery.of(context).size.width * 1.5).toInt(),
              maxWidthDiskCache: (MediaQuery.of(context).size.width * 1.5).toInt(),
              placeholder: (context, url) => Container(
                color: Theme.of(context).colorScheme.surface,
                child: _lastTrack != null && _lastImageUrl != null
                  ? Image(
                      image: CachedNetworkImageProvider(_lastImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : Image.asset('assets/examples/CXOXO.png', fit: BoxFit.cover),
              ),
              errorWidget: (context, url, error) => 
                Image.asset('assets/examples/CXOXO.png', fit: BoxFit.cover),
            )
          : Image.asset('assets/examples/CXOXO.png', fit: BoxFit.cover),
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
          indicatorAnimation: _indicatorController,
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
  final Animation<double> indicatorAnimation;
  final bool isNext;

  const DragIndicator({
    required this.dragDistance,
    required this.fadeAnimation,
    required this.indicatorAnimation,
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
          child: AnimatedBuilder(
            animation: indicatorAnimation,
            builder: (context, child) {
              final slideOffset = maxWidth * indicatorAnimation.value;
              return Transform.translate(
                offset: Offset(
                  isNext ? slideOffset : -slideOffset,
                  0,
                ),
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
              );
            },
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
