//player.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import '../providers/spotify_provider.dart';
import '../providers/theme_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/physics.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../widgets/song_info_result_page.dart';
import '../services/notification_service.dart';
import '../l10n/app_localizations.dart';

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
  double? _dragStartY;
  bool _isHorizontalDragConfirmed = false;
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
  bool _isSeekOverlayVisible = false;
  
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
    _dragStartY = details.globalPosition.dy;
    _dragDistanceNotifier.value = 0.0;
    _isHorizontalDragConfirmed = false;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_dragStartX == null || _dragStartY == null) return;

    final dx = details.globalPosition.dx - _dragStartX!;
    final dy = details.globalPosition.dy - _dragStartY!;

    if (!_isHorizontalDragConfirmed) {
      if (dy.abs() > dx.abs() * 1.5) {
        _dragStartX = null;
        _dragStartY = null;
        _fadeController.reverse();
        _transitionController.reverse();
        _dragDistanceNotifier.value = 0.0;
        return;
      } else if (dx.abs() > 10.0) {
         _isHorizontalDragConfirmed = true;
      }
    }
    
    if (_isHorizontalDragConfirmed) {
      final dragDistance = widget.isLargeScreen ? dx / 2 : dx;
      _dragDistanceNotifier.value = dragDistance;
      
      final progress = (_dragDistanceNotifier.value.abs() / 100).clamp(0.0, 1.0);
      _transitionController.value = progress;
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details, SpotifyProvider spotify) async {
    if (_dragStartX == null || !_isHorizontalDragConfirmed) {
       if (_fadeController.value > 0.0) _fadeController.reverse();
       if (_transitionController.value > 0.0) _transitionController.reverse();
       _dragDistanceNotifier.value = 0.0;
       _dragStartX = null;
       _dragStartY = null;
       _isHorizontalDragConfirmed = false;
       return;
    }
    
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
      
      HapticFeedback.mediumImpact();
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
    _dragStartY = null;
    _isHorizontalDragConfirmed = false;
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

    if (widget.isLargeScreen) {
      return RepaintBoundary(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _buildLargeScreenPlayerLayout(displayTrack, spotifyProvider),
          ),
        ),
      );
    } else {
      return RepaintBoundary(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Stack(
                    children: [
                    _buildMainContent(displayTrack, spotifyProvider),
                    Positioned(
                      bottom: 64,
                      right: MediaQuery.of(context).size.width < 350 ? 25 : 
                             MediaQuery.of(context).size.width < 400 ? 20 : 15,
                      child: PlayButton(
                        isPlaying: context.watch<SpotifyProvider>().currentTrack?['is_playing'] ?? false,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          spotifyProvider.togglePlayPause();
                        },
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
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          spotifyProvider.togglePlayMode();
                        },
                      ),
                    ),
                    _buildDragIndicators(),
                    ],
                  ),
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
                            onPressed: spotifyProvider.currentTrack != null && track != null
                              ? () {
                                  HapticFeedback.lightImpact();
                                  spotifyProvider.toggleTrackSave();
                                }
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
        onTap: () {
          setState(() {
            _isSeekOverlayVisible = !_isSeekOverlayVisible;
          });
        },
        onLongPress: () async {
          final currentTrackData = spotify.currentTrack;
          String? urlToLaunch;

          // 1. Try to get context URL (album, playlist, etc.)
          final contextData = currentTrackData?['context'];
          if (contextData != null && contextData['external_urls'] is Map) {
            urlToLaunch = contextData['external_urls']['spotify'];
          }

          // 2. If no context URL, try track URL
          if (urlToLaunch == null) {
            final trackData = currentTrackData?['item'];
            if (trackData != null && trackData['external_urls'] is Map) {
              urlToLaunch = trackData['external_urls']['spotify'];
            }
          }

          // 3. Try launching the found URL or fallback to opening Spotify app
          if (urlToLaunch != null) {
            _launchSpotifyURL(context, urlToLaunch);
          } else {
            // Fallback: Try opening the Spotify app directly
            final spotifyUri = Uri.parse('spotify:');
            try {
              if (await canLaunchUrl(spotifyUri)) {
                await launchUrl(spotifyUri, mode: LaunchMode.externalApplication);
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)!.cannotOpenSpotify)),
                );
              }
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.failedToOpenSpotify(''))),
              );
            }
          }
        },
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
            themeProvider.updateThemeFromImage(imageProvider, MediaQuery.platformBrightnessOf(context));
          }
          _isThemeUpdating = false;
        });
      }
    }

    // 原本的 ClipRRect 现在是 Stack 的第一个子元素
    final albumArtWidget = ClipRRect(
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

    // 返回包含专辑封面和遮罩的 Stack
    return Stack(
      alignment: Alignment.center, // 居中对齐 Stack 子元素
      children: [
        // 1. 专辑封面，根据状态调整透明度使其变暗
        AnimatedOpacity(
          opacity: _isSeekOverlayVisible ? 0.6 : 1.0, // 遮罩可见时降低透明度
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: albumArtWidget, // 将原始封面放在这里
        ),

        // 2. 条件渲染的按钮层 (保持在顶层)
        AnimatedOpacity(
          opacity: _isSeekOverlayVisible ? 1.0 : 0.0, // 遮罩可见时按钮完全不透明
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !_isSeekOverlayVisible,
            // 不需要 GestureDetector 了，因为外部 onTap 会处理
            child: Center( // 确保按钮在 Stack 中心
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSeekButton(
                    icon: Icons.replay_10_rounded,
                    label: '-10s',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
                      final currentProgressMs = spotifyProvider.currentTrack?['progress_ms'] as int?;
                      if (currentProgressMs != null) {
                        final targetPosition = max(0, currentProgressMs - 10000); // 减去 10 秒，但不小于 0
                        spotifyProvider.seekToPosition(Duration(milliseconds: targetPosition).inMilliseconds);
                      }
                    },
                  ),
                  _buildSeekButton(
                    icon: Icons.info_outline_rounded,
                    label: AppLocalizations.of(context)!.infoLabel,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _showSongInfo();
                    },
                  ),
                  _buildSeekButton(
                    icon: Icons.forward_10_rounded,
                    label: '+10s',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
                      final currentProgressMs = spotifyProvider.currentTrack?['progress_ms'] as int?;
                      final trackDurationMs = spotifyProvider.currentTrack?['item']?['duration_ms'] as int?;
                      if (currentProgressMs != null && trackDurationMs != null) {
                        final targetPosition = min(trackDurationMs, currentProgressMs + 10000); // 加上 10 秒，但不超过总时长
                        spotifyProvider.seekToPosition(Duration(milliseconds: targetPosition).inMilliseconds);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 辅助方法构建 Seek 按钮 (可以放在 _PlayerState 类中)
  Widget _buildSeekButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 48),
          onPressed: onPressed,
        ),
      ],
    );
  }

  // 显示歌曲信息
  Future<void> _showSongInfo() async {
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack;
    
    if (currentTrack == null || currentTrack['item'] == null) {
      notificationService.showSnackBar(AppLocalizations.of(context)!.noCurrentTrackPlaying);
      return;
    }

    final trackData = currentTrack['item'] as Map<String, dynamic>;
    
    // 隐藏seek overlay
    setState(() {
      _isSeekOverlayVisible = false;
    });

    // 直接导航到结果页面，页面内部会处理加载状态
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SongInfoResultPage(
          trackData: trackData,
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
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width < 350 ? 8 : 16,
      ),
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
          SizedBox(width: MediaQuery.of(context).size.width < 350 ? 8 : 16),
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
          // Control Buttons - 响应式设计
          _buildResponsiveControlButtons(spotify, isPlaying),
        ],
      ),
    );
  }

  /// 构建响应式控制按钮
  Widget _buildResponsiveControlButtons(SpotifyProvider spotify, bool isPlaying) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        
        // 根据屏幕宽度调整按钮大小和行为
        if (screenWidth < 350) {
          // 极窄屏幕：只显示播放/暂停按钮
          return IconButton(
            iconSize: 20, // 较小的图标
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
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
            onPressed: () {
              HapticFeedback.lightImpact();
              spotify.togglePlayPause();
            },
          );
        } else if (screenWidth < 400) {
          // 窄屏幕：使用紧凑按钮
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 20,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
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
                onPressed: () {
                  HapticFeedback.lightImpact();
                  spotify.togglePlayPause();
                },
              ),
              IconButton(
                iconSize: 20,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  spotify.skipToNext();
                },
              ),
            ],
          );
        } else {
          // 普通屏幕：使用标准按钮
          return Row(
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
                onPressed: () {
                  HapticFeedback.lightImpact();
                  spotify.togglePlayPause();
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  spotify.skipToNext();
                },
              ),
            ],
          );
        }
      },
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

  void _launchSpotifyURL(BuildContext context, String? url) async {
    if (url == null) return;
    
    // Capture context before async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final localizations = AppLocalizations.of(context)!;
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(localizations.failedToOpenSpotify(url))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(localizations.failedToOpenSpotify(''))),
      );
    }
  }

  Future<void> _showArtistSelectionDialog(BuildContext context, List<Map<String, dynamic>> artists) async {
    if (!context.mounted) return;

    final playerState = context.findAncestorStateOfType<_PlayerState>();
    if (playerState == null) return;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.selectArtistTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                final artistName = artist['name'] as String? ?? 'Unknown Artist';
                final artistUrl = artist['url'] as String?;
                final bool canLaunch = artistUrl != null;

                return ListTile(
                  title: Text(artistName),
                  enabled: canLaunch,
                  onTap: canLaunch
                      ? () {
                          Navigator.pop(dialogContext); // Close the dialog
                          playerState._launchSpotifyURL(context, artistUrl);
                        }
                      : null,
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context)!.cancel),
              onPressed: () {
                Navigator.pop(dialogContext); // Close the dialog
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildLargeScreenPlayerLayout(Map<String, dynamic>? displayTrack, SpotifyProvider spotifyProvider) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double textSectionFixedHeight = 70.0;
        const double spacingBelowArt = 8.0;
        const double artExternalPaddingHorizontal = 48.0 * 2;
        const double artExternalPaddingVertical = 32.0 * 2;

        double artContentAvailableWidth = constraints.maxWidth - artExternalPaddingHorizontal;
        double artContentAvailableHeight = constraints.maxHeight -
                                          textSectionFixedHeight -
                                          spacingBelowArt -
                                          artExternalPaddingVertical;
        artContentAvailableWidth = max(0, artContentAvailableWidth);
        artContentAvailableHeight = max(0, artContentAvailableHeight);
        double artDimension = min(artContentAvailableWidth, artContentAvailableHeight);
        artDimension = max(0, artDimension);

        final isPlaying = context.select<SpotifyProvider, bool>(
          (provider) => provider.currentTrack?['is_playing'] ?? false
        );

        final double stackWidth = artDimension * 1.2;
        final double stackHeight = artDimension * 1.2;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: stackWidth,
              height: stackHeight,
              child: Stack(
                children: [
                  Center(
                    child: _buildConfigurableMainContent(
                      displayTrack,
                      spotifyProvider,
                      isPlaying: isPlaying,
                      artDimension: artDimension, // Actual album art content is still artDimension
                    ),
                  ),
                  Positioned(
                    bottom: stackHeight * 0.10, // 距离底部 20% container 高度
                    right: max(stackWidth * 0.02, 10), // 确保至少10px边距，避免负值
                    child: PlayButton(
                      isPlaying: context.watch<SpotifyProvider>().currentTrack?['is_playing'] ?? false,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        spotifyProvider.togglePlayPause();
                      },
                    ),
                  ),
                  Positioned(
                    bottom: max(stackHeight * 0.02, 10), // 确保至少10px底部边距，避免负值
                    left: stackWidth * 0.10, // 距离左边 10% container 宽度
                    child: MyButton(
                      width: 64,
                      height: 64,
                      radius: 20,
                      icon: _getPlayModeIcon(context.watch<SpotifyProvider>().currentMode),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        spotifyProvider.togglePlayMode();
                      },
                    ),
                  ),
                  _buildDragIndicators(),
                ],
              ),
            ),
            const SizedBox(height: spacingBelowArt), // Use the defined spacing
            SizedBox(
              height: textSectionFixedHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 48, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                          onPressed: spotifyProvider.currentTrack != null && displayTrack != null
                            ? () {
                                HapticFeedback.lightImpact();
                                spotifyProvider.toggleTrackSave();
                              }
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
            ),
          ],
        );
      },
    );
  }

  Widget _buildConfigurableMainContent(Map<String, dynamic>? track, SpotifyProvider spotify, {required bool isPlaying, double? artDimension}) {
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
        onTap: () {
          setState(() {
            _isSeekOverlayVisible = !_isSeekOverlayVisible;
          });
        },
        onLongPress: () async {
          final currentTrackData = spotify.currentTrack;
          String? urlToLaunch;

          // 1. Try to get context URL (album, playlist, etc.)
          final contextData = currentTrackData?['context'];
          if (contextData != null && contextData['external_urls'] is Map) {
            urlToLaunch = contextData['external_urls']['spotify'];
          }

          // 2. If no context URL, try track URL
          if (urlToLaunch == null) {
            final trackData = currentTrackData?['item'];
            if (trackData != null && trackData['external_urls'] is Map) {
              urlToLaunch = trackData['external_urls']['spotify'];
            }
          }

          // 3. Try launching the found URL or fallback to opening Spotify app
          if (urlToLaunch != null) {
            _launchSpotifyURL(context, urlToLaunch);
          } else {
            // Fallback: Try opening the Spotify app directly
            final spotifyUri = Uri.parse('spotify:');
            try {
              if (await canLaunchUrl(spotifyUri)) {
                await launchUrl(spotifyUri, mode: LaunchMode.externalApplication);
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)!.cannotOpenSpotify)),
                );
              }
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.failedToOpenSpotify(''))),
              );
            }
          }
        },
        child: RepaintBoundary(
          child: artDimension != null
              ? SizedBox(
                  width: artDimension,
                  height: artDimension,
                  child: _buildAlbumArt(track),
                )
              : _buildAlbumArt(track),
        ),
      ),
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
                      color: Theme.of(context).colorScheme.primaryContainer.withAlpha((0.9 * 255).round()),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withAlpha((0.2 * 255).round()),
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
      final availableHeight = MediaQuery.of(context).size.height - 64;
      // Ensure maxHeight is not negative
      final maxHeight = max(0.0, availableHeight); 
      final minHeight = maxHeight * 0.8;
      final heightProgress = (width / maxWidth).clamp(0.0, 1.0);
      final height = minHeight + (maxHeight - minHeight) * heightProgress;
      
      // Ensure top and bottom calculation doesn't result in negative values if availableHeight was initially negative.
      // This prevents issues if the widget is somehow rendered in a space smaller than 64 logical pixels high.
      final verticalPadding = max(0.0, (availableHeight - height) / 2);

      return Positioned(
        top: 32 + verticalPadding,
        bottom: 32 + verticalPadding,
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
                height: height, // height is now guaranteed >= 0
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withAlpha((0.9 * 255).round()),
                  borderRadius: BorderRadius.horizontal(
                    left: isNext ? const Radius.circular(16) : Radius.zero,
                    right: isNext ? Radius.zero : const Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withAlpha((0.2 * 255).round()),
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
            width: MediaQuery.of(context).size.width < 400 ? 80 : 96,  // 窄屏幕使用更小尺寸
            height: MediaQuery.of(context).size.width < 400 ? 56 : 64,  // 窄屏幕使用更小尺寸
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
                color: Theme.of(context).colorScheme.onPrimary,
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
                    Theme.of(context).colorScheme.surface.withAlpha((0.0 * 255).round()),
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface.withAlpha((0.0 * 255).round()),
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

  @override
  Widget build(BuildContext context) {
    final playerState = context.findAncestorStateOfType<_PlayerState>();

    final albumUrl = track?['album']?['external_urls']?['spotify'];
    final artists = (track?['artists'] as List?)?.map((artist) => {
      'name': artist['name'],
      'url': artist['external_urls']?['spotify'],
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: albumUrl != null && playerState != null 
            ? () => playerState._launchSpotifyURL(context, albumUrl) 
            : null,
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
          GestureDetector(
            onTap: playerState != null
                ? () {
                    if (artists.length > 1) {
                      playerState._showArtistSelectionDialog(context, artists);
                    } else if (artists.length == 1 && artists[0]['url'] != null) {
                      playerState._launchSpotifyURL(context, artists[0]['url']);
                    }
                  }
                : null,
            child: ScrollingText(
              text: artists.map((artist) => artist['name'] as String).join(', '),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
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
