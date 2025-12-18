#!/usr/bin/env python3
"""
歌词翻译质量测试 - 使用示例

这个脚本演示了如何使用 test_lyrics_translation.py 进行批量测试
"""

from test_lyrics_translation import test_translation_quality
import os
import time


def batch_test_songs():
    """批量测试多首歌曲"""

    # 测试歌曲列表（Spotify Track ID）
    test_tracks = [
        {
            'id': '3n3Ppam7vgaVa1iaRUc9Lp',
            'name': 'Mr. Brightside - The Killers',
            'language': '简体中文'
        },
        {
            'id': '0VjIjW4GlUZAMYd2vXMi3b',
            'name': 'Blinding Lights - The Weeknd',
            'language': '简体中文'
        },
        {
            'id': '7qiZfU4dY1lWllzX7mPBI',
            'name': 'Shape of You - Ed Sheeran',
            'language': '日本語'
        },
    ]

    # 从环境变量读取配置
    spotify_client_id = os.getenv('SPOTIFY_CLIENT_ID')
    spotify_client_secret = os.getenv('SPOTIFY_CLIENT_SECRET')
    gemini_api_key = os.getenv('GEMINI_API_KEY')

    if not all([spotify_client_id, spotify_client_secret, gemini_api_key]):
        print("错误: 请设置环境变量 SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, GEMINI_API_KEY")
        return

    print("开始批量测试...")
    print(f"共 {len(test_tracks)} 首歌曲\n")

    results = []

    for i, track in enumerate(test_tracks, 1):
        print(f"\n{'='*80}")
        print(f"测试 {i}/{len(test_tracks)}: {track['name']}")
        print(f"{'='*80}")

        try:
            result = test_translation_quality(
                track_id=track['id'],
                target_language=track['language'],
                spotify_client_id=spotify_client_id,
                spotify_client_secret=spotify_client_secret,
                gemini_api_key=gemini_api_key
            )

            results.append({
                'track': track['name'],
                'success': True,
                'result': result
            })

            # 等待一段时间，避免 API 限流
            if i < len(test_tracks):
                print("\n等待 5 秒...")
                time.sleep(5)

        except Exception as e:
            print(f"✗ 测试失败: {e}")
            results.append({
                'track': track['name'],
                'success': False,
                'error': str(e)
            })

    # 打印总结
    print("\n" + "="*80)
    print("批量测试完成")
    print("="*80)

    success_count = sum(1 for r in results if r['success'])
    print(f"\n成功: {success_count}/{len(test_tracks)}")

    for result in results:
        status = "✓" if result['success'] else "✗"
        print(f"{status} {result['track']}")


def single_test_example():
    """单个歌曲测试示例"""

    # 示例: Taylor Swift - Anti-Hero
    track_id = '0V3wPSX9ygBnCm8psDIegu'

    try:
        result = test_translation_quality(
            track_id=track_id,
            target_language='简体中文'
        )

        print("\n测试成功!")
        print(f"歌名: {result['track_info']['name']}")
        print(f"翻译风格数量: {len(result['translations'])}")

    except Exception as e:
        print(f"测试失败: {e}")


if __name__ == '__main__':
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == '--batch':
        # 批量测试
        batch_test_songs()
    else:
        # 单个测试
        print("运行单个测试示例...")
        print("提示: 使用 --batch 参数进行批量测试\n")
        single_test_example()
