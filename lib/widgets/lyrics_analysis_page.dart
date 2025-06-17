import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math'; // Added for Random
import '../services/notification_service.dart';
import '../services/lyrics_analysis_service.dart';
import '../widgets/materialui.dart';
import '../l10n/app_localizations.dart';

class LyricsAnalysisPage extends StatefulWidget {
  final String lyrics;
  final String trackTitle;
  final String artistName;
  final String? albumCoverUrl;

  const LyricsAnalysisPage({
    super.key,
    required this.lyrics,
    required this.trackTitle,
    required this.artistName,
    this.albumCoverUrl,
  });

  @override
  State<LyricsAnalysisPage> createState() => _LyricsAnalysisPageState();
}

class _LyricsAnalysisPageState extends State<LyricsAnalysisPage>
    with TickerProviderStateMixin { // Added TickerProviderStateMixin
  bool _isLoading = true;
  Map<String, dynamic>? _analysisResult;
  String? _errorMessage;

  // Animation Controllers
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  // Loading Texts
  late String _currentFunnyText;

  @override
  void initState() {
    super.initState();

    _currentFunnyText = _getRandomFunnyText();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.elasticInOut),
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.elasticInOut),
    );

    _performAnalysis();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  String _getRandomFunnyText() {
    final l10n = AppLocalizations.of(context)!;
    final trackName = widget.trackTitle;
    final artistName = widget.artistName;

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
    if (Random().nextDouble() < 0.6 && trackName.isNotEmpty && artistName.isNotEmpty) {
      return l10n.loadingChatting(artistName);
    } else {
      return staticTexts[Random().nextInt(staticTexts.length)];
    }
  }

  void _startFunnyTextRotation() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isLoading) {
        setState(() {
          _currentFunnyText = _getRandomFunnyText();
        });
        _startFunnyTextRotation();
      }
    });
  }

  void _startVibrationCycle() {
    const vibrationInterval = Duration(milliseconds: 600);
    int vibrationCount = 0;

    void performVibration() {
      if (mounted && _isLoading) {
        if (vibrationCount % 2 == 0) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
        vibrationCount++;
        Future.delayed(vibrationInterval, performVibration);
      }
    }
    performVibration();
  }

  Future<void> _performAnalysis() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentFunnyText = _getRandomFunnyText(); // Update text on new analysis
    });

    _pulseController.repeat(reverse: true);
    _rotationController.repeat(reverse: true);
    _startFunnyTextRotation();
    _startVibrationCycle();

    try {
      final analysisService = LyricsAnalysisService();
      final analysis = await analysisService.analyzeLyrics(
        widget.lyrics,
        widget.trackTitle,
        widget.artistName,
      );

      if (mounted) {
        setState(() {
          _analysisResult = analysis;
          _isLoading = false;
        });
        _pulseController.stop();
        _rotationController.stop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
        _pulseController.stop();
        _rotationController.stop();
      }
    }
  }

  Future<void> _copyAnalysis() async {
    final l10n = AppLocalizations.of(context)!;
    if (_analysisResult == null) return;

    final List<String> contentParts = [];
    
    if (_hasContent(_analysisResult!['metaphor'])) {
      contentParts.add('${l10n.lyricsMetaphor}: ${_analysisResult!['metaphor']}');
    }
    
    if (_hasContent(_analysisResult!['reference'])) {
      contentParts.add('${l10n.lyricsReference}: ${_analysisResult!['reference']}');
    }
    
    if (_hasContent(_analysisResult!['keywords_explanation'])) {
      contentParts.add('${l10n.lyricsKeywordsExplanation}: ${_analysisResult!['keywords_explanation']}');
    }
    
    if (_hasContent(_analysisResult!['interpretation'])) {
      contentParts.add('${l10n.lyricsInterpretation}: ${_analysisResult!['interpretation']}');
    }

    if (contentParts.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noAnalysisResults);
      return;
    }

    final fullText = contentParts.join('\n\n');
    await Clipboard.setData(ClipboardData(text: fullText));
    
    if (mounted) {
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.analysisResultCopied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.lyricsAnalysisTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_analysisResult != null)
            IconButton(
              onPressed: _performAnalysis,
              icon: const Icon(Icons.refresh),
              tooltip: AppLocalizations.of(context)!.regenerateAnalysisTooltip,
            ),
          if (_analysisResult != null && _hasAnyContent())
            IconButton(
              onPressed: _copyAnalysis,
              icon: const Icon(Icons.copy_all),
              tooltip: AppLocalizations.of(context)!.copyAllAnalysisTooltip,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 歌曲信息卡片
            Card(
              elevation: 0,
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildAlbumCoverWithLoadingIndicator(), // Changed
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.trackTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.artistName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 选中的歌词
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              child: Text(
                '"${widget.lyrics}"',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
            
            // 波浪线分隔符
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: _isLoading 
                ? const AnimatedWavyDivider(
                    height: 10.0,
                    waveHeight: 5.0,
                    waveFrequency: 0.02,
                    animate: true,
                    animationDuration: Duration(seconds: 2),
                  )
                : const WavyDivider(
                    height: 10.0,
                    waveHeight: 5.0,
                    waveFrequency: 0.02,
                  ),
            ),
            
            // 分析内容
            _buildAnalysisContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumCoverWithLoadingIndicator() {
    final theme = Theme.of(context);
    
    Widget coverArt = widget.albumCoverUrl != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              widget.albumCoverUrl!,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.music_note,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        : Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.music_note,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          coverArt,
          if (_isLoading)
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([_pulseController, _rotationController]),
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Transform.rotate(
                      angle: _rotationAnimation.value * 2 * 3.14159,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: theme.colorScheme.primary,
                        size: 24, // Adjusted size
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalysisContent() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _currentFunnyText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.geminiGrounding,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.analysisFailed(_errorMessage!),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _performAnalysis,
                child: Text(l10n.retryButton),
              ),
            ],
          ),
        ),
      );
    }

    if (_analysisResult == null) {
      return Center(
        child: Text(l10n.noAnalysisResults),
      );
    }

    // 过滤掉空内容的分析部分
    final List<Widget> analysisWidgets = [];
    
    // 检查每个字段是否有内容
    if (_hasContent(_analysisResult!['metaphor'])) {
      analysisWidgets.add(_buildAnalysisSection(
        l10n.lyricsMetaphor,
        _analysisResult!['metaphor'],
        Icons.psychology_outlined,
        theme.colorScheme.primary,
      ));
    }
    
    if (_hasContent(_analysisResult!['reference'])) {
      analysisWidgets.add(_buildAnalysisSection(
        l10n.lyricsReference,
        _analysisResult!['reference'],
        Icons.format_quote_outlined,
        theme.colorScheme.primary,
      ));
    }
    
    if (_hasContent(_analysisResult!['keywords_explanation'])) {
      analysisWidgets.add(_buildAnalysisSection(
        l10n.lyricsKeywordsExplanation,
        _analysisResult!['keywords_explanation'],
        Icons.info_outline,
        theme.colorScheme.primary,
      ));
    }
    
    if (_hasContent(_analysisResult!['interpretation'])) {
      analysisWidgets.add(_buildAnalysisSection(
        l10n.lyricsInterpretation,
        _analysisResult!['interpretation'],
        Icons.insights_outlined,
        theme.colorScheme.primary,
      ));
    }

    // 如果没有任何有效内容
    if (analysisWidgets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.content_paste_search_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noDeepAnalysisContent,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.simpleContentExplanation,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _performAnalysis,
                child: Text(l10n.reanalyzeButton),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 添加一个说明文字
          if (analysisWidgets.length < 4)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.onlyFoundDimensionsInfo,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ...analysisWidgets,
        ],
      ),
    );
  }

  // 检查内容是否有效（非空且非null）
  bool _hasContent(dynamic content) {
    if (content == null) return false;
    if (content is String) {
      return content.trim().isNotEmpty;
    }
    return false;
  }

  bool _hasAnyContent() {
    if (_analysisResult == null) return false;
    return _hasContent(_analysisResult!['metaphor']) ||
           _hasContent(_analysisResult!['reference']) ||
           _hasContent(_analysisResult!['keywords_explanation']) ||
           _hasContent(_analysisResult!['interpretation']);
  }

  Widget _buildAnalysisSection(String title, String content, IconData icon, Color iconColor) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _copyToClipboard(content, title),
                tooltip: '${l10n.copyButtonText} $title',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28.0),
            child: Text(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String content, String type) {
    Clipboard.setData(ClipboardData(text: content));
    Provider.of<NotificationService>(context, listen: false)
        .showSnackBar('$type ${AppLocalizations.of(context)!.copiedToClipboard}');
  }
} 