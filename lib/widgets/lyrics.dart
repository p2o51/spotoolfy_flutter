import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../services/lyrics_service.dart';
import 'dart:async';
import 'dart:math' as math;

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine(this.timestamp, this.text);
}

class LyricsWidget extends StatefulWidget {
  const LyricsWidget({Key? key}) : super(key: key);

  @override
  State<LyricsWidget> createState() => _LyricsWidgetState();
}

class _LyricsWidgetState extends State<LyricsWidget> {
  List<LyricLine> _lyrics = [];
  final LyricsService _lyricsService = LyricsService();
  String? _lastTrackId;
  Timer? _progressTimer;
  Duration _currentPosition = Duration.zero;
  final ScrollController _scrollController = ScrollController();
  final Map<int, double> _lineHeights = {};
  final GlobalKey _listViewKey = GlobalKey();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
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
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        final provider = Provider.of<SpotifyProvider>(context, listen: false);
        final isPlaying = provider.currentTrack?['is_playing'] ?? false;
        final spotifyProgress = provider.currentTrack?['progress_ms'] ?? 0;
        
        if (isPlaying) {
          setState(() {
            _currentPosition = Duration(milliseconds: spotifyProgress);
          });
        }
      }
    });
  }

  Future<void> _loadLyrics() async {
    final provider = Provider.of<SpotifyProvider>(context, listen: false);
    final currentTrack = provider.currentTrack;
    if (currentTrack == null) return;

    final trackId = currentTrack['item']?['id'];
    if (trackId == null || trackId == _lastTrackId) return;
    
    _lastTrackId = trackId;
    final songName = currentTrack['item']?['name'] ?? '';
    final artistName = currentTrack['item']?['artists']?[0]?['name'] ?? '';
    
    final rawLyrics = await _lyricsService.getLyrics(songName, artistName, trackId);
    if (rawLyrics != null) {
      setState(() {
        _lyrics = _parseLyrics(rawLyrics);
      });
    }
  }

  void _scrollToCurrentLine(int currentLineIndex) {
    if (!mounted || 
        currentLineIndex < 0 || 
        !_scrollController.hasClients || 
        _lyrics.isEmpty) return;

    try {
      final RenderBox? renderBox = _listViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final viewportHeight = _scrollController.position.viewportDimension;
      
      double totalOffset = 0;
      for (int i = 0; i < currentLineIndex; i++) {
        totalOffset += _lineHeights[i] ?? 50.0;
      }
      
      final currentLineHeight = _lineHeights[currentLineIndex] ?? 50.0;
      totalOffset += currentLineHeight / 2;
      
      final offset = totalOffset - (viewportHeight / 2);
      
      _scrollController.animateTo(
        math.max(0, offset),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      print('滚动到当前行时出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SpotifyProvider>(
      builder: (context, provider, child) {
        final currentProgress = provider.currentTrack?['progress_ms'] ?? 0;
        if (_currentPosition.inMilliseconds != currentProgress) {
          _currentPosition = Duration(milliseconds: currentProgress);
        }

        final currentTrackId = provider.currentTrack?['item']?['id'];
        if (currentTrackId != _lastTrackId) {
          Future.microtask(() => _loadLyrics());
        }

        final isPlaying = provider.currentTrack?['is_playing'] ?? false;
        if (!isPlaying) {
          _progressTimer?.cancel();
        } else if (_progressTimer == null || !_progressTimer!.isActive) {
          Future.microtask(() => _startProgressTimer());
        }

        final currentLineIndex = _getCurrentLineIndex(_currentPosition);

        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToCurrentLine(currentLineIndex);
          });
        }

        return Stack(
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) {
                final fadeHeight = 40.0;
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [
                    0.0,
                    fadeHeight / bounds.height,
                    1 - (fadeHeight / bounds.height),
                    1.0,
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollNotification) {
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
                child: ListView.builder(
                  key: _listViewKey,
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _lyrics.length + 10,
                  itemBuilder: (context, index) {
                    if (index >= _lyrics.length) {
                      return const SizedBox(height: 50.0);
                    }
                    
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return MeasureSize(
                          onChange: (size) {
                            if (_lineHeights[index] != size.height) {
                              _lineHeights[index] = size.height;
                            }
                          },
                          child: GestureDetector(
                            onTap: () {
                              final provider = Provider.of<SpotifyProvider>(
                                context, 
                                listen: false
                              );
                              provider.seekToPosition(_lyrics[index].timestamp);
                              setState(() {
                                _autoScroll = true;
                              });
                            },
                            child: AnimatedPadding(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              padding: EdgeInsets.symmetric(
                                vertical: index == currentLineIndex ? 16.0 : 12.0,
                                horizontal: 24.0,
                              ),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: index == currentLineIndex 
                                    ? FontWeight.w700 
                                    : FontWeight.w600,
                                  color: index < currentLineIndex
                                    ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                                    : index == currentLineIndex
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondaryContainer,
                                  height: 1.2,
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
                    );
                  },
                ),
              ),
            ),
            if (!_autoScroll)
              Positioned(
                left: 16,
                bottom: 24,
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.vertical_align_center),
                  onPressed: () {
                    setState(() {
                      _autoScroll = true;
                    });
                    _scrollToCurrentLine(currentLineIndex);
                  },
                  tooltip: '返回到当前播放位置',
                ),
              ),
          ],
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
              final text = line.substring(line.indexOf(']') + 1).trim();
              if (text.isNotEmpty && !text.startsWith('[')) {
                result.add(LyricLine(timestamp, text));
              }
            }
          } catch (e) {
            print('解析歌词行失败: $line');
          }
        }
      }
    }
    
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}

class MeasureSize extends StatefulWidget {
  final Widget child;
  final Function(Size) onChange;

  const MeasureSize({
    Key? key,
    required this.onChange,
    required this.child,
  }) : super(key: key);

  @override
  _MeasureSizeState createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  final widgetKey = GlobalKey();
  Size? oldSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSize();
    });
  }

  void _measureSize() {
    final context = widgetKey.currentContext;
    if (context == null) return;
    
    final RenderBox box = context.findRenderObject() as RenderBox;
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