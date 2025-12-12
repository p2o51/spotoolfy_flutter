import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/app_localizations.dart';
import 'time_machine_carousel.dart'; // For AlbumColorExtractor

/// 随机回顾卡片 - 根据封面动态配色
class RandomReviewCard extends StatefulWidget {
  final Map<String, dynamic> record;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const RandomReviewCard({
    super.key,
    required this.record,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<RandomReviewCard> createState() => _RandomReviewCardState();
}

class _RandomReviewCardState extends State<RandomReviewCard> {
  ColorScheme? _cardColorScheme;
  String? _lastExtractedUrl;

  @override
  void initState() {
    super.initState();
    _extractColors();
  }

  @override
  void didUpdateWidget(RandomReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newUrl = widget.record['albumCoverUrl'] as String?;
    final oldUrl = oldWidget.record['albumCoverUrl'] as String?;
    if (newUrl != oldUrl) {
      _extractColors();
    }
  }

  Future<void> _extractColors() async {
    final albumCoverUrl = widget.record['albumCoverUrl'] as String?;
    if (albumCoverUrl == null || albumCoverUrl == _lastExtractedUrl) return;

    _lastExtractedUrl = albumCoverUrl;
    final brightness = Theme.of(context).brightness;
    final colorScheme = await AlbumColorExtractor.extractFromUrl(albumCoverUrl, brightness);

    if (mounted && colorScheme != null) {
      setState(() {
        _cardColorScheme = colorScheme;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultColorScheme = theme.colorScheme;
    final cardColors = _cardColorScheme ?? defaultColorScheme;

    final trackName = widget.record['trackName'] as String? ?? 'Unknown Track';
    final artistName = widget.record['artistName'] as String? ?? 'Unknown Artist';
    final noteContent = widget.record['noteContent'] as String? ?? '';
    final albumCoverUrl = widget.record['albumCoverUrl'] as String?;
    final lyricsSnapshot = widget.record['lyricsSnapshot'] as String?;

    // Get rating icon
    final dynamic ratingRaw = widget.record['rating'];
    int ratingValue = 3;
    if (ratingRaw is int) ratingValue = ratingRaw;
    IconData ratingIcon;
    switch (ratingValue) {
      case 0:
        ratingIcon = Icons.thumb_down_rounded;
        break;
      case 5:
        ratingIcon = Icons.whatshot_rounded;
        break;
      case 3:
      default:
        ratingIcon = Icons.sentiment_neutral_rounded;
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: cardColors.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cardColors.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap != null
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onTap!();
                  }
                : null,
            onLongPress: widget.onLongPress != null
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onLongPress!();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with badge
                  Row(
                    children: [
                      Icon(
                        Icons.shuffle_rounded,
                        size: 18,
                        color: cardColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.randomReviewTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cardColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Main content row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Album cover
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: albumCoverUrl ?? '',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 80,
                            height: 80,
                            color: cardColors.surfaceContainerHighest,
                            child: Icon(Icons.music_note_rounded,
                                size: 32, color: cardColors.onSurfaceVariant),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 80,
                            height: 80,
                            color: cardColors.surfaceContainerHighest,
                            child: Icon(Icons.music_note_rounded,
                                size: 32, color: cardColors.onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Track name
                            Text(
                              trackName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: cardColors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // Artist name
                            Text(
                              artistName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cardColors.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // Rating icon and tap hint
                            Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cardColors.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    ratingIcon,
                                    size: 14,
                                    color: cardColors.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Note content or lyrics snapshot
                  if (noteContent.isNotEmpty ||
                      (lyricsSnapshot != null && lyricsSnapshot.isNotEmpty)) ...[
                    const SizedBox(height: 8),
                    if (noteContent.isNotEmpty)
                      Text(
                        noteContent,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cardColors.onSurface,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (lyricsSnapshot != null &&
                        lyricsSnapshot.isNotEmpty &&
                        noteContent.isEmpty)
                      Text(
                        '"$lyricsSnapshot"',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cardColors.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
