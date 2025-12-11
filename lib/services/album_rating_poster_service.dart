import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

final _logger = Logger();

class AlbumRatingPosterService {
  AlbumRatingPosterService();

  Future<void> shareAlbumPoster({
    required String albumName,
    required String artistLine,
    required double? averageScore,
    required int ratedTrackCount,
    required int totalTrackCount,
    required List<Map<String, dynamic>> tracks,
    required Map<String, int?> trackRatings,
    required Map<String, int?> trackRatingTimestamps,
    required Color backgroundColor,
    required Color titleColor,
    required Color artistColor,
    required Color scoreColor,
    required Color trackColor,
    required Color ratingColor,
    required Color watermarkColor,
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
      backgroundColor: backgroundColor,
      titleColor: titleColor,
      artistColor: artistColor,
      scoreColor: scoreColor,
      trackColor: trackColor,
      ratingColor: ratingColor,
      watermarkColor: watermarkColor,
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
    required Color backgroundColor,
    required Color titleColor,
    required Color artistColor,
    required Color scoreColor,
    required Color trackColor,
    required Color ratingColor,
    required Color watermarkColor,
    String? albumCoverUrl,
    String? fontFamily,
    String? insightsTitle,
  }) async {
    // 使用与 lyrics/note poster 相同的缩放因子
    const double scaleFactor = 2.0;
    const double baseWidth = 720;
    const double width = baseWidth * scaleFactor;
    const double horizontalMargin = 32.0 * scaleFactor;
    const double contentWidth = width - 2 * horizontalMargin;

    // 字号调整
    const double titleFontSize = 28.0 * scaleFactor;
    const double artistFontSize = 20.0 * scaleFactor;
    const double scoreFontSize = 96.0 * scaleFactor;
    const double insightsFontSize = 20.0 * scaleFactor;
    const double trackFontSize = 24.0 * scaleFactor;
    const double ratingFontSize = 18.0 * scaleFactor;
    const double watermarkFontSize = 20.0 * scaleFactor;

    const double topMargin = 40.0 * scaleFactor;
    const double bottomMargin = 40.0 * scaleFactor;
    const double elementSpacing = 24.0 * scaleFactor;
    const double interTextSpacing = 8.0 * scaleFactor;
    const double albumArtSize = 100.0 * scaleFactor;
    const double albumCornerRadius = 8.0 * scaleFactor;
    const double headerSpacing = 20.0 * scaleFactor;
    const double trackRowHeight = 56.0 * scaleFactor;

    double calculatedHeight = topMargin;

    ui.Image? loadedAlbumImage;
    double headerHeight = 0;

    // 加载封面图片
    if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
      try {
        loadedAlbumImage = await _loadNetworkImage(albumCoverUrl);
      } catch (e) {
        _logger.w('Failed to load album cover: $e');
      }
    }

    // 计算 header 高度
    final titleStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: titleFontSize,
      color: titleColor,
      fontWeight: FontWeight.w600,
    );
    final artistStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: artistFontSize,
      color: artistColor,
      fontWeight: FontWeight.w400,
    );

    final titlePainter = TextPainter(
      text: TextSpan(text: albumName, style: titleStyle),
      textDirection: TextDirection.ltr,
    );
    final artistPainter = TextPainter(
      text: TextSpan(text: artistLine, style: artistStyle),
      textDirection: TextDirection.ltr,
    );

    if (loadedAlbumImage != null) {
      final maxTextWidth = contentWidth - albumArtSize - headerSpacing;
      titlePainter.layout(maxWidth: maxTextWidth);
      artistPainter.layout(maxWidth: maxTextWidth);
      final textTotalHeight =
          titlePainter.height + interTextSpacing + artistPainter.height;
      headerHeight =
          albumArtSize > textTotalHeight ? albumArtSize : textTotalHeight;
    } else {
      titlePainter.layout(maxWidth: contentWidth);
      artistPainter.layout(maxWidth: contentWidth);
      headerHeight =
          titlePainter.height + interTextSpacing + artistPainter.height;
    }
    calculatedHeight += headerHeight + elementSpacing;

    // 评分显示
    final scoreStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: scoreFontSize,
      color: scoreColor,
      fontWeight: FontWeight.w700,
      letterSpacing: -2.0,
    );
    final averageLabel =
        averageScore != null ? averageScore.toStringAsFixed(1) : '--';
    final scorePainter = TextPainter(
      text: TextSpan(text: averageLabel, style: scoreStyle),
      textDirection: TextDirection.ltr,
    );
    scorePainter.layout();
    calculatedHeight += scorePainter.height + elementSpacing;

    // Insights 标题
    TextPainter? insightsPainter;
    if (insightsTitle != null && insightsTitle.trim().isNotEmpty) {
      final insightsStyle = TextStyle(
        fontFamily: fontFamily,
        fontSize: insightsFontSize,
        color: artistColor,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
      );
      insightsPainter = TextPainter(
        text: TextSpan(text: insightsTitle.trim(), style: insightsStyle),
        textDirection: TextDirection.ltr,
      );
      insightsPainter.layout(maxWidth: contentWidth);
      calculatedHeight += insightsPainter.height + elementSpacing;
    }

    // 曲目列表
    final topTracks = _buildTopTracks(
      tracks: tracks,
      trackRatings: trackRatings,
      trackRatingTimestamps: trackRatingTimestamps,
    );

    if (topTracks.isNotEmpty) {
      calculatedHeight += topTracks.length * trackRowHeight;
      calculatedHeight += elementSpacing;
    }

    // 水印
    final watermarkStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: watermarkFontSize,
      color: watermarkColor,
      fontWeight: FontWeight.w400,
    );
    final watermarkPainter = TextPainter(
      text: TextSpan(text: 'Spotoolfy', style: watermarkStyle),
      textDirection: TextDirection.ltr,
    );
    watermarkPainter.layout(maxWidth: contentWidth);

    ui.Image? watermarkIcon;
    try {
      watermarkIcon =
          await _loadAssetImage('assets/icons/adaptive_icon_monochrome.png');
    } catch (e) {
      _logger.w('Failed to load watermark icon: $e');
    }

    final double iconSize = watermarkPainter.height;
    const double iconTextSpacing = 8.0 * scaleFactor;
    double watermarkHeight = watermarkPainter.height;
    if (watermarkIcon != null) {
      watermarkHeight = watermarkHeight > iconSize ? watermarkHeight : iconSize;
    }
    calculatedHeight += watermarkHeight + bottomMargin;

    final double finalPosterHeight =
        calculatedHeight < 400 ? 400 : calculatedHeight;

    // 开始绘制
    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, width, finalPosterHeight));

    // 背景
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width, finalPosterHeight), backgroundPaint);

    double currentY = topMargin;

    // 绘制 header（封面 + 标题/艺术家）
    if (loadedAlbumImage != null) {
      final maxTextWidth = contentWidth - albumArtSize - headerSpacing;
      titlePainter.layout(maxWidth: maxTextWidth);
      artistPainter.layout(maxWidth: maxTextWidth);

      // 绘制圆角封面
      final albumX = horizontalMargin;
      final albumRect =
          Rect.fromLTWH(albumX, currentY, albumArtSize, albumArtSize);
      final albumRRect = RRect.fromRectAndRadius(
          albumRect, Radius.circular(albumCornerRadius));

      canvas.save();
      canvas.clipRRect(albumRRect);
      canvas.drawImageRect(
        loadedAlbumImage,
        Rect.fromLTWH(0, 0, loadedAlbumImage.width.toDouble(),
            loadedAlbumImage.height.toDouble()),
        albumRect,
        Paint(),
      );
      canvas.restore();

      // 绘制文字
      final textStartX = albumX + albumArtSize + headerSpacing;
      final textTotalHeight =
          titlePainter.height + interTextSpacing + artistPainter.height;
      final textStartY = currentY + (albumArtSize - textTotalHeight) / 2;

      titlePainter.paint(canvas, Offset(textStartX, textStartY));
      artistPainter.paint(canvas,
          Offset(textStartX, textStartY + titlePainter.height + interTextSpacing));

      currentY += headerHeight + elementSpacing;
    } else {
      titlePainter.layout(maxWidth: contentWidth);
      artistPainter.layout(maxWidth: contentWidth);

      titlePainter.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += titlePainter.height + interTextSpacing;
      artistPainter.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += artistPainter.height + elementSpacing;
    }

    // 绘制评分（左对齐）
    scorePainter.paint(canvas, Offset(horizontalMargin, currentY));
    currentY += scorePainter.height + elementSpacing;

    // 绘制 insights 标题
    if (insightsPainter != null) {
      insightsPainter.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += insightsPainter.height + elementSpacing;
    }

    // 绘制曲目列表
    if (topTracks.isNotEmpty) {
      final trackStyle = TextStyle(
        fontFamily: fontFamily,
        fontSize: trackFontSize,
        color: trackColor,
        fontWeight: FontWeight.w500,
      );

      for (int i = 0; i < topTracks.length; i++) {
        final entry = topTracks[i];
        final numberLabel = entry.position.toString().padLeft(2, '0');

        // 绘制曲目号和标题
        final trackTextPainter = TextPainter(
          text: TextSpan(text: '$numberLabel  ${entry.title}', style: trackStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '...',
        );
        trackTextPainter.layout(maxWidth: contentWidth * 0.65);
        trackTextPainter.paint(canvas, Offset(horizontalMargin, currentY));

        // 绘制评分信息
        if (entry.rating != null) {
          String iconText;
          Color iconColor;

          switch (entry.rating!) {
            case 5:
              iconText = String.fromCharCode(0xf654); // whatshot_rounded
              iconColor = scoreColor;
              break;
            case 3:
              iconText = String.fromCharCode(0xf52e); // sentiment_neutral_rounded
              iconColor = ratingColor;
              break;
            case 0:
            default:
              iconText = String.fromCharCode(0xf589); // thumb_down_rounded
              iconColor = ratingColor.withValues(alpha: 0.6);
              break;
          }

          final ratingLabel = _formatDate(entry.recordedAt);
          final ratingPainter = TextPainter(
            text: TextSpan(
              children: [
                TextSpan(
                  text: iconText,
                  style: TextStyle(
                    fontFamily: 'MaterialIcons',
                    fontSize: ratingFontSize,
                    color: iconColor,
                  ),
                ),
                TextSpan(
                  text: '  $ratingLabel',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: ratingFontSize,
                    fontWeight: FontWeight.w400,
                    color: ratingColor,
                  ),
                ),
              ],
            ),
            textDirection: TextDirection.ltr,
          );
          ratingPainter.layout();

          final ratingX = width - horizontalMargin - ratingPainter.width;
          final ratingY = currentY + (trackTextPainter.height - ratingPainter.height) / 2;
          ratingPainter.paint(canvas, Offset(ratingX, ratingY));
        }

        currentY += trackRowHeight;
      }
      currentY += elementSpacing - trackRowHeight + trackFontSize;
    }

    // 绘制水印
    if (watermarkIcon != null) {
      final iconY =
          currentY + (watermarkHeight - iconSize) / 2;
      canvas.drawImageRect(
        watermarkIcon,
        Rect.fromLTWH(0, 0, watermarkIcon.width.toDouble(),
            watermarkIcon.height.toDouble()),
        Rect.fromLTWH(horizontalMargin, iconY, iconSize, iconSize),
        Paint()
          ..colorFilter = ColorFilter.mode(watermarkColor, BlendMode.srcIn),
      );

      final textX = horizontalMargin + iconSize + iconTextSpacing;
      final textY = currentY + (watermarkHeight - watermarkPainter.height) / 2;
      watermarkPainter.paint(canvas, Offset(textX, textY));
    } else {
      watermarkPainter.paint(canvas, Offset(horizontalMargin, currentY));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), finalPosterHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  Future<String?> savePosterFromBytes(Uint8List imageBytes, String albumName) async {
    try {
      final result = await ImageGallerySaverPlus.saveImage(
        imageBytes,
        quality: 90,
        name: "album_poster_${albumName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}",
      );
      if (result != null && result['isSuccess'] == true) {
        _logger.d('Album poster saved to gallery: ${result["filePath"]}');
        return result["filePath"];
      } else {
        throw Exception('Failed to save album poster');
      }
    } catch (e) {
      _logger.e('Error saving album poster: $e');
      rethrow;
    }
  }

  Future<void> sharePosterFile(String imagePath, String textToShare) async {
    try {
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: textToShare,
      );
      _logger.d('Album poster shared successfully');
    } catch (e) {
      _logger.e('Error sharing album poster: $e');
      rethrow;
    }
  }

  Future<ui.Image> _loadNetworkImage(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } else {
      throw Exception('Failed to load image from $url');
    }
  }

  Future<ui.Image> _loadAssetImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
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
