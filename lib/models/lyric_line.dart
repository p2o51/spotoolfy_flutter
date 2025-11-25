/// 歌词行模型
///
/// 表示一行歌词及其时间戳和可选的翻译
class LyricLine {
  /// 歌词时间戳
  final Duration timestamp;

  /// 原始歌词文本
  final String text;

  /// 翻译后的歌词文本（可选）
  String? translation;

  LyricLine(this.timestamp, this.text, {this.translation});

  /// 从 Map 创建 LyricLine
  factory LyricLine.fromMap(Map<String, dynamic> map) {
    return LyricLine(
      map['timestamp'] as Duration,
      map['text'] as String,
      translation: map['translation'] as String?,
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'text': text,
      'translation': translation,
    };
  }

  /// 创建带有翻译的副本
  LyricLine copyWith({
    Duration? timestamp,
    String? text,
    String? translation,
  }) {
    return LyricLine(
      timestamp ?? this.timestamp,
      text ?? this.text,
      translation: translation ?? this.translation,
    );
  }

  /// 检查是否有翻译
  bool get hasTranslation =>
      translation != null && translation!.trim().isNotEmpty;

  @override
  String toString() {
    return 'LyricLine(timestamp: $timestamp, text: $text, translation: $translation)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LyricLine &&
        other.timestamp == timestamp &&
        other.text == text &&
        other.translation == translation;
  }

  @override
  int get hashCode => timestamp.hashCode ^ text.hashCode ^ translation.hashCode;
}
