import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../providers/local_database_provider.dart';
import '../services/lyrics_service.dart';
import '../services/translation_service.dart';
import '../models/translation.dart';
import '../models/track.dart';
import './translation_result_sheet.dart';
import './lyrics_search_page.dart';
import 'dart:async';
import '../services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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

class _LyricsWidgetState extends State<LyricsWidget> {
  List<LyricLine> _lyrics = [];
  final LyricsService _lyricsService = LyricsService();
  final TranslationService _translationService = TranslationService();
  final SettingsService _settingsService = SettingsService();
  String? _lastTrackId;
  Timer? _progressTimer;
  Duration _currentPosition = Duration.zero;
  final ScrollController _scrollController = ScrollController();
  final Map<int, double> _lineHeights = {};
  final GlobalKey _listViewKey = GlobalKey();
  bool _autoScroll = true;
  bool _isTranslating = false;
  bool _isCopyLyricsMode = false;
  bool _isScrollRetryScheduled = false;
  PlayMode? _previousPlayMode;
  int _previousLineIndex = -1; // Track last scrolled line

  @override
  void initState() {
    super.initState();
    // 确保自动滚动在初始化时启用
    setState(() {
      _autoScroll = true;
    });
    _loadLyrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startProgressTimer();
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startProgressTimer() {
    if (!mounted) return;
    
    _progressTimer?.cancel();
    
    // 立即更新位置
    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    final isPlaying = provider.currentTrack?['is_playing'] ?? false;
    final spotifyProgress = provider.currentTrack?['progress_ms'] ?? 0;
    
    // 如果歌曲正在播放且有歌词，立即更新位置并触发滚动
    if (isPlaying && mounted && _lyrics.isNotEmpty) {
      final newPosition = Duration(milliseconds: spotifyProgress);
      
      if (_currentPosition != newPosition) {
        setState(() {
          _currentPosition = newPosition;
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoScroll && _lyrics.isNotEmpty) {
            final currentIndex = _getCurrentLineIndex(_currentPosition);
            if (currentIndex >= 0 && currentIndex != _previousLineIndex) {
              _previousLineIndex = currentIndex;
              _scrollToCurrentLine(currentIndex);
            }
          }
        });
      }
    }
    
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final provider = Provider.of<SpotifyProvider>(context, listen: false);
      final isPlaying = provider.currentTrack?['is_playing'] ?? false;
      final spotifyProgress = provider.currentTrack?['progress_ms'] ?? 0;
      
      if (isPlaying && mounted) {
        final newPosition = Duration(milliseconds: spotifyProgress);
        if (_currentPosition != newPosition) {
          setState(() {
            _currentPosition = newPosition;
          });
        }
        
        // 删除这段自动重新启用滚动的逻辑，保持用户滑动后滚动禁用状态
        // 直到用户明确点击按钮
      }
    });
  }

  Future<void> _loadLyrics() async {
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    if (!mounted) return;
    
    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = provider.currentTrack;
    if (currentTrack == null) return;

    final trackId = currentTrack['item']?['id'];
    if (trackId == null || trackId == _lastTrackId) return;
    
    _lastTrackId = trackId;
    final songName = currentTrack['item']?['name'] ?? '';
    final artistName = currentTrack['item']?['artists']?[0]?['name'] ?? '';
    
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _lyrics = [];
      _lineHeights.clear();
      _autoScroll = true;
    });

    final rawLyrics = await _lyricsService.getLyrics(songName, artistName, trackId);
    
    // Check mounted *before* accessing context again after await
    if (!mounted) return;
    
    final latestTrackId = Provider.of<SpotifyProvider>(context, listen: false).currentTrack?['item']?['id'];
    if (latestTrackId != trackId) {
      return;
    }

    if (rawLyrics != null) {
      setState(() {
        _lyrics = _parseLyrics(rawLyrics);
      });
      
      // Trigger scroll check immediately after lyrics are loaded and state is set
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _lastTrackId != trackId) return; // Check if still relevant

        final provider = Provider.of<SpotifyProvider>(context, listen: false);
        final isPlaying = provider.currentTrack?['is_playing'] ?? false;
        final currentProgressMs = provider.currentTrack?['progress_ms'] ?? 0;
        
        if (isPlaying && _autoScroll && _lyrics.isNotEmpty) {
          final currentPosition = Duration(milliseconds: currentProgressMs);
          final currentIndex = _getCurrentLineIndex(currentPosition);
          if (currentIndex >= 0) {
            // Ensure heights are estimated if not fully measured yet, similar to old logic
            final measuredHeightsCount = _lineHeights.length;
            if (measuredHeightsCount < _lyrics.length) {
              // Use average or default if needed
              final avgHeight = measuredHeightsCount > 0
                  ? _lineHeights.values.fold(0.0, (sum, h) => sum + h) / measuredHeightsCount
                  : 40.0; // Default fallback height
              for (int i = 0; i < _lyrics.length; i++) {
                _lineHeights.putIfAbsent(i, () => avgHeight);
              }
            }
            // Set previous index and scroll
            _previousLineIndex = currentIndex;
            _scrollToCurrentLine(currentIndex);
          }
        }
      });
    } else {
      setState(() {
        _lyrics = [];
      });
      if (mounted) {
        // Show error message using named placeholder
        notificationService.showSnackBar(AppLocalizations.of(context)!.lyricsFetchError('Failed to fetch lyrics'));
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
       if (mounted) {
         notificationService.showErrorSnackBar(l10n.couldNotGetCurrentTrackId);
         setState(() { _isTranslating = false; });
       }
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

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => TranslationResultSheet(
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
        ).then((_) {
          // This block executes after the bottom sheet is dismissed
          if (mounted && wasAutoScrolling) {
            // If auto-scroll was active before, ensure it still is
            // and trigger a scroll to the current line after the frame renders
            if (!_autoScroll) { // Only set state if it needs changing
              setState(() {
                _autoScroll = true;
              });
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                // Use the latest position and index when scrolling
                _scrollToCurrentLine(_getCurrentLineIndex(_currentPosition));
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
        !_autoScroll) {
      _isScrollRetryScheduled = false;
      return;
    }

    try {
      final RenderBox? renderBox = _listViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
         _isScrollRetryScheduled = false;
         return;
      }
      
      // 检查所有必需的行高是否可用
      bool heightsAvailable = true;
      for (int i = 0; i <= currentLineIndex; i++) {
        if (!_lineHeights.containsKey(i)) {
          heightsAvailable = false;
          break;
        }
      }

      if (!heightsAvailable) {
        if (!_isScrollRetryScheduled) {
          _isScrollRetryScheduled = true;
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && _autoScroll) {
               _isScrollRetryScheduled = false;
               final latestCurrentIndex = _getCurrentLineIndex(_currentPosition);
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

      _isScrollRetryScheduled = false;
      
      final viewportHeight = _scrollController.position.viewportDimension;
      final maxScroll = _scrollController.position.maxScrollExtent;
      
      // 计算当前行前的总高度
      double totalOffset = 0;
      for (int i = 0; i < currentLineIndex; i++) {
        totalOffset += _lineHeights[i]!;
      }
      
      // 添加当前行高度的一半
      final currentLineHeight = _lineHeights[currentLineIndex]!;
      totalOffset += currentLineHeight / 2;
      
      // 计算目标偏移量
      final topPadding = 80 + MediaQuery.of(context).padding.top;
      final targetOffset = totalOffset - (viewportHeight / 2) + topPadding;
      
      // 将滚动位置限制在有效范围内
      final clampedOffset = targetOffset.clamp(0.0, maxScroll);
      
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      // 滚动出错
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SpotifyProvider>(context);
 
    final l10n = AppLocalizations.of(context)!;

    // Calculate the current line index based on the latest position from provider
    // Do this in the build method to ensure it reflects the latest state
    final Duration latestPosition;
    if (provider.currentTrack?['progress_ms'] != null) {
      latestPosition = Duration(milliseconds: provider.currentTrack?['progress_ms']);
    } else {
      latestPosition = Duration.zero;
    }

    final currentLineIndex = _getCurrentLineIndex(latestPosition);

    return Consumer<SpotifyProvider>(
      builder: (context, provider, child) {
        final currentProgress = provider.currentTrack?['progress_ms'] ?? 0;
        final localCurrentPosition = Duration(milliseconds: currentProgress);
        
        if (_currentPosition != localCurrentPosition) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                 _currentPosition = localCurrentPosition;
              });
            }
          });
        }

        final currentTrackId = provider.currentTrack?['item']?['id'];
        if (currentTrackId != _lastTrackId) {
          if (_isCopyLyricsMode) {
            if (mounted) {
              Future.microtask(() {
                _toggleCopyLyricsMode();
              });
            }
          }
          if (mounted) {
             _previousLineIndex = -1;
             Future.microtask(() => _loadLyrics());
          }
        }

        final isPlaying = provider.currentTrack?['is_playing'] ?? false;
        if (!isPlaying) {
          _progressTimer?.cancel();
        } else if (_progressTimer == null || !_progressTimer!.isActive) {
          if (mounted) {
            Future.microtask(() => _startProgressTimer());
          }
        }

        if (_autoScroll && 
            mounted && 
            _lyrics.isNotEmpty && 
            currentTrackId == _lastTrackId &&
            currentLineIndex != _previousLineIndex) {
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _autoScroll) {
              _scrollToCurrentLine(currentLineIndex);
              _previousLineIndex = currentLineIndex;
            }
          });
        }

        return Material(
          color: Colors.transparent,
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollNotification) {
              if (!mounted) return true;
              
              if (scrollNotification is UserScrollNotification &&
                  scrollNotification.direction != ScrollDirection.idle) {
                if (_autoScroll) {
                  setState(() {
                    _autoScroll = false;
                  });
                }
              }
              return true;
            },
            child: Stack(
              children: [
                ListView.builder(
                  key: _listViewKey,
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: 80 + MediaQuery.of(context).padding.top,
                    bottom: 40 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: _lyrics.length + 10,
                  itemBuilder: (context, index) {
                    if (index >= _lyrics.length) {
                      return const SizedBox(height: 50.0);
                    }
                    
                    return MeasureSize(
                      onChange: (size) {
                        if (_lineHeights[index] != size.height) {
                          _lineHeights[index] = size.height;
                        }
                      },
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (!mounted) return;
                          
                          final provider = Provider.of<SpotifyProvider>(context, listen: false);
                          final tappedTimestamp = _lyrics[index].timestamp;
                          provider.seekToPosition(tappedTimestamp);

                          bool needsScrollTrigger = false;
                          if (_isCopyLyricsMode) {
                            _toggleCopyLyricsMode();
                          } else {
                            if (!_autoScroll) {
                              needsScrollTrigger = true; 
                              setState(() {
                                _autoScroll = true; 
                              });
                            }
                          }

                          if (needsScrollTrigger) {
                             WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && _autoScroll) {
                                   final latestCurrentIndex = _getCurrentLineIndex(_currentPosition);
                                   _scrollToCurrentLine(latestCurrentIndex);
                                   _previousLineIndex = latestCurrentIndex;
                                }
                             });
                          }
                        },
                        child: AnimatedPadding(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            vertical: index == currentLineIndex ? 12.0 : 8.0,
                            horizontal: MediaQuery.of(context).size.width > 600 ? 24.0 : 40.0,
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: MediaQuery.of(context).size.width > 600 ? 24 : 22,
                              fontWeight: index == currentLineIndex 
                                ? FontWeight.w700 
                                : FontWeight.w600,
                              color: index < currentLineIndex
                                ? Theme.of(context).colorScheme.secondaryContainer
                                : index == currentLineIndex
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.primary.withAlpha((0.5 * 255).round()),
                              height: 1.1,
                            ),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              opacity: index == currentLineIndex ? 1.0 : 0.8,
                              child: Text(
                                _lyrics[index].text,
                                textAlign: TextAlign.left,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 40 + MediaQuery.of(context).padding.top,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).scaffoldBackgroundColor,
                          Theme.of(context).scaffoldBackgroundColor,
                          Theme.of(context).scaffoldBackgroundColor.withAlpha((0.8 * 255).round()), // Updated opacity
                          Theme.of(context).scaffoldBackgroundColor.withAlpha((0.0 * 255).round()), // Updated opacity
                        ],
                        stops: const [0.0, 0.3, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
                if (!_autoScroll || _lyrics.isEmpty)
                  Positioned(
                    left: MediaQuery.of(context).size.width > 600 ? 24 : 16,
                    bottom: 24 + MediaQuery.of(context).padding.bottom,
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.vertical_align_center),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            if (!mounted) return;
                            
                            if (_isCopyLyricsMode) {
                              _toggleCopyLyricsMode();
                            } else {
                              setState(() {
                                _autoScroll = true; 
                              });
                            }
                          },
                          tooltip: l10n.centerCurrentLine,
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: _isTranslating 
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.translate),
                          onPressed: _isTranslating ? null : () {
                            HapticFeedback.lightImpact();
                            _translateAndShowLyrics();
                          },
                          tooltip: l10n.translateLyrics,
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: Icon(
                            _isCopyLyricsMode 
                              ? Icons.playlist_play_rounded
                              : Icons.edit_note_rounded,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _toggleCopyLyricsMode();
                          }, 
                          tooltip: _isCopyLyricsMode 
                              ? l10n.exitCopyModeResumeScroll 
                              : l10n.enterCopyLyricsMode,
                          style: ButtonStyle(
                            backgroundColor: _isCopyLyricsMode 
                              ? WidgetStateProperty.all( // Updated property
                                  Theme.of(context).colorScheme.primary.withAlpha((0.3 * 255).round()) // Updated opacity
                                ) 
                              : null,
                          ),
                        ),
                        // 将搜索按钮始终显示在抄歌词模式按钮的右边
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.search),
                          onPressed: _showSearchLyricsPage, 
                          tooltip: '搜索歌词', // 直接使用固定文本，不依赖未定义的本地化键
                        ),
                      ],
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
    if (_lyrics.isEmpty) return -1;
    
    
    if (_lyrics.isNotEmpty && currentPosition < _lyrics[0].timestamp) {
      return -1;
    }
    
    for (int i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].timestamp > currentPosition) {
        return i - 1;
      }
    }
    
    return _lyrics.length - 1;
  }

  List<LyricLine> _parseLyrics(String rawLyrics) {
    final lines = rawLyrics.split('\n');
    final List<LyricLine> result = [];
    
    for (var line in lines) {
      if (line.startsWith('[') && line.contains(']')) {
        final timeStr = line.substring(1, line.indexOf(']'));
        if (timeStr.contains(':')) {
          try {
            if (timeStr.contains('ti:') || timeStr.contains('ar:') || 
                timeStr.contains('al:') || timeStr.contains('by:') || 
                timeStr.contains('offset:')) {
              continue;
            }

            final parts = timeStr.split(':');
            if (parts.length == 2) {
              final minutes = int.parse(parts[0]);
              final seconds = double.parse(parts[1]);
              final timestamp = Duration(
                minutes: minutes,
                milliseconds: (seconds * 1000).round(),
              );
              var text = line.substring(line.indexOf(']') + 1).trim();
              // Decode HTML entities (moved from original code)
              text = text.replaceAll('&apos;', "'")
                        .replaceAll('&quot;', '"')
                        .replaceAll('&amp;', '&')
                        .replaceAll('&lt;', '<')
                        .replaceAll('&gt;', '>');
              if (text.isNotEmpty && !text.startsWith('[')) {
                // Skip empty lines resulting from metadata tags if any slipped through
                if (text.trim().isNotEmpty) { 
                  result.add(LyricLine(timestamp, text));
                }
              }
            }
          } catch (e) {
            // print('解析歌词行失败: $line, Error: $e'); // Log error too
          }
        }
      }
    }
    
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  void _toggleCopyLyricsMode() {
    if (!mounted) return;

    final provider = Provider.of<SpotifyProvider>(context, listen: false);

    setState(() {
      if (_isCopyLyricsMode) {
        // Exiting copy mode
        _isCopyLyricsMode = false;
        _autoScroll = true; // Resume auto-scroll
        // Restore previous play mode if it was saved
        if (_previousPlayMode != null) {
          provider.setPlayMode(_previousPlayMode!); 
        }
        // Trigger scroll after exiting copy mode and enabling autoScroll
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoScroll) {
            final latestCurrentIndex = _getCurrentLineIndex(_currentPosition);
            _scrollToCurrentLine(latestCurrentIndex);
            _previousLineIndex = latestCurrentIndex;
          }
        });
      } else {
        // Entering copy mode
        _isCopyLyricsMode = true;
        _autoScroll = false; // Disable auto-scroll
        // Store current mode and set to single repeat
        _previousPlayMode = provider.currentMode;
        provider.setPlayMode(PlayMode.singleRepeat);
        
        // Use the NotificationService to show the hint
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          Provider.of<NotificationService>(context, listen: false).showSnackBar(
            l10n.lyricsCopyModeSnackbar,
            duration: const Duration(seconds: 3),
          );
        }
      }
    });
  }

  // Method stub for showing the search page
  void _showSearchLyricsPage() {
    // Add handler for search page navigation
    if (!mounted) return;
    
    final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = spotifyProvider.currentTrack?['item'];
    
    if (currentTrack == null) {
      Provider.of<NotificationService>(context, listen: false)
        .showSnackBar('没有正在播放的歌曲');
      return;
    }
    
    final trackId = currentTrack['id'];
    final trackName = currentTrack['name'] ?? '';
    final artistName = currentTrack['artists']?[0]?['name'] ?? '';
    
    if (trackId == null || trackName.isEmpty) {
      Provider.of<NotificationService>(context, listen: false)
        .showSnackBar('无法获取当前歌曲信息');
      return;
    }
    
    // 暂停当前自动滚动
    final wasAutoScrollEnabled = _autoScroll;
    if (_autoScroll) {
      setState(() {
        _autoScroll = false;
      });
    }
    
    // 导航到搜索页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LyricsSearchPage(
          initialTrackTitle: trackName,
          initialArtistName: artistName,
          trackId: trackId,
        ),
      ),
    ).then((result) {
      // 处理返回值 (歌词文本)
      if (result != null && result is String && result.isNotEmpty) {
        setState(() {
          _lyrics = _parseLyrics(result);
          
          // 如果之前是自动滚动模式，恢复它
          if (wasAutoScrollEnabled) {
            _autoScroll = true;
            
            // 滚动到当前位置
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autoScroll) {
                final currentIndex = _getCurrentLineIndex(_currentPosition);
                if (currentIndex >= 0) {
                  _scrollToCurrentLine(currentIndex);
                  _previousLineIndex = currentIndex;
                }
              }
            });
          }
        });
        
        // 显示成功消息
        Provider.of<NotificationService>(context, listen: false)
          .showSnackBar('已成功搜索并应用歌词');
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