#!/usr/bin/env python3
"""
歌词翻译质量测试脚本

功能：
1. 从 Spotify track ID 获取歌曲信息（歌名、歌手、专辑）和歌词（QQ音乐优先，其次网易云）
2. 使用 Gemini 2.5 Flash 进行三种不同风格的翻译测试
"""

import os
import json
import time
import requests
import base64
from typing import Optional, Dict, List, Tuple
from dataclasses import dataclass
from enum import Enum

# 导入验证器
try:
    from lyrics_translation_validator import (
        LyricsTranslationValidator,
        ValidationStatus,
        print_validation_result
    )
    VALIDATOR_AVAILABLE = True
except ImportError:
    VALIDATOR_AVAILABLE = False
    print("警告: 未找到 lyrics_translation_validator.py，将跳过格式验证")


# ============================================================================
# 数据模型
# ============================================================================

@dataclass
class TrackInfo:
    """歌曲信息"""
    track_id: str
    name: str
    artists: str
    album: str
    release_date: str
    lyrics: Optional[str] = None
    lyrics_source: Optional[str] = None


@dataclass
class TranslationResult:
    """翻译结果"""
    original_text: str
    translated_text: str
    cleaned_text: str
    line_translations: Dict[int, str]
    style: str
    language: str
    missing_lines: List[int]
    validation_status: Optional[str] = None  # 验证状态: success, auto_fixed, error
    validation_issues: List[str] = None  # 验证问题列表
    success_rate: float = 0.0  # 翻译成功率


class TranslationStyle(Enum):
    """翻译风格"""
    FAITHFUL = "faithful"
    MELODRAMATIC_POET = "melodramatic_poet"
    MACHINE_CLASSIC = "machine_classic"


# ============================================================================
# Spotify API 客户端
# ============================================================================

class SpotifyClient:
    """Spotify API 客户端"""

    def __init__(self, client_id: str, client_secret: str):
        self.client_id = client_id
        self.client_secret = client_secret
        self.access_token = None
        self.token_expires_at = 0

    def _get_access_token(self) -> str:
        """获取访问令牌"""
        if self.access_token and time.time() < self.token_expires_at:
            return self.access_token

        # 使用 Client Credentials Flow
        auth_str = f"{self.client_id}:{self.client_secret}"
        auth_b64 = base64.b64encode(auth_str.encode()).decode()

        response = requests.post(
            'https://accounts.spotify.com/api/token',
            headers={
                'Authorization': f'Basic {auth_b64}',
                'Content-Type': 'application/x-www-form-urlencoded'
            },
            data={'grant_type': 'client_credentials'}
        )
        response.raise_for_status()

        data = response.json()
        self.access_token = data['access_token']
        self.token_expires_at = time.time() + data['expires_in'] - 60

        return self.access_token

    def get_track_info(self, track_id: str) -> TrackInfo:
        """获取歌曲信息"""
        token = self._get_access_token()

        response = requests.get(
            f'https://api.spotify.com/v1/tracks/{track_id}',
            headers={'Authorization': f'Bearer {token}'}
        )
        response.raise_for_status()

        data = response.json()

        return TrackInfo(
            track_id=track_id,
            name=data['name'],
            artists=', '.join([artist['name'] for artist in data['artists']]),
            album=data['album']['name'],
            release_date=data['album']['release_date']
        )


# ============================================================================
# QQ 音乐歌词提供者
# ============================================================================

class QQMusicProvider:
    """QQ音乐歌词提供者"""

    BASE_URL = 'https://c.y.qq.com'
    BACKUP_URL = 'https://u6.y.qq.com'

    HEADERS = {
        'referer': 'https://y.qq.com/',
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
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
            print(f"QQ音乐搜索失败: {e}")

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
                # 解码歌词（处理编码问题）
                return cls._normalize_encoding(lyric)

        except Exception as e:
            print(f"QQ音乐获取歌词失败: {e}")
            # 尝试备用域名
            if not use_backup:
                return cls.get_lyrics(songmid, use_backup=True)

        return None

    @staticmethod
    def _normalize_encoding(text: str) -> str:
        """修复编码问题（mojibake）"""
        try:
            # 尝试修复 UTF-8/Latin1 混淆
            return text.encode('latin1').decode('utf-8')
        except (UnicodeDecodeError, UnicodeEncodeError):
            return text

    @classmethod
    def fetch_lyrics(cls, title: str, artist: str) -> Optional[str]:
        """搜索并获取歌词"""
        songmid = cls.search_song(title, artist)
        if songmid:
            return cls.get_lyrics(songmid)
        return None


# ============================================================================
# 网易云音乐歌词提供者
# ============================================================================

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
            print(f"网易云搜索失败: {e}")

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
                # 解析 LRC 格式，提取纯文本
                return cls._parse_lrc(lrc)

        except Exception as e:
            print(f"网易云获取歌词失败: {e}")

        return None

    @staticmethod
    def _parse_lrc(lrc_text: str) -> str:
        """解析 LRC 格式歌词"""
        import re

        lines = []
        # 匹配 LRC 时间标签 [mm:ss.xx]
        pattern = r'\[\d{2}:\d{2}\.\d{2,3}\](.+)'

        for line in lrc_text.strip().split('\n'):
            match = re.search(pattern, line)
            if match:
                text = match.group(1).strip()
                # 过滤元数据
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


# ============================================================================
# 歌词服务（优先级获取）
# ============================================================================

class LyricsService:
    """歌词服务"""

    @staticmethod
    def get_lyrics(title: str, artist: str) -> Tuple[Optional[str], Optional[str]]:
        """
        获取歌词（QQ音乐优先，其次网易云）

        返回: (歌词文本, 来源)
        """
        print(f"正在获取歌词: {title} - {artist}")

        # 1. 尝试 QQ 音乐
        print("  尝试 QQ 音乐...")
        lyrics = QQMusicProvider.fetch_lyrics(title, artist)
        if lyrics:
            print("  ✓ 从 QQ 音乐获取成功")
            return lyrics, "QQ Music"

        # 2. 尝试网易云音乐
        print("  尝试网易云音乐...")
        lyrics = NetEaseProvider.fetch_lyrics(title, artist)
        if lyrics:
            print("  ✓ 从网易云音乐获取成功")
            return lyrics, "NetEase Cloud Music"

        print("  ✗ 所有来源均未找到歌词")
        return None, None


# ============================================================================
# Gemini 翻译服务
# ============================================================================

class GeminiTranslator:
    """Gemini AI 翻译服务"""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = 'https://generativelanguage.googleapis.com/v1beta/models'

    def _build_structured_lyrics(self, lyrics: str) -> Tuple[str, List[str]]:
        """
        构建结构化歌词

        格式:
        __L0001__ >>> 第一行歌词
        __L0002__ >>> 第二行歌词
        __L0003__ >>> [BLANK]
        """
        lines = lyrics.strip().split('\n')
        structured_lines = []

        for i, line in enumerate(lines, 1):
            text = line.strip() if line.strip() else '[BLANK]'
            structured_lines.append(f'__L{i:04d}__ >>> {text}')

        return '\n'.join(structured_lines), lines

    def _parse_structured_translation(
        self,
        response_text: str,
        original_lines: List[str]
    ) -> TranslationResult:
        """
        解析结构化翻译响应

        预期格式:
        __L0001__ <<< 翻译的第一行
        __L0002__ <<< 翻译的第二行
        """
        import re

        line_translations = {}
        missing_lines = []

        # 匹配模式: __L0001__ <<< 翻译文本
        pattern = r'__L(\d{4})__\s*<<<\s*(.+)'

        for match in re.finditer(pattern, response_text, re.MULTILINE):
            line_num = int(match.group(1))
            translation = match.group(2).strip()

            if translation and translation != '[BLANK]':
                line_translations[line_num - 1] = translation

        # 检查缺失的行
        for i in range(len(original_lines)):
            if original_lines[i].strip() and i not in line_translations:
                missing_lines.append(i)

        # 构建清理后的翻译文本
        cleaned_lines = []
        for i, original in enumerate(original_lines):
            if i in line_translations:
                cleaned_lines.append(line_translations[i])
            elif original.strip():
                # 使用原文
                cleaned_lines.append(f"[MISSING: {original}]")
            else:
                cleaned_lines.append('')

        cleaned_text = '\n'.join(cleaned_lines)

        return TranslationResult(
            original_text='\n'.join(original_lines),
            translated_text=response_text,
            cleaned_text=cleaned_text,
            line_translations=line_translations,
            style='',  # 由调用方设置
            language='',  # 由调用方设置
            missing_lines=missing_lines
        )

    def _get_prompt_for_style(
        self,
        style: TranslationStyle,
        structured_lyrics: str,
        target_language: str
    ) -> str:
        """根据风格生成提示词"""

        if style == TranslationStyle.FAITHFUL:
            return f"""你是一位专业的歌词翻译专家。请将以下歌词翻译成{target_language}，保持忠实于原文的含义和情感。

翻译要求：
1. 准确传达原文的字面意思和深层含义
2. 保持原文的情感基调和氛围
3. 使用自然流畅的{target_language}表达
4. 保持每一行的对应关系

输入格式：
__L0001__ >>> 原文第一行
__L0002__ >>> 原文第二行
__L0003__ >>> [BLANK]

你的输出格式必须严格遵循：
__L0001__ <<< 翻译的第一行
__L0002__ <<< 翻译的第二行
__L0003__ <<<

歌词内容：
{structured_lyrics}

请开始翻译："""

        elif style == TranslationStyle.MELODRAMATIC_POET:
            return f"""你是一位充满激情的诗人和歌词翻译家。请将以下歌词翻译成{target_language}，用诗意和戏剧化的方式演绎。

翻译风格：
1. 使用富有诗意和文学性的表达
2. 强化情感的渲染和戏剧张力
3. 可以适当使用修辞手法（比喻、拟人等）
4. 营造更强烈的艺术氛围

输入格式：
__L0001__ >>> 原文第一行
__L0002__ >>> 原文第二行
__L0003__ >>> [BLANK]

你的输出格式必须严格遵循：
__L0001__ <<< 翻译的第一行
__L0002__ <<< 翻译的第二行
__L0003__ <<<

歌词内容：
{structured_lyrics}

请用你的诗意才华翻译："""

        elif style == TranslationStyle.MACHINE_CLASSIC:
            return f"""你是一位追求精准和经典的翻译机器。请将以下歌词翻译成{target_language}，采用直译风格。

翻译原则：
1. 逐字逐句直译，最大程度保留原文结构
2. 优先选择常见、经典的词汇
3. 保持译文的简洁和规范
4. 不添加额外的修饰或解释

输入格式：
__L0001__ >>> 原文第一行
__L0002__ >>> 原文第二行
__L0003__ >>> [BLANK]

你的输出格式必须严格遵循：
__L0001__ <<< 翻译的第一行
__L0002__ <<< 翻译的第二行
__L0003__ <<<

歌词内容：
{structured_lyrics}

请开始直译："""

        return ""

    def translate_lyrics(
        self,
        lyrics: str,
        target_language: str,
        style: TranslationStyle
    ) -> TranslationResult:
        """
        翻译歌词

        Args:
            lyrics: 歌词文本
            target_language: 目标语言（如 "简体中文", "English", "日本語"）
            style: 翻译风格

        Returns:
            TranslationResult
        """
        print(f"\n使用 Gemini 2.5 Flash 翻译（风格: {style.value}）...")

        # 1. 构建结构化歌词
        structured_lyrics, original_lines = self._build_structured_lyrics(lyrics)

        # 2. 生成提示词
        prompt = self._get_prompt_for_style(style, structured_lyrics, target_language)

        # 3. 调用 Gemini API
        url = f'{self.base_url}/gemini-2.0-flash-exp:generateContent'

        payload = {
            'contents': [{
                'parts': [{'text': prompt}]
            }],
            'generationConfig': {
                'temperature': 0.8,
            }
        }

        try:
            response = requests.post(
                f'{url}?key={self.api_key}',
                headers={'Content-Type': 'application/json'},
                json=payload,
                timeout=60
            )
            response.raise_for_status()

            data = response.json()

            # 提取响应文本
            response_text = data['candidates'][0]['content']['parts'][0]['text']

            # 4. 解析结构化响应
            result = self._parse_structured_translation(response_text, original_lines)
            result.style = style.value
            result.language = target_language

            # 5. 使用验证器验证格式（如果可用）
            if VALIDATOR_AVAILABLE:
                validator = LyricsTranslationValidator()
                validation_result = validator.validate(response_text, original_lines)

                result.validation_status = validation_result.status.value
                result.validation_issues = [
                    f"{issue.severity}: {issue.message}"
                    for issue in validation_result.issues
                ]
                result.success_rate = validation_result.success_rate

                # 使用验证器的统计（更准确）
                total_lines = validation_result.original_line_count
                translated_lines = validation_result.translated_line_count
                missing_count = len(validation_result.missing_line_indices)

                # 打印验证状态
                status_symbols = {
                    'success': '✓',
                    'auto_fixed': '⚠',
                    'error': '✗'
                }
                symbol = status_symbols.get(result.validation_status, '•')
                print(f"  {symbol} 验证状态: {result.validation_status.upper()}")
                print(f"  翻译完成：{translated_lines}/{total_lines} 行 ({result.success_rate*100:.1f}%)")

                if validation_result.issues:
                    print(f"  发现 {len(validation_result.issues)} 个问题:")
                    for issue in validation_result.issues[:3]:  # 只显示前3个
                        print(f"    - {issue.message}")
                    if len(validation_result.issues) > 3:
                        print(f"    ... 还有 {len(validation_result.issues)-3} 个问题")
            else:
                # 传统统计方式
                total_lines = len([line for line in original_lines if line.strip()])
                translated_lines = len(result.line_translations)
                missing_count = len(result.missing_lines)
                result.success_rate = translated_lines / total_lines if total_lines > 0 else 0

                print(f"  ✓ 翻译完成：{translated_lines}/{total_lines} 行")
                if missing_count > 0:
                    print(f"  ⚠ 缺失 {missing_count} 行翻译")

            return result

        except Exception as e:
            print(f"  ✗ 翻译失败: {e}")
            raise


# ============================================================================
# 主测试函数
# ============================================================================

def test_translation_quality(
    track_id: str,
    target_language: str = "简体中文",
    spotify_client_id: Optional[str] = None,
    spotify_client_secret: Optional[str] = None,
    gemini_api_key: Optional[str] = None
):
    """
    歌词翻译质量测试主函数

    Args:
        track_id: Spotify track ID
        target_language: 目标语言
        spotify_client_id: Spotify Client ID（可选，从环境变量读取）
        spotify_client_secret: Spotify Client Secret（可选，从环境变量读取）
        gemini_api_key: Gemini API Key（可选，从环境变量读取）
    """
    # 读取配置
    spotify_client_id = spotify_client_id or os.getenv('SPOTIFY_CLIENT_ID')
    spotify_client_secret = spotify_client_secret or os.getenv('SPOTIFY_CLIENT_SECRET')
    gemini_api_key = gemini_api_key or os.getenv('GEMINI_API_KEY')

    if not all([spotify_client_id, spotify_client_secret, gemini_api_key]):
        raise ValueError("请设置环境变量: SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, GEMINI_API_KEY")

    print("=" * 80)
    print("歌词翻译质量测试")
    print("=" * 80)

    # 1. 获取歌曲信息
    print("\n[1] 获取 Spotify 歌曲信息...")
    spotify = SpotifyClient(spotify_client_id, spotify_client_secret)
    track_info = spotify.get_track_info(track_id)

    print(f"  歌名: {track_info.name}")
    print(f"  歌手: {track_info.artists}")
    print(f"  专辑: {track_info.album}")
    print(f"  发行日期: {track_info.release_date}")

    # 2. 获取歌词
    print("\n[2] 获取歌词...")
    lyrics, source = LyricsService.get_lyrics(track_info.name, track_info.artists)

    if not lyrics:
        print("✗ 无法获取歌词，测试终止")
        return None

    track_info.lyrics = lyrics
    track_info.lyrics_source = source

    print(f"  来源: {source}")
    print(f"  歌词长度: {len(lyrics)} 字符")
    print(f"  歌词行数: {len(lyrics.strip().split(chr(10)))} 行")

    # 3. 三种风格翻译
    print(f"\n[3] 使用 Gemini 2.5 Flash 进行三种风格翻译（目标语言: {target_language}）...")

    translator = GeminiTranslator(gemini_api_key)
    results = {}

    styles = [
        TranslationStyle.FAITHFUL,
        TranslationStyle.MELODRAMATIC_POET,
        TranslationStyle.MACHINE_CLASSIC
    ]

    for style in styles:
        try:
            result = translator.translate_lyrics(lyrics, target_language, style)
            results[style.value] = result
            time.sleep(1)  # 避免 API 限流
        except Exception as e:
            print(f"✗ {style.value} 翻译失败: {e}")
            results[style.value] = None

    # 4. 保存结果
    print("\n[4] 保存测试结果...")

    output = {
        'track_info': {
            'track_id': track_info.track_id,
            'name': track_info.name,
            'artists': track_info.artists,
            'album': track_info.album,
            'release_date': track_info.release_date,
            'lyrics_source': track_info.lyrics_source
        },
        'original_lyrics': lyrics,
        'target_language': target_language,
        'translations': {}
    }

    for style_name, result in results.items():
        if result:
            translation_data = {
                'cleaned_text': result.cleaned_text,
                'raw_response': result.translated_text,
                'line_count': len(result.line_translations),
                'missing_lines': result.missing_lines,
                'line_translations': {
                    str(k): v for k, v in result.line_translations.items()
                }
            }

            # 添加验证信息（如果可用）
            if VALIDATOR_AVAILABLE and result.validation_status:
                translation_data['validation'] = {
                    'status': result.validation_status,
                    'success_rate': result.success_rate,
                    'issues': result.validation_issues or []
                }

            output['translations'][style_name] = translation_data

    # 保存为 JSON
    output_file = f'translation_test_{track_id}_{int(time.time())}.json'
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"  ✓ 结果已保存到: {output_file}")

    # 5. 打印预览
    print("\n" + "=" * 80)
    print("翻译结果预览")
    print("=" * 80)

    original_lines = lyrics.strip().split('\n')[:5]  # 前5行

    print("\n原文（前5行）:")
    for i, line in enumerate(original_lines, 1):
        print(f"  {i}. {line}")

    for style_name, result in results.items():
        if result:
            # 显示验证状态
            if VALIDATOR_AVAILABLE and result.validation_status:
                status_symbols = {
                    'success': '✓',
                    'auto_fixed': '⚠',
                    'error': '✗'
                }
                symbol = status_symbols.get(result.validation_status, '•')
                print(f"\n{style_name.upper()} 翻译 [{symbol} {result.validation_status.upper()}] (成功率: {result.success_rate*100:.1f}%):")
            else:
                print(f"\n{style_name.upper()} 翻译（前5行）:")

            # 显示前5行翻译
            for i in range(min(5, len(original_lines))):
                if i in result.line_translations:
                    print(f"  {i+1}. {result.line_translations[i]}")
                else:
                    print(f"  {i+1}. [缺失]")

    # 打印验证统计
    if VALIDATOR_AVAILABLE:
        print("\n" + "=" * 80)
        print("验证统计")
        print("=" * 80)

        validation_counts = {'success': 0, 'auto_fixed': 0, 'error': 0}
        for result in results.values():
            if result and result.validation_status:
                validation_counts[result.validation_status] = validation_counts.get(result.validation_status, 0) + 1

        print(f"✓ 成功: {validation_counts['success']}")
        print(f"⚠ 自动修复: {validation_counts['auto_fixed']}")
        print(f"✗ 错误: {validation_counts['error']}")

    print("\n" + "=" * 80)
    print("测试完成！")
    print("=" * 80)

    return output


# ============================================================================
# 命令行入口
# ============================================================================

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='歌词翻译质量测试')
    parser.add_argument('track_id', help='Spotify Track ID')
    parser.add_argument(
        '--language',
        default='简体中文',
        help='目标翻译语言（默认: 简体中文）'
    )
    parser.add_argument(
        '--spotify-client-id',
        help='Spotify Client ID（或设置环境变量 SPOTIFY_CLIENT_ID）'
    )
    parser.add_argument(
        '--spotify-client-secret',
        help='Spotify Client Secret（或设置环境变量 SPOTIFY_CLIENT_SECRET）'
    )
    parser.add_argument(
        '--gemini-api-key',
        help='Gemini API Key（或设置环境变量 GEMINI_API_KEY）'
    )

    args = parser.parse_args()

    try:
        test_translation_quality(
            track_id=args.track_id,
            target_language=args.language,
            spotify_client_id=args.spotify_client_id,
            spotify_client_secret=args.spotify_client_secret,
            gemini_api_key=args.gemini_api_key
        )
    except Exception as e:
        print(f"\n✗ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
