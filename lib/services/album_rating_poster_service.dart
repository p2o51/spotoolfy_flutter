import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AlbumRatingPosterService {
  AlbumRatingPosterService();

  final Logger _logger = Logger();

  Future<void> shareAlbumPoster({
    required String albumName,
    required String artistLine,
    required double? averageScore,
    required int ratedTrackCount,
    required int totalTrackCount,
    required List<Map<String, dynamic>> tracks,
    required Map<String, int?> trackRatings,
    required Map<String, int?> trackRatingTimestamps,
    required ColorScheme colorScheme,
    String? albumCoverUrl,
    String? fontFamily,
    String? insightsTitle,
    String? shareText,
  }) async {
    final posterBytes = await generatePosterData(
      albumName: albumName,
      artistLine: artistLine,
      averageScore: averageScore,
      ratedTrackCount: ratedTrackCount,
      totalTrackCount: totalTrackCount,
      tracks: tracks,
      trackRatings: trackRatings,
      trackRatingTimestamps: trackRatingTimestamps,
      colorScheme: colorScheme,
      albumCoverUrl: albumCoverUrl,
      fontFamily: fontFamily,
      insightsTitle: insightsTitle,
    );

    final tempDir = await getTemporaryDirectory();
    final fileName =
        'album_rating_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(posterBytes);

    try {
      await Share.shareXFiles([XFile(file.path)], text: shareText);
    } catch (e, s) {
      _logger.e('Failed to share album rating poster', error: e, stackTrace: s);
      rethrow;
    }
  }

  Future<Uint8List> generatePosterData({
    required String albumName,
    required String artistLine,
    required double? averageScore,
    required int ratedTrackCount,
    required int totalTrackCount,
    required List<Map<String, dynamic>> tracks,
    required Map<String, int?> trackRatings,
    required Map<String, int?> trackRatingTimestamps,
    required ColorScheme colorScheme,
    String? albumCoverUrl,
    String? fontFamily,
    String? insightsTitle,
  }) async {
    const double width = 1080;
    const double height = 1920;
    const double horizontalPadding = 96.0;
    const double topPadding = 120.0;
    const double coverSize = 480.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    final backgroundPaint = Paint()..color = colorScheme.surface;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), backgroundPaint);

    ui.Image? coverImage;
    if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
      coverImage = await _loadNetworkImage(albumCoverUrl);
    }

    double currentY = topPadding;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;
    final primary = colorScheme.primary;
    final primaryContainer = colorScheme.primaryContainer;
    final onPrimaryContainer = colorScheme.onPrimaryContainer;
    final surfaceContainerHighest = colorScheme.surfaceContainerHighest;

    final coverRect = Rect.fromLTWH(
      (width - coverSize) / 2,
      currentY,
      coverSize,
      coverSize,
    );

    if (coverImage != null) {
      final coverRRect =
          RRect.fromRectAndRadius(coverRect, const Radius.circular(48));
      canvas.save();
      canvas.clipRRect(coverRRect);
      final srcRect = Rect.fromLTWH(
        0,
        0,
        coverImage.width.toDouble(),
        coverImage.height.toDouble(),
      );
      canvas.drawImageRect(coverImage, srcRect, coverRect, Paint());
      canvas.restore();

      // 添加 Material 风格的封面边框
      final borderPaint = Paint()
        ..color = surfaceContainerHighest.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(coverRRect, borderPaint);
    } else {
      final placeholderPaint = Paint()
        ..color = surfaceContainerHighest.withValues(alpha: 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(coverRect, const Radius.circular(48)),
        placeholderPaint,
      );
      _paintText(
        canvas,
        text: 'No Cover',
        maxWidth: coverSize - 40,
        offset: Offset(coverRect.center.dx, coverRect.center.dy),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: onSurfaceVariant.withValues(alpha: 0.6),
        ),
        align: TextAlign.center,
        center: true,
      );
    }

    currentY = coverRect.bottom + 56;

    _paintText(
      canvas,
      text: albumName,
      maxWidth: width - horizontalPadding * 2,
      offset: Offset(width / 2, currentY),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: 64,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: -0.5,
      ),
      align: TextAlign.center,
      center: true,
    );
    currentY += 96;

    if (insightsTitle != null && insightsTitle.trim().isNotEmpty) {
      // 为 insights 添加突出的背景标签
      final insightsPainter = TextPainter(
        text: TextSpan(
          text: insightsTitle.trim(),
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 38,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.25,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      insightsPainter.layout(maxWidth: width - horizontalPadding * 2);

      final insightsBgRect = Rect.fromCenter(
        center: Offset(width / 2, currentY + insightsPainter.height / 2),
        width: insightsPainter.width + 48,
        height: insightsPainter.height + 24,
      );
      final insightsBgPaint = Paint()
        ..color = primaryContainer.withValues(alpha: 0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(insightsBgRect, const Radius.circular(20)),
        insightsBgPaint,
      );

      _paintText(
        canvas,
        text: insightsTitle.trim(),
        maxWidth: width - horizontalPadding * 2,
        offset: Offset(width / 2, currentY),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 38,
          fontWeight: FontWeight.w500,
          color: onPrimaryContainer,
          letterSpacing: 0.25,
        ),
        align: TextAlign.center,
        center: true,
      );
      currentY += 68;
    }

    _paintText(
      canvas,
      text: artistLine,
      maxWidth: width - horizontalPadding * 2,
      offset: Offset(width / 2, currentY),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: onSurfaceVariant.withValues(alpha: 0.8),
        letterSpacing: 0.15,
      ),
      align: TextAlign.center,
      center: true,
    );
    currentY += 96;

    // 为评分数字添加 Primary Container 背景
    final scoreContainerRect = Rect.fromCenter(
      center: Offset(width / 2, currentY + 90),
      width: 400,
      height: 240,
    );
    final scoreContainerPaint = Paint()
      ..color = primaryContainer.withValues(alpha: 0.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(scoreContainerRect, const Radius.circular(32)),
      scoreContainerPaint,
    );

    final averageLabel =
        averageScore != null ? averageScore.toStringAsFixed(1) : '--';
    _paintText(
      canvas,
      text: averageLabel,
      maxWidth: width - horizontalPadding * 2,
      offset: Offset(width / 2, currentY),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: 180,
        fontWeight: FontWeight.w700,
        color: primary,
        letterSpacing: -2.0,
      ),
      align: TextAlign.center,
      center: true,
    );
    currentY += 200;

    final ratedSummary = ratedTrackCount == 0
        ? '还没有歌曲被评分'
        : '已评分 $ratedTrackCount/$totalTrackCount 首曲目';
    _paintText(
      canvas,
      text: ratedSummary,
      maxWidth: width - horizontalPadding * 2,
      offset: Offset(width / 2, currentY),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant.withValues(alpha: 0.75),
        letterSpacing: 0.25,
      ),
      align: TextAlign.center,
      center: true,
    );

    currentY += 100;

    final topTracks = _buildTopTracks(
      tracks: tracks,
      trackRatings: trackRatings,
      trackRatingTimestamps: trackRatingTimestamps,
    );

    final listWidth = width - horizontalPadding * 2;
    final listStartX = horizontalPadding;
    double rowY = currentY;

    // 添加列表区域背景容器
    final listContainerPadding = 48.0;
    final listBgRect = Rect.fromLTWH(
      listStartX - listContainerPadding,
      rowY - 32,
      listWidth + listContainerPadding * 2,
      0, // 高度将在后面动态计算
    );

    _paintText(
      canvas,
      text: '曲目评分列表',
      maxWidth: listWidth,
      offset: Offset(listStartX, rowY),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: 42,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: 0.25,
      ),
    );
    rowY += 56;

    // 使用 Primary 颜色作为分隔线
    canvas.drawLine(
      Offset(listStartX, rowY),
      Offset(listStartX + listWidth, rowY),
      Paint()
        ..color = primary.withValues(alpha: 0.3)
        ..strokeWidth = 3,
    );
    rowY += 44;

    if (topTracks.isNotEmpty) {
      for (int i = 0; i < topTracks.length; i++) {
        final entry = topTracks[i];
        final numberLabel = entry.position.toString().padLeft(2, '0');
        final titleMaxWidth = listWidth * 0.58;

        // 为列表项添加交替背景色
        if (i % 2 == 0) {
          final itemBgRect = Rect.fromLTWH(
            listStartX - 24,
            rowY - 12,
            listWidth + 48,
            76,
          );
          final itemBgPaint = Paint()
            ..color = surfaceContainerHighest.withValues(alpha: 0.25);
          canvas.drawRRect(
            RRect.fromRectAndRadius(itemBgRect, const Radius.circular(16)),
            itemBgPaint,
          );
        }

        _paintText(
          canvas,
          text: '$numberLabel  ${entry.title}',
          maxWidth: titleMaxWidth,
          offset: Offset(listStartX, rowY),
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 38,
            fontWeight: FontWeight.w500,
            color: onSurface,
            letterSpacing: 0.15,
          ),
        );

        final ratingLabel = entry.rating != null
            ? '${_ratingEmoji(entry.rating!)} ${entry.rating} · ${_formatDate(entry.recordedAt)}'
            : '未评分';

        // 根据评分显示不同的颜色
        Color ratingColor;
        if (entry.rating == null) {
          ratingColor = onSurfaceVariant.withValues(alpha: 0.6);
        } else if (entry.rating == 5) {
          ratingColor = primary; // 使用 primary 颜色突出高分
        } else if (entry.rating == 3) {
          ratingColor = onSurfaceVariant.withValues(alpha: 0.9);
        } else {
          ratingColor = onSurfaceVariant.withValues(alpha: 0.7);
        }

        _paintText(
          canvas,
          text: ratingLabel,
          maxWidth: listWidth - titleMaxWidth - 32,
          offset: Offset(listStartX + titleMaxWidth + 24,
              rowY + (entry.rating != null ? 2 : 0)),
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 32,
            fontWeight: entry.rating == 5 ? FontWeight.w500 : FontWeight.w400,
            color: ratingColor,
            letterSpacing: 0.25,
          ),
        );

        rowY += 80;
      }
    } else {
      _paintText(
        canvas,
        text: '给几首歌打分，生成专属专辑评分榜单',
        maxWidth: listWidth,
        offset: Offset(listStartX, rowY),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: onSurfaceVariant.withValues(alpha: 0.7),
          letterSpacing: 0.25,
        ),
      );
      rowY += 76;
    }

    // 添加底部装饰线
    final decorLineY = height - 200;
    canvas.drawLine(
      Offset(width / 2 - 100, decorLineY),
      Offset(width / 2 + 100, decorLineY),
      Paint()
        ..color = primary.withValues(alpha: 0.25)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    final watermarkText = 'Spotoolfy · Album Ratings';
    _paintText(
      canvas,
      text: watermarkText,
      maxWidth: width - horizontalPadding * 2,
      offset: Offset(width / 2, height - 160),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w400,
        color: primary.withValues(alpha: 0.5),
        letterSpacing: 0.5,
      ),
      align: TextAlign.center,
      center: true,
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to encode album rating poster.');
    }

    return byteData.buffer.asUint8List();
  }

  Future<ui.Image?> _loadNetworkImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        _logger.w('Failed to load album cover: HTTP ${response.statusCode}');
        return null;
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e, s) {
      _logger.w('Failed to load album cover for poster',
          error: e, stackTrace: s);
      return null;
    }
  }

  void _paintText(
    Canvas canvas, {
    required String text,
    required double maxWidth,
    required Offset offset,
    required TextStyle style,
    TextAlign align = TextAlign.left,
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    );
    painter.layout(maxWidth: maxWidth);

    Offset paintOffset = offset;
    if (center) {
      paintOffset = Offset(
        offset.dx - painter.width / 2,
        offset.dy,
      );
    }

    painter.paint(canvas, paintOffset);
  }

  List<_PosterTrackEntry> _buildTopTracks({
    required List<Map<String, dynamic>> tracks,
    required Map<String, int?> trackRatings,
    required Map<String, int?> trackRatingTimestamps,
  }) {
    final entries = <_PosterTrackEntry>[];
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final trackId = track['id'] as String?;
      if (trackId == null) {
        continue;
      }
      final rating = trackRatings[trackId];
      final recordedAt = trackRatingTimestamps[trackId];
      final title = track['name'] as String? ?? '未知曲目';
      entries.add(
        _PosterTrackEntry(
          position: i + 1,
          title: title,
          rating: rating,
          recordedAt: recordedAt,
        ),
      );
    }

    entries.sort((a, b) {
      final weightCompare = _ratingWeight(b.rating) - _ratingWeight(a.rating);
      if (weightCompare != 0) {
        return weightCompare;
      }
      final timeCompare = (b.recordedAt ?? 0).compareTo(a.recordedAt ?? 0);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return a.position.compareTo(b.position);
    });

    return entries.take(6).toList();
  }

  int _ratingWeight(int? rating) {
    if (rating == null) {
      return 0;
    }
    switch (rating) {
      case 5:
        return 3;
      case 3:
        return 2;
      case 0:
      default:
        return 1;
    }
  }

  String _ratingEmoji(int rating) {
    switch (rating) {
      case 5:
        return '🔥';
      case 3:
        return '🙂';
      case 0:
      default:
        return '👎';
    }
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null || timestamp <= 0) {
      return '--';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${dt.year}.${dt.month}.${dt.day}';
  }
}

class _PosterTrackEntry {
  final int position;
  final String title;
  final int? rating;
  final int? recordedAt;

  const _PosterTrackEntry({
    required this.position,
    required this.title,
    required this.rating,
    required this.recordedAt,
  });
}
