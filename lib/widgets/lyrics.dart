import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/lyrics_translation_error.dart';
import '../models/track.dart';
import '../models/translation.dart';
import '../models/translation_load_result.dart';
import '../providers/local_database_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/lyrics_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/translation_service.dart';
import '../utils/lyric_timing_utils.dart';
import '../utils/responsive.dart';
import '../utils/structured_translation.dart';
import 'lyrics_search_page.dart';
import 'lyrics_selection_page.dart';
import 'translation_result_page.dart';

class LyricLine {
  final Duration timestamp;
  final String text;
  String? translation;

  LyricLine(this.timestamp, this.text, {this.translation});
}

class LyricsWidget extends StatefulWidget {
  const LyricsWidget({super.key});

  @override
  State<LyricsWidget> createState() => _LyricsWidgetState();
}

class _LyricsWidgetState extends State<LyricsWidget>
    with AutomaticKeepAliveClientMixin<LyricsWidget> {
  List<LyricLine> _lyrics = [];
  final LyricsService _lyricsService = LyricsService();
  final TranslationService _translationService = TranslationService();
  final SettingsService _settingsService = SettingsService();
  String? _lastTrackId;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listViewKey = GlobalKey();
  bool _autoScroll = true;
  bool _isCopyLyricsMode = false;
  PlayMode? _previousPlayMode;
  int _previousLineIndex = -1; // Track last scrolled line
  bool _isTranslationLoading = false;
  bool _translationsVisible = false;
  bool _autoTranslationRequestedForTrack = false;
  final List<GlobalKey> _lineKeys = [];
  int? _pendingScrollIndex;
  TranslationStyle? _activeTranslationStyle;
  int? _lastFallbackIndexAttempted;
  int _fallbackAttemptsForCurrentIndex = 0;
  int? _currentTrackDurationMs;
  bool _temporarilyIgnoreUserScroll = false;
  Timer? _userScrollSuppressionTimer;
  Timer? _quickActionsHideTimer;
  bool _manualQuickActionsVisible = false;
  bool _lyricsContentScrollable = true;
  bool _scrollabilityCheckScheduled = false;
  Future<TranslationLoadResult>? _translationPreloadFuture;
  TranslationLoadResult? _preloadedTranslationResult;
  String? _preloadedTrackId;
  String? _preloadingTrackId;
  Future<void>? _nextTrackPreloadFuture;
  String? _nextTrackPreloadedId;
  String? _nextTrackPreloadingId;
  bool _lyricsAreSynced = true;
  bool _isLyricsLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Ensure auto-scroll is enabled initially
    setState(() {
      _autoScroll = true;
    });
    // Load lyrics immediately if possible (will check provider context)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadLyrics();
      }
    });
  }

  @override
  void dispose() {
    _userScrollSuppressionTimer?.cancel();
    _quickActionsHideTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    final notificationService =
        Provider.of<NotificationService>(context, listen: false);
    if (!mounted) return;

    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = provider.currentTrack;
    if (currentTrack == null) {
      _autoTranslationRequestedForTrack = false;
      _translationPreloadFuture = null;
      _preloadedTranslationResult = null;
      _preloadedTrackId = null;
      _preloadingTrackId = null;
      _nextTrackPreloadFuture = null;
      _activeTranslationStyle = null;
      // If no track is playing, clear lyrics and reset state
      if (_lyrics.isNotEmpty || _lastTrackId != null) {
        _quickActionsHideTimer?.cancel();
        setState(() {
          _lyrics = [];
          _lastTrackId = null;
          _autoScroll = true; // Default to auto-scroll when lyrics clear/load
          _previousLineIndex = -1;
          _translationsVisible = false;
          _isTranslationLoading = false;
          _syncLineKeys(0);
          _currentTrackDurationMs = null;
          _activeTranslationStyle = null;
          _lyricsAreSynced = true;
          _manualQuickActionsVisible = false;
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
      return;
    }

    final trackId = currentTrack['item']?['id'];
    final durationValue = currentTrack['item']?['duration_ms'];
    final trackDurationMs = durationValue is int
        ? durationValue
        : durationValue is String
            ? int.tryParse(durationValue)
            : null;
    // Only load if trackId is valid and different from the last loaded one
    if (trackId == null || trackId == _lastTrackId) return;

    _autoTranslationRequestedForTrack = false;
    _lastTrackId = trackId;
    final songName = currentTrack['item']?['name'] ?? '';
    final artistName = currentTrack['item']?['artists']?[0]?['name'] ?? '';

    // Reset state for the new track
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _quickActionsHideTimer?.cancel();
    setState(() {
      _lyrics = [];
      _autoScroll = true; // Default to auto-scroll when new lyrics load
      _previousLineIndex = -1;
      _translationsVisible = false;
      _isTranslationLoading = false;
      _syncLineKeys(0);
      _currentTrackDurationMs = trackDurationMs;
      _preloadedTrackId = null;
      _preloadedTranslationResult = null;
      _translationPreloadFuture = null;
      _preloadingTrackId = null;
      _activeTranslationStyle = null;
      _lyricsAreSynced = true;
      _manualQuickActionsVisible = false;
      _isLyricsLoading = true;
    });

    final rawLyrics =
        await _lyricsService.getLyrics(songName, artistName, trackId);

    // Check mounted *before* accessing context again after await
    if (!mounted) return;

    final latestTrackId = Provider.of<SpotifyProvider>(context, listen: false)
        .currentTrack?['item']?['id'];
    // Ensure the lyrics are still for the *current* track before updating state
    if (latestTrackId != trackId) {
      return;
    }

    if (rawLyrics != null) {
      final summary = LyricTimingUtils.summarize(rawLyrics);
      final parsedLyrics = _parseLyrics(rawLyrics);

      if (summary.hasTimestamps && parsedLyrics.isNotEmpty) {
        _quickActionsHideTimer?.cancel();
        setState(() {
          _lyricsAreSynced = true;
          _lyrics = parsedLyrics;
          _autoScroll = true;
          _previousLineIndex = -1;
          _translationsVisible = false;
          _isTranslationLoading = false;
          _syncLineKeys(_lyrics.length);
          _currentTrackDurationMs = trackDurationMs;
          _pendingScrollIndex = null;
          _lastFallbackIndexAttempted = null;
          _fallbackAttemptsForCurrentIndex = 0;
          _manualQuickActionsVisible = false;
          _isLyricsLoading = false;
        });
        // 始终预加载下一首歌词，翻译根据自动翻译设置决定
        unawaited(_preloadNextTrackResources());
        unawaited(_maybeTriggerAutoTranslate());
      } else {
        final unsyncedLines = _buildUnsyncedLyrics(rawLyrics);
        if (unsyncedLines.isNotEmpty) {
          _quickActionsHideTimer?.cancel();
          setState(() {
            _lyricsAreSynced = false;
            _lyrics = unsyncedLines;
            _autoScroll = false;
            _previousLineIndex = -1;
            _translationsVisible = false;
            _isTranslationLoading = false;
            _syncLineKeys(_lyrics.length);
            _currentTrackDurationMs = trackDurationMs;
            _pendingScrollIndex = null;
            _lastFallbackIndexAttempted = null;
            _fallbackAttemptsForCurrentIndex = 0;
            _manualQuickActionsVisible = false;
            _isLyricsLoading = false;
          });
          // 始终预加载下一首歌词，翻译根据自动翻译设置决定
          unawaited(_preloadNextTrackResources());
          unawaited(_maybeTriggerAutoTranslate());
        } else {
          _quickActionsHideTimer?.cancel();
          setState(() {
            _lyricsAreSynced = true;
            _lyrics = [];
            _autoScroll = true;
            _syncLineKeys(0);
            _manualQuickActionsVisible = false;
            _isLyricsLoading = false;
          });
        }
      }
    } else {
      // Lyrics fetch failed, keep lyrics list empty
      _quickActionsHideTimer?.cancel();
      setState(() {
        _lyrics = [];
        // Keep _autoScroll = true
        _syncLineKeys(0);
        _lyricsAreSynced = true;
        _manualQuickActionsVisible = false;
        _isLyricsLoading = false;
      });
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        notificationService.showSnackBar(l10n.lyricsFailedToLoad);
      }
    }
  }

  void _syncLineKeys(int targetLength) {
    if (_lineKeys.length == targetLength) return;
    if (_lineKeys.length < targetLength) {
      final difference = targetLength - _lineKeys.length;
      for (int i = 0; i < difference; i++) {
        _lineKeys.add(GlobalKey());
      }
    } else {
      _lineKeys.removeRange(targetLength, _lineKeys.length);
    }
  }

  String _extractArtistNames(Map<String, dynamic> trackItem) {
    final artists = trackItem['artists'];
    if (artists is List) {
      final names = artists
          .map((artist) {
            if (artist is Map && artist['name'] != null) {
              final value = artist['name'].toString().trim();
              if (value.isNotEmpty) {
                return value;
              }
            }
            return '';
          })
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }
    return 'Unknown Artist';
  }

  String? _extractAlbumCover(Map<String, dynamic> trackItem) {
    final album = trackItem['album'];
    if (album is Map) {
      final images = album['images'];
      if (images is List && images.isNotEmpty) {
        final first = images.first;
        if (first is Map && first['url'] != null) {
          final url = first['url'].toString();
          if (url.isNotEmpty) {
            return url;
          }
        }
      }
    }
    return null;
  }

  String _extractAlbumName(Map<String, dynamic> trackItem) {
    final album = trackItem['album'];
    if (album is Map && album['name'] != null) {
      final value = album['name'].toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return 'Unknown Album';
  }

  String _getPrimaryArtistName(Map<String, dynamic> trackItem) {
    final artists = trackItem['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map && first['name'] != null) {
        final value = first['name'].toString().trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return _extractArtistNames(trackItem);
  }

  Future<TranslationLoadResult> _loadTranslationForTrack({
    required String trackId,
    required List<String> originalLines,
    Map<String, dynamic>? trackItem,
    bool forceRefresh = false,
    TranslationStyle? style,
  }) async {
    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final localDbProvider =
        Provider.of<LocalDatabaseProvider>(context, listen: false);

    final effectiveStyle =
        style ?? await _settingsService.getTranslationStyle();
    final currentLanguage = await _settingsService.getTargetLanguage();
    final styleString = translationStyleToString(effectiveStyle);

    if (!forceRefresh) {
      final cached = await localDbProvider.fetchTranslation(
        trackId,
        currentLanguage,
        styleString,
      );

      if (cached != null) {
        final parsed = parseStructuredTranslation(
          cached.translatedLyrics,
          originalLines: originalLines,
        );

        return TranslationLoadResult(
          rawTranslatedLyrics: cached.translatedLyrics,
          cleanedTranslatedLyrics: parsed.cleanedText,
          perLineTranslations: parsed.translations,
          style: stringToTranslationStyle(cached.style),
          languageCode: cached.languageCode,
        );
      }
    }

    final structuredLyrics = buildStructuredLyrics(originalLines);

    final translationData = await _translationService.translateLyrics(
      structuredLyrics,
      trackId,
      targetLanguage: currentLanguage,
      forceRefresh: forceRefresh,
      originalLines: originalLines,
    );

    final textPayload = translationData['text'];
    if (textPayload is! String || textPayload.trim().isEmpty) {
      throw const LyricsTranslationException(
        code: LyricsTranslationErrorCode.invalidResponse,
        message: 'Missing translated text in response.',
      );
    }

    final rawText = textPayload.trim();
    final cleanedText =
        (translationData['cleanedText'] as String?)?.trim() ?? rawText;
    final languageCodeUsed =
        (translationData['languageCode'] as String?) ?? currentLanguage;
    final styleUsedString =
        (translationData['style'] as String?) ?? styleString;
    final resolvedStyle = stringToTranslationStyle(styleUsedString);

    final perLineTranslations = <int, String>{};
    final lineTranslationsMap =
        translationData['lineTranslations'] as Map<String, dynamic>?;
    if (lineTranslationsMap != null) {
      for (final entry in lineTranslationsMap.entries) {
        final index = int.tryParse(entry.key);
        final value = (entry.value ?? '').toString().trim();
        if (index != null && value.isNotEmpty) {
          perLineTranslations[index] = value;
        }
      }
    }

    if (perLineTranslations.isEmpty) {
      final parsed = parseStructuredTranslation(
        rawText,
        originalLines: originalLines,
      );
      perLineTranslations.addAll(parsed.translations);
    }

    try {
      final existingTrack = await localDbProvider.getTrack(trackId);
      if (existingTrack == null) {
        final item = trackItem ?? spotifyProvider.currentTrack?['item'];
        if (item is Map<String, dynamic>) {
          final trackToAdd = Track(
            trackId: trackId,
            trackName: item['name']?.toString() ?? '',
            artistName: _extractArtistNames(item),
            albumName: _extractAlbumName(item),
            albumCoverUrl: _extractAlbumCover(item),
          );
          await localDbProvider.addTrack(trackToAdd);
        }
      }

      final translationToSave = Translation(
        trackId: trackId,
        languageCode: languageCodeUsed,
        style: styleUsedString,
        translatedLyrics: rawText,
        generatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await localDbProvider.saveTranslation(translationToSave);
    } catch (e) {
      debugPrint('Error saving translation to DB: $e');
    }

    return TranslationLoadResult(
      rawTranslatedLyrics: rawText,
      cleanedTranslatedLyrics: cleanedText,
      perLineTranslations: perLineTranslations,
      style: resolvedStyle,
      languageCode: languageCodeUsed,
    );
  }

  Future<TranslationLoadResult> _loadTranslationData({
    bool forceRefresh = false,
    TranslationStyle? style,
    List<String>? overrideOriginalLines,
  }) async {
    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final currentTrackId = spotifyProvider.currentTrack?['item']?['id'];

    if (currentTrackId == null) {
      throw Exception(l10n.couldNotGetCurrentTrackId);
    }

    final originalLines =
        overrideOriginalLines ?? _lyrics.map((line) => line.text).toList();
    final trackItem = spotifyProvider.currentTrack?['item'];
    return _loadTranslationForTrack(
      trackId: currentTrackId,
      originalLines: originalLines,
      trackItem: trackItem is Map<String, dynamic> ? trackItem : null,
      forceRefresh: forceRefresh,
      style: style,
    );
  }

  bool get _hasTranslationsLoaded {
    return _lyrics.any(
      (line) => line.translation != null && line.translation!.trim().isNotEmpty,
    );
  }

  void _applyTranslationToLyrics(
    Map<int, String> translations,
  ) {
    for (var i = 0; i < _lyrics.length; i++) {
      final translated = translations[i];
      if (translated != null && translated.trim().isNotEmpty) {
        _lyrics[i].translation = translated.trim();
      } else {
        _lyrics[i].translation = null;
      }
    }
  }

  Future<void> _startTranslationPreload({
    required bool triggerDisplayWhenReady,
    bool forceRefresh = false,
  }) async {
    if (!mounted || _lyrics.isEmpty) {
      return;
    }

    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final notificationService =
        Provider.of<NotificationService>(context, listen: false);
    final currentTrackId = spotifyProvider.currentTrack?['item']?['id'];

    if (currentTrackId == null) {
      return;
    }

    if (!forceRefresh &&
        _preloadedTrackId == currentTrackId &&
        _preloadedTranslationResult != null) {
      if (triggerDisplayWhenReady && !_translationsVisible) {
        setState(() {
          _applyTranslationToLyrics(
              _preloadedTranslationResult!.perLineTranslations);
          _translationsVisible = true;
          _isTranslationLoading = false;
          _activeTranslationStyle = _preloadedTranslationResult!.style;
        });
        _scheduleRealignScroll();
      }
      return;
    }

    if (!forceRefresh &&
        _translationPreloadFuture != null &&
        _preloadingTrackId == currentTrackId) {
      if (triggerDisplayWhenReady && !_isTranslationLoading) {
        setState(() {
          _isTranslationLoading = true;
        });
      }
      try {
        final result = await _translationPreloadFuture!;
        if (!mounted) return;
        _preloadedTrackId = currentTrackId;
        _preloadedTranslationResult = result;
        if (triggerDisplayWhenReady && !_translationsVisible) {
          setState(() {
            _applyTranslationToLyrics(result.perLineTranslations);
            _translationsVisible = true;
            _isTranslationLoading = false;
            _activeTranslationStyle = result.style;
          });
          _scheduleRealignScroll();
        } else if (triggerDisplayWhenReady) {
          setState(() {
            _isTranslationLoading = false;
            _activeTranslationStyle = result.style;
          });
        }
      } catch (e) {
        if (!mounted) return;
        if (triggerDisplayWhenReady) {
          setState(() {
            _isTranslationLoading = false;
          });
          final l10n = AppLocalizations.of(context)!;
          notificationService.showSnackBar(
            l10n.translationFailed(e.toString()),
          );
        } else {
          debugPrint('Translation preload failed: $e');
        }
      }
      return;
    }

    if (triggerDisplayWhenReady && !_isTranslationLoading) {
      setState(() {
        _isTranslationLoading = true;
      });
    }

    _preloadingTrackId = currentTrackId;
    final future = _loadTranslationData(
      forceRefresh: forceRefresh,
    );
    _translationPreloadFuture = future;

    try {
      final result = await future;
      if (!mounted) return;
      _preloadedTrackId = currentTrackId;
      _preloadedTranslationResult = result;
      _translationPreloadFuture = null;
      _preloadingTrackId = null;

      if (triggerDisplayWhenReady) {
        setState(() {
          _applyTranslationToLyrics(result.perLineTranslations);
          _translationsVisible = true;
          _isTranslationLoading = false;
          _activeTranslationStyle = result.style;
        });
        _scheduleRealignScroll();
      }
    } catch (e) {
      if (!mounted) return;
      _translationPreloadFuture = null;
      _preloadingTrackId = null;
      if (triggerDisplayWhenReady) {
        setState(() {
          _isTranslationLoading = false;
        });
        final l10n = AppLocalizations.of(context)!;
        notificationService.showSnackBar(
          l10n.translationFailed(e.toString()),
        );
      } else {
        debugPrint('Translation preload failed: $e');
      }
    }
  }

  /// 预加载下一首歌曲的歌词和翻译（当启用自动翻译时）
  ///
  /// [preloadTranslation] 是否预加载翻译。如果为 null，则根据用户的自动翻译设置决定。
  Future<void> _preloadNextTrackResources({bool? preloadTranslation}) async {
    if (!mounted) {
      return;
    }

    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    final dynamic nextTrackRaw = provider.nextTrack ??
        (provider.upcomingTracks.isNotEmpty
            ? provider.upcomingTracks.first
            : null);

    if (nextTrackRaw == null) {
      return;
    }

    final nextTrack =
        nextTrackRaw is Map<String, dynamic> ? nextTrackRaw : null;
    if (nextTrack == null) {
      return;
    }

    final trackId = nextTrack['id']?.toString();
    if (trackId == null ||
        trackId.isEmpty ||
        trackId == _lastTrackId ||
        _nextTrackPreloadedId == trackId) {
      return;
    }

    if (_nextTrackPreloadFuture != null && _nextTrackPreloadingId == trackId) {
      return;
    }

    _nextTrackPreloadingId = trackId;
    _nextTrackPreloadFuture = Future(() async {
      try {
        final songName = nextTrack['name']?.toString() ?? '';
        final artistName = _getPrimaryArtistName(nextTrack);

        // 始终预加载歌词（会自动缓存到 SharedPreferences）
        final rawLyrics =
            await _lyricsService.getLyrics(songName, artistName, trackId);
        if (rawLyrics == null || !mounted) {
          debugPrint('Preloaded lyrics for next track: $trackId (no lyrics found)');
          return;
        }

        debugPrint('Preloaded lyrics for next track: $trackId');

        var lyricLines = _parseLyrics(rawLyrics);
        List<String> originalLines =
            lyricLines.map((line) => line.text).toList(growable: false);

        if (originalLines.isEmpty) {
          originalLines = rawLyrics
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
        }

        if (originalLines.isEmpty) {
          return;
        }

        // 根据参数或用户设置决定是否预加载翻译
        final shouldPreloadTranslation = preloadTranslation ??
            await _settingsService.getAutoTranslateLyricsEnabled();

        if (shouldPreloadTranslation) {
          await _loadTranslationForTrack(
            trackId: trackId,
            originalLines: originalLines,
            trackItem: nextTrack,
          );
          debugPrint('Preloaded translation for next track: $trackId');
        }

        if (!mounted) return;
        _nextTrackPreloadedId = trackId;
      } catch (e) {
        debugPrint('Failed to preload next track resources: $e');
      } finally {
        if (_nextTrackPreloadingId == trackId) {
          _nextTrackPreloadingId = null;
        }
        _nextTrackPreloadFuture = null;
      }
    });
  }

  Future<void> _maybeTriggerAutoTranslate() async {
    if (!mounted ||
        _autoTranslationRequestedForTrack ||
        _lyrics.isEmpty ||
        _hasTranslationsLoaded) {
      return;
    }

    final autoTranslateEnabled =
        await _settingsService.getAutoTranslateLyricsEnabled();

    if (!mounted ||
        _autoTranslationRequestedForTrack ||
        !autoTranslateEnabled ||
        _lyrics.isEmpty ||
        _hasTranslationsLoaded) {
      return;
    }

    _autoTranslationRequestedForTrack = true;
    unawaited(_startTranslationPreload(triggerDisplayWhenReady: true));
    // 注意：下一首歌的预加载已在 _loadLyrics 中触发，这里不需要重复调用
    // _preloadNextTrackResources() 会根据自动翻译设置自动决定是否预加载翻译
  }

  bool get _requiresManualQuickActions =>
      _lyrics.isNotEmpty && (!_lyricsAreSynced || !_lyricsContentScrollable);

  bool get _shouldShowQuickActionsBar {
    if (_isCopyLyricsMode || _lyrics.isEmpty) {
      return true;
    }
    if (_lyricsAreSynced && _lyricsContentScrollable) {
      return !_autoScroll;
    }
    return _requiresManualQuickActions && _manualQuickActionsVisible;
  }

  void _scheduleScrollabilityCheck() {
    if (_scrollabilityCheckScheduled) {
      return;
    }
    _scrollabilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollabilityCheckScheduled = false;
      if (!mounted) {
        return;
      }
      if (!_scrollController.hasClients) {
        _scheduleScrollabilityCheck();
        return;
      }
      final position = _scrollController.position;
      final bool canScroll =
          (position.maxScrollExtent - position.minScrollExtent).abs() > 1.0;
      final bool nextRequiresManual =
          _lyrics.isNotEmpty && (!_lyricsAreSynced || !canScroll);
      final bool manualRequirementChanged =
          _requiresManualQuickActions != nextRequiresManual;
      if (_lyricsContentScrollable != canScroll || manualRequirementChanged) {
        setState(() {
          _lyricsContentScrollable = canScroll;
          if (!nextRequiresManual) {
            _manualQuickActionsVisible = false;
            _quickActionsHideTimer?.cancel();
          }
        });
      }
    });
  }

  void _showManualQuickActionsTemporarily() {
    if (!mounted ||
        !_requiresManualQuickActions ||
        _isCopyLyricsMode ||
        _lyrics.isEmpty) {
      return;
    }
    if (!_manualQuickActionsVisible) {
      setState(() {
        _manualQuickActionsVisible = true;
      });
    }
    _quickActionsHideTimer?.cancel();
    _quickActionsHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted ||
          !_requiresManualQuickActions ||
          _isCopyLyricsMode ||
          _lyrics.isEmpty) {
        return;
      }
      if (_manualQuickActionsVisible) {
        setState(() {
          _manualQuickActionsVisible = false;
        });
      }
    });
  }

  void _scheduleRealignScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autoScroll) return;
      WidgetsBinding.instance.addPostFrameCallback((__) {
        if (!mounted || !_autoScroll) return;
        final provider = Provider.of<SpotifyProvider>(context, listen: false);
        final currentProgressMs = provider.currentTrack?['progress_ms'] ?? 0;
        final currentPosition = Duration(milliseconds: currentProgressMs);
        final latestCurrentIndex = _getCurrentLineIndex(currentPosition);
        if (latestCurrentIndex >= 0) {
          _scrollToCurrentLine(latestCurrentIndex);
          _previousLineIndex = latestCurrentIndex;
        }
      });
    });
  }

  Future<void> _handleTranslateButtonTap() async {
    if (_lyrics.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsToTranslate);
      return;
    }

    if (_isTranslationLoading) {
      return;
    }

    if (_hasTranslationsLoaded) {
      setState(() {
        _translationsVisible = !_translationsVisible;
      });
      _scheduleRealignScroll();
      return;
    }

    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrackId = spotifyProvider.currentTrack?['item']?['id'];

    if (currentTrackId != null &&
        _preloadedTrackId == currentTrackId &&
        _preloadedTranslationResult != null) {
      setState(() {
        _applyTranslationToLyrics(
            _preloadedTranslationResult!.perLineTranslations);
        _translationsVisible = true;
        _isTranslationLoading = false;
        _activeTranslationStyle = _preloadedTranslationResult!.style;
      });
      _scheduleRealignScroll();
      return;
    }

    await _startTranslationPreload(triggerDisplayWhenReady: true);
  }

  Future<void> _openTranslationResultPage() async {
    if (_lyrics.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsToTranslate);
      return;
    }

    final originalLines = _lyrics.map((line) => line.text).toList();
    final originalLyricsJoined = originalLines.join('\n');
    final currentStyle = await _settingsService.getTranslationStyle();
    final wasAutoScrolling = _autoScroll;
    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrackId = spotifyProvider.currentTrack?['item']?['id'];

    if (_autoScroll) {
      setState(() {
        _autoScroll = false;
        _temporarilyIgnoreUserScroll = false;
        _userScrollSuppressionTimer?.cancel();
      });
    }

    late Future<TranslationLoadResult> initialFuture;
    if (currentTrackId != null) {
      if (_translationPreloadFuture != null &&
          _preloadingTrackId == currentTrackId) {
        initialFuture = _translationPreloadFuture!;
      } else if (_preloadedTrackId == currentTrackId &&
          _preloadedTranslationResult != null) {
        initialFuture = Future.value(_preloadedTranslationResult!);
      } else {
        initialFuture = _loadTranslationData(
          style: currentStyle,
          overrideOriginalLines: originalLines,
        );
      }
    } else {
      initialFuture = _loadTranslationData(
        style: currentStyle,
        overrideOriginalLines: originalLines,
      );
    }

    initialFuture.then((result) {
      if (!mounted) return;
      setState(() {
        _applyTranslationToLyrics(result.perLineTranslations);
        _activeTranslationStyle = result.style;
      });
      if (_translationsVisible) {
        _scheduleRealignScroll();
      }
    }).catchError((_) {});

    if (!mounted) return;

    await ResponsiveNavigation.showSecondaryPage(
      context: context,
      child: TranslationResultPage(
        originalLyrics: originalLyricsJoined,
        initialStyle: currentStyle,
        loadTranslation: ({
          bool forceRefresh = false,
          TranslationStyle? style,
        }) {
          return _loadTranslationData(
            forceRefresh: forceRefresh,
            style: style,
            overrideOriginalLines: originalLines,
          );
        },
        initialData: initialFuture,
      ),
      preferredMode: SecondaryPageMode.sideSheet,
      maxWidth: 520,
    );

    if (!mounted) return;

    if (wasAutoScrolling) {
      _enableAutoScrollWithSuppression();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoScroll) {
          final currentProvider =
              Provider.of<SpotifyProvider>(context, listen: false);
          final currentProgressMs =
              currentProvider.currentTrack?['progress_ms'] ?? 0;
          final currentPosition = Duration(milliseconds: currentProgressMs);
          final latestCurrentIndex = _getCurrentLineIndex(currentPosition);
          if (latestCurrentIndex >= 0) {
            _scrollToCurrentLine(latestCurrentIndex);
            _previousLineIndex = latestCurrentIndex;
          }
        }
      });
    }
  }

  double _computeEffectiveAlignment() {
    if (!_scrollController.hasClients) return 0.5;

    final mediaQuery = MediaQuery.of(context);
    final double viewport = _scrollController.position.viewportDimension;
    if (viewport <= 0) return 0.5;

    final double topOverlay = 40.0 + mediaQuery.padding.top;

    final bool bottomBarVisible = _shouldShowQuickActionsBar;
    final double bottomOverlay =
        bottomBarVisible ? (24.0 + mediaQuery.padding.bottom + 48.0) : 0.0;

    final double delta = ((topOverlay - bottomOverlay) / 2.0) / viewport;
    final double alignment = (0.5 + delta).clamp(0.0, 1.0);
    return alignment;
  }

  double _tailSpace() {
    if (!_scrollController.hasClients) return 400.0;

    final mediaQuery = MediaQuery.of(context);
    final position = _scrollController.position;
    if (!position.hasPixels || position.viewportDimension <= 0) {
      return 400.0;
    }
    final double viewport = position.viewportDimension;

    final double topOverlay = 40.0 + mediaQuery.padding.top;

    final bool bottomBarVisible = _shouldShowQuickActionsBar;
    final double bottomOverlay =
        bottomBarVisible ? (24.0 + mediaQuery.padding.bottom + 48.0) : 0.0;

    final double visibleHeight =
        (viewport - topOverlay - bottomOverlay).clamp(0.0, viewport);
    return (visibleHeight / 2.0) + bottomOverlay + 8.0;
  }

  void _scrollToCurrentLine(int currentLineIndex) {
    if (!mounted ||
        !_autoScroll ||
        !_lyricsAreSynced ||
        !_scrollController.hasClients ||
        currentLineIndex < 0 ||
        currentLineIndex >= _lineKeys.length) {
      return;
    }

    final key = _lineKeys[currentLineIndex];
    final context = key.currentContext;
    if (context == null) {
      if (_lastFallbackIndexAttempted != currentLineIndex) {
        _fallbackAttemptsForCurrentIndex = 0;
      }
      _pendingScrollIndex = currentLineIndex;
      _lastFallbackIndexAttempted = currentLineIndex;
      _fallbackAttemptsForCurrentIndex++;

      final position = _scrollController.position;
      if (position.hasPixels &&
          position.hasContentDimensions &&
          position.viewportDimension > 0 &&
          _lyrics.isNotEmpty) {
        final line = _lyrics[currentLineIndex];
        double ratio;
        if (_currentTrackDurationMs != null &&
            _currentTrackDurationMs! > 0 &&
            line.timestamp.inMilliseconds >= 0) {
          final double totalMs = _currentTrackDurationMs!.toDouble();
          ratio = line.timestamp.inMilliseconds / totalMs;
        } else if (_lyrics.length <= 1) {
          ratio = 0.0;
        } else {
          ratio = currentLineIndex / (_lyrics.length - 1);
        }

        if (!ratio.isFinite) {
          ratio = 0.0;
        } else if (ratio < 0.0) {
          ratio = 0.0;
        } else if (ratio > 1.0) {
          ratio = 1.0;
        }

        final double alignment = _computeEffectiveAlignment();
        final double viewportDim = position.viewportDimension;
        final double viewportHalf = viewportDim * 0.5;
        double targetOffset =
            (ratio * position.maxScrollExtent) - (viewportDim * alignment);

        if (_fallbackAttemptsForCurrentIndex > 1) {
          final double direction =
              (targetOffset >= position.pixels) ? 1.0 : -1.0;
          final double fallbackMagnitude =
              (_fallbackAttemptsForCurrentIndex - 1).clamp(1, 4).toDouble();
          final double extraOffset = viewportHalf * 0.6 * fallbackMagnitude;
          targetOffset += direction * extraOffset;
        }

        if (targetOffset < position.minScrollExtent) {
          targetOffset = position.minScrollExtent;
        } else if (targetOffset > position.maxScrollExtent) {
          targetOffset = position.maxScrollExtent;
        }

        try {
          if ((position.pixels - targetOffset).abs() > 1.0) {
            _scrollController.jumpTo(targetOffset);
          }
        } catch (_) {
          // Ignore jump errors; we'll retry on the next frame if needed.
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoScroll && _pendingScrollIndex == currentLineIndex) {
          _scrollToCurrentLine(currentLineIndex);
        }
      });
      return;
    }

    _pendingScrollIndex = null;
    _lastFallbackIndexAttempted = null;
    _fallbackAttemptsForCurrentIndex = 0;

    try {
      final renderObject = context.findRenderObject();
      if (renderObject == null) return;

      final viewport = RenderAbstractViewport.of(renderObject);
      final double alignment = _computeEffectiveAlignment();
      final reveal = viewport.getOffsetToReveal(renderObject, alignment);
      final position = _scrollController.position;
      final targetOffset = reveal.offset;
      final clampedOffset = targetOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      final distance = (position.pixels - clampedOffset).abs();
      final durationMs =
          distance < 60 ? 160 : (220 + distance * 0.2).clamp(200, 600).toInt();

      _scrollController.animateTo(
        clampedOffset,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.easeInOutCubic,
      );
    } catch (_) {
      // Ignore scroll errors; they'll be retried on the next tick if needed.
    }
  }

  void _enableAutoScrollWithSuppression(
      {Duration duration = const Duration(milliseconds: 350)}) {
    if (!mounted) {
      return;
    }
    if (!_lyricsAreSynced) {
      setState(() {
        _autoScroll = false;
        _temporarilyIgnoreUserScroll = false;
      });
      return;
    }
    setState(() {
      _autoScroll = true;
      _temporarilyIgnoreUserScroll = duration > Duration.zero;
    });
    _userScrollSuppressionTimer?.cancel();
    if (duration > Duration.zero) {
      _userScrollSuppressionTimer = Timer(duration, () {
        if (!mounted) return;
        setState(() {
          _temporarilyIgnoreUserScroll = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    //final provider = Provider.of<SpotifyProvider>(context); // Get provider once
    final l10n = AppLocalizations.of(context)!;

    // Use Consumer to react to provider changes efficiently
    return Consumer<SpotifyProvider>(
      builder: (context, provider, child) {
        // debugPrint('[LyricsBuilder] Build Start - PrevIdx: $_previousLineIndex'); // Log builder start
        final currentTrackData =
            provider.currentTrack; // Get current track data
        final currentTrackId = currentTrackData?['item']?['id'];
        final bool trackJustChanged = (currentTrackId != _lastTrackId);

        // 1. Handle track change: Load lyrics if track ID changes
        if (trackJustChanged) {
          // Reset copy mode if active when track changes
          if (_isCopyLyricsMode && mounted) {
            Future.microtask(() => _toggleCopyLyricsMode());
          }
          // Load lyrics for the new track (handles null track internally)
          Future.microtask(() async {
            await _loadLyrics();
          });
        }

        _syncLineKeys(_lyrics.length);
        _scheduleScrollabilityCheck();

        // 2. Calculate latest position and index based on provider state
        final currentProgressMs = currentTrackData?['progress_ms'] ?? 0;
        final latestPosition = Duration(milliseconds: currentProgressMs);
        final currentLineIndex = _getCurrentLineIndex(latestPosition);
        // debugPrint('[LyricsBuilder] Calculated Idx: $currentLineIndex (from ${currentProgressMs}ms)'); // Log calculated index

        if (_autoScroll &&
            _lyrics.isNotEmpty &&
            mounted &&
            currentLineIndex >= 0) {
          if (_previousLineIndex != currentLineIndex ||
              _pendingScrollIndex != null) {
            _previousLineIndex = currentLineIndex;
            _pendingScrollIndex = currentLineIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _autoScroll &&
                  _pendingScrollIndex == currentLineIndex) {
                _scrollToCurrentLine(currentLineIndex);
              }
            });
          }
        }

        final bool shouldShowQuickActions = _shouldShowQuickActionsBar;

        // REMOVED: Internal _currentPosition state update logic
        // REMOVED: Logic to start/stop internal _progressTimer based on isPlaying

        return Material(
          color: Colors.transparent,
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollNotification) {
              if (!mounted) return true;

              bool userInitiatedScroll = false;
              // Disable auto-scroll on user interaction
              if (scrollNotification is UserScrollNotification) {
                if (_temporarilyIgnoreUserScroll) {
                  return true;
                }
                if (scrollNotification.direction != ScrollDirection.idle &&
                    _autoScroll) {
                  setState(() {
                    _autoScroll = false;
                    _temporarilyIgnoreUserScroll = false;
                    _userScrollSuppressionTimer?.cancel();
                  });
                }
                if (scrollNotification.direction != ScrollDirection.idle) {
                  userInitiatedScroll = true;
                }
              } else if (scrollNotification is ScrollStartNotification) {
                userInitiatedScroll = scrollNotification.dragDetails != null;
              } else if (scrollNotification is ScrollUpdateNotification) {
                userInitiatedScroll = scrollNotification.dragDetails != null;
              } else if (scrollNotification is OverscrollNotification) {
                userInitiatedScroll = scrollNotification.dragDetails != null;
              }

              if (_requiresManualQuickActions && userInitiatedScroll) {
                _showManualQuickActionsTemporarily();
              }
              return true; // Allow notification to bubble up
            },
            child: Stack(
              children: [
                // 歌词加载中时显示居中的加载指示器
                if (_lyrics.isEmpty && _isLyricsLoading)
                  Positioned.fill(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha((0.7 * 255).round()),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.lyricsLoading,
                            style: TextStyle(
                              fontFamily: 'Spotify Mix',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha((0.6 * 255).round()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ListView.builder(
                  key: _listViewKey,
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  cacheExtent:
                      1000.0, // Prebuild nearby items to reduce fallback jumps
                  padding: EdgeInsets.only(
                    top: 80 + MediaQuery.of(context).padding.top,
                    bottom: 40 +
                        MediaQuery.of(context)
                            .padding
                            .bottom, // Reverted bottom padding
                  ),
                  itemCount: _lyrics.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _lyrics.length) {
                      return SizedBox(
                          height:
                              _tailSpace()); // Spacer keeps final line centerable
                    }
                    final theme = Theme.of(context);
                    final bool isWideLyricLayout = context.isLargeScreen;
                    final bool isWeb = kIsWeb;
                    final line = _lyrics[index];
                    final bool showTranslationLine = _translationsVisible &&
                        line.translation != null &&
                        line.translation!.trim().isNotEmpty;
                    final bool lyricsSynced = _lyricsAreSynced;
                    final bool isCurrentLine =
                        lyricsSynced && index == currentLineIndex;
                    final bool isPastLine =
                        lyricsSynced && index < currentLineIndex;
                    final Color baseTextColor;
                    if (!lyricsSynced) {
                      baseTextColor = theme.colorScheme.primary;
                    } else if (isPastLine) {
                      baseTextColor = theme.colorScheme.secondaryContainer;
                    } else if (isCurrentLine) {
                      baseTextColor = theme.colorScheme.primary;
                    } else {
                      baseTextColor = theme.colorScheme.primary
                          .withAlpha((0.5 * 255).round());
                    }
                    final Color translationColor = baseTextColor;
                    final double lyricFontSize = isWideLyricLayout
                        ? (isWeb ? 30.0 : 24.0)
                        : (isWeb ? 36.0 : 22.0);
                    final double translationFontSize = isWideLyricLayout
                        ? (isWeb ? 24.0 : 18.0)
                        : (isWeb ? 20.0 : 16.0);

                    return GestureDetector(
                      key: _lineKeys[index],
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (!mounted) return;

                        // Seek Spotify to the tapped line's timestamp
                        final tappedTimestamp = _lyrics[index].timestamp;
                        provider.seekToPosition(tappedTimestamp.inMilliseconds);

                        // If in copy mode, exit it. Otherwise, ensure auto-scroll is enabled.
                        bool needsScrollTrigger = false;
                        if (_isCopyLyricsMode) {
                          _toggleCopyLyricsMode(); // Exits copy mode, enables autoScroll
                          needsScrollTrigger = true; // Scroll after exiting
                        } else {
                          if (!_autoScroll) {
                            needsScrollTrigger = true; // Scroll after enabling
                            _enableAutoScrollWithSuppression(
                              duration: const Duration(milliseconds: 250),
                            );
                          } else {
                            // If already auto-scrolling, just seeking might be enough,
                            // but explicitly trigger scroll for immediate feedback.
                            needsScrollTrigger = true;
                          }
                        }

                        // Trigger scroll immediately after state change/seek
                        if (needsScrollTrigger) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _autoScroll) {
                              // Scroll to the *tapped* index immediately
                              _scrollToCurrentLine(index);
                              _previousLineIndex =
                                  index; // Update index after tap scroll
                            }
                          });
                        }
                      },
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          // Web端行间距增大30%
                          vertical: isWeb
                              ? (isCurrentLine ? 15.6 : 10.4)
                              : (isCurrentLine ? 12.0 : 8.0),
                          // Responsive horizontal padding
                          horizontal: isWideLyricLayout
                              ? 24.0
                              : 40.0, // Reverted padding
                        ),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontFamily: 'Spotify Mix',
                            fontSize: lyricFontSize,
                            fontWeight: isCurrentLine
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: baseTextColor,
                            // Web端文字行高增大30%
                            height: isWeb ? 1.43 : 1.1,
                          ),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            opacity: lyricsSynced
                                ? (isCurrentLine ? 1.0 : 0.8)
                                : 1.0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.text,
                                  textAlign: TextAlign.left, // Align text left
                                ),
                                if (showTranslationLine)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      // Web端翻译行间距增大30%
                                      top: isWeb ? 7.8 : 6.0,
                                    ),
                                    child: Text(
                                      line.translation!,
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        fontFamily: 'Spotify Mix',
                                        fontSize: translationFontSize,
                                        fontWeight: FontWeight.w500,
                                        color: translationColor,
                                        // Web端翻译文字行高增大30%
                                        height: isWeb ? 1.69 : 1.3,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Gradient overlay at the top
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 40 +
                      MediaQuery.of(context).padding.top, // Reverted height
                  child: IgnorePointer(
                    // Makes gradient non-interactive
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(context).scaffoldBackgroundColor,
                            Theme.of(context)
                                .scaffoldBackgroundColor, // Reverted: Original had 2 solid colors
                            Theme.of(context)
                                .scaffoldBackgroundColor
                                .withAlpha((0.8 * 255).round()),
                            Theme.of(context)
                                .scaffoldBackgroundColor
                                .withAlpha((0.0 * 255).round()),
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0], // Reverted stops
                        ),
                      ),
                    ),
                  ),
                ),
                // Buttons overlay at the bottom
                if (shouldShowQuickActions)
                  Positioned(
                    left: context.isLargeScreen
                        ? 24
                        : 16, // Reverted left positioning
                    bottom: 24 +
                        MediaQuery.of(context)
                            .padding
                            .bottom, // Reverted bottom positioning
                    child: Padding(
                      padding:
                          EdgeInsets.zero, // Removed horizontal padding wrapper
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment
                            .start, // Reverted alignment to start
                        children: [
                          // Center/Resume Scroll Button
                          if (!_autoScroll &&
                              _lyrics.isNotEmpty &&
                              _lyricsAreSynced) // Show only if synced lyrics exist
                            IconButton.filledTonal(
                              icon: const Icon(Icons.vertical_align_center),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                if (!mounted) return;
                                _enableAutoScrollWithSuppression();
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted && _autoScroll) {
                                    final currentProvider =
                                        Provider.of<SpotifyProvider>(context,
                                            listen: false);
                                    final currentProgressMs = currentProvider
                                            .currentTrack?['progress_ms'] ??
                                        0;
                                    final latestPosition = Duration(
                                        milliseconds: currentProgressMs);
                                    final latestCurrentIndex =
                                        _getCurrentLineIndex(latestPosition);
                                    _scrollToCurrentLine(latestCurrentIndex);
                                    _previousLineIndex = latestCurrentIndex;
                                  }
                                });
                              },
                              tooltip: l10n
                                  .centerCurrentLine, // "Center Current Line"
                            ),
                          if (!_autoScroll &&
                              _lyrics.isNotEmpty &&
                              _lyricsAreSynced)
                            const SizedBox(width: 8), // Spacer

                          // Translate Button (tap for inline, long-press for full view)
                          GestureDetector(
                            onLongPress:
                                (_lyrics.isEmpty || _isTranslationLoading)
                                    ? null
                                    : () {
                                        HapticFeedback.mediumImpact();
                                        _openTranslationResultPage();
                                      },
                            child: IconButton.filledTonal(
                              icon: _isTranslationLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _translationsVisible &&
                                              _hasTranslationsLoaded
                                          ? Icons.g_translate
                                          : Icons.translate,
                                    ),
                              onPressed:
                                  (_lyrics.isEmpty || _isTranslationLoading)
                                      ? null
                                      : () {
                                          HapticFeedback.lightImpact();
                                          _handleTranslateButtonTap();
                                        },
                              tooltip:
                                  l10n.translateLyrics, // "Translate Lyrics"
                              style: (_translationsVisible &&
                                      _hasTranslationsLoaded)
                                  ? ButtonStyle(
                                      backgroundColor: WidgetStateProperty.all(
                                        Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withAlpha((0.18 * 255).round()),
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        Theme.of(context).colorScheme.primary,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Copy/Edit Mode Button
                          IconButton.filledTonal(
                            icon: Icon(
                              _isCopyLyricsMode
                                  ? Icons.playlist_play_rounded // Exit icon
                                  : Icons.edit_note_rounded, // Enter icon
                            ),
                            onPressed: _lyrics.isEmpty
                                ? null
                                : () {
                                    // Disable if no lyrics
                                    HapticFeedback.lightImpact();
                                    _toggleCopyLyricsMode();
                                  },
                            tooltip: _isCopyLyricsMode
                                ? l10n
                                    .exitCopyModeResumeScroll // "Exit Copy Mode & Resume Scroll"
                                : l10n
                                    .enterCopyLyricsMode, // "Enter Copy Lyrics Mode"
                            style: ButtonStyle(
                              // Visual feedback when in copy mode
                              backgroundColor: _isCopyLyricsMode
                                  ? WidgetStateProperty.all(Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withAlpha((0.3 * 255).round()))
                                  : null,
                              foregroundColor: _isCopyLyricsMode
                                  ? WidgetStateProperty.all(
                                      Theme.of(context).colorScheme.onPrimary)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Search Lyrics Button
                          IconButton.filledTonal(
                            icon: const Icon(Icons.search),
                            onPressed: _showSearchLyricsPage,
                            tooltip: l10n.searchLyrics,
                          ),
                          const SizedBox(width: 8),

                          // Select Lyrics Button
                          IconButton.filledTonal(
                            icon: const Icon(Icons.checklist),
                            onPressed: _lyrics.isEmpty
                                ? null
                                : _showLyricsSelectionPage,
                            tooltip: l10n.selectLyricsTooltip,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _getCurrentLineIndex(Duration currentPosition) {
    if (_lyrics.isEmpty) return -1; // No lyrics, no index
    if (!_lyricsAreSynced) return -1;

    // If position is before the first timestamp, highlight nothing (-1) or first line (0)?
    // Let's choose -1 for consistency (no line is "current" yet)
    if (currentPosition < _lyrics[0].timestamp) {
      return -1; // Before the first line starts
    }

    // Find the last line whose timestamp is less than or equal to the current position
    for (int i = _lyrics.length - 1; i >= 0; i--) {
      if (_lyrics[i].timestamp <= currentPosition) {
        return i;
      }
    }

    // Should not happen if the first check passed, but as a fallback
    return -1;
  }

  List<LyricLine> _buildUnsyncedLyrics(String rawLyrics) {
    final lines = rawLyrics
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final List<LyricLine> result = [];
    for (var i = 0; i < lines.length; i++) {
      result.add(LyricLine(Duration(milliseconds: i), lines[i]));
    }
    return result;
  }

  List<LyricLine> _parseLyrics(String rawLyrics) {
    final lines = rawLyrics.split('\n');
    final List<LyricLine> result = [];

    final RegExp timeTagRegex = RegExp(r'^\[(\d{2,}):(\d{2})\.?(\d{2,3})?\]');

    for (var line in lines) {
      final match = timeTagRegex.firstMatch(line);
      if (match != null) {
        try {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          // Handle optional milliseconds (2 or 3 digits)
          final millisecondsStr = match.group(3);
          int milliseconds = 0;
          if (millisecondsStr != null) {
            if (millisecondsStr.length == 2) {
              milliseconds = int.parse(millisecondsStr) *
                  10; // 2 digits -> centiseconds to milliseconds
            } else {
              milliseconds =
                  int.parse(millisecondsStr); // 3 digits -> milliseconds
            }
          }

          final timestamp = Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          );

          var text = line.substring(match.end).trim();
          // Decode common HTML entities
          text = text
              .replaceAll('&apos;', "'")
              .replaceAll('&quot;', '"')
              .replaceAll('&amp;', '&')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>');

          // Add line only if the text part is not empty
          if (text.isNotEmpty) {
            result.add(LyricLine(timestamp, text));
          }
        } catch (e) {
          // Log parsing errors for specific lines if needed
          // debugPrint('Failed to parse lyric line: $line, Error: $e');
        }
      } else if (line.trim().isNotEmpty && !line.trim().startsWith('[')) {
        // Handle lines without timestamps (e.g., for unsynced lyrics)
        // Assign a zero timestamp or handle differently? For now, assign zero.
        // Or maybe filter them out if only synced lyrics are desired.
        // Let's add them with a zero timestamp for now.
        // result.add(LyricLine(Duration.zero, line.trim()));
        // --> Let's actually SKIP lines without valid timestamps for synced lyrics.
      }
    }

    // Sort lines by timestamp just in case they weren't ordered
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Optional: Merge consecutive lines with the same timestamp?
    // For now, keep them separate.

    return result;
  }

  void _toggleCopyLyricsMode() {
    if (!mounted) return;

    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    final wasCopyMode = _isCopyLyricsMode;

    setState(() {
      if (_isCopyLyricsMode) {
        // --- Exiting copy mode ---
        _isCopyLyricsMode = false;
        _autoScroll = _lyricsAreSynced; // Resume auto-scroll only when synced
        _temporarilyIgnoreUserScroll = true;
        _quickActionsHideTimer?.cancel();
        _manualQuickActionsVisible = false;
        // Restore previous play mode if it was saved
        if (_previousPlayMode != null) {
          provider.setPlayMode(_previousPlayMode!);
          _previousPlayMode = null; // Clear saved mode
        }
        // Trigger scroll after exiting copy mode and enabling autoScroll
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoScroll) {
            // Get latest index based on provider's progress
            final currentProgressMs =
                provider.currentTrack?['progress_ms'] ?? 0;
            final currentPosition = Duration(milliseconds: currentProgressMs);
            final latestCurrentIndex = _getCurrentLineIndex(currentPosition);
            if (latestCurrentIndex >= 0) {
              _scrollToCurrentLine(latestCurrentIndex);
              _previousLineIndex =
                  latestCurrentIndex; // Update index after scroll
            }
          }
        });
      } else {
        // --- Entering copy mode ---
        _isCopyLyricsMode = true;
        _autoScroll = false; // Disable auto-scroll explicitly
        _temporarilyIgnoreUserScroll = false;
        _userScrollSuppressionTimer?.cancel();
        _quickActionsHideTimer?.cancel();
        // Store current mode and set to single repeat
        _previousPlayMode = provider.currentMode;
        provider.setPlayMode(PlayMode.singleRepeat);

        // Show snackbar hint using NotificationService
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          Provider.of<NotificationService>(context, listen: false).showSnackBar(
            l10n.lyricsCopyModeSnackbar, // "Lyrics copy mode: Auto-scroll disabled, tap line to seek."
            duration: const Duration(seconds: 4), // Slightly longer duration
          );
        }
      }
    });

    if (wasCopyMode) {
      _userScrollSuppressionTimer?.cancel();
      _userScrollSuppressionTimer = Timer(
        const Duration(milliseconds: 350),
        () {
          if (!mounted) return;
          setState(() {
            _temporarilyIgnoreUserScroll = false;
          });
        },
      );
    }
  }

  // Method to navigate to the lyrics search page
  void _showSearchLyricsPage() {
    if (!mounted) return;

    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack?['item'];
    final notificationService =
        Provider.of<NotificationService>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    if (currentTrack == null) {
      notificationService.showSnackBar(l10n.noCurrentTrackPlaying);
      return;
    }

    final trackId = currentTrack['id'];
    final trackName = currentTrack['name'] ?? '';
    final artistName = (currentTrack['artists'] as List?)
            ?.map((artist) => artist['name'] as String)
            .join(', ') ??
        ''; // Join multiple artists

    if (trackId == null || trackName.isEmpty) {
      notificationService.showSnackBar(l10n.cannotGetTrackInfo);
      return;
    }

    // Pause current auto-scrolling before pushing the new page
    final wasAutoScrollEnabled = _autoScroll;
    if (_autoScroll) {
      setState(() {
        _autoScroll = false;
        _temporarilyIgnoreUserScroll = false;
        _userScrollSuppressionTimer?.cancel();
      });
    }

    // Navigate to the search page
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => LyricsSearchPage(
          initialTrackTitle: trackName,
          initialArtistName: artistName,
          trackId: trackId,
        ),
      ),
    )
        .then((result) {
      // This block executes when the search page is popped
      if (!mounted) return; // Check if widget is still mounted

      // If lyrics were returned from the search page
      if (result != null && result is String && result.isNotEmpty) {
        final summary = LyricTimingUtils.summarize(result);
        final parsed = _parseLyrics(result);
        final bool synced = summary.hasTimestamps && parsed.isNotEmpty;
        final newLyrics = synced ? parsed : _buildUnsyncedLyrics(result);
        _quickActionsHideTimer?.cancel();
        setState(() {
          _lyrics = newLyrics;
          _lyricsAreSynced = synced;
          _lastTrackId =
              trackId; // Update last track ID as we applied lyrics for it
          _previousLineIndex = -1; // Reset previous index
          _translationsVisible = false;
          _isTranslationLoading = false;
          _syncLineKeys(_lyrics.length);
          _manualQuickActionsVisible = false;

          // Restore auto-scroll if it was enabled before searching
          if (wasAutoScrollEnabled && synced) {
            _autoScroll = true;
            _temporarilyIgnoreUserScroll = true;

            // Trigger scroll to the current position after lyrics update
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autoScroll) {
                final currentProgressMs =
                    spotifyProvider.currentTrack?['progress_ms'] ?? 0;
                final currentPosition =
                    Duration(milliseconds: currentProgressMs);
                final currentIndex = _getCurrentLineIndex(currentPosition);
                if (currentIndex >= 0) {
                  _scrollToCurrentLine(currentIndex);
                  _previousLineIndex = currentIndex;
                }
              }
            });
          } else {
            _autoScroll = false; // Keep it disabled if it was disabled before
            _temporarilyIgnoreUserScroll = false;
            _userScrollSuppressionTimer?.cancel();
          }
        });

        if (_lyrics.isNotEmpty) {
          unawaited(_maybeTriggerAutoTranslate());
        }

        if (wasAutoScrollEnabled && _lyricsAreSynced && _autoScroll) {
          _userScrollSuppressionTimer?.cancel();
          _userScrollSuppressionTimer = Timer(
            const Duration(milliseconds: 350),
            () {
              if (!mounted) return;
              setState(() {
                _temporarilyIgnoreUserScroll = false;
              });
            },
          );
        }

        // Show success message
        notificationService.showSnackBar(l10n.lyricsSearchAppliedSuccess);
      } else {
        // If no lyrics were returned or user cancelled,
        // restore auto-scroll state if it was previously enabled
        if (wasAutoScrollEnabled && !_autoScroll) {
          _enableAutoScrollWithSuppression();
          // Optionally trigger scroll again if needed upon returning
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _autoScroll) {
              final currentProgressMs =
                  spotifyProvider.currentTrack?['progress_ms'] ?? 0;
              final currentPosition = Duration(milliseconds: currentProgressMs);
              final currentIndex = _getCurrentLineIndex(currentPosition);
              if (currentIndex >= 0) {
                _scrollToCurrentLine(currentIndex);
                _previousLineIndex = currentIndex;
              }
            }
          });
        }
      }
    });
  }

  // Method to navigate to the lyrics selection page
  Future<void> _showLyricsSelectionPage() async {
    if (!mounted) return;

    final spotifyProvider =
        Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack?['item'];
    final notificationService =
        Provider.of<NotificationService>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    if (currentTrack == null) {
      notificationService.showSnackBar(l10n.noCurrentTrackPlaying);
      return;
    }

    if (_lyrics.isEmpty) {
      notificationService.showSnackBar(l10n.noLyricsToSelect);
      return;
    }

    final trackName = currentTrack['name'] ?? '';
    final artistName = (currentTrack['artists'] as List?)
            ?.map((artist) => artist['name'] as String)
            .join(', ') ??
        '';
    final albumCoverUrl =
        (currentTrack['album']?['images'] as List?)?.isNotEmpty == true
            ? currentTrack['album']['images'][0]['url']
            : null;

    // 暂停当前的自动滚动
    final wasAutoScrollEnabled = _autoScroll;
    if (_autoScroll) {
      setState(() {
        _autoScroll = false;
        _temporarilyIgnoreUserScroll = false;
        _userScrollSuppressionTimer?.cancel();
      });
    }

    final originalLines = _lyrics.map((line) => line.text).toList();
    final originalLyricsJoined = originalLines.join('\n');
    final currentStyle =
        _activeTranslationStyle ?? await _settingsService.getTranslationStyle();

    if (!mounted) return;

    final List<Map<String, dynamic>> lyricsData = _lyrics
        .map((line) => {
              'timestamp': line.timestamp,
              'text': line.text,
              'translation': line.translation,
            })
        .toList();

    await ResponsiveNavigation.showSecondaryPage(
      context: context,
      child: LyricsSelectionPage(
        lyrics: lyricsData,
        trackTitle: trackName,
        artistName: artistName,
        albumCoverUrl: albumCoverUrl,
        initialShowTranslation: _translationsVisible,
        initialStyle: currentStyle,
        loadTranslation: ({
          bool forceRefresh = false,
          TranslationStyle? style,
        }) {
          return _loadTranslationData(
            forceRefresh: forceRefresh,
            style: style,
            overrideOriginalLines: originalLines,
          );
        },
        originalLyrics: originalLyricsJoined,
      ),
      preferredMode: SecondaryPageMode.sideSheet,
      maxWidth: 520,
    );

    if (!mounted) return;

    if (_translationsVisible) {
      try {
        final result = await _loadTranslationData(
          overrideOriginalLines: originalLines,
          style: _activeTranslationStyle,
        );
        if (mounted) {
          setState(() {
            _applyTranslationToLyrics(result.perLineTranslations);
            _activeTranslationStyle = result.style;
          });
          _scheduleRealignScroll();
        }
      } catch (_) {
        // Ignore refresh errors; UI will keep existing translations.
      }
    }

    if (wasAutoScrollEnabled && !_autoScroll) {
      _enableAutoScrollWithSuppression();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoScroll) {
          final currentProgressMs =
              spotifyProvider.currentTrack?['progress_ms'] ?? 0;
          final currentPosition = Duration(milliseconds: currentProgressMs);
          final currentIndex = _getCurrentLineIndex(currentPosition);
          if (currentIndex >= 0) {
            _scrollToCurrentLine(currentIndex);
            _previousLineIndex = currentIndex;
          }
        }
      });
    }
  }
}
