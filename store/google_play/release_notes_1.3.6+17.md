# Spotoolfy 1.3.6 (Build 17)

## 更新说明

- 优化歌词页与歌词选择页的刷新范围，减少播放过程中不必要的重绘，滚动与切页更流畅。
- 优化播放页与 Spotify 播放状态轮询逻辑，降低等待时间，状态同步更快。
- 优化最近播放、播放列表和收藏专辑的并发加载，大型资料库加载明显提速。
- 改进 QQ 歌词搜索响应兼容性，并修复相关测试编码问题。

## 本次版本包含的主要变更

- `NowPlaying` 减少页面滑动时的无效重建。
- `LyricsWidget` 仅在当前歌词行变化时重建。
- `LyricsSelectionPage` 只监听实际需要的播放进度字段。
- `SpotifyPlaybackManager` 并发刷新曲目、设备和队列。
- `SpotifyProvider` 并发拉取最近播放详情与 Spotify 分页数据。
