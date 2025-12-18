#!/usr/bin/env python3
"""
歌词翻译格式验证和处理器

用于验证 AI 翻译结果的格式，并尝试自动修复常见问题。

结果分类：
1. ERROR - 格式严重错误，无法自动修复
2. AUTO_FIXED - 格式有问题，但成功自动修复
3. SUCCESS - 格式正确或仅有少量可接受的缺失行
"""

import re
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, field
from enum import Enum


# ============================================================================
# 枚举和数据模型
# ============================================================================

class ValidationStatus(Enum):
    """验证状态"""
    ERROR = "error"              # 严重错误，无法修复
    AUTO_FIXED = "auto_fixed"    # 自动修复成功
    SUCCESS = "success"          # 完全成功


class ErrorType(Enum):
    """错误类型"""
    # 严重错误（无法修复）
    NO_TRANSLATION_MARKERS = "no_translation_markers"  # 没有翻译标记
    INVALID_FORMAT = "invalid_format"                  # 完全无效的格式
    EMPTY_RESPONSE = "empty_response"                  # 空响应
    TOO_MANY_MISSING = "too_many_missing"             # 缺失行数过多（>30%）

    # 可修复的问题
    WRONG_MARKER_DIRECTION = "wrong_marker_direction"  # 使用了 >>> 而非 <<<
    MISSING_LINE_NUMBERS = "missing_line_numbers"      # 缺少行号
    INCONSISTENT_SPACING = "inconsistent_spacing"      # 空格不一致
    EXTRA_CONTENT = "extra_content"                    # 有额外的说明文字
    LINE_COUNT_MISMATCH = "line_count_mismatch"       # 行数不匹配


@dataclass
class TranslationLine:
    """翻译行"""
    line_number: int           # 行号（从1开始）
    text: str                  # 翻译文本
    original_text: str = ""    # 原文（可选）
    confidence: float = 1.0    # 置信度（0-1）


@dataclass
class ValidationIssue:
    """验证问题"""
    error_type: ErrorType
    severity: str  # "critical", "warning", "info"
    message: str
    line_numbers: List[int] = field(default_factory=list)
    auto_fixable: bool = False


@dataclass
class ValidationResult:
    """验证结果"""
    status: ValidationStatus
    translation_lines: Dict[int, TranslationLine]  # 行号(0-based) -> 翻译行
    original_line_count: int
    translated_line_count: int
    missing_line_indices: List[int]  # 缺失的行索引（0-based）
    issues: List[ValidationIssue]
    raw_response: str
    cleaned_text: str = ""

    @property
    def success_rate(self) -> float:
        """翻译成功率"""
        if self.original_line_count == 0:
            return 0.0
        translated = len(self.translation_lines)
        return translated / self.original_line_count

    @property
    def is_acceptable(self) -> bool:
        """是否可接受（成功率 >= 70%）"""
        return self.success_rate >= 0.7


# ============================================================================
# 翻译格式验证器
# ============================================================================

class LyricsTranslationValidator:
    """歌词翻译格式验证器"""

    # 正则模式
    TRANSLATION_PATTERN = re.compile(
        r'__L(\d{4})__\s*<<<\s*(.*)$',
        re.MULTILINE
    )

    INPUT_PATTERN = re.compile(
        r'__L(\d{4})__\s*>>>\s*(.*)$',
        re.MULTILINE
    )

    # 常见错误模式
    WRONG_DIRECTION_PATTERN = re.compile(
        r'__L(\d{4})__\s*>>>\s*(.*)$',  # 使用了输入符号
        re.MULTILINE
    )

    NO_MARKER_PATTERN = re.compile(
        r'^(\d+)[\.\)]\s+(.+)$',  # 1. 翻译文本 或 1) 翻译文本
        re.MULTILINE
    )

    # 阈值配置
    MAX_MISSING_RATE = 0.3  # 最大允许缺失率 30%

    def __init__(self):
        self.issues: List[ValidationIssue] = []

    def validate(
        self,
        response_text: str,
        original_lines: List[str]
    ) -> ValidationResult:
        """
        验证翻译结果

        Args:
            response_text: AI 返回的翻译文本
            original_lines: 原始歌词行列表

        Returns:
            ValidationResult
        """
        self.issues = []

        # 过滤空行和仅空格的行
        non_empty_original = [
            (i, line) for i, line in enumerate(original_lines)
            if line.strip() and line.strip() != '[BLANK]'
        ]

        original_count = len(non_empty_original)

        # 1. 基本检查
        if not response_text or not response_text.strip():
            self.issues.append(ValidationIssue(
                error_type=ErrorType.EMPTY_RESPONSE,
                severity="critical",
                message="AI 返回了空响应",
                auto_fixable=False
            ))
            return self._create_error_result(
                response_text,
                original_count,
                "空响应"
            )

        # 2. 尝试标准格式解析
        translation_lines = self._parse_standard_format(response_text)

        if translation_lines:
            # 标准格式解析成功
            return self._validate_parsed_translations(
                translation_lines,
                non_empty_original,
                original_count,
                response_text
            )

        # 3. 尝试自动修复
        fixed_text, fix_applied = self._attempt_auto_fix(response_text)

        if fix_applied:
            translation_lines = self._parse_standard_format(fixed_text)
            if translation_lines:
                self.issues.append(ValidationIssue(
                    error_type=ErrorType.INVALID_FORMAT,
                    severity="warning",
                    message="格式错误，已自动修复",
                    auto_fixable=True
                ))

                result = self._validate_parsed_translations(
                    translation_lines,
                    non_empty_original,
                    original_count,
                    response_text
                )

                # 如果原本是 SUCCESS，改为 AUTO_FIXED
                if result.status == ValidationStatus.SUCCESS:
                    result.status = ValidationStatus.AUTO_FIXED

                return result

        # 4. 无法修复
        self.issues.append(ValidationIssue(
            error_type=ErrorType.NO_TRANSLATION_MARKERS,
            severity="critical",
            message="未找到有效的翻译标记，且无法自动修复",
            auto_fixable=False
        ))

        return self._create_error_result(
            response_text,
            original_count,
            "无效格式"
        )

    def _parse_standard_format(
        self,
        text: str
    ) -> Optional[Dict[int, TranslationLine]]:
        """
        解析标准格式

        格式: __L0001__ <<< 翻译文本

        Returns:
            Dict[行号(1-based), TranslationLine] 或 None
        """
        matches = self.TRANSLATION_PATTERN.findall(text)

        if not matches:
            return None

        translation_lines = {}

        for line_num_str, translation_text in matches:
            line_num = int(line_num_str)
            text_clean = translation_text.strip()

            # 跳过空翻译和 [BLANK] 标记
            if text_clean and text_clean != '[BLANK]':
                translation_lines[line_num] = TranslationLine(
                    line_number=line_num,
                    text=text_clean
                )

        return translation_lines if translation_lines else None

    def _attempt_auto_fix(self, text: str) -> Tuple[str, bool]:
        """
        尝试自动修复常见格式错误

        Returns:
            (修复后的文本, 是否应用了修复)
        """
        fixed_text = text
        fix_applied = False

        # 修复1: 将 >>> 替换为 <<<
        if '>>>' in fixed_text and '<<<' not in fixed_text:
            matches = self.WRONG_DIRECTION_PATTERN.findall(fixed_text)
            if matches:
                self.issues.append(ValidationIssue(
                    error_type=ErrorType.WRONG_MARKER_DIRECTION,
                    severity="warning",
                    message="使用了错误的方向标记 (>>>)，已自动修正为 (<<<)",
                    line_numbers=[int(m[0]) for m in matches],
                    auto_fixable=True
                ))
                fixed_text = fixed_text.replace('>>>', '<<<')
                fix_applied = True

        # 修复2: 尝试从简单编号格式转换
        # 例如: "1. 翻译文本" -> "__L0001__ <<< 翻译文本"
        if '__L' not in fixed_text:
            matches = self.NO_MARKER_PATTERN.findall(fixed_text)
            if matches and len(matches) > 3:  # 至少有3行才认为是有效的
                lines = fixed_text.split('\n')
                converted_lines = []

                for line in lines:
                    match = self.NO_MARKER_PATTERN.match(line.strip())
                    if match:
                        num, content = match.groups()
                        converted_lines.append(
                            f'__L{int(num):04d}__ <<< {content}'
                        )
                    else:
                        converted_lines.append(line)

                self.issues.append(ValidationIssue(
                    error_type=ErrorType.MISSING_LINE_NUMBERS,
                    severity="warning",
                    message="缺少标准行号标记，已尝试自动转换",
                    auto_fixable=True
                ))

                fixed_text = '\n'.join(converted_lines)
                fix_applied = True

        # 修复3: 移除常见的额外说明文字
        unwanted_phrases = [
            r'以下是翻译[：:]\s*',
            r'翻译如下[：:]\s*',
            r'Translation[：:]\s*',
            r'Here is the translation[：:]\s*',
            r'我已.*翻译.*\n',
        ]

        for phrase in unwanted_phrases:
            if re.search(phrase, fixed_text, re.IGNORECASE):
                fixed_text = re.sub(phrase, '', fixed_text, flags=re.IGNORECASE)
                fix_applied = True

                if not any(i.error_type == ErrorType.EXTRA_CONTENT for i in self.issues):
                    self.issues.append(ValidationIssue(
                        error_type=ErrorType.EXTRA_CONTENT,
                        severity="info",
                        message="移除了额外的说明文字",
                        auto_fixable=True
                    ))

        return fixed_text, fix_applied

    def _validate_parsed_translations(
        self,
        translation_lines: Dict[int, TranslationLine],
        non_empty_original: List[Tuple[int, str]],
        original_count: int,
        raw_response: str
    ) -> ValidationResult:
        """验证已解析的翻译"""

        # 创建索引映射
        original_indices = {i: (idx, line) for i, (idx, line) in enumerate(non_empty_original, 1)}

        # 找到缺失的翻译
        missing_indices = []
        matched_translations = {}

        for i, (original_idx, original_line) in enumerate(non_empty_original, 1):
            if i in translation_lines:
                # 翻译存在，存储时使用原始索引（0-based）
                matched_translations[original_idx] = translation_lines[i]
                matched_translations[original_idx].original_text = original_line
            else:
                # 翻译缺失
                missing_indices.append(original_idx)

        translated_count = len(matched_translations)
        missing_count = len(missing_indices)
        missing_rate = missing_count / original_count if original_count > 0 else 0

        # 检查缺失率
        if missing_rate > self.MAX_MISSING_RATE:
            self.issues.append(ValidationIssue(
                error_type=ErrorType.TOO_MANY_MISSING,
                severity="critical",
                message=f"缺失翻译过多: {missing_count}/{original_count} ({missing_rate*100:.1f}%)",
                line_numbers=missing_indices,
                auto_fixable=False
            ))

            return ValidationResult(
                status=ValidationStatus.ERROR,
                translation_lines=matched_translations,
                original_line_count=original_count,
                translated_line_count=translated_count,
                missing_line_indices=missing_indices,
                issues=self.issues.copy(),
                raw_response=raw_response,
                cleaned_text=self._build_cleaned_text(
                    matched_translations,
                    non_empty_original
                )
            )

        # 行数不匹配警告
        if translated_count != original_count:
            self.issues.append(ValidationIssue(
                error_type=ErrorType.LINE_COUNT_MISMATCH,
                severity="warning" if missing_rate < 0.1 else "warning",
                message=f"翻译行数不匹配: {translated_count}/{original_count}",
                line_numbers=missing_indices,
                auto_fixable=False
            ))

        # 构建清理后的文本
        cleaned_text = self._build_cleaned_text(matched_translations, non_empty_original)

        # 判断最终状态
        if missing_count == 0:
            status = ValidationStatus.SUCCESS
        elif missing_rate < 0.1:  # 缺失率 < 10%
            status = ValidationStatus.SUCCESS
        else:
            # 有缺失但可接受
            status = ValidationStatus.AUTO_FIXED if any(
                i.auto_fixable for i in self.issues
            ) else ValidationStatus.SUCCESS

        return ValidationResult(
            status=status,
            translation_lines=matched_translations,
            original_line_count=original_count,
            translated_line_count=translated_count,
            missing_line_indices=missing_indices,
            issues=self.issues.copy(),
            raw_response=raw_response,
            cleaned_text=cleaned_text
        )

    def _build_cleaned_text(
        self,
        translations: Dict[int, TranslationLine],
        non_empty_original: List[Tuple[int, str]]
    ) -> str:
        """构建清理后的翻译文本"""
        lines = []

        for i, (original_idx, original_line) in enumerate(non_empty_original):
            if original_idx in translations:
                lines.append(translations[original_idx].text)
            else:
                # 缺失的行，显示原文或标记
                lines.append(f"[MISSING: {original_line[:50]}...]" if len(original_line) > 50 else f"[MISSING: {original_line}]")

        return '\n'.join(lines)

    def _create_error_result(
        self,
        raw_response: str,
        original_count: int,
        reason: str
    ) -> ValidationResult:
        """创建错误结果"""
        return ValidationResult(
            status=ValidationStatus.ERROR,
            translation_lines={},
            original_line_count=original_count,
            translated_line_count=0,
            missing_line_indices=list(range(original_count)),
            issues=self.issues.copy(),
            raw_response=raw_response,
            cleaned_text=f"[ERROR: {reason}]"
        )


# ============================================================================
# 批量验证和统计
# ============================================================================

@dataclass
class BatchValidationStats:
    """批量验证统计"""
    total: int = 0
    success: int = 0
    auto_fixed: int = 0
    error: int = 0

    avg_success_rate: float = 0.0
    avg_missing_lines: float = 0.0

    common_issues: Dict[str, int] = field(default_factory=dict)

    def add_result(self, result: ValidationResult):
        """添加验证结果"""
        self.total += 1

        if result.status == ValidationStatus.SUCCESS:
            self.success += 1
        elif result.status == ValidationStatus.AUTO_FIXED:
            self.auto_fixed += 1
        else:
            self.error += 1

        # 统计常见问题
        for issue in result.issues:
            issue_name = issue.error_type.value
            self.common_issues[issue_name] = self.common_issues.get(issue_name, 0) + 1

    def calculate_averages(self, results: List[ValidationResult]):
        """计算平均值"""
        if not results:
            return

        self.avg_success_rate = sum(r.success_rate for r in results) / len(results)
        self.avg_missing_lines = sum(len(r.missing_line_indices) for r in results) / len(results)

    def print_summary(self):
        """打印统计摘要"""
        print("\n" + "="*80)
        print("批量验证统计")
        print("="*80)
        print(f"\n总计: {self.total}")
        print(f"✓ 成功: {self.success} ({self.success/self.total*100:.1f}%)")
        print(f"⚠ 自动修复: {self.auto_fixed} ({self.auto_fixed/self.total*100:.1f}%)")
        print(f"✗ 错误: {self.error} ({self.error/self.total*100:.1f}%)")

        print(f"\n平均成功率: {self.avg_success_rate*100:.1f}%")
        print(f"平均缺失行数: {self.avg_missing_lines:.1f}")

        if self.common_issues:
            print("\n常见问题:")
            sorted_issues = sorted(
                self.common_issues.items(),
                key=lambda x: x[1],
                reverse=True
            )
            for issue_name, count in sorted_issues:
                print(f"  - {issue_name}: {count} 次")


# ============================================================================
# 辅助函数
# ============================================================================

def validate_translation(
    response_text: str,
    original_lyrics: str
) -> ValidationResult:
    """
    验证单个翻译结果（便捷函数）

    Args:
        response_text: AI 返回的翻译文本
        original_lyrics: 原始歌词文本

    Returns:
        ValidationResult
    """
    original_lines = original_lyrics.strip().split('\n')
    validator = LyricsTranslationValidator()
    return validator.validate(response_text, original_lines)


def print_validation_result(result: ValidationResult, verbose: bool = False):
    """
    打印验证结果

    Args:
        result: ValidationResult
        verbose: 是否显示详细信息
    """
    status_symbols = {
        ValidationStatus.SUCCESS: "✓",
        ValidationStatus.AUTO_FIXED: "⚠",
        ValidationStatus.ERROR: "✗"
    }

    symbol = status_symbols[result.status]
    status_name = result.status.value.upper()

    print(f"\n{symbol} 验证状态: {status_name}")
    print(f"成功率: {result.success_rate*100:.1f}% ({result.translated_line_count}/{result.original_line_count})")

    if result.missing_line_indices:
        print(f"缺失行数: {len(result.missing_line_indices)}")
        if verbose:
            print(f"缺失行索引: {result.missing_line_indices[:10]}..." if len(result.missing_line_indices) > 10 else f"缺失行索引: {result.missing_line_indices}")

    if result.issues:
        print(f"\n问题列表 ({len(result.issues)}):")
        for i, issue in enumerate(result.issues, 1):
            severity_symbol = {
                "critical": "✗",
                "warning": "⚠",
                "info": "ℹ"
            }.get(issue.severity, "•")

            fixable = " [可自动修复]" if issue.auto_fixable else ""
            print(f"  {severity_symbol} {issue.message}{fixable}")

            if verbose and issue.line_numbers:
                line_preview = issue.line_numbers[:5]
                more = f"... (+{len(issue.line_numbers)-5} more)" if len(issue.line_numbers) > 5 else ""
                print(f"     受影响的行: {line_preview}{more}")

    if verbose and result.cleaned_text:
        print(f"\n清理后的文本预览（前5行）:")
        preview_lines = result.cleaned_text.split('\n')[:5]
        for i, line in enumerate(preview_lines, 1):
            print(f"  {i}. {line[:80]}..." if len(line) > 80 else f"  {i}. {line}")


# ============================================================================
# 命令行测试工具
# ============================================================================

if __name__ == '__main__':
    import sys
    import json

    def test_validation():
        """测试验证器"""

        print("歌词翻译格式验证器 - 测试")
        print("="*80)

        # 测试用例
        test_cases = [
            {
                'name': '完美格式',
                'original': 'Line 1\nLine 2\nLine 3',
                'response': '__L0001__ <<< 第一行\n__L0002__ <<< 第二行\n__L0003__ <<< 第三行',
                'expected': ValidationStatus.SUCCESS
            },
            {
                'name': '缺失一行',
                'original': 'Line 1\nLine 2\nLine 3',
                'response': '__L0001__ <<< 第一行\n__L0003__ <<< 第三行',
                'expected': ValidationStatus.SUCCESS  # <10% 缺失仍然是 SUCCESS
            },
            {
                'name': '错误的方向标记',
                'original': 'Line 1\nLine 2',
                'response': '__L0001__ >>> 第一行\n__L0002__ >>> 第二行',
                'expected': ValidationStatus.AUTO_FIXED
            },
            {
                'name': '简单编号格式',
                'original': 'Line 1\nLine 2\nLine 3',
                'response': '1. 第一行\n2. 第二行\n3. 第三行',
                'expected': ValidationStatus.AUTO_FIXED
            },
            {
                'name': '缺失过多',
                'original': 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5',
                'response': '__L0001__ <<< 第一行',
                'expected': ValidationStatus.ERROR
            },
            {
                'name': '空响应',
                'original': 'Line 1\nLine 2',
                'response': '',
                'expected': ValidationStatus.ERROR
            },
            {
                'name': '完全无效格式',
                'original': 'Line 1\nLine 2',
                'response': 'This is just random text without any structure',
                'expected': ValidationStatus.ERROR
            },
        ]

        stats = BatchValidationStats()

        for i, test_case in enumerate(test_cases, 1):
            print(f"\n[测试 {i}] {test_case['name']}")
            print("-" * 80)

            validator = LyricsTranslationValidator()
            result = validator.validate(
                test_case['response'],
                test_case['original'].split('\n')
            )

            stats.add_result(result)
            print_validation_result(result, verbose=True)

            # 验证预期结果
            if result.status == test_case['expected']:
                print(f"✓ 测试通过（预期状态: {test_case['expected'].value}）")
            else:
                print(f"✗ 测试失败（预期: {test_case['expected'].value}, 实际: {result.status.value}）")

        # 打印统计
        stats.calculate_averages([])
        stats.print_summary()

    def validate_file():
        """从文件验证"""
        if len(sys.argv) < 3:
            print("用法: python lyrics_translation_validator.py <original_lyrics.txt> <translation.txt>")
            return

        original_file = sys.argv[1]
        translation_file = sys.argv[2]

        try:
            with open(original_file, 'r', encoding='utf-8') as f:
                original_lyrics = f.read()

            with open(translation_file, 'r', encoding='utf-8') as f:
                translation_text = f.read()

            print(f"验证翻译文件...")
            print(f"原文: {original_file}")
            print(f"翻译: {translation_file}")

            result = validate_translation(translation_text, original_lyrics)
            print_validation_result(result, verbose=True)

            # 保存结果
            output_file = 'validation_result.json'
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump({
                    'status': result.status.value,
                    'success_rate': result.success_rate,
                    'translated_lines': result.translated_line_count,
                    'original_lines': result.original_line_count,
                    'missing_lines': result.missing_line_indices,
                    'issues': [
                        {
                            'type': issue.error_type.value,
                            'severity': issue.severity,
                            'message': issue.message,
                            'auto_fixable': issue.auto_fixable
                        }
                        for issue in result.issues
                    ],
                    'cleaned_text': result.cleaned_text
                }, f, ensure_ascii=False, indent=2)

            print(f"\n结果已保存到: {output_file}")

        except FileNotFoundError as e:
            print(f"错误: 文件不存在 - {e}")
        except Exception as e:
            print(f"错误: {e}")

    # 根据参数决定运行哪个测试
    if len(sys.argv) == 1:
        test_validation()
    else:
        validate_file()
