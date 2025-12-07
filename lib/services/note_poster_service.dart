import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

final logger = Logger();

class NotePosterService {
  // Generate note poster image data
  Future<Uint8List> generatePosterData({
    required String noteContent,
    String? lyricsSnapshot,
    required String trackTitle,
    required String artistName,
    required String albumName,
    required int rating, // 0, 3, or 5
    String? albumCoverUrl,
    required Color backgroundColor,
    required Color titleColor,
    required Color artistColor,
    required Color noteColor,
    required Color lyricsColor,
    required Color watermarkColor,
    String? fontFamily,
  }) async {
    const double scaleFactor = 2.0;
    const double baseWidth = 720;
    const double width = baseWidth * scaleFactor;
    const double horizontalMargin = 32.0 * scaleFactor;
    const double contentWidth = width - 2 * horizontalMargin;

    // Font sizes
    const double titleFontSize = 28.0 * scaleFactor;
    const double artistFontSize = 20.0 * scaleFactor;
    const double albumFontSize = 16.0 * scaleFactor;
    const double noteFontSize = 36.0 * scaleFactor;
    const double lyricsFontSize = 24.0 * scaleFactor;
    const double watermarkFontSize = 20.0 * scaleFactor;
    const double emojiFontSize = 48.0 * scaleFactor;

    const double topMargin = 40.0 * scaleFactor;
    const double bottomMargin = 40.0 * scaleFactor;
    const double elementSpacing = 24.0 * scaleFactor;
    const double interTextSpacing = 8.0 * scaleFactor;
    const double albumArtSize = 100.0 * scaleFactor;
    const double albumCornerRadius = 8.0 * scaleFactor;
    const double headerSpacing = 20.0 * scaleFactor;

    double calculatedHeight = topMargin;

    ui.Image? loadedAlbumImage;
    double headerHeight = 0;

    // Load album cover
    if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
      try {
        loadedAlbumImage = await _loadNetworkImage(albumCoverUrl);
      } catch (e) {
        logger.w('Failed to load album cover: $e');
      }
    }

    // Calculate header height
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
    final albumStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: albumFontSize,
      color: artistColor.withValues(alpha: 0.7),
      fontWeight: FontWeight.w400,
    );

    final titlePainter = TextPainter(
      text: TextSpan(text: trackTitle, style: titleStyle),
      textDirection: TextDirection.ltr,
    );
    final artistPainter = TextPainter(
      text: TextSpan(text: artistName, style: artistStyle),
      textDirection: TextDirection.ltr,
    );
    final albumPainter = TextPainter(
      text: TextSpan(text: albumName, style: albumStyle),
      textDirection: TextDirection.ltr,
    );

    if (loadedAlbumImage != null) {
      final maxTextWidth = contentWidth - albumArtSize - headerSpacing;
      titlePainter.layout(maxWidth: maxTextWidth);
      artistPainter.layout(maxWidth: maxTextWidth);
      albumPainter.layout(maxWidth: maxTextWidth);
      final textTotalHeight = titlePainter.height +
          interTextSpacing +
          artistPainter.height +
          interTextSpacing / 2 +
          albumPainter.height;
      headerHeight = albumArtSize > textTotalHeight ? albumArtSize : textTotalHeight;
    } else {
      titlePainter.layout(maxWidth: contentWidth);
      artistPainter.layout(maxWidth: contentWidth);
      albumPainter.layout(maxWidth: contentWidth);
      headerHeight = titlePainter.height +
          interTextSpacing +
          artistPainter.height +
          interTextSpacing / 2 +
          albumPainter.height;
    }
    calculatedHeight += headerHeight + elementSpacing;

    // Rating emoji
    final ratingEmoji = _getRatingEmoji(rating);
    final emojiStyle = TextStyle(
      fontSize: emojiFontSize,
    );
    final emojiPainter = TextPainter(
      text: TextSpan(text: ratingEmoji, style: emojiStyle),
      textDirection: TextDirection.ltr,
    );
    emojiPainter.layout();
    calculatedHeight += emojiPainter.height + elementSpacing;

    // Note content
    final noteStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: noteFontSize,
      color: noteColor,
      height: 1.4,
      fontWeight: FontWeight.w600,
    );
    final notePainter = TextPainter(
      text: TextSpan(text: noteContent.isNotEmpty ? noteContent : ' ', style: noteStyle),
      textDirection: TextDirection.ltr,
    );
    notePainter.layout(maxWidth: contentWidth);
    calculatedHeight += notePainter.height + elementSpacing;

    // Lyrics snapshot (if available)
    TextPainter? lyricsPainter;
    if (lyricsSnapshot != null && lyricsSnapshot.isNotEmpty) {
      final lyricsStyle = TextStyle(
        fontFamily: fontFamily,
        fontSize: lyricsFontSize,
        color: lyricsColor,
        height: 1.3,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
      );
      lyricsPainter = TextPainter(
        text: TextSpan(text: lyricsSnapshot, style: lyricsStyle),
        textDirection: TextDirection.ltr,
      );
      lyricsPainter.layout(maxWidth: contentWidth);
      calculatedHeight += lyricsPainter.height + elementSpacing;
    }

    // Watermark
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
      watermarkIcon = await _loadAssetImage('assets/icons/adaptive_icon_monochrome.png');
    } catch (e) {
      logger.w('Failed to load watermark icon: $e');
    }

    final double iconSize = watermarkPainter.height;
    const double iconTextSpacing = 8.0 * scaleFactor;
    double watermarkHeight = watermarkPainter.height;
    if (watermarkIcon != null) {
      watermarkHeight = watermarkHeight > iconSize ? watermarkHeight : iconSize;
    }
    calculatedHeight += watermarkHeight + bottomMargin;

    final double finalPosterHeight = calculatedHeight < 400 ? 400 : calculatedHeight;

    // Start drawing
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, finalPosterHeight));

    // Background
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, finalPosterHeight), backgroundPaint);

    double currentY = topMargin;

    // Draw header (album art + title/artist/album)
    if (loadedAlbumImage != null) {
      final maxTextWidth = contentWidth - albumArtSize - headerSpacing;
      titlePainter.layout(maxWidth: maxTextWidth);
      artistPainter.layout(maxWidth: maxTextWidth);
      albumPainter.layout(maxWidth: maxTextWidth);

      // Draw album cover
      final albumX = horizontalMargin;
      final albumRect = Rect.fromLTWH(albumX, currentY, albumArtSize, albumArtSize);
      final albumRRect = RRect.fromRectAndRadius(albumRect, Radius.circular(albumCornerRadius));

      canvas.save();
      canvas.clipRRect(albumRRect);
      canvas.drawImageRect(
        loadedAlbumImage,
        Rect.fromLTWH(0, 0, loadedAlbumImage.width.toDouble(), loadedAlbumImage.height.toDouble()),
        albumRect,
        Paint(),
      );
      canvas.restore();

      // Draw text
      final textStartX = albumX + albumArtSize + headerSpacing;
      final textTotalHeight = titlePainter.height +
          interTextSpacing +
          artistPainter.height +
          interTextSpacing / 2 +
          albumPainter.height;
      final textStartY = currentY + (albumArtSize - textTotalHeight) / 2;

      titlePainter.paint(canvas, Offset(textStartX, textStartY));
      artistPainter.paint(canvas, Offset(textStartX, textStartY + titlePainter.height + interTextSpacing));
      albumPainter.paint(canvas, Offset(textStartX, textStartY + titlePainter.height + interTextSpacing + artistPainter.height + interTextSpacing / 2));

      currentY += headerHeight + elementSpacing;
    } else {
      titlePainter.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += titlePainter.height + interTextSpacing;
      artistPainter.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += artistPainter.height + interTextSpacing / 2;
      albumPainter.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += albumPainter.height + elementSpacing;
    }

    // Draw rating emoji
    emojiPainter.paint(canvas, Offset(horizontalMargin, currentY));
    currentY += emojiPainter.height + elementSpacing;

    // Draw note content
    notePainter.paint(canvas, Offset(horizontalMargin, currentY));
    currentY += notePainter.height + elementSpacing;

    // Draw lyrics snapshot
    if (lyricsPainter != null) {
      lyricsPainter.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += lyricsPainter.height + elementSpacing;
    }

    // Draw watermark
    if (watermarkIcon != null) {
      final iconY = currentY + (watermarkHeight - iconSize) / 2;
      canvas.drawImageRect(
        watermarkIcon,
        Rect.fromLTWH(0, 0, watermarkIcon.width.toDouble(), watermarkIcon.height.toDouble()),
        Rect.fromLTWH(horizontalMargin, iconY, iconSize, iconSize),
        Paint()..colorFilter = ColorFilter.mode(watermarkColor, BlendMode.srcIn),
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

  String _getRatingEmoji(int rating) {
    switch (rating) {
      case 0:
        return '👎';
      case 5:
        return '🔥';
      case 3:
      default:
        return '😐';
    }
  }

  Future<String?> savePosterFromBytes(Uint8List imageBytes, String trackTitle) async {
    try {
      final result = await ImageGallerySaverPlus.saveImage(
        imageBytes,
        quality: 90,
        name: "note_poster_${trackTitle.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}",
      );
      if (result != null && result['isSuccess'] == true) {
        logger.d('Note poster saved to gallery: ${result["filePath"]}');
        return result["filePath"];
      } else {
        throw Exception('Failed to save note poster');
      }
    } catch (e) {
      logger.e('Error saving note poster: $e');
      rethrow;
    }
  }

  Future<void> sharePosterFile(String imagePath, String textToShare) async {
    try {
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: textToShare,
      );
      logger.d('Note poster shared successfully');
    } catch (e) {
      logger.e('Error sharing note poster: $e');
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
}
