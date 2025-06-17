import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart'; // 确保导入
// import 'package:share_plus/share_plus.dart'; // Removed unused import
import '../services/notification_service.dart';
import '../services/lyrics_poster_service.dart';
import '../l10n/app_localizations.dart';

class LyricsPosterPreviewPage extends StatefulWidget {
  final String lyrics;
  final String trackTitle;
  final String artistName;
  final String? albumCoverUrl;

  const LyricsPosterPreviewPage({
    super.key,
    required this.lyrics,
    required this.trackTitle,
    required this.artistName,
    this.albumCoverUrl,
  });

  @override
  State<LyricsPosterPreviewPage> createState() => _LyricsPosterPreviewPageState();
}

class _LyricsPosterPreviewPageState extends State<LyricsPosterPreviewPage> {
  bool _isLoading = true;
  bool _isOperating = false; // 保存或分享操作中
  Uint8List? _posterBytes; // Store image bytes directly
  String? _tempFilePath; // Store temporary file path for sharing
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // _generatePoster is called after the first frame is built, to have access to Theme
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _generatePoster();
      }
    });
  }

  Future<void> _generatePoster() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    // 获取主题字体或指定默认字体
    final String? uiFontFamily = theme.textTheme.bodyMedium?.fontFamily ?? 'Montserrat'; // Default to Montserrat if not found

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _posterBytes = null;
      _tempFilePath = null;
    });

    try {
      final posterService = LyricsPosterService();
      final bytes = await posterService.generatePosterData(
        lyrics: widget.lyrics,
        trackTitle: widget.trackTitle,
        artistName: widget.artistName,
        albumCoverUrl: widget.albumCoverUrl,
        // 根据新的设计要求更新颜色配置
        backgroundColor: theme.colorScheme.onPrimaryContainer, // 背景为onPrimaryContainer颜色
        titleColor: theme.colorScheme.primaryContainer, // 歌曲标题为primaryContainer颜色
        artistColor: theme.colorScheme.primary, // 歌手为primary颜色
        lyricsColor: theme.colorScheme.primaryContainer, // 歌词为primaryContainer颜色
        watermarkColor: theme.colorScheme.primary, // 脚注为primary颜色
        separatorColor: theme.colorScheme.outline.withAlpha((0.3 * 255).round()),
        fontFamily: uiFontFamily, // 传递字体族
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = 'lyrics_poster_preview_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _posterBytes = bytes;
          _tempFilePath = file.path;
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

  Future<void> _savePoster() async {
    if (_posterBytes == null || _isOperating) return;

    // final l10n = AppLocalizations.of(context); // Kept for context if needed later
    setState(() { _isOperating = true; });

    try {
      final posterService = LyricsPosterService();
      await posterService.savePosterFromBytes(_posterBytes!, widget.trackTitle);
      
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showSnackBar(AppLocalizations.of(context)!.exportSuccess);
      }
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar('${AppLocalizations.of(context)!.operationFailed}: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() { _isOperating = false; });
      }
    }
  }

  Future<void> _sharePoster() async {
    if (_tempFilePath == null || _isOperating) return;
    
    // final l10n = AppLocalizations.of(context); // Kept for context if needed later
    setState(() { _isOperating = true; });

    try {
      final posterService = LyricsPosterService();
      await posterService.sharePosterFile(
        _tempFilePath!,
        '${widget.trackTitle} - ${widget.artistName}\n\n${widget.lyrics}',
      );
    } catch (e) {
      if (mounted) {
        Provider.of<NotificationService>(context, listen: false)
            .showErrorSnackBar('${AppLocalizations.of(context)!.operationFailed}: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() { _isOperating = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context); // Keep for parts that work in _buildPosterContent
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.sharePoster),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _buildPosterContent(theme, l10n), // Pass l10n
              ),
            ),
          ),
          
          if (!_isLoading && _posterBytes != null)
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withAlpha((0.2 * 255).round()), // Corrected deprecated member use
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _isOperating ? null : _savePoster,
                      icon: const Icon(Icons.download),
                      label: Text(AppLocalizations.of(context)!.saveChanges),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isOperating ? null : _sharePoster,
                      icon: const Icon(Icons.share),
                      label: Text(AppLocalizations.of(context)!.sharePoster),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPosterContent(ThemeData theme, AppLocalizations? l10n) {
    if (_isLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.loadingGenerating,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.posterGenerationFailed(_errorMessage!),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _generatePoster,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context)!.retryButton),
          ),
        ],
      );
    }

    if (_posterBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _posterBytes!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Column(
            children: [
              Icon(
                Icons.broken_image,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.lyricsFailedToLoad,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
} 