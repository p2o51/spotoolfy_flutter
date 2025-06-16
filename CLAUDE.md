# CLAUDE.md

此文件为 Claude Code (claude.ai/code) 在此代码仓库中工作时提供指导。

## 项目概述

Spotoolfy Flutter 是一个采用 Material Design 3 设计的 Spotify API 客户端，集成了歌词显示、翻译和笔记记录功能。应用使用 Provider 进行状态管理，SQLite 进行本地存储，并集成 Gemini AI 进行歌词翻译和音乐洞察。

## 核心架构

### 状态管理
应用使用 **Provider** 模式，包含多个核心 Provider：
- `SpotifyProvider`: 核心 Spotify API 集成和播放控制
- `ThemeProvider`: 基于专辑封面的动态主题
- `LibraryProvider`: 用户音乐库管理
- `SearchProvider`: 搜索功能
- `LocalDatabaseProvider`: SQLite 数据库操作

### 核心服务
- `SpotifyService`: 处理 Spotify Web API 和 SDK 操作
- `LyricsService`: 聚合多个歌词源（QQ音乐、网易云音乐）
- `TranslationService`: Gemini 驱动的歌词翻译
- `InsightsService`: AI 生成的音乐洞察
- `NotificationService`: 用户通知和反馈

### 数据库结构
- 使用 `sqflite` 包进行 SQLite 操作
- 主要实体：tracks（曲目）、records（用户笔记）、translations（翻译）
- 数据库助手位于 `lib/data/database_helper.dart`

## 开发命令

```bash
# 安装依赖
flutter pub get

# 在连接的设备上运行
flutter run

# 运行测试
flutter test

# Android 构建
flutter build apk

# iOS 构建
flutter build ios

# 代码分析
flutter analyze

# 检查 lint 问题
flutter analyze --flutter-lints
```

## 环境设置

### 必需的环境变量
创建 `lib/config/secrets.dart` 文件（使用 `secrets.example.dart` 作为模板）：
```dart
class Secrets {
  static const String spotifyClientId = 'your_spotify_client_id';
  static const String spotifyClientSecret = 'your_spotify_client_secret';
  static const String googleApiKey = 'your_gemini_api_key';
}
```

### Spotify API 设置
- 在 https://developer.spotify.com/dashboard 注册应用
- 添加重定向 URI：`spotoolfy://callback`
- 应用的播放控制功能需要 Spotify Premium

## 平台特定说明

### iOS
- 使用自定义 URL scheme 处理 Spotify OAuth
- 需要 iOS 12.0+（在 `ios/Podfile` 中设置）
- 通过提供的链接可获取 TestFlight 构建版本

### Android
- 最低 SDK 31，目标 SDK 34
- 使用 Spotify App Remote SDK 进行原生播放
- Spotify SDK 功能需要签名 APK

## 测试策略

- 单元测试位于 `test/` 目录
- 专注于服务层测试（歌词提供商、API 调用）
- UI 组件的小部件测试
- 运行测试：`flutter test`

## 核心依赖项

- `spotify_sdk`: 原生 Spotify SDK 集成
- `provider`: 状态管理
- `sqflite`: 本地数据库
- `http`: API 请求
- `cached_network_image`: 图片缓存
- `flutter_secure_storage`: 安全凭据存储
- `palette_generator`: 动态颜色主题
- `logger`: 结构化日志记录

## 本地化

- 支持英语、中文（简体/繁体）、日语
- ARB 文件位于 `lib/l10n/`
- 生成的本地化文件在 `lib/l10n/app_localizations*.dart`
- 配置文件：`l10n.yaml`

## 常见开发任务

### 添加新的歌词提供商
1. 在 `lib/services/lyrics/` 中实现 `LyricProvider` 接口
2. 在 `LyricsService` 构造函数中注册
3. 添加错误处理和速率限制

### 更新 Spotify API 集成
- 主要逻辑在 `SpotifyProvider` 和 `SpotifyService` 中
- 自动处理 token 刷新
- 使用安全存储保存凭据

### 数据库架构更改
- 更新 `DatabaseHelper.createTables()`
- 递增 `DATABASE_VERSION`
- 在 `_upgradeDatabase()` 中添加迁移逻辑

### 主题更新
- 颜色通过 `palette_generator` 从专辑封面提取
- Material 3 设计系统实现
- 深色/浅色模式跟随系统设置

## 代码规范

### 状态管理
- 所有状态更改都应通过 Provider 进行
- 使用 `notifyListeners()` 更新 UI
- 避免在 Provider 中直接操作 UI

### 错误处理
- 网络错误使用智能重试机制
- 用户友好的错误消息
- 关键操作的回退状态

### 日志记录
- 使用 `logger` 包进行结构化日志
- 不同级别：debug、info、warning、error
- 避免在生产环境中记录敏感信息

## 性能优化

### 图片缓存
- 使用 `cached_network_image` 进行网络图片
- 预加载队列中的专辑封面
- 内存中缓存映射以避免重复加载

### 网络请求
- 实现请求去重和缓存
- 智能的网络错误重试
- 批处理相关的 API 调用

### UI 优化
- 使用 `IndexedStack` 保持页面状态
- 延迟加载非关键组件
- 优化列表渲染性能