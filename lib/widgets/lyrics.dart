import 'package:flutter/material.dart';
import 'materialui.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../services/lyrics_service.dart';
import 'dart:async';
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
          print('Spotify progress: ${spotifyProgress}ms');
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
    
    final rawLyrics = await _lyricsService.getLyrics(songName, artistName);
    if (rawLyrics != null) {
      setState(() {
        _lyrics = _parseLyrics(rawLyrics);
      });
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

        return Column(
          children: [
            const SizedBox(height: 24),
            const IconHeader(icon: Icons.lyrics, text: "LYRICS"),
            Expanded(
              child: ListView.builder(
                itemCount: _lyrics.length,
                itemBuilder: (context, index) {
                  final isCurrentLine = index == currentLineIndex;
                  final isPastLine = index < currentLineIndex;
                  
                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      vertical: isCurrentLine ? 16.0 : 12.0,
                      horizontal: 24.0,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: isCurrentLine ? FontWeight.w700 : FontWeight.w600,
                        color: isPastLine
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : isCurrentLine
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
                        height: 1.5,
                      ),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        opacity: isCurrentLine ? 1.0 : 0.8,
                        child: Text(
                          _lyrics[index].text,
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  int _getCurrentLineIndex(Duration currentPosition) {
    if (_lyrics.isEmpty) return -1;
    
    print('Current position ms: ${currentPosition.inMilliseconds}');
    
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
