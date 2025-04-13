Spotoolfy 本地化与功能增强开发计划
目标: 将应用的数据存储从 Firebase 完全迁移到设备本地的 SQLite 数据库，增强歌曲记录功能（包含歌词快照和上下文），添加多版本翻译存储，并实现数据的导出与导入，为最终开源做准备。

最终数据库设计 (SQLite)
我们将使用以下三个核心表：

1. tracks 表 (存储歌曲元数据)

|

| 列名 | 数据类型 | 约束 | 描述 |
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | 本地数据库唯一 ID |
| trackId | TEXT | NOT NULL, UNIQUE | Spotify 歌曲的唯一 ID |
| trackName | TEXT | NOT NULL | 歌曲名称 |
| artistName | TEXT | NOT NULL | 艺术家名称 |
| albumName | TEXT | NOT NULL | 专辑名称 |
| albumCoverUrl | TEXT |  | 专辑封面的 URL |
| lastRecordedAt | INTEGER |  | 最后一次为此歌曲添加 Record 的时间戳 (Unix 毫秒，UTC) |
| latestPlayedAt | INTEGER |  | 从 Spotify API 获取的该歌曲的最后播放时间戳 (Unix 毫秒，UTC) |

索引: trackId

2. records 表 (存储用户记录/想法)

| 列名 | 数据类型 | 约束 | 描述 |
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | 本地数据库唯一 ID |
| trackId | TEXT | NOT NULL, FOREIGN KEY (REFERENCES tracks) | 关联到 tracks 表中的歌曲 trackId |
| noteContent | TEXT |  | 用户输入的笔记/想法内容 |
| rating | TEXT |  | 用户评分 (例如 'good', 'bad', 'fire') |
| songTimestampMs | INTEGER |  | 记录时，歌曲播放到的进度 (毫秒) |
| recordedAt | INTEGER | NOT NULL | 这条记录被创建/保存时的绝对时间戳 (Unix 毫秒，UTC) |
| contextUri | TEXT |  | （可选）播放时所在的 Spotify 上下文 URI (如 spotify:playlist:xxx) |
| contextName | TEXT |  | （可选）播放时所在的 Spotify 上下文名称 (如播放列表或专辑名) |
| lyricsSnapshot | TEXT |  | （可选）记录时该歌曲的歌词快照 |

索引: trackId, recordedAt 外键: FOREIGN KEY (trackId) REFERENCES tracks (trackId) ON DELETE CASCADE ON UPDATE CASCADE

3. translations 表 (存储歌词翻译)

| 列名 | 数据类型 | 约束 | 描述 |
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | 本地数据库唯一 ID |
| trackId | TEXT | NOT NULL, FOREIGN KEY (REFERENCES tracks) | 关联到 tracks 表中的歌曲 trackId |
| languageCode | TEXT | NOT NULL | 目标翻译语言代码 (例如 'en', 'zh-CN', 'ja') |
| style | TEXT | NOT NULL | 翻译风格标识符 (例如 'faithful', 'melodramaticPoet', 'machineClassic') |
| translatedLyrics | TEXT | NOT NULL | 翻译后的歌词文本 |
| generatedAt | INTEGER | NOT NULL | 该翻译生成或保存时的时间戳 (Unix 毫秒，UTC) |
|  |  | UNIQUE (trackId, languageCode, style) | 确保同一种翻译只存储一份 |

索引: trackId, (trackId, languageCode, style) (用于 UNIQUE 约束) 外键: FOREIGN KEY (trackId) REFERENCES tracks (trackId) ON DELETE CASCADE ON UPDATE CASCADE

开发阶段与步骤
阶段一：基础设置与数据库核心实现

任务 1.1: 依赖管理

在 pubspec.yaml 中添加 sqflite, path_provider。

(暂不移除 Firebase 依赖，待后续迁移完成后再移除)

任务 1.2: 创建数据模型类 (Data Models)

在 lib/models (或新建 lib/data/models) 目录下创建 Dart 类：Track, Record, Translation，其属性对应上述数据库表的列。

任务 1.3: 创建数据库助手 (DatabaseHelper)

创建 lib/data/database_helper.dart 文件。

实现单例模式 (Singleton) 获取数据库实例。

实现 initDb() 方法：

使用 path_provider 获取数据库文件路径 (your_app_database.db)。

调用 sqflite.openDatabase() 打开数据库。

设置 version: 1。

在 onCreate 回调中，执行 CREATE TABLE SQL 语句创建 tracks, records, translations 三个表（包含所有列、约束和索引）。

(可选) 添加 onUpgrade 回调的空实现，为未来可能的数据库结构变更做准备。

实现基础的 CRUD (Create, Read, Update, Delete) 方法：

Future<int> insertTrack(Track track)

Future<Track?> getTrack(String trackId)

Future<int> insertRecord(Record record)

Future<List<Record>> getRecordsForTrack(String trackId)

Future<int> insertTranslation(Translation translation)

Future<Translation?> getTranslation(String trackId, String languageCode, String style)

Future<void> updateTrackLastRecordedAt(String trackId, int timestamp)

Future<void> updateTrackLatestPlayedAt(String trackId, int timestamp)

测试节点 1:

编写单元测试或集成测试来验证 DatabaseHelper：

数据库能否成功创建？

tracks, records, translations 表结构是否正确？

基础的插入和查询方法是否按预期工作？

UNIQUE 约束是否生效？

阶段二：Provider 层重构

任务 2.1: 创建 LocalDatabaseProvider

创建 lib/providers/local_database_provider.dart 文件。

使其成为 ChangeNotifier。

注入（或创建）DatabaseHelper 实例。

实现基本的数据获取方法，调用 DatabaseHelper：

Future<void> fetchRecordsForTrack(String trackId) (获取数据并更新内部状态，然后 notifyListeners())

Future<void> fetchRandomRecords(int count)

Future<Translation?> fetchTranslation(...)

添加 isLoading 状态管理。

添加空的 addRecord, saveTranslation, updateLatestPlayedTime 等方法占位。

任务 2.2: 注册新 Provider

在 main.dart 中，在 MultiProvider 的 providers 列表中注册 ChangeNotifierProvider(create: (_) => LocalDatabaseProvider())。

(暂时保留 FirestoreProvider 和 AuthProvider 的注册)

任务 2.3: UI 读取端初步对接

选择几个只读取数据的 Widget（例如 NotesDisplay 的一部分，Roam 页面的列表）。

修改这些 Widget，使其 Consumer 或 context.watch 的目标从 FirestoreProvider 改为 LocalDatabaseProvider。

调整 UI 以显示从新 Provider 获取的数据（即使是空列表或加载状态）。

(提示) 你可能需要在 DatabaseHelper 中插入一些临时的测试数据，以便在 UI 中看到效果。

测试节点 2:

运行应用，导航到修改过的页面。

检查 Provider 是否正确注入，没有报错。

确认 UI 是否能正确反映 LocalDatabaseProvider 的 isLoading 状态和（测试）数据。

检查原有的 Firebase 数据读取是否仍然正常工作（因为还未移除）。

阶段三：核心功能迁移与增强

任务 3.1: 实现 addRecord 核心逻辑

在 LocalDatabaseProvider 中完善 addRecord 方法。

输入: 需要 noteContent, rating, songTimestampMs, contextUri, contextName 以及当前的 Track 对象 (包含 trackId, trackName 等) 和 lyricsSnapshot (从 AddNoteSheet 传递过来)。

逻辑:

获取 recordedAt (当前时间戳)。

调用 _dbHelper.getTrack(track.trackId) 检查 tracks 表。

如果 Track 不存在:

创建 Track 对象（包含 trackId, trackName 等，lastRecordedAt = recordedAt, latestPlayedAt = null）。

调用 _dbHelper.insertTrack(newTrack)。

如果 Track 存在:

调用 _dbHelper.updateTrackLastRecordedAt(track.trackId, recordedAt)。

创建 Record 对象（包含所有记录信息和 lyricsSnapshot）。

调用 _dbHelper.insertRecord(newRecord)。

(可选) 插入成功后，可以立即刷新当前轨道的记录列表 (fetchRecordsForTrack)。

任务 3.2: 更新 AddNoteSheet

修改 _handleSubmit 方法：

从 SpotifyProvider 获取当前歌曲的 Track 信息。

调用 LyricsService 获取当前歌词，作为 lyricsSnapshot。

调用 LocalDatabaseProvider.addRecord 并传递所有需要的数据。

移除原有的 FirestoreProvider.addThought 调用。

任务 3.3: 实现翻译保存逻辑

在 LocalDatabaseProvider 中实现 saveTranslation 方法，调用 _dbHelper.insertTranslation (处理可能的 UNIQUE 约束冲突，例如使用 insert...onConflictUpdate)。

修改 TranslationService 或 TranslationResultSheet，在成功获取翻译后，调用 LocalDatabaseProvider.saveTranslation。

任务 3.4: 实现 latestPlayedAt 更新逻辑

在 SpotifyProvider 或 LocalDatabaseProvider 中，添加监听 SpotifyProvider.currentTrack 变化的逻辑。

当 trackId 变化时，调用 Spotify API (/me/player/recently-played?limit=1)。

解析返回的 played_at 时间戳。

调用 LocalDatabaseProvider 中的方法（该方法再调用 _dbHelper.updateTrackLatestPlayedAt）。

在应用启动时，调用一次获取 limit=50 的最近播放列表，并更新所有匹配到的本地 tracks 的 latestPlayedAt。

测试节点 3:

添加记录:

播放一首歌，打开 AddNoteSheet，输入内容并保存。

使用数据库浏览器检查 tracks 和 records 表数据是否正确插入/更新 (lastRecordedAt, lyricsSnapshot 等)。

再次为同一首歌添加记录，检查 tracks 表是否只更新了 lastRecordedAt，records 表是否新增了记录。

翻译:

翻译一首歌词。检查 translations 表是否正确保存了结果。

再次翻译同一首歌（相同语言、相同风格），检查数据库是否没有重复插入（或是否正确更新了时间戳，取决于你的冲突处理策略）。

关闭应用再打开，翻译同一首歌，确认是从数据库加载而不是重新请求 API。

播放时间: 切换歌曲，检查 tracks 表中的 latestPlayedAt 是否被更新。

阶段四：高级功能与 UI 集成完善

任务 4.1: 实现 Roam 页面

在 LocalDatabaseProvider 中实现 fetchRandomRecords 方法，使用 JOIN 查询从 records 和 tracks 表获取随机记录及其关联的歌曲信息。

更新 Roam 页面 (lib/pages/roam.dart) 以调用此方法并显示数据。

任务 4.2: 实现相关想法 (同名歌曲)

在 LocalDatabaseProvider 中实现 fetchRelatedThoughts 方法，根据当前 trackName 查询 tracks 表获取所有同名 trackId，然后查询 records 表（排除当前 trackId），可能需要 JOIN 获取歌曲信息。

更新 NotesDisplay Widget (lib/widgets/notes.dart) 以调用此方法并显示“RELATED THOUGHTS”部分。

任务 4.3: 歌词显示优化

(此任务可能不需要，因为原始歌词通常由 LyricsService 实时获取，而不是存储在 tracks 表中。如果你的设计是在 tracks 表存一份原始歌词，则需要修改 LyricsWidget 先检查数据库)

确认 LyricsWidget (lib/widgets/lyrics.dart) 是否需要修改以适应新的数据流（如果之前依赖 FirestoreProvider 的话）。

任务 4.4: 翻译显示优化

修改 TranslationResultSheet (lib/widgets/translation_result_sheet.dart)，在显示翻译前，先调用 LocalDatabaseProvider.fetchTranslation 尝试从数据库加载。如果数据库没有，再调用 TranslationService 请求 API。

测试节点 4:

Roam: 反复刷新 Roam 页面，检查是否能正确加载随机记录及其关联的歌曲信息。

Related Thoughts: 播放一首有同名歌曲记录的歌，检查“RELATED THOUGHTS”部分是否正确显示。

Translation: 打开翻译面板，检查是否优先从数据库加载已有的翻译。清除数据库后，检查是否能正常调用 API 获取并保存。

阶段五：导出/导入与 Firebase 清理

任务 5.1: 实现数据导出

在 LocalDatabaseProvider 中实现 exportDataToJson() 方法：

查询 tracks, records, translations 表的所有数据。

将数据构造成一个合适的 JSON 结构（例如，一个包含三个列表的对象）。

将 JSON 写入临时文件。

使用 share_plus 提供分享/保存选项。

在设置页面 (login.dart) 添加“导出数据”按钮并连接逻辑。

任务 5.2: 实现数据导入

在 LocalDatabaseProvider 中实现 importDataFromJson() 方法：

使用文件选择器让用户选择 JSON 文件。

读取并解析 JSON 数据。

重要: 实现冲突处理逻辑（是跳过、覆盖还是合并？建议提供选项或默认跳过）。

调用 DatabaseHelper 的插入方法将数据写入数据库。

警告: 如果选择覆盖，必须明确警告用户当前数据将丢失。

在设置页面 (login.dart) 添加“导入数据”按钮，连接逻辑，并包含必要的警告信息。

任务 5.3: 移除 Firebase

确认所有功能已迁移到本地数据库且工作正常。

从 pubspec.yaml 中移除所有 firebase_* 和 google_sign_in 依赖。

删除 lib/firebase_options.dart 文件。

移除 main.dart 中的 Firebase.initializeApp() 和 AuthProvider, FirestoreProvider 的注册。

删除 lib/providers/auth_provider.dart 和 lib/providers/firestore_provider.dart 文件。

移除 login.dart 中所有与 Google 登录相关的 UI 和逻辑。

清理代码中所有残留的 Firebase 相关导入和调用。

测试节点 5:

Export: 导出一份数据，检查生成的 JSON 文件内容是否完整、格式是否正确。

Import:

（可选）清除应用数据或在一个新设备上安装。

导入之前导出的 JSON 文件。

检查数据是否成功恢复，记录、歌曲信息、翻译是否都存在。

测试导入包含冲突数据的文件的行为是否符合预期。

Firebase Removal: 确认应用在移除 Firebase 依赖后仍能正常编译和运行所有功能。

回归测试: 全面测试应用的所有核心功能（播放、记录、歌词、翻译、Roam、设置、导出、导入），确保没有引入新的 Bug。

阶段六：文档与开源准备

任务 6.1: 更新 README.md

详细说明项目目的、功能。

提供清晰的设置指南，特别是如何获取和配置 Spotify API 凭据（引导用户修改 secrets.dart 或通过 UI 输入）。

解释本地存储机制和导出/导入功能。

包含构建和运行说明。

任务 6.2: 添加代码注释

为主要类、方法和复杂逻辑添加清晰的注释。

任务 6.3: 选择并添加许可证

在项目根目录添加 LICENSE 文件（例如 MIT, Apache 2.0）。

任务 6.4: 代码库清理

检查并确认没有将 secrets.dart 或其他敏感信息提交到版本控制。

移除不必要的文件或注释掉的旧代码。

这个计划提供了一个清晰的路线图。每个阶段都有明确的任务和测试节点，有助于你逐步完成这次重要的重构。祝你开发顺利！