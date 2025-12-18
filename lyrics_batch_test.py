#!/usr/bin/env python3
"""
歌词翻译批量测试工具

输入：CSV 文件（包含歌名、歌手、语言）
输出：
1. 原始歌词文件
2. 翻译结果 CSV
3. 纯文本歌词（用于 CometKiwi 评估）
"""

import os
import csv
import json
import time
import requests
from typing import Optional, Dict, List, Tuple
from dataclasses import dataclass
from pathlib import Path


# ============================================================================
# 模块 1: 歌词获取
# ============================================================================

class QQMusicProvider:
    """QQ音乐歌词提供者"""

    BASE_URL = 'https://c.y.qq.com'
    BACKUP_URL = 'https://u6.y.qq.com'

    HEADERS = {
        'referer': 'https://y.qq.com/',
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }

    @classmethod
    def search_song(cls, title: str, artist: str) -> Optional[str]:
        """搜索歌曲，返回 songmid"""
        params = {
            'w': f'{title} {artist}',
            'p': '1',
            'n': '3',
            'format': 'json'
        }

        try:
            response = requests.get(
                f'{cls.BASE_URL}/soso/fcgi-bin/client_search_cp',
                params=params,
                headers=cls.HEADERS,
                timeout=10
            )
            response.raise_for_status()
            data = response.json()
            songs = data.get('data', {}).get('song', {}).get('list', [])
            if songs:
                return songs[0].get('songmid')
        except Exception as e:
            print(f"    QQ音乐搜索失败: {e}")
        return None

    @classmethod
    def get_lyrics(cls, songmid: str, use_backup: bool = False) -> Optional[str]:
        """获取歌词"""
        base_url = cls.BACKUP_URL if use_backup else cls.BASE_URL
        params = {
            'songmid': songmid,
            'format': 'json',
            'nobase64': '1'
        }

        try:
            response = requests.get(
                f'{base_url}/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
                params=params,
                headers=cls.HEADERS,
                timeout=10
            )
            response.raise_for_status()
            data = response.json()
            lyric = data.get('lyric', '')
            if lyric:
                return cls._normalize_encoding(lyric)
        except Exception as e:
            if not use_backup:
                return cls.get_lyrics(songmid, use_backup=True)
        return None

    @staticmethod
    def _normalize_encoding(text: str) -> str:
        """修复编码问题"""
        try:
            return text.encode('latin1').decode('utf-8')
        except:
            return text

    @classmethod
    def fetch_lyrics(cls, title: str, artist: str) -> Optional[str]:
        """搜索并获取歌词"""
        songmid = cls.search_song(title, artist)
        if songmid:
            return cls.get_lyrics(songmid)
        return None


class NetEaseProvider:
    """网易云音乐歌词提供者"""

    BASE_URL = 'https://163api.qijieya.cn'

    @classmethod
    def search_song(cls, title: str, artist: str) -> Optional[str]:
        """搜索歌曲，返回 song ID"""
        params = {
            'keywords': f'{title} {artist}',
            'limit': '1'
        }

        try:
            response = requests.get(
                f'{cls.BASE_URL}/cloudsearch',
                params=params,
                timeout=10
            )
            response.raise_for_status()
            data = response.json()
            songs = data.get('result', {}).get('songs', [])
            if songs:
                return str(songs[0].get('id'))
        except Exception as e:
            print(f"    网易云搜索失败: {e}")
        return None

    @classmethod
    def get_lyrics(cls, song_id: str) -> Optional[str]:
        """获取歌词"""
        params = {'id': song_id}

        try:
            response = requests.get(
                f'{cls.BASE_URL}/lyric/new',
                params=params,
                timeout=10
            )
            response.raise_for_status()
            data = response.json()
            lrc = data.get('lrc', {}).get('lyric', '')
            if lrc:
                return cls._parse_lrc(lrc)
        except Exception as e:
            print(f"    网易云获取歌词失败: {e}")
        return None

    @staticmethod
    def _parse_lrc(lrc_text: str) -> str:
        """解析 LRC 格式歌词"""
        import re
        lines = []
        pattern = r'\[\d{2}:\d{2}\.\d{2,3}\](.+)'

        for line in lrc_text.strip().split('\n'):
            match = re.search(pattern, line)
            if match:
                text = match.group(1).strip()
                if not text.startswith(('作词', '作曲', '编曲', '制作')):
                    lines.append(text)
        return '\n'.join(lines)

    @classmethod
    def fetch_lyrics(cls, title: str, artist: str) -> Optional[str]:
        """搜索并获取歌词"""
        song_id = cls.search_song(title, artist)
        if song_id:
            return cls.get_lyrics(song_id)
        return None


def get_lyrics_with_priority(title: str, artist: str) -> Tuple[Optional[str], Optional[str]]:
    """
    获取歌词（QQ优先，网易云备用）

    返回: (歌词文本, 来源)
    """
    print(f"  获取歌词: {title} - {artist}")

    # 1. QQ音乐
    print("    尝试 QQ音乐...")
    lyrics = QQMusicProvider.fetch_lyrics(title, artist)
    if lyrics:
        print("    ✓ QQ音乐")
        return lyrics, "QQ"

    # 2. 网易云
    print("    尝试 网易云...")
    lyrics = NetEaseProvider.fetch_lyrics(title, artist)
    if lyrics:
        print("    ✓ 网易云")
        return lyrics, "NetEase"

    print("    ✗ 未找到")
    return None, None


def save_lyrics_file(lyrics: str, index: int, title: str, artist: str, lang: str, output_dir: str) -> str:
    """
    保存歌词文件

    格式: 00_歌名-歌手_语言.txt
    """
    filename = f"{index:02d}_{title}-{artist}_{lang}.txt"
    # 清理文件名中的非法字符
    filename = "".join(c for c in filename if c.isalnum() or c in (' ', '-', '_', '.')).strip()
    filepath = os.path.join(output_dir, filename)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(lyrics)

    return filepath


# ============================================================================
# 模块 2: 翻译函数（模拟真实 App 环境）
# ============================================================================

def translate_lyrics(
    lyrics: str,
    target_language: str,
    style: int,
    gemini_api_key: str,
    model: str = "gemini-2.0-flash-exp"
) -> Tuple[str, str]:
    """
    翻译歌词（模拟 App 真实环境）

    Args:
        lyrics: 原始歌词
        target_language: 目标语言（如 "简体中文", "English"）
        style: 翻译风格 (1=faithful, 2=melodramatic_poet, 3=machine_classic)
        gemini_api_key: Gemini API Key
        model: Gemini 模型名称

    Returns:
        (原始响应, 结构化歌词)
    """
    # 构建结构化歌词（与 App 一致）
    structured_lyrics, original_lines = build_structured_lyrics(lyrics)

    # 获取 Prompt
    prompt = get_translation_prompt(style, structured_lyrics, target_language)

    # 调用 Gemini API
    url = f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'

    payload = {
        'contents': [{
            'parts': [{'text': prompt}]
        }],
        'generationConfig': {
            'temperature': 0.8,
        }
    }

    response = requests.post(
        f'{url}?key={gemini_api_key}',
        headers={'Content-Type': 'application/json'},
        json=payload,
        timeout=60
    )
    response.raise_for_status()

    data = response.json()
    response_text = data['candidates'][0]['content']['parts'][0]['text']

    return response_text, structured_lyrics


def build_structured_lyrics(lyrics: str) -> Tuple[str, List[str]]:
    """
    构建结构化歌词（与 App 中的 buildStructuredLyrics 一致）

    格式:
    __L0001__ >>> 第一行
    __L0002__ >>> 第二行
    __L0003__ >>> [BLANK]
    """
    lines = lyrics.strip().split('\n')
    structured_lines = []

    for i, line in enumerate(lines, 1):
        text = line.strip() if line.strip() else '[BLANK]'
        structured_lines.append(f'__L{i:04d}__ >>> {text}')

    return '\n'.join(structured_lines), lines


def get_translation_prompt(style: int, structured_lyrics: str, target_language: str) -> str:
    """
    获取翻译 Prompt（与 App 中的逻辑一致）

    Args:
        style: 1=faithful, 2=melodramatic_poet, 3=machine_classic
    """
    base_instructions = f"""输入格式：
__L0001__ >>> 原文第一行
__L0002__ >>> 原文第二行
__L0003__ >>> [BLANK]

你的输出格式必须严格遵循：
__L0001__ <<< 翻译的第一行
__L0002__ <<< 翻译的第二行
__L0003__ <<<

歌词内容：
{structured_lyrics}"""

    if style == 1:  # faithful
        return f"""你是一位专业的歌词翻译专家。请将以下歌词翻译成{target_language}，保持忠实于原文的含义和情感。

翻译要求：
1. 准确传达原文的字面意思和深层含义
2. 保持原文的情感基调和氛围
3. 使用自然流畅的{target_language}表达
4. 保持每一行的对应关系

{base_instructions}

请开始翻译："""

    elif style == 2:  # melodramatic_poet
        return f"""你是一位充满激情的诗人和歌词翻译家。请将以下歌词翻译成{target_language}，用诗意和戏剧化的方式演绎。

翻译风格：
1. 使用富有诗意和文学性的表达
2. 强化情感的渲染和戏剧张力
3. 可以适当使用修辞手法（比喻、拟人等）
4. 营造更强烈的艺术氛围

{base_instructions}

请用你的诗意才华翻译："""

    elif style == 3:  # machine_classic
        return f"""你是一位追求精准和经典的翻译机器。请将以下歌词翻译成{target_language}，采用直译风格。

翻译原则：
1. 逐字逐句直译，最大程度保留原文结构
2. 优先选择常见、经典的词汇
3. 保持译文的简洁和规范
4. 不添加额外的修饰或解释

{base_instructions}

请开始直译："""

    return ""


# ============================================================================
# 模块 3: 清洗和验证逻辑（与 App 一致）
# ============================================================================

def clean_translation(raw_response: str, original_lyrics: str) -> Dict:
    """
    清洗翻译结果（完全模拟 App 中的 parseStructuredTranslation）

    与 App 的差异：
    - App 在 Dart 中，这是 Python 实现
    - 但逻辑完全一致，包括 fallback、容错、防御性清理等

    返回:
    {
        'cleaned_text': '清洗后的翻译',
        'line_translations': {0: '第一行', 1: '第二行'},
        'missing_lines': [2, 5]
    }
    """
    import re

    original_lines = original_lyrics.strip().split('\n')
    sanitized = raw_response.replace('\r\n', '\n')

    # 支持两种分隔符（与 App 一致）
    delimiter_pattern = r'(?:<<<|>>>)'

    # 匹配标记（与 App 的 markerRegex 一致）
    marker_regex = re.compile(
        r'__L(\d{4})__\s*' + delimiter_pattern,
        re.MULTILINE
    )

    matches = list(marker_regex.finditer(sanitized))
    line_translations = {}

    # Fallback 逻辑：如果找不到标记，尝试按行对齐（与 App 一致）
    if not matches:
        fallback_lines = [line.strip() for line in sanitized.split('\n') if line.strip()]

        if len(fallback_lines) == len(original_lines):
            for i, line in enumerate(fallback_lines):
                line_translations[i] = line

        # 构建清洗后的文本（去除标记）
        cleaned = _clean_markers_from_text(sanitized).strip()

        return {
            'cleaned_text': cleaned if cleaned else '\n'.join(fallback_lines),
            'line_translations': line_translations,
            'missing_lines': _find_missing_indices(original_lines, line_translations)
        }

    # 提取每个标记对应的段落（与 App 一致）
    for i, match in enumerate(matches):
        idx = int(match.group(1))
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(sanitized)

        segment = sanitized[start:end]

        # 去除包裹的代码块标记（与 App 的 _stripWrappingDelimiters 一致）
        segment = _strip_wrapping_delimiters(segment)

        # 防御性清理：处理多余的分隔符（与 App 一致）
        if '<<<' in segment:
            segment = segment.split('<<<')[-1]
        if '>>>' in segment:
            segment = segment.split('>>>')[-1]

        # 处理 [BLANK] 标记
        if segment.strip() == '[BLANK]':
            segment = ''

        line_translations[idx - 1] = segment.strip()

    # 构建清洗后的文本（与 App 的 _buildCleanedText 一致）
    cleaned_lines = []
    for i, original in enumerate(original_lines):
        translated = line_translations.get(i, '').strip()
        if translated:
            cleaned_lines.append(translated)
        else:
            # 用原文替代（与 App 一致，不用 [MISSING] 标记）
            cleaned_lines.append(original)

    return {
        'cleaned_text': '\n'.join(cleaned_lines).strip(),
        'line_translations': line_translations,
        'missing_lines': _find_missing_indices(original_lines, line_translations)
    }


def _strip_wrapping_delimiters(value: str) -> str:
    """去除包裹标记（与 App 一致）"""
    result = value.strip()

    # 去除 ``` 包裹
    if result.startswith('```') and result.endswith('```'):
        result = result[3:-3].strip()

    # 去除 ### 包裹
    if result.startswith('###') and result.endswith('###'):
        result = result[3:-3].strip()

    return result


def _find_missing_indices(original_lines: List[str], translations: Dict[int, str]) -> List[int]:
    """查找缺失的行索引（与 App 一致）"""
    missing = []
    for i, original in enumerate(original_lines):
        translated = translations.get(i, '').strip()
        # 只检查非空原文行
        if original.strip() and not translated:
            missing.append(i)
    return missing


def _clean_markers_from_text(value: str) -> str:
    """从文本中清除所有标记（与 App 一致）"""
    import re

    # 清除输入标记 __L0001__ >>>
    value = re.sub(
        r'__L\d{4}__\s*>>>\s*',
        '',
        value,
        flags=re.IGNORECASE
    )

    # 清除输出标记 __L0001__ <<<
    value = re.sub(
        r'__L\d{4}__\s*<<<\s*',
        '',
        value,
        flags=re.IGNORECASE
    )

    return value.strip()


def validate_translation(raw_response: str, original_lyrics: str) -> Dict:
    """
    验证翻译质量

    返回:
    {
        'status': 'success' | 'auto_fixed' | 'error',
        'success_rate': 0.95,
        'issues': ['问题1', '问题2']
    }
    """
    try:
        from lyrics_translation_validator import LyricsTranslationValidator

        original_lines = original_lyrics.strip().split('\n')
        validator = LyricsTranslationValidator()
        result = validator.validate(raw_response, original_lines)

        return {
            'status': result.status.value,
            'success_rate': result.success_rate,
            'issues': [f"{issue.severity}: {issue.message}" for issue in result.issues]
        }
    except ImportError:
        # 简单验证
        cleaned = clean_translation(raw_response, original_lyrics)
        original_count = len([line for line in original_lyrics.split('\n') if line.strip()])
        translated_count = len(cleaned['line_translations'])

        success_rate = translated_count / original_count if original_count > 0 else 0

        if success_rate >= 0.9:
            status = 'success'
        elif success_rate >= 0.7:
            status = 'auto_fixed'
        else:
            status = 'error'

        return {
            'status': status,
            'success_rate': success_rate,
            'issues': [f"缺失 {len(cleaned['missing_lines'])} 行"] if cleaned['missing_lines'] else []
        }


# ============================================================================
# 模块 4: 批量处理和 CSV 生成
# ============================================================================

@dataclass
class TestCase:
    """测试用例"""
    index: int
    title: str
    artist: str
    language: str


def load_test_cases_from_csv(csv_file: str) -> List[TestCase]:
    """
    从 CSV 加载测试用例

    CSV 格式:
    title,artist,language
    Song Name,Artist Name,zh
    """
    test_cases = []

    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            test_cases.append(TestCase(
                index=i,
                title=row['title'].strip(),
                artist=row['artist'].strip(),
                language=row['language'].strip()
            ))

    return test_cases


def run_batch_test(
    input_csv: str,
    output_dir: str,
    gemini_api_key: str,
    target_language: str = "简体中文",
    styles: List[int] = [1, 2, 3],
    model: str = "gemini-2.0-flash-exp"
):
    """
    批量测试

    Args:
        input_csv: 输入 CSV 文件路径
        output_dir: 输出目录
        gemini_api_key: Gemini API Key
        target_language: 目标语言
        styles: 测试的风格列表 [1, 2, 3]
        model: Gemini 模型
    """
    # 创建输出目录
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    lyrics_dir = os.path.join(output_dir, 'lyrics')
    translations_dir = os.path.join(output_dir, 'translations')
    plaintext_dir = os.path.join(output_dir, 'plaintext')

    Path(lyrics_dir).mkdir(exist_ok=True)
    Path(translations_dir).mkdir(exist_ok=True)
    Path(plaintext_dir).mkdir(exist_ok=True)

    # 加载测试用例
    test_cases = load_test_cases_from_csv(input_csv)
    print(f"加载了 {len(test_cases)} 个测试用例\n")

    # 结果列表
    results = []

    # 处理每个测试用例
    for tc in test_cases:
        print(f"\n[{tc.index:02d}] {tc.title} - {tc.artist} ({tc.language})")
        print("-" * 80)

        # 1. 获取歌词
        lyrics, source = get_lyrics_with_priority(tc.title, tc.artist)

        if not lyrics:
            print("  ✗ 跳过（无歌词）")
            continue

        # 2. 保存原始歌词
        lyrics_file = save_lyrics_file(lyrics, tc.index, tc.title, tc.artist, tc.language, lyrics_dir)
        print(f"  ✓ 保存歌词: {os.path.basename(lyrics_file)}")

        # 3. 保存纯文本（用于 CometKiwi）
        plaintext_file = os.path.join(plaintext_dir, f"{tc.index:02d}_{tc.title}-{tc.artist}_original.txt")
        plaintext_file = "".join(c for c in plaintext_file if c.isalnum() or c in (' ', '-', '_', '.', '/')).strip()
        save_plaintext(lyrics, plaintext_file)

        # 4. 翻译（不同风格）
        for style in styles:
            style_name = {1: 'faithful', 2: 'melodramatic_poet', 3: 'machine_classic'}[style]

            print(f"\n  翻译 (Style {style}: {style_name})...")

            try:
                # 翻译
                raw_response, structured = translate_lyrics(
                    lyrics, target_language, style, gemini_api_key, model
                )

                # 清洗
                cleaned = clean_translation(raw_response, lyrics)

                # 验证
                validation = validate_translation(raw_response, lyrics)

                # 保存翻译文件
                trans_file = os.path.join(
                    translations_dir,
                    f"{tc.index:02d}_{tc.title}-{tc.artist}_style{style}.txt"
                )
                trans_file = "".join(c for c in trans_file if c.isalnum() or c in (' ', '-', '_', '.', '/')).strip()

                with open(trans_file, 'w', encoding='utf-8') as f:
                    f.write(cleaned['cleaned_text'])

                # 保存翻译纯文本（用于 CometKiwi）
                plaintext_trans_file = os.path.join(
                    plaintext_dir,
                    f"{tc.index:02d}_{tc.title}-{tc.artist}_style{style}_{target_language}.txt"
                )
                plaintext_trans_file = "".join(c for c in plaintext_trans_file if c.isalnum() or c in (' ', '-', '_', '.', '/')).strip()
                save_plaintext(cleaned['cleaned_text'], plaintext_trans_file)

                # 统计
                status_symbol = {'success': '✓', 'auto_fixed': '⚠', 'error': '✗'}[validation['status']]
                print(f"    {status_symbol} {validation['status'].upper()} ({validation['success_rate']*100:.1f}%)")

                # 记录结果
                results.append({
                    'index': tc.index,
                    'title': tc.title,
                    'artist': tc.artist,
                    'language': tc.language,
                    'lyrics_source': source,
                    'style': style,
                    'style_name': style_name,
                    'target_language': target_language,
                    'model': model,
                    'validation_status': validation['status'],
                    'success_rate': validation['success_rate'],
                    'translated_lines': len(cleaned['line_translations']),
                    'missing_lines': len(cleaned['missing_lines']),
                    'issues': '; '.join(validation['issues'])
                })

                # 避免 API 限流
                time.sleep(2)

            except Exception as e:
                print(f"    ✗ 失败: {e}")
                results.append({
                    'index': tc.index,
                    'title': tc.title,
                    'artist': tc.artist,
                    'language': tc.language,
                    'style': style,
                    'validation_status': 'error',
                    'success_rate': 0.0,
                    'issues': str(e)
                })

    # 5. 生成结果 CSV
    output_csv = os.path.join(output_dir, 'results.csv')
    save_results_csv(results, output_csv)

    print("\n" + "=" * 80)
    print("批量测试完成！")
    print("=" * 80)
    print(f"结果 CSV: {output_csv}")
    print(f"原始歌词: {lyrics_dir}")
    print(f"翻译结果: {translations_dir}")
    print(f"纯文本（CometKiwi）: {plaintext_dir}")


def save_results_csv(results: List[Dict], output_file: str):
    """保存结果为 CSV"""
    if not results:
        return

    fieldnames = [
        'index', 'title', 'artist', 'language', 'lyrics_source',
        'style', 'style_name', 'target_language', 'model',
        'validation_status', 'success_rate', 'translated_lines', 'missing_lines', 'issues'
    ]

    with open(output_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"\n✓ 结果已保存: {output_file}")


def save_plaintext(lyrics: str, output_file: str):
    """
    保存纯文本歌词（移除时间戳等元数据）
    用于 CometKiwi 等质量评估工具
    """
    import re

    lines = []
    # 移除 LRC 时间戳 [00:12.34]
    # 移除 [MISSING: ...] 标记

    for line in lyrics.split('\n'):
        # 移除时间戳
        clean_line = re.sub(r'\[\d{2}:\d{2}\.\d{2,3}\]', '', line)
        # 移除 MISSING 标记
        clean_line = re.sub(r'\[MISSING:.*?\]', '', clean_line)
        # 移除前后空格
        clean_line = clean_line.strip()

        if clean_line:
            lines.append(clean_line)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


# ============================================================================
# 命令行入口
# ============================================================================

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='歌词翻译批量测试')
    parser.add_argument('input_csv', help='输入 CSV 文件（包含 title, artist, language）')
    parser.add_argument('output_dir', help='输出目录')
    parser.add_argument('--api-key', help='Gemini API Key（或设置环境变量 GEMINI_API_KEY）')
    parser.add_argument('--target-lang', default='简体中文', help='目标语言（默认：简体中文）')
    parser.add_argument('--styles', default='1,2,3', help='测试风格，逗号分隔（默认：1,2,3）')
    parser.add_argument('--model', default='gemini-2.0-flash-exp', help='Gemini 模型')

    args = parser.parse_args()

    # 获取 API Key
    api_key = args.api_key or os.getenv('GEMINI_API_KEY')
    if not api_key:
        print("错误: 请提供 Gemini API Key（--api-key 或环境变量 GEMINI_API_KEY）")
        exit(1)

    # 解析风格
    styles = [int(s.strip()) for s in args.styles.split(',')]

    # 运行批量测试
    run_batch_test(
        input_csv=args.input_csv,
        output_dir=args.output_dir,
        gemini_api_key=api_key,
        target_language=args.target_lang,
        styles=styles,
        model=args.model
    )
