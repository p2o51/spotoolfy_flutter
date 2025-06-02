import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart'; // Updated import

final logger = Logger();

class LyricsPosterService {

  // 1. 生成海报图片数据 (Uint8List)
  Future<Uint8List> generatePosterData({
    required String lyrics,
    required String trackTitle,
    required String artistName,
    String? albumCoverUrl,
    // 新增颜色参数
    required Color backgroundColor,
    required Color titleColor,
    required Color artistColor,
    required Color lyricsColor,
    required Color watermarkColor,
    required Color separatorColor,
    String? fontFamily, // 新增 fontFamily 参数
  }) async {
    // --- 调整参数 ---
    const double scaleFactor = 2.0; // 2倍分辨率
    const double baseWidth = 720;
    const double width = baseWidth * scaleFactor;
    const double horizontalMargin = 24.0 * scaleFactor; // 按比例缩放边距
    const double contentWidth = width - 2 * horizontalMargin;

    // 字号调整 - 按比例缩放
    const double titleFontSize = 28.0 * scaleFactor;
    const double artistFontSize = 24.0 * scaleFactor;
    const double lyricsFontSize = 32 * scaleFactor; 
    const double watermarkFontSize = 24.0 * scaleFactor;

    const double topMargin = 30.0 * scaleFactor; 
    const double bottomMargin = 30.0 * scaleFactor; // 增加底部间距，与顶部保持对称
    const double elementSpacing = 18.0 * scaleFactor; 
    const double interTextSpacing = 6.0 * scaleFactor; 
    const double albumArtSize = 120.0 * scaleFactor;
    const double albumCornerRadius = 12.0 * scaleFactor; // 新增：封面圆角半径
    const double headerSpacing = 40.0 * scaleFactor; // 增加封面和文字之间的间距

    double calculatedHeight = 0;
    calculatedHeight += topMargin;

    ui.Image? loadedAlbumImage;
    double headerHeight = 0;
    
    if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
      try {
        loadedAlbumImage = await _loadNetworkImage(albumCoverUrl);
        // 计算标题和艺术家的高度来确定header区域高度
        final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor);
        final titlePainter = TextPainter(
          text: TextSpan(text: trackTitle, style: titleStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
        );
        final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor);
        final artistPainter = TextPainter(
          text: TextSpan(text: artistName, style: artistStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
        );
        
        // 设置文本的最大宽度，超过时自动换行
        final maxTextWidth = contentWidth - albumArtSize - headerSpacing;
        titlePainter.layout(maxWidth: maxTextWidth);
        artistPainter.layout(maxWidth: maxTextWidth);
        
        // header区域高度取封面高度和文字总高度的较大值
        final textTotalHeight = titlePainter.height + interTextSpacing + artistPainter.height;
        headerHeight = albumArtSize > textTotalHeight ? albumArtSize : textTotalHeight;
        calculatedHeight += headerHeight + elementSpacing;
      } catch (e) {
        logger.w('Failed to load album cover for height calculation: $e');
        // 如果封面加载失败，仍然计算标题和艺术家高度
        final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor);
        final titlePainter = TextPainter(
          text: TextSpan(text: trackTitle, style: titleStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        titlePainter.layout(maxWidth: contentWidth);
        headerHeight += titlePainter.height + interTextSpacing;

        final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor);
        final artistPainter = TextPainter(
          text: TextSpan(text: artistName, style: artistStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        artistPainter.layout(maxWidth: contentWidth);
        headerHeight += artistPainter.height;
        calculatedHeight += headerHeight + elementSpacing;
      }
    } else {
      // 没有封面时，标题和艺术家居中显示
      final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor);
      final titlePainter = TextPainter(
        text: TextSpan(text: trackTitle, style: titleStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      titlePainter.layout(maxWidth: contentWidth);
      headerHeight += titlePainter.height + interTextSpacing;

      final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor);
      final artistPainter = TextPainter(
        text: TextSpan(text: artistName, style: artistStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      artistPainter.layout(maxWidth: contentWidth);
      headerHeight += artistPainter.height;
      calculatedHeight += headerHeight + elementSpacing;
    }

    final lyricsStyle = TextStyle(fontFamily: fontFamily, fontSize: lyricsFontSize, color: lyricsColor, height: 1.5, fontWeight: FontWeight.w600); // 调整行高，使用与歌词页面相同的字重
    final List<String> lyricLines = lyrics.split('\n');
    final List<TextPainter> lyricLinePainters = [];
    double totalLyricsBlockHeight = 0;

    if (lyricLines.isNotEmpty && lyrics.trim().isNotEmpty) {
      for (final line in lyricLines) {
        final lyricLinePainter = TextPainter(
          text: TextSpan(text: line.isEmpty ? ' ' : line, style: lyricsStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        lyricLinePainter.layout(maxWidth: contentWidth);
        lyricLinePainters.add(lyricLinePainter);
        totalLyricsBlockHeight += lyricLinePainter.height;
      }
    } else {
      final emptyLyricPainter = TextPainter(text: TextSpan(text: ' ', style: lyricsStyle), textDirection: TextDirection.ltr);
      emptyLyricPainter.layout(maxWidth: contentWidth);
      totalLyricsBlockHeight = emptyLyricPainter.height;
      if (lyrics.trim().isEmpty && lyricLines.length == 1) {
        lyricLinePainters.add(emptyLyricPainter);
      }
    }
    calculatedHeight += totalLyricsBlockHeight;
    if (lyricLinePainters.isNotEmpty) calculatedHeight += elementSpacing; // Add spacing only if there are lyrics

    // 去掉水印的斜体
    final watermarkStyle = TextStyle(fontFamily: fontFamily, fontSize: watermarkFontSize, color: watermarkColor);
    final watermarkPainter = TextPainter(
      text: TextSpan(text: 'Spotoolfy', style: watermarkStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    watermarkPainter.layout(maxWidth: contentWidth);
    
    // 加载水印图标
    ui.Image? watermarkIcon;
    try {
      watermarkIcon = await _loadAssetImage('assets/icons/adaptive_icon_monochrome.png');
    } catch (e) {
      logger.w('Failed to load watermark icon: $e');
    }
    
    // 计算水印区域高度（图标和文字的较大值）
    final double iconSize = watermarkPainter.height; // 图标大小与文字高度匹配
    const double iconTextSpacing = 8.0 * scaleFactor; // 图标和文字之间的间距
    double watermarkHeight = watermarkPainter.height;
    if (watermarkIcon != null) {
      watermarkHeight = watermarkHeight > iconSize ? watermarkHeight : iconSize;
    }
    
    calculatedHeight += watermarkHeight;

    calculatedHeight += bottomMargin;
    final double finalPosterHeight = (calculatedHeight < 400) ? 400 : calculatedHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, finalPosterHeight));

    // 让颜色变淡，例如与白色混合50%，并确保最终颜色不透明
    final Color lightenedBackgroundColor = Color.lerp(backgroundColor, Colors.white, 0.5)!;
    // 使用淡化后的不透明颜色作为背景
    final backgroundPaint = Paint()..color = lightenedBackgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, finalPosterHeight), backgroundPaint);

    double currentY = topMargin;

    if (loadedAlbumImage != null) {
      // 计算header整体的紧凑宽度和居中位置
      final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor);
      final titlePainter = TextPainter(
        text: TextSpan(text: trackTitle, style: titleStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor);
      final artistPainter = TextPainter(
        text: TextSpan(text: artistName, style: artistStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      
      // 设置文本的最大宽度，超过时自动换行
      final maxTextWidth = contentWidth - albumArtSize - headerSpacing;
      titlePainter.layout(maxWidth: maxTextWidth);
      artistPainter.layout(maxWidth: maxTextWidth);
      
      // 计算整个header的实际宽度：封面 + 间距 + 文字的最大宽度
      final actualTextWidth = titlePainter.width > artistPainter.width ? titlePainter.width : artistPainter.width;
      final actualHeaderWidth = albumArtSize + headerSpacing + actualTextWidth;
      
      // 让整个header在海报中水平居中
      final headerStartX = (width - actualHeaderWidth) / 2;
      
      // 绘制圆角封面
      final albumX = headerStartX;
      final albumRect = Rect.fromLTWH(albumX, currentY, albumArtSize, albumArtSize);
      final albumRRect = RRect.fromRectAndRadius(albumRect, const Radius.circular(albumCornerRadius));
      
      // 裁剪圆角区域
      canvas.save();
      canvas.clipRRect(albumRRect);
      canvas.drawImageRect(
        loadedAlbumImage,
        Rect.fromLTWH(0, 0, loadedAlbumImage.width.toDouble(), loadedAlbumImage.height.toDouble()),
        albumRect,
        Paint(),
      );
      canvas.restore();
      
      // 绘制标题和艺术家（左对齐，在封面右侧）
      final textStartX = albumX + albumArtSize + headerSpacing;
      
      // 计算文字垂直居中位置
      final textTotalHeight = titlePainter.height + interTextSpacing + artistPainter.height;
      final textStartY = currentY + (albumArtSize - textTotalHeight) / 2;
      
      // 绘制标题
      titlePainter.paint(canvas, Offset(textStartX, textStartY));
      
      // 绘制艺术家
      artistPainter.paint(canvas, Offset(textStartX, textStartY + titlePainter.height + interTextSpacing));
      
      currentY += headerHeight + elementSpacing;
    } else {
      // 没有封面时，标题和艺术家居中显示
      final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor);
      final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor);
      
      final titlePainter = TextPainter(
        text: TextSpan(text: trackTitle, style: titleStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      titlePainter.layout(maxWidth: contentWidth);
      
      final artistPainter = TextPainter(
        text: TextSpan(text: artistName, style: artistStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      artistPainter.layout(maxWidth: contentWidth);
      
      _drawText(canvas, trackTitle, Offset(width / 2, currentY + titlePainter.height / 2), titleStyle, contentWidth, TextAlign.center);
      currentY += titlePainter.height + interTextSpacing;

      _drawText(canvas, artistName, Offset(width / 2, currentY + artistPainter.height / 2), artistStyle, contentWidth, TextAlign.center);
      currentY += artistPainter.height + elementSpacing;
    }

    for (final painter in lyricLinePainters) {
      _drawTextPainter(canvas, painter, Offset(width / 2, currentY + painter.height / 2), TextAlign.center);
      currentY += painter.height;
    }
    if (lyricLinePainters.isNotEmpty) {
      currentY += elementSpacing;
    }

    // 绘制水印：图标 + 文字组合，跟在歌词后面
    final watermarkY = currentY + (watermarkHeight / 2);
    
    if (watermarkIcon != null) {
      // 计算图标+文字组合的总宽度
      final totalWatermarkWidth = iconSize + iconTextSpacing + watermarkPainter.width;
      final watermarkStartX = (width - totalWatermarkWidth) / 2;
      
      // 绘制图标
      final iconY = watermarkY - (watermarkHeight / 2) + (watermarkHeight - iconSize) / 2;
      canvas.drawImageRect(
        watermarkIcon,
        Rect.fromLTWH(0, 0, watermarkIcon.width.toDouble(), watermarkIcon.height.toDouble()),
        Rect.fromLTWH(watermarkStartX, iconY, iconSize, iconSize),
        Paint()..colorFilter = ColorFilter.mode(watermarkColor, BlendMode.srcIn), // 应用颜色滤镜
      );
      
      // 绘制文字
      final textX = watermarkStartX + iconSize + iconTextSpacing;
      final textY = watermarkY - (watermarkHeight / 2) + (watermarkHeight - watermarkPainter.height) / 2;
      watermarkPainter.paint(canvas, Offset(textX, textY));
    } else {
      // 如果图标加载失败，只显示文字
      _drawText(canvas, 'Spotoolfy', Offset(width / 2, watermarkY), watermarkStyle, contentWidth, TextAlign.center);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), finalPosterHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  // 2. 保存图片数据到相册
  Future<String?> savePosterFromBytes(Uint8List imageBytes, String trackTitle) async {
    try {
      // Updated to use ImageGallerySaverPlus
      final result = await ImageGallerySaverPlus.saveImage(
        imageBytes,
        quality: 90,
        name: "lyrics_poster_${trackTitle.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}",
      );
      // The result structure for image_gallery_saver_plus might be different.
      // Assuming it returns a Map with 'isSuccess' and 'filePath' or just a boolean/path.
      // For simplicity, let's check if the result indicates success.
      // The plugin docs state: "Returns true if the image was saved successfully, false otherwise."
      // And for saveFile: "Returns a Map with the keys isSuccess, filePath (String), and errorMessage (String).
      // Let's assume saveImage returns a boolean based on its typical usage, or a map if more detailed.
      // The example from image_gallery_saver_plus for saveImage shows it returns a result that implies success/failure directly.
      // It seems it returns a Map like: {isSuccess: true, filePath: /path/to/file}

      if (result != null && result['isSuccess'] == true) {
        logger.d('Poster saved to gallery: ${result["filePath"]}');
        return result["filePath"];
      } else if (result != null && result['isSuccess'] == false) {
        logger.e('Failed to save poster to gallery plus: ${result["errorMessage"] ?? "Unknown error"}');
        throw Exception('Failed to save poster to gallery plus: ${result["errorMessage"] ?? "Unknown error"}');
      } else {
        // This case might occur if result is null or not the expected map.
        logger.e('Failed to save poster to gallery plus: Unexpected result format.');
        throw Exception('Failed to save poster to gallery plus: Unexpected result format.');
      }

    } catch (e) {
      logger.e('Error saving poster to gallery: $e');
      rethrow;
    }
  }

  // 3. 分享图片文件
  Future<void> sharePosterFile(String imagePath, String textToShare) async {
    try {
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: textToShare,
      );
      logger.d('Poster shared successfully from file: $imagePath');
    } catch (e) {
      logger.e('Error sharing poster from file: $e');
      rethrow;
    }
  }

  // 辅助方法：加载网络图片
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

  // 辅助方法：加载本地资源图片
  Future<ui.Image> _loadAssetImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // 辅助方法：绘制文本 (支持居中对齐)
  void _drawText(
    Canvas canvas,
    String text,
    Offset position, // This is the CENTER of the text block
    TextStyle style,
    double maxWidth,
    TextAlign textAlign,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    );
    textPainter.layout(maxWidth: maxWidth);
    
    double dx = position.dx;
    if (textAlign == TextAlign.center) {
      dx -= textPainter.width / 2;
    } else if (textAlign == TextAlign.right) {
      // This case needs to be thought out if position.dx is not the right edge of the container
      dx -= textPainter.width; 
    }
    // For TextAlign.left, if position.dx is the center of the container, 
    // dx should be position.dx - containerWidth/2 + padding, or simply the left starting x.
    // Given our usage (centering text within a contentWidth area), this is mostly for TextAlign.center.

    final offsetY = position.dy - textPainter.height / 2; 
    
    textPainter.paint(canvas, Offset(dx, offsetY));
  }

  void _drawTextPainter(Canvas canvas, TextPainter textPainter, Offset centerPosition, TextAlign textAlign) {
    double dx = centerPosition.dx;
    // Assuming textPainter.width is available after layout
    if (textAlign == TextAlign.center) {
      dx -= textPainter.width / 2;
    } else if (textAlign == TextAlign.right) {
      dx -= textPainter.width;
    }
    
    final offsetY = centerPosition.dy - textPainter.height / 2;
    textPainter.paint(canvas, Offset(dx, offsetY));
  }

  // @Deprecated('Use generatePosterData and sharePosterFile separately')
  // Future<void> generateAndSharePoster({
  //   required String lyrics,
  //   required String trackTitle,
  //   required String artistName,
  //   String? albumCoverUrl,
  // }) async {
  //   // This method is deprecated and its call to generatePosterData
  //   // would now be broken due to new required color parameters.
  //   // It's better to remove it entirely as the app flow has changed.
  //   logger.w('generateAndSharePoster is deprecated and should not be called.');
  //   // throw UnimplementedError('generateAndSharePoster is deprecated');
  // }
} 