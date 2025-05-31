import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../services/song_info_service.dart';
import '../services/notification_service.dart';
import '../widgets/materialui.dart';

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
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;
  
  // 信息出现动画控制器
  late AnimationController _infoAnimationController;
  late List<Animation<double>> _infoAnimations;
  
  String _loadingText = 'Analyzing song information...';
  int _dotCount = 0;
  
  // 幽默的英文加载文本列表
  final List<String> _funnyLoadingTexts = [
    'Teaching Gemini to appreciate good music...',
    'Consulting the music gods...',
    'Decoding musical DNA...',
    'Asking Spotify for gossip...',
    'Summoning the rhythm spirits...',
    'Translating beats into wisdom...',
    'Downloading musical memories...',
    'Celebrating the breakup...',
    'Analyzing sonic fingerprints...',
    'Channeling the artist\'s soul...',
    'Extracting melody secrets...',
    'Interviewing the instruments...',
    'Reading between the notes...',
    'Diving into the sound waves...',
    'Unlocking harmonic mysteries...',
    'Searching the musical universe...',
    '365 partying...',
    'Deciphering lyrical codes...',
    'Awakening dormant frequencies...',
    'Exploring temporal soundscapes...',
    'Gathering acoustic intelligence...',
    'Scanning musical dimensions...',
    'Harvesting sonic data...',
    'Communicating with vinyl spirits...',
    'Investigating melodic patterns...',
    'Calibrating emotional resonance...',
  ];

  // 包含歌曲信息的动态文本模板
  final List<String> _dynamicTextTemplates = [
    'Having a chat with {artist}...',
    'Asking {artist} about "{song}"...',
    'Getting the inside scoop on "{song}"...',
    'Interviewing {artist} backstage...',
    'Decoding {artist}\'s creative process...',
    'Exploring the story behind "{song}"...',
    'Channeling {artist}\'s inspiration...',
    'Diving into {artist}\'s musical mind...',
    'Uncovering "{song}" secrets...',
    'Learning from {artist}\'s experience...',
    'Analyzing {artist}\'s artistic vision...',
    'Discovering "{song}" hidden meanings...',
  ];
  
  late String _currentFunnyText;

  String _getRandomFunnyText() {
    final trackName = widget.trackData['name'] as String? ?? 'Unknown Track';
    final artistNames = (widget.trackData['artists'] as List?)
        ?.map((artist) => artist['name'] as String)
        .join(', ') ?? 'Unknown Artist';

    // 60% 概率使用动态文本，40% 概率使用静态文本
    if (Random().nextDouble() < 0.6 && trackName != 'Unknown Track' && artistNames != 'Unknown Artist') {
      final template = _dynamicTextTemplates[Random().nextInt(_dynamicTextTemplates.length)];
      return template
          .replaceAll('{artist}', artistNames)
          .replaceAll('{song}', trackName);
    } else {
      return _funnyLoadingTexts[Random().nextInt(_funnyLoadingTexts.length)];
    }
  }

  @override
  void initState() {
    super.initState();
    
    // 随机选择一个幽默文本
    _currentFunnyText = _getRandomFunnyText();
    
    // 初始化动画控制器
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000), // 延长脉冲时间让弹性效果更明显
      vsync: this,
    );
    
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 1800), // 加快旋转速度，1.8秒一圈
      vsync: this,
    );
    
    // 信息出现动画控制器
    _infoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200), // 总动画时长1.2秒
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.elasticInOut, // 脉冲也使用弹性效果
    ));
    
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5, // 修改为0.5，一次只转半圈（180度）
    ).animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.elasticInOut, // 使用弹性曲线，更夸张的弹跳效果
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

    // 如果有初始数据，直接使用；否则开始加载
    if (widget.initialSongInfo != null) {
      _currentSongInfo = widget.initialSongInfo;
      // 延迟启动动画，让页面先渲染
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _infoAnimationController.forward();
      });
    } else {
      _loadSongInfo();
    }
  }

  void _startLoadingTextAnimation() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _isLoading) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4;
          _loadingText = 'Analyzing song information${'.' * _dotCount}';
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
    // 图标旋转半圈是1.8秒，三个振动一循环，所以每个振动间隔约600毫秒
    const vibrationInterval = Duration(milliseconds: 600);
    int vibrationCount = 0;
    
    void performVibration() {
      if (mounted && (_isLoading || _isRegenerating)) {
        // 强弱强弱的交替模式
        if (vibrationCount % 2 == 0) {
          HapticFeedback.mediumImpact(); // 强振动
        } else {
          HapticFeedback.lightImpact();  // 弱振动
        }
        
        vibrationCount++;
        Future.delayed(vibrationInterval, performVibration);
      }
    }
    
    performVibration();
  }

  Future<void> _loadSongInfo() async {
    setState(() {
      _isLoading = true;
      _regenerationError = null;
      // 每次加载时随机选择新的幽默文本
      _currentFunnyText = _getRandomFunnyText();
    });

    // 启动动画
    _pulseController.repeat(reverse: true);
    _rotationController.repeat(reverse: true);
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
        
        // 启动信息出现动画
        _infoAnimationController.forward();
      } else {
        _showError('Unable to get song information');
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to get song information: ${e.toString()}');
      }
    }
  }

  // 重新生成歌曲信息
  Future<void> _regenerateSongInfo() async {
    if (_isRegenerating || _isLoading) return;

    setState(() {
      _isRegenerating = true;
      _regenerationError = null;
      // 重新生成时也随机选择新的幽默文本
      _currentFunnyText = _getRandomFunnyText();
    });

    // 启动动画和文本轮换
    _pulseController.repeat(reverse: true);
    _rotationController.repeat(reverse: true);
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
        
        // 重置并启动信息出现动画
        _infoAnimationController.reset();
        _infoAnimationController.forward();
        
        if (mounted) {
          Provider.of<NotificationService>(context, listen: false)
              .showSnackBar('Song information regenerated');
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
    
    Provider.of<NotificationService>(context, listen: false)
        .showSnackBar(message);
  }

  void _copyToClipboard(String content, String type) {
    Clipboard.setData(ClipboardData(text: content));
    Provider.of<NotificationService>(context, listen: false)
        .showSnackBar('$type copied to clipboard');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
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
        title: const Text('Song Information'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isLoading && !_isRegenerating) // 只有在非加载和非重新生成状态下才显示刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _regenerateSongInfo,
              tooltip: 'Regenerate',
            ),
        ],
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
    return Card(
      elevation: 0,
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 专辑封面 - 统一位置，根据状态显示不同效果
            _buildAlbumCover(),
            const SizedBox(width: 16),
            // 文字信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trackName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artistNames,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  if (widget.trackData['album']?['name'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.trackData['album']['name'],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumCover() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: SizedBox(
        width: 100,
        height: 100,
        child: Stack(
          children: [
            // 专辑封面图片
            widget.trackData['album']?['images'] != null &&
                   (widget.trackData['album']['images'] as List).isNotEmpty
                ? Image.network(
                    widget.trackData['album']['images'][0]['url'],
                    fit: BoxFit.cover,
                    width: 100,
                    height: 100,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 40,
                        ),
                      );
                    },
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 40,
                    ),
                  ),
            
            // 加载遮罩和动画 - 在加载或重新生成时显示
            if (_isLoading || _isRegenerating)
              Container(
                width: 100,
                height: 100,
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
                          size: 32,
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
            // 随机幽默文本
            Text(
              _currentFunnyText,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 24),
            
            // 进度指示器
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 固定的 Gemini grounding 文本
            Text(
              "Gemini's grounding...",
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
                'Regeneration failed: $_regenerationError',
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
              'No song information available',
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
            'Generated by Gemini 2.5 Flash',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Powered by Google Search Grounding',
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
                        tooltip: 'Copy $title',
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
        title: 'Creation Time',
        content: _currentSongInfo!['creation_time'] as String,
        icon: Icons.schedule_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['creation_location'] != null && _currentSongInfo!['creation_location'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: 'Creation Location',
        content: _currentSongInfo!['creation_location'] as String,
        icon: Icons.location_on_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['lyricist'] != null && _currentSongInfo!['lyricist'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: 'Lyricist',
        content: _currentSongInfo!['lyricist'] as String,
        icon: Icons.edit_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['composer'] != null && _currentSongInfo!['composer'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: 'Composer',
        content: _currentSongInfo!['composer'] as String,
        icon: Icons.music_note_rounded,
        animationIndex: animationIndex++,
      ));
      cards.add(const SizedBox(height: 8));
    }

    if (_currentSongInfo!['producer'] != null && _currentSongInfo!['producer'] != '') {
      cards.add(_buildInfoSection(
        context,
        title: 'Producer',
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
        title: 'Song Analysis',
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