import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/spotify_provider.dart';
import '../models/spotify_device.dart';

/// Spotify Provider 选择器集合
///
/// 使用 Selector 替代 Consumer 可以显著减少不必要的 Widget 重建。
///
/// ## 使用指南
///
/// ### 什么时候用 Selector vs Consumer
///
/// **用 Consumer 当:**
/// - 需要访问 Provider 的多个属性
/// - Widget 确实需要在任何状态变化时重建
///
/// **用 Selector 当:**
/// - 只需要 Provider 的特定属性
/// - 只想在特定属性变化时重建
///
/// ### 示例对比
///
/// ```dart
/// // 差：每次 SpotifyProvider 变化都重建
/// Consumer<SpotifyProvider>(
///   builder: (context, provider, child) {
///     return Text(provider.currentTrack?['item']?['name'] ?? '');
///   },
/// )
///
/// // 好：只在曲目名称变化时重建
/// TrackNameSelector(
///   builder: (context, trackName, child) {
///     return Text(trackName ?? '');
///   },
/// )
/// ```

// ============================================================================
// 播放状态选择器
// ============================================================================

/// 选择当前是否正在播放
class IsPlayingSelector extends StatelessWidget {
  final Widget Function(BuildContext context, bool isPlaying, Widget? child) builder;
  final Widget? child;

  const IsPlayingSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, bool>(
      selector: (_, provider) => provider.currentTrack?['is_playing'] ?? false,
      builder: builder,
      child: child,
    );
  }
}

/// 选择当前播放进度
class PlaybackProgressSelector extends StatelessWidget {
  final Widget Function(
      BuildContext context, ({int progress, int duration}) data, Widget? child) builder;
  final Widget? child;

  const PlaybackProgressSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, ({int progress, int duration})>(
      selector: (_, provider) {
        final track = provider.currentTrack;
        return (
          progress: track?['progress_ms'] as int? ?? 0,
          duration: track?['item']?['duration_ms'] as int? ?? 1,
        );
      },
      builder: builder,
      child: child,
    );
  }
}

/// 选择播放进度百分比（0.0 - 1.0）
class PlaybackProgressPercentSelector extends StatelessWidget {
  final Widget Function(BuildContext context, double percent, Widget? child) builder;
  final Widget? child;

  const PlaybackProgressPercentSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, double>(
      selector: (_, provider) {
        final track = provider.currentTrack;
        final progress = track?['progress_ms'] as int? ?? 0;
        final duration = track?['item']?['duration_ms'] as int? ?? 1;
        return duration > 0 ? (progress / duration).clamp(0.0, 1.0) : 0.0;
      },
      builder: builder,
      child: child,
    );
  }
}

// ============================================================================
// 曲目信息选择器
// ============================================================================

/// 选择当前曲目 ID
class TrackIdSelector extends StatelessWidget {
  final Widget Function(BuildContext context, String? trackId, Widget? child) builder;
  final Widget? child;

  const TrackIdSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, String?>(
      selector: (_, provider) => provider.currentTrack?['item']?['id'] as String?,
      builder: builder,
      child: child,
    );
  }
}

/// 选择当前曲目名称
class TrackNameSelector extends StatelessWidget {
  final Widget Function(BuildContext context, String? trackName, Widget? child) builder;
  final Widget? child;

  const TrackNameSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, String?>(
      selector: (_, provider) => provider.currentTrack?['item']?['name'] as String?,
      builder: builder,
      child: child,
    );
  }
}

/// 选择当前艺术家名称
class ArtistNameSelector extends StatelessWidget {
  final Widget Function(BuildContext context, String? artistName, Widget? child) builder;
  final Widget? child;

  const ArtistNameSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, String?>(
      selector: (_, provider) {
        final artists = provider.currentTrack?['item']?['artists'] as List?;
        if (artists == null || artists.isEmpty) return null;
        return artists[0]['name'] as String?;
      },
      builder: builder,
      child: child,
    );
  }
}

/// 选择当前专辑封面 URL
class AlbumArtSelector extends StatelessWidget {
  final Widget Function(BuildContext context, String? albumArtUrl, Widget? child) builder;
  final Widget? child;

  const AlbumArtSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, String?>(
      selector: (_, provider) {
        final images = provider.currentTrack?['item']?['album']?['images'] as List?;
        if (images == null || images.isEmpty) return null;
        return images[0]['url'] as String?;
      },
      builder: builder,
      child: child,
    );
  }
}

/// 选择曲目基本信息（名称 + 艺术家）
class TrackInfoSelector extends StatelessWidget {
  final Widget Function(
      BuildContext context, ({String? name, String? artist}) info, Widget? child) builder;
  final Widget? child;

  const TrackInfoSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, ({String? name, String? artist})>(
      selector: (_, provider) {
        final item = provider.currentTrack?['item'];
        final artists = item?['artists'] as List?;
        return (
          name: item?['name'] as String?,
          artist: artists?.isNotEmpty == true ? artists![0]['name'] as String? : null,
        );
      },
      builder: builder,
      child: child,
    );
  }
}

// ============================================================================
// 设备选择器
// ============================================================================

/// 选择可用设备列表
class AvailableDevicesSelector extends StatelessWidget {
  final Widget Function(
      BuildContext context, List<SpotifyDevice> devices, Widget? child) builder;
  final Widget? child;

  const AvailableDevicesSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, List<SpotifyDevice>>(
      selector: (_, provider) => provider.availableDevices,
      builder: builder,
      child: child,
    );
  }
}

/// 选择当前活动设备
class ActiveDeviceSelector extends StatelessWidget {
  final Widget Function(
      BuildContext context, SpotifyDevice? device, Widget? child) builder;
  final Widget? child;

  const ActiveDeviceSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, SpotifyDevice?>(
      selector: (_, provider) => provider.activeDevice,
      builder: builder,
      child: child,
    );
  }
}

// ============================================================================
// 收藏状态选择器
// ============================================================================

/// 选择当前曲目是否已收藏
class TrackSavedSelector extends StatelessWidget {
  final Widget Function(BuildContext context, bool? isSaved, Widget? child) builder;
  final Widget? child;

  const TrackSavedSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, bool?>(
      selector: (_, provider) => provider.isCurrentTrackSaved,
      builder: builder,
      child: child,
    );
  }
}

// ============================================================================
// 播放模式选择器
// ============================================================================

/// 选择当前播放模式
class PlayModeSelector extends StatelessWidget {
  final Widget Function(BuildContext context, PlayMode mode, Widget? child) builder;
  final Widget? child;

  const PlayModeSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, PlayMode>(
      selector: (_, provider) => provider.currentMode,
      builder: builder,
      child: child,
    );
  }
}

// ============================================================================
// 用户状态选择器
// ============================================================================

/// 选择用户名
class UsernameSelector extends StatelessWidget {
  final Widget Function(BuildContext context, String? username, Widget? child) builder;
  final Widget? child;

  const UsernameSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, String?>(
      selector: (_, provider) => provider.username,
      builder: builder,
      child: child,
    );
  }
}

/// 选择加载状态
class IsLoadingSelector extends StatelessWidget {
  final Widget Function(BuildContext context, bool isLoading, Widget? child) builder;
  final Widget? child;

  const IsLoadingSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, bool>(
      selector: (_, provider) => provider.isLoading,
      builder: builder,
      child: child,
    );
  }
}

// ============================================================================
// 队列选择器
// ============================================================================

/// 选择下一首曲目
class NextTrackSelector extends StatelessWidget {
  final Widget Function(
      BuildContext context, Map<String, dynamic>? nextTrack, Widget? child) builder;
  final Widget? child;

  const NextTrackSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, Map<String, dynamic>?>(
      selector: (_, provider) => provider.nextTrack,
      builder: builder,
      child: child,
    );
  }
}

/// 选择播放队列长度
class QueueLengthSelector extends StatelessWidget {
  final Widget Function(BuildContext context, int length, Widget? child) builder;
  final Widget? child;

  const QueueLengthSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, int>(
      selector: (_, provider) => provider.upcomingTracks.length,
      builder: builder,
      child: child,
    );
  }
}

// ============================================================================
// 复合选择器（多属性）
// ============================================================================

/// 选择播放控制所需的状态
class PlaybackControlSelector extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    ({bool isPlaying, bool hasTrack, PlayMode mode}) state,
    Widget? child,
  ) builder;
  final Widget? child;

  const PlaybackControlSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider,
        ({bool isPlaying, bool hasTrack, PlayMode mode})>(
      selector: (_, provider) => (
        isPlaying: provider.currentTrack?['is_playing'] ?? false,
        hasTrack: provider.currentTrack != null,
        mode: provider.currentMode,
      ),
      builder: builder,
      child: child,
    );
  }
}

/// 选择 AppBar 显示所需的状态
class AppBarStateSelector extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    ({String? trackName, String? artistName, bool isPlaying, double progress}) state,
    Widget? child,
  ) builder;
  final Widget? child;

  const AppBarStateSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider,
        ({String? trackName, String? artistName, bool isPlaying, double progress})>(
      selector: (_, provider) {
        final track = provider.currentTrack;
        final item = track?['item'];
        final artists = item?['artists'] as List?;
        final progress = track?['progress_ms'] as int? ?? 0;
        final duration = item?['duration_ms'] as int? ?? 1;

        return (
          trackName: item?['name'] as String?,
          artistName: artists?.isNotEmpty == true ? artists![0]['name'] as String? : null,
          isPlaying: track?['is_playing'] ?? false,
          progress: duration > 0 ? (progress / duration).clamp(0.0, 1.0) : 0.0,
        );
      },
      builder: builder,
      child: child,
    );
  }
}

/// 选择播放上下文信息（用于 AppBar 标题）
class PlaybackContextSelector extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    ({String? contextName, String? contextType, bool isPlaying}) state,
    Widget? child,
  ) builder;
  final Widget? child;

  const PlaybackContextSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider,
        ({String? contextName, String? contextType, bool isPlaying})>(
      selector: (_, provider) {
        final track = provider.currentTrack;
        return (
          contextName: track?['context']?['name'] as String?,
          contextType: track?['context']?['type'] as String?,
          isPlaying: track?['is_playing'] ?? false,
        );
      },
      builder: builder,
      child: child,
    );
  }
}

/// 选择进度条所需的数据
class ProgressBarSelector extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    ({int progress, int duration, bool isPlaying, bool hasTrack}) state,
    Widget? child,
  ) builder;
  final Widget? child;

  const ProgressBarSelector({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider,
        ({int progress, int duration, bool isPlaying, bool hasTrack})>(
      selector: (_, provider) {
        final track = provider.currentTrack;
        return (
          progress: track?['progress_ms'] as int? ?? 0,
          duration: track?['item']?['duration_ms'] as int? ?? 1,
          isPlaying: track?['is_playing'] ?? false,
          hasTrack: track != null && track['item'] != null,
        );
      },
      builder: builder,
      child: child,
    );
  }
}
