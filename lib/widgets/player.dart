//player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import '../providers/spotify_provider.dart';
import '../providers/theme_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/physics.dart';
import 'package:url_launcher/url_launcher.dart';

class Player extends StatefulWidget {
  final bool isLargeScreen;
  final bool isMiniPlayer;

  const Player({
    super.key,
    this.isLargeScreen = false,
    this.isMiniPlayer = false,
  });

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
  late AnimationController _playStateController;
  late Animation<double> _playStateScaleAnimation;
  late Animation<double> _playStateOpacityAnimation;
  
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
    
    _playStateController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _playStateScaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _playStateController, curve: Curves.easeOutCubic)
    );
    
    _playStateOpacityAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _playStateController, curve: Curves.easeOutCubic)
    );
    
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
    _playStateController.dispose();
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
    
    final dragDistance = details.globalPosition.dx - _dragStartX!;
    _dragDistanceNotifier.value = widget.isLargeScreen ? dragDistance / 2 : dragDistance;
    
    final progress = (_dragDistanceNotifier.value.abs() / 100).clamp(0.0, 1.0);
    _transitionController.value = progress;
  }

  void _handleHorizontalDragEnd(DragEndDetails details, SpotifyProvider spotify) async {
    if (_dragStartX == null) return;
    
    final velocity = details.velocity.pixelsPerSecond.dx;
    final threshold = widget.isLargeScreen ? 400.0 : 800.0;
    final distance = _dragDistanceNotifier.value;
    
    final triggerDistance = widget.isLargeScreen ? 40.0 : 80.0;
    
    if (velocity.abs() > threshold || distance.abs() > triggerDistance) {
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
    _fadeController.reverse().then((_) {
      _dragDistanceNotifier.value = 0.0;
    });
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

    if (widget.isMiniPlayer) {
      return _buildMiniPlayer(displayTrack, spotifyProvider);
    }

    return RepaintBoundary(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.isLargeScreen ? 600 : double.infinity,
          ),
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
                            track: displayTrack,
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
      ),
    );
  }

  Widget _buildMainContent(Map<String, dynamic>? track, SpotifyProvider spotify) {
    final isPlaying = context.select<SpotifyProvider, bool>(
      (provider) => provider.currentTrack?['is_playing'] ?? false
    );
    
    if (isPlaying) {
      _playStateController.forward();
    } else {
      _playStateController.reverse();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_transitionController, _playStateController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value * _playStateScaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value * _playStateOpacityAnimation.value,
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: animation.drive(
                Tween<double>(begin: 0.95, end: 1.0)
                  .chain(CurveTween(curve: Curves.easeOutCubic))
              ),
              child: child,
            ),
          );
        },
        child: displayTrack != null && 
               displayTrack['album']?['images'] != null &&
               (displayTrack['album']['images'] as List).isNotEmpty
            ? CachedNetworkImage(
                key: ValueKey(currentImageUrl),
                imageUrl: currentImageUrl!,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholderFadeInDuration: Duration.zero,
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
            : Image.asset(
                'assets/examples/CXOXO.png',
                key: const ValueKey('default_image'),
                fit: BoxFit.cover,
              ),
      ),
    );
  }

  Widget _buildDragIndicators() {
    return ValueListenableBuilder<double>(
      valueListenable: _dragDistanceNotifier,
      builder: (context, dragDistance, _) {
        return DragIndicator(
          dragDistance: dragDistance,
          fadeAnimation: _fadeController,
          indicatorAnimation: _indicatorController,
          isNext: dragDistance < 0,
          isLargeScreen: widget.isLargeScreen,
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

  Widget _buildMiniPlayer(Map<String, dynamic>? track, SpotifyProvider spotify) {
    final isPlaying = context.select<SpotifyProvider, bool>(
      (provider) => provider.currentTrack?['is_playing'] ?? false
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: _buildMiniAlbumArt(track),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?['name'] ?? 'Godspeed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  track != null 
                    ? (track['artists'] as List?)
                        ?.map((artist) => artist['name'] as String)
                        .join(', ') ?? 'Unknown Artist'
                    : 'Camila Cabello',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Control Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  },
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey(isPlaying),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onPressed: () => spotify.togglePlayPause(),
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => spotify.skipToNext(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAlbumArt(Map<String, dynamic>? track) {
    final displayTrack = track ?? _lastTrack;
    final String? currentImageUrl = displayTrack?['album']?['images']?[0]?['url'];

    return displayTrack != null && 
           displayTrack['album']?['images'] != null &&
           (displayTrack['album']['images'] as List).isNotEmpty
        ? CachedNetworkImage(
            key: ValueKey(currentImageUrl),
            imageUrl: currentImageUrl!,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
            memCacheWidth: 48,
            maxWidthDiskCache: 48,
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
        : Image.asset(
            'assets/examples/CXOXO.png',
            key: const ValueKey('default_image'),
            fit: BoxFit.cover,
          );
  }
}

class DragIndicator extends StatelessWidget {
  final double dragDistance;
  final Animation<double> fadeAnimation;
  final Animation<double> indicatorAnimation;
  final bool isNext;
  final bool isLargeScreen;

  const DragIndicator({
    required this.dragDistance,
    required this.fadeAnimation,
    required this.indicatorAnimation,
    required this.isNext,
    this.isLargeScreen = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const maxWidth = 80.0;
    final width = (dragDistance.abs() / 100.0).clamp(0.0, 1.0) * maxWidth;
    
    if (isLargeScreen) {
      // 大屏幕模式：居中圆形指示器
      return Center(
        child: RepaintBoundary(
          child: FadeTransition(
            opacity: fadeAnimation,
            child: AnimatedBuilder(
              animation: indicatorAnimation,
              builder: (context, child) {
                final scale = 1.0 + (1.0 - indicatorAnimation.value) * 0.2;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: width,
                    height: width,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          blurRadius: 16,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: (width / maxWidth).clamp(0.0, 1.0),
                        child: Icon(
                          isNext ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } else {
      // 小屏幕模式
      final maxHeight = MediaQuery.of(context).size.height - 64;
      final minHeight = maxHeight * 0.8;
      final heightProgress = (width / maxWidth).clamp(0.0, 1.0);
      final height = minHeight + (maxHeight - minHeight) * heightProgress;
      
      return Positioned(
        top: 32 + (MediaQuery.of(context).size.height - 64 - height) / 2,
        bottom: 32 + (MediaQuery.of(context).size.height - 64 - height) / 2,
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
                  child: child,
                );
              },
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9),
                  borderRadius: BorderRadius.horizontal(
                    left: isNext ? const Radius.circular(16) : Radius.zero,
                    right: isNext ? Radius.zero : const Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      blurRadius: 16,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Opacity(
                    opacity: (width / maxWidth).clamp(0.0, 1.0),
                    child: Icon(
                      isNext ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
}

class PlayButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const PlayButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  State<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<PlayButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        ),
        child: TextButton(
          onPressed: widget.onPressed,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: Icon(
                widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(widget.isPlaying),
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScrollingText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const ScrollingText({
    super.key,
    required this.text,
    this.style,
  });

  @override
  State<ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<ScrollingText> with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animationController;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _checkIfNeedsScroll();
      }
    });

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _animationController.reverse();
          }
        });
      } else if (status == AnimationStatus.dismissed) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _animationController.forward();
          }
        });
      }
    });
  }

  void _checkIfNeedsScroll() {
    if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
      setState(() {
        _needsScroll = true;
      });
      
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _animationController.forward();
        }
      });

      _animationController.addListener(() {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _animationController.value * _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      _needsScroll = false;
      _animationController.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _checkIfNeedsScroll();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _scrollController,
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(right: 32.0),
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
            ),
          ),
        ),
        if (_needsScroll)
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Theme.of(context).colorScheme.surface.withOpacity(0.0),
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.05, 0.85, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstOut,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
      ],
    );
  }
}

class HeaderAndFooter extends StatelessWidget {
  final String header;
  final String footer;
  final Map<String, dynamic>? track;

  const HeaderAndFooter({
    super.key,
    required this.header,
    required this.footer,
    this.track,
  });

  void _launchSpotifyURL(BuildContext context, String? url) async {
    if (url == null) return;
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法打开 Spotify: $url')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打开 Spotify 链接失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    final albumUrl = track?['album']?['external_urls']?['spotify'];
    final artists = (track?['artists'] as List?)?.map((artist) => {
      'name': artist['name'],
      'url': artist['external_urls']?['spotify'],
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: albumUrl != null ? () => _launchSpotifyURL(context, albumUrl) : null,
          child: ScrollingText(
            text: header,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (artists != null && artists.isNotEmpty)
          Row(
            children: [
              for (int i = 0; i < artists.length; i++) ...[
                if (i > 0) Text(', ', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                )),
                GestureDetector(
                  onTap: artists[i]['url'] != null 
                    ? () => _launchSpotifyURL(context, artists[i]['url']) 
                    : null,
                  child: Text(
                    artists[i]['name'] as String,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ],
          )
        else
          ScrollingText(
            text: footer,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
      ],
    );
  }
}
