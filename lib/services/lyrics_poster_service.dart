import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;

final logger = Logger();

class LyricsPosterService {
  Future<void> generateAndSharePoster({
    required String lyrics,
    required String trackTitle,
    required String artistName,
    String? albumCoverUrl,
  }) async {
    try {
      // 生成海报图片
      final posterBytes = await _generatePosterImage(
        lyrics: lyrics,
        trackTitle: trackTitle,
        artistName: artistName,
        albumCoverUrl: albumCoverUrl,
      );

      // 保存到临时文件
      final tempDir = await getTemporaryDirectory();
      final fileName = 'lyrics_poster_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(posterBytes);

      // 分享文件
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '$trackTitle - $artistName\n\n$lyrics',
      );

      logger.d('Poster shared successfully');
    } catch (e) {
      logger.e('Error generating/sharing poster: $e');
      rethrow;
    }
  }

  Future<Uint8List> _generatePosterImage({
    required String lyrics,
    required String trackTitle,
    required String artistName,
    String? albumCoverUrl,
  }) async {
    // 创建一个记录器来转换widget为图片
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // 设置海报尺寸 (9:16 比例，适合社交媒体)
    const double width = 720;
    const double height = 1280;
    const Size size = Size(width, height);

    // 绘制背景渐变
    final gradient = ui.Gradient.linear(
      const Offset(0, 0),
      const Offset(width, height),
      [
        const Color(0xFF1a1a2e),
        const Color(0xFF16213e),
        const Color(0xFF0f3460),
      ],
      [0.0, 0.5, 1.0],
    );
    
    final paint = Paint()..shader = gradient;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), paint);

    // 获取专辑封面（如果有的话）
    ui.Image? albumImage;
    if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
      try {
        albumImage = await _loadNetworkImage(albumCoverUrl);
      } catch (e) {
        logger.w('Failed to load album cover: $e');
      }
    }

    // 绘制专辑封面（如果有）
    if (albumImage != null) {
      const double albumSize = 200;
      const double albumX = (width - albumSize) / 2;
      const double albumY = 80;
      
      // 添加阴影效果
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(albumX + 5, albumY + 5, albumSize, albumSize),
          const Radius.circular(12),
        ),
        shadowPaint,
      );
      
      // 绘制专辑封面
      canvas.drawImageRect(
        albumImage,
        Rect.fromLTWH(0, 0, albumImage.width.toDouble(), albumImage.height.toDouble()),
        Rect.fromLTWH(albumX, albumY, albumSize, albumSize),
        Paint(),
      );
    }

    // 绘制歌曲信息
    final titleY = albumImage != null ? 320.0 : 120.0;
    
    // 歌曲标题
    _drawText(
      canvas,
      trackTitle,
      Offset(width / 2, titleY),
      const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      width - 80,
      TextAlign.center,
    );

    // 艺术家名称
    _drawText(
      canvas,
      artistName,
      Offset(width / 2, titleY + 50),
      const TextStyle(
        fontSize: 20,
        color: Colors.white70,
      ),
      width - 80,
      TextAlign.center,
    );

    // 分割线
    final linePaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;
    
    final lineY = titleY + 100;
    canvas.drawLine(
      Offset(60, lineY),
      Offset(width - 60, lineY),
      linePaint,
    );

    // 绘制歌词
    final lyricsY = lineY + 40;
    final maxLyricsHeight = height - lyricsY - 100;
    
    _drawLyrics(
      canvas,
      lyrics,
      Offset(60, lyricsY),
      width - 120,
      maxLyricsHeight,
    );

    // 绘制底部装饰
    _drawText(
      canvas,
      'Spotoolfy',
      Offset(width / 2, height - 40),
      const TextStyle(
        fontSize: 14,
        color: Colors.white38,
        fontStyle: FontStyle.italic,
      ),
      width - 80,
      TextAlign.center,
    );

    // 完成绘制
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
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

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
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
    
    final offset = Offset(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2,
    );
    
    textPainter.paint(canvas, offset);
  }

  void _drawLyrics(
    Canvas canvas,
    String lyrics,
    Offset startPosition,
    double maxWidth,
    double maxHeight,
  ) {
    const textStyle = TextStyle(
      fontSize: 18,
      color: Colors.white,
      height: 1.6,
    );

    // 将歌词按行分割
    final lines = lyrics.split('\n');
    double currentY = startPosition.dy;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        currentY += 20; // 空行间距
        continue;
      }

      final textPainter = TextPainter(
        text: TextSpan(text: line, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      
      textPainter.layout(maxWidth: maxWidth);
      
      // 检查是否超出最大高度
      if (currentY + textPainter.height > startPosition.dy + maxHeight) {
        // 如果空间不够，添加省略号
        final ellipsisTextPainter = TextPainter(
          text: const TextSpan(text: '...', style: textStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        ellipsisTextPainter.layout(maxWidth: maxWidth);
        ellipsisTextPainter.paint(
          canvas,
          Offset(startPosition.dx + (maxWidth - ellipsisTextPainter.width) / 2, currentY),
        );
        break;
      }
      
      textPainter.paint(canvas, Offset(startPosition.dx, currentY));
      currentY += textPainter.height + 8; // 行间距
    }
  }
} 