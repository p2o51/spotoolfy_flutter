import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:provider/provider.dart';
import 'package:logger/logger.dart'; // Added logger
import 'package:intl/intl.dart'; // Import intl for date formatting
import 'dart:convert'; // Import for JSON operations
import 'dart:math'; // Import for min function
// import '../providers/firestore_provider.dart'; // Keep for homoThoughts for now
import '../providers/local_database_provider.dart'; // Import new provider
import '../providers/spotify_provider.dart';
import '../models/record.dart' as model; // Use prefix to avoid name collision
import 'materialui.dart';
import 'stats_card.dart'; // Import the new StatsCard widget
import '../utils/date_formatter.dart'; // Assuming getLeadingText uses this
import 'package:flutter/cupertino.dart'; // For CupertinoActionSheet
import '../l10n/app_localizations.dart';
import '../services/song_info_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

final logger = Logger(); // Added logger instance

class NotesDisplay extends StatefulWidget {
  const NotesDisplay({super.key});

  @override
  State<NotesDisplay> createState() => _NotesDisplayState();
}

class _NotesDisplayState extends State<NotesDisplay>
    with TickerProviderStateMixin {
  String? _lastFetchedTrackId;
  final SongInfoService _songInfoService = SongInfoService();
  Map<String, dynamic>? _cachedSongInfo;
  bool _isGeneratingAI = false;
  late AnimationController _generateButtonController;
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _generateButtonController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // 初始化动画控制器（参考songinfo页面）
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.elasticInOut,
    ));

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.elasticInOut,
    ));
  }

  @override
  void dispose() {
    _generateButtonController.dispose();
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  // --- AI Content Methods ---

  void _startVibrationCycle() {
    const vibrationInterval = Duration(milliseconds: 600);
    int vibrationCount = 0;

    void performVibration() {
      if (mounted && _isGeneratingAI) {
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

  Future<void> _checkCachedSongInfo(String trackId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_song_info_$trackId';
      final cachedInfoJson = prefs.getString(cacheKey);

      if (cachedInfoJson != null && cachedInfoJson.isNotEmpty) {
        final cachedInfo =
            Map<String, dynamic>.from(jsonDecode(cachedInfoJson));
        if (mounted) {
          setState(() {
            _cachedSongInfo = cachedInfo;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _cachedSongInfo = null;
          });
        }
      }
    } catch (e) {
      logger.e('Error checking cached song info: $e');
      if (mounted) {
        setState(() {
          _cachedSongInfo = null;
        });
      }
    }
  }

  Future<void> _generateAIContent() async {
    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack?['item'];

    if (currentTrack == null || _isGeneratingAI) return;

    // Capture context-dependent values before async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    setState(() {
      _isGeneratingAI = true;
    });

    // Start animations and vibration
    _generateButtonController.repeat();
    _pulseController.repeat(reverse: true);
    _rotationController.repeat(reverse: true);
    _startVibrationCycle();

    try {
      final songInfo = await _songInfoService.generateSongInfo(
        currentTrack,
        skipCache: false,
      );

      if (songInfo != null && mounted) {
        setState(() {
          _cachedSongInfo = songInfo;
        });
      }
    } catch (e) {
      logger.e('Error generating AI content: $e');
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('生成失败: ${e.toString()}'),
            backgroundColor: errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingAI = false;
        });
        _generateButtonController.stop();
        _generateButtonController.reset();
        _pulseController.stop();
        _rotationController.stop();
      }
    }
  }

  Widget _buildAIContentSection(BuildContext context) {
    if (_cachedSongInfo != null && _cachedSongInfo!.isNotEmpty) {
      // 检查是否有ideas - 如果没有就不显示
      bool hasValidContent = false;
      final fieldsToCheck = [
        'creation_time',
        'creation_location',
        'lyricist',
        'composer',
        'producer',
        'review'
      ];
      for (String field in fieldsToCheck) {
        if (_cachedSongInfo![field] != null && _cachedSongInfo![field] != '') {
          hasValidContent = true;
          break;
        }
      }

      if (!hasValidContent) {
        return _buildAIButtonSection(context);
      }

      return Card(
        elevation: 0,
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with IconHeader style from materialui.dart - 居中显示
              Center(
                child: IconHeader(
                  icon: Icons.info_outline,
                  text: AppLocalizations.of(context)!.songInformationTitle,
                ),
              ),
              const SizedBox(height: 8),
              // Info sections in the same order as song info page
              ..._buildAIInfoSections(context),
              const SizedBox(height: 16),
              // 单个按钮区域
              _buildAIButtonSection(context),
            ],
          ),
        ),
      );
    } else {
      return _buildAIButtonSection(context);
    }
  }

  Widget _buildAIButtonSection(BuildContext context) {
    // 确定按钮状态和文字
    late IconData buttonIcon;
    late String buttonText;
    late VoidCallback? onPressed;

    if (_cachedSongInfo != null && _cachedSongInfo!.isNotEmpty) {
      // 已有内容，显示删除按钮
      buttonIcon = Icons.delete_outline;
      buttonText = AppLocalizations.of(context)!.deleteAIContent;
      onPressed = _isGeneratingAI ? null : _deleteAIContent;
    } else if (_isGeneratingAI) {
      // 正在生成，显示加载状态
      buttonIcon = Icons.hourglass_empty;
      buttonText = AppLocalizations.of(context)!.generatingAIContent;
      onPressed = null;
    } else {
      // 没有内容，显示生成按钮
      buttonIcon = Icons.auto_awesome;
      buttonText = AppLocalizations.of(context)!.generateAIContent;
      onPressed = _generateAIContent;
    }

    return Card(
      elevation: 0,
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // 如果没有内容，显示标题 - 居中显示
            if (_cachedSongInfo == null || _cachedSongInfo!.isEmpty) ...[
              Center(
                child: IconHeader(
                  icon: Icons.info_outline,
                  text: AppLocalizations.of(context)!.songInformationTitle,
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 文字单独一行，居中
            Text(
              buttonText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // 按钮在下方居中，大小固定
            Center(
              child: AnimatedBuilder(
                animation:
                    Listenable.merge([_pulseController, _rotationController]),
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isGeneratingAI ? _pulseAnimation.value : 1.0,
                    child: Transform.rotate(
                      angle: _isGeneratingAI
                          ? _rotationAnimation.value * 2 * math.pi
                          : 0.0,
                      child: SizedBox(
                        width: 56, // 固定宽度
                        height: 56, // 固定高度
                        child: IconButton(
                          icon: Icon(
                            buttonIcon,
                            size: 24, // 固定图标大小
                          ),
                          onPressed: onPressed,
                          style: IconButton.styleFrom(
                            backgroundColor: onPressed != null
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.1)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            foregroundColor: onPressed != null
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                            shape: const CircleBorder(), // 圆形按钮
                          ),
                        ),
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

  void _deleteAIContent() {
    setState(() {
      _cachedSongInfo = null;
    });

    // 也从缓存中清除
    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack?['item'];
    if (currentTrack != null) {
      final trackId = currentTrack['id'] as String?;
      if (trackId != null) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.remove('cached_song_info_$trackId');
        });
      }
    }
  }

  List<Widget> _buildAIInfoSections(BuildContext context) {
    List<Widget> sections = [];

    // Same order as song info page
    if (_cachedSongInfo!['creation_time'] != null &&
        _cachedSongInfo!['creation_time'] != '') {
      sections.add(_buildAIInfoSection(
        context,
        title: AppLocalizations.of(context)!.creationTimeTitle,
        content: _cachedSongInfo!['creation_time'] as String,
        icon: Icons.schedule_rounded,
      ));
      sections.add(const SizedBox(height: 4));
    }

    if (_cachedSongInfo!['creation_location'] != null &&
        _cachedSongInfo!['creation_location'] != '') {
      sections.add(_buildAIInfoSection(
        context,
        title: AppLocalizations.of(context)!.creationLocationTitle,
        content: _cachedSongInfo!['creation_location'] as String,
        icon: Icons.location_on_rounded,
      ));
      sections.add(const SizedBox(height: 4));
    }

    if (_cachedSongInfo!['lyricist'] != null &&
        _cachedSongInfo!['lyricist'] != '') {
      sections.add(_buildAIInfoSection(
        context,
        title: AppLocalizations.of(context)!.lyricistTitle,
        content: _cachedSongInfo!['lyricist'] as String,
        icon: Icons.edit_rounded,
      ));
      sections.add(const SizedBox(height: 4));
    }

    if (_cachedSongInfo!['composer'] != null &&
        _cachedSongInfo!['composer'] != '') {
      sections.add(_buildAIInfoSection(
        context,
        title: AppLocalizations.of(context)!.composerTitle,
        content: _cachedSongInfo!['composer'] as String,
        icon: Icons.music_note_rounded,
      ));
      sections.add(const SizedBox(height: 4));
    }

    if (_cachedSongInfo!['producer'] != null &&
        _cachedSongInfo!['producer'] != '') {
      sections.add(_buildAIInfoSection(
        context,
        title: AppLocalizations.of(context)!.producerTitle,
        content: _cachedSongInfo!['producer'] as String,
        icon: Icons.settings_rounded,
      ));
      sections.add(const SizedBox(height: 4));
    }

    // Add Song Analysis at the end if available
    if (_cachedSongInfo!['review'] != null &&
        _cachedSongInfo!['review'] != '') {
      sections.add(_buildAIInfoSection(
        context,
        title: AppLocalizations.of(context)!.songAnalysisTitle,
        content: _cachedSongInfo!['review'] as String,
        icon: Icons.article_rounded,
      ));
      sections.add(const SizedBox(height: 4));
    }

    // Remove last spacing
    if (sections.isNotEmpty && sections.last is SizedBox) {
      sections.removeLast();
    }

    return sections;
  }

  Widget _buildAIInfoSection(
    BuildContext context, {
    required String title,
    required String content,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () => _copyAIContent(content, title),
                tooltip:
                    '${AppLocalizations.of(context)!.copyButtonText} $title',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }

  void _copyAIContent(String content, String type) {
    Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$type ${AppLocalizations.of(context)!.copiedToClipboard('content')}'),
        ),
      );
    }
  }

  // --- Helper Methods for Edit/Delete ---

  void _showActionSheetForRecord(BuildContext context, model.Record record) {
    // Remove unused variable
    final recordId = record.id;
    final trackId = record.trackId;
    final songTimestampMs = record.songTimestampMs; // 获取时间戳
    // 获取 SpotifyProvider
    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);

    if (recordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.incompleteRecordError)),
      );
      return;
    }

    // 格式化时间戳 (如果存在)
    String formattedTimestamp = '';
    if (songTimestampMs != null && songTimestampMs > 0) {
      final duration = Duration(milliseconds: songTimestampMs);
      final minutes =
          duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds =
          duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      formattedTimestamp = '$minutes:$seconds';
    }

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return CupertinoActionSheet(
          title: Text(AppLocalizations.of(context)!.optionsTitle),
          actions: <CupertinoActionSheetAction>[
            // 新增：从指定时间播放
            if (songTimestampMs != null && songTimestampMs > 0)
              CupertinoActionSheetAction(
                child: Text(AppLocalizations.of(context)!
                    .playFromTimestamp(formattedTimestamp)),
                onPressed: () async {
                  Navigator.pop(bottomSheetContext);
                  final trackUri = 'spotify:track:$trackId';
                  logger.i(
                      'Attempting to play URI: $trackUri from $songTimestampMs ms');
                  try {
                    await spotifyProvider.playTrack(trackUri: trackUri);
                    final duration = Duration(milliseconds: songTimestampMs);
                    await spotifyProvider
                        .seekToPosition(duration.inMilliseconds);
                  } catch (e) {
                    logger.e('Error calling playTrack or seekToPosition: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context)!
                              .playbackFailed(e.toString())),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              ),
            CupertinoActionSheetAction(
              child: Text(AppLocalizations.of(context)!.editNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _showEditDialogForRecord(context, record);
              },
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              child: Text(AppLocalizations.of(context)!.deleteNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _confirmDeleteRecordForRecord(context, recordId, trackId);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: Text(AppLocalizations.of(context)!.cancel),
            onPressed: () => Navigator.pop(bottomSheetContext),
          ),
        );
      },
    );
  }

  void _showActionSheetForRelatedRecord(
      BuildContext context, Map<String, dynamic> record) {
    // 对于相关记录，确保从 map 中获取 id, trackId, 和 songTimestampMs
    final recordId = record['id'] as int?;
    final trackId = record['trackId'] as String?;
    final songTimestampMs = record['songTimestampMs'] as int?; // 获取时间戳
    // 获取 SpotifyProvider
    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);

    if (recordId == null || trackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cannot proceed: Incomplete record information')),
      );
      return;
    }

    // 格式化时间戳 (如果存在)
    String formattedTimestamp = '';
    if (songTimestampMs != null && songTimestampMs > 0) {
      final duration = Duration(milliseconds: songTimestampMs);
      final minutes =
          duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds =
          duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      formattedTimestamp = '$minutes:$seconds';
    }

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return CupertinoActionSheet(
          title: Text(record['trackName'] ?? 'Options'),
          actions: <CupertinoActionSheetAction>[
            // 新增：从指定时间播放
            if (songTimestampMs != null && songTimestampMs > 0)
              CupertinoActionSheetAction(
                child: Text(AppLocalizations.of(context)!
                    .playFromTimestamp(formattedTimestamp)),
                onPressed: () async {
                  Navigator.pop(bottomSheetContext);
                  final trackUri = 'spotify:track:$trackId';
                  logger.i(
                      'Attempting to play URI: $trackUri from $songTimestampMs ms');
                  try {
                    await spotifyProvider.playTrack(trackUri: trackUri);
                    final duration = Duration(milliseconds: songTimestampMs);
                    await spotifyProvider
                        .seekToPosition(duration.inMilliseconds);
                  } catch (e) {
                    logger.e('Error calling playTrack or seekToPosition: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context)!
                              .playbackFailed(e.toString())),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              ),
            CupertinoActionSheetAction(
              child: Text(AppLocalizations.of(context)!.editNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _showEditDialogForRelatedRecord(context, record);
              },
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              child: Text(AppLocalizations.of(context)!.deleteNote),
              onPressed: () {
                Navigator.pop(bottomSheetContext);
                _confirmDeleteRecordForRelatedRecord(
                    context, recordId, trackId);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: Text(AppLocalizations.of(context)!.cancel),
            onPressed: () => Navigator.pop(bottomSheetContext),
          ),
        );
      },
    );
  }

  void _showEditDialogForRecord(BuildContext context, model.Record record) {
    final localDbProvider =
        Provider.of<LocalDatabaseProvider>(context, listen: false);
    final recordId = record.id!; // 我们在上面检查过了
    final trackId = record.trackId;
    final initialContent = record.noteContent ?? '';
    final initialRating = record.rating ?? 3; // 默认值为 3

    final TextEditingController textController =
        TextEditingController(text: initialContent);
    int selectedRating = initialRating;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.editNote),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: null,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.noteContent,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(
                            value: 0, icon: Icon(Icons.thumb_down_outlined)),
                        ButtonSegment<int>(
                            value: 3,
                            icon: Icon(Icons.sentiment_neutral_rounded)),
                        ButtonSegment<int>(
                            value: 5, icon: Icon(Icons.whatshot_outlined)),
                      ],
                      selected: {selectedRating},
                      onSelectionChanged: (Set<int> newSelection) {
                        setDialogState(() {
                          selectedRating = newSelection.first;
                        });
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(AppLocalizations.of(context)!.cancel),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
                TextButton(
                  child: Text(AppLocalizations.of(context)!.saveChanges),
                  onPressed: () {
                    localDbProvider.updateRecord(
                      recordId: recordId,
                      trackId: trackId,
                      newNoteContent: textController.text.trim(),
                      newRating: selectedRating,
                    );
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDialogForRelatedRecord(
      BuildContext context, Map<String, dynamic> record) {
    final localDbProvider =
        Provider.of<LocalDatabaseProvider>(context, listen: false);
    final recordId = record['id'] as int;
    final trackId = record['trackId'] as String;
    final initialContent = record['noteContent'] as String? ?? '';

    // 处理从旧数据格式中可能的字符串评分
    dynamic initialRatingRaw = record['rating'];
    int initialRating = 3; // 默认值
    if (initialRatingRaw is int) {
      initialRating = initialRatingRaw;
    } else if (initialRatingRaw is String) {
      initialRating = 3; // 对编辑来说，将旧数据格式的字符串视为默认值 3
    }

    final TextEditingController textController =
        TextEditingController(text: initialContent);
    int selectedRating = initialRating;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.editNote),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: null,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.noteContent,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(
                            value: 0, icon: Icon(Icons.thumb_down_outlined)),
                        ButtonSegment<int>(
                            value: 3,
                            icon: Icon(Icons.sentiment_neutral_rounded)),
                        ButtonSegment<int>(
                            value: 5, icon: Icon(Icons.whatshot_outlined)),
                      ],
                      selected: {selectedRating},
                      onSelectionChanged: (Set<int> newSelection) {
                        setDialogState(() {
                          selectedRating = newSelection.first;
                        });
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(AppLocalizations.of(context)!.cancel),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
                TextButton(
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                  onPressed: () {
                    localDbProvider.updateRecord(
                      recordId: recordId,
                      trackId: trackId,
                      newNoteContent: textController.text.trim(),
                      newRating: selectedRating,
                    );
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteRecordForRecord(
      BuildContext context, int recordId, String trackId) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.confirmDelete),
          content: Text(AppLocalizations.of(context)!.deleteConfirmMessage),
          actions: [
            TextButton(
              child: Text(AppLocalizations.of(context)!.cancel),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              child: Text(AppLocalizations.of(context)!.deleteNote),
              onPressed: () {
                Provider.of<LocalDatabaseProvider>(context, listen: false)
                    .deleteRecord(
                  recordId: recordId,
                  trackId: trackId,
                );
                Navigator.pop(dialogContext);
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteRecordForRelatedRecord(
      BuildContext context, int recordId, String trackId) {
    // 对于关联记录的删除确认，我们可以重用相同的逻辑
    _confirmDeleteRecordForRecord(context, recordId, trackId);
  }

  // --- Helper Functions for StatsCard Data ---

  Map<String, String> _formatTimeAgo(BuildContext context, int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inDays > 0) {
      return {
        'value': difference.inDays.toString(),
        'unit': AppLocalizations.of(context)!.daysAgo
      };
    } else if (difference.inHours > 0) {
      return {
        'value': difference.inHours.toString(),
        'unit': AppLocalizations.of(context)!.hoursAgo
      };
    } else if (difference.inMinutes > 0) {
      return {
        'value': difference.inMinutes.toString(),
        'unit': AppLocalizations.of(context)!.minsAgo
      };
    } else {
      return {
        'value': difference.inSeconds.toString(),
        'unit': AppLocalizations.of(context)!.secsAgo
      };
    }
  }

  Map<String, String> _formatLastPlayed(BuildContext context, int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateToFormat = DateTime(dt.year, dt.month, dt.day);

    String line1;
    if (dateToFormat == today) {
      line1 = '${AppLocalizations.of(context)!.today},';
    } else if (dateToFormat == yesterday) {
      line1 = '${AppLocalizations.of(context)!.yesterday},';
    } else {
      line1 = DateFormat.yMd().format(dt); // Format as date if older
    }

    final line2 = DateFormat.Hm().format(dt); // HH:mm format

    return {'line1': line1, 'line2': line2};
  }

  IconData _getTrendIcon(List<model.Record> records) {
    if (records.length < 2) {
      return Icons.horizontal_rule;
    }
    // Records are typically sorted newest first
    final latestRating = records[0].rating ?? 3; // Default to neutral if null
    final previousRating = records[1].rating ?? 3; // Default to neutral if null

    if (latestRating > previousRating) {
      return Icons.arrow_outward;
    } else if (latestRating < previousRating) {
      return Icons.arrow_downward;
    } else {
      return Icons.horizontal_rule;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Remove FirestoreProvider if no longer needed after this change
    // final firestoreProvider = Provider.of<FirestoreProvider>(context);
    final localDbProvider = context.watch<LocalDatabaseProvider>();
    final currentTrackId = context.select<SpotifyProvider, String?>(
      (provider) => provider.currentTrack?['item']?['id'] as String?,
    );
    final spotifyProvider = context.read<SpotifyProvider>();
    final currentTrack = spotifyProvider.currentTrack?['item'];
    final currentTrackName = currentTrack?['name'] as String?; // Get track name

    // Fetch records and related records if track changed
    if (currentTrackId != null && currentTrackId != _lastFetchedTrackId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          logger.d(
              'NotesDisplay: Track changed, fetching records for $currentTrackId');
          // Assuming fetchRecordsForTrack also fetches latestPlayedAt
          localDbProvider.fetchRecordsForTrack(currentTrackId);
          // Also fetch related records
          if (currentTrackName != null) {
            logger.d(
                'NotesDisplay: Fetching related records for "$currentTrackName"');
            localDbProvider.fetchRelatedRecords(
                currentTrackId, currentTrackName);
          }
          // Check for cached AI content
          _checkCachedSongInfo(currentTrackId);
          setState(() {
            _lastFetchedTrackId = currentTrackId;
          });
        }
      });
    } else if (currentTrackId == null && _lastFetchedTrackId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          logger.d(
              'NotesDisplay: Track is null, clearing last fetched ID and related records');
          // Clear related records when track becomes null
          // Assuming clearRelatedRecords also clears latestPlayedAt
          localDbProvider.clearRelatedRecords();
          setState(() {
            _lastFetchedTrackId = null;
            _cachedSongInfo = null; // Clear cached AI content
          });
        }
      });
    }

    // --- Prepare data for StatsCard ---
    String firstRecordedValue = '-';
    String firstRecordedUnit = '';
    String lastPlayedLine1 = '-';
    String lastPlayedLine2 = '';
    IconData trendIcon = Icons.horizontal_rule; // Default icon
    IconData latestRatingIcon =
        Icons.horizontal_rule; // 修改：默认最新评级图标为 horizontal_rule

    final records = localDbProvider.currentTrackRecords;
    // Placeholder for latestPlayedAt - NEEDS TO BE IMPLEMENTED IN PROVIDER
    final latestPlayedTimestamp = localDbProvider.currentTrackLatestPlayedAt;
    // final latestPlayedTimestamp = records.isNotEmpty ? records.first.recordedAt : null; // Temporary fallback

    if (records.isNotEmpty) {
      // First Recorded
      final earliestRecordTimestamp =
          records.map((r) => r.recordedAt).reduce(min);
      final firstRecordedMap = _formatTimeAgo(context, earliestRecordTimestamp);
      firstRecordedValue = firstRecordedMap['value']!;
      firstRecordedUnit = firstRecordedMap['unit']!;

      // Trend Icon
      trendIcon = _getTrendIcon(records);

      // --- 新增：获取最新评级图标 ---
      final latestRating = records.first.rating; // Records sorted newest first
      switch (latestRating) {
        case 0:
          latestRatingIcon = Icons.thumb_down_outlined;
          break;
        case 5:
          latestRatingIcon = Icons.whatshot_outlined;
          break;
        case 3:
        default:
          latestRatingIcon = Icons.sentiment_neutral_rounded;
          break;
      }
      // --- 结束获取最新评级图标 ---
    }

    if (latestPlayedTimestamp != null) {
      // Last Played At
      final lastPlayedMap = _formatLastPlayed(context, latestPlayedTimestamp);
      lastPlayedLine1 = lastPlayedMap['line1']!;
      lastPlayedLine2 = lastPlayedMap['line2']!;
    } else if (records.isNotEmpty) {
      // Fallback: Use latest record time if latestPlayedAt is unavailable
      final lastPlayedMap = _formatLastPlayed(
          context, records.first.recordedAt); // Use latest record time
      lastPlayedLine1 = lastPlayedMap['line1']!;
      lastPlayedLine2 = lastPlayedMap['line2']!;
    }

    // Helper for current track thoughts (using model.Record)
    String getCurrentThoughtLeading(List<model.Record> records, int index) {
      if (index == records.length - 1) return '初';
      final dt = DateTime.fromMillisecondsSinceEpoch(records[index].recordedAt);
      // Format DateTime to ISO 8601 String for getLeadingText
      return getLeadingText(dt.toIso8601String());
    }

    // Helper for related thoughts (using Map from Local DB)
    String getRelatedThoughtLeading(
        List<Map<String, dynamic>> records, int index) {
      if (index == records.length - 1) return '初';
      final recordedAtTimestamp = records[index]['recordedAt'] as int?;
      if (recordedAtTimestamp != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(recordedAtTimestamp);
        return getLeadingText(dt.toIso8601String());
      }
      return '?';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Conditionally display StatsCard only when a track is playing
          if (currentTrackId != null)
            StatsCard(
              firstRecordedValue: firstRecordedValue,
              firstRecordedUnit: firstRecordedUnit,
              trendIcon: trendIcon,
              latestRatingIcon: latestRatingIcon,
              lastPlayedLine1: lastPlayedLine1,
              lastPlayedLine2: lastPlayedLine2,
            ),
          // 只有在有笔记时才显示 thoughts 部分
          if (currentTrackId != null &&
              localDbProvider.currentTrackRecords.isNotEmpty) ...[
            // Add spacing only if StatsCard is shown
            const SizedBox(height: 16),
            IconHeader(
              icon: Icons.comment_bank_outlined,
              text: AppLocalizations.of(context)!.thoughts,
            ),
            Card(
              elevation: 0,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha((255 * 0.3).round()),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: localDbProvider.currentTrackRecords.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final record = localDbProvider.currentTrackRecords[index];
                  // Determine the icon based on the integer rating
                  IconData ratingIcon;
                  switch (record.rating) {
                    case 0:
                      ratingIcon = Icons.thumb_down_outlined;
                      break;
                    case 5:
                      ratingIcon = Icons.whatshot_outlined;
                      break;
                    case 3:
                    default:
                      ratingIcon = Icons.sentiment_neutral_rounded;
                      break;
                  }

                  // 为 ListTile 添加长按功能
                  return InkWell(
                    onLongPress: () =>
                        _showActionSheetForRecord(context, record),
                    // 使 InkWell 占据整个宽度，以便长按事件更容易触发
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          getCurrentThoughtLeading(
                            localDbProvider.currentTrackRecords,
                            index,
                          ),
                        ),
                      ),
                      title: Text(
                        // Check if note content is empty
                        (record.noteContent?.isEmpty ?? true)
                            ? AppLocalizations.of(context)!.ratedStatus
                            : record.noteContent!,
                        style: (record.noteContent?.isEmpty ?? true)
                            ? TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)
                            : const TextStyle(fontSize: 16, height: 1.05),
                      ),
                      // Add the rating icon as the trailing widget
                      trailing: Icon(ratingIcon,
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  );
                },
              ),
            ),
          ],
          // --- RELATED THOUGHTS (Use LocalDatabaseProvider) ---
          // Show loading indicator if fetching related records
          if (localDbProvider.isLoadingRelated)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          // Show related thoughts only if not loading and list is not empty
          else if (localDbProvider.relatedRecords.isNotEmpty) ...[
            const SizedBox(height: 16),
            IconHeader(
              icon: Icons.library_music_outlined,
              text: AppLocalizations.of(context)!.relatedThoughts,
            ),
            Card(
              elevation: 0,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha((255 * 0.3).round()),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Use relatedRecords from LocalDatabaseProvider
                itemCount: localDbProvider.relatedRecords.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  // Access data from the map
                  final relatedRecord = localDbProvider.relatedRecords[index];
                  // Determine the icon based on the integer rating from the map
                  IconData relatedRatingIcon;
                  final int? ratingValue = relatedRecord['rating'] as int?;
                  switch (ratingValue) {
                    case 0:
                      relatedRatingIcon = Icons.thumb_down_outlined;
                      break;
                    case 5:
                      relatedRatingIcon = Icons.whatshot_outlined;
                      break;
                    case 3:
                    default:
                      relatedRatingIcon = Icons.sentiment_neutral_rounded;
                      break;
                  }

                  // 为相关记录的 ListTile 添加长按功能
                  return InkWell(
                    onLongPress: () => _showActionSheetForRelatedRecord(
                        context, relatedRecord),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          // Use the correct helper function
                          getRelatedThoughtLeading(
                            localDbProvider.relatedRecords,
                            index,
                          ),
                        ),
                      ),
                      title: Text(
                        // Check if related note content is empty
                        (relatedRecord['noteContent'] as String?)?.isEmpty ??
                                true
                            ? AppLocalizations.of(context)!.ratedStatus
                            : relatedRecord['noteContent'] as String,
                        style: (relatedRecord['noteContent'] as String?)
                                    ?.isEmpty ??
                                true
                            ? TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)
                            : const TextStyle(fontSize: 16, height: 1.05),
                      ),
                      subtitle: Text(
                        // Access track/artist name from map
                        '[0m${relatedRecord['artistName'] ?? AppLocalizations.of(context)!.unknownArtist} - ${relatedRecord['trackName'] ?? AppLocalizations.of(context)!.unknownTrack}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      // Add the rating icon as the trailing widget for related records
                      trailing: Icon(relatedRatingIcon,
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  );
                },
              ),
            ),
          ],
          // --- AI Content Section ---
          if (currentTrackId != null) ...[
            const SizedBox(height: 16),
            _buildAIContentSection(context),
          ],
        ],
      ),
    );
  }
}
