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

    currentY = coverRect.bottom + 64;

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
    currentY += 104;

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
    currentY += 120;

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
    currentY += 260;

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
      currentY += 120;
    }

    final topTracks = _buildTopTracks(
      tracks: tracks,
      trackRatings: trackRatings,
      trackRatingTimestamps: trackRatingTimestamps,
    );

    final listWidth = width - horizontalPadding * 2;
    final listStartX = horizontalPadding;
    double rowY = currentY;

    if (topTracks.isNotEmpty) {
      for (int i = 0; i < topTracks.length; i++) {
        final entry = topTracks[i];
        final numberLabel = entry.position.toString().padLeft(2, '0');
        final titleMaxWidth = listWidth * 0.58;

        // 为列表项添加交替背景色
        if (i % 2 == 0) {
          final itemBgRect = Rect.fromLTWH(
            listStartX - 24,
            rowY - 16,
            listWidth + 48,
            100,
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

        // 绘制评分图标和信息
        final ratingStartX = listStartX + titleMaxWidth + 24;
        final ratingY = rowY + 48;

        if (entry.rating != null) {
          // 根据评分选择图标和颜色
          String iconText;
          Color iconColor;
          Color bgColor;

          switch (entry.rating!) {
            case 5:
              iconText = String.fromCharCode(0xe23a); // whatshot icon
              iconColor = primary;
              bgColor = primaryContainer.withValues(alpha: 0.4);
              break;
            case 3:
              iconText = String.fromCharCode(0xe7f3); // sentiment_neutral icon
              iconColor = onSurfaceVariant;
              bgColor = surfaceContainerHighest.withValues(alpha: 0.6);
              break;
            case 0:
            default:
              iconText = String.fromCharCode(0xe8db); // thumb_down icon
              iconColor = onSurfaceVariant.withValues(alpha: 0.7);
              bgColor = surfaceContainerHighest.withValues(alpha: 0.5);
              break;
          }

          // 绘制带背景的评分信息
          final ratingLabel = _formatDate(entry.recordedAt);
          final ratingPainter = TextPainter(
            text: TextSpan(
              children: [
                TextSpan(
                  text: iconText,
                  style: TextStyle(
                    fontFamily: 'MaterialIcons',
                    fontSize: 32,
                    color: iconColor,
                  ),
                ),
                TextSpan(
                  text: '  $ratingLabel',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 30,
                    fontWeight: FontWeight.w400,
                    color: onSurfaceVariant.withValues(alpha: 0.8),
                    letterSpacing: 0.25,
                  ),
                ),
              ],
            ),
            textDirection: TextDirection.ltr,
          );
          ratingPainter.layout(maxWidth: listWidth - titleMaxWidth - 32);

          final ratingBgRect = Rect.fromLTWH(
            ratingStartX - 12,
            ratingY - 8,
            ratingPainter.width + 24,
            ratingPainter.height + 16,
          );
          final ratingBgPaint = Paint()..color = bgColor;
          canvas.drawRRect(
            RRect.fromRectAndRadius(ratingBgRect, const Radius.circular(12)),
            ratingBgPaint,
          );

          ratingPainter.paint(canvas, Offset(ratingStartX, ratingY));
        } else {
          // 未评分显示 N/A
          final naPainter = TextPainter(
            text: TextSpan(
              text: 'N/A',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 30,
                fontWeight: FontWeight.w400,
                color: onSurfaceVariant.withValues(alpha: 0.5),
                letterSpacing: 0.25,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          naPainter.layout();

          final naBgRect = Rect.fromLTWH(
            ratingStartX - 12,
            ratingY - 8,
            naPainter.width + 24,
            naPainter.height + 16,
          );
          final naBgPaint = Paint()
            ..color = surfaceContainerHighest.withValues(alpha: 0.3);
          canvas.drawRRect(
            RRect.fromRectAndRadius(naBgRect, const Radius.circular(12)),
            naBgPaint,
          );

          naPainter.paint(canvas, Offset(ratingStartX, ratingY));
        }

        rowY += 104;
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

    // 按原始曲目顺序排序，不再按评分排序
    return entries.take(6).toList();
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
