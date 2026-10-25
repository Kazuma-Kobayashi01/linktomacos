#!/usr/bin/env python3
"""列出 Mac App 里所有需要翻译的字符串（来自编译器导出的 .stringsdata），并找出代码里没被提取的中文字符串。

先编译一次（xcodebuild ... build），再运行：python3 tools/i18n/mac_keys.py
输出 JSON 到 stdout：{"keys": [...], "missing": [[位置, 字符串], ...]}
"""
import collections
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CJK = re.compile(r'[一-鿿]')


def extracted_keys():
    pattern = os.path.join(ROOT, 'macos/build/Intermediates.noindex/LinkToMacOS.build/Debug/LinkToMacOS.build/Objects-normal/arm64/*.stringsdata')
    keys = collections.OrderedDict()
    for path in sorted(glob.glob(pattern)):
        for table, items in json.load(open(path)).get('tables', {}).items():
            if table != 'Localizable':
                continue
            for item in items:
                keys[item['key']] = True
    return list(keys)


def code_literals():
    literals = collections.OrderedDict()
    for root, _, files in os.walk(os.path.join(ROOT, 'macos/LinkToMacOS')):
        for name in files:
            if not name.endswith('.swift'):
                continue
            for number, line in enumerate(open(os.path.join(root, name), encoding='utf-8'), 1):
                if line.strip().startswith('//'):
                    continue
                for match in re.finditer(r'"((?:[^"\\]|\\.)*)"', line):
                    if CJK.search(match.group(1)):
                        literals.setdefault(match.group(1), f'{name}:{number}')
    return literals


def normalize(text):
    text = re.sub(r'\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)', '%@', text)  # \(expr) → %@
    text = re.sub(r'%(?:lld|lf|ld|d|f)', '%@', text)
    return text.replace('%%', '%')


if __name__ == '__main__':
    keys = extracted_keys()
    normalized = {normalize(k) for k in keys}
    missing = [[where, text] for text, where in code_literals().items() if normalize(text) not in normalized]
    json.dump({'keys': [k for k in keys if CJK.search(k)], 'missing': missing}, sys.stdout, ensure_ascii=False, indent=1)
