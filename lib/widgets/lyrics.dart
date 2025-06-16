import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/local_database_provider.dart';
import '../services/lyrics_service.dart';
import '../services/translation_service.dart';
import '../models/translation.dart';
import '../models/track.dart';
import './translation_result_page.dart';
import './lyrics_search_page.dart';
import './lyrics_selection_page.dart';
import 'dart:async';
import '../services/settings_service.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../l10n/app_localizations.dart';

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine(this.timestamp, this.text);
}

class LyricsWidget extends StatefulWidget {
  const LyricsWidget({super.key});

  @override
  State<LyricsWidget> createState() => _LyricsWidgetState();
}

class _LyricsWidgetState extends State<LyricsWidget> with AutomaticKeepAliveClientMixin<LyricsWidget> {
  List<LyricLine> _lyrics = [];
  final LyricsService _lyricsService = LyricsService();
  final TranslationService _translationService = TranslationService();
  final SettingsService _settingsService = SettingsService();
  String? _lastTrackId;
  final ScrollController _scrollController = ScrollController();
  final Map<int, double> _lineHeights = {};
  final GlobalKey _listViewKey = GlobalKey();
  bool _autoScroll = true;
  bool _isTranslating = false;
  bool _isCopyLyricsMode = false;
  bool _isScrollRetryScheduled = false;
  int _scrollRetryCount = 0; // Track retry attempts
  PlayMode? _previousPlayMode;
  int _previousLineIndex = -1; // Track last scrolled line
  double? _cachedAverageHeight; // Cache average height for performance

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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    if (!mounted) return;
    
    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = provider.currentTrack;
    if (currentTrack == null) {
      // If no track is playing, clear lyrics and reset state
      if (_lyrics.isNotEmpty || _lastTrackId != null) {
        setState(() {
          _lyrics = [];
          _lastTrackId = null;
          _lineHeights.clear();
          _cachedAverageHeight = null; // Reset cached average height
          _scrollRetryCount = 0; // Reset retry count
          _autoScroll = true; // Default to auto-scroll when lyrics clear/load
          _previousLineIndex = -1;
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
      return;
    }

    final trackId = currentTrack['item']?['id'];
    // Only load if trackId is valid and different from the last loaded one
    if (trackId == null || trackId == _lastTrackId) return;
    
    _lastTrackId = trackId;
    final songName = currentTrack['item']?['name'] ?? '';
    final artistName = currentTrack['item']?['artists']?[0]?['name'] ?? '';
    
    // Reset state for the new track
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _lyrics = [];
      _lineHeights.clear();
      _cachedAverageHeight = null; // Reset cached average height
      _scrollRetryCount = 0; // Reset retry count for new track
      _autoScroll = true; // Default to auto-scroll when new lyrics load
      _previousLineIndex = -1;
    });

    final rawLyrics = await _lyricsService.getLyrics(songName, artistName, trackId);
    
    // Check mounted *before* accessing context again after await
    if (!mounted) return;
    
    final latestTrackId = Provider.of<SpotifyProvider>(context, listen: false).currentTrack?['item']?['id'];
    // Ensure the lyrics are still for the *current* track before updating state
    if (latestTrackId != trackId) {
      return;
    }

    if (rawLyrics != null) {
      setState(() {
        _lyrics = _parseLyrics(rawLyrics);
        // Keep _autoScroll = true here
        _previousLineIndex = -1; // Ensure index is reset for the new track
      });
    } else {
      // Lyrics fetch failed, keep lyrics list empty
      setState(() {
        _lyrics = [];
        // Keep _autoScroll = true
      });
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        notificationService.showSnackBar(l10n.lyricsFailedToLoad);
      }
    }
  }
  
  // Helper to estimate line heights if they are not fully measured
  void _ensureLineHeightsAvailable() {
     if (!mounted || _lyrics.isEmpty) return;
     final measuredHeightsCount = _lineHeights.length;
     if (measuredHeightsCount < _lyrics.length) {
        // Use cached average height if available, otherwise calculate
        if (_cachedAverageHeight == null && measuredHeightsCount > 0) {
          _cachedAverageHeight = _lineHeights.values.fold(0.0, (sum, h) => sum + h) / measuredHeightsCount;
        }
        final avgHeight = _cachedAverageHeight ?? 40.0; // Default fallback height
        for (int i = 0; i < _lyrics.length; i++) {
           _lineHeights.putIfAbsent(i, () => avgHeight);
        }
     }
  }

  Future<void> _translateAndShowLyrics() async {
    if (_lyrics.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      Provider.of<NotificationService>(context, listen: false)
          .showSnackBar(l10n.noLyricsToTranslate);
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    // Get providers and services
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);
    final currentTrackId = spotifyProvider.currentTrack?['item']?['id'];

    final notificationService = Provider.of<NotificationService>(context, listen: false);

    if (currentTrackId == null) {
      final l10n = AppLocalizations.of(context)!;
      notificationService.showSnackBar(l10n.couldNotGetCurrentTrackId);
      return;
    }

    String? errorMsg;

    try {
      // Combine lyric lines into a single string
      final originalLyrics = _lyrics.map((line) => line.text).toList();
      
      // Get current settings
      final currentStyle = await _settingsService.getTranslationStyle();
      final currentLanguage = await _settingsService.getTargetLanguage();
      final styleString = translationStyleToString(currentStyle);

      // *** TRY LOADING FROM DATABASE FIRST ***
      debugPrint('Attempting to load translation from DB: $currentTrackId, $currentLanguage, $styleString');
      final cachedTranslation = await localDbProvider.fetchTranslation(currentTrackId, currentLanguage, styleString);

      Map<String, String?>? translationData;
      String? fetchedTranslatedText;

      if (cachedTranslation != null && mounted) {
        debugPrint('Translation found in DB.');
        fetchedTranslatedText = cachedTranslation.translatedLyrics;
        // Use the language and style stored in the DB record
        translationData = {
          'text': fetchedTranslatedText,
          'languageCode': cachedTranslation.languageCode, // Use languageCode
          'style': cachedTranslation.style, // Make sure style is included
        };
        debugPrint('Loaded translation from DB: Lang=${cachedTranslation.languageCode}, Style=${cachedTranslation.style}'); // Use languageCode
      } else {
        debugPrint('Translation not found in DB. Calling API...');
        // *** FETCH FROM API IF NOT IN DB ***
        // Store the result map
        translationData = await _translationService.translateLyrics(
          originalLyrics.join('\n'), 
          currentTrackId, 
          targetLanguage: currentLanguage, // Pass current target language
        );
        fetchedTranslatedText = translationData?['text']; // Extract text from map

        // *** SAVE TO DB IF FETCHED FROM API ***
        if (mounted && fetchedTranslatedText != null && translationData != null) {
          // Use languageCode from the translation result
          final languageCodeUsed = translationData['languageCode'];
          final styleUsed = translationData['style']; // String name of the style

          if (languageCodeUsed != null && styleUsed != null) {
            try {
              // Ensure track exists first (logic copied from previous step)
              final existingTrack = await localDbProvider.getTrack(currentTrackId);
              if (existingTrack == null) {
                debugPrint('Track $currentTrackId not found in DB when saving API translation, adding it...');
                final trackItem = spotifyProvider.currentTrack?['item'];
                if (trackItem != null) {
                   final trackToAdd = Track(
                     trackId: currentTrackId,
                     trackName: trackItem['name'] as String,
                     artistName: (trackItem['artists'] as List).map((a) => a['name']).join(', '),
                     albumName: trackItem['album']?['name'] as String? ?? 'Unknown Album',
                     albumCoverUrl: (trackItem['album']?['images'] as List?)?.isNotEmpty == true
                                  ? trackItem['album']['images'][0]['url']
                                  : null,
                   );
                   await localDbProvider.addTrack(trackToAdd);
                   debugPrint('Track $currentTrackId added to DB.');
                } else {
                   throw Exception('Could not fetch track details for $currentTrackId');
                }
              }
              // Now save the translation using fetched details
              final translationToSave = Translation(
                trackId: currentTrackId,
                languageCode: languageCodeUsed, // Use languageCode
                style: styleUsed,             // Use style string from result
                translatedLyrics: fetchedTranslatedText,
                generatedAt: DateTime.now().millisecondsSinceEpoch,
              );
              await localDbProvider.saveTranslation(translationToSave);
              debugPrint('Translation fetched from API and saved to local DB for track $currentTrackId');
            } catch (dbOrTrackError) {
              debugPrint('Error ensuring track/saving API translation to local DB: $dbOrTrackError');
              errorMsg = 'Failed to save fetched translation: ${dbOrTrackError.toString()}';
            }
          } else {
             debugPrint('Translation result map missing language or style after API fetch.');
             errorMsg = 'Translation result incomplete.';
          }
        }
      } // End else (fetch from API)

      // *** SHOW BOTTOM SHEET IF TRANSLATION IS AVAILABLE ***
      if (mounted && fetchedTranslatedText != null) {
        final wasAutoScrolling = _autoScroll;
        final displayLanguageCode = translationData?['languageCode'] ?? currentLanguage; // Use languageCode
        final displayStyleString = translationData?['style'] ?? styleString;
        final displayStyleEnum = TranslationStyle.values.firstWhere(
          (e) => translationStyleToString(e) == displayStyleString,
          orElse: () => currentStyle,
        );

        // Temporarily disable auto-scroll while sheet is open
        if (_autoScroll) {
          setState(() { _autoScroll = false; });
        }

        // 使用 Navigator.push 导航到新页面
        final navigator = Navigator.of(context); // 捕获 navigator
        navigator.push(
          MaterialPageRoute(
            builder: (context) => TranslationResultPage( // <-- 使用新名称 TranslationResultPage
              originalLyrics: originalLyrics.join('\n'),
              translatedLyrics: fetchedTranslatedText!,
              translationStyle: displayStyleEnum,
              trackId: currentTrackId,
              onReTranslate: () async {
                // Re-translate logic fetches from API and saves to DB again
                String? newTranslationText;
                try {
                    // Call service, get the map
                    final retranslateResult = await _translationService.translateLyrics(
                      originalLyrics.join('\n'),
                      currentTrackId,
                      forceRefresh: true,
                      targetLanguage: displayLanguageCode, // Use the language code from this context
                    );

                    newTranslationText = retranslateResult?['text']; // Extract text

                    // Save if successful and component is mounted
                    if (mounted && newTranslationText != null && retranslateResult != null) {
                       final langCode = retranslateResult['languageCode']; // Use languageCode
                       final styleStr = retranslateResult['style'];

                       if (langCode != null && styleStr != null) {
                          try {
                             final retranslatedToSave = Translation(
                               trackId: currentTrackId,
                               languageCode: langCode, // Use languageCode for the retranslated entry
                               style: styleStr,
                               translatedLyrics: newTranslationText,
                               generatedAt: DateTime.now().millisecondsSinceEpoch,
                             );
                             await localDbProvider.saveTranslation(retranslatedToSave);
                             debugPrint('Re-translation saved to local DB for track $currentTrackId');
                          } catch (reSaveError) {
                             debugPrint('Error saving re-translation to local DB: $reSaveError');
                          }
                       } else {
                          debugPrint('Retranslate result map missing language or style.');
                       }
                    }
                    // Return ONLY the text (String?) as expected by the sheet
                    return newTranslationText;
                  } catch (e) {
                    debugPrint('Error during re-translation: $e');
                    // Return null or rethrow depending on how sheet handles error
                    return null;
                  }
              },
            ),
          ),
        ).then((_) {
          // 页面返回后的逻辑 (与之前 bottom sheet 关闭后的逻辑相同)
          if (mounted && wasAutoScrolling) {
            // If auto-scroll was active before, re-enable it
            // and trigger a scroll to the current line after the frame renders
            setState(() {
              _autoScroll = true;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autoScroll) {
                // Use the latest position from provider when scrolling
                final currentProvider = Provider.of<SpotifyProvider>(context, listen: false);
                final currentProgressMs = currentProvider.currentTrack?['progress_ms'] ?? 0;
                final currentPosition = Duration(milliseconds: currentProgressMs);
                final latestCurrentIndex = _getCurrentLineIndex(currentPosition);
                if (latestCurrentIndex >= 0) {
                    _scrollToCurrentLine(latestCurrentIndex);
                    _previousLineIndex = latestCurrentIndex; // Update index after scroll
                }
              }
            });
          }
        });
      } else if (mounted) {
          // Handle case where translation failed
          if (errorMsg != null) {
            notificationService.showErrorSnackBar(AppLocalizations.of(context)!.lyricsTranslationError(errorMsg));
            debugPrint('Translation failed: $errorMsg');
          } else {
            notificationService.showErrorSnackBar(AppLocalizations.of(context)!.lyricsTranslationError('Failed to translate lyrics'));
            debugPrint('Translation failed (generic).');
          }
      }

    } catch (e) {
       debugPrint('Error in translation process: $e');
       if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          notificationService.showErrorSnackBar(l10n.lyricsTranslationError(e.toString()));
       }
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  void _scrollToCurrentLine(int currentLineIndex) {
    if (!mounted ||
        currentLineIndex < 0 ||
        !_scrollController.hasClients ||
        _lyrics.isEmpty ||
        !_autoScroll) { // Keep autoScroll check
      _isScrollRetryScheduled = false;
      return;
    }

    try {
      final RenderBox? renderBox = _listViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
         _isScrollRetryScheduled = false;
         return;
      }
      
      // Check if all required line heights are available
      bool heightsAvailable = true;
      for (int i = 0; i <= currentLineIndex; i++) {
        if (!_lineHeights.containsKey(i)) {
          heightsAvailable = false;
          break;
        }
      }

      if (!heightsAvailable) {
        if (!_isScrollRetryScheduled && _scrollRetryCount < 3) { // Limit retries to 3
          _isScrollRetryScheduled = true;
          _scrollRetryCount++;
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && _autoScroll) { // Check autoScroll again
               _isScrollRetryScheduled = false;
               // Get latest index based on provider's progress
               final currentProvider = Provider.of<SpotifyProvider>(context, listen: false);
               final currentProgressMs = currentProvider.currentTrack?['progress_ms'] ?? 0;
               final currentPosition = Duration(milliseconds: currentProgressMs);
               final latestCurrentIndex = _getCurrentLineIndex(currentPosition);
               
               if (latestCurrentIndex >= 0 && latestCurrentIndex < _lyrics.length) {
                 _scrollToCurrentLine(latestCurrentIndex);
               }
            } else {
               _isScrollRetryScheduled = false;
            }
          });
        }
        return;
      }

      _isScrollRetryScheduled = false; // Reset retry flag if heights are available
      _scrollRetryCount = 0; // Reset retry count on successful scroll
      
      final viewportHeight = _scrollController.position.viewportDimension;
      final maxScroll = _scrollController.position.maxScrollExtent;
      
      // Calculate total height before the current line
      double totalOffset = 0;
      for (int i = 0; i < currentLineIndex; i++) {
        totalOffset += _lineHeights[i]!;
      }
      
      // Add half the height of the current line
      final currentLineHeight = _lineHeights[currentLineIndex]!;
      totalOffset += currentLineHeight / 2;
      
      // Calculate the target offset to center the line
      final topPadding = 80 + MediaQuery.of(context).padding.top;
      final targetOffset = totalOffset - (viewportHeight / 2) + topPadding;
      
      // Clamp the offset within the valid scroll range [0, maxScroll]
      final clampedOffset = targetOffset.clamp(0.0, maxScroll);
      
      // --- Calculate optimized dynamic duration based on scroll distance ---
      final currentOffset = _scrollController.offset;
      final scrollDistance = (clampedOffset - currentOffset).abs();
      
      // Improved duration calculation for smoother scrolling
      const double baseDurationMs = 250.0; // Reduced base duration for snappier feel
      const double extraMsPer1000Pixels = 150.0; // Reduced scaling for faster long scrolls
      const double maxDurationMs = 700.0; // Reduced max duration
      const double minDurationMs = 150.0; // Added minimum duration for very short scrolls

      final dynamicDurationMs = (baseDurationMs + (scrollDistance / 1000.0) * extraMsPer1000Pixels)
          .clamp(minDurationMs, maxDurationMs)
          .toInt();
      final duration = Duration(milliseconds: dynamicDurationMs);
      // --- End of optimized dynamic duration calculation ---

      // Animate the scroll with improved curve
      _scrollController.animateTo(
        clampedOffset,
        duration: duration, // Use optimized dynamic duration
        curve: Curves.easeInOutCubic, // More natural easing curve
      );
    } catch (e) {
      // Log scroll errors if necessary
      // debugPrint('Error scrolling lyrics: $e');
      _isScrollRetryScheduled = false; // Reset retry on error too
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
        final currentTrackData = provider.currentTrack; // Get current track data
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
        
        // 2. Calculate latest position and index based on provider state
        final currentProgressMs = currentTrackData?['progress_ms'] ?? 0;
        final latestPosition = Duration(milliseconds: currentProgressMs);
        final currentLineIndex = _getCurrentLineIndex(latestPosition);
        // debugPrint('[LyricsBuilder] Calculated Idx: $currentLineIndex (from ${currentProgressMs}ms)'); // Log calculated index

        // 3. Trigger scroll if needed (immediately within build if possible)
        if (_autoScroll && 
            _lyrics.isNotEmpty && 
            mounted && 
            currentLineIndex != _previousLineIndex) {

           // debugPrint('[LyricsScroll] Line change detected! New: $currentLineIndex, Old: $_previousLineIndex'); // Log line change detection

           // Update the index *before* attempting to scroll
           final int indexToScroll = currentLineIndex; // Capture current index
           // debugPrint('[LyricsScroll] Updating _previousLineIndex to $indexToScroll'); // Log index update
           _previousLineIndex = indexToScroll; // Update state *immediately* for next build

           // Ensure estimated heights so scroll can proceed without delay
           // debugPrint('[LyricsScroll] Calling _ensureLineHeightsAvailable()'); // Log height estimation call
           _ensureLineHeightsAvailable();
           // Check if scroll controller is attached to the view and attempt scroll
           if (_scrollController.hasClients) {
              // debugPrint('[LyricsScroll] Calling _scrollToCurrentLine($indexToScroll)'); // Log scroll function call
              _scrollToCurrentLine(indexToScroll); // Use the captured index
           } 
        }
        
        // REMOVED: Internal _currentPosition state update logic
        // REMOVED: Logic to start/stop internal _progressTimer based on isPlaying

        return Material(
          color: Colors.transparent,
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollNotification) {
              if (!mounted) return true;
              
              // Disable auto-scroll on user interaction
              if (scrollNotification is UserScrollNotification &&
                  scrollNotification.direction != ScrollDirection.idle) {
                if (_autoScroll) {
                  setState(() {
                    _autoScroll = false;
                  });
                }
              }
              return true; // Allow notification to bubble up
            },
            child: Stack(
              children: [
                ListView.builder(
                  key: _listViewKey,
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: 80 + MediaQuery.of(context).padding.top,
                    bottom: 40 + MediaQuery.of(context).padding.bottom, // Reverted bottom padding
                  ),
                  itemCount: _lyrics.length + 10, // Add padding at the end
                  itemBuilder: (context, index) {
                    if (index >= _lyrics.length) {
                      // Render empty space at the end for overscroll/padding
                      return const SizedBox(height: 50.0);
                    }
                    
                    // Measure the size of each lyric line
                    return MeasureSize(
                      onChange: (size) {
                        // Update height map directly without causing a rebuild
                        if (mounted && _lineHeights[index] != size.height) {
                          _lineHeights[index] = size.height;
                          // Invalidate cached average height when new measurements come in
                          if (_cachedAverageHeight != null && _lineHeights.length > 5) {
                            _cachedAverageHeight = null; // Force recalculation on next use
                          }
                        }
                      },
                      child: GestureDetector(
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
                              setState(() {
                                _autoScroll = true; 
                              });
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
                                   _previousLineIndex = index; // Update index after tap scroll
                                }
                             });
                          }
                        },
                        child: AnimatedPadding(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            vertical: index == currentLineIndex ? 12.0 : 8.0,
                            // Responsive horizontal padding
                            horizontal: MediaQuery.of(context).size.width > 600 ? 24.0 : 40.0, // Reverted padding
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              fontFamily: 'Montserrat', // Consider making this configurable
                              fontSize: MediaQuery.of(context).size.width > 600 ? 24 : 22,
                              fontWeight: index == currentLineIndex 
                                ? FontWeight.w700 
                                : FontWeight.w600,
                              color: index < currentLineIndex
                                ? Theme.of(context).colorScheme.secondaryContainer // Past lines color
                                : index == currentLineIndex
                                  ? Theme.of(context).colorScheme.primary // Current line color
                                  : Theme.of(context).colorScheme.primary.withAlpha((0.5 * 255).round()), // Future lines color - Reverted alpha
                              height: 1.1, // Line height for readability - Reverted height
                            ),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              opacity: index == currentLineIndex ? 1.0 : 0.8, // Reverted opacity logic
                              child: Text(
                                _lyrics[index].text,
                                textAlign: TextAlign.left, // Align text left
                              ),
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
                  height: 40 + MediaQuery.of(context).padding.top, // Reverted height
                  child: IgnorePointer( // Makes gradient non-interactive
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(context).scaffoldBackgroundColor,
                            Theme.of(context).scaffoldBackgroundColor, // Reverted: Original had 2 solid colors
                            Theme.of(context).scaffoldBackgroundColor.withAlpha((0.8 * 255).round()),
                            Theme.of(context).scaffoldBackgroundColor.withAlpha((0.0 * 255).round()),
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0], // Reverted stops
                        ),
                      ),
                    ),
                  ),
                ),
                // Buttons overlay at the bottom
                if (!_autoScroll || _lyrics.isEmpty || _isCopyLyricsMode) // Show buttons if not auto-scrolling, lyrics empty, or in copy mode
                  Positioned(
                    left: MediaQuery.of(context).size.width > 600 ? 24 : 16, // Reverted left positioning
                    bottom: 24 + MediaQuery.of(context).padding.bottom, // Reverted bottom positioning
                    child: Padding(
                      padding: EdgeInsets.zero, // Removed horizontal padding wrapper
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start, // Reverted alignment to start
                        children: [
                          // Center/Resume Scroll Button
                          if (!_autoScroll && _lyrics.isNotEmpty) // Show only if not auto-scrolling and lyrics exist
                            IconButton.filledTonal(
                              icon: const Icon(Icons.vertical_align_center),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                if (!mounted) return;
                                // Enable auto-scroll and trigger scroll immediately
                                setState(() { _autoScroll = true; });
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                   if (mounted && _autoScroll) {
                                      final latestCurrentIndex = _getCurrentLineIndex(latestPosition);
                                      _scrollToCurrentLine(latestCurrentIndex);
                                      _previousLineIndex = latestCurrentIndex;
                                   }
                                });
                              },
                              tooltip: l10n.centerCurrentLine, // "Center Current Line"
                            ),
                          if (!_autoScroll && _lyrics.isNotEmpty) const SizedBox(width: 8), // Spacer

                          // Translate Button
                          IconButton.filledTonal(
                            icon: _isTranslating 
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.translate),
                            onPressed: _isTranslating || _lyrics.isEmpty ? null : () { // Disable if translating or no lyrics
                              HapticFeedback.lightImpact();
                              _translateAndShowLyrics();
                            },
                            tooltip: l10n.translateLyrics, // "Translate Lyrics"
                          ),
                          const SizedBox(width: 8),

                          // Copy/Edit Mode Button
                          IconButton.filledTonal(
                            icon: Icon(
                              _isCopyLyricsMode 
                                ? Icons.playlist_play_rounded // Exit icon
                                : Icons.edit_note_rounded, // Enter icon
                            ),
                            onPressed: _lyrics.isEmpty ? null : () { // Disable if no lyrics
                              HapticFeedback.lightImpact();
                              _toggleCopyLyricsMode();
                            }, 
                            tooltip: _isCopyLyricsMode 
                                ? l10n.exitCopyModeResumeScroll // "Exit Copy Mode & Resume Scroll"
                                : l10n.enterCopyLyricsMode, // "Enter Copy Lyrics Mode"
                            style: ButtonStyle(
                              // Visual feedback when in copy mode
                              backgroundColor: _isCopyLyricsMode 
                                ? WidgetStateProperty.all(
                                    Theme.of(context).colorScheme.primary.withAlpha((0.3 * 255).round())
                                  ) 
                                : null,
                              foregroundColor: _isCopyLyricsMode
                                ? WidgetStateProperty.all(Theme.of(context).colorScheme.onPrimary)
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
                            onPressed: _lyrics.isEmpty ? null : _showLyricsSelectionPage,
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
                  milliseconds = int.parse(millisecondsStr) * 10; // 2 digits -> centiseconds to milliseconds
              } else {
                  milliseconds = int.parse(millisecondsStr); // 3 digits -> milliseconds
              }
          }

          final timestamp = Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          );

          var text = line.substring(match.end).trim();
          // Decode common HTML entities
          text = text.replaceAll('&apos;', "'")
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

    setState(() {
      if (_isCopyLyricsMode) {
        // --- Exiting copy mode ---
        _isCopyLyricsMode = false;
        _autoScroll = true; // Resume auto-scroll implicitly
        // Restore previous play mode if it was saved
        if (_previousPlayMode != null) {
          provider.setPlayMode(_previousPlayMode!); 
          _previousPlayMode = null; // Clear saved mode
        }
        // Trigger scroll after exiting copy mode and enabling autoScroll
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoScroll) {
            // Get latest index based on provider's progress
            final currentProgressMs = provider.currentTrack?['progress_ms'] ?? 0;
            final currentPosition = Duration(milliseconds: currentProgressMs);
            final latestCurrentIndex = _getCurrentLineIndex(currentPosition);
            if (latestCurrentIndex >= 0) {
                _scrollToCurrentLine(latestCurrentIndex);
                _previousLineIndex = latestCurrentIndex; // Update index after scroll
            }
          }
        });
      } else {
        // --- Entering copy mode ---
        _isCopyLyricsMode = true;
        _autoScroll = false; // Disable auto-scroll explicitly
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
  }

  // Method to navigate to the lyrics search page
  void _showSearchLyricsPage() {
    if (!mounted) return;
    
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack?['item'];
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    if (currentTrack == null) {
      notificationService.showSnackBar(l10n.noCurrentTrackPlaying);
      return;
    }
    
    final trackId = currentTrack['id'];
    final trackName = currentTrack['name'] ?? '';
    final artistName = (currentTrack['artists'] as List?)
                          ?.map((artist) => artist['name'] as String)
                          .join(', ') ?? ''; // Join multiple artists
    
    if (trackId == null || trackName.isEmpty) {
      notificationService.showSnackBar(l10n.cannotGetTrackInfo);
      return;
    }
    
    // Pause current auto-scrolling before pushing the new page
    final wasAutoScrollEnabled = _autoScroll;
    if (_autoScroll) {
      setState(() { _autoScroll = false; });
    }
    
    // Navigate to the search page
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LyricsSearchPage(
          initialTrackTitle: trackName,
          initialArtistName: artistName,
          trackId: trackId,
        ),
      ),
    ).then((result) {
      // This block executes when the search page is popped
      if (!mounted) return; // Check if widget is still mounted

      // If lyrics were returned from the search page
      if (result != null && result is String && result.isNotEmpty) {
        final newLyrics = _parseLyrics(result);
        setState(() {
          _lyrics = newLyrics;
          _lastTrackId = trackId; // Update last track ID as we applied lyrics for it
          _lineHeights.clear(); // Clear old heights
          _previousLineIndex = -1; // Reset previous index

          // Restore auto-scroll if it was enabled before searching
          if (wasAutoScrollEnabled) {
            _autoScroll = true;
            
            // Trigger scroll to the current position after lyrics update
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autoScroll) {
                final currentProgressMs = spotifyProvider.currentTrack?['progress_ms'] ?? 0;
                final currentPosition = Duration(milliseconds: currentProgressMs);
                final currentIndex = _getCurrentLineIndex(currentPosition);
                if (currentIndex >= 0) {
                  _ensureLineHeightsAvailable(); // Ensure heights estimated
                  _scrollToCurrentLine(currentIndex);
                  _previousLineIndex = currentIndex;
                }
              }
            });
          } else {
             _autoScroll = false; // Keep it disabled if it was disabled before
          }
        });
        
        // Show success message
        notificationService.showSnackBar(l10n.lyricsSearchAppliedSuccess);
      } else {
         // If no lyrics were returned or user cancelled,
         // restore auto-scroll state if it was previously enabled
         if (wasAutoScrollEnabled && !_autoScroll) {
            setState(() { _autoScroll = true; });
            // Optionally trigger scroll again if needed upon returning
            WidgetsBinding.instance.addPostFrameCallback((_){
               if(mounted && _autoScroll) {
                  final currentProgressMs = spotifyProvider.currentTrack?['progress_ms'] ?? 0;
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
  void _showLyricsSelectionPage() {
    if (!mounted) return;
    
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack?['item'];
    final notificationService = Provider.of<NotificationService>(context, listen: false);
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
                          .join(', ') ?? '';
    final albumCoverUrl = (currentTrack['album']?['images'] as List?)?.isNotEmpty == true
                        ? currentTrack['album']['images'][0]['url']
                        : null;
    
    // 暂停当前的自动滚动
    final wasAutoScrollEnabled = _autoScroll;
    if (_autoScroll) {
      setState(() { _autoScroll = false; });
    }
    
    // 准备歌词数据，包含时间戳和文本
    final List<Map<String, dynamic>> lyricsData = _lyrics.map((line) => {
      'timestamp': line.timestamp,
      'text': line.text,
    }).toList();
    
    // 导航到选择页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LyricsSelectionPage(
          lyrics: lyricsData, //传递包含时间戳和文本的列表
          trackTitle: trackName,
          artistName: artistName,
          albumCoverUrl: albumCoverUrl,
        ),
      ),
    ).then((_) {
      // 页面返回后恢复自动滚动状态
      if (!mounted) return;
      
      if (wasAutoScrollEnabled && !_autoScroll) {
        setState(() { _autoScroll = true; });
        // 触发滚动到当前位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoScroll) {
            final currentProgressMs = spotifyProvider.currentTrack?['progress_ms'] ?? 0;
            final currentPosition = Duration(milliseconds: currentProgressMs);
            final currentIndex = _getCurrentLineIndex(currentPosition);
            if (currentIndex >= 0) {
              _scrollToCurrentLine(currentIndex);
              _previousLineIndex = currentIndex;
            }
          }
        });
      }
    });
  }
}

class MeasureSize extends StatefulWidget {
  final Widget child;
  final Function(Size) onChange;

  const MeasureSize({
    super.key, // Use super parameter
    required this.onChange,
    required this.child,
  });

  @override
  // ignore: library_private_types_in_public_api
  _MeasureSizeState createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  final widgetKey = GlobalKey();
  Size? oldSize;

  @override
  void initState() {
    super.initState();
    // 初始构建后立即测量尺寸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSize();
    });
  }
  
  @override
  void didUpdateWidget(MeasureSize oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 组件更新后检查尺寸变化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSize();
    });
  }

  void _measureSize() {
    if (!mounted) return;
    
    final context = widgetKey.currentContext;
    if (context == null) return;
    
    final RenderBox box = context.findRenderObject() as RenderBox;
    if (!box.hasSize) {
      // 如果尺寸还不可用，在下一帧再次尝试
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureSize();
      });
      return;
    }
    
    final size = box.size;
    
    if (oldSize != size) {
      oldSize = size;
      widget.onChange(size);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: widgetKey,
      child: widget.child,
    );
  }
}