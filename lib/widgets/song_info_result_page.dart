import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../services/song_info_service.dart';
import '../services/gemini_chat_service.dart';
import '../services/notification_service.dart';
import '../widgets/materialui.dart';
import '../widgets/ai_chat_sheet.dart';
import '../l10n/app_localizations.dart';

class SongInfoResultPage extends StatefulWidget {
  final Map<String, dynamic> trackData;
  final Map<String, dynamic>? initialSongInfo; // 可选的初始数据

  const SongInfoResultPage({
    super.key,
    required this.trackData,
    this.initialSongInfo,
  });

  @override
  State<SongInfoResultPage> createState() => _SongInfoResultPageState();
}

class _SongInfoResultPageState extends State<SongInfoResultPage>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isRegenerating = false;
  String? _regenerationError;
  Map<String, dynamic>? _currentSongInfo;

  final SongInfoService _songInfoService = SongInfoService();

  
  // 加载动画控制器
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _bounceController;
  late AnimationController _shimmerController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _shimmerAnimation;

  // 信息出现动画控制器
  late AnimationController _infoAnimationController;
  late List<Animation<double>> _infoAnimations;
  
  int _dotCount = 0;
  
  late String _currentFunnyText;

  String _getRandomFunnyText() {
    // Only call this method after the widget is fully built
    if (!mounted) return 'Loading...';
    
    final l10n = AppLocalizations.of(context)!;
    final trackName = widget.trackData['name'] as String? ?? l10n.unknownTrack;
    final artistNames = (widget.trackData['artists'] as List?)
        ?.map((artist) => artist['name'] as String)
        .join(', ') ?? l10n.unknownArtist;

    final staticTexts = [
      l10n.loadingAnalyzing,
      l10n.loadingDecoding,
      l10n.loadingSearching,
      l10n.loadingThinking,
      l10n.loadingGenerating,
      l10n.loadingDiscovering,
      l10n.loadingExploring,
      l10n.loadingUnraveling,
      l10n.loadingConnecting,
    ];

    // 60% 概率使用动态文本，40% 概率使用静态文本
    if (Random().nextDouble() < 0.6 && trackName != l10n.unknownTrack && artistNames != l10n.unknownArtist) {
      return l10n.loadingChatting(artistNames);
    } else {
      return staticTexts[Random().nextInt(staticTexts.length)];
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize with a default text, will be set properly in didChangeDependencies
    _currentFunnyText = 'Loading...';
    
    // 初始化动画控制器
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // 信息出现动画控制器
    _infoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutBack,
    ));

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.easeInOutCubic,
    ));

    _bounceAnimation = Tween<double>(
      begin: 0.0,
      end: 12.0,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.elasticOut,
    ));

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    ));
    
    // 初始化信息动画列表（最多6个信息板块）
    _infoAnimations = List.generate(6, (index) {
      final startTime = (index * 0.15).clamp(0.0, 0.8); // 每个板块延迟150ms，确保不超过0.8
      final endTime = (startTime + 0.4).clamp(startTime, 1.0); // 每个动画持续400ms，确保不超过1.0
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _infoAnimationController,
        curve: Interval(startTime, endTime, curve: Curves.easeOutBack),
      ));
    });

    // 如果有初始数据，直接使用
    if (widget.initialSongInfo != null) {
      _currentSongInfo = widget.initialSongInfo;
      // 延迟启动动画，让页面先渲染
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _infoAnimationController.forward();
      });
    }
    // Note: _loadSongInfo() will be called in didChangeDependencies() if needed
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Now it's safe to call _getRandomFunnyText() since the context is fully initialized
    if (_currentFunnyText == 'Loading...') {
      _currentFunnyText = _getRandomFunnyText();
    }
    
    // Start loading if no initial data was provided
    if (widget.initialSongInfo == null && _currentSongInfo == null && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSongInfo();
      });
    }
  }

  void _startLoadingTextAnimation() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _isLoading) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4;
          // Loading text animation (dots only for now)
        });
        _startLoadingTextAnimation();
      }
    });
  }

  void _startFunnyTextRotation() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && (_isLoading || _isRegenerating)) {
        setState(() {
          // 每2秒随机选择新的幽默文本
          _currentFunnyText = _getRandomFunnyText();
        });
        _startFunnyTextRotation();
      }
    });
  }

  void _startVibrationCycle() {
    // 更富表现力的振动模式：强-弱-弱-强 循环
    final vibrationPattern = [
      (Duration(milliseconds: 400), HapticFeedback.heavyImpact),
      (Duration(milliseconds: 200), HapticFeedback.lightImpact),
      (Duration(milliseconds: 200), HapticFeedback.selectionClick),
      (Duration(milliseconds: 300), HapticFeedback.mediumImpact),
      (Duration(milliseconds: 600), HapticFeedback.lightImpact),
    ];
    int patternIndex = 0;

    void performVibration() {
      if (mounted && (_isLoading || _isRegenerating)) {
        final (delay, vibration) = vibrationPattern[patternIndex];
        vibration();
        patternIndex = (patternIndex + 1) % vibrationPattern.length;
        Future.delayed(delay, performVibration);
      }
    }

    performVibration();
  }

  Future<void> _loadSongInfo() async {
    setState(() {
      _isLoading = true;
      _regenerationError = null;
      // 每次加载时随机选择新的幽默文本
      if (mounted) {
        _currentFunnyText = _getRandomFunnyText();
      }
    });

    // 启动动画
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
    _bounceController.repeat(reverse: true);
    _shimmerController.repeat();
    _startLoadingTextAnimation();
    _startFunnyTextRotation();
    _startVibrationCycle();

    try {
      final songInfo = await _songInfoService.generateSongInfo(widget.trackData);
      
      if (!mounted) return;
      
      if (songInfo != null) {
        setState(() {
          _currentSongInfo = songInfo;
          _isLoading = false;
        });
        
        // 停止加载动画
        _pulseController.stop();
        _rotationController.stop();
        _bounceController.stop();
        _shimmerController.stop();

        // 启动信息出现动画
        _infoAnimationController.forward();
      } else {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          _showError(l10n.noSongInfoAvailable);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _showError('${l10n.noSongInfoAvailable}: ${e.toString()}');
      }
    }
  }

  // 重新生成歌曲信息
  Future<void> _regenerateSongInfo() async {
    if (_isRegenerating || _isLoading) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isRegenerating = true;
      _regenerationError = null;
      // 重新生成时也随机选择新的幽默文本
      if (mounted) {
        _currentFunnyText = _getRandomFunnyText();
      }
    });

    // 启动动画和文本轮换
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
    _bounceController.repeat(reverse: true);
    _shimmerController.repeat();
    _startLoadingTextAnimation();
    _startFunnyTextRotation();
    _startVibrationCycle();

    try {
      final newSongInfo = await _songInfoService.generateSongInfo(widget.trackData, skipCache: true);
      
      if (mounted && newSongInfo != null) {
        setState(() {
          _currentSongInfo = newSongInfo;
          _isRegenerating = false;
        });
        
        // 停止加载动画
        _pulseController.stop();
        _rotationController.stop();
        _bounceController.stop();
        _shimmerController.stop();

        // 重置并启动信息出现动画
        _infoAnimationController.reset();
        _infoAnimationController.forward();
        
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          Provider.of<NotificationService>(context, listen: false)
              .showSnackBar(l10n.songInfoRegeneratedMessage);
        }
      } else {
        throw Exception('Regeneration failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _regenerationError = e.toString();
          _isRegenerating = false;
        });

        // 停止动画
        _pulseController.stop();
        _rotationController.stop();
        _bounceController.stop();
        _shimmerController.stop();
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _isLoading = false;
      _regenerationError = message;
    });

    // 停止动画
    _pulseController.stop();
    _rotationController.stop();
    _bounceController.stop();
    _shimmerController.stop();

    Provider.of<NotificationService>(context, listen: false)
        .showSnackBar(message);
  }

  void _copyToClipboard(String content, String type) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar('$type ${l10n.copiedToClipboard('content')}');
    }
  }

  void _showFollowUpSheet(BuildContext context) {
    HapticFeedback.mediumImpact();

    final trackName = widget.trackData['name'] as String? ?? 'Unknown Track';
    final artistNames = (widget.trackData['artists'] as List?)
            ?.map((artist) => artist['name'] as String)
            .join(', ') ??
        'Unknown Artist';
    final albumName = widget.trackData['album']?['name'] as String?;

    AIChatSheet.show(
      context: context,
      chatContext: ChatContext(
        type: ChatContextType.songInfo,
        trackTitle: trackName,
        artistName: artistNames,
        albumName: albumName,
        additionalContext: _currentSongInfo,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _bounceController.dispose();
    _shimmerController.dispose();
    _infoAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackName = widget.trackData['name'] as String? ?? 'Unknown Track';
    final artistNames = (widget.trackData['artists'] as List?)
        ?.map((artist) => artist['name'] as String)
        .join(', ') ?? 'Unknown Artist';

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.songInformationTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isLoading && !_isRegenerating)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _regenerateSongInfo,
              tooltip: AppLocalizations.of(context)!.regenerateTooltip,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFollowUpSheet(context),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: Text(AppLocalizations.of(context)!.askGemini),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 歌曲标题卡片 - 统一的封面位置
            _buildHeaderCard(trackName, artistNames),
            
            // 在歌曲标题下方添加波浪线
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isLoading || _isRegenerating 
                ? const AnimatedWavyDivider(
                    height: 10.0,
                    waveHeight: 5.0,
                    waveFrequency: 0.02,
                    animate: true,
                    animationDuration: Duration(seconds: 2), // 从4秒改为2秒，动画更快
                  )
                : const WavyDivider(
                    height: 10.0,
                    waveHeight: 5.0,
                    waveFrequency: 0.02,
                  ),
            ),

            // 错误提示
            if (_regenerationError != null && !_isLoading)
              _buildErrorCard(),

            if (_regenerationError != null && !_isLoading) 
              const SizedBox(height: 16),

            // 主要内容区域
            if (_isLoading || _isRegenerating)
              _buildLoadingContent()
            else if (_currentSongInfo != null)
              ..._buildInfoCards()
            else
              _buildEmptyState(),

            const SizedBox(height: 24),

            // 底部信息
            if (!_isLoading)
              _buildFooter(),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String trackName, String artistNames) {
    final albumName = widget.trackData['album']?['name'] as String?;
    // Build subtitle with artist and album separated by ·
    final subtitle = albumName != null && albumName.isNotEmpty
        ? '$artistNames · $albumName'
        : artistNames;

    return Card(
      elevation: 0,
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 专辑封面 - 缩小尺寸
            _buildAlbumCover(),
            const SizedBox(width: 16),
            // 文字信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trackName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumCover() {
    const double coverSize = 72.0; // Smaller, more refined size

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: SizedBox(
        width: coverSize,
        height: coverSize,
        child: Stack(
          children: [
            // 专辑封面图片
            widget.trackData['album']?['images'] != null &&
                   (widget.trackData['album']['images'] as List).isNotEmpty
                ? Image.network(
                    widget.trackData['album']['images'][0]['url'],
                    fit: BoxFit.cover,
                    width: coverSize,
                    height: coverSize,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 28,
                        ),
                      );
                    },
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                  ),

            // 加载遮罩和动画 - 在加载或重新生成时显示
            if (_isLoading || _isRegenerating)
              Container(
                width: coverSize,
                height: coverSize,
                color: Colors.black.withValues(alpha: 0.6),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulseController, _rotationController]),
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Transform.rotate(
                        angle: _rotationAnimation.value * 2 * 3.14159,
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingContent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48.0),
        child: Column(
          children: [
            // 动态闪烁图标组
            AnimatedBuilder(
              animation: Listenable.merge([
                _pulseController,
                _rotationController,
                _bounceController,
                _shimmerController,
              ]),
              builder: (context, child) {
                return SizedBox(
                  height: 80,
                  width: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 外圈脉冲光环
                      Transform.scale(
                        scale: _pulseAnimation.value * 1.3,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.3 * (1 - (_pulseAnimation.value - 0.85) / 0.3)),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      // 中心旋转图标
                      Transform.translate(
                        offset: Offset(0, -_bounceAnimation.value),
                        child: Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Transform.rotate(
                            angle: _rotationAnimation.value * 2 * 3.14159,
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.tertiary,
                                    Theme.of(context).colorScheme.primary,
                                  ],
                                  stops: [
                                    (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                                    _shimmerAnimation.value.clamp(0.0, 1.0),
                                    (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                                  ],
                                ).createShader(bounds);
                              },
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 42,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 小星星装饰
                      ...List.generate(3, (index) {
                        final angle = (index * 2.0944) + (_rotationAnimation.value * 3.14159);
                        final radius = 30.0 + (_bounceAnimation.value * 0.5);
                        return Positioned(
                          left: 40 + cos(angle) * radius - 6,
                          top: 40 + sin(angle) * radius - 6,
                          child: Transform.scale(
                            scale: 0.5 + (_pulseAnimation.value - 0.85) * 1.5,
                            child: Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 随机幽默文本带渐变动画
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, child) {
                return ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.onSurface,
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.onSurface,
                      ],
                      stops: [
                        (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                        _shimmerAnimation.value.clamp(0.0, 1.0),
                        (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                      ],
                    ).createShader(bounds);
                  },
                  child: Text(
                    _currentFunnyText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 动态进度条
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, child) {
                return SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        LinearProgressIndicator(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        // 闪光效果
                        Positioned.fill(
                          child: ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withValues(alpha: 0.3),
                                  Colors.transparent,
                                ],
                                stops: [
                                  (_shimmerAnimation.value - 0.2).clamp(0.0, 1.0),
                                  _shimmerAnimation.value.clamp(0.0, 1.0),
                                  (_shimmerAnimation.value + 0.2).clamp(0.0, 1.0),
                                ],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.srcATop,
                            child: Container(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // 固定的 Gemini grounding 文本
            Text(
              AppLocalizations.of(context)!.geminiGrounding,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${AppLocalizations.of(context)!.operationFailed}: $_regenerationError',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48.0),
        child: Column(
          children: [
            Icon(
              Icons.info_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noSongInfoAvailable,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Column(
        children: [
          Text(
            AppLocalizations.of(context)!.generatedByGemini,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.poweredByGoogleSearch,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
    BuildContext context, {
    required String title,
    required String content,
    required IconData icon,
    required int animationIndex,
  }) {
    // 确保animationIndex在有效范围内
    final safeIndex = animationIndex.clamp(0, _infoAnimations.length - 1);
    
    return AnimatedBuilder(
      animation: _infoAnimations[safeIndex],
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - _infoAnimations[safeIndex].value)),
          child: Opacity(
            opacity: _infoAnimations[safeIndex].value.clamp(0.0, 1.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () => _copyToClipboard(content, title),
                        tooltip: '${AppLocalizations.of(context)!.copyButtonText} $title',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 28.0),
                    child: Text(
                      content,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildInfoCards() {
    List<Widget> cards = [];
    int animationIndex = 0;

    if (_currentSongInfo!['creation_time'] != null && _currentSongInfo!['creation_time'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: AppLocalizations.of(context)!.creationTimeTitle,
        content: _currentSongInfo!['creation_time'] as String,
        icon: Icons.schedule_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['creation_location'] != null && _currentSongInfo!['creation_location'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: AppLocalizations.of(context)!.creationLocationTitle,
        content: _currentSongInfo!['creation_location'] as String,
        icon: Icons.location_on_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['lyricist'] != null && _currentSongInfo!['lyricist'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: AppLocalizations.of(context)!.lyricistTitle,
        content: _currentSongInfo!['lyricist'] as String,
        icon: Icons.edit_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['composer'] != null && _currentSongInfo!['composer'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: AppLocalizations.of(context)!.composerTitle,
        content: _currentSongInfo!['composer'] as String,
        icon: Icons.music_note_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['producer'] != null && _currentSongInfo!['producer'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: AppLocalizations.of(context)!.producerTitle,
        content: _currentSongInfo!['producer'] as String,
        icon: Icons.settings_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    // 在Song Analysis之前添加波浪线
    if (_currentSongInfo!['review'] != null && _currentSongInfo!['review'] != '') {
      // 添加波浪线分隔符
      cards.add(const Padding(
        padding: EdgeInsets.all(16.0),
        child: WavyDivider(
          height: 10.0,
          waveHeight: 5.0,
          waveFrequency: 0.02,
        ),
      ));
      
      cards.add(_buildInfoSection(
        context,
        title: AppLocalizations.of(context)!.songAnalysisTitle,
        content: _currentSongInfo!['review'] as String,
        icon: Icons.article_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    // 移除最后一个间距
    if (cards.isNotEmpty && cards.last is SizedBox) {
      cards.removeLast();
    }

    return cards;
  }
} 