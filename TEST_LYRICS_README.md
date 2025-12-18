# 歌词翻译质量测试工具

这个 Python 脚本用于测试歌词翻译质量，支持从 Spotify track ID 获取歌曲信息和歌词，并使用 Gemini 2.5 Flash 进行三种不同风格的翻译。

## 功能特性

### 1. 歌曲信息获取
- 从 Spotify API 获取歌曲的基本信息：
  - 歌名
  - 歌手
  - 专辑名
  - 发行日期

### 2. 歌词获取（优先级策略）
- **QQ 音乐**（第一优先级）
  - 支持主域名和备用域名
  - 自动修复编码问题
- **网易云音乐**（第二优先级）
  - 解析 LRC 格式歌词
  - 过滤元数据信息

### 3. 三种翻译风格

使用 **Gemini 2.5 Flash** 模型进行翻译，支持以下三种风格：

#### 风格 1: 忠实翻译 (Faithful)
- 准确传达原文的字面意思和深层含义
- 保持原文的情感基调和氛围
- 使用自然流畅的目标语言表达

#### 风格 2: 戏剧化诗人 (Melodramatic Poet)
- 使用富有诗意和文学性的表达
- 强化情感的渲染和戏剧张力
- 适当使用修辞手法（比喻、拟人等）
- 营造更强烈的艺术氛围

#### 风格 3: 机器古典 (Machine Classic)
- 逐字逐句直译，保留原文结构
- 优先选择常见、经典的词汇
- 保持译文的简洁和规范
- 不添加额外的修饰或解释

### 4. 结构化翻译格式

使用行号标记确保翻译的准确对应：

```
输入格式：
__L0001__ >>> 原文第一行
__L0002__ >>> 原文第二行
__L0003__ >>> [BLANK]

输出格式：
__L0001__ <<< 翻译的第一行
__L0002__ <<< 翻译的第二行
__L0003__ <<<
```

## 安装依赖

```bash
pip install -r requirements_test.txt
```

## 配置 API 密钥

### 方式 1: 使用环境变量（推荐）

复制示例配置文件：
```bash
cp .env.example .env
```

编辑 `.env` 文件，填入你的 API 密钥：
```bash
SPOTIFY_CLIENT_ID=your_spotify_client_id
SPOTIFY_CLIENT_SECRET=your_spotify_client_secret
GEMINI_API_KEY=your_gemini_api_key
```

加载环境变量：
```bash
# Linux/macOS
export $(cat .env | xargs)

# 或者使用 python-dotenv
pip install python-dotenv
```

### 方式 2: 使用命令行参数

```bash
python test_lyrics_translation.py <track_id> \
  --spotify-client-id YOUR_CLIENT_ID \
  --spotify-client-secret YOUR_CLIENT_SECRET \
  --gemini-api-key YOUR_GEMINI_KEY
```

### 获取 API 密钥

#### Spotify API
1. 访问 [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. 创建一个新应用
3. 获取 Client ID 和 Client Secret

#### Gemini API
1. 访问 [Google AI Studio](https://aistudio.google.com/app/apikey)
2. 创建 API Key

## 使用方法

### 基本用法

```bash
python test_lyrics_translation.py <spotify_track_id>
```

### 指定目标语言

```bash
python test_lyrics_translation.py <spotify_track_id> --language "English"
```

### 完整示例

```bash
# 翻译为简体中文（默认）
python test_lyrics_translation.py 3n3Ppam7vgaVa1iaRUc9Lp

# 翻译为英文
python test_lyrics_translation.py 3n3Ppam7vgaVa1iaRUc9Lp --language "English"

# 翻译为日文
python test_lyrics_translation.py 3n3Ppam7vgaVa1iaRUc9Lp --language "日本語"
```

### 如何获取 Spotify Track ID

从 Spotify 分享链接中提取：
```
https://open.spotify.com/track/3n3Ppam7vgaVa1iaRUc9Lp?si=xxx
                                ^^^^^^^^^^^^^^^^^^^^^^
                                这就是 Track ID
```

## 输出结果

### 控制台输出

脚本会在控制台输出：
1. 歌曲基本信息
2. 歌词来源和统计信息
3. 三种风格的翻译进度
4. 前 5 行翻译结果预览

示例：
```
================================================================================
歌词翻译质量测试
================================================================================

[1] 获取 Spotify 歌曲信息...
  歌名: Bohemian Rhapsody
  歌手: Queen
  专辑: A Night at the Opera
  发行日期: 1975-11-21

[2] 获取歌词...
  尝试 QQ 音乐...
  ✓ 从 QQ 音乐获取成功
  来源: QQ Music
  歌词长度: 1234 字符
  歌词行数: 56 行

[3] 使用 Gemini 2.5 Flash 进行三种风格翻译（目标语言: 简体中文）...

使用 Gemini 2.5 Flash 翻译（风格: faithful）...
  ✓ 翻译完成：56/56 行

使用 Gemini 2.5 Flash 翻译（风格: melodramatic_poet）...
  ✓ 翻译完成：55/56 行
  ⚠ 缺失 1 行翻译

...
```

### JSON 文件输出

脚本会生成一个 JSON 文件：`translation_test_<track_id>_<timestamp>.json`

文件结构：
```json
{
  "track_info": {
    "track_id": "3n3Ppam7vgaVa1iaRUc9Lp",
    "name": "Song Name",
    "artists": "Artist Name",
    "album": "Album Name",
    "release_date": "2023-01-01",
    "lyrics_source": "QQ Music"
  },
  "original_lyrics": "原始歌词文本...",
  "target_language": "简体中文",
  "translations": {
    "faithful": {
      "cleaned_text": "清理后的翻译文本...",
      "raw_response": "AI 原始响应...",
      "line_count": 56,
      "missing_lines": [],
      "line_translations": {
        "0": "第一行翻译",
        "1": "第二行翻译"
      }
    },
    "melodramatic_poet": { ... },
    "machine_classic": { ... }
  }
}
```

## 代码结构

```
test_lyrics_translation.py
├── 数据模型
│   ├── TrackInfo          # 歌曲信息
│   ├── TranslationResult  # 翻译结果
│   └── TranslationStyle   # 翻译风格枚举
├── Spotify API 客户端
│   └── SpotifyClient      # Spotify 认证和歌曲信息获取
├── 歌词提供者
│   ├── QQMusicProvider    # QQ 音乐歌词获取
│   ├── NetEaseProvider    # 网易云音乐歌词获取
│   └── LyricsService      # 歌词服务（优先级策略）
├── 翻译服务
│   └── GeminiTranslator   # Gemini AI 翻译
└── 主测试函数
    └── test_translation_quality()
```

## 高级用法

### 在 Python 代码中调用

```python
from test_lyrics_translation import test_translation_quality

# 执行测试
result = test_translation_quality(
    track_id='3n3Ppam7vgaVa1iaRUc9Lp',
    target_language='简体中文',
    spotify_client_id='your_id',
    spotify_client_secret='your_secret',
    gemini_api_key='your_key'
)

# 访问结果
print(result['track_info']['name'])
print(result['translations']['faithful']['cleaned_text'])
```

### 单独使用各个组件

```python
from test_lyrics_translation import (
    SpotifyClient,
    LyricsService,
    GeminiTranslator,
    TranslationStyle
)

# 1. 获取歌曲信息
spotify = SpotifyClient(client_id, client_secret)
track = spotify.get_track_info('3n3Ppam7vgaVa1iaRUc9Lp')

# 2. 获取歌词
lyrics, source = LyricsService.get_lyrics(track.name, track.artists)

# 3. 翻译歌词
translator = GeminiTranslator(api_key)
result = translator.translate_lyrics(
    lyrics,
    target_language='English',
    style=TranslationStyle.FAITHFUL
)

print(result.cleaned_text)
```

## 注意事项

1. **API 限流**：脚本在翻译之间有 1 秒延迟，避免触发 Gemini API 限流

2. **歌词可用性**：并非所有歌曲都能从 QQ 音乐或网易云获取歌词，建议使用知名度较高的歌曲进行测试

3. **翻译质量**：AI 翻译质量取决于：
   - 歌词的复杂度
   - 语言对（如中英互译通常效果较好）
   - 提示词的设计

4. **缺失行检测**：脚本会检测并报告未能翻译的行（通常是空行或 AI 遗漏）

5. **编码问题**：QQ 音乐歌词可能存在编码问题，脚本会自动尝试修复

## 测试建议

### 选择测试歌曲

建议选择以下类型的歌曲进行测试：

1. **经典流行歌曲**：如 Queen - Bohemian Rhapsody
2. **不同语言**：英文、中文、日文、韩文等
3. **不同风格**：流行、摇滚、民谣、说唱等
4. **复杂歌词**：诗意的、抽象的、俚语多的

### 质量评估维度

对比三种翻译风格时，可以从以下维度评估：

1. **准确性**：是否准确传达原文含义
2. **流畅性**：译文是否自然流畅
3. **艺术性**：是否保留或增强艺术感染力
4. **完整性**：缺失行的数量
5. **一致性**：术语和人称的一致性

## 故障排除

### 问题 1: 无法获取歌词

```
✗ 所有来源均未找到歌词
```

**解决方案**：
- 确认歌曲在 QQ 音乐或网易云音乐上可用
- 尝试使用更知名的歌曲
- 检查网络连接

### 问题 2: Spotify API 认证失败

```
✗ 401 Unauthorized
```

**解决方案**：
- 检查 Client ID 和 Client Secret 是否正确
- 确认 API 凭证未过期

### 问题 3: Gemini API 限流

```
✗ 429 Too Many Requests
```

**解决方案**：
- 增加翻译之间的延迟时间
- 等待几分钟后重试
- 检查 API 配额

### 问题 4: 翻译缺失行过多

```
⚠ 缺失 10 行翻译
```

**解决方案**：
- 这是 AI 生成的随机性导致的
- 可以调整 `temperature` 参数（当前为 0.8）
- 重新运行测试，结果可能会不同

## 许可证

本脚本遵循项目主许可证。

## 贡献

欢迎提交 Issue 和 Pull Request！
