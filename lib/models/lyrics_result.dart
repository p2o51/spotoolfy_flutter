/// 歌词获取结果
///
/// 封装歌词文本、来源信息和翻译可用性
class LyricsResult {
  /// 歌词文本（LRC 格式或纯文本）
  final String lyric;

  /// 歌词提供者名称：'netease', 'qq', 'lrclib'
  final String provider;

  /// 是否有网易云翻译可用
  final bool hasNeteaseTranslation;

  const LyricsResult({
    required this.lyric,
    required this.provider,
    this.hasNeteaseTranslation = false,
  });

  /// 歌词是否来自网易云
  bool get isFromNetease => provider == 'netease';

  /// 歌词是否来自 QQ 音乐
  bool get isFromQQ => provider == 'qq';

  /// 歌词是否来自 LRCLIB
  bool get isFromLrclib => provider == 'lrclib';

  @override
  String toString() =>
      'LyricsResult(provider: $provider, hasNeteaseTranslation: $hasNeteaseTranslation, lyric: ${lyric.length} chars)';
}
