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
    const double horizontalMargin = 32.0 * scaleFactor; // 增加左右边距
    const double contentWidth = width - 2 * horizontalMargin;

    // 字号调整 - 按比例缩放
    const double titleFontSize = 28.0 * scaleFactor;
    const double artistFontSize = 28.0 * scaleFactor;
    const double lyricsFontSize = 40 * scaleFactor; 
    const double watermarkFontSize = 20.0 * scaleFactor; // 减小水印字号

    const double topMargin = 40.0 * scaleFactor; // 增加顶部边距
    const double bottomMargin = 40.0 * scaleFactor; 
    const double elementSpacing = 24.0 * scaleFactor; // 增加元素间距
    const double interTextSpacing = 8.0 * scaleFactor; 
    const double albumArtSize = 100.0 * scaleFactor; // 稍微减小封面尺寸
    const double albumCornerRadius = 8.0 * scaleFactor; 
    const double headerSpacing = 20.0 * scaleFactor; // 减少封面和文字之间的间距

    double calculatedHeight = 0;
    calculatedHeight += topMargin;

    ui.Image? loadedAlbumImage;
    double headerHeight = 0;
    
    if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
      try {
        loadedAlbumImage = await _loadNetworkImage(albumCoverUrl);
        // 计算标题和艺术家的高度来确定header区域高度
        final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor, fontWeight: FontWeight.w400); // Regular字重
        final titlePainter = TextPainter(
          text: TextSpan(text: trackTitle, style: titleStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
        );
        final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor, fontWeight: FontWeight.w400); // Regular字重
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
        final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor, fontWeight: FontWeight.w400);
        final titlePainter = TextPainter(
          text: TextSpan(text: trackTitle, style: titleStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left, // 改为左对齐
        );
        titlePainter.layout(maxWidth: contentWidth);
        headerHeight += titlePainter.height + interTextSpacing;

        final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor, fontWeight: FontWeight.w400);
        final artistPainter = TextPainter(
          text: TextSpan(text: artistName, style: artistStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left, // 改为左对齐
        );
        artistPainter.layout(maxWidth: contentWidth);
        headerHeight += artistPainter.height;
        calculatedHeight += headerHeight + elementSpacing;
      }
    } else {
      // 没有封面时，标题和艺术家左对齐显示
      final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor, fontWeight: FontWeight.w400);
      final titlePainter = TextPainter(
        text: TextSpan(text: trackTitle, style: titleStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left, // 改为左对齐
      );
      titlePainter.layout(maxWidth: contentWidth);
      headerHeight += titlePainter.height + interTextSpacing;

      final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor, fontWeight: FontWeight.w400);
      final artistPainter = TextPainter(
        text: TextSpan(text: artistName, style: artistStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left, // 改为左对齐
      );
      artistPainter.layout(maxWidth: contentWidth);
      headerHeight += artistPainter.height;
      calculatedHeight += headerHeight + elementSpacing;
    }

    final lyricsStyle = TextStyle(fontFamily: fontFamily, fontSize: lyricsFontSize, color: lyricsColor, height: 1.4, fontWeight: FontWeight.w600); // SemiBold字重，调整行高
    final List<String> lyricLines = lyrics.split('\n');
    final List<TextPainter> lyricLinePainters = [];
    double totalLyricsBlockHeight = 0;

    if (lyricLines.isNotEmpty && lyrics.trim().isNotEmpty) {
      for (final line in lyricLines) {
        final lyricLinePainter = TextPainter(
          text: TextSpan(text: line.isEmpty ? ' ' : line, style: lyricsStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left, // 改为左对齐
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
    if (lyricLinePainters.isNotEmpty) calculatedHeight += elementSpacing; 

    // 水印样式
    final watermarkStyle = TextStyle(fontFamily: fontFamily, fontSize: watermarkFontSize, color: watermarkColor, fontWeight: FontWeight.w400);
    final watermarkPainter = TextPainter(
      text: TextSpan(text: 'Spotoolfy', style: watermarkStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left, // 改为左对齐
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

    // 使用背景颜色直接作为背景，不进行颜色混合
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, finalPosterHeight), backgroundPaint);

    double currentY = topMargin;

    if (loadedAlbumImage != null) {
      // 左对齐布局：封面和文字都从左侧开始
      final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor, fontWeight: FontWeight.w400);
      final titlePainter = TextPainter(
        text: TextSpan(text: trackTitle, style: titleStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor, fontWeight: FontWeight.w400);
      final artistPainter = TextPainter(
        text: TextSpan(text: artistName, style: artistStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      
      // 设置文本的最大宽度，超过时自动换行
      final maxTextWidth = contentWidth - albumArtSize - headerSpacing;
      titlePainter.layout(maxWidth: maxTextWidth);
      artistPainter.layout(maxWidth: maxTextWidth);
      
      // 绘制圆角封面（左对齐）
      final albumX = horizontalMargin;
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
      // 没有封面时，标题和艺术家左对齐显示
      final titleStyle = TextStyle(fontFamily: fontFamily, fontSize: titleFontSize, color: titleColor, fontWeight: FontWeight.w400);
      final artistStyle = TextStyle(fontFamily: fontFamily, fontSize: artistFontSize, color: artistColor, fontWeight: FontWeight.w400);
      
      final titlePainter = TextPainter(
        text: TextSpan(text: trackTitle, style: titleStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      titlePainter.layout(maxWidth: contentWidth);
      
      final artistPainter = TextPainter(
        text: TextSpan(text: artistName, style: artistStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      artistPainter.layout(maxWidth: contentWidth);
      
      _drawText(canvas, trackTitle, Offset(horizontalMargin, currentY + titlePainter.height / 2), titleStyle, contentWidth, TextAlign.left);
      currentY += titlePainter.height + interTextSpacing;

      _drawText(canvas, artistName, Offset(horizontalMargin, currentY + artistPainter.height / 2), artistStyle, contentWidth, TextAlign.left);
      currentY += artistPainter.height + elementSpacing;
    }

    // 绘制歌词（左对齐）
    for (final painter in lyricLinePainters) {
      _drawTextPainter(canvas, painter, Offset(horizontalMargin, currentY + painter.height / 2), TextAlign.left);
      currentY += painter.height;
    }
    if (lyricLinePainters.isNotEmpty) {
      currentY += elementSpacing;
    }

    // 绘制水印：图标 + 文字组合，左对齐
    final watermarkY = currentY + (watermarkHeight / 2);
    
    if (watermarkIcon != null) {
      // 左对齐布局
      final watermarkStartX = horizontalMargin;
      
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
      // 如果图标加载失败，只显示文字（左对齐）
      _drawText(canvas, 'Spotoolfy', Offset(horizontalMargin, watermarkY), watermarkStyle, contentWidth, TextAlign.left);
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

  // 辅助方法：绘制文本 (支持左对齐)
  void _drawText(
    Canvas canvas,
    String text,
    Offset position, // 对于左对齐，这是文本块的左上角位置
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
      dx -= textPainter.width; 
    }
    // 对于 TextAlign.left，dx 保持不变

    final offsetY = position.dy - textPainter.height / 2; 
    
    textPainter.paint(canvas, Offset(dx, offsetY));
  }

  void _drawTextPainter(Canvas canvas, TextPainter textPainter, Offset position, TextAlign textAlign) {
    double dx = position.dx;
    if (textAlign == TextAlign.center) {
      dx -= textPainter.width / 2;
    } else if (textAlign == TextAlign.right) {
      dx -= textPainter.width;
    }
    // 对于 TextAlign.left，dx 保持不变
    
    final offsetY = position.dy - textPainter.height / 2;
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