# 歌词翻译批量测试工具

简化版测试工具，无需 Spotify API，直接使用 CSV 输入进行批量测试。

## 特性

✅ **模块化设计**，5个独立可分离模块
✅ **CSV 输入**，无需 Spotify 凭据
✅ **批量测试**，支持多首歌曲
✅ **三种翻译风格**，完全模拟 App 环境
✅ **自动验证**，集成格式验证器
✅ **纯文本导出**，支持 CometKiwi 等质量评估工具

## 模块说明

### 模块 1: 歌词获取
- QQ 音乐优先，网易云备用
- 自动编码修复
- 保存格式：`00_歌名-歌手_语言.txt`

### 模块 2: 翻译函数
- 完全模拟 App 真实环境
- 使用与 App 相同的 Prompt
- 结构化歌词格式：`__L0001__ >>> 原文`
- 可配置参数：
  - 文件路径
  - Style (1-3)
  - 目标语言（String）
  - Gemini 模型

### 模块 3: 清洗和验证
- 与 App 中的 `parseStructuredTranslation` 逻辑一致
- 使用验证器检查格式
- 三种结果：SUCCESS / AUTO_FIXED / ERROR

### 模块 4: 结果 CSV
- 记录所有测试结果
- 包含验证状态和成功率
- 便于批量分析

### 模块 5: 纯文本导出
- 移除所有时间戳和元数据
- 只保留歌词正文
- 用于 CometKiwi 等评估工具

## 安装

```bash
pip install requests
```

## 使用方法

### 1. 准备输入 CSV

创建 `songs.csv` 文件：

```csv
title,artist,language
Bohemian Rhapsody,Queen,en
Hotel California,Eagles,en
晴天,周杰伦,zh
```

**字段说明**：
- `title`: 歌名
- `artist`: 歌手
- `language`: 语言标记（en=英文, zh=中文, ja=日文等）

### 2. 运行批量测试

```bash
# 基础用法
python lyrics_batch_test.py songs.csv output/

# 指定 API Key
python lyrics_batch_test.py songs.csv output/ --api-key YOUR_GEMINI_KEY

# 完整参数
python lyrics_batch_test.py songs.csv output/ \
  --api-key YOUR_KEY \
  --target-lang "简体中文" \
  --styles "1,2,3" \
  --model "gemini-2.0-flash-exp"
```

### 3. 使用环境变量

```bash
export GEMINI_API_KEY="your_api_key"
python lyrics_batch_test.py songs.csv output/
```

## 参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `input_csv` | 输入 CSV 文件 | 必需 |
| `output_dir` | 输出目录 | 必需 |
| `--api-key` | Gemini API Key | 环境变量 `GEMINI_API_KEY` |
| `--target-lang` | 目标语言 | `简体中文` |
| `--styles` | 翻译风格（逗号分隔） | `1,2,3` |
| `--model` | Gemini 模型 | `gemini-2.0-flash-exp` |

### 翻译风格

| Style | 名称 | 说明 |
|-------|------|------|
| 1 | faithful | 忠实翻译，准确传达原文 |
| 2 | melodramatic_poet | 戏剧化诗人，强化情感 |
| 3 | machine_classic | 机器直译，保留结构 |

### 支持的模型

- `gemini-2.0-flash-exp` (推荐，最新实验版)
- `gemini-1.5-flash`
- `gemini-1.5-pro`
- `gemini-2.0-flash-thinking-exp`

## 输出结构

```
output/
├── lyrics/                    # 原始歌词
│   ├── 00_Song1-Artist1_en.txt
│   ├── 01_Song2-Artist2_zh.txt
│   └── ...
├── translations/              # 翻译结果
│   ├── 00_Song1-Artist1_style1.txt
│   ├── 00_Song1-Artist1_style2.txt
│   ├── 00_Song1-Artist1_style3.txt
│   └── ...
├── plaintext/                 # 纯文本（用于 CometKiwi）
│   ├── 00_Song1-Artist1_original.txt
│   ├── 00_Song1-Artist1_style1_简体中文.txt
│   ├── 00_Song1-Artist1_style2_简体中文.txt
│   └── ...
└── results.csv                # 测试结果汇总
```

## 结果 CSV 格式

```csv
index,title,artist,language,lyrics_source,style,style_name,target_language,model,validation_status,success_rate,translated_lines,missing_lines,issues
0,Bohemian Rhapsody,Queen,en,QQ,1,faithful,简体中文,gemini-2.0-flash-exp,success,1.0,56,0,
0,Bohemian Rhapsody,Queen,en,QQ,2,melodramatic_poet,简体中文,gemini-2.0-flash-exp,auto_fixed,0.98,55,1,warning: 翻译行数不匹配
```

**字段说明**：
- `validation_status`: 验证状态（success / auto_fixed / error）
- `success_rate`: 翻译成功率（0.0-1.0）
- `translated_lines`: 成功翻译的行数
- `missing_lines`: 缺失的行数
- `issues`: 发现的问题（分号分隔）

## 用于 CometKiwi 评估

### 1. 准备参考文本和翻译文本

```bash
# 运行测试后，plaintext/ 目录包含所有纯文本文件
ls output/plaintext/

# 原文
00_Song-Artist_original.txt

# 翻译（三种风格）
00_Song-Artist_style1_简体中文.txt
00_Song-Artist_style2_简体中文.txt
00_Song-Artist_style3_简体中文.txt
```

### 2. 使用 CometKiwi 评估

```python
from comet import download_model, load_from_checkpoint

# 加载模型
model_path = download_model("Unbabel/wmt22-cometkiwi-da")
model = load_from_checkpoint(model_path)

# 评估翻译质量
data = [
    {
        "src": open("00_Song-Artist_original.txt").read(),
        "mt": open("00_Song-Artist_style1_简体中文.txt").read()
    }
]

scores = model.predict(data, batch_size=8, gpus=1)
print(f"Score: {scores['system_score']}")
```

### 3. 批量评估

```python
import os
import glob

plaintext_dir = "output/plaintext/"

# 找到所有原文
originals = glob.glob(f"{plaintext_dir}/*_original.txt")

for original in originals:
    base = original.replace("_original.txt", "")

    # 找到对应的翻译
    translations = glob.glob(f"{base}_style*_简体中文.txt")

    for trans in translations:
        # 评估每个翻译
        src_text = open(original).read()
        mt_text = open(trans).read()

        score = evaluate_translation(src_text, mt_text)
        print(f"{os.path.basename(trans)}: {score}")
```

## 示例：完整工作流程

```bash
# 1. 准备测试歌曲列表
cat > my_songs.csv << EOF
title,artist,language
Imagine,John Lennon,en
Yesterday,The Beatles,en
夜曲,周杰伦,zh
EOF

# 2. 设置 API Key
export GEMINI_API_KEY="your_key_here"

# 3. 运行批量测试（只测试 Style 1 和 2）
python lyrics_batch_test.py my_songs.csv results/ \
  --target-lang "简体中文" \
  --styles "1,2" \
  --model "gemini-2.0-flash-exp"

# 4. 查看结果
cat results/results.csv

# 5. 使用 CometKiwi 评估
cd results/plaintext/
# ... 运行评估脚本
```

## 高级用法

### 只运行特定模块

```python
from lyrics_batch_test import (
    get_lyrics_with_priority,
    translate_lyrics,
    clean_translation,
    validate_translation
)

# 模块 1: 获取歌词
lyrics, source = get_lyrics_with_priority("Song", "Artist")

# 模块 2: 翻译
raw_response, structured = translate_lyrics(
    lyrics,
    target_language="简体中文",
    style=1,
    gemini_api_key="your_key",
    model="gemini-2.0-flash-exp"
)

# 模块 3: 清洗
cleaned = clean_translation(raw_response, lyrics)

# 模块 3: 验证
validation = validate_translation(raw_response, lyrics)

print(f"状态: {validation['status']}")
print(f"成功率: {validation['success_rate']}")
```

### 自定义 Prompt

修改 `get_translation_prompt()` 函数来自定义翻译提示词。

### 添加新的歌词源

```python
class NewLyricsProvider:
    @classmethod
    def fetch_lyrics(cls, title: str, artist: str) -> Optional[str]:
        # 实现你的歌词获取逻辑
        pass

# 在 get_lyrics_with_priority() 中添加
def get_lyrics_with_priority(title: str, artist: str):
    # 尝试 QQ
    # 尝试 NetEase
    # 尝试 NewLyricsProvider  # 新增
    pass
```

## 故障排除

### 问题 1: 找不到歌词

```
✗ 未找到
```

**原因**：歌曲在 QQ 音乐和网易云都不可用

**解决**：
- 检查歌名和歌手是否正确
- 尝试使用英文名或别名
- 添加其他歌词源

### 问题 2: 翻译失败

```
✗ 失败: 429 Too Many Requests
```

**原因**：API 限流

**解决**：
- 增加 `time.sleep()` 延迟
- 使用 `--styles "1"` 只测试一个风格
- 分批处理歌曲

### 问题 3: 验证状态为 ERROR

```
✗ ERROR (45%)
```

**原因**：AI 返回的格式严重错误或缺失过多

**解决**：
- 检查 `translations/` 目录中的原始响应
- 调整 Prompt 或更换模型
- 重新运行该测试用例

## 与原工具对比

| 特性 | `test_lyrics_translation.py` | `lyrics_batch_test.py` |
|------|------------------------------|------------------------|
| 输入 | Spotify Track ID | CSV 文件 |
| 依赖 | Spotify API | 仅 Gemini API |
| 批量测试 | ❌ | ✅ |
| 模块化 | ⚠️ | ✅ 5个独立模块 |
| CometKiwi | ❌ | ✅ 纯文本导出 |
| 结果 CSV | ❌ | ✅ |

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

遵循项目主许可证。
