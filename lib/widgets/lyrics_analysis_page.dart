import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import '../services/lyrics_analysis_service.dart';
import '../widgets/materialui.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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

class _LyricsAnalysisPageState extends State<LyricsAnalysisPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _analysisResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _performAnalysis();
  }

  Future<void> _performAnalysis() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _copyAnalysis() async {
    final l10n = AppLocalizations.of(context)!;
    if (_analysisResult == null) return;

    final fullText = [
      if (_analysisResult!['theme'] != null) '${l10n.lyricsTheme}: ${_analysisResult!['theme']}',
      if (_analysisResult!['emotion'] != null) '${l10n.lyricsEmotion}: ${_analysisResult!['emotion']}',
      if (_analysisResult!['metaphor'] != null) '${l10n.lyricsMetaphor}: ${_analysisResult!['metaphor']}',
      if (_analysisResult!['interpretation'] != null) '${l10n.lyricsInterpretation}: ${_analysisResult!['interpretation']}',
    ].join('\n\n');
    
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
        title: const Text('Lyrics Analysis'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_analysisResult != null)
            IconButton(
              onPressed: _performAnalysis,
              icon: const Icon(Icons.refresh),
              tooltip: 'Regenerate Analysis',
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
                    if (widget.albumCoverUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.albumCoverUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
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
                    else
                      Container(
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

  Widget _buildAnalysisContent() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('分析中...'),
          ],
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
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_analysisResult == null) {
      return const Center(
        child: Text('没有分析结果'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_analysisResult!['theme'] != null) ...[
            _buildAnalysisSection(
              l10n.lyricsTheme,
              _analysisResult!['theme'],
              Icons.lightbulb_outline,
              theme.colorScheme.primary,
            ),
          ],
          if (_analysisResult!['emotion'] != null) ...[
            _buildAnalysisSection(
              l10n.lyricsEmotion,
              _analysisResult!['emotion'],
              Icons.favorite_outline,
              theme.colorScheme.primary,
            ),
          ],
          if (_analysisResult!['metaphor'] != null) ...[
            _buildAnalysisSection(
              l10n.lyricsMetaphor,
              _analysisResult!['metaphor'],
              Icons.psychology_outlined,
              theme.colorScheme.primary,
            ),
          ],
          if (_analysisResult!['interpretation'] != null) ...[
            _buildAnalysisSection(
              l10n.lyricsInterpretation,
              _analysisResult!['interpretation'],
              Icons.insights_outlined,
              theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisSection(String title, String content, IconData icon, Color iconColor) {
    final theme = Theme.of(context);
    
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
        .showSnackBar('$type copied to clipboard');
  }
} 